#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh"

RESTORE_CONF="$CONFIGS_DIR/restore.conf"

# --- Argument Parsing ---
FORCE=false
for arg in "$@"; do
    case "$arg" in
        -f|--force)
            FORCE=true
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [-f | --force]" >&2
            exit 1
            ;;
    esac
done

# --- Validation Checks ---
if [[ ! -f "$RESTORE_CONF" ]]; then
    echo "Error: Configuration file not found at $RESTORE_CONF" >&2
    exit 1
fi

# Validate that the keys directory is ignored in git to prevent credential leak
if ! git -C "$OS_CONFIGS" check-ignore -q "$KEYS_DIR"; then
    echo "Error: Keys directory ($KEYS_DIR) is NOT ignored in .gitignore!" >&2
    echo "Backup aborted to prevent security leakage of private keys." >&2
    exit 1
fi

# --- Helper function for conflict checking and backup ---
# Args: section_name, live_base, repo_base, rel_repo_prefix
backup_section() {
    local section="$1"
    local live_base="$2"
    local repo_base="$3"
    local rel_repo_prefix="$4"

    local files
    files=$(crudini --get "$RESTORE_CONF" "$section" || true)

    for file in $files; do
        [[ -z "$file" ]] && continue
        local src="${live_base}/${file}"
        local dest="${repo_base}/${file}"
        local rel_repo="${rel_repo_prefix}/${file}"

        if [[ ! -e "$src" ]]; then
            if [[ "$section" == "keys" ]]; then
                echo "    (Info: Skipping key backup for $file - does not exist on live system)"
            else
                echo "Warning: path does not exist, skipping: $src"
            fi
            continue
        fi

        # Find all files recursively if the source is a directory (ignoring *.old and *.bak)
        local src_files=()
        if [[ -d "$src" ]]; then
            while IFS= read -r -d $'\0' f; do
                src_files+=("$f")
            done < <(get_relative_files "$src")
        else
            src_files+=("")
        fi

        for sub_file in "${src_files[@]}"; do
            local file_src="$src"
            local file_dest="$dest"
            local file_rel_repo="$rel_repo"

            if [[ -n "$sub_file" ]]; then
                local rel_path="${sub_file#./}"
                file_src="$src/$rel_path"
                file_dest="$dest/$rel_path"
                file_rel_repo="$rel_repo/$rel_path"
            fi

            # Check for conflict if repository copy exists and differs from live
            if [[ -e "$file_dest" ]]; then
                if ! cmp -s "$file_src" "$file_dest"; then
                    if [[ "$FORCE" == "true" ]]; then
                        local backup_file="$BACKUP_REPO_DIR/$file_rel_repo"
                        echo "Conflict detected! Backing up repository copy to $backup_file..."
                        run_as_owner mkdir -p "$(dirname "$backup_file")"
                        run_as_owner cp -a "$file_dest" "$backup_file"
                    else
                        echo "Conflict: Repository $file_dest differs from live $file_src. Skipping (use -f/--force to override)."
                        continue
                    fi
                fi
            fi

            # Sync file to repository destination
            echo "Syncing file: $file_src -> $file_dest"
            if [[ "$section" == "system" ]]; then
                # Root reads system config, writes to repo, and immediately corrects ownership
                mkdir -p "$(dirname "$file_dest")"
                cp -a "$file_src" "$file_dest"
                chown "${OWNER}:${OWNER}" "$file_dest"
                chown "${OWNER}:${OWNER}" "$(dirname "$file_dest")" 2>/dev/null || true
            else
                # Non-system configs are written entirely as standard user
                run_as_owner mkdir -p "$(dirname "$file_dest")"
                run_as_owner cp -a "$file_src" "$file_dest"
            fi
        done
    done
}

# Removes paths from the repository that are no longer listed in restore.conf
prune_section() {
    local section="$1"
    local repo_base="$2"

    if [[ ! -d "$repo_base" ]]; then
        return 0
    fi

    echo "Pruning unreferenced configurations in repository section [$section]..."

    # Build the allowed paths map (O(1) lookups)
    declare -A allowed_map
    build_allowed_map "$section" allowed_map

    # Walk all files and directories under repo_base
    local repo_items=()
    while IFS= read -r -d $'\0' item; do
        repo_items+=("${item#./}")
    done < <(get_relative_items "$repo_base")

    # Process items top-down
    for item in "${repo_items[@]}"; do
        local full_path="$repo_base/$item"

        # Verify the item still exists (might have been deleted as a child of a previously pruned directory)
        [[ ! -e "$full_path" ]] && continue

        # Special exclusion: keys/identity.env must never be deleted
        if [[ "$section" == "keys" && "$item" == "identity.env" ]]; then
            continue
        fi

        if ! is_path_covered "$item" allowed_map; then
            local section_prefix="user-configs/home"
            [[ "$section" == "system" ]] && section_prefix="user-configs/system"
            [[ "$section" == "keys" ]] && section_prefix="keys"

            local backup_dest="$BACKUP_REPO_DIR/$section_prefix/$item"
            echo "  Backup/Pruned: backing up repository $item -> $backup_dest"
            run_as_owner mkdir -p "$(dirname "$backup_dest")"
            run_as_owner cp -a "$full_path" "$backup_dest"

            echo "  Removing unallowed repository path: $item"
            rm -rf "$full_path"
        fi
    done
}

# --- Execution sequence ---
echo "Starting configuration backup..."

backup_section "home" "$USER_HOME" "$HOME_CONFIGS" "user-configs/home"
prune_section "home" "$HOME_CONFIGS"

backup_section "system" "/etc" "$SYSTEM_CONFIGS" "user-configs/system"
prune_section "system" "$SYSTEM_CONFIGS"

backup_section "keys" "$USER_HOME" "$KEYS_DIR" "keys"
prune_section "keys" "$KEYS_DIR"

# Re-ensure standard user ownership on entire repository
if [[ -n "${OWNER:-}" && "$OWNER" != "root" ]]; then
    echo "Correcting repository file ownership to $OWNER..."
    chown -R "$OWNER:$OWNER" "$OS_CONFIGS"
fi

echo "Backup complete."
