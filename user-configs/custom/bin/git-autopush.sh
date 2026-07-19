#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh"

# --- Execution sequence ---
cd "$OS_CONFIGS" || exit 1

# Check that 'origin' remote exists before pushing
git_cmd remote get-url origin >/dev/null 2>&1 || { echo "Error: git remote 'origin' not configured." >&2; exit 1; }

if [[ -n "$(git_cmd status --porcelain)" ]]; then
    echo "Changes detected in repository. Committing changes..."
    git_cmd add -A
    git_cmd commit -m "[bot] Auto-update configurations: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Push to remote repository
    if git_cmd push origin HEAD; then
        echo "Push complete."
        run_as_owner notify-send "os-configs" "Configurations backed up and pushed successfully." -i dialog-information 2>/dev/null || true
    else
        echo "Error: Failed to push to remote repository."
        run_as_owner notify-send "os-configs" "Failed to push configurations to GitHub." -u critical -i dialog-error 2>/dev/null || true
        exit 1
    fi
else
    echo "No configuration changes detected."
fi
