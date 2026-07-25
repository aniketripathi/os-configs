#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh"

RESTORE_CONF="$SYNC_MANIFEST"

FORCE=false
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=true ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [-f | --force]" >&2
            exit 1
            ;;
    esac
done

if [[ ! -f "$RESTORE_CONF" ]]; then
    echo "Error: Configuration file not found at $RESTORE_CONF" >&2
    exit 1
fi

# --- Check requirements ---
# If we cannot read the required system configurations, we must run as root/sudo.
check_requirements() {
    [[ $EUID -eq 0 ]] && return 0 # root can read anything

    local files
    files=$(crudini --get "$RESTORE_CONF" "system" || true)
    for file in $files; do
        [[ -z "$file" ]] && continue
        local src="/etc/${file}"
        # If the file/dir exists but we don't have read permission, we need root.
        if [[ -e "$src" && ! -r "$src" ]]; then
            echo "Error: Cannot read system configuration: $src" >&2
            echo "This script must be run with sudo or as root to access all system configuration files." >&2
            exit 1
        fi
    done
}

check_requirements

# Use relative path so git check-ignore works regardless of where the repo is mounted.
if ! git -C "$OS_CONFIGS" check-ignore -q "keys"; then
    echo "Error: keys/ is NOT ignored in .gitignore!" >&2
    echo "Backup aborted to prevent security leakage of private keys." >&2
    exit 1
fi

# Args: section_name, live_base, repo_base, rel_repo_prefix
backup_section() {
    local section="$1"
    local live_base="$2"
    local repo_base="$3"
    local rel_repo_prefix="$4"
    local is_system=false
    [[ "$section" == "system" ]] && is_system=true

    local files
    files=$(crudini --get "$RESTORE_CONF" "$section" || true)

    for file in $files; do
        [[ -z "$file" ]] && continue
        local src="${live_base}/${file}"
        local dest="${repo_base}/${file}"
        local rel_repo="${rel_repo_prefix}/${file}"

        if [[ ! -e "$src" ]]; then
            if [[ "$section" == "keys" ]]; then
                echo "  (Info: Skipping key backup for $file - does not exist on live system)"
            else
                echo "  Warning: path does not exist, skipping: $src"
            fi
            continue
        fi

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

            # Identical content: skip quietly
            if [[ -e "$file_dest" ]] && cmp -s "$file_src" "$file_dest"; then
                continue
            fi

            if is_conflict "$file_src" "$file_dest"; then
                if [[ "$FORCE" == "true" ]]; then
                    echo "  [Conflict] Overwriting (repo newer) — backed up: $file_rel_repo"
                    backup_file_to "$file_dest" "$BACKUP_REPO_DIR/$file_rel_repo" "$is_system"
                else
                    echo "  [Conflict] Skipping (repo newer than live): $file_rel_repo  (use -f to overwrite)"
                    continue
                fi
            elif [[ -e "$file_dest" ]]; then
                echo "  [Backup] Overwriting (live newer) — backed up old repo copy: $file_rel_repo"
                backup_file_to "$file_dest" "$BACKUP_REPO_DIR/$file_rel_repo" "$is_system"
            fi

            echo "  Syncing: $file_src -> $file_dest"
            if [[ "$is_system" == "true" ]]; then
                mkdir -p "$(dirname "$file_dest")"
                cp -a "$file_src" "$file_dest"
                fix_repo_ownership "$file_dest"
                fix_repo_ownership "$(dirname "$file_dest")"
            else
                run_as_owner mkdir -p "$(dirname "$file_dest")"
                run_as_owner cp -a "$file_src" "$file_dest"
            fi
        done
    done
}

# Removes repo paths no longer in restore.conf, backing each up first.
prune_section() {
    local section="$1"
    local repo_base="$2"

    [[ ! -d "$repo_base" ]] && return 0

    echo "Pruning unreferenced configurations in [$section]..."

    declare -A allowed_map
    build_allowed_map "$section" allowed_map

    local repo_items=()
    while IFS= read -r -d $'\0' item; do
        repo_items+=("${item#./}")
    done < <(get_relative_items "$repo_base")

    for item in "${repo_items[@]}"; do
        local full_path="$repo_base/$item"
        [[ ! -e "$full_path" ]] && continue
        [[ "$section" == "keys" && "$item" == "identity.env" ]] && continue

        if ! is_path_covered "$item" allowed_map; then
            local section_prefix="user-configs/home"
            [[ "$section" == "system" ]] && section_prefix="user-configs/system"
            [[ "$section" == "keys" ]] && section_prefix="keys"

            local backup_dest="$BACKUP_REPO_DIR/$section_prefix/$item"
            echo "  [Pruned] Backed up to: $backup_dest"
            # Files in repo are owned by OWNER (enforced at end); rm as owner is sufficient.
            run_as_owner mkdir -p "$(dirname "$backup_dest")"
            run_as_owner cp -a "$full_path" "$backup_dest"
            rm -rf "$full_path"
        fi
    done
}

echo "Starting configuration backup..."

backup_section "home"   "$USER_HOME" "$HOME_CONFIGS"   "user-configs/home"
prune_section  "home"   "$HOME_CONFIGS"

backup_section "system" "/etc"        "$SYSTEM_CONFIGS" "user-configs/system"
prune_section  "system" "$SYSTEM_CONFIGS"

backup_section "keys"   "$USER_HOME" "$KEYS_DIR"       "keys"
prune_section  "keys"   "$KEYS_DIR"

# Ensure entire repo is owned by the standard user, not root.
if [[ $EUID -eq 0 && -n "${OWNER:-}" && "$OWNER" != "root" ]]; then
    echo "Correcting repository ownership to $OWNER..."
    chown -R "$OWNER:$OWNER" "$OS_CONFIGS"
fi

echo "Backup complete."
