# Main entry point for custom shell configurations

CUSTOM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize environment variables once per session
if [[ "$CUSTOM_PROFILE_INITIALIZED" != "yes" ]]; then
    umask 027
    unset -f command_not_found_handle command_not_found_handler 2>/dev/null

    if [[ -f "${CUSTOM_DIR}/env.sh" ]]; then
        set -a
        source "${CUSTOM_DIR}/env.sh"
        set +a
    fi
    CUSTOM_PROFILE_INITIALIZED="yes"
fi

# Always source interactive aliases and functions for every shell instance
if [[ -f "${CUSTOM_DIR}/aliases.sh" ]]; then
    source "${CUSTOM_DIR}/aliases.sh"
fi
