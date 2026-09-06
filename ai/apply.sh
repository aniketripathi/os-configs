#!/bin/bash

# ==============================================================================
# CONSTANTS
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SOURCE_HOOKS_FILE="$SCRIPT_DIR/hooks.json"

# Text Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================
show_help() {
    echo -e "${GREEN}Usage:${NC} $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --agy                 Apply Antigravity (AGY) configurations globally (~/.gemini/config)."
    echo "  -h, --help            Show this help message."
    echo ""
}

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Please install jq first."
        exit 1
    fi
}

# ==============================================================================
# CORE LOGIC
# ==============================================================================
apply_agy() {
    # Default global target directory for Antigravity (AGY)
    local target_dir="$HOME/.gemini/config"
    local target_hooks_file="$target_dir/hooks.json"
    
    log_info "Applying AGY configuration to: $target_dir"
    mkdir -p "$target_dir"
    
    # Critical: Target hooks.json needs absolute paths so it can find the scripts from anywhere.
    # Replace relative "./scripts" with the absolute path to our scripts directory dynamically.
    local tmp_source=$(mktemp)
    sed "s|\./scripts|$SCRIPT_DIR/scripts|g" "$SOURCE_HOOKS_FILE" > "$tmp_source"
    
    if [ ! -f "$target_hooks_file" ]; then
        log_info "No existing hooks.json found. Creating new one at $target_hooks_file"
        cp "$tmp_source" "$target_hooks_file"
        rm -f "$tmp_source"
        return
    fi

    # File exists, perform smart JSON merge
    local existing_hooks=$(jq -r 'keys[]' "$target_hooks_file" 2>/dev/null)
    local new_hooks=$(jq -r 'keys[]' "$tmp_source" 2>/dev/null)

    # Output detailed feedback on what is being updated vs added
    for hook in $new_hooks; do
        if echo "$existing_hooks" | grep -q "^${hook}$"; then
            log_info "Hook '${hook}' already exists in target; updating."
        else
            log_info "Hook '${hook}' not found in target; adding."
        fi
    done

    # jq -s '.[0] * .[1]' performs a recursive merge, with the second file taking precedence
    local tmp_merged=$(mktemp)
    if jq -s '.[0] * .[1]' "$target_hooks_file" "$tmp_source" > "$tmp_merged"; then
        mv "$tmp_merged" "$target_hooks_file"
        log_info "Successfully merged hooks.json!"
    else
        log_error "Failed to merge JSON files."
        rm -f "$tmp_merged"
        rm -f "$tmp_source"
        exit 1
    fi
    
    rm -f "$tmp_source"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
main() {
    check_dependencies
    
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --agy)
                apply_agy
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main "$@"
