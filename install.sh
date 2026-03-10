#!/usr/bin/env bash
# install.sh - Main entry point for setup-dev-mac
# Modular, idempotent Mac development environment setup

set -euo pipefail

# ============================================================================
# Script Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
VERSION="1.0.0"

# Proxy settings (required for network access behind firewall)
export ALL_PROXY="${ALL_PROXY:-http://127.0.0.1:7897}"
export HTTP_PROXY="${HTTP_PROXY:-http://127.0.0.1:7897}"
export HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:7897}"

# Default settings
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
SKIP_BACKUP="${SKIP_BACKUP:-false}"
AUTO_YES="${AUTO_YES:-false}"
UPDATE_BREW="${UPDATE_BREW:-true}"

# Module selection
SELECTED_MODULES=()
SKIP_MODULES=()

# ============================================================================
# Source Library Files
# ============================================================================

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/brew.sh"

# ============================================================================
# Help and Usage
# ============================================================================

print_usage() {
    cat << EOF
${BOLD}setup-dev-mac${RESET} v$VERSION
Modular, idempotent Mac development environment setup

${BOLD}USAGE:${RESET}
    $SCRIPT_NAME [OPTIONS]

${BOLD}OPTIONS:${RESET}
    -h, --help              Show this help message
    -v, --version           Show version
    -n, --dry-run           Show what would be done without making changes
    -y, --yes               Auto-accept all prompts
    --verbose               Enable verbose output
    --skip-backup           Skip backup of existing configurations
    --no-update             Don't update Homebrew

    --module=NAME           Run only specific module(s) (can be repeated)
    --skip=NAME             Skip specific module(s) (can be repeated)
    --list-modules          List available modules

    --restore=SESSION       Restore from a backup session
    --list-backups          List available backup sessions
    --detect                Run detection only and print summary

${BOLD}MODULES:${RESET}
    00-preflight            System checks and Xcode CLI
    01-homebrew             Homebrew package manager
    02-core-tools           Shell/Tmux tools (fzf, zsh plugins, oh-my-posh)
    02a-dev-tools           Optional dev tools (uv, node) - interactive
    03-zsh-base             Oh-My-Zsh installation
    04-zsh-plugins          Zsh plugin configuration
    05-oh-my-posh           Oh-My-Posh prompt theme
    06-tmux                 Tmux + Oh-My-Tmux + Solarized Dark
    07-fonts                Nerd Fonts installation
    99-finalize             Verification and summary

${BOLD}EXAMPLES:${RESET}
    # Full installation
    $SCRIPT_NAME

    # Dry run to see what would happen
    $SCRIPT_NAME --dry-run

    # Install only specific modules
    $SCRIPT_NAME --module=02-core-tools --module=06-tmux

    # Skip optional dev tools
    $SCRIPT_NAME --skip=02a-dev-tools

    # Restore from backup
    $SCRIPT_NAME --restore=20231215_143022

EOF
}

print_version() {
    echo "setup-dev-mac v$VERSION"
}

list_modules() {
    echo -e "\n${BOLD}Available Modules:${RESET}"
    for module in "$SCRIPT_DIR/modules/"*.sh; do
        local name
        name=$(basename "$module" .sh)
        # shellcheck source=/dev/null
        source "$module"
        echo -e "  ${CYAN}$name${RESET}"
        echo -e "    ${DIM}$MODULE_DESC${RESET}"
    done
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -v|--version)
                print_version
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            --no-update)
                UPDATE_BREW=false
                shift
                ;;
            --module=*)
                SELECTED_MODULES+=("${1#*=}")
                shift
                ;;
            --skip=*)
                SKIP_MODULES+=("${1#*=}")
                shift
                ;;
            --list-modules)
                list_modules
                exit 0
                ;;
            --restore=*)
                restore_backup "${1#*=}"
                exit $?
                ;;
            --list-backups)
                list_backups
                exit $?
                ;;
            --detect)
                print_detection_summary
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$SCRIPT_NAME --help' for usage"
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Module Execution
# ============================================================================

# Get list of modules to run (in order)
get_modules_to_run() {
    local modules=()

    # If specific modules selected, use those
    if [[ ${#SELECTED_MODULES[@]} -gt 0 ]]; then
        for mod in "${SELECTED_MODULES[@]}"; do
            local module_path="$SCRIPT_DIR/modules/$mod.sh"
            if [[ -f "$module_path" ]]; then
                modules+=("$module_path")
            else
                log_error "Module not found: $mod"
                exit 1
            fi
        done
    else
        # Run all modules in order
        for module in "$SCRIPT_DIR/modules/"*.sh; do
            modules+=("$module")
        done
    fi

    # Filter out skipped modules
    local filtered=()
    for module in "${modules[@]}"; do
        local name
        name=$(basename "$module" .sh)
        local skip=false

        # Only check SKIP_MODULES if it has elements
        if [[ ${#SKIP_MODULES[@]} -gt 0 ]]; then
            for skip_mod in "${SKIP_MODULES[@]}"; do
                if [[ "$name" == "$skip_mod" ]]; then
                    skip=true
                    break
                fi
            done
        fi

        if [[ "$skip" == "false" ]]; then
            filtered+=("$module")
        else
            log_debug "Skipping module: $name"
        fi
    done

    printf '%s\n' "${filtered[@]}"
}

execute_module() {
    local module_path="$1"
    local module_name
    module_name=$(basename "$module_path" .sh)

    log_debug "Loading module: $module_name"

    # Source the module (this loads its functions)
    # shellcheck source=/dev/null
    source "$module_path"

    # Run the module's run_module function
    run_module
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"

    # Print banner
    echo ""
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║                    setup-dev-mac v$VERSION                      ║${RESET}"
    echo -e "${BOLD}${CYAN}║         Modular Mac Development Environment Setup             ║${RESET}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    if is_dry_run; then
        echo -e "${YELLOW}>>> DRY RUN MODE - No changes will be made <<<${RESET}"
        echo ""
    fi

    # Initialize backup session
    init_backup_session

    # Get modules to run (bash 3.x compatible)
    local modules=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && modules+=("$line")
    done < <(get_modules_to_run)

    log_info "Running ${#modules[@]} module(s)"
    if [[ ${#modules[@]} -gt 0 ]]; then
        log_debug "Modules: ${modules[*]}"
    fi

    # Run each module
    for module in "${modules[@]}"; do
        execute_module "$module"
    done

    echo ""
    log_success "All modules completed!"
}

# Run main function
main "$@"
