#!/bin/bash
# Automatically commit and push changes in the os-configs repository

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

cd "$OS_CONFIGS" || exit 1

# Check if there are any changes (including untracked files)
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Changes detected in repository. Committing changes..."
    git add -A
    git commit -m "[bot] Auto-update configurations: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Load local SSH agent keychain to authenticate Git push in background session
    # First search for hostname-specific file, fallback to wildcards
    if [[ -f "$HOME/.keychain/$(hostname)-sh" ]]; then
        source "$HOME/.keychain/$(hostname)-sh" >/dev/null 2>&1
    else
        # Try evaluating keychain output or sourcing existing environment
        source "$HOME/.keychain/"*-sh >/dev/null 2>&1 || true
    fi

    # Explicitly check push success
    if git push origin main; then
        echo "Push complete."
        notify-send "os-configs" "Configurations backed up and pushed successfully." -i dialog-information 2>/dev/null || true
    else
        echo "Error: Failed to push to remote repository."
        notify-send "os-configs" "Failed to push configurations to GitHub." -u critical -i dialog-error 2>/dev/null || true
        exit 1
    fi
else
    echo "No configuration changes detected."
fi
