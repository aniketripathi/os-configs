#!/bin/bash
# ==============================================================================
# Multi-Aspect Power Profile Manager
# ==============================================================================
# Manages ACPI Platform Profiles, CPU Frequency Capping, Dynamic Boost, and EPP.
# Reads declarative profile definitions from power-profiles.conf via crudini.
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

# --- TOP-LEVEL SCRIPT CONSTANTS ---
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_CONFIG="${SCRIPT_DIR}/../power-profiles.conf"
readonly FALLBACK_CONFIG="${SCRIPT_DIR}/../../../init/configs/power-profiles.conf.default"

# Resolve non-root user home safely even under sudo
ACTUAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$ACTUAL_USER" 2>/dev/null | cut -d: -f6 || echo "$HOME")
readonly STATE_DIR="${USER_HOME}/.local/state/os-configs"
readonly STATE_FILE="${STATE_DIR}/power-profile.state"

# Sysfs hardware interfaces
readonly ACPI_PROFILE_PATH="/sys/firmware/acpi/platform_profile"
readonly ACPI_CHOICES_PATH="/sys/firmware/acpi/platform_profile_choices"
readonly CPU_BOOST_PATH="/sys/devices/system/cpu/cpufreq/boost"
readonly CPU_EPP_AVAIL="/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences"
readonly CPU_AMD_MAX_FREQ="/sys/devices/system/cpu/cpu0/cpufreq/amd_pstate_max_freq"
readonly CPU_FREQ_MAX_AVAIL="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
readonly CPU_FREQ_MIN_AVAIL="/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq"

# --- HELPER FUNCTIONS ---

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: Root privileges required. Run with: sudo $0 $*" >&2
        exit 1
    fi
}

get_config_path() {
    if [[ -f "$DEFAULT_CONFIG" ]]; then
        echo "$DEFAULT_CONFIG"
    elif [[ -f "$FALLBACK_CONFIG" ]]; then
        echo "$FALLBACK_CONFIG"
    else
        echo ""
    fi
}

get_config_val() {
    local section="$1"
    local key="$2"
    local default_val="$3"
    local cfg
    cfg=$(get_config_path)

    if [[ -n "$cfg" ]] && command -v crudini >/dev/null 2>&1; then
        local val
        val=$(crudini --get "$cfg" "$section" "$key" 2>/dev/null || echo "")
        if [[ -n "$val" ]]; then
            echo "$val"
            return 0
        fi
    fi
    echo "$default_val"
}

get_hw_min_mhz() {
    local min_khz
    min_khz=$(cat "$CPU_FREQ_MIN_AVAIL" 2>/dev/null || echo "400000")
    echo $(( min_khz / 1000 ))
}

get_hw_max_mhz() {
    local max_khz
    # Prefer true hardware maximum boost clock from amd_pstate_max_freq if present
    if [[ -f "$CPU_AMD_MAX_FREQ" ]]; then
        max_khz=$(cat "$CPU_AMD_MAX_FREQ" 2>/dev/null || echo "4280000")
    else
        max_khz=$(cat "$CPU_FREQ_MAX_AVAIL" 2>/dev/null || echo "4280000")
    fi
    echo $(( max_khz / 1000 ))
}

get_power_source() {
    local online
    online=$(cat /sys/class/power_supply/AC*/online 2>/dev/null || echo 1)
    if [[ "$online" -eq 1 ]]; then
        echo "AC Charger"
    else
        echo "Battery"
    fi
}

# --- VALIDATION HELPERS ---

validate_acpi_mode() {
    local mode="$1"
    local choices
    choices=$(cat "$ACPI_CHOICES_PATH" 2>/dev/null || echo "low-power balanced performance")
    if ! [[ " $choices " =~ [[:space:]]${mode}[[:space:]] ]]; then
        echo "Error: Invalid ACPI mode '$mode'. Valid choices: $choices" >&2
        return 1
    fi
    return 0
}

validate_freq() {
    local freq_str="$1"
    local num_val
    num_val=$(echo "$freq_str" | grep -o -E '^[0-9]+' || echo "")
    if [[ -z "$num_val" ]]; then
        echo "Error: Invalid frequency format '$freq_str'. Must be e.g. 3500MHz" >&2
        return 1
    fi
    local min_mhz
    min_mhz=$(get_hw_min_mhz)
    local max_mhz
    max_mhz=$(get_hw_max_mhz)
    if (( num_val < min_mhz || num_val > max_mhz )); then
        echo "Warning: Frequency ${num_val}MHz is outside detected hardware limits (${min_mhz}MHz - ${max_mhz}MHz)." >&2
    fi
    return 0
}

validate_epp() {
    local epp="$1"
    local avail
    avail=$(cat "$CPU_EPP_AVAIL" 2>/dev/null || echo "power balance_power balance_performance performance")
    if ! [[ " $avail " =~ [[:space:]]${epp}[[:space:]] ]]; then
        echo "Error: Invalid EPP preference '$epp'. Available choices: $avail" >&2
        return 1
    fi
    return 0
}

validate_boost() {
    local boost="$1"
    if [[ "$boost" != "0" && "$boost" != "1" ]]; then
        echo "Error: Invalid boost value '$boost'. Must be 0 (Disabled) or 1 (Enabled)." >&2
        return 1
    fi
    return 0
}

# --- STATUS & DISPLAY ROUTINE ---

show_status() {
    local saved_profile
    saved_profile="unknown"
    if [[ -f "$STATE_FILE" ]]; then
        saved_profile=$(grep "^ACTIVE_PROFILE=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    fi

    local cur_acpi
    cur_acpi=$(cat "$ACPI_PROFILE_PATH" 2>/dev/null || echo "N/A")
    local cur_acpi_choices
    cur_acpi_choices=$(cat "$ACPI_CHOICES_PATH" 2>/dev/null || echo "low-power balanced performance custom")
    local cur_boost
    cur_boost=$(cat "$CPU_BOOST_PATH" 2>/dev/null || echo "1")
    local cur_max_khz
    cur_max_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo "0")
    local cur_max_mhz
    cur_max_mhz=$(( cur_max_khz / 1000 ))
    local cur_cur_mhz
    cur_cur_mhz=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | awk '{s+=$1; n++} END {if(n>0) printf "%.0f", s/n/1000; else print "0"}')
    local cur_epp
    cur_epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "N/A")
    local cur_epp_avail
    cur_epp_avail=$(cat "$CPU_EPP_AVAIL" 2>/dev/null || echo "power balance_power balance_performance performance")
    local min_mhz
    min_mhz=$(get_hw_min_mhz)
    local max_mhz
    max_mhz=$(get_hw_max_mhz)
    local pwr_src
    pwr_src=$(get_power_source)

    echo "Power Profile: ${saved_profile^^} (Saved: $saved_profile)"
    echo "  ACPI        : $cur_acpi (available: $cur_acpi_choices)"
    echo "  Freq Limit  : ${cur_max_mhz}MHz (hardware: ${min_mhz}MHz - ${max_mhz}MHz, current: ${cur_cur_mhz}MHz)"
    echo "  Boost       : $cur_boost (available: 0, 1)"
    echo "  EPP         : $cur_epp (available: $cur_epp_avail)"
    echo "  Power       : $pwr_src"
}

# --- APPLICATION ROUTINE ---

apply_profile() {
    local target_profile="$1"
    require_root "$@"

    local target_acpi
    local target_freq
    local target_boost
    local target_epp

    case "$target_profile" in
        quiet)
            target_acpi=$(get_config_val "quiet" "acpi" "low-power")
            target_freq=$(get_config_val "quiet" "freq" "3300MHz")
            target_boost=$(get_config_val "quiet" "boost" "0")
            target_epp=$(get_config_val "quiet" "epp" "power")
            ;;
        balanced)
            target_acpi=$(get_config_val "balanced" "acpi" "balanced")
            target_freq=$(get_config_val "balanced" "freq" "3500MHz")
            target_boost=$(get_config_val "balanced" "boost" "1")
            target_epp=$(get_config_val "balanced" "epp" "balance_performance")
            ;;
        performance)
            target_acpi=$(get_config_val "performance" "acpi" "performance")
            target_freq=$(get_config_val "performance" "freq" "3750MHz")
            target_boost=$(get_config_val "performance" "boost" "1")
            target_epp=$(get_config_val "performance" "epp" "balance_performance")
            ;;
        *)
            echo "Error: Unknown profile '$target_profile'. Available: quiet, balanced, performance" >&2
            exit 1
            ;;
    esac

    # Perform value validation
    validate_acpi_mode "$target_acpi"
    validate_freq "$target_freq"
    validate_boost "$target_boost"
    validate_epp "$target_epp"

    # Capture previous values for clear transition output
    local old_acpi
    old_acpi=$(cat "$ACPI_PROFILE_PATH" 2>/dev/null || echo "unknown")
    local old_freq_khz
    old_freq_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo "0")
    local old_freq_mhz
    old_freq_mhz=$(( old_freq_khz / 1000 ))
    local old_boost
    old_boost=$(cat "$CPU_BOOST_PATH" 2>/dev/null || echo "1")
    local old_epp
    old_epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "unknown")

    # 1. Apply ACPI Platform Profile
    echo "$target_acpi" > "$ACPI_PROFILE_PATH" 2>/dev/null || echo "Warning: Failed to write $target_acpi to $ACPI_PROFILE_PATH" >&2

    # 2. Apply CPU Boost
    echo "$target_boost" > "$CPU_BOOST_PATH" 2>/dev/null || echo "Warning: Failed to write boost=$target_boost" >&2

    # 3. Apply CPU Frequency Cap
    if command -v cpupower >/dev/null 2>&1; then
        cpupower frequency-set -u "$target_freq" >/dev/null 2>&1 || echo "Warning: cpupower failed to set $target_freq" >&2
    fi

    # 4. Apply EPP Silicon Bias across all cores
    local f
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        [[ -f "$f" ]] && echo "$target_epp" > "$f" 2>/dev/null || true
    done

    # 5. Persist runtime state to XDG state file
    mkdir -p "$STATE_DIR"
    cat > "$STATE_FILE" << EOF
ACTIVE_PROFILE="$target_profile"
LAST_SWITCHED="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
    chown -R "${ACTUAL_USER}:${ACTUAL_USER}" "$STATE_DIR" 2>/dev/null || true
    chmod 644 "$STATE_FILE" 2>/dev/null || true

    # Clean, concise transition output
    echo "Switched to [${target_profile^^}] profile:"
    echo "  ACPI  : $old_acpi -> $target_acpi"
    echo "  Freq  : ${old_freq_mhz}MHz -> $target_freq (boost: $old_boost -> $target_boost)"
    echo "  EPP   : $old_epp -> $target_epp"
}

restore_on_boot() {
    require_root "$@"

    local target_profile
    target_profile=""
    if [[ -f "$STATE_FILE" ]]; then
        target_profile=$(grep "^ACTIVE_PROFILE=" "$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
    fi

    # If no saved state, select default based on power source
    if [[ -z "$target_profile" ]]; then
        if [[ $(get_power_source) == "AC Charger" ]]; then
            target_profile="balanced"
        else
            target_profile="quiet"
        fi
    fi

    apply_profile "$target_profile" || {
        echo "Warning: Failed to apply power profile '$target_profile' during startup. Continuing boot." >&2
        return 0
    }
    return 0
}

# --- SUBCOMMAND DISPATCH ---
action="${1:-status}"
case "$action" in
    status)
        show_status
        ;;
    quiet|balanced|performance)
        apply_profile "$action"
        ;;
    restore)
        restore_on_boot "$@"
        ;;
    auto)
        if [[ $(get_power_source) == "AC Charger" ]]; then
            apply_profile "balanced"
        else
            apply_profile "quiet"
        fi
        ;;
    *)
        echo "Usage: $0 {quiet|balanced|performance|status|restore|auto}" >&2
        exit 1
        ;;
esac
