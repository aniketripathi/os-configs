#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

_RESTORE_CONF="$SYNC_MANIFEST"
has_unallowed=false  # set by check_section_cleanliness, read in validate_restore_and_desktop

# ---------------------------------------------------------------------------
# Top-level helpers (formerly nested inside validate_restore_and_desktop)
# ---------------------------------------------------------------------------

# Compares files listed in a restore.conf section against their live counterparts.
# Args: section, live_base, prefix_label
check_section_configs() {
    local section="$1"
    local base_path="$2"
    local prefix_label="$3"
    local repo_base="$HOME_CONFIGS"
    [[ "$section" == "system" ]] && repo_base="$SYSTEM_CONFIGS"
    [[ "$section" == "keys"   ]] && repo_base="$KEYS_DIR"

    local files
    files=$(crudini --get "$_RESTORE_CONF" "$section" || true)

    for f in $files; do
        [[ -z "$f" ]] && continue
        local clean_f="${f%/}"
        local repo_path="${repo_base}/${clean_f}"
        local live_path="${base_path}/${clean_f}"

        if [[ "$section" == "keys" && -d "$repo_path" ]]; then
            if [[ ! -d "$live_path" ]]; then
                print_status "MISSING" "Key directory ~/$f is missing"
            else
                print_status "OK" "Key directory ~/$f exists"
            fi
        fi

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
            local check_label="$clean_f"
            if [[ -n "$sub_file" ]]; then
                local rel_path="${sub_file#./}"
                check_repo="$repo_path/$rel_path"
                check_live="$live_path/$rel_path"
                check_label="$clean_f/$rel_path"
            fi

            local display_path
            display_path=$(echo "$prefix_label/$check_label" | tr -s '/')
            check_live=$(echo "$check_live" | tr -s '/')

            if [[ ! -e "$check_live" ]]; then
                print_status "MISSING" "$display_path"
            elif [[ ! -s "$check_live" ]]; then
                print_status "DIFFERENT" "$display_path" "(file is empty)"
            elif [[ "$check_label" == *"/rclone.conf" ]]; then
                print_status "OK" "$display_path" "(exists, content matching skipped)"
            else
                local cmp_prefix=()
                if [[ "$section" == "system" && $EUID -ne 0 && ! -r "$check_live" ]]; then
                    cmp_prefix=("sudo")
                fi

                if ! "${cmp_prefix[@]}" cmp -s "$check_repo" "$check_live" 2>/dev/null; then
                    if [[ "$section" == "keys" ]]; then
                        print_status "DIFFERENT" "$display_path"
                    elif file -b --mime-type "$check_repo" | grep -q "^text/"; then
                        local diff_lines
                        diff_lines=$(("${cmp_prefix[@]}" diff -u "$check_repo" "$check_live" || true) 2>/dev/null \
                            | grep -vE '^(\+\+\+|---)' | grep -c '^[+-]' || echo 0)
                        print_status "DIFFERENT" "$display_path" "(diff: $diff_lines lines)"
                    else
                        print_status "DIFFERENT" "$display_path" "(binary mismatch)"
                    fi
                else
                    local perm_ok=true
                    if [[ "$section" == "keys" ]]; then
                        local perm
                        if [[ "$check_label" == *"/id_ed25519" && ! "$check_label" == *".pub" ]]; then
                            perm=$(stat -c "%a" "$check_live" 2>/dev/null || true)
                            if [[ "$perm" != "600" ]]; then
                                print_status "DIFFERENT" "$display_path" "(permissions: $perm, expected 600)"
                                perm_ok=false
                            fi
                        elif [[ "$check_label" == *"/id_ed25519.pub" ]]; then
                            perm=$(stat -c "%a" "$check_live" 2>/dev/null || true)
                            if [[ "$perm" != "644" ]]; then
                                print_status "DIFFERENT" "$display_path" "(permissions: $perm, expected 644)"
                                perm_ok=false
                            fi
                        fi
                    fi
                    $perm_ok && print_status "OK" "$display_path"
                fi
            fi
        done
    done
}

# Reports repo entries that are no longer referenced in restore.conf.
# Sets script-level has_unallowed=true when any are found.
# Args: section, repo_base, prefix_label
check_section_cleanliness() {
    local section="$1"
    local repo_base="$2"
    local prefix_label="$3"

    [[ ! -d "$repo_base" ]] && return 0

    declare -A allowed_map
    build_allowed_map "$section" allowed_map

    local repo_items=()
    while IFS= read -r -d $'\0' item; do
        repo_items+=("${item#./}")
    done < <(get_relative_items "$repo_base")

    for item in "${repo_items[@]}"; do
        [[ "$section" == "keys" && "$item" == "identity.env" ]] && continue
        if ! is_path_covered "$item" allowed_map; then
            print_status "DIFFERENT" "$prefix_label/$item" "(not listed in restore.conf)"
            has_unallowed=true
        fi
    done
}

# ---------------------------------------------------------------------------
# Verification sections
# ---------------------------------------------------------------------------

validate_mounts() {
    print_heading "[1] Mount Points Verification"
    for mnt in "$CORE_MNT" "$LIBRARY_MNT" "$TEMP_MNT"; do
        if findmnt "$mnt" > /dev/null; then
            report_ok "$mnt is mounted."
        else
            report_missing "$mnt is NOT mounted."
        fi
    done
    echo ""
}

validate_git_repository() {
    print_heading "[2] Git Repository Verification"
    if git_cmd -C "$OS_CONFIGS" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        report_ok "$OS_CONFIGS is a valid git repository."

        if git_cmd -C "$OS_CONFIGS" remote -v | grep -q "origin"; then
            report_ok "Git remote 'origin' is configured."
        else
            report_missing "Git remote 'origin' is NOT configured."
        fi

        # Uncommitted changes — categorised as new / updated / deleted
        local uncommitted new_count=0 updated_count=0 deleted_count=0
        uncommitted=$(git_cmd -C "$OS_CONFIGS" status --porcelain 2>/dev/null)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local x="${line:0:1}" y="${line:1:1}"
            if [[ "$x$y" == "??" || "$x" == "A" ]]; then
                (( new_count++ )) || true
            elif [[ "$x" == "D" || "$y" == "D" ]]; then
                (( deleted_count++ )) || true
            else
                (( updated_count++ )) || true
            fi
        done <<< "$uncommitted"

        if (( new_count + updated_count + deleted_count > 0 )); then
            report_different "Repository has uncommitted changes ($new_count new, $updated_count updated, $deleted_count deleted)."
        else
            report_ok "Working tree is clean, no uncommitted changes."
        fi

        # Ahead / behind remote
        local branch ahead behind
        branch=$(git_cmd -C "$OS_CONFIGS" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        if git_cmd -C "$OS_CONFIGS" fetch origin --quiet 2>/dev/null; then
            ahead=$(git_cmd -C "$OS_CONFIGS" rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo 0)
            behind=$(git_cmd -C "$OS_CONFIGS" rev-list --count "HEAD..origin/${branch}" 2>/dev/null || echo 0)
            if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
                report_missing "Branch '$branch' has diverged: $ahead ahead, $behind behind remote."
            elif [[ "$ahead" -gt 0 ]]; then
                report_missing "Local is $ahead commit(s) ahead of remote (unpushed)."
            elif [[ "$behind" -gt 0 ]]; then
                report_missing "Remote is $behind commit(s) ahead of local (not pulled)."
            else
                report_ok "Branch '$branch' is in sync with remote."
            fi
        else
            report_skip "Could not reach remote to check ahead/behind status."
        fi
    else
        report_missing "$OS_CONFIGS is NOT a valid git repository."
    fi
    echo ""
}

validate_default_configs_and_fstab() {
    print_heading "[3] Default Configs and Fstab Verification"
    if [[ -f "$KEYS_DIR/identity.env" ]]; then
        report_ok "Identity configuration file exists at keys/identity.env."
    else
        report_missing "Identity configuration file NOT found at keys/identity.env."
    fi

    local git_name git_email
    git_name=$(run_as_owner git config --global user.name || true)
    git_email=$(run_as_owner git config --global user.email || true)

    if [[ -n "$git_name" && -n "$git_email" ]]; then
        report_ok "Git global identity is set (Name: '${git_name}', Email: '${git_email}')."
    else
        report_missing "Git global identity is NOT configured."
    fi

    for rc_file in "${SHELL_RC_FILES[@]}"; do
        local is_relevant=false
        if [[ "$rc_file" == *".bashrc" || "$rc_file" == *".bash_profile" || "$rc_file" == *".bash_login" ]] && command -v bash > /dev/null 2>&1; then
            is_relevant=true
        elif [[ "$rc_file" == *".zshrc" || "$rc_file" == *".zprofile" ]] && command -v zsh > /dev/null 2>&1; then
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
            if ! grep -E "^LABEL=${label}[[:space:]]" /etc/fstab > /dev/null; then
                missing_labels=$((missing_labels + 1))
            fi
        done
        if [[ $missing_labels -eq 0 ]]; then
            report_ok "fstab contains correct partition labels."
        else
            report_missing "fstab is missing $missing_labels partition label configurations."
        fi
    else
        report_missing "/etc/fstab does not exist."
    fi
    echo ""
}

validate_restore_and_desktop() {
    print_heading "[4] Comparing configs."

    if [[ ! -f "$_RESTORE_CONF" ]]; then
        report_missing "restore.conf not found."
        echo ""
        return
    fi

    echo "--- Home Configurations ---"
    check_section_configs "home" "$USER_HOME" "~"
    echo ""
    echo "--- System Configurations ---"
    check_section_configs "system" "/etc" "/etc"
    echo ""
    echo "--- Private Credentials & Keys ---"
    check_section_configs "keys" "$USER_HOME" "~"
    echo ""

    echo "--- Repository Cleanliness ---"
    has_unallowed=false
    check_section_cleanliness "home"   "$HOME_CONFIGS"   "user-configs/home"
    check_section_cleanliness "system" "$SYSTEM_CONFIGS" "user-configs/system"
    check_section_cleanliness "keys"   "$KEYS_DIR"       "keys"
    $has_unallowed || report_ok "Repository folders are clean."
    echo ""

    local auth_sock="${SSH_AUTH_SOCK:-}"
    if [[ -z "$auth_sock" ]]; then
        local user_uid
        user_uid=$(id -u "$OWNER" 2>/dev/null || echo "1000")
        auth_sock=$(find "/tmp" "/run/user/$user_uid" -type s \( -name "agent.*" -o -name "ssh" -o -name "*ssh-agent*" \) -user "$OWNER" 2>/dev/null | head -n 1 || true)
    fi

    if [[ -n "$auth_sock" && -S "$auth_sock" ]]; then
        local key_list exit_code=0
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

validate_snapper_and_grub() {
    print_heading "[5] Snapper and GRUB Verification"

    local has_sudo=false
    [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null && has_sudo=true

    if command -v snapper > /dev/null 2>&1; then
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
        report_skip "Snapshot submenus check (requires sudo/root privileges)."
    fi
    echo ""
}

validate_rclone() {
    print_heading "[6] Rclone and Google Drive Mount Verification"

    if findmnt "$GDRIVE_DIR" > /dev/null; then
        report_ok "$GDRIVE_DIR (rclone) is mounted."
    else
        report_skip "$GDRIVE_DIR is NOT mounted (optional cloud sync)."
    fi

    if [[ -f "/etc/fstab" ]]; then
        if ! grep -q "rclone" /etc/fstab; then
            report_missing "fstab: missing rclone gdrive mount configuration."
        elif ! grep -E "rclone.*nofail" /etc/fstab > /dev/null; then
            report_missing "fstab: rclone gdrive mount exists but is missing the 'nofail' option."
        else
            report_ok "fstab contains correct rclone mount options."
        fi
    fi
    echo ""
}

validate_timers() {
    print_heading "[7] Automation Service Timers Verification"

    local systemctl_cmd=("systemctl" "--user")
    if [[ $EUID -eq 0 && -n "${OWNER:-}" && "$OWNER" != "root" ]]; then
        systemctl_cmd=("systemctl" "--user" "-M" "${OWNER}@")
    fi

    if "${systemctl_cmd[@]}" is-enabled os-configs-sync.timer &>/dev/null; then
        report_ok "os-configs-sync.timer is enabled."
    else
        report_skip "os-configs-sync.timer is disabled (optional)."
    fi

    if "${systemctl_cmd[@]}" is-enabled os-configs-gdrive.timer &>/dev/null; then
        report_ok "os-configs-gdrive.timer is enabled."
    else
        report_skip "os-configs-gdrive.timer is disabled (optional)."
    fi
    echo ""
}

validate_gpu_and_secure_boot() {
    print_heading "[8] GPU and Secure Boot Key Enrollment Verification"

    if lspci | grep -E -i "nvidia" > /dev/null; then
        if grep -q "^nvidia " /proc/modules; then
            report_ok "NVIDIA kernel drivers are loaded."
        else
            report_missing "NVIDIA drivers are NOT loaded (verify driver rebuild or secure boot enrollment)."
        fi
    else
        report_skip "No NVIDIA GPU detected on this system."
    fi

    if command -v mokutil > /dev/null 2>&1; then
        local sb_state
        sb_state=$(mokutil --sb-state || true)
        report_ok "Secure Boot state: $sb_state"
    else
        report_skip "mokutil command not found."
    fi
    echo ""
}

validate_packages() {
    print_heading "[9] Packages Install/Uninstall Verification"
    local packages_conf="$PACKAGES_CONF"
    if [[ ! -f "$packages_conf" ]]; then
        report_missing "Packages configuration file not found."
        echo ""
        return
    fi

    local required_dnf daily_dnf dev_dnf
    required_dnf=$(crudini --get "$packages_conf" "required"     || true)
    daily_dnf=$(crudini --get "$packages_conf"    "daily-driver" || true)
    dev_dnf=$(crudini --get "$packages_conf"      "development"  || true)

    local all_dnf_packages
    all_dnf_packages="${required_dnf}"$'\n'"${daily_dnf}"$'\n'"${dev_dnf}"

    check_packages() {
        local packages="$1" mode="$2" check_cmd="$3"
        for pkg in $packages; do
            [[ -z "$pkg" ]] && continue
            local is_installed=false
            if [[ "$check_cmd" == "rpm -q" ]]; then
                rpm -q "$pkg" &>/dev/null || command -v "$pkg" &>/dev/null && is_installed=true || true
            else
                eval "$check_cmd \"$pkg\"" &>/dev/null && is_installed=true || true
            fi
            if $is_installed; then
                [[ "$mode" == "install" ]] \
                    && print_status "OK"        "DNF/Flatpak package $pkg is installed" \
                    || print_status "DIFFERENT" "Unwanted package $pkg is still installed"
            else
                [[ "$mode" == "install" ]] \
                    && print_status "MISSING" "DNF/Flatpak package $pkg is NOT installed" \
                    || print_status "OK"      "Unwanted package $pkg is uninstalled"
            fi
        done
    }

    echo "--- Installed Packages ---"
    check_packages "$all_dnf_packages" "install" "rpm -q"

    local daily_flat dev_flat all_flatpak_packages
    daily_flat=$(crudini --get "$packages_conf" "daily-driver-flatpak" || true)
    dev_flat=$(crudini --get   "$packages_conf" "development-flatpak"  || true)
    all_flatpak_packages="${daily_flat}"$'\n'"${dev_flat}"
    check_packages "$all_flatpak_packages" "install" "flatpak info"
    echo ""

    echo "--- Unwanted Packages ---"
    local uninstall_packages
    uninstall_packages=$(crudini --get "$packages_conf" "uninstall" || true)
    check_packages "$uninstall_packages" "uninstall" "rpm -q"
    echo ""
}

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------
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
