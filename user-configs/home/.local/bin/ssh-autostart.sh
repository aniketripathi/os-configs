#!/bin/bash
# ssh-autostart.sh — Automate SSH Agent and KWallet key loading on login
#
# Add this script to KDE Plasma System Settings -> Autostart to load keys silently at boot.

set -euo pipefail

# 1. Ensure ssh-agent is running and environment is set up
# Fedora KDE starts ssh-agent automatically, but we fall back if it is missing.
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo "Starting ssh-agent..."
    eval "$(ssh-agent -s)"
fi

# 2. Configure ksshaskpass as the translation bridge
export SSH_ASKPASS="/usr/bin/ksshaskpass"
export SSH_ASKPASS_REQUIRE="prefer"

# 3. Silently load the SSH key
# ksshaskpass will query KWallet in the background and load the key without prompting.
KEY_PATH="$HOME/.ssh/id_ed25519"
if [[ -f "$KEY_PATH" ]]; then
    echo "Loading SSH key: $KEY_PATH"
    ssh-add "$KEY_PATH" < /dev/null >/dev/null 2>&1 || true
else
    echo "Warning: SSH key not found at $KEY_PATH"
fi
