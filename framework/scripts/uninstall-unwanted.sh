#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Ensure script is run with sudo/root
require_root

CONF="$PACKAGES_CONF"

# --- Validation Checks ---
if [[ ! -f "$CONF" ]]; then
    echo "Error: Packages config file not found at $CONF" >&2
    exit 1
fi

# --- Execution sequence ---
echo "=== Removing Unwanted Applications ==="
echo "Parsing unwanted packages list from configuration..."
uninstall_packages=$(crudini --get "$CONF" "uninstall" || true)

if [[ -z "$uninstall_packages" ]]; then
    echo "No packages listed under [uninstall] in configuration. Nothing to do."
    exit 0
fi

for pkg in $uninstall_packages; do
    [[ -z "$pkg" ]] && continue
    if rpm -q "$pkg" &>/dev/null; then
        echo "Removing unwanted package: $pkg..."
        dnf remove -y "$pkg"
    else
        echo "Package $pkg is not installed. Skipping."
    fi
done

echo "Unwanted package removal complete."
