#!/bin/bash
# 01-restore-configs.sh — Parse restore.conf and deploy home and system configurations

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

RESTORE_FILE="$CONFIGS_DIR/restore.conf"
BACKUP_DIR="/mnt/temp/reinstall_backup"

echo "=== Phase 3: Restoring Dotfiles and System Configurations ==="
echo "Restoring configurations from $RESTORE_FILE..."
echo "Backups of existing configs will be saved in $BACKUP_DIR/"

if [[ ! -f "$RESTORE_FILE" ]]; then
    echo "Error: restore.conf not found at $RESTORE_FILE"
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

    file="$line"

    if [[ "$current_section" == "home" ]]; then
        source_path="$HOME_CONFIGS/$file"
        dest="${HOME}/${file}"
        use_sudo=false
    elif [[ "$current_section" == "system" ]]; then
        source_path="$SYSTEM_CONFIGS/$file"
        dest="/etc/${file}"
        use_sudo=true
    else
        echo "Warning: File '$file' is not under a valid section ([home] or [system]). Skipping..."
        continue
    fi

    if [[ ! -e "$source_path" ]]; then
        echo "    (Info: Skipping restore for $file - no backup file in repository yet)"
        continue
    fi

    # Backup existing configuration
    if [[ -e "$dest" ]]; then
        echo "Backing up existing $dest to $BACKUP_DIR/..."
        mkdir -p "$BACKUP_DIR"
        if $use_sudo; then
            sudo cp -a "$dest" "$BACKUP_DIR/" 2>/dev/null || true
        else
            cp -a "$dest" "$BACKUP_DIR/" 2>/dev/null || true
        fi
    fi

    # Copy new configuration (No symlinks!)
    echo "Restoring $source_path -> $dest..."
    dest_dir="$(dirname "$dest")"
    if $use_sudo; then
        sudo mkdir -p "$dest_dir"
        sudo cp -a "$source_path" "$dest"
    else
        mkdir -p "$dest_dir"
        cp -a "$source_path" "$dest"
    fi

done < "$RESTORE_FILE"

# Apply Git Global configurations from keys/identity.env
if [[ -f "${IDENTITY_ENV:-}" ]]; then
    echo "Applying Git identity configs from $IDENTITY_ENV..."
    # Source it to ensure variables are present
    source "$IDENTITY_ENV"
    
    if [[ -n "${GIT_USER_NAME:-}" ]]; then
        echo "Configuring git global user.name: $GIT_USER_NAME"
        git config --global user.name "$GIT_USER_NAME"
    fi
    if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
        echo "Configuring git global user.email: $GIT_USER_EMAIL"
        git config --global user.email "$GIT_USER_EMAIL"
    fi
    if [[ -n "${GITHUB_USERNAME:-}" && "$GITHUB_USERNAME" != "your-github-username" ]]; then
        if ! git -C "$OS_CONFIGS" remote -v | grep -q "origin"; then
            remote_url="git@github.com:${GITHUB_USERNAME}/os-configs.git"
            echo "Configuring git remote 'origin' to: $remote_url"
            git -C "$OS_CONFIGS" remote add origin "$remote_url"
        fi
    fi
else
    echo "Warning: $IDENTITY_ENV not found. Skipping git identity customization."
fi

# Configure custom profile loading
echo "Configuring custom profile loading..."
CUSTOM_PROFILE="$CUSTOM_CONFIGS/.profile"
SOURCE_CMD="[ -f \"$CUSTOM_PROFILE\" ] && . \"$CUSTOM_PROFILE\""

for rc_file in "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.profile"; do
    is_relevant=false
    if [[ "$rc_file" =~ "bash" ]] && command -v bash >/dev/null 2>&1; then
        is_relevant=true
    elif [[ "$rc_file" =~ "zsh" ]] && command -v zsh >/dev/null 2>&1; then
        is_relevant=true
    elif [[ "$rc_file" == *".profile" ]]; then
        is_relevant=true
    fi
    
    if $is_relevant; then
        if [[ ! -f "$rc_file" ]]; then
            touch "$rc_file"
        fi
        
        if ! grep -qF "$CUSTOM_PROFILE" "$rc_file"; then
            echo "Appending custom profile sourcing to $rc_file"
            echo -e "\n# Load custom os-configs profile" >> "$rc_file"
            echo "$SOURCE_CMD" >> "$rc_file"
        else
            echo "Custom profile sourcing already configured in $rc_file"
        fi
    fi
done

echo "Configuration restoration complete."
