#!/usr/bin/env bash
# ============================================================
# Dynamic CPU Benchmark & Telemetry Logger
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- PATHS & ARGUMENT PARSING ---
DEFAULT_OUT_DIR="${SCRIPT_DIR}/results"
OUT_DIR="$DEFAULT_OUT_DIR"
OUT_PREFIX="cpu_bench"

# shellcheck source=../lib/bench_common.sh
source "${SCRIPT_DIR}/../lib/bench_common.sh"

parse_bench_args "cpu" "$@"

# --- PRIVILEGE CHECK ---
ensure_root

# --- CONSTANTS ---
readonly RESULT_FILE="${OUT_DIR}/${OUT_PREFIX}_results.txt"
readonly CSV_FILE="${OUT_DIR}/${OUT_PREFIX}_data.csv"
readonly TMP_BENCH_FILE="/tmp/${OUT_PREFIX}_7z.txt"

# --- TOOL DEPENDENCY CHECK ---
readonly REQUIRED_TOOLS=(sensors cpupower 7z bc awk grep top nproc)
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ ERROR: Required tool '$tool' is missing. Please install it first." >&2
        exit 1
    fi
done

# --- DYNAMIC HARDWARE & FREQUENCY DETECTION ---
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null \
    || lspci 2>/dev/null | grep -iE 'vga|3d' | head -1 | cut -d: -f3 | xargs \
    || echo "Integrated Graphics")
KERNEL_VER=$(uname -r)
HOST_NAME="Linux-PC"
THREADS=$(nproc)

# Detect Max Boost and Base Clock dynamically
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/amd_pstate_max_freq ]; then
    MAX_BOOST_MHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/amd_pstate_max_freq 2>/dev/null \
        | awk '{printf "%.0f", $1/1000}')
else
    MAX_BOOST_MHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null \
        | awk '{printf "%.0f", $1/1000}')
fi

BASE_MHZ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/base_frequency 2>/dev/null \
    | awk '{printf "%.0f", $1/1000}')
if [ -z "$BASE_MHZ" ] || [ "$BASE_MHZ" -eq 0 ]; then
    BASE_MHZ=3300
fi

if [ -z "$MAX_BOOST_MHZ" ] || [ "$MAX_BOOST_MHZ" -le "$BASE_MHZ" ]; then
    MAX_BOOST_MHZ=4280
fi

# Dynamically distribute the boost headroom across 4 steps
# First element is 0 (sentinel: base clock, boost disabled) then +25%/+50%/+75%/+100%
BOOST_RANGE=$(( MAX_BOOST_MHZ - BASE_MHZ ))
if [ "$BOOST_RANGE" -gt 0 ]; then
    STEP_25=$(( ((BASE_MHZ + BOOST_RANGE * 25 / 100) + 25) / 50 * 50 ))
    STEP_50=$(( ((BASE_MHZ + BOOST_RANGE * 50 / 100) + 25) / 50 * 50 ))
    STEP_75=$(( ((BASE_MHZ + BOOST_RANGE * 75 / 100) + 25) / 50 * 50 ))
    readonly TEST_FREQS_MHZ=(0 "$STEP_25" "$STEP_50" "$STEP_75" "$MAX_BOOST_MHZ")
else
    readonly TEST_FREQS_MHZ=(0 3500 3750 4000 "$MAX_BOOST_MHZ")
fi

# --- STATE MANAGEMENT ---
ORIG_BOOST=$(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo "1")
ORIG_EPP=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "balance_performance")
# Store as MHz string (with unit) to be consistent with apply_cpu_limit's cpupower call
_orig_max_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo "4280000")
ORIG_MAX_FREQ="$(( _orig_max_khz / 1000 ))MHz"

restore_state() {
    echo -e "\n[Restore] Resetting to original state..." | tee -a "$RESULT_FILE"
    echo "$ORIG_BOOST" > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
    cpupower frequency-set -u "$ORIG_MAX_FREQ" > /dev/null 2>&1 || true
    for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        echo "$ORIG_EPP" > "$f" 2>/dev/null || true
    done
    echo "[Restore] ✅ System restored." | tee -a "$RESULT_FILE"
    bench_fix_ownership "$RESULT_FILE" "$CSV_FILE" "$OUT_DIR"
}

cleanup_and_exit() {
    echo -e "\n\n⚠️ Benchmark aborted by user (Ctrl+C). Terminating all workloads..." | tee -a "$RESULT_FILE"
    pkill -P $$ 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    restore_state
    exit 130
}
trap cleanup_and_exit INT TERM
trap restore_state EXIT

# --- MEASUREMENT METHODS ---
# Universal CPU Temp: Works on AMD (Tctl/Tdie) and Intel (Package id 0 / Core 0)
measure_cpu_temp() {
    local t
    t=$(sensors 2>/dev/null | grep -iE "Tctl|Package id 0|Tdie" | head -1 | awk '{print $2}' | tr -d '+°C')
    echo "${t:-0.0}"
}
measure_igpu_temp() {
    local t
    t=$(sensors 2>/dev/null | grep -A5 -iE "amdgpu|i915|xe" | grep -iE "edge|temp1" | head -1 | awk '{print $2}' | tr -d '+°C')
    echo "${t:-0.0}"
}
measure_igpu_power() {
    local p
    p=$(sensors 2>/dev/null | grep -A10 -iE "amdgpu|i915|xe" | grep "PPT" | head -1 | awk '{print $2}')
    echo "${p:-0.00}"
}
measure_cpu_util() {
    local u
    u=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{printf "%.1f", 100 - $8}')
    echo "${u:-0.0}"
}
measure_avg_freq() {
    local f
    f=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null \
        | awk '{sum+=$1; n++} END {if(n>0) printf "%.0f", sum/n/1000; else print "0"}')
    echo "${f:-0}"
}
read_rapl_uj() {
    local domain="$1"
    cat "/sys/class/powercap/intel-rapl:${domain}/energy_uj" 2>/dev/null || echo "0"
}

# --- CONTROL METHODS ---
apply_cpu_limit() {
    local target_mhz="$1"
    if [ "$target_mhz" -eq 0 ]; then
        # Sentinel 0: base clock run, boost disabled, conservative EPP
        echo 0 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || log_warn "Unable to write boost=0 in sysfs"
        cpupower frequency-set -u "${BASE_MHZ}MHz" > /dev/null 2>&1 || log_warn "cpupower reset failed"
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo "power" > "$f" 2>/dev/null || true
        done
    else
        echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || log_warn "Unable to write boost=1 in sysfs"
        cpupower frequency-set -u "${target_mhz}MHz" > /dev/null 2>&1 || log_warn "cpupower set ${target_mhz}MHz failed"
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo "balance_performance" > "$f" 2>/dev/null || true
        done
    fi
}

cooldown() {
    local label="$1"
    echo -e "\n⏳ Cooldown ${COOLDOWN}s before: $label" | tee -a "$RESULT_FILE"

    local start_temp
    start_temp=$(measure_cpu_temp)

    local timer
    for timer in $(seq "$COOLDOWN" -5 5); do
        printf "\r   [Cooldown] %3ds | CPU: %s°C | GPU: %s°C | Freq: %s MHz    " \
            "$timer" "$(measure_cpu_temp)" "$(measure_igpu_temp)" "$(measure_avg_freq)"
        sleep 5
    done
    echo ""
    echo "   End of cooldown — CPU: $(measure_cpu_temp)°C (was: ${start_temp}°C)" | tee -a "$RESULT_FILE"
}

# --- BENCHMARK ROUTINE ---
run_benchmark() {
    local freq_target="$1"
    local test_name

    if   [ "$freq_target" -eq 0 ];            then test_name="${BASE_MHZ} MHz (No Boost)"
    elif [ "$freq_target" -eq "$MAX_BOOST_MHZ" ]; then test_name="${MAX_BOOST_MHZ} MHz (Full Boost)"
    else test_name="${freq_target} MHz (Cap)"
    fi

    echo -e "\n============================================================" | tee -a "$RESULT_FILE"
    echo " TEST: $test_name" | tee -a "$RESULT_FILE"
    echo "============================================================" | tee -a "$RESULT_FILE"

    apply_cpu_limit "$freq_target"
    sleep 3

    echo "   Pre-test — CPU: $(measure_cpu_temp)°C | Freq: $(measure_avg_freq) MHz" | tee -a "$RESULT_FILE"
    echo "   Starting 7zip benchmark (${BENCH_DURATION}s)..." | tee -a "$RESULT_FILE"

    local start_cpu peak_cpu peak_power total_power sample_count bench_pid
    start_cpu=$(measure_cpu_temp)
    peak_cpu="$start_cpu"
    peak_power="0"
    total_power="0"
    sample_count=0

    # Start continuous workload as background process
    > "$TMP_BENCH_FILE"
    (
        while true; do
            7z b -mmt="$THREADS" >> "$TMP_BENCH_FILE" 2>&1
        done
    ) &
    bench_pid=$!

    # Verify background worker started
    sleep 0.5
    if ! kill -0 "$bench_pid" 2>/dev/null; then
        log_err "Failed to start 7-Zip workload. Error output:"
        cat "$TMP_BENCH_FILE" 2>/dev/null | tee -a "$RESULT_FILE" >&2
        return 1
    fi

    local elapsed=0 prev_pkg_uj prev_core_uj prev_ts
    prev_pkg_uj=$(read_rapl_uj "0")
    prev_core_uj=$(read_rapl_uj "0:0")
    prev_ts=$(date +%s%3N)

    printf "\n   %-8s %-8s %-10s %-10s %-12s %-12s %-10s %-10s\n" \
        "Time" "Load%" "CPU°C" "iGPU°C" "PkgPwr(W)" "CorePwr(W)" "iGPU PPT" "Freq"
    printf "   %s\n" "--------------------------------------------------------------------------------------"

    while [ "$elapsed" -lt "$BENCH_DURATION" ]; do
        sleep "$SAMPLE_INTERVAL"
        elapsed=$((elapsed + SAMPLE_INTERVAL))

        local curr_pkg_uj curr_core_uj curr_ts
        curr_pkg_uj=$(read_rapl_uj "0")
        curr_core_uj=$(read_rapl_uj "0:0")
        curr_ts=$(date +%s%3N)

        local dt_ms=$(( curr_ts - prev_ts ))
        local pkg_power="0" core_power="0"

        if [ "$dt_ms" -gt 0 ]; then
            # Protect against RAPL counter wraparound
            if (( curr_pkg_uj >= prev_pkg_uj )); then
                pkg_power=$(echo "scale=2; ($curr_pkg_uj - $prev_pkg_uj) / $dt_ms / 1000" | bc -l 2>/dev/null || echo "0")
            fi
            if (( curr_core_uj >= prev_core_uj )); then
                core_power=$(echo "scale=2; ($curr_core_uj - $prev_core_uj) / $dt_ms / 1000" | bc -l 2>/dev/null || echo "0")
            fi
        fi

        local cpu_t igpu_t igpu_p freq cpu_u
        cpu_t=$(measure_cpu_temp)
        igpu_t=$(measure_igpu_temp)
        igpu_p=$(measure_igpu_power)
        freq=$(measure_avg_freq)
        cpu_u=$(measure_cpu_util)

        bench_update_peak "$cpu_t"    peak_cpu
        bench_update_peak "$pkg_power" peak_power
        total_power=$(echo "$total_power + $pkg_power" | bc -l 2>/dev/null || echo "$total_power")
        ((sample_count++))

        printf "   %-8s %-8s %-10s %-10s %-12s %-12s %-10s %-10s\n" \
            "${elapsed}s" "${cpu_u}%" "${cpu_t}°C" "${igpu_t}°C" "${pkg_power}W" "${core_power}W" \
            "${igpu_p}W" "${freq}MHz"

        echo "${elapsed},${freq_target},${cpu_u},${cpu_t},${igpu_t},${pkg_power},${core_power},${igpu_p},${freq}" >> "$CSV_FILE"

        prev_pkg_uj=$curr_pkg_uj
        prev_core_uj=$curr_core_uj
        prev_ts=$curr_ts
    done

    # Measure End Temp BEFORE terminating workload so it captures true sustained load temp
    local end_cpu
    end_cpu=$(measure_cpu_temp)

    # Clean up workload process and all its children safely
    pkill -P "$bench_pid" 2>/dev/null || true
    kill "$bench_pid" 2>/dev/null || true
    wait "$bench_pid" 2>/dev/null || true

    local mips avg_power="0" eff="N/A"
    # Average MIPS across all completed passes in the run
    mips=$(awk '/^Tot:/ {sum += $NF; count++} END {if (count > 0) printf "%.0f", sum/count; else print "0"}' "$TMP_BENCH_FILE")
    if [ -z "$mips" ]; then
        mips="0"
    fi

    if [ "$sample_count" -gt 0 ]; then
        avg_power=$(echo "scale=2; $total_power / $sample_count" | bc -l 2>/dev/null || echo "0")
    fi

    if [ "$mips" != "0" ] && bench_gt "$avg_power" "0"; then
        eff=$(echo "scale=1; $mips / $avg_power" | bc -l 2>/dev/null || echo "N/A")
    fi
    if [ "$mips" = "0" ]; then
        mips="N/A"
    fi

    echo "" | tee -a "$RESULT_FILE"
    echo "   ┌─ Start Temp    : ${start_cpu}°C" | tee -a "$RESULT_FILE"
    echo "   ├─ Peak Temp     : ${peak_cpu}°C" | tee -a "$RESULT_FILE"
    echo "   ├─ End Temp      : ${end_cpu}°C" | tee -a "$RESULT_FILE"
    echo "   ├─ Peak Pkg Pwr  : ${peak_power}W" | tee -a "$RESULT_FILE"
    echo "   ├─ Avg Pkg Pwr   : ${avg_power}W" | tee -a "$RESULT_FILE"
    echo "   ├─ 7z Rating     : ${mips} MIPS" | tee -a "$RESULT_FILE"
    echo "   └─ Efficiency    : ${eff} MIPS/W" | tee -a "$RESULT_FILE"
}

# --- MAIN INITIALIZATION ---
rm -f "$RESULT_FILE" "$CSV_FILE" "$TMP_BENCH_FILE" 2>/dev/null || true
> "$RESULT_FILE"
> "$CSV_FILE"
echo "elapsed_s,target_mhz,cpu_util_pct,cpu_temp_c,igpu_temp_c,cpu_pkg_power_w,cpu_core_power_w,igpu_ppt_w,avg_freq_mhz" > "$CSV_FILE"

echo "============================================================" | tee -a "$RESULT_FILE"
echo " DYNAMIC CPU BENCHMARK & TELEMETRY" | tee -a "$RESULT_FILE"
echo " $(date)" | tee -a "$RESULT_FILE"
echo " CPU  : $CPU_MODEL ($THREADS Threads)" | tee -a "$RESULT_FILE"
echo " GPU  : $GPU_MODEL" | tee -a "$RESULT_FILE"
echo " Host : $HOST_NAME | Kernel: $KERNEL_VER" | tee -a "$RESULT_FILE"
# Build clean display list for scheduled targets banner
scheduled_display=()
for f in "${TEST_FREQS_MHZ[@]}"; do
    if [ "$f" -eq 0 ]; then
        scheduled_display+=("${BASE_MHZ}")
    else
        scheduled_display+=("$f")
    fi
done

echo " Tests Scheduled: ${#TEST_FREQS_MHZ[@]} Targets (${scheduled_display[*]} MHz)" | tee -a "$RESULT_FILE"
echo "============================================================" | tee -a "$RESULT_FILE"

# Warn if intel-rapl power cap is unavailable (expected on AMD — sensors PPT is the alternative)
if [[ ! -f /sys/class/powercap/intel-rapl:0/energy_uj ]]; then
    log_warn "intel-rapl power cap not found. Package/Core power readings will show 0W. (Expected on AMD — use sensors PPT column instead.)"
fi

# --- EXECUTION LOOP ---
for target in "${TEST_FREQS_MHZ[@]}"; do
    if [ "$target" -eq 0 ]; then
        cooldown "Target: ${BASE_MHZ}MHz (No Boost)"
    elif [ "$target" -eq "$MAX_BOOST_MHZ" ]; then
        cooldown "Target: ${MAX_BOOST_MHZ}MHz (Full Boost)"
    else
        cooldown "Target: ${target}MHz (Cap)"
    fi
    run_benchmark "$target"
done

echo -e "\n============================================================" | tee -a "$RESULT_FILE"
echo " SUMMARY" | tee -a "$RESULT_FILE"
echo "============================================================" | tee -a "$RESULT_FILE"
printf " %-30s %-10s %-10s %-10s %-10s %-10s\n" "Test" "Start°C" "Peak°C" "PeakPwr" "MIPS" "MIPS/W" | tee -a "$RESULT_FILE"
printf " %-30s %-10s %-10s %-10s %-10s %-10s\n" "----" "-------" "------" "-------" "----" "------" | tee -a "$RESULT_FILE"

grep -E "TEST: |┌─ Start Temp|├─ Peak Temp|├─ Peak Pkg Pwr|├─ 7z Rating|└─ Efficiency" "$RESULT_FILE" | \
    awk '
    /TEST:/        { test=$0; gsub(/.*TEST: /,"",test) }
    /Start Temp/   { start=$NF }
    /Peak Temp/    { peak=$NF }
    /Peak Pkg Pwr/ { pwr=$NF }
    /7z Rating/    { mips=$(NF-1) }
    /Efficiency/   { printf " %-30s %-10s %-10s %-10s %-10s %-10s\n", substr(test,1,29), start, peak, pwr, mips, $(NF-1) }
    ' | tee -a "$RESULT_FILE"

echo -e "\n✅ ALL BENCHMARKS COMPLETED SUCCESSFULLY." | tee -a "$RESULT_FILE"
echo "============================================================" | tee -a "$RESULT_FILE"
echo " Data saved to:" | tee -a "$RESULT_FILE"
echo " 📄 Log: $RESULT_FILE" | tee -a "$RESULT_FILE"
echo " 📊 CSV: $CSV_FILE" | tee -a "$RESULT_FILE"
echo "============================================================" | tee -a "$RESULT_FILE"
