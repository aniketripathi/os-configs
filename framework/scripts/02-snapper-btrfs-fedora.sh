#!/bin/bash
# 02-snapper-btrfs-fedora.sh — Configure Snapper config, timeline limits, GRUB menu visibility

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

echo "=== Phase 3: Snapper and BTRFS Setup ==="

# 1. Initialize Snapper config for root if not already done
if [[ ! -f /etc/snapper/configs/root ]]; then
    echo "Creating snapper root config for /..."
    sudo snapper -c root create-config /
fi

# 2. Overwrite default config with snapper-root settings
if [[ -f "$SYSTEM_CONFIGS/snapper/configs/root" ]]; then
    echo "Deploying custom snapper root configuration..."
    sudo cp "$SYSTEM_CONFIGS/snapper/configs/root" /etc/snapper/configs/root
else
    echo "Warning: Custom snapper configuration not found at $SYSTEM_CONFIGS/snapper/configs/root"
fi

# 3. Enable Snapper timelines and cleanup timers
echo "Enabling snapper timers..."
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer

# 4. Ensure grub-btrfs is installed and enable grub-btrfsd service
if ! rpm -q grub-btrfs &>/dev/null; then
    echo "Enabling grub-btrfs Copr repository..."
    sudo dnf copr enable -y kylegospo/grub-btrfs
    echo "Installing grub-btrfs from Copr..."
    sudo dnf install -y grub-btrfs
fi

echo "Enabling grub-btrfs path monitor..."
if systemctl cat grub-btrfs.path 2>/dev/null | grep -q 'snapshots.mount'; then
    echo "Detected snapshots.mount dependency bug in grub-btrfs.path. Masking with a corrected unit file in /etc/systemd/system/..."
    # Ensure any legacy overrides are cleaned up
    sudo rm -rf /etc/systemd/system/grub-btrfs.path.d
    
    # Write the complete corrected unit file
    sudo sh -c 'cat <<EOF > /etc/systemd/system/grub-btrfs.path
[Unit]
Description=Monitors for new snapshots
DefaultDependencies=no
Requires=local-fs.target
After=local-fs.target

[Path]
PathModified=/.snapshots

[Install]
WantedBy=multi-user.target
EOF'
    sudo systemctl daemon-reload
    sudo systemctl enable --now grub-btrfs.path
else
    sudo systemctl enable --now grub-btrfs.path
fi

# 5. Configure GRUB menu visibility and timeouts
echo "Updating GRUB configuration defaults..."
sudo grub2-editenv - unset menu_auto_hide

if grep -q "^GRUB_TIMEOUT=" /etc/default/grub; then
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
else
    echo "GRUB_TIMEOUT=5" | sudo tee -a /etc/default/grub
fi

if grep -q "^GRUB_TIMEOUT_STYLE=" /etc/default/grub; then
    sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
else
    echo "GRUB_TIMEOUT_STYLE=menu" | sudo tee -a /etc/default/grub
fi

# 6. Regenerate GRUB config targeting /boot/grub2/grub.cfg (Rule 9: never target EFI stub)
echo "Regenerating GRUB configuration file..."
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

echo "Snapper, BTRFS, and GRUB setup complete. Snapshot menu should appear in GRUB boot menu after reboot."
