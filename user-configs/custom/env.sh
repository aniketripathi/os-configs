# Shell Environment Variables (sourced with auto-export, no shebang required)

PATH="/mnt/core/os-configs/user-configs/custom/bin:$PATH"

CORE="/mnt/core"
LIBRARY="/mnt/library"
TEMP="/mnt/temp"

# --- GPU Shader & Compute Cache Sizes ---
# Cache paths: NVIDIA: ~/.cache/nvidia/GLCache | CUDA: ~/.nv/ComputeCache | Mesa: ~/.cache/mesa_shader_cache
__GL_SHADER_DISK_CACHE_SIZE=21474836480
__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
CUDA_CACHE_MAXSIZE=2147483648
MESA_SHADER_CACHE_MAX_SIZE="2G"
