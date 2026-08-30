#!/usr/bin/env bash
# ============================================================
# Shared Benchmark Library
# ============================================================
# Sourced by cpu_bench.sh and gpu_bench.sh.
# Must be sourced AFTER OUT_DIR and OUT_PREFIX globals are
# initialized, and BEFORE RESULT_FILE is declared readonly.
# ============================================================

# --- SHARED TIMING CONSTANTS ---
readonly BENCH_DURATION=120
readonly COOLDOWN=60
readonly SAMPLE_INTERVAL=5

# --- LOGGING HELPERS ---
# RESULT_FILE must be set in calling script before log_* are used for file output.
log_msg()  { echo -e "$*" | tee -a "${RESULT_FILE:-/dev/stderr}"; }
log_err()  { echo -e "❌ [ERROR] $*" | tee -a "${RESULT_FILE:-/dev/stderr}" >&2; }
log_warn() { echo -e "⚠️ [WARN] $*" | tee -a "${RESULT_FILE:-/dev/stderr}"; }

# --- PRIVILEGE CHECK ---
ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ ERROR: Root privileges required. Run with: sudo bash $0" >&2
        exit 1
    fi
}

# --- ARGUMENT PARSING ---
# Parses -h (help), -f (prefix), -o (output dir).
# Modifies OUT_PREFIX and OUT_DIR globals in calling scope.
# Usage: parse_bench_args "cpu" "$@"   or   parse_bench_args "gpu" "$@"
parse_bench_args() {
    local kind="$1"; shift
    local opt
    local OPTIND=1
    while getopts ":hf:o:" opt "$@"; do
        case $opt in
            h)
                echo "Usage: sudo $0 [-f suffix_or_name] [-o output_directory]"
                exit 0
                ;;
            f)
                if [[ "$OPTARG" == ${kind}_* ]]; then
                    OUT_PREFIX="$OPTARG"
                else
                    OUT_PREFIX="${kind}_${OPTARG}"
                fi
                ;;
            o) OUT_DIR="$OPTARG" ;;
            :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
            \?) echo "Usage: $0 [-h] [-f suffix_or_name] [-o output_directory]" >&2; exit 1 ;;
        esac
    done
    mkdir -p "$OUT_DIR" 2>/dev/null || OUT_DIR="/tmp"
}

# --- FLOAT GREATER-THAN COMPARISON ---
# Returns 0 (true) if $1 > $2 numerically, 1 (false) otherwise.
bench_gt() {
    (( $(echo "$1 > $2" | bc -l 2>/dev/null || echo 0) ))
}

# --- PEAK VALUE TRACKING ---
# Updates the named variable if val is greater than its current value.
# Usage: bench_update_peak "42.5" peak_var_name
bench_update_peak() {
    local val="$1"
    local varname="$2"
    if bench_gt "$val" "${!varname}"; then
        printf -v "$varname" '%s' "$val"
    fi
}

# --- OWNERSHIP FIX ---
# Restores file ownership to the real user after running under sudo.
bench_fix_ownership() {
    chown -R "${SUDO_USER:-$USER}" "$@" 2>/dev/null || true
}
