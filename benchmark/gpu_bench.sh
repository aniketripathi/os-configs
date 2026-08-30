#!/usr/bin/env bash
# ============================================================
# Dynamic GPU CUDA Benchmark & Telemetry Logger
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- PATHS & ARGUMENT PARSING ---
DEFAULT_OUT_DIR="${SCRIPT_DIR}/results"
OUT_DIR="$DEFAULT_OUT_DIR"
OUT_PREFIX="gpu_bench"

# shellcheck source=../lib/bench_common.sh
source "${SCRIPT_DIR}/../lib/bench_common.sh"

parse_bench_args "gpu" "$@"

# --- PRIVILEGE CHECK ---
ensure_root

# --- CONSTANTS ---
readonly RESULT_FILE="${OUT_DIR}/${OUT_PREFIX}_results.txt"
readonly CSV_FILE="${OUT_DIR}/${OUT_PREFIX}_data.csv"
readonly TMP_BENCH_FILE="/tmp/${OUT_PREFIX}_cuda.txt"

# --- TOOL DEPENDENCY CHECK ---
readonly REQUIRED_TOOLS=(nvidia-smi python3 bc awk grep)
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ ERROR: Required tool '$tool' is missing. Please install it first." >&2
        exit 1
    fi
done

if ! nvidia-smi >/dev/null 2>&1; then
    echo "❌ ERROR: NVIDIA driver is not active or nvidia-smi failed." >&2
    exit 1
fi

if ! python3 -c "import ctypes; assert ctypes.CDLL('libcuda.so.1').cuInit(0) == 0" 2>/dev/null; then
    echo "❌ ERROR: Failed to initialize CUDA Driver API (libcuda.so.1)." >&2
    exit 1
fi

# --- DYNAMIC HARDWARE & FREQUENCY DETECTION ---
GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs || echo "NVIDIA GPU")
VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ' || echo "4096")
VRAM_TYPE="GDDR6"
DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | xargs || echo "NVIDIA")
KERNEL_VER=$(uname -r)
HOST_NAME="Linux-PC"

# Detect GPU max boost clock dynamically
MAX_BOOST_MHZ=$(nvidia-smi --query-gpu=clocks.max.graphics --format=csv,noheader,nounits 2>/dev/null \
    | head -1 | grep -o -E '^[0-9]+' || echo "2100")
if [ -z "$MAX_BOOST_MHZ" ]; then
    MAX_BOOST_MHZ=2100
fi

# GPU base graphics clock (minimum benchmark target)
BASE_MHZ=1200

# Dynamically distribute the boost headroom across 4 steps.
# First element is 0 (sentinel: quiet floor capped at BASE_MHZ) then +25%/+50%/+75%/+100%
BOOST_RANGE=$(( MAX_BOOST_MHZ - BASE_MHZ ))
if [ "$BOOST_RANGE" -gt 0 ]; then
    STEP_25=$(( ((BASE_MHZ + BOOST_RANGE * 25 / 100) + 25) / 50 * 50 ))
    STEP_50=$(( ((BASE_MHZ + BOOST_RANGE * 50 / 100) + 25) / 50 * 50 ))
    STEP_75=$(( ((BASE_MHZ + BOOST_RANGE * 75 / 100) + 25) / 50 * 50 ))
    readonly TEST_FREQS_MHZ=(0 "$STEP_25" "$STEP_50" "$STEP_75" "$MAX_BOOST_MHZ")
else
    readonly TEST_FREQS_MHZ=(0 1450 1650 1850 "$MAX_BOOST_MHZ")
fi

# --- STATE MANAGEMENT ---
restore_state() {
    echo -e "\n[Restore] Resetting GPU to default dynamic clocks (nvidia-smi -rgc)..." | tee -a "$RESULT_FILE"
    nvidia-smi -rgc >/dev/null 2>&1 || true
    echo "[Restore] ✅ GPU state restored." | tee -a "$RESULT_FILE"
    bench_fix_ownership "$RESULT_FILE" "$CSV_FILE" "$OUT_DIR"
    rm -f "$TMP_BENCH_FILE" 2>/dev/null || true
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
measure_gpu_temp() {
    local t
    t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    echo "${t:-0}"
}

measure_gpu_power() {
    local p
    p=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    echo "${p:-0.00}"
}

measure_gpu_clock() {
    local c
    c=$(nvidia-smi --query-gpu=clocks.current.graphics --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    echo "${c:-0}"
}

measure_gpu_mem_clock() {
    local m
    m=$(nvidia-smi --query-gpu=clocks.current.memory --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    echo "${m:-0}"
}

measure_gpu_util() {
    local u
    u=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    echo "${u:-0}"
}

# --- CONTROL & COOLDOWN METHODS ---
apply_gpu_limit() {
    local target_mhz="$1"
    if [ "$target_mhz" -eq 0 ]; then
        # Sentinel 0: quiet floor — cap at BASE_MHZ
        nvidia-smi -lgc 0,"$BASE_MHZ" >/dev/null 2>&1 || log_warn "nvidia-smi -lgc 0,$BASE_MHZ failed"
    elif [ "$target_mhz" -eq "$MAX_BOOST_MHZ" ]; then
        # Max boost — reset to unconstrained dynamic boost
        nvidia-smi -rgc >/dev/null 2>&1 || log_warn "nvidia-smi -rgc failed"
    else
        # Intermediate cap
        nvidia-smi -lgc 0,"$target_mhz" >/dev/null 2>&1 || log_warn "nvidia-smi -lgc 0,$target_mhz failed"
    fi
}

cooldown() {
    local label="$1"
    echo -e "\n⏳ Cooldown ${COOLDOWN}s before: $label" | tee -a "$RESULT_FILE"

    local start_temp
    start_temp=$(measure_gpu_temp)

    local timer
    for timer in $(seq "$COOLDOWN" -5 5); do
        printf "\r   [Cooldown] %3ds | GPU: %s°C | Power: %sW | Clock: %s MHz    " \
            "$timer" "$(measure_gpu_temp)" "$(measure_gpu_power)" "$(measure_gpu_clock)"
        sleep 5
    done
    echo ""
    echo "   End of cooldown — GPU: $(measure_gpu_temp)°C (was: ${start_temp}°C)" | tee -a "$RESULT_FILE"
}

# --- STAGE 1: MEMORY & BUS BENCHMARK ---
run_memory_bench() {
    python3 - << 'EOF'
import ctypes, time, sys

try:
    cuda = ctypes.CDLL('libcuda.so.1')
    assert cuda.cuInit(0) == 0
    ctx = ctypes.c_void_p()
    dev = ctypes.c_int(0)
    assert cuda.cuCtxCreate_v2(ctypes.byref(ctx), 0, dev) == 0

    cuda.cuMemAlloc_v2.argtypes = [ctypes.POINTER(ctypes.c_ulonglong), ctypes.c_size_t]
    cuda.cuMemcpyDtoD_v2.argtypes = [ctypes.c_ulonglong, ctypes.c_ulonglong, ctypes.c_size_t]
    cuda.cuMemcpyHtoD_v2.argtypes = [ctypes.c_ulonglong, ctypes.c_void_p, ctypes.c_size_t]
    cuda.cuMemFree_v2.argtypes = [ctypes.c_ulonglong]

    # 1. PCIe Host-to-Device Transfer Bandwidth
    pcie_size = 256 * 1024 * 1024 # 256 MB
    d_pcie = ctypes.c_ulonglong()
    assert cuda.cuMemAlloc_v2(ctypes.byref(d_pcie), pcie_size) == 0
    host_buf = ctypes.create_string_buffer(pcie_size)

    # Warmup
    cuda.cuMemcpyHtoD_v2(d_pcie, host_buf, pcie_size)
    cuda.cuCtxSynchronize()

    t0 = time.time()
    for _ in range(5):
        cuda.cuMemcpyHtoD_v2(d_pcie, host_buf, pcie_size)
    cuda.cuCtxSynchronize()
    t1 = time.time()
    pcie_bw = (5 * 0.256) / (t1 - t0)
    cuda.cuMemFree_v2(d_pcie)

    # 2. Dedicated VRAM Bandwidth (Device-to-Device)
    vram_size = 512 * 1024 * 1024 # 512 MB
    d_src = ctypes.c_ulonglong()
    d_dst = ctypes.c_ulonglong()
    assert cuda.cuMemAlloc_v2(ctypes.byref(d_src), vram_size) == 0
    assert cuda.cuMemAlloc_v2(ctypes.byref(d_dst), vram_size) == 0

    # Warmup
    cuda.cuMemcpyDtoD_v2(d_dst, d_src, vram_size)
    cuda.cuCtxSynchronize()

    t0 = time.time()
    for _ in range(10):
        cuda.cuMemcpyDtoD_v2(d_dst, d_src, vram_size)
    cuda.cuCtxSynchronize()
    t1 = time.time()
    # 512MB read + 512MB write = 1GB per iter
    vram_bw = (10 * 1.0) / (t1 - t0)
    cuda.cuMemFree_v2(d_src)
    cuda.cuMemFree_v2(d_dst)

    print(f"PCIE_BW:{pcie_bw:.2f}")
    print(f"VRAM_BW:{vram_bw:.2f}")
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# --- BENCHMARK ROUTINE ---
run_benchmark() {
    local freq_target="$1"
    local test_name

    if   [ "$freq_target" -eq 0 ];                then test_name="${BASE_MHZ} MHz (Quiet Floor)"
    elif [ "$freq_target" -eq "$MAX_BOOST_MHZ" ]; then test_name="${MAX_BOOST_MHZ} MHz (Full Dynamic Boost)"
    else test_name="${freq_target} MHz (Cap)"
    fi

    echo -e "\n============================================================" | tee -a "$RESULT_FILE"
    echo " TEST: $test_name" | tee -a "$RESULT_FILE"
    echo "============================================================" | tee -a "$RESULT_FILE"

    apply_gpu_limit "$freq_target"
    sleep 3

    echo "   Pre-test — GPU: $(measure_gpu_temp)°C | Clock: $(measure_gpu_clock) MHz" | tee -a "$RESULT_FILE"
    echo "   Starting CUDA compute benchmark (${BENCH_DURATION}s)..." | tee -a "$RESULT_FILE"

    local start_gpu peak_gpu peak_power total_power sample_count bench_pid
    start_gpu=$(measure_gpu_temp)
    peak_gpu="$start_gpu"
    peak_power="0"
    total_power="0"
    sample_count=0

    # Launch CUDA compute worker as background process
    rm -f "$TMP_BENCH_FILE" 2>/dev/null || true
    python3 - "$TMP_BENCH_FILE" << 'EOF' >/dev/null 2>&1 &
import ctypes, time, signal, sys

raw_out_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/gpu_raw.txt"

running = True
def sig_handler(sig, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, sig_handler)
signal.signal(signal.SIGINT, sig_handler)

cuda = ctypes.CDLL('libcuda.so.1')
assert cuda.cuInit(0) == 0
ctx = ctypes.c_void_p()
dev = ctypes.c_int(0)
assert cuda.cuCtxCreate_v2(ctypes.byref(ctx), 0, dev) == 0

ptx = b'''
.version 6.0
.target sm_50
.address_size 64
.visible .entry compute_stress(.param .u64 d_out, .param .u32 iterations) {
    .reg .pred %p; .reg .u32 %iter, %i; .reg .f32 %f0, %f1, %f2, %f3; .reg .u64 %out_ptr;
    ld.param.u64 %out_ptr, [d_out]; ld.param.u32 %iter, [iterations];
    mov.f32 %f0, 1.0001; mov.f32 %f1, 1.0002; mov.f32 %f2, 1.0003; mov.f32 %f3, 1.0004; mov.u32 %i, 0;
LOOP:
    fma.rn.f32 %f0, %f0, %f1, %f2; fma.rn.f32 %f1, %f1, %f2, %f3;
    fma.rn.f32 %f2, %f2, %f3, %f0; fma.rn.f32 %f3, %f3, %f0, %f1;
    fma.rn.f32 %f0, %f0, %f1, %f2; fma.rn.f32 %f1, %f1, %f2, %f3;
    fma.rn.f32 %f2, %f2, %f3, %f0; fma.rn.f32 %f3, %f3, %f0, %f1;
    add.u32 %i, %i, 1; setp.lt.u32 %p, %i, %iter; @%p bra LOOP;
    st.global.f32 [%out_ptr], %f0; ret;
}
'''
mod = ctypes.c_void_p()
assert cuda.cuModuleLoadData(ctypes.byref(mod), ptx) == 0
func = ctypes.c_void_p()
assert cuda.cuModuleGetFunction(ctypes.byref(func), mod, b'compute_stress') == 0

cuda.cuMemAlloc_v2.argtypes = [ctypes.POINTER(ctypes.c_ulonglong), ctypes.c_size_t]
cuda.cuLaunchKernel.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint, ctypes.c_uint, ctypes.c_uint,
    ctypes.c_uint, ctypes.c_uint, ctypes.c_uint,
    ctypes.c_uint, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p)
]
d_out = ctypes.c_ulonglong()
assert cuda.cuMemAlloc_v2(ctypes.byref(d_out), 1024) == 0

blocks = 1024
threads_per_block = 256
iters_per_batch = 100000
flops_per_thread = iters_per_batch * 16
flops_per_batch = blocks * threads_per_block * flops_per_thread

arg1 = ctypes.c_void_p(d_out.value)
arg2 = ctypes.c_uint32(iters_per_batch)
args = (ctypes.c_void_p * 2)(ctypes.cast(ctypes.byref(arg1), ctypes.c_void_p), ctypes.cast(ctypes.byref(arg2), ctypes.c_void_p))

total_batches = 0
start_time = time.time()
while running:
    cuda.cuLaunchKernel(func, blocks, 1, 1, threads_per_block, 1, 1, 0, None, args, None)
    cuda.cuCtxSynchronize()
    total_batches += 1
end_time = time.time()

elapsed = end_time - start_time
total_flops = total_batches * flops_per_batch
gflops = (total_flops / elapsed) / 1e9 if elapsed > 0 else 0

with open(raw_out_path, "w") as f:
    f.write(f"GFLOPS:{gflops:.2f}\n")
    f.write(f"ELAPSED:{elapsed:.2f}\n")
    f.write(f"BATCHES:{total_batches}\n")
EOF
    bench_pid=$!

    # Verify background worker started
    sleep 0.5
    if ! kill -0 "$bench_pid" 2>/dev/null; then
        log_err "Failed to start CUDA compute worker."
        return 1
    fi

    local elapsed=0

    # Print aligned header — sample every 5 seconds, identical cadence to cpu_bench
    printf "\n   %-8s %-8s %-10s %-12s %-12s %-10s\n" \
        "Time" "Load%" "GPU°C" "Power(W)" "Clock" "MemClock"
    printf "   %s\n" "----------------------------------------------------------------------"

    while [ "$elapsed" -lt "$BENCH_DURATION" ]; do
        sleep "$SAMPLE_INTERVAL"
        elapsed=$((elapsed + SAMPLE_INTERVAL))

        local gpu_t gpu_p gpu_c gpu_m gpu_u
        gpu_t=$(measure_gpu_temp)
        gpu_p=$(measure_gpu_power)
        gpu_c=$(measure_gpu_clock)
        gpu_m=$(measure_gpu_mem_clock)
        gpu_u=$(measure_gpu_util)

        bench_update_peak "$gpu_t" peak_gpu
        bench_update_peak "$gpu_p" peak_power
        total_power=$(echo "$total_power + $gpu_p" | bc -l 2>/dev/null || echo "$total_power")
        ((sample_count++))

        printf "   %-8s %-8s %-10s %-12s %-12s %-10s\n" \
            "${elapsed}s" "${gpu_u}%" "${gpu_t}°C" "${gpu_p}W" "${gpu_c}MHz" "${gpu_m}MHz"

        echo "${elapsed},${freq_target},${gpu_u},${gpu_t},${gpu_p},${gpu_c},${gpu_m}" >> "$CSV_FILE"
    done

    # Measure End Temp BEFORE terminating workload so it captures true sustained load temp
    local end_gpu
    end_gpu=$(measure_gpu_temp)

    # Send SIGTERM so Python records final GFLOPS and exits cleanly
    kill -TERM "$bench_pid" 2>/dev/null || true
    wait "$bench_pid" 2>/dev/null || true
    sleep 0.2

    local gflops="0"
    if [ -f "$TMP_BENCH_FILE" ]; then
        gflops=$(grep "GFLOPS:" "$TMP_BENCH_FILE" | cut -d: -f2 | tr -d ' ' || echo "0")
    fi

    local avg_power="0" eff="N/A"
    if [ "$sample_count" -gt 0 ]; then
        avg_power=$(echo "scale=2; $total_power / $sample_count" | bc -l 2>/dev/null || echo "0")
    fi

    if [ "$gflops" != "0" ] && bench_gt "$avg_power" "0"; then
        eff=$(echo "scale=1; $gflops / $avg_power" | bc -l 2>/dev/null || echo "N/A")
    fi

    echo "" | tee -a "$RESULT_FILE"
    echo "   ┌─ Start Temp    : ${start_gpu}°C" | tee -a "$RESULT_FILE"
    echo "   ├─ Peak Temp     : ${peak_gpu}°C" | tee -a "$RESULT_FILE"
    echo "   ├─ End Temp      : ${end_gpu}°C" | tee -a "$RESULT_FILE"
    echo "   ├─ Peak Power    : ${peak_power}W" | tee -a "$RESULT_FILE"
    echo "   ├─ Avg Power     : ${avg_power}W" | tee -a "$RESULT_FILE"
    echo "   ├─ FP32 Compute  : ${gflops} GFLOPS" | tee -a "$RESULT_FILE"
    echo "   └─ Efficiency    : ${eff} GF/W" | tee -a "$RESULT_FILE"
}

# --- MAIN INITIALIZATION ---
rm -f "$RESULT_FILE" "$CSV_FILE" "$TMP_BENCH_FILE" 2>/dev/null || true
> "$RESULT_FILE"
> "$CSV_FILE"
echo "elapsed_s,target_mhz,gpu_util_pct,gpu_temp_c,power_w,clock_mhz,mem_clock_mhz" > "$CSV_FILE"

echo "============================================================" | tee -a "$RESULT_FILE"
echo " DYNAMIC GPU CUDA BENCHMARK & TELEMETRY" | tee -a "$RESULT_FILE"
echo " $(date)" | tee -a "$RESULT_FILE"
echo " GPU  : $GPU_MODEL" | tee -a "$RESULT_FILE"
echo " VRAM : ${VRAM_MB} MB ${VRAM_TYPE}" | tee -a "$RESULT_FILE"
echo " Host : $HOST_NAME | Driver: $DRIVER_VER" | tee -a "$RESULT_FILE"
echo " Mode : $(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo 'N/A')" | tee -a "$RESULT_FILE"
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

# --- STAGE 1: MEMORY & BUS TEST ---
# Warn if VRAM may be insufficient for the bandwidth test (needs ~1.1 GB for src+dst buffers)
if (( VRAM_MB < 1100 )); then
    log_warn "Available VRAM (${VRAM_MB}MB) may be insufficient for VRAM bandwidth test (needs ~1.1GB). Results may show 0."
fi

echo -e "\n[Stage 1: Memory & PCIe Bus Bandwidth Test]" | tee -a "$RESULT_FILE"
MEM_OUT=$(run_memory_bench)
PCIE_BW=$(echo "$MEM_OUT" | grep "PCIE_BW:" | cut -d: -f2 | tr -d ' ' || echo "0")
VRAM_BW=$(echo "$MEM_OUT" | grep "VRAM_BW:" | cut -d: -f2 | tr -d ' ' || echo "0")

echo " • PCIe Host-to-Device Bandwidth : ${PCIE_BW} GB/s" | tee -a "$RESULT_FILE"
echo " • Dedicated ${VRAM_TYPE} VRAM Speed     : ${VRAM_BW} GB/s" | tee -a "$RESULT_FILE"

# --- STAGE 2: EXECUTION LOOP — 5 TARGETS (1 BASE + 3 STEPS + MAX) ---
for target in "${TEST_FREQS_MHZ[@]}"; do
    if [ "$target" -eq 0 ]; then
        cooldown "Target: ${BASE_MHZ}MHz (Quiet Floor)"
    elif [ "$target" -eq "$MAX_BOOST_MHZ" ]; then
        cooldown "Target: ${MAX_BOOST_MHZ}MHz (Full Dynamic Boost)"
    else
        cooldown "Target: ${target}MHz (Cap)"
    fi
    run_benchmark "$target"
done

# --- STAGE 3: SUMMARY REPORT ---
echo -e "\n============================================================" | tee -a "$RESULT_FILE"
echo " SUMMARY" | tee -a "$RESULT_FILE"
echo "============================================================" | tee -a "$RESULT_FILE"
printf " %-30s %-10s %-10s %-10s %-14s %-10s\n" "Test" "Start°C" "Peak°C" "PeakPwr" "FP32 Compute" "Efficiency" | tee -a "$RESULT_FILE"
printf " %-30s %-10s %-10s %-10s %-14s %-10s\n" "----" "-------" "------" "-------" "------------" "----------" | tee -a "$RESULT_FILE"

grep -E "TEST: |┌─ Start Temp|├─ Peak Temp|├─ Peak Power|├─ FP32 Compute|└─ Efficiency" "$RESULT_FILE" | \
    awk '
    /TEST:/        { test=$0; gsub(/.*TEST: /,"",test) }
    /Start Temp/   { start=$NF }
    /Peak Temp/    { peak=$NF }
    /Peak Power/   { pwr=$NF }
    /FP32 Compute/ { compute=$(NF-1) }
    /Efficiency/   { printf " %-30s %-10s %-10s %-10s %-14s %-10s\n", substr(test,1,29), start, peak, pwr, compute " GF", $(NF-1) }
    ' | tee -a "$RESULT_FILE"

echo -e "\n✅ ALL BENCHMARKS COMPLETED SUCCESSFULLY." | tee -a "$RESULT_FILE"
echo "============================================================" | tee -a "$RESULT_FILE"
echo " Data saved to:" | tee -a "$RESULT_FILE"
echo " 📄 Log: $RESULT_FILE" | tee -a "$RESULT_FILE"
echo " 📊 CSV: $CSV_FILE" | tee -a "$RESULT_FILE"
echo "============================================================" | tee -a "$RESULT_FILE"
