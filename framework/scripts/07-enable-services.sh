#!/bin/bash
# 07-enable-services.sh — Copy systemd user service/timer units and enable weekly configuration sync

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

echo "=== Phase 4: Deploying and Enabling Automation Timers ==="

# 1. Ensure user-level systemd configuration directory exists
mkdir -p "$HOME/.config/systemd/user"

# 2. Copy services and timers to target directory (No symlinks!)
echo "Copying systemd user configuration files..."
if [[ -d "$AUTOMATION_DIR/systemd" ]]; then
    cp "$AUTOMATION_DIR"/systemd/os-configs-*.service "$HOME/.config/systemd/user/"
    cp "$AUTOMATION_DIR"/systemd/os-configs-*.timer "$HOME/.config/systemd/user/"
else
    echo "Error: systemd directory not found under $AUTOMATION_DIR."
    exit 1
fi

# 3. Reload systemd user daemon to recognize new units
echo "Reloading systemd user manager configuration..."
systemctl --user daemon-reload

# 4. Enable and start weekly sync timer
echo "Enabling and starting os-configs-sync.timer..."
systemctl --user enable --now os-configs-sync.timer

echo "Note: os-configs-gdrive.timer is NOT enabled by default."
echo "If you wish to enable weekly compressed Google Drive backups, run:"
echo "  systemctl --user enable --now os-configs-gdrive.timer"

echo "Systemd user services configuration complete."
