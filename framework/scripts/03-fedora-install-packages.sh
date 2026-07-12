#!/bin/bash
# 03-fedora-install-packages.sh — Install required, daily-driver and flatpak packages sequentially showing their purposes

set -euo pipefail
IFS=$'\n\t'

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo or as root."
   exit 1
fi

source "/mnt/core/os-configs/framework/configs/reinstall.env"

CONF="$CONFIGS_DIR/packages.conf"

echo "=== Phase 4: Application Setup ==="

INSTALL_REQUIRED=false
INSTALL_DAILY=false
INSTALL_DEV=false

if [[ $# -eq 0 ]]; then
    # Default behavior: install required and daily drivers (everything except dev)
    INSTALL_REQUIRED=true
    INSTALL_DAILY=true
else
    for arg in "${@:-}"; do
        case "$arg" in
            --all)
                INSTALL_REQUIRED=true
                INSTALL_DAILY=true
                INSTALL_DEV=true
                ;;
            --daily)
                INSTALL_REQUIRED=true
                INSTALL_DAILY=true
                ;;
            --dev)
                INSTALL_DEV=true
                ;;
            *)
                echo "Unknown flag: $arg"
                echo "Usage: $0 [--all | --daily | --dev]"
                exit 1
                ;;
        esac
    done
fi

echo "Installing packages declared in $CONF..."

if [[ ! -f "$CONF" ]]; then
    echo "Error: Packages configuration file not found at $CONF"
    exit 1
fi

# Ensure Flatpak is configured with Flathub
if command -v flatpak >/dev/null 2>&1; then
    echo "Configuring Flathub remote for Flatpak..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
else
    echo "Warning: flatpak command not found. Skipping flatpak setup."
fi

function install_dnf_section() {
    local section="$1"
    echo "Installing DNF packages from group: [$section]..."

    local packages_data
    packages_data=$(awk -v sec="$section" '
        $0 ~ "^\\["sec"\\]" {flag=1; next}
        /^\[/ {flag=0}
        flag && NF && !/^#/ {
            split($0, parts, "#")
            pkg = parts[1]
            gsub(/[ \t]+$/, "", pkg)
            gsub(/^[ \t]+/, "", pkg)
            purpose = ""
            if (length(parts) > 1) {
                purpose = parts[2]
                gsub(/^[ \t]+/, "", purpose)
                gsub(/[ \t]+$/, "", purpose)
            }
            if (pkg != "") {
                print pkg "::" purpose
            }
        }
    ' "$CONF")

    if [[ -z "$packages_data" ]]; then
        echo "No packages found in section [$section]."
        return
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local pkg="${line%%::*}"
        local purpose="${line##*::}"

        if [[ -n "$purpose" ]]; then
            echo "Installing: $pkg — ($purpose)..."
        else
            echo "Installing: $pkg..."
        fi

        dnf install -y "$pkg"
    done <<< "$packages_data"
}

function install_flatpak_section() {
    local section="$1"
    echo "Installing Flatpak packages from group: [$section]..."

    local packages_data
    packages_data=$(awk -v sec="$section" '
        $0 ~ "^\\["sec"\\]" {flag=1; next}
        /^\[/ {flag=0}
        flag && NF && !/^#/ {
            split($0, parts, "#")
            pkg = parts[1]
            gsub(/[ \t]+$/, "", pkg)
            gsub(/^[ \t]+/, "", pkg)
            purpose = ""
            if (length(parts) > 1) {
                purpose = parts[2]
                gsub(/^[ \t]+/, "", purpose)
                gsub(/[ \t]+$/, "", purpose)
            }
            if (pkg != "") {
                print pkg "::" purpose
            }
        }
    ' "$CONF")

    if [[ -z "$packages_data" ]]; then
        echo "No flatpaks found in section [$section]."
        return
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local pkg="${line%%::*}"
        local purpose="${line##*::}"

        if [[ -n "$purpose" ]]; then
            echo "Installing Flatpak: $pkg — ($purpose)..."
        else
            echo "Installing Flatpak: $pkg..."
        fi

        flatpak install -y flathub "$pkg"
        
        # Apply Flatpak normal app behavior override for each app specifically
        echo "Applying overrides to $pkg to behave like a normal app..."
        flatpak override --filesystem=host --device=all --socket=session-bus --socket=system-bus "$pkg"
    done <<< "$packages_data"
}

# Add Microsoft VS Code repository if development packages are selected
if $INSTALL_DEV; then
    echo "Setting up Microsoft VS Code repository..."
    rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
fi

# Run DNF and Flatpak installations based on active flags
if $INSTALL_REQUIRED; then
    install_dnf_section "required"
fi

if $INSTALL_DAILY; then
    install_dnf_section "daily-driver"
    install_flatpak_section "daily-driver-flatpak"
fi

if $INSTALL_DEV; then
    install_dnf_section "development"
    install_flatpak_section "development-flatpak"
fi

# Apply global system Flatpak permissions overrides
if command -v flatpak >/dev/null 2>&1; then
    echo "Applying global filesystem & device permissions to all system Flatpaks..."
    flatpak override --filesystem=host --device=all --socket=session-bus --socket=system-bus
fi

echo "Package installation and flatpak overriding complete."
