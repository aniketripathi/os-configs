#!/bin/bash
# Sync configurations archive directly to local GDrive partition using 7z update mode

set -euo pipefail
IFS=$'\n\t'

source "/mnt/core/os-configs/framework/configs/reinstall.env"

# Ensure Google Drive remote is actually mounted before writing to directory
if ! findmnt "$GDRIVE_DIR" >/dev/null 2>&1; then
    echo "Error: Google Drive is not mounted at $GDRIVE_DIR."
    notify-send "os-configs" "Google Drive is not mounted. Backup aborted." -u critical -i dialog-error 2>/dev/null || true
    exit 1
fi

echo "Compressing os-configs directory..."
mkdir -p "$GDRIVE_BACKUP_DIR"

# Update flag details:
# -u: update options.
# -up0q3r2x2y2z1w2: updates archive selectively (updates existing/appends new/deletes removed)
# -xr!*.git/ -xr!keys/: excludes git index and sensitive keys/credentials
if 7z u "$GDRIVE_BACKUP_DIR/$BACKUP_ARCHIVE" "$OS_CONFIGS" -up0q3r2x2y2z1w2 -xr!*.git/ -xr!keys/ -mx=5; then
    echo "GDrive backup complete: $GDRIVE_BACKUP_DIR/$BACKUP_ARCHIVE"
    notify-send "os-configs" "GDrive 7z Archive updated." -i dialog-information 2>/dev/null || true
else
    echo "Error: GDrive 7z Archive update failed."
    notify-send "os-configs" "GDrive 7z Archive update FAILED." -u critical -i dialog-error 2>/dev/null || true
    exit 1
fi
