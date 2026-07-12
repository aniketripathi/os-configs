#!/bin/bash
# Generate default configs for first-time setup based on flags
# Sourced reinstall.env variables are used for target locations

set -euo pipefail

# Make sure we can source reinstall.env from framework
source "$(dirname "$0")/../framework/configs/reinstall.env"

function generate() {
    local src="$INIT_DIR/configs/$1"
    local dest="$2"
    if [[ -f "$dest" ]]; then
        echo "Skipping $dest (already exists)"
    else
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
        echo "Generated $dest"
    fi
}

if [[ "${1:-}" == "--all" || -z "${1:-}" ]]; then
    generate "gitconfig.default" "$HOME_CONFIGS/.gitconfig"
    generate "ssh_config.default" "$HOME_CONFIGS/.ssh/config"
    generate "profile.default" "$CUSTOM_CONFIGS/.profile"
    generate "dnf.conf.default" "$SYSTEM_CONFIGS/dnf/dnf.conf"
    generate "snapper-root.default" "$SYSTEM_CONFIGS/snapper/configs/root"
    generate "powerdevil.default" "$HOME_CONFIGS/.config/powerdevilrc"
    generate "identity.env.default" "$KEYS_DIR/identity.env"
    exit 0
fi

for arg in "$@"; do
    case "$arg" in
        --git)      generate "gitconfig.default" "$HOME_CONFIGS/.gitconfig" ;;
        --ssh)      generate "ssh_config.default" "$HOME_CONFIGS/.ssh/config" ;;
        --profile)  generate "profile.default" "$CUSTOM_CONFIGS/.profile" ;;
        --dnf)      generate "dnf.conf.default" "$SYSTEM_CONFIGS/dnf/dnf.conf" ;;
        --snapper)  generate "snapper-root.default" "$SYSTEM_CONFIGS/snapper/configs/root" ;;
        --power)    generate "powerdevil.default" "$HOME_CONFIGS/.config/powerdevilrc" ;;
        --identity) generate "identity.env.default" "$KEYS_DIR/identity.env" ;;
        *)          echo "Unknown flag: $arg" ;;
    esac
done
