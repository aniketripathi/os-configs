#!/bin/bash
# Sync live configuration files back to the os-configs repository
# Reads restore.conf and copies system configurations back into user-configs/

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"
RESTORE_CONF="$CONFIGS_DIR/restore.conf"

echo "Starting configuration backup to $USER_CONFIGS..."

if [[ ! -f "$RESTORE_CONF" ]]; then
    echo "Error: $RESTORE_CONF not found."
    exit 1
fi

current_section=""

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^#.*$ ]] && continue

    # Check for section headers
    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        current_section="${BASH_REMATCH[1]}"
        continue
    fi

    # Remove potential trailing carriage returns or spaces
    file=$(echo "$line" | xargs)

    if [[ "$current_section" == "home" ]]; then
        live_path="${HOME}/${file}"
        repo_path="$HOME_CONFIGS/${file}"
    elif [[ "$current_section" == "system" ]]; then
        live_path="/etc/${file}"
        repo_path="$SYSTEM_CONFIGS/${file}"
    else
        echo "Warning: File '$file' is not under a valid section ([home] or [system]). Skipping..."
        continue
    fi

    if [[ -f "$live_path" ]]; then
        echo "Syncing file: $live_path -> $repo_path"
        mkdir -p "$(dirname "$repo_path")"
        rsync -a --checksum "$live_path" "$repo_path"
    elif [[ -d "$live_path" ]]; then
        echo "Syncing directory: $live_path -> $repo_path"
        mkdir -p "$repo_path"
        rsync -a --checksum --delete "$live_path/" "$repo_path/"
    else
        echo "Warning: path does not exist, skipping: $live_path"
    fi
done < "$RESTORE_CONF"

# Manually backup rclone.conf to keys/ (gitignored) to prevent exposing credentials
if [[ -f "${HOME}/.config/rclone/rclone.conf" ]]; then
    echo "Syncing rclone.conf to $KEYS_DIR/rclone.conf..."
    mkdir -p "$KEYS_DIR"
    rsync -a --checksum "${HOME}/.config/rclone/rclone.conf" "$KEYS_DIR/rclone.conf"
fi

# Manually backup private gitconfig to keys/ (gitignored)
if [[ -f "${HOME}/.gitconfig" ]]; then
    echo "Syncing private gitconfig to $KEYS_DIR/gitconfig..."
    mkdir -p "$KEYS_DIR"
    rsync -a --checksum "${HOME}/.gitconfig" "$KEYS_DIR/gitconfig"
fi

# Manually backup SSH keys to keys/ (gitignored)
if [[ -d "${HOME}/.ssh" ]]; then
    echo "Syncing SSH keys to $KEYS_DIR/ssh/..."
    mkdir -p "$KEYS_DIR/ssh"
    rsync -a --checksum "${HOME}/.ssh/id_ed25519"* "$KEYS_DIR/ssh/" || true
fi

echo "Backup complete."
