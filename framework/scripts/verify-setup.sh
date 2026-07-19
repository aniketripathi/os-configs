#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# [1] Mount Points Verification
validate_mounts() {
    print_heading "[1] Mount Points Verification"
    for mnt in "$CORE_MNT" "$LIBRARY_MNT" "$TEMP_MNT"; do
        if findmnt "$mnt" >/dev/null; then
            report_ok "$mnt is mounted."
        else
            report_missing "$mnt is NOT mounted."
        fi
    done
    echo ""
}

# [2] Git Repository Verification
validate_git_repository() {
    print_heading "[2] Git Repository Verification"
    if git -C "$OS_CONFIGS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        report_ok "$OS_CONFIGS is a valid git repository."
        if git -C "$OS_CONFIGS" remote -v | grep -q "origin"; then
            report_ok "Git remote 'origin' is configured."
        else
            report_missing "Git remote 'origin' is NOT configured."
        fi
    else
        report_missing "$OS_CONFIGS is NOT a valid git repository."
    fi
    echo ""
}

# [3] Default Configs and Fstab Verification
validate_default_configs_and_fstab() {
    print_heading "[3] Default Configs and Fstab Verification"
    if [[ -f "$KEYS_DIR/identity.env" ]]; then
        report_ok "Identity configuration file exists at keys/identity.env."
    else
        report_missing "Identity configuration file NOT found at keys/identity.env."
    fi

    local git_name
    local git_email
    git_name=$(git config --global user.name || true)
    git_email=$(git config --global user.email || true)

    if [[ -n "$git_name" && -n "$git_email" ]]; then
        report_ok "Git global identity is set (Name: '${git_name}', Email: '${git_email}')."
    else
        report_missing "Git global identity is NOT configured."
    fi

    for rc_file in "${SHELL_RC_FILES[@]}"; do
        local is_relevant=false
        if [[ "$rc_file" == *".bashrc" || "$rc_file" == *".bash_profile" || "$rc_file" == *".bash_login" ]] && command -v bash >/dev/null 2>&1; then
            is_relevant=true
        elif [[ "$rc_file" == *".zshrc" || "$rc_file" == *".zprofile" ]] && command -v zsh >/dev/null 2>&1; then
            is_relevant=true
        elif [[ "$rc_file" == *".profile" ]]; then
            is_relevant=true
        fi

        if $is_relevant; then
            local file_name="${rc_file#$USER_HOME/}"
            if is_profile_sourced_in "$rc_file"; then
                report_ok "Custom profile sourcing is configured in ~/$file_name."
            else
                report_missing "Custom profile sourcing is NOT configured in ~/$file_name."
            fi
        fi
    done

    if [[ -f "/etc/fstab" ]]; then
        local missing_labels=0
        for mnt in "$CORE_MNT" "$LIBRARY_MNT" "$TEMP_MNT"; do
            local label="${mnt##*/}"
            if ! grep -E "^LABEL=${label}[[:space:]]" /etc/fstab >/dev/null; then
                missing_labels=$((missing_labels + 1))
            fi
        done
        if [[ $missing_labels -eq 0 ]]; then
            report_ok "fstab contains correct partitions labels."
        else
            report_missing "fstab is missing $missing_labels partition label configurations."
        fi
    else
        report_missing "/etc/fstab does not exist."
    fi
    echo ""
}

# [4] Comparing configs.
validate_restore_and_desktop() {
    print_heading "[4] Comparing configs."
    
    local restore_conf="$CONFIGS_DIR/restore.conf"
    if [[ ! -f "$restore_conf" ]]; then
        report_missing "restore.conf not found."
        echo ""
        return
    fi
    
    check_configs() {
        local section="$1"
        local base_path="$2"
        local prefix_label="$3"
        local repo_base="$HOME_CONFIGS"
        [[ "$section" == "system" ]] && repo_base="$SYSTEM_CONFIGS"
        [[ "$section" == "keys" ]] && repo_base="$KEYS_DIR"
        
        local files
        files=$(crudini --get "$restore_conf" "$section" || true)
        for f in $files; do
            [[ -z "$f" ]] && continue
            local repo_path="${repo_base}/${f}"
            local live_path="${base_path}/${f}"

            # Verify existence of keys directory if applicable
            if [[ "$section" == "keys" && -d "$repo_path" ]]; then
                if [[ ! -d "$live_path" ]]; then
                    print_status "MISSING" "Key directory ~/$f is missing"
                else
                    print_status "OK" "Key directory ~/$f exists"
                fi
            fi

            # Find files recursively in source if directory (ignoring known_hosts.old)
            local repo_files=()
            if [[ -d "$repo_path" ]]; then
                while IFS= read -r -d $'\0' file_item; do
                    repo_files+=("$file_item")
                done < <(get_relative_files "$repo_path")
            else
                repo_files+=("")
            fi

            for sub_file in "${repo_files[@]}"; do
                local check_repo="$repo_path"
                local check_live="$live_path"
                local check_label="$f"
                if [[ -n "$sub_file" ]]; then
                    local rel_path="${sub_file#./}"
                    check_repo="$repo_path/$rel_path"
                    check_live="$live_path/$rel_path"
                    check_label="$f/$rel_path"
                fi

                local display_path="$prefix_label/$check_label"
                display_path=$(echo "$display_path" | tr -s '/')
                check_live=$(echo "$check_live" | tr -s '/')

                if [[ ! -e "$check_live" ]]; then
                    print_status "MISSING" "$display_path"
                elif [[ ! -s "$check_live" ]]; then
                    print_status "DIFFERENT" "$display_path (file is empty)"
                elif [[ "$check_label" == *"/rclone.conf" ]]; then
                    print_status "OK" "$display_path (exists, content matching skipped)"
                else
                    local cmp_prefix=()
                    if [[ "$section" == "system" && $EUID -ne 0 && ! -r "$check_live" ]]; then
                        cmp_prefix=("sudo")
                    fi

                    local has_mismatch=false
                    if ! "${cmp_prefix[@]}" cmp -s "$check_repo" "$check_live"; then
                        has_mismatch=true
                    fi

                    if $has_mismatch; then
                        if [[ "$section" == "keys" ]]; then
                            print_status "DIFFERENT" "$display_path"
                        elif file -b --mime-type "$check_repo" | grep -q "^text/"; then
                            local diff_lines
                            diff_lines=$( ("${cmp_prefix[@]}" diff -u "$check_repo" "$check_live" || true) 2>/dev/null | grep -vE '^(\+\+\+|---)' | grep -c '^[+-]')
                            print_status "DIFFERENT" "$display_path" "(diff: $diff_lines lines)"
                        else
                            print_status "DIFFERENT" "$display_path" "(binary mismatch)"
                        fi
                    else
                        local perm_ok=true
                        if [[ "$section" == "keys" ]]; then
                            if [[ "$check_label" == *"/id_ed25519" ]]; then
                                local perm
                                perm=$(stat -c "%a" "$check_live" 2>/dev/null || true)
                                if [[ "$perm" != "600" ]]; then
                                    print_status "DIFFERENT" "$display_path (permissions: $perm, expected 600)"
                                    perm_ok=false
                                fi
                            elif [[ "$check_label" == *"/id_ed25519.pub" ]]; then
                                local perm
                                perm=$(stat -c "%a" "$check_live" 2>/dev/null || true)
                                if [[ "$perm" != "644" ]]; then
                                    print_status "DIFFERENT" "$display_path (permissions: $perm, expected 644)"
                                    perm_ok=false
                                fi
                            fi
                        fi
                        
                        if $perm_ok; then
                            print_status "OK" "$display_path"
                        fi
                    fi
                fi
            done
        done
    }

    echo "--- Home Configurations ---"
    check_configs "home" "$USER_HOME" "~"
    echo ""
    echo "--- System Configurations ---"
    check_configs "system" "/etc" "/etc"
    echo ""
    echo "--- Private Credentials & Keys ---"
    check_configs "keys" "$USER_HOME" "~"
    echo ""

    # Verify active SSH Agent and key load state (fixes exit code capture bug)
    local auth_sock="${SSH_AUTH_SOCK:-}"
    if [[ -z "$auth_sock" ]]; then
        local user_uid
        user_uid=$(id -u "$OWNER" 2>/dev/null || echo "1000")
        auth_sock=$(find "/tmp" "/run/user/$user_uid" -type s \( -name "agent.*" -o -name "ssh" -o -name "*ssh-agent*" \) -user "$OWNER" 2>/dev/null | head -n 1 || true)
    fi

    if [[ -n "$auth_sock" && -S "$auth_sock" ]]; then
        local key_list
        local exit_code=0
        key_list=$(run_as_owner env SSH_AUTH_SOCK="$auth_sock" ssh-add -l 2>/dev/null) || exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            local key_names
            key_names=$(echo "$key_list" | awk '{print $NF}' | xargs -n1 basename | paste -sd, - || echo "unknown")
            report_ok "SSH agent is running with loaded keys: $key_names"
        elif [[ $exit_code -eq 1 ]]; then
            report_missing "SSH agent is running but has no loaded keys."
        else
            report_missing "SSH agent is not running (failed to connect to socket $auth_sock)."
        fi
    else
        report_missing "SSH agent is not running (no active socket found)."
    fi
    echo ""
}

# [5] Snapper and GRUB Verification
validate_snapper_and_grub() {
    print_heading "[5] Snapper and GRUB Verification"
    
    local has_sudo=false
    if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
        has_sudo=true
    fi

    if command -v snapper >/dev/null 2>&1; then
        if $has_sudo; then
            local snapper_prefix=()
            [[ $EUID -ne 0 ]] && snapper_prefix=("sudo")
            if "${snapper_prefix[@]}" snapper list-configs 2>/dev/null | grep -q "root"; then
                report_ok "Snapper root configuration exists."
            else
                report_missing "Snapper root configuration does NOT exist."
            fi
        else
            report_skip "Snapper root configuration check (requires sudo/root privileges)."
        fi
    else
        report_missing "snapper command not found."
    fi

    if systemctl is-active grub-btrfs.path &>/dev/null; then
        report_ok "grub-btrfs path monitor is active."
    else
        report_missing "grub-btrfs path monitor is NOT active."
    fi

    if $has_sudo; then
        local grub_prefix=()
        [[ $EUID -ne 0 ]] && grub_prefix=("sudo")
        if "${grub_prefix[@]}" test -f "/boot/grub2/grub.cfg"; then
            if "${grub_prefix[@]}" grep -q "submenu" /boot/grub2/grub.cfg; then
                report_ok "Snapshot submenus are present in /boot/grub2/grub.cfg."
            else
                report_missing "Snapshot submenus NOT found in /boot/grub2/grub.cfg."
            fi
        else
            report_missing "/boot/grub2/grub.cfg does not exist."
        fi
    else
        report_skip "Snapshot submenus in /boot/grub2/grub.cfg check (requires sudo/root privileges)."
    fi
    echo ""
}

# [6] Rclone and Google Drive Mount Verification
validate_rclone() {
    print_heading "[6] Rclone and Google Drive Mount Verification"
    
    if findmnt "$GDRIVE_DIR" >/dev/null; then
        report_ok "$GDRIVE_DIR (rclone) is mounted."
    else
        report_skip "$GDRIVE_DIR is NOT mounted (optional cloud sync)."
    fi

    if [[ -f "/etc/fstab" ]]; then
        if ! grep -q "rclone" /etc/fstab; then
            report_missing "fstab: missing rclone gdrive mount configuration."
        elif ! grep -E "rclone.*nofail" /etc/fstab >/dev/null; then
            report_missing "fstab: rclone gdrive mount exists but is missing the 'nofail' option."
        else
            report_ok "fstab contains correct rclone mount options."
        fi
    fi
    echo ""
}

# [7] Automation Service Timers Verification
validate_timers() {
    print_heading "[7] Automation Service Timers Verification"
    if run_as_owner systemctl --user is-enabled os-configs-sync.timer &>/dev/null; then
        report_ok "os-configs-sync.timer is enabled."
    else
        report_skip "os-configs-sync.timer is disabled (optional)."
    fi

    if run_as_owner systemctl --user is-enabled os-configs-gdrive.timer &>/dev/null; then
        report_ok "os-configs-gdrive.timer is enabled (optional)."
    else
        report_skip "os-configs-gdrive.timer is disabled (optional)."
    fi
    echo ""
}

# [8] GPU and Secure Boot Key Enrollment Verification
validate_gpu_and_secure_boot() {
    print_heading "[8] GPU and Secure Boot Key Enrollment Verification"
    
    if lspci | grep -E -i "nvidia" >/dev/null; then
        if grep -q "^nvidia " /proc/modules; then
            report_ok "NVIDIA kernel drivers are loaded."
        else
            report_missing "NVIDIA drivers are NOT loaded (verify driver rebuild or secure boot enrollment)."
        fi
    else
        report_skip "No NVIDIA GPU detected on this system."
    fi

    if command -v mokutil >/dev/null 2>&1; then
        local sb_state
        sb_state=$(mokutil --sb-state || true)
        report_ok "Secure Boot state: $sb_state"
    else
        report_skip "mokutil command not found."
    fi
    echo ""
}

# [9] Packages Install/Uninstall Verification
validate_packages() {
    print_heading "[9] Packages Install/Uninstall Verification"
    local packages_conf="$CONFIGS_DIR/packages.conf"
    if [[ ! -f "$packages_conf" ]]; then
        report_missing "Packages configuration file not found."
        echo ""
        return
    fi
    
    local required_dnf
    local daily_dnf
    local dev_dnf
    required_dnf=$(crudini --get "$packages_conf" "required" || true)
    daily_dnf=$(crudini --get "$packages_conf" "daily-driver" || true)
    dev_dnf=$(crudini --get "$packages_conf" "development" || true)
    
    local all_dnf_packages
    all_dnf_packages="${required_dnf}"$'\n'"${daily_dnf}"$'\n'"${dev_dnf}"
    
    check_packages() {
        local packages="$1"
        local mode="$2"
        local check_cmd="$3"

        for pkg in $packages; do
            [[ -z "$pkg" ]] && continue
            if eval "$check_cmd \"\$pkg\"" &>/dev/null; then
                if [[ "$mode" == "install" ]]; then
                    print_status "OK" "DNF/Flatpak package $pkg is installed"
                else
                    print_status "DIFFERENT" "Unwanted package $pkg is still installed"
                fi
            else
                if [[ "$mode" == "install" ]]; then
                    print_status "MISSING" "DNF/Flatpak package $pkg is NOT installed"
                else
                    print_status "OK" "Unwanted package $pkg is uninstalled"
                fi
            fi
        done
    }

    echo "--- Installed Packages ---"
    check_packages "$all_dnf_packages" "install" "rpm -q"

    local daily_flat
    local dev_flat
    daily_flat=$(crudini --get "$packages_conf" "daily-driver-flatpak" || true)
    dev_flat=$(crudini --get "$packages_conf" "development-flatpak" || true)
    
    local all_flatpak_packages
    all_flatpak_packages="${daily_flat}"$'\n'"${dev_flat}"
    
    check_packages "$all_flatpak_packages" "install" "flatpak info"
    echo ""

    echo "--- Unwanted Packages ---"
    local uninstall_packages
    uninstall_packages=$(crudini --get "$packages_conf" "uninstall" || true)
    check_packages "$uninstall_packages" "uninstall" "rpm -q"
    echo ""
}

# --- Execution sequence ---
echo -e "\e[1;35m=== os-configs Diagnostic Verification ===\e[0m"
echo -e "\e[90mPhilosophy: Read-only report. Checks existence, status, and config templates sync.\e[0m"
echo ""

validate_mounts
validate_git_repository
validate_default_configs_and_fstab
validate_restore_and_desktop
validate_snapper_and_grub
validate_rclone
validate_timers
validate_gpu_and_secure_boot
validate_packages

echo -e "\e[1;35m=== Verification Summary ===\e[0m"
echo -e "\e[32m${ok_count} ok\e[0m, \e[31m${missing_count} missing\e[0m, \e[33m${skip_count} skipped\e[0m."

if [[ ${missing_count} -gt 0 ]]; then
    exit 1
fi
