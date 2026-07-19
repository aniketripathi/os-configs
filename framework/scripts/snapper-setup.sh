#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Ensure script is run with sudo/root
require_root

# --- Validation Checks ---
# Check if root snapper configuration template is deployed or backed up
if [[ ! -f "/etc/snapper/configs/root" && ! -f "$SYSTEM_CONFIGS/snapper/configs/root" ]]; then
    echo "Error: Snapper root configuration file not found at /etc/snapper/configs/root or in repository." >&2
    echo "Please run restore-configs.sh or init-defaults.sh first to deploy the configuration." >&2
    exit 1
fi

# --- Execution sequence ---
echo "=== Snapper and BTRFS Setup ==="

# Copy the config from backup if missing from system
if [[ ! -f "/etc/snapper/configs/root" && -f "$SYSTEM_CONFIGS/snapper/configs/root" ]]; then
    echo "Deploying Snapper root configuration from repository backup..."
    mkdir -p /etc/snapper/configs
    cp "$SYSTEM_CONFIGS/snapper/configs/root" /etc/snapper/configs/root
fi

# Register root config in /etc/sysconfig/snapper
if [[ ! -f /etc/sysconfig/snapper ]]; then
    echo 'SNAPPER_CONFIGS="root"' > /etc/sysconfig/snapper
elif ! grep -q "^SNAPPER_CONFIGS=.*root" /etc/sysconfig/snapper; then
    if grep -q "^SNAPPER_CONFIGS=" /etc/sysconfig/snapper; then
        sed -i 's/^SNAPPER_CONFIGS="\(.*\)"/SNAPPER_CONFIGS="\1 root"/' /etc/sysconfig/snapper
    else
        echo 'SNAPPER_CONFIGS="root"' >> /etc/sysconfig/snapper
    fi
fi

# Ensure /.snapshots is a Btrfs subvolume (avoiding catastrophic rm -rf on non-empty dirs)
if [[ -d /.snapshots ]] && [[ "$(stat -c %i /.snapshots 2>/dev/null)" -ne 256 ]]; then
    echo "Converting /.snapshots plain directory into a Btrfs subvolume..."
    if [[ -n "$(ls -A /.snapshots 2>/dev/null)" ]]; then
        echo "Error: /.snapshots contains existing files. Manual intervention required to prevent data loss." >&2
        exit 1
    fi
    rmdir /.snapshots
    btrfs subvolume create /.snapshots
elif [[ ! -e /.snapshots ]]; then
    echo "Creating /.snapshots Btrfs subvolume..."
    btrfs subvolume create /.snapshots
fi

echo "Enabling snapper timers..."
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

# Setup grub-btrfs Copr repository
if ! rpm -q grub-btrfs &>/dev/null; then
    echo "Enabling grub-btrfs Copr repository..."
    dnf copr enable -y kylegospo/grub-btrfs
    echo "Installing grub-btrfs from Copr..."
    dnf install -y grub-btrfs
fi

# Configure grub-btrfs path monitor dependency override
echo "Enabling grub-btrfs path monitor..."
if systemctl cat grub-btrfs.path 2>/dev/null | grep -q 'snapshots.mount'; then
    echo "Detected snapshots.mount dependency bug in grub-btrfs.path. Masking with a corrected unit file..."
    rm -rf /etc/systemd/system/grub-btrfs.path.d
    
    cat > /etc/systemd/system/grub-btrfs.path <<'EOF'
[Unit]
Description=Monitors for new snapshots
DefaultDependencies=no
Requires=local-fs.target
After=local-fs.target

[Path]
PathModified=/.snapshots

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now grub-btrfs.path
else
    systemctl enable --now grub-btrfs.path
fi

# Helper to set options in /etc/default/grub
set_grub_option() {
    local key="$1"
    local value="$2"
    local file="/etc/default/grub"

    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# Unhide GRUB boot menu and configure timeouts
echo "Updating GRUB configuration defaults..."
grub2-editenv - unset menu_auto_hide 2>/dev/null || echo "Warning: grub env block not found. Skipping auto-hide unset."

set_grub_option "GRUB_TIMEOUT" "5"
set_grub_option "GRUB_TIMEOUT_STYLE" "menu"
# Note: 644 permissions for /etc/default/grub allows standard user backup utilities to read it
chmod 644 /etc/default/grub

# Regenerate GRUB configuration file
echo "Regenerating GRUB configuration file..."
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "Snapper, BTRFS, and GRUB setup complete. Snapshot menu should appear in GRUB boot menu after reboot."
