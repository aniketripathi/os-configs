#!/bin/bash
# 00-dnf-post-install.sh — DNF optimizations, RPM Fusion, Terra, and COPR setup
# Sourced reinstall.env variables are used for path configuration.

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

echo "=== Phase 2: OS Configuration & Core Upgrades ==="

SOURCE_DNF="$INIT_DIR/configs/dnf.conf.default"
DEST_DNF="/etc/dnf/dnf.conf"
BACKUP_DIR="/mnt/temp/reinstall_backup"
BACKUP_DNF="$BACKUP_DIR/dnf.conf.bak"

# 1. Back up existing DNF configuration and copy optimized one (No symlinks!)
echo "Optimizing DNF configuration..."
if [[ -f "$DEST_DNF" ]]; then
    echo "Creating backup of current dnf.conf to $BACKUP_DNF..."
    mkdir -p "$BACKUP_DIR"
    cp "$DEST_DNF" "$BACKUP_DNF"
fi

if [[ -f "$SOURCE_DNF" ]]; then
    echo "Copying optimized dnf.conf to $DEST_DNF..."
    sudo cp "$SOURCE_DNF" "$DEST_DNF"
else
    echo "Warning: Optimized DNF configuration template not found at $SOURCE_DNF."
fi

# 2. Upgrade system packages
echo "Upgrading system packages..."
sudo dnf -y upgrade

# 3. Add RPM Fusion repositories
echo "Enabling RPM Fusion free and nonfree repositories..."
sudo dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 4. Swap to RPM Fusion ffmpeg and upgrade multimedia codecs
echo "Replacing default ffmpeg-free with full multimedia codecs..."
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf group upgrade -y multimedia
sudo dnf group upgrade -y core

# 5. Enable Terra repository from Fyra Labs
if ! rpm -q terra-release &>/dev/null; then
    echo "Setting up Terra repository..."
    sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
else
    echo "Terra repository is already enabled."
fi

echo "Phase 2 Core Upgrades complete. Please proceed with GPU setup and enroll Secure Boot keys if necessary, then reboot."
