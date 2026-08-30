
if [[ "$CUSTOM_PROFILE_INITIALIZED" == "yes" ]]; then
    return 0
fi

umask 027


export PATH="/mnt/core/os-configs/user-configs/custom/bin:$PATH"

export CORE="/mnt/core"
export LIBRARY="/mnt/library"
export TEMP="/mnt/temp"

# Git Repository Sync Aliases
alias os-configs-sync-now='systemctl --user start os-configs-sync.service'
alias os-configs-sync-enable='systemctl --user enable --now os-configs-sync.timer'
alias os-configs-sync-disable='systemctl --user disable --now os-configs-sync.timer'
os-configs-sync-logs() {
    local n_flag=()
    [[ $# -gt 0 ]] && n_flag=(-n "$1")
    journalctl --user -u os-configs-sync.service "${n_flag[@]}" --no-pager
}

# Google Drive Backup Aliases
alias os-configs-gdrive-now='systemctl --user start os-configs-gdrive.service'
alias os-configs-gdrive-enable='systemctl --user enable --now os-configs-gdrive.timer'
alias os-configs-gdrive-disable='systemctl --user disable --now os-configs-gdrive.timer'
os-configs-gdrive-logs() {
    local n_flag=()
    [[ $# -gt 0 ]] && n_flag=(-n "$1")
    journalctl --user -u os-configs-gdrive.service "${n_flag[@]}" --no-pager
}

# General Status Alias
alias os-configs-status='systemctl --user list-timers --all "os-configs-*"'

# GPU Offload Aliases
alias nvidia-run='env __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only'
alias amd-run='env DRI_PRIME=0'

# Disable PackageKit command-not-found search delay on mistyped commands
unset -f command_not_found_handle 2>/dev/null
unset -f command_not_found_handler 2>/dev/null

CUSTOM_PROFILE_INITIALIZED="yes"

