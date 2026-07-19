#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

CONF="$CONFIGS_DIR/packages.conf"

# --- Validation Checks ---
if [[ ! -f "$CONF" ]]; then
    echo "Error: Packages configuration file not found at $CONF" >&2
    exit 1
fi

install_required=false
install_daily=false
install_dev=false

if [[ $# -eq 0 ]]; then
    install_required=true
    install_daily=true
else
    for arg in "$@"; do
        case "$arg" in
            --all)
                install_required=true
                install_daily=true
                install_dev=true
                ;;
            --daily)
                install_required=true
                install_daily=true
                ;;
            --dev)
                install_required=true
                install_dev=true
                ;;
            --required)
                install_required=true
                ;;
            *)
                echo "Unknown flag: $arg" >&2
                echo "Usage: $0 [--required | --daily | --dev | --all]" >&2
                exit 1
                ;;
        esac
    done
fi

# Helper functions
install_section() {
    local section="$1"
    local manager="$2"

    local type_label="DNF"
    [[ "$manager" == "flatpak" ]] && type_label="Flatpak"

    echo "Installing $type_label packages from group: [$section]..."

    local packages
    packages=$(crudini --get "$CONF" "$section" || true)

    if [[ -z "$packages" ]]; then
        echo "No packages found in section [$section]."
        return
    fi

    for pkg in $packages; do
        [[ -z "$pkg" ]] && continue
        if [[ "$manager" == "dnf" ]]; then
            echo "Installing: $pkg..."
            sudo dnf install -y "$pkg"
        else
            echo "Installing Flatpak: $pkg..."
            flatpak install -y flathub "$pkg"
        fi
    done
}

# --- Execution sequence ---
echo "=== Application Setup ==="
echo "Installing packages declared in configuration..."

# Configure Flathub remote
if command -v flatpak >/dev/null 2>&1; then
    echo "Configuring Flathub remote for Flatpak..."
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
else
    echo "Warning: flatpak command not found. Skipping flatpak setup."
fi

# Set up VS Code repository if development section is requested
if $install_dev; then
    echo "Setting up Microsoft VS Code repository..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
fi

if $install_required; then
    install_section "required" "dnf"
fi

if $install_daily; then
    install_section "daily-driver" "dnf"
    install_section "daily-driver-flatpak" "flatpak"
fi

if $install_dev; then
    install_section "development" "dnf"
    install_section "development-flatpak" "flatpak"
fi

# Apply global filesystem overrides for current user
if command -v flatpak >/dev/null 2>&1; then
    echo "Applying global filesystem & device permissions to all user Flatpaks..."
    sudo -u "$OWNER" flatpak override --user --filesystem=host --socket=session-bus
fi

echo "Package installation and flatpak overriding complete."
