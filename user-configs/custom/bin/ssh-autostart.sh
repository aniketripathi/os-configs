#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

KEY_PATH="$HOME/.ssh/id_ed25519"

# --- Execution sequence ---
# Ensure ssh-agent is running robustly to prevent orphaned agents
# ssh-add exit codes: 0 = active keys, 1 = running no keys, 2 = not running
ssh_add_status=0
ssh-add -l >/dev/null 2>&1 || ssh_add_status=$?

if [[ $ssh_add_status -eq 2 ]]; then
    echo "Starting ssh-agent..."
    eval "$(ssh-agent -s)"
fi

# Configure askpass options
export SSH_ASKPASS="/usr/bin/ksshaskpass"
export SSH_ASKPASS_REQUIRE="prefer"

# Load SSH key
if [[ -f "$KEY_PATH" ]]; then
    echo "Loading SSH key: $KEY_PATH"
    ssh-add "$KEY_PATH" < /dev/null >/dev/null 2>&1 || true
else
    echo "Warning: SSH key not found at $KEY_PATH"
fi
