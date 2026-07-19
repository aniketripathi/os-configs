#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load layout configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/layout.env
source "${SCRIPT_DIR}/../../lib/layout.env"

# Copies source template file to target destination path if not exists
generate() {
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

# --- Execution sequence ---
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
        *)
            echo "Unknown flag: $arg" >&2
            exit 1
            ;;
    esac
done
