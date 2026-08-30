# Shell Aliases and Interactive Helper Functions (sourced, no shebang required)

# --- Git Repository Sync Aliases ---
alias os-configs-sync-now='systemctl --user start os-configs-sync.service'
alias os-configs-sync-enable='systemctl --user enable --now os-configs-sync.timer'
alias os-configs-sync-disable='systemctl --user disable --now os-configs-sync.timer'
os-configs-sync-logs() {
    local n_flag=()
    [[ $# -gt 0 ]] && n_flag=(-n "$1")
    journalctl --user -u os-configs-sync.service "${n_flag[@]}" --no-pager
}

# --- Google Drive Backup Aliases ---
alias os-configs-gdrive-now='systemctl --user start os-configs-gdrive.service'
alias os-configs-gdrive-enable='systemctl --user enable --now os-configs-gdrive.timer'
alias os-configs-gdrive-disable='systemctl --user disable --now os-configs-gdrive.timer'
os-configs-gdrive-logs() {
    local n_flag=()
    [[ $# -gt 0 ]] && n_flag=(-n "$1")
    journalctl --user -u os-configs-gdrive.service "${n_flag[@]}" --no-pager
}

# --- General Framework Status ---
alias os-configs-status='systemctl --user list-timers --all "os-configs-*"'

# --- GPU Offload Aliases ---
alias nvidia-run='env __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only'

# --- Multi-Aspect Power & Thermal Profile Management ---
# 3 Available Profiles (defined in custom/power-profiles.conf):
#   1. 'quiet'       - Low-Power ACPI, 3300 MHz (No Boost), Power EPP
#   2. 'balanced'    - Balanced ACPI, 3500 MHz (Boost Enabled), Balance_Performance EPP
#   3. 'performance' - Performance ACPI, 3750 MHz (Sweet Spot), Balance_Performance EPP
alias mode-quiet='sudo /mnt/core/os-configs/user-configs/custom/bin/power-profile.sh quiet'
alias mode-balanced='sudo /mnt/core/os-configs/user-configs/custom/bin/power-profile.sh balanced'
alias mode-performance='sudo /mnt/core/os-configs/user-configs/custom/bin/power-profile.sh performance'
alias mode-status='/mnt/core/os-configs/user-configs/custom/bin/power-profile.sh status'
