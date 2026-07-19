#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Ensure script is run with sudo/root
require_root
FSTAB="/etc/fstab"
mount_paths=("$CORE_MNT" "$LIBRARY_MNT" "$TEMP_MNT")

# --- Execution sequence ---
echo "=== Reconciling /etc/fstab with layout mounts ==="
echo ""

error_count=0

for mount_path in "${mount_paths[@]}"; do
    # Convention: partition LABEL must equal the mount directory basename (e.g. LABEL=core -> /mnt/core)
    label="${mount_path##*/}"

    echo "[Mount]  ${mount_path}  (expects LABEL=${label})"

    # Check if a block partition with the given LABEL exists
    if ! lsblk -o LABEL --noheadings 2>/dev/null | grep -qx "$label"; then
        echo "  ERROR: No block device with LABEL=${label} found on this machine."
        echo "         Create and label the partition first, then re-run this script."
        error_count=$((error_count + 1))
        echo ""
        continue
    fi

    # Create mount directory if missing (inherits umask 027)
    if [[ ! -d "$mount_path" ]]; then
        echo "  Creating mount directory: ${mount_path}"
        mkdir -p "$mount_path"
        chown "${OWNER}:${OWNER}" "$mount_path"
    fi

    # Update or add entry in fstab
    # Note: Assumes ext4 data partitions as documented in README Section 1
    if grep -qE "^LABEL=${label}[[:space:]]" "$FSTAB"; then
        existing_mount=$(awk -v lbl="LABEL=${label}" '$1 == lbl { print $2; exit }' "$FSTAB" || true)
        if [[ "$existing_mount" == "$mount_path" ]]; then
            echo "  OK: fstab entry already correct."
        else
            echo "  Mount point changed: ${existing_mount} -> ${mount_path}"
            sed -i -E "s|^(LABEL=${label}[[:space:]]+)[^[:space:]]+|\1${mount_path}|" "$FSTAB"
        fi
    else
        echo "  Adding fstab entry: LABEL=${label} -> ${mount_path}"
        echo "LABEL=${label} ${mount_path} ext4 defaults,noatime 0 2" >> "$FSTAB"
    fi
    echo ""
done

if [[ $error_count -gt 0 ]]; then
    echo "ERROR: ${error_count} partition(s) could not be configured. Skipping mount -a."
    exit 1
fi

echo "Reloading systemd and mounting all fstab entries..."
systemctl daemon-reload
mount -a

echo ""
echo "=== Mount Verification ==="
all_ok=true
for mount_path in "${mount_paths[@]}"; do
    if findmnt "$mount_path" > /dev/null 2>&1; then
        echo -e "  \e[32m[OK]\e[0m  ${mount_path} is mounted."
    else
        echo -e "  \e[31m[FAIL]\e[0m ${mount_path} is NOT mounted."
        all_ok=false
    fi
done

echo ""
if $all_ok; then
    echo "All declared mount points are active."
else
    echo "Warning: Some mount points are not mounted. Check dmesg or journalctl."
    exit 1
fi
