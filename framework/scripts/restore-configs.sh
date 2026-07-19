#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

RESTORE_FILE="$CONFIGS_DIR/restore.conf"
BACKUP_DIR="$LOCAL_BACKUP_DIR"

# --- Validation Checks ---
if [[ ! -f "$RESTORE_FILE" ]]; then
    echo "Error: Configuration file not found at $RESTORE_FILE" >&2
    exit 1
fi

restore_configs=false
restore_keys=false
FORCE=false
has_action_flag=false

for arg in "$@"; do
    case "$arg" in
        --configs)
            restore_configs=true
            has_action_flag=true
            ;;
        --keys)
            restore_keys=true
            has_action_flag=true
            ;;
        --all)
            restore_configs=true
            restore_keys=true
            has_action_flag=true
            ;;
        -f|--force)
            FORCE=true
            ;;
        *)
            echo "Unknown flag: $arg" >&2
            echo "Usage: $0 [--configs | --keys | --all] [-f | --force]" >&2
            exit 1
            ;;
    esac
done

if ! $has_action_flag; then
    restore_configs=true
    restore_keys=true
fi

# --- Helper function for generic restoration ---
# Args: section_name, repo_base, live_base, is_system (true|false)
restore_section() {
    local section="$1"
    local repo_base="$2"
    local live_base="$3"
    local is_system="$4"

    local files
    files=$(crudini --get "$RESTORE_FILE" "$section" || true)

    for file in $files; do
        [[ -z "$file" ]] && continue
        
        local source_path="${repo_base}/${file}"
        local dest="${live_base}/${file}"
        
        if [[ ! -e "$source_path" ]]; then
            if [[ "$section" == "keys" ]]; then
                echo "    (Info: Skipping restore for key $file - no backup file in local keys vault)"
            else
                echo "    (Info: Skipping restore for $file - no backup file in repository yet)"
            fi
            continue
        fi

        # Find all files recursively if the source is a directory (ignoring known_hosts.old)
        local src_files=()
        if [[ -d "$source_path" ]]; then
            while IFS= read -r -d $'\0' f; do
                src_files+=("$f")
            done < <(get_relative_files "$source_path")
        else
            src_files+=("")
        fi

        for sub_file in "${src_files[@]}"; do
            local file_src="$source_path"
            local file_dest="$dest"
            local rel_file="$file"

            if [[ -n "$sub_file" ]]; then
                local rel_path="${sub_file#./}"
                file_src="$source_path/$rel_path"
                file_dest="$dest/$rel_path"
                rel_file="$file/$rel_path"
            fi

            # Check for conflict if live destination exists and differs from repository source
            if [[ -e "$file_dest" ]]; then
                if ! cmp -s "$file_src" "$file_dest"; then
                    if [[ "$FORCE" == "true" ]]; then
                        local backup_file="$BACKUP_LIVE_DIR/$rel_file"
                        echo "Conflict detected! Backing up live copy of $rel_file to $backup_file..."
                        
                        if [[ "$is_system" == "true" ]]; then
                            sudo mkdir -p "$(dirname "$backup_file")"
                            sudo cp -a "$file_dest" "$backup_file"
                            sudo chown -R "${OWNER}:${OWNER}" "$backup_file" 2>/dev/null || true
                        else
                            run_as_owner mkdir -p "$(dirname "$backup_file")"
                            run_as_owner cp -a "$file_dest" "$backup_file"
                        fi
                    else
                        echo "Conflict: Live file $file_dest differs from repository $file_src. Skipping (use -f/--force to override)."
                        continue
                    fi
                fi
            fi

            # Perform restore and ensure user access permissions
            echo "Restoring $file_src -> $file_dest..."
            if [[ "$is_system" == "true" ]]; then
                sudo mkdir -p "$(dirname "$file_dest")"
                sudo cp -a "$file_src" "$file_dest"
                apply_default_permissions "$file_dest" "true"
            else
                run_as_owner mkdir -p "$(dirname "$file_dest")"
                run_as_owner cp -a "$file_src" "$file_dest"
                apply_default_permissions "$file_dest" "false"
            fi
        done

        # Apply specific security permissions if restoring keys
        if [[ "$section" == "keys" ]]; then
            if [[ "$file" == ".ssh" || "$file" == *"/_ssh" || "$file" == *"/.[Ss][Ss][Hh]" ]]; then
                run_as_owner chmod 700 "$dest"
                run_as_owner find "$dest" -type f -name "id_ed25519*" ! -name "*.pub" -exec chmod 600 {} + 2>/dev/null || true
                run_as_owner find "$dest" -type f -name "id_ed25519*.pub" -exec chmod 644 {} + 2>/dev/null || true
            elif [[ "$file" == *"/id_ed25519" ]]; then
                run_as_owner chmod 600 "$dest"
            elif [[ "$file" == *"/id_ed25519.pub" ]]; then
                run_as_owner chmod 644 "$dest"
            fi
        fi
    done
}

# --- Execution sequence ---
if $restore_configs; then
    echo "=== Restoring Dotfiles and System Configurations ==="
    echo "Restoring configurations from $RESTORE_FILE..."
    echo "Backups of conflicting live configs will be saved in $BACKUP_LIVE_DIR/"

    # Restore home dotfiles (user-level)
    restore_section "home" "$HOME_CONFIGS" "$USER_HOME" "false"

    # Configure custom profile loading
    echo "Configuring custom profile loading..."
    custom_profile="$CUSTOM_CONFIGS/.profile"
    source_cmd="[ -f \"$custom_profile\" ] && source \"$custom_profile\""

    # Helper to append custom profile sourcing to shell file if it doesn't have it
    append_profile_sourcing() {
        local target_file="$1"
        local is_relevant="$2"
        
        if [[ "$is_relevant" == "true" ]]; then
            if ! is_profile_sourced_in "$target_file"; then
                if [[ ! -f "$target_file" ]]; then
                    run_as_owner touch "$target_file"
                fi
                echo "Appending custom profile sourcing to $target_file"
                run_as_owner tee -a "$target_file" >/dev/null <<EOF

# Load custom profile
$source_cmd
EOF
            else
                echo "Custom profile sourcing already configured in $target_file"
            fi
        fi
    }

    bash_installed=false
    command -v bash >/dev/null 2>&1 && bash_installed=true
    
    zsh_installed=false
    command -v zsh >/dev/null 2>&1 && zsh_installed=true

    append_profile_sourcing "$USER_HOME/.bashrc" "$bash_installed"
    append_profile_sourcing "$USER_HOME/.bash_profile" "$bash_installed"
    append_profile_sourcing "$USER_HOME/.bash_login" "$bash_installed"
    append_profile_sourcing "$USER_HOME/.zshrc" "$zsh_installed"
    append_profile_sourcing "$USER_HOME/.zprofile" "$zsh_installed"
    append_profile_sourcing "$USER_HOME/.profile" "true"

    # Restore system configs (requires sudo/root)
    restore_section "system" "$SYSTEM_CONFIGS" "/etc" "true"
fi

if $restore_keys; then
    echo "=== Restoring Private Keys ==="
    echo "Backups of conflicting live keys will be saved in $BACKUP_LIVE_DIR/"

    restore_section "keys" "$KEYS_DIR" "$USER_HOME" "false"

    if [[ -n "${GIT_USER_NAME:-}" || -n "${GIT_USER_EMAIL:-}" ]]; then
        current_name=""
        current_email=""
        current_name=$(run_as_owner git config --global user.name || true)
        current_email=$(run_as_owner git config --global user.email || true)

        if [[ -n "${GIT_USER_NAME:-}" && "$current_name" != "$GIT_USER_NAME" ]]; then
            echo "Setting name = $GIT_USER_NAME in ~/.gitconfig"
            run_as_owner git config --global user.name "$GIT_USER_NAME"
        fi
        if [[ -n "${GIT_USER_EMAIL:-}" && "$current_email" != "$GIT_USER_EMAIL" ]]; then
            echo "Setting email = $GIT_USER_EMAIL in ~/.gitconfig"
            run_as_owner git config --global user.email "$GIT_USER_EMAIL"
        fi
    fi
    # Ensure ~/.ssh has correct secure permissions if it exists
    if [[ -d "$USER_HOME/.ssh" ]]; then
        run_as_owner chmod 700 "$USER_HOME/.ssh"
    fi
fi

echo "Configuration restoration complete."
