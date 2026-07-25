#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

RESTORE_FILE="$SYNC_MANIFEST"

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
        --configs) restore_configs=true; has_action_flag=true ;;
        --keys)    restore_keys=true;    has_action_flag=true ;;
        --all)     restore_configs=true; restore_keys=true; has_action_flag=true ;;
        -f|--force) FORCE=true ;;
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

# System section writes to /etc — requires root.
if $restore_configs && [[ $EUID -ne 0 ]]; then
    echo "Error: restoring system configurations requires sudo." >&2
    exit 1
fi

# Top-level: appends custom profile sourcing to a shell rc file if not already present.
append_profile_sourcing() {
    local target_file="$1"
    local is_relevant="$2"
    local custom_profile="$CUSTOM_CONFIGS/.profile"
    local source_cmd="[ -f \"$custom_profile\" ] && source \"$custom_profile\""
    if [[ "$is_relevant" == "true" ]]; then
        if ! is_profile_sourced_in "$target_file"; then
            [[ ! -f "$target_file" ]] && run_as_owner touch "$target_file"
            echo "Appending custom profile sourcing to $target_file"
            run_as_owner tee -a "$target_file" > /dev/null <<EOF

# Load custom profile
$source_cmd
EOF
        else
            echo "Custom profile sourcing already configured in $target_file"
        fi
    fi
}

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

        local clean_file="${file%/}"
        local source_path="${repo_base}/${clean_file}"
        local dest="${live_base}/${clean_file}"

        if [[ ! -e "$source_path" ]]; then
            if [[ "$section" == "keys" ]]; then
                echo "  (Info: Skipping restore for key $file - no backup in local keys vault)"
            else
                echo "  (Info: Skipping restore for $file - no backup in repository yet)"
            fi
            continue
        fi

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
            local rel_file="$clean_file"

            if [[ -n "$sub_file" ]]; then
                local rel_path="${sub_file#./}"
                file_src="$source_path/$rel_path"
                file_dest="$dest/$rel_path"
                rel_file="$clean_file/$rel_path"
            fi

            # Identical content: skip quietly
            if [[ -e "$file_dest" ]] && cmp -s "$file_src" "$file_dest"; then
                continue
            fi

            if is_conflict "$file_src" "$file_dest"; then
                if [[ "$FORCE" == "true" ]]; then
                    echo "  [Conflict] Overwriting (live newer) — backed up: $rel_file"
                    backup_file_to "$file_dest" "$BACKUP_LIVE_DIR/$rel_file" "$is_system"
                else
                    echo "  [Conflict] Skipping (live newer than repo): $rel_file  (use -f to overwrite)"
                    continue
                fi
            elif [[ -e "$file_dest" ]]; then
                echo "  [Backup] Overwriting (repo newer) — backed up old live copy: $rel_file"
                backup_file_to "$file_dest" "$BACKUP_LIVE_DIR/$rel_file" "$is_system"
            fi

            echo "  Restoring: $file_src -> $file_dest"
            if [[ "$is_system" == "true" ]]; then
                mkdir -p "$(dirname "$file_dest")"
                cp -a "$file_src" "$file_dest"
                apply_default_permissions "$file_dest" "true"
            else
                run_as_owner mkdir -p "$(dirname "$file_dest")"
                run_as_owner cp -a "$file_src" "$file_dest"
                apply_default_permissions "$file_dest" "false"
            fi
        done

        # SSH-specific permissions applied after all sub-files are restored.
        if [[ "$section" == "keys" ]]; then
            if [[ "$clean_file" == ".ssh" || "$clean_file" == *"/_ssh" || "$clean_file" == *"/.[Ss][Ss][Hh]" ]]; then
                run_as_owner chmod 700 "$dest"
                run_as_owner find "$dest" -type f -name "id_ed25519*" ! -name "*.pub" -exec chmod 600 {} + 2>/dev/null || true
                run_as_owner find "$dest" -type f -name "id_ed25519*.pub" -exec chmod 644 {} + 2>/dev/null || true
            elif [[ "$clean_file" == *"/id_ed25519" ]]; then
                run_as_owner chmod 600 "$dest"
            elif [[ "$clean_file" == *"/id_ed25519.pub" ]]; then
                run_as_owner chmod 644 "$dest"
            fi
        fi
    done
}

if $restore_configs; then
    echo "=== Restoring Dotfiles and System Configurations ==="
    echo "Restoring configurations from $RESTORE_FILE..."
    echo "Backups of overwritten live configs will be saved in $BACKUP_LIVE_DIR/"

    restore_section "home" "$HOME_CONFIGS" "$USER_HOME" "false"

    echo "Configuring custom profile loading..."
    bash_installed=false
    command -v bash > /dev/null 2>&1 && bash_installed=true
    zsh_installed=false
    command -v zsh  > /dev/null 2>&1 && zsh_installed=true

    append_profile_sourcing "$USER_HOME/.bashrc"       "$bash_installed"
    append_profile_sourcing "$USER_HOME/.bash_profile" "$bash_installed"
    append_profile_sourcing "$USER_HOME/.bash_login"   "$bash_installed"
    append_profile_sourcing "$USER_HOME/.zshrc"        "$zsh_installed"
    append_profile_sourcing "$USER_HOME/.zprofile"     "$zsh_installed"
    append_profile_sourcing "$USER_HOME/.profile"      "true"

    restore_section "system" "$SYSTEM_CONFIGS" "/etc" "true"
fi

if $restore_keys; then
    echo "=== Restoring Private Keys ==="
    echo "Backups of overwritten live keys will be saved in $BACKUP_LIVE_DIR/"

    restore_section "keys" "$KEYS_DIR" "$USER_HOME" "false"

    if [[ -n "${GIT_USER_NAME:-}" || -n "${GIT_USER_EMAIL:-}" ]]; then
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

    if [[ -d "$USER_HOME/.ssh" ]]; then
        run_as_owner chmod 700 "$USER_HOME/.ssh"
    fi
fi

echo "Configuration restoration complete."
