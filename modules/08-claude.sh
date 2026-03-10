#!/usr/bin/env bash
# 08-claude.sh - Claude Code installation and launcher setup
# Installs Claude Code CLI and deploys the tmux launcher script

set -euo pipefail

MODULE_NAME="claude"
MODULE_DESC="Claude Code CLI and launcher"

run_module() {
    log_step "Setting up Claude Code"

    # Install Claude Code CLI
    install_claude_code

    # Verify installation
    verify_claude_install

    # Deploy launcher script
    deploy_launcher

    log_success "Claude Code ready"
}

install_claude_code() {
    log_substep "Checking Claude Code CLI"

    # Claude Code native build installs per-user to ~/.local/bin/claude
    # Must check the actual file, not command_exists (which may find another user's binary via PATH)
    local claude_bin="$HOME/.local/bin/claude"

    if [[ -x "$claude_bin" ]]; then
        local version
        version=$("$claude_bin" --version 2>/dev/null | head -1) || version="installed"
        log_success "Claude Code already installed ($version)"
        return 0
    fi

    log_info "Installing Claude Code (native build, per-user)"

    if is_dry_run; then
        log_info "[DRY-RUN] Would install Claude Code via curl"
        return 0
    fi

    curl -fsSL https://claude.ai/install.sh | bash
    log_success "Claude Code installed to $claude_bin"
}

verify_claude_install() {
    log_substep "Verifying Claude Code installation"

    local claude_bin="$HOME/.local/bin/claude"

    if [[ ! -x "$claude_bin" ]]; then
        log_error "Claude Code binary not found at $claude_bin"
        return 1
    fi

    if is_dry_run; then
        log_info "[DRY-RUN] Would verify claude installation"
        return 0
    fi

    # Verify it's a native build (Mach-O binary, not a node/npm script)
    local file_type
    file_type=$(file "$claude_bin" 2>/dev/null) || true

    local version
    version=$("$claude_bin" --version 2>/dev/null | head -1) || version="unknown"

    if echo "$file_type" | grep -q "Mach-O"; then
        log_success "Claude Code verified: native build ($version)"
    elif echo "$file_type" | grep -q "ELF"; then
        log_success "Claude Code verified: native build ($version)"
    else
        log_warn "Claude Code installed ($version) but may not be native build"
        log_warn "Binary type: $file_type"
        log_warn "Run 'claude doctor' interactively to inspect"
    fi
}

deploy_launcher() {
    log_substep "Deploying claude.sh launcher"

    local src="$SCRIPT_DIR/claude.sh"
    local dest="$HOME/claude.sh"

    if [[ ! -f "$src" ]]; then
        log_warn "claude.sh not found at $src, skipping launcher deploy"
        return 0
    fi

    # Check if already deployed and up-to-date
    if [[ -f "$dest" ]] && diff -q "$src" "$dest" &>/dev/null; then
        log_success "claude.sh launcher already deployed"
        return 0
    fi

    if is_dry_run; then
        log_info "[DRY-RUN] Would copy claude.sh to $dest"
        return 0
    fi

    # Backup existing launcher if present
    if [[ -f "$dest" ]]; then
        backup_file "$dest" "existing claude.sh launcher"
    fi

    cp "$src" "$dest"
    chmod +x "$dest"
    log_success "claude.sh launcher deployed to $dest"
}

# Only run if executed directly
if [[ "${1:-}" == "--run" ]]; then
    run_module
fi
