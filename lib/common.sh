# Shared library script for os-configs framework (sourced, no shebang required; ensure 644 permissions).

# Resolve repository root dynamically based on common.sh location
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OS_CONFIGS="$(cd "${LIB_DIR}/.." && pwd)"

# Source directory structure layout config (sets layout paths and umask)
source "${LIB_DIR}/layout.env"

# Resolve non-root owner and their home directory
OWNER="${SUDO_USER:-$USER}"
if [[ "$OWNER" == "root" ]]; then
    # Fallback to the owner of the repository directory
    repo_owner=$(stat -c '%U' "$OS_CONFIGS" 2>/dev/null || true)
    if [[ -n "$repo_owner" && "$repo_owner" != "root" ]]; then
        OWNER="$repo_owner"
    fi
fi
# USER_HOME is used by external scripts that source this file (e.g., restore-configs.sh, verify-setup.sh, backup-configs.sh)
USER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)

# Standard user shell startup files to configure/verify (all 6 files)
SHELL_RC_FILES=(
    "$USER_HOME/.bashrc"
    "$USER_HOME/.bash_profile"
    "$USER_HOME/.bash_login"
    "$USER_HOME/.zshrc"
    "$USER_HOME/.zprofile"
    "$USER_HOME/.profile"
)

# Initialize counters
ok_count=0
missing_count=0
skip_count=0

# Verify root privileges
require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run with sudo or as root." >&2
        exit 1
    fi
}

# Run a command as the standard user if currently running as root
run_as_owner() {
    if [[ $EUID -eq 0 && -n "${OWNER:-}" && "$OWNER" != "root" ]]; then
        sudo -u "$OWNER" "$@"
    else
        "$@"
    fi
}

# Run a git command as the standard user if currently running as root
git_cmd() {
    if [[ $EUID -eq 0 && -n "${OWNER:-}" && "$OWNER" != "root" ]]; then
        sudo -u "$OWNER" git "$@"
    else
        git "$@"
    fi
}

# Common reporting helpers
report_ok() {
    echo -e "\e[32m[OK]\e[0m $1"
    ok_count=$((ok_count + 1))
}

# Common reporting helpers
report_missing() {
    echo -e "\e[31m[MISSING]\e[0m $1"
    missing_count=$((missing_count + 1))
}

# Common reporting helpers
report_skip() {
    echo -e "\e[33m[SKIP]\e[0m $1"
    skip_count=$((skip_count + 1))
}

print_heading() {
    echo -e "\e[1;36m$1\e[0m"
}

# Unified status printer. Optional 3rd arg appended as detail to the message.
print_status() {
    local status="$1"
    local msg="$2${3:+ $3}"
    case "$status" in
        "OK")
            echo -e "  \e[32m[OK]\e[0m $msg"
            ok_count=$((ok_count + 1))
            ;;
        "MISSING")
            echo -e "  \e[31m[MISSING]\e[0m $msg"
            missing_count=$((missing_count + 1))
            ;;
        "DIFFERENT")
            echo -e "  \e[33m[DIFFERENT]\e[0m $msg"
            missing_count=$((missing_count + 1))
            ;;
        "SKIP")
            echo -e "  \e[33m[SKIP]\e[0m $msg"
            skip_count=$((skip_count + 1))
            ;;
    esac
}

# Apply standard permissions & ownership (750 dirs, 640 files).
# System path: always called as root, so no sudo needed.
apply_default_permissions() {
    local target="$1"
    local is_system="$2"

    if [[ "$is_system" == "true" ]]; then
        chown root:root "$target"
        if [[ -d "$target" ]]; then
            chmod 750 "$target"
        else
            chmod 640 "$target"
        fi
        if command -v restorecon > /dev/null 2>&1; then
            restorecon -R "$target"
        fi
    else
        if [[ $EUID -eq 0 && -n "${OWNER:-}" && "$OWNER" != "root" ]]; then
            chown "${OWNER}:${OWNER}" "$target"
        fi
        if [[ -d "$target" ]]; then
            run_as_owner chmod 750 "$target"
        else
            run_as_owner chmod 640 "$target"
        fi
    fi
}

# Lists recursive files in a path (relative to it) ignoring *.old and *.bak.
# find errors (e.g. permission denied) print to stderr and are skipped; not suppressed.
get_relative_files() {
    local target_path="$1"
    if [[ -d "$target_path" ]]; then
        (cd "$target_path" && find . -type f ! -name "*.old" ! -name "*.bak" -print0 || true)
    fi
}

# Lists recursive files and directories in a path (relative to it) ignoring *.old and *.bak.
get_relative_items() {
    local target_path="$1"
    if [[ -d "$target_path" ]]; then
        (cd "$target_path" && find . -mindepth 1 ! -name "*.old" ! -name "*.bak" -print0 || true)
    fi
}

# Returns 0 (conflict) if dest exists, content differs, and dest is newer than src.
# Conflict = force required. src newer = safe overwrite. identical = skip.
is_conflict() {
    local src="$1" dest="$2"
    [[ ! -e "$dest" ]] && return 1
    cmp -s "$src" "$dest" && return 1
    [[ "$dest" -nt "$src" ]] && return 0
    return 1
}

# Fixes ownership of a path to OWNER after root writes it.
fix_repo_ownership() {
    local path="$1"
    if [[ $EUID -eq 0 && -n "${OWNER:-}" && "$OWNER" != "root" ]]; then
        chown -R "${OWNER}:${OWNER}" "$path" 2>/dev/null || true
    fi
}

# Copies src to dest, creating parent dirs. For system (root-written) files, fixes ownership to OWNER.
# Args: src dest is_system (true|false)
backup_file_to() {
    local src="$1" dest="$2" is_system="${3:-false}"
    if [[ "$is_system" == "true" ]]; then
        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest"
        fix_repo_ownership "$dest"
    else
        run_as_owner mkdir -p "$(dirname "$dest")"
        run_as_owner cp -a "$src" "$dest"
    fi
}

# Builds the allowed paths map for a section from restore.conf
# Args: section, map_name (nameref)
build_allowed_map() {
    local section="$1"
    local -n __allowed_map="$2"
    
    local RESTORE_CONF="$SYNC_MANIFEST"
    if [[ ! -f "$RESTORE_CONF" ]]; then
        return 0
    fi

    local allowed_paths=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && allowed_paths+=("$line")
    done < <(crudini --get "$RESTORE_CONF" "$section" || true)

    local allowed
    for allowed in "${allowed_paths[@]}"; do
        local clean_allowed="${allowed%/}"
        __allowed_map["$clean_allowed"]="exact"

        # Add all ancestor directories as "ancestor" if not already "exact"
        local parent="$clean_allowed"
        while [[ "$parent" != "." && "$parent" != "/" ]]; do
            parent=$(dirname "$parent")
            if [[ -z "${__allowed_map[$parent]:-}" ]]; then
                __allowed_map["$parent"]="ancestor"
            fi
        done
    done
}

# Checks if a repository item is covered by the allowed configurations map in O(1)
# Args: rel_path, map_name (nameref)
is_path_covered() {
    local rel_path="${1%/}"
    local -n __allowed_map="$2"

    # 1. Exact or ancestor match (O(1))
    if [[ -n "${__allowed_map[$rel_path]:-}" ]]; then
        return 0
    fi

    # 2. Descendant match: check if any parent directory is an exact allowed path (O(depth))
    local p="$rel_path"
    while [[ "$p" != "." && "$p" != "/" ]]; do
        p=$(dirname "$p")
        if [[ "${__allowed_map[$p]:-}" == "exact" ]]; then
            return 0
        fi
    done

    return 1
}


# Checks if a specific file exists and sources the custom profile.
# Returns 0 if it exists and sources the custom profile, 1 otherwise.
is_profile_sourced_in() {
    local rc_file="$1"
    local custom_profile="${CUSTOM_CONFIGS:-$USER_CONFIGS/custom}/.profile"
    if [[ -f "$rc_file" ]] && grep -qF "$custom_profile" "$rc_file"; then
        return 0
    fi
    return 1
}

# Verifies if the custom profile is sourced in all relevant user shell rc files.
# Returns 0 if all relevant files source the custom profile, 1 otherwise.
check_profile_sourcing() {
    local status=0

    for rc_file in "${SHELL_RC_FILES[@]}"; do
        local is_relevant=false
        if [[ "$rc_file" == *".bashrc" || "$rc_file" == *".bash_profile" || "$rc_file" == *".bash_login" ]] && command -v bash >/dev/null 2>&1; then
            is_relevant=true
        elif [[ "$rc_file" == *".zshrc" || "$rc_file" == *".zprofile" ]] && command -v zsh >/dev/null 2>&1; then
            is_relevant=true
        elif [[ "$rc_file" == *".profile" ]]; then
            is_relevant=true
        fi

        if $is_relevant; then
            if ! is_profile_sourced_in "$rc_file"; then
                status=1
            fi
        fi
    done
    return $status
}
