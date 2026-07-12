#!/bin/sh
# Custom profile — sourced by .bashrc/.zshrc/.profile

# SSH agent via keychain
if command -v keychain >/dev/null 2>&1; then
    eval $(keychain --eval --quiet id_ed25519)
fi

# Load custom bin directory containing utility scripts (e.g. gpu-switch)
export PATH="/mnt/core/os-configs/user-configs/custom/bin:$PATH"

# Convenient mounts environment variables
export CORE="/mnt/core"
export LIBRARY="/mnt/library"
export TEMP="/mnt/temp"

# os-configs aliases for weekly sync, timers, and service operations
alias os-configs-backup-now='systemctl --user start os-configs-sync.service'
alias os-configs-status='systemctl --user list-timers "os-configs-*"'
alias os-configs-logs='journalctl --user -u os-configs-sync.service -n 20'
alias os-configs-disable='systemctl --user disable --now os-configs-sync.timer'
alias os-configs-enable='systemctl --user enable --now os-configs-sync.timer'
alias os-configs-gdrive-now='systemctl --user start os-configs-gdrive.service'
