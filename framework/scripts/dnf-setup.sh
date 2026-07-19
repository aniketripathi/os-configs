#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Ensure script is run with sudo/root
require_root

SOURCE_DNF="$SYSTEM_CONFIGS/dnf/dnf.conf"
if [[ ! -f "$SOURCE_DNF" ]]; then
    SOURCE_DNF="$INIT_DIR/configs/dnf.conf.default"
fi

DEST_DNF="/etc/dnf/dnf.conf"
BACKUP_DIR="$LOCAL_BACKUP_DIR"
BACKUP_DNF="$BACKUP_DIR/dnf.conf.bak"

# --- Execution sequence ---
echo "=== OS Configuration & Core Upgrades ==="

# Copy configurations instead of symlinking to preserve native file ownership
echo "Optimizing DNF configuration..."
if [[ -f "$DEST_DNF" ]]; then
    echo "Creating backup of current configuration to $BACKUP_DNF..."
    mkdir -p "$BACKUP_DIR"
    cp "$DEST_DNF" "$BACKUP_DNF"
    chown -R "${OWNER}:${OWNER}" "$BACKUP_DIR" 2>/dev/null || true
fi

if [[ -f "$SOURCE_DNF" ]]; then
    echo "Copying optimized configuration to $DEST_DNF..."
    cp "$SOURCE_DNF" "$DEST_DNF"
    apply_default_permissions "$DEST_DNF" "true"
else
    echo "Warning: Optimized DNF template not found at $SOURCE_DNF."
fi

echo "Upgrading system packages..."
dnf -y upgrade

echo "Enabling RPM Fusion free and nonfree repositories..."
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

echo "Replacing default ffmpeg-free with full multimedia codecs..."
if rpm -q ffmpeg-free &>/dev/null; then
    dnf swap -y ffmpeg-free ffmpeg --allowerasing
else
    echo "ffmpeg-free is already removed/swapped. Ensuring ffmpeg is installed..."
    dnf install -y ffmpeg --allowerasing
fi

dnf group upgrade -y multimedia
dnf group upgrade -y core

if ! rpm -q terra-release &>/dev/null; then
    echo "Setting up Terra repository..."
    dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
else
    echo "Terra repository is already enabled."
fi

echo "Core Upgrades complete. Please proceed with GPU setup and enroll Secure Boot keys if necessary, then reboot."
