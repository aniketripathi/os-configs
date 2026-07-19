# Shared library script for os-configs framework (sourced, no shebang required; ensure 644 permissions).

# Resolve repository root dynamically based on common.sh location
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OS_CONFIGS="$(cd "${LIB_DIR}/.." && pwd)"

# Source directory structure layout config (sets layout paths and umask)
source "${LIB_DIR}/layout.env"

# Resolve non-root owner and their home directory
OWNER="${SUDO_USER:-$USER}"
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

# Unified status printer with automatic indentation and counter updates
print_status() {
    local status="$1"
    local msg="$2"
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

# Apply standard permissions & ownership (umask 027 default: 750 for directories, 640 for files)
apply_default_permissions() {
    local target="$1"
    local is_system="$2"

    if [[ "$is_system" == "true" ]]; then
        sudo chown root:root "$target"
        if [[ -d "$target" ]]; then
            sudo chmod 750 "$target"
        else
            sudo chmod 640 "$target"
        fi
    else
        if [[ $EUID -eq 0 && -n "${OWNER:-}" && "$OWNER" != "root" ]]; then
            sudo chown "${OWNER}:${OWNER}" "$target"
        fi
        if [[ -d "$target" ]]; then
            run_as_owner chmod 750 "$target"
        else
            run_as_owner chmod 640 "$target"
        fi
    fi
}

# Lists recursive files in a path (relative to it) ignoring *.old and *.bak files.
# Outputs NUL-separated relative file paths.
get_relative_files() {
    local target_path="$1"
    if [[ -d "$target_path" ]]; then
        (cd "$target_path" && find . -type f ! -name "*.old" ! -name "*.bak" -print0 2>/dev/null || true)
    fi
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
