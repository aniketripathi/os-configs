#!/bin/bash
# 04-fedora-uninstall-bloat.sh — Parse [uninstall] from packages.conf and remove system bloatware

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

CONF="$CONFIGS_DIR/packages.conf"

echo "=== Phase 4: Removing System Bloatware ==="

if [[ ! -f "$CONF" ]]; then
    echo "Error: Packages config file not found at $CONF"
    exit 1
fi

echo "Parsing bloatware list from $CONF..."
UNINSTALL_PACKAGES=$(awk '/^\[uninstall\]/ {flag=1; next} /^\[/ {flag=0} flag && NF && !/^#/ {print $1}' "$CONF")

if [[ -z "$UNINSTALL_PACKAGES" ]]; then
    echo "No packages listed under [uninstall] in packages.conf. Nothing to do."
    exit 0
fi

for pkg in $UNINSTALL_PACKAGES; do
    # Check if package is installed before removing
    if rpm -q "$pkg" &>/dev/null; then
        echo "Removing bloatware package: $pkg..."
        sudo dnf remove -y "$pkg"
    else
        echo "Package $pkg is not installed. Skipping."
    fi
done

echo "Bloatware removal complete."
