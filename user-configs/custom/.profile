#!/bin/sh
# Custom profile — sourced by .bashrc/.zshrc/.profile
# WARNING: Sourced by graphical login shells (non-interactive).
# ONLY place non-blocking, error-handling configurations here.
# Any interactive prompts or blocking processes will freeze the boot/login sequence.

# Prevent double loading of custom profile
if [ "${CUSTOM_PROFILE_INITIALIZED:-0}" -eq 1 ]; then
    return 0
fi
export CUSTOM_PROFILE_INITIALIZED=1

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
