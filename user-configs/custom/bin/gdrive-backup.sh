#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Load common library (automatically loads layout configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh"

# --- Execution sequence ---
BACKUP_ARCHIVE="os-configs.7z"
# Ensure Google Drive mount is active
if ! findmnt "$GDRIVE_DIR" >/dev/null 2>&1; then
    echo "Error: Google Drive is not mounted at $GDRIVE_DIR."
    run_as_owner notify-send "os-configs" "Google Drive is not mounted. Backup aborted." -u critical -i dialog-error || true
    exit 1
fi

echo "Compressing os-configs directory..."
run_as_owner mkdir -p "$GDRIVE_BACKUP_DIR"

# 7z update flags:
# -up0q3r2x2y2z1w2 instructs 7z to perform differential archiving:
#   p0: no action on files in archive only
#   q3: overwrite files newer in host (overwrite archive)
#   r2: compress files newer in archive than host
#   x2: skip files existing but newer in archive
#   y2: update files changed
#   z1: archive file attribute handling
#   w2: add files only in host (new files)
# -xr!*.git/, -xr!keys/, and -xr!backup/ excludes git tracking folder, private credentials vault, and local backup folder
if run_as_owner 7z u "$GDRIVE_BACKUP_DIR/$BACKUP_ARCHIVE" "$OS_CONFIGS" -up0q3r2x2y2z1w2 -xr!*.git/ -xr!keys/ -xr!backup/ -mx=5; then
    echo "GDrive backup complete: $GDRIVE_BACKUP_DIR/$BACKUP_ARCHIVE"
    run_as_owner notify-send "os-configs" "GDrive 7z Archive updated." -i dialog-information || true
else
    echo "Error: GDrive 7z Archive update failed."
    run_as_owner notify-send "os-configs" "GDrive 7z Archive update FAILED." -u critical -i dialog-error || true
    exit 1
fi
