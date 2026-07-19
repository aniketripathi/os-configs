
if [[ "$CUSTOM_PROFILE_INITIALIZED" = "yes" ]]; then
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
alias os-configs-sync-logs='journalctl --user -u os-configs-sync.service -n 20'

# Google Drive Backup Aliases
alias os-configs-gdrive-now='systemctl --user start os-configs-gdrive.service'
alias os-configs-gdrive-enable='systemctl --user enable --now os-configs-gdrive.timer'
alias os-configs-gdrive-disable='systemctl --user disable --now os-configs-gdrive.timer'
alias os-configs-gdrive-logs='journalctl --user -u os-configs-gdrive.service -n 20'

# General Status Alias
alias os-configs-status='systemctl --user list-timers --all "os-configs-*"'


CUSTOM_PROFILE_INITIALIZED="true"
