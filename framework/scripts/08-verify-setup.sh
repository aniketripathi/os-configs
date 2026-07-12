#!/bin/bash
# 08-verify-setup.sh — Read-only diagnostic verification suite

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

# Parse command line options
CHECK_DEV=false
for arg in "${@:-}"; do
    if [[ "$arg" == "--dev" ]]; then
        CHECK_DEV=true
    fi
done

echo "=== os-configs Diagnostic Verification ==="
echo "Philosophy: Read-only report. Checks existence/status, not content diffs."
echo ""

ok_count=0
missing_count=0
skip_count=0

function report_ok() {
    echo -e "\e[32m[OK]\e[0m $1"
    ok_count=$((ok_count + 1))
}

function report_missing() {
    echo -e "\e[31m[MISSING]\e[0m $1"
    missing_count=$((missing_count + 1))
}

function report_skip() {
    echo -e "\e[33m[SKIP]\e[0m $1"
    skip_count=$((skip_count + 1))
}

# ----------------- 1. MOUNTS -----------------
echo "[1] Mount Points Verification"
for mnt in "/mnt/core" "/mnt/library" "/mnt/temp"; do
    if findmnt "$mnt" >/dev/null; then
        report_ok "$mnt is mounted."
    else
        report_missing "$mnt is NOT mounted."
    fi
done

if findmnt "/mnt/core/gdrive" >/dev/null; then
    report_ok "/mnt/core/gdrive (rclone) is mounted."
else
    report_skip "/mnt/core/gdrive is NOT mounted (optional cloud sync)."
fi
echo ""

# ----------------- 2. GIT -----------------
echo "[2] Git Repository Verification"
if git -C "$OS_CONFIGS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    report_ok "$OS_CONFIGS is a valid git repository."
    if git -C "$OS_CONFIGS" remote -v | grep -q "origin"; then
        report_ok "Git remote 'origin' is configured."
    else
        report_missing "Git remote 'origin' is NOT configured."
    fi
    
    # Informational check for dirty/clean status
    if [[ -z "$(git -C "$OS_CONFIGS" status --porcelain)" ]]; then
        echo "    (Info: Working directory is clean)"
    else
        echo "    (Info: Working directory has uncommitted modifications)"
    fi
else
    report_missing "$OS_CONFIGS is NOT a valid git repository."
fi
echo ""

# ----------------- 3. IDENTITY -----------------
echo "[3] Git Identity Verification"
if [[ -f "$IDENTITY_ENV" ]]; then
    report_ok "Identity configuration file exists at $IDENTITY_ENV."
    
    # Check if git configs are applied globally
    active_name=$(git config --global user.name || true)
    active_email=$(git config --global user.email || true)
    
    if [[ -n "$active_name" && -n "$active_email" && "$active_name" != "<user-name>" && "$active_email" != "<email>" ]]; then
        report_ok "Git global identity is set (Name: '$active_name', Email: '$active_email')."
    else
        report_missing "Git global identity is unset or contains defaults."
    fi
else
    report_missing "Identity configuration $IDENTITY_ENV does not exist."
fi
echo ""

# ----------------- 4. SSH & KEYCHAIN -----------------
echo "[4] SSH Keys and Keychain agent"
if ls "$HOME/.ssh/id_ed25519" &>/dev/null && ls "$HOME/.ssh/id_ed25519.pub" &>/dev/null; then
    report_ok "SSH key pair (id_ed25519) exists in ~/.ssh/."
else
    report_missing "SSH key pair (id_ed25519) is missing from ~/.ssh/."
fi

# Check if keychain has set up ssh-agent and created the session files
if pgrep -u "$USER" ssh-agent >/dev/null && ls "$HOME/.keychain/"*"-sh" &>/dev/null; then
    report_ok "Keychain SSH agent is running and active."
else
    report_missing "Keychain SSH agent is NOT running."
fi
echo ""

# ----------------- 5. SNAPPER -----------------
echo "[5] Snapper Subvolume Snapshots"
if command -v snapper >/dev/null 2>&1; then
    if snapper list-configs | grep -q "root"; then
        report_ok "Snapper root configuration exists."
        
        # Verify weekly snapper limits
        weekly_limit=$(sudo snapper -c root get-config 2>/dev/null | awk '$1 == "TIMELINE_LIMIT_WEEKLY" {print $3}' || true)
        if [[ "$weekly_limit" == "2" ]]; then
            report_ok "Snapper timeline weekly limit is optimized (Weekly=2)."
        else
            report_missing "Snapper timeline weekly limit is '$weekly_limit' (expected: 2)."
        fi
    else
        report_missing "Snapper root configuration does NOT exist."
    fi
else
    report_missing "snapper command not found."
fi
echo ""

# ----------------- 6. GRUB -----------------
echo "[6] GRUB Configurations"
if systemctl is-active grub-btrfs.path &>/dev/null; then
    report_ok "grub-btrfs path monitor is active."
else
    report_missing "grub-btrfs path monitor is NOT active."
fi

if sudo test -f "/boot/grub2/grub.cfg"; then
    if sudo grep -q "submenu" /boot/grub2/grub.cfg; then
        report_ok "Snapshot submenus are present in /boot/grub2/grub.cfg."
    else
        report_missing "Snapshot submenus NOT found in /boot/grub2/grub.cfg (Reboot 2 required or grub-btrfs not run)."
    fi
else
    report_missing "/boot/grub2/grub.cfg does not exist."
fi
echo ""

# ----------------- 7. PACKAGES (conf vs installed) -----------------
echo "[7] Packages Installation Check"
packages_conf="$CONFIGS_DIR/packages.conf"
if [[ -f "$packages_conf" ]]; then
    # Parse required, daily driver, and optionally development DNF packages
    if $CHECK_DEV; then
        all_dnf_packages=$(awk '/^\[required\]|^\[daily-driver\]|^\[development\]/ {flag=1; next} /^\[/ {flag=0} flag && NF && !/^#/ {print $1}' "$packages_conf")
    else
        all_dnf_packages=$(awk '/^\[required\]|^\[daily-driver\]/ {flag=1; next} /^\[/ {flag=0} flag && NF && !/^#/ {print $1}' "$packages_conf")
    fi
    
    dnf_missing=0
    for pkg in $all_dnf_packages; do
        # Exclude snapper and grub-btrfs from package list check because they are bootstrap packages
        if [[ "$pkg" == "snapper" || "$pkg" == "grub-btrfs" ]]; then
            continue
        fi
        if ! rpm -q "$pkg" &>/dev/null; then
            echo "    (Missing package: $pkg)"
            dnf_missing=$((dnf_missing + 1))
        fi
    done
    
    if [[ $dnf_missing -eq 0 ]]; then
        if $CHECK_DEV; then
            report_ok "All required/daily-driver/development DNF packages are installed."
        else
            report_ok "All required/daily-driver DNF packages are installed."
        fi
    else
        if $CHECK_DEV; then
            report_missing "$dnf_missing DNF packages from packages.conf (including [development]) are not installed."
        else
            report_missing "$dnf_missing DNF packages from packages.conf (excluding [development]) are not installed."
        fi
    fi

    # Parse Flatpak packages
    all_flatpak_packages=$(awk '/^\[daily-driver-flatpak\]|^\[development-flatpak\]/ {flag=1; next} /^\[/ {flag=0} flag && NF && !/^#/ {print $1}' "$packages_conf")
    
    flatpak_missing=0
    for flat in $all_flatpak_packages; do
        if ! flatpak info "$flat" &>/dev/null; then
            echo "    (Missing Flatpak: $flat)"
            flatpak_missing=$((flatpak_missing + 1))
        fi
    done

    if [[ $flatpak_missing -eq 0 ]]; then
        report_ok "All Flatpak packages are installed."
    else
        report_missing "$flatpak_missing Flatpak packages from packages.conf are not installed."
    fi

    # Parse Uninstall list (verify they are absent)
    uninstall_packages=$(awk '/^\[uninstall\]/ {flag=1; next} /^\[/ {flag=0} flag && NF && !/^#/ {print $1}' "$packages_conf" || true)
    uninstall_installed=0
    for upkg in $uninstall_packages; do
        if rpm -q "$upkg" &>/dev/null; then
            echo "    (Bloatware still installed: $upkg)"
            uninstall_installed=$((uninstall_installed + 1))
        fi
    done

    if [[ $uninstall_installed -eq 0 ]]; then
        report_ok "All listed bloatware packages are successfully uninstalled."
    else
        report_missing "$uninstall_installed bloatware packages from packages.conf are still present."
    fi
else
    report_missing "packages.conf not found."
fi
echo ""

# ----------------- 8. CONFIGS RESTORE -----------------
echo "[8] Configuration Restoration Target Check"
restore_conf="$CONFIGS_DIR/restore.conf"
if [[ -f "$restore_conf" ]]; then
    home_configs=$(awk '/^\[home\]/ {flag=1; next} /^\[/ {flag=0} flag && NF && !/^#/ {print $1}' "$restore_conf")
    system_configs=$(awk '/^\[system\]/ {flag=1; next} /^\[/ {flag=0} flag && NF && !/^#/ {print $1}' "$restore_conf")
    
    config_missing=0
    for hf in $home_configs; do
        if [[ ! -s "$HOME/$hf" ]]; then
            echo "    (Home config missing/empty: ~/$hf)"
            config_missing=$((config_missing + 1))
        fi
    done

    for sf in $system_configs; do
        if [[ ! -s "/etc/$sf" ]]; then
            echo "    (System config missing/empty: /etc/$sf)"
            config_missing=$((config_missing + 1))
        fi
    done

    if [[ $config_missing -eq 0 ]]; then
        report_ok "All mapped configuration files are deployed and non-empty."
    else
        report_missing "$config_missing configuration files are missing or empty on the system."
    fi
else
    report_missing "restore.conf not found."
fi
echo ""

# ----------------- 9. POWER CONFIG -----------------
echo "[9] KDE Power Settings"
power_file="$HOME/.config/powerdevilrc"
if [[ -f "$power_file" ]]; then
    if grep -q "DimDisplayWhenIdle=true" "$power_file" && grep -q "DimDisplayWhenIdleTimeoutSec=600" "$power_file"; then
        report_ok "KDE Powerdevil AC profile matches optimized timeline configurations."
    else
        report_missing "KDE Powerdevil timeline profiles deviate or are missing keys."
    fi
else
    report_missing "powerdevilrc config does not exist at ~/.config/powerdevilrc."
fi
echo ""

# ----------------- 10. GPU SWITCH -----------------
echo "[10] Default GPU Configuration"
gpu_env_file="$HOME/.config/environment.d/10-default-gpu.conf"
if [[ -f "$gpu_env_file" ]]; then
    report_ok "GPU environment config exists at ~/.config/environment.d/10-default-gpu.conf."
    if command -v gpu-switch >/dev/null 2>&1; then
        report_ok "gpu-switch utility is present on the PATH."
        if active_gpu=$(gpu-switch status 2>/dev/null); then
            report_ok "Active GPU config: $active_gpu"
        else
            report_missing "gpu-switch status query failed."
        fi
    elif [[ -x "$HOME/.local/bin/gpu-switch" ]]; then
        report_ok "gpu-switch utility is present at ~/.local/bin/gpu-switch."
        if active_gpu=$( "$HOME/.local/bin/gpu-switch" status 2>/dev/null ); then
            report_ok "Active GPU config: $active_gpu"
        else
            report_missing "gpu-switch status query failed."
        fi
    else
        report_missing "gpu-switch utility is NOT on the PATH or ~/.local/bin/."
    fi
else
    report_missing "GPU environment configuration file is missing."
fi
echo ""

# ----------------- 11. TIMERS -----------------
echo "[11] Automation Service Timers"
if systemctl --user is-enabled os-configs-sync.timer &>/dev/null; then
    report_ok "os-configs-sync.timer is enabled."
else
    report_missing "os-configs-sync.timer is disabled."
fi

if systemctl --user is-enabled os-configs-gdrive.timer &>/dev/null; then
    report_ok "os-configs-gdrive.timer is enabled (optional)."
else
    report_skip "os-configs-gdrive.timer is disabled (optional)."
fi
echo ""

# ----------------- 12. FSTAB -----------------
echo "[12] Fstab Labels & Rclone mounts"
if [[ -f "/etc/fstab" ]]; then
    fstab_missing=0
    for label in "core" "library" "temp"; do
        if ! grep -q "LABEL=$label" /etc/fstab; then
            echo "    (fstab: missing label $label)"
            fstab_missing=$((fstab_missing + 1))
        fi
    done
    
    if ! grep -q "rclone" /etc/fstab; then
        echo "    (fstab: missing rclone gdrive mount)"
        fstab_missing=$((fstab_missing + 1))
    fi

    if [[ $fstab_missing -eq 0 ]]; then
        report_ok "fstab contains correct partitions labels and gdrive rclone mount configurations."
    else
        report_missing "$fstab_missing fstab partition/mount lines are missing."
    fi
else
    report_missing "/etc/fstab does not exist."
fi
echo ""

# ----------------- SUMMARY -----------------
echo "=== Verification Summary ==="
echo -e "$ok_count ok, $missing_count missing, $skip_count skipped."
