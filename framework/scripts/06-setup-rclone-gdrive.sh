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

# 5. Append fstab mount entry if not already present
FSTAB_LINE="${RCLONE_REMOTE}: $GDRIVE_DIR rclone rw,noauto,nofail,allow_other,_netdev,args2env,config=${RCLONE_CONF} 0 0"

echo "Checking /etc/fstab for Google Drive mount configuration..."
if ! grep -q "[[:space:]]${GDRIVE_DIR}[[:space:]]" /etc/fstab; then
    echo "Appending Google Drive rclone mount entry to /etc/fstab..."
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
    echo "fstab entry appended successfully."
else
    echo "Google Drive mount entry already exists in /etc/fstab. Updating config path if necessary..."
    # Update config path in place if it exists to match the current user home directory
    sudo sed -i "s|config=.*$GDRIVE_DIR|config=${RCLONE_CONF}|" /etc/fstab || true
fi

echo "Google Drive rclone fstab setup complete."
