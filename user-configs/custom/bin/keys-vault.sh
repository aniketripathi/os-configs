#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh"

# --- Defaults ---
DEFAULT_BACKUP_SRC="$KEYS_DIR"
DEFAULT_BACKUP_DEST="${GDRIVE_BACKUP_DIR}/security"   # directory; filename auto-generated
DEFAULT_RESTORE_DEST="$KEYS_DIR"
# No default for restore --src: user must supply the exact vault file

MODE=""
HINT=""
SRC=""
DEST=""

# --- Temp file (global so EXIT trap can always reach it) ---
_TMPFILE=""
trap '[[ -n "${_TMPFILE:-}" ]] && rm -f "$_TMPFILE"' EXIT

# --- Usage (single statement, shown on any error) ---
_usage() {
    echo "Usage: $(basename "$0") --backup  --hint <text> [--src <keys_dir>] [--dest <dir_or_file.vault>]"
    echo "       $(basename "$0") --restore --src <file.vault> [--dest <keys_dir>]"
    echo "Defaults: backup  --src $DEFAULT_BACKUP_SRC  --dest $DEFAULT_BACKUP_DEST/<keys-TIMESTAMP.vault>"
    echo "          restore --dest $DEFAULT_RESTORE_DEST  (--src is mandatory)"
    exit 1
}

# --- Parse arguments ---
[[ $# -eq 0 ]] && _usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup)  MODE="backup";  shift ;;
        --restore) MODE="restore"; shift ;;
        --hint)    HINT="$2";      shift 2 ;;
        --src)     SRC="$2";       shift 2 ;;
        --dest)    DEST="$2";      shift 2 ;;
        *)         _usage ;;
    esac
done

[[ -z "$MODE" ]]                        && _usage
[[ "$MODE" == "backup"  && -z "$HINT" ]] && _usage
[[ "$MODE" == "restore" && -z "$SRC"  ]] && _usage

# Apply defaults
if [[ "$MODE" == "backup" ]]; then
    SRC="${SRC:-$DEFAULT_BACKUP_SRC}"
    DEST="${DEST:-$DEFAULT_BACKUP_DEST}"
else
    DEST="${DEST:-$DEFAULT_RESTORE_DEST}"
fi

# --- Backup: $SRC (keys/) → 7z compress → openssl AES-256 encrypt → $DEST ---
#
# $DEST can be:
#   - A directory  → filename auto-generated as keys-TIMESTAMP.vault inside it
#   - A file path  → used directly as the output vault file
#
# Vault file format:
#   Line 1:  HINT:<hint text>\n          ← plaintext, always readable without password
#   Rest:    openssl AES-256-CBC blob    ← encrypted 7z archive of keys/
do_backup() {
    [[ ! -d "$SRC" ]] && { echo "Error: Source directory not found: $SRC"; exit 1; }

    # Resolve output archive path
    local archive
    if [[ "$DEST" == *.vault ]]; then
        archive="$DEST"
        mkdir -p "$(dirname "$archive")"
    else
        mkdir -p "$DEST"
        archive="$DEST/keys-$(date '+%Y%m%d_%H%M%S').vault"
    fi

    [[ -f "$archive" ]] && { echo "Error: Vault already exists: $archive"; exit 1; }

    local PASS PASS2
    read -rsp "Password: " PASS;  echo
    read -rsp "Confirm:  " PASS2; echo
    [[ "$PASS"  != "$PASS2" ]] && { echo "Error: Passwords do not match."; exit 1; }
    [[ -z "$PASS" ]]           && { echo "Error: Password cannot be empty."; exit 1; }

    local src_parent src_name
    src_parent=$(dirname "$SRC")
    src_name=$(basename "$SRC")
    # PID-based path: never pre-exists so 7z creates the archive fresh
    _TMPFILE="/tmp/keys-vault-$$.7z"

    echo "Compressing $SRC ..."
    # cd to parent so archive stores relative path: keys/... (not absolute)
    (cd "$src_parent" && 7z a -mx=5 "$_TMPFILE" "$src_name") > /dev/null

    echo "Encrypting..."
    # Write plaintext hint header, then append encrypted blob
    # Password passed via fd 3 — never appears in process list
    printf 'HINT:%s\n' "$HINT" > "$archive"
    openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
        -pass fd:3 -in "$_TMPFILE" 3<<<"$PASS" >> "$archive"

    rm -f "$_TMPFILE"; _TMPFILE=""
    chmod 600 "$archive"
    echo "Vault created: $archive"
    notify-send "os-configs" "Keys vault backup created." -i dialog-information 2>/dev/null || true
}

# --- Restore: $SRC (vault file) → openssl decrypt → 7z extract → $DEST (keys dir) ---
#
# $SRC must be a vault file path.
# $DEST is the directory where keys/ will land (extraction goes to its parent).
#
# Reads plaintext hint from Line 1 BEFORE asking for password, so user knows
# which password to use regardless of how many attempts are needed.
do_restore() {
    [[ ! -f "$SRC" ]] && { echo "Error: Vault file not found: $SRC"; exit 1; }

    # Read and display plaintext hint header — no password required
    local hint_line hint header_bytes
    hint_line=$(head -1 "$SRC")
    hint="${hint_line#HINT:}"
    header_bytes=$(printf '%s\n' "$hint_line" | wc -c)

    echo "Vault: $(basename "$SRC")"
    echo "Hint:  $hint"

    # Ask for password AFTER showing the hint
    local PASS
    read -rsp "Password: " PASS; echo
    [[ -z "$PASS" ]] && { echo "Error: Password cannot be empty."; exit 1; }

    # Extract to parent of $DEST so that keys/ lands exactly at $DEST
    local dest_parent
    dest_parent=$(dirname "$DEST")
    # PID-based path: never pre-exists so openssl writes a fresh file
    _TMPFILE="/tmp/keys-vault-$$.7z"

    # Refuse to overwrite an existing destination
    [[ -d "$DEST" ]] && { echo "Error: Destination already exists: $DEST"; exit 1; }

    echo "Decrypting..."
    # Skip plaintext hint header, pipe remaining encrypted blob to openssl
    # Password passed via fd 3 — never appears in process list
    if ! tail -c "+$((header_bytes + 1))" "$SRC" | \
        openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
        -pass fd:3 3<<<"$PASS" > "$_TMPFILE"; then
        echo "Error: Decryption failed. Wrong password?"
        exit 1
    fi

    if ! 7z x "$_TMPFILE" -o"$dest_parent/" > /dev/null; then
        echo "Error: Archive extraction failed."
        exit 1
    fi

    rm -f "$_TMPFILE"; _TMPFILE=""
    echo "Keys restored to: $DEST"
    notify-send "os-configs" "Keys vault restored." -i dialog-information 2>/dev/null || true
}

# --- Main ---
case "$MODE" in
    backup)  do_backup ;;
    restore) do_restore ;;
esac
