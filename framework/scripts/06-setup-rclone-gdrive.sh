#!/bin/bash
# 06-setup-rclone-gdrive.sh — Configure and append rclone Google Drive mount to /etc/fstab

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

echo "=== Phase 4: Setting up Google Drive Mount via Rclone ==="

# 1. Dynamically resolve the non-root user home directory
if [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

RCLONE_CONF="${USER_HOME}/.config/rclone/rclone.conf"

# Restore rclone.conf from keys/ (gitignored) if it exists in the repo
if [[ -f "$KEYS_DIR/rclone.conf" && ! -f "$RCLONE_CONF" ]]; then
    echo "Restoring rclone.conf from keys/rclone.conf..."
    mkdir -p "$(dirname "$RCLONE_CONF")"
    cp "$KEYS_DIR/rclone.conf" "$RCLONE_CONF"
fi

# 2. Check if rclone configuration exists
if [[ ! -f "$RCLONE_CONF" ]]; then
    echo "Error: Rclone configuration file not found at $RCLONE_CONF."
    echo "Please configure rclone first by running: rclone config"
    exit 1
fi

# 3. Test the connection to the remote
echo "Testing connection to rclone remote '$RCLONE_REMOTE'..."
if rclone --config "$RCLONE_CONF" lsd "$RCLONE_REMOTE:" >/dev/null 2>&1; then
    echo "Successfully connected to '$RCLONE_REMOTE:' remote."
else
    echo "Warning: Connection to '$RCLONE_REMOTE:' failed. Please verify credentials/network."
fi

# 4. Ensure the target mount directory exists
echo "Creating mount point directory: $GDRIVE_DIR..."
sudo mkdir -p "$GDRIVE_DIR"
if [[ -n "${SUDO_USER:-}" ]]; then
    sudo chown "$SUDO_USER":"$SUDO_USER" "$GDRIVE_DIR"
fi

# 5. Append or update fstab mount entry with high-performance VFS and directory caching options
# Performance optimization breakdown:
# - vfs_cache_mode=full: Enables full read/write caching locally (gives instant local-disk behavior)
# - vfs_cache_max_size=50G: Limits the cache folder footprint on disk
# - vfs_cache_max_age=72h: Extends cache lifetime for frequently accessed files
# - dir_cache_time=72h: Caches GDrive directory structure in memory (browsing directories becomes instant)
# - buffer_size=128M: Allocates per-file read buffers for faster sequential access
# - drive_chunk_size=64M: Optimizes upload chunk sizes for faster transfers
FSTAB_LINE="${RCLONE_REMOTE}: $GDRIVE_DIR rclone rw,noauto,nofail,allow_other,_netdev,args2env,config=${RCLONE_CONF},vfs_cache_mode=full,vfs_cache_max_size=50G,vfs_cache_max_age=72h,dir_cache_time=72h,buffer_size=128M,drive_chunk_size=64M 0 0"

echo "Configuring /etc/fstab for optimized Google Drive mount..."
if grep -q "[[:space:]]${GDRIVE_DIR}[[:space:]]" /etc/fstab; then
    echo "Updating existing Google Drive mount entry in /etc/fstab..."
    sudo sed -i "\|[[:space:]]${GDRIVE_DIR}[[:space:]]|d" /etc/fstab
fi

echo "Appending optimized Google Drive rclone mount entry to /etc/fstab..."
echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
echo "fstab entry configured successfully."

echo "Google Drive rclone fstab setup complete."
