#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Ensure script is run with sudo/root
require_root

# --- User Customizable Mount Settings ---
# RCLONE_REMOTE is loaded from layout.env
RCLONE_MOUNT_OPTIONS="rw,nofail,allow_other,allow_non_empty,_netdev,args2env,vfs_cache_mode=full,vfs_cache_max_size=15G,vfs_cache_max_age=8760h,dir_cache_time=8760h,buffer_size=128M,drive_chunk_size=64M,vfs_read_chunk_size=32M,vfs_read_chunk_size_limit=off"
RCLONE_CONF="${USER_HOME}/.config/rclone/rclone.conf"

# Format fstab entry
FSTAB_LINE="${RCLONE_REMOTE}: $GDRIVE_DIR rclone ${RCLONE_MOUNT_OPTIONS},config=${RCLONE_CONF} 0 0"

# --- Execution sequence ---
echo "=== Setting up Google Drive Mount via Rclone ==="

# --- Validation Checks ---
config_restored=false
if [[ -f "$KEYS_DIR/.config/rclone/rclone.conf" && ! -f "$RCLONE_CONF" ]]; then
    echo "Restoring rclone.conf from keys/.config/rclone/rclone.conf..."
    sudo -u "$OWNER" mkdir -p "$(dirname "$RCLONE_CONF")"
    sudo -u "$OWNER" cp "$KEYS_DIR/.config/rclone/rclone.conf" "$RCLONE_CONF"
    config_restored=true
fi

if [[ ! -f "$RCLONE_CONF" ]]; then
    echo "Error: Rclone configuration file not found at $RCLONE_CONF." >&2
    echo "First-time setup: Please run 'rclone config' as your normal user first." >&2
    exit 1
fi

# 1. Enable user_allow_other in /etc/fuse.conf to resolve Dolphin's red/broken mount icon
if [[ -f /etc/fuse.conf ]]; then
    echo "Enabling user_allow_other in /etc/fuse.conf..."
    sed -i 's/#\s*user_allow_other/user_allow_other/' /etc/fuse.conf
fi

# 2. Ensure target mount directory exists with correct ownership
echo "Creating mount point directory: $GDRIVE_DIR..."
mkdir -p "$GDRIVE_DIR"
chown "$OWNER":"$OWNER" "$GDRIVE_DIR"

# 3. Validate remote connection
echo "Testing connection to rclone remote '$RCLONE_REMOTE'..."
if sudo -u "$OWNER" rclone --config "$RCLONE_CONF" lsd "$RCLONE_REMOTE:" >/dev/null 2>&1; then
    echo "Successfully connected to '$RCLONE_REMOTE:' remote."
    
    # 4. Perform initial bisync if config was restored
    if $config_restored; then
        echo "Performing initial Google Drive bisync to local directory $GDRIVE_DIR..."
        echo "Testing bisync via dry-run..."
        if sudo -u "$OWNER" rclone --config "$RCLONE_CONF" bisync "${RCLONE_REMOTE}:" "$GDRIVE_DIR" --resync --resync-mode path1 --dry-run -P; then
            echo "Dry-run successful. Running actual bisync..."
            sudo -u "$OWNER" rclone --config "$RCLONE_CONF" bisync "${RCLONE_REMOTE}:" "$GDRIVE_DIR" --resync --resync-mode path1 -P
        else
            echo "Warning: Bisync dry-run failed. Skipping actual bisync."
        fi
    fi
else
    echo "Warning: Connection to '$RCLONE_REMOTE:' failed. Please verify credentials/network."
fi

# 5. Reconcile mount entry in fstab
echo "Configuring /etc/fstab for optimized Google Drive mount..."
if grep -q "[[:space:]]${GDRIVE_DIR}[[:space:]]" /etc/fstab; then
    echo "Updating existing Google Drive mount entry in /etc/fstab..."
    sed -i "\|[[:space:]]${GDRIVE_DIR}[[:space:]]|d" /etc/fstab
fi

echo "Appending optimized Google Drive rclone mount entry to /etc/fstab..."
echo "$FSTAB_LINE" >> /etc/fstab

# Reload systemd to recognize fstab changes
systemctl daemon-reload

echo "Google Drive rclone fstab setup complete."
echo ""
echo "=== Configured Rclone Settings ==="
echo "RCLONE_REMOTE: $RCLONE_REMOTE"
echo "GDRIVE_DIR: $GDRIVE_DIR"
echo "RCLONE_CONF: $RCLONE_CONF"
echo "RCLONE_MOUNT_OPTIONS: $RCLONE_MOUNT_OPTIONS"
