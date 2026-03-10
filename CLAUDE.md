# CLAUDE.md - mac-dev-setup

Modular, idempotent Mac development environment configuration scripts.
Multi-user setup via shared Homebrew (`developer` group) + per-user dotfiles.

## Quick Start

```bash
# Preview what will happen (dry-run)
./install.sh --dry-run

# Full installation (current user)
./install.sh

# Install specific modules only
./install.sh --module=02-core-tools --module=06-tmux

# Install for another developer user (admin runs this)
sudo -u <username> -H bash -c \
  'export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH && \
   export HOMEBREW_NO_AUTO_UPDATE=1 && \
   bash /path/to/install.sh --yes --no-update'
```

## Project Structure

```
mac-dev-setup/
├── install.sh                 # Main entry point (has proxy config)
├── claude.sh                  # Claude Code tmux launcher (deployed to ~/claude.sh)
├── setup-developers.sh        # macOS user/group creation (sudo required)
├── lib/                       # Shared libraries
│   ├── common.sh              # Logging, colors, utilities
│   ├── detect.sh              # Tool/config detection
│   ├── backup.sh              # Backup/restore functionality
│   └── brew.sh                # Homebrew helpers
├── modules/                   # Installation modules (run in order)
│   ├── 00-preflight.sh        # System checks, Xcode CLI
│   ├── 01-homebrew.sh         # Homebrew installation
│   ├── 02-core-tools.sh       # tmux, fzf, zsh plugins, oh-my-posh
│   ├── 02a-dev-tools.sh       # Optional: uv, node (interactive)
│   ├── 03-zsh-base.sh         # Oh-My-Zsh + zshrc template deploy
│   ├── 04-zsh-plugins.sh      # Zsh plugin configuration
│   ├── 05-oh-my-posh.sh       # Prompt theme (di4am0nd)
│   ├── 06-tmux.sh             # Oh-My-Tmux + Solarized Dark
│   ├── 07-fonts.sh            # Nerd Fonts
│   ├── 08-claude.sh           # Claude Code CLI (native) + launcher
│   └── 99-finalize.sh         # Verification
├── configs/                   # Configuration templates
│   ├── zshrc.template         # Standard zshrc (single source of truth)
│   ├── tmux.conf.local.template
│   └── plugins.list
└── themes/
    └── solarized-dark/
        └── tmux.conf.colors
```

## Key Design Principles

1. **Idempotent**: All scripts check if work is needed before making changes
2. **Modular**: Each module is self-contained and can run independently
3. **Backup-first**: Existing configs are backed up before modification
4. **Dry-run support**: Preview changes with `--dry-run`
5. **Template-driven**: `configs/zshrc.template` is the single source for `.zshrc` — modules 04/05 detect it and skip redundant writes

## Multi-User Admin

### Initial user creation
```bash
# Edit USERS array and ADMIN_USER/ADMIN_PASS in setup-developers.sh, then:
sudo ./setup-developers.sh
```
Creates macOS users, `developer` group, SSH access, shared Homebrew permissions.

### Install dev environment for a user
```bash
sudo -u <user> -H bash -c \
  'export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH && \
   export HOMEBREW_NO_AUTO_UPDATE=1 && \
   bash /path/to/install.sh --yes --no-update'
```

### What's shared vs per-user

| Layer | Scope | Examples |
|-------|-------|---------|
| Homebrew packages | Shared (developer group) | tmux, fzf, oh-my-posh, node, uv |
| Claude Code binary | Per-user (`~/.local/bin/claude`) | Native Mach-O build, not npm |
| Dotfiles | Per-user (from template) | `.zshrc`, `.config/tmux/` |
| Oh-My-Zsh | Per-user (`~/.oh-my-zsh/`) | Cloned from GitHub |

## Gotchas

- **Proxy**: `install.sh` sets `ALL_PROXY/HTTP_PROXY/HTTPS_PROXY` to `http://127.0.0.1:7897` by default. Override with env vars if your proxy differs.
- **`HOMEBREW_NO_AUTO_UPDATE=1`**: Required when running as non-admin developer user — shared Homebrew's `.git` triggers `update-report` errors without it.
- **`sudo -u` PATH inheritance**: Parent user's PATH leaks through `sudo`. Always explicitly set `PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH` to avoid detecting another user's binaries.
- **Claude Code is native, not npm**: Installed per-user via `curl -fsSL https://claude.ai/install.sh | bash` to `~/.local/bin/claude`. Cannot be shared via Homebrew.
- **`claude doctor` requires TTY**: Cannot run in `sudo` pipe; use `file ~/.local/bin/claude` (expect `Mach-O`) + `claude --version` for non-interactive verification.
- **zshrc template vs module assembly**: `configs/zshrc.template` is the authoritative `.zshrc`. Modules 04 (plugins) and 05 (oh-my-posh) detect the template's content and skip modification. Edit the template, not the modules, to change shell config.

## Common Tasks

### Add a new tool to core-tools
Edit `modules/02-core-tools.sh`, add formula to `CORE_FORMULAS` array.

### Add a new optional dev tool
Edit `modules/02a-dev-tools.sh`:
1. Add to `DEV_TOOL_NAMES`/`DEV_TOOL_DESCS` arrays
2. Add detection in `detect_dev_tools()`
3. Add installation in `install_dev_tool()`

### Change shell configuration for all users
Edit `configs/zshrc.template`, then re-run `./install.sh --module=03-zsh-base` for each user.

### Change default Oh-My-Posh theme
Edit `modules/05-oh-my-posh.sh` (`DEFAULT_THEME`) **and** `configs/zshrc.template` (the eval line).

### Add zsh plugins
Edit both `modules/04-zsh-plugins.sh` (`DEFAULT_PLUGINS`) **and** `configs/zshrc.template` (`plugins=(...)`).

### Modify tmux Solarized Dark colors
Edit `configs/tmux.conf.local.template` — color variables are `tmux_conf_theme_colour_N`.

## Testing

```bash
# Dry run full install
./install.sh --dry-run

# Run single module
./install.sh --module=02-core-tools --dry-run

# Detection summary only
./install.sh --detect

# List available backups
./install.sh --list-backups
```

## Library Functions Reference

### common.sh
- `log_info`, `log_warn`, `log_error`, `log_success`, `log_step`, `log_substep`
- `ask_yes_no "prompt" [default]` — Interactive yes/no
- `command_exists name` — Check if command available
- `is_dry_run` — Check dry-run mode
- `run_cmd cmd...` — Execute or print in dry-run

### detect.sh
- `detect_homebrew`, `detect_zsh`, `detect_tmux`, `detect_fzf`
- `detect_oh_my_zsh`, `detect_oh_my_posh`, `detect_oh_my_tmux`
- `detect_node`, `detect_uv`
- `detect_nerd_font [name]`
- `print_detection_summary`

### backup.sh
- `init_backup_session` — Start backup session with timestamp
- `backup_file path [description]` — Backup single file
- `backup_dir path [description]` — Backup directory
- `restore_backup session_name` — Restore from backup
- `list_backups` — Show available backups

### brew.sh
- `brew_install formula [tap]` — Install if not present
- `brew_install_cask cask` — Install cask if not present
- `brew_is_installed formula` — Check if installed
- `brew_get_version formula` — Get installed version
- `get_brew_prefix` — Returns /opt/homebrew (arm64) or /usr/local (x86)

## Module Template

```bash
#!/usr/bin/env bash
# XX-module-name.sh - Description

set -euo pipefail

MODULE_NAME="module-name"
MODULE_DESC="Short description"

run_module() {
    log_step "Doing something"

    if some_check; then
        log_success "Already done"
        return 0
    fi

    if is_dry_run; then
        log_info "[DRY-RUN] Would do something"
        return 0
    fi

    # Actual work here

    log_success "Done"
}

if [[ "${1:-}" == "--run" ]]; then
    run_module
fi
```

## Backup Location

`~/.setup-dev-mac-backups/YYYYMMDD_HHMMSS/`

Each backup preserves the original file's relative path from $HOME.
