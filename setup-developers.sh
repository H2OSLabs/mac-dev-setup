#!/bin/bash
# ============================================
# macOS Developer User Setup Script
#
# Creates a 'developer' group, batch-creates
# users, grants SSH access, and shares Homebrew.
#
# Usage: sudo ./setup-developers.sh
# ============================================

set -uo pipefail
# Note: -e omitted intentionally — we handle errors explicitly
# to avoid silent exits from pipelines (e.g., tr | head → SIGPIPE)

# --- Configuration ---
GROUP_NAME="developer"
USERS=("lin.yilun" "yao.shengyue" "huang.jiajia" "li.zhenyu" "dai.ming")
PASSWORD_LENGTH=12
HOMEBREW_PREFIX="/opt/homebrew"
ADMIN_USER=""
ADMIN_PASS=""
# Set these before running, or the script will prompt interactively

# --- Pre-flight checks ---
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    echo "Usage: sudo $0"
    exit 1
fi

if ! command -v sysadminctl &>/dev/null; then
    echo "sysadminctl not found. This script requires macOS."
    exit 1
fi

if [ ! -d "$HOMEBREW_PREFIX" ]; then
    echo "Warning: $HOMEBREW_PREFIX not found. Homebrew sharing will be skipped."
    SKIP_BREW=1
else
    SKIP_BREW=0
fi

# Verify admin credentials
if ! dscl /Local/Default -authonly "$ADMIN_USER" "$ADMIN_PASS" &>/dev/null; then
    echo "Invalid admin credentials."
    exit 1
fi

# --- Helper: generate random password (SIGPIPE-safe) ---
generate_password() {
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$PASSWORD_LENGTH" || true
}

# --- Store credentials for final output ---
declare -a CREDENTIALS

echo ""
echo "=========================================="
echo " macOS Developer User Setup"
echo "=========================================="
echo ""

# --- Step 1: Create developer group ---
if dseditgroup -o read "$GROUP_NAME" &>/dev/null; then
    echo "[OK] Group '$GROUP_NAME' already exists."
else
    echo "[..] Creating group '$GROUP_NAME'..."
    dseditgroup -o create "$GROUP_NAME"
    echo "[OK] Group '$GROUP_NAME' created."
fi
echo ""

# --- Step 2: Create users ---
for username in "${USERS[@]}"; do
    echo "--- $username ---"

    if dscl . -read "/Users/$username" &>/dev/null; then
        echo "[SKIP] User '$username' already exists."
        CREDENTIALS+=("$username | (already exists, password unchanged)")
        dseditgroup -o edit -a "$username" -t user "$GROUP_NAME" 2>/dev/null || true
        echo ""
        continue
    fi

    # Generate password
    password=$(generate_password)
    if [ -z "$password" ]; then
        echo "[ERROR] Failed to generate password for $username"
        continue
    fi

    # Create user
    echo "[..] Creating user..."
    if sysadminctl -addUser "$username" \
        -password "$password" \
        -fullName "$username" \
        -shell /bin/zsh \
        -adminUser "$ADMIN_USER" \
        -adminPassword "$ADMIN_PASS" 2>&1; then
        echo "[OK] User created."
    else
        echo "[ERROR] Failed to create user '$username'"
        continue
    fi

    # Create home directory (sysadminctl may not create it)
    USER_HOME="/Users/$username"
    if [ ! -d "$USER_HOME" ]; then
        createhomedir -c -u "$username" 2>/dev/null || {
            mkdir -p "$USER_HOME"
            chown "$username:staff" "$USER_HOME"
            chmod 750 "$USER_HOME"
        }
        echo "[OK] Home directory created at $USER_HOME"
    fi

    # Add to developer group
    dseditgroup -o edit -a "$username" -t user "$GROUP_NAME"
    echo "[OK] Added to '$GROUP_NAME' group."

    # Configure shell environment for Homebrew
    if [ "$SKIP_BREW" -eq 0 ]; then
        ZSHRC="$USER_HOME/.zshrc"
        echo '# Homebrew' >> "$ZSHRC"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$ZSHRC"
        chown "$username" "$ZSHRC"
        echo "[OK] Configured Homebrew PATH in .zshrc"
    fi

    CREDENTIALS+=("$username | $password")
    echo ""
done

# --- Step 3: Grant SSH access to developer group ---
echo "--- SSH Access ---"
dseditgroup -o edit -a "$GROUP_NAME" -t group com.apple.access_ssh 2>/dev/null && \
    echo "[OK] Group '$GROUP_NAME' added to SSH access (com.apple.access_ssh)." || {
    echo "[WARN] Could not add group. Adding users individually..."
    for username in "${USERS[@]}"; do
        dseditgroup -o edit -a "$username" -t user com.apple.access_ssh 2>/dev/null || true
    done
    echo "[OK] Users added to SSH access individually."
}
echo ""

# --- Step 4: Share Homebrew ---
if [ "$SKIP_BREW" -eq 0 ]; then
    echo "--- Homebrew Sharing ---"
    echo "[..] Setting $HOMEBREW_PREFIX group to '$GROUP_NAME'..."
    chgrp -R "$GROUP_NAME" "$HOMEBREW_PREFIX"
    chmod -R g+rwX "$HOMEBREW_PREFIX"
    echo "[OK] Homebrew shared with '$GROUP_NAME' group."
    echo ""
fi

# --- Step 5: Print credentials ---
echo "=========================================="
echo " Setup Complete"
echo "=========================================="
echo ""
echo "Credentials:"
echo ""
printf "%-20s | %s\n" "USERNAME" "PASSWORD"
printf "%-20s-+-%s\n" "--------------------" "--------------------"
for entry in "${CREDENTIALS[@]}"; do
    user=$(echo "$entry" | cut -d'|' -f1 | xargs)
    pass=$(echo "$entry" | cut -d'|' -f2 | xargs)
    printf "%-20s | %s\n" "$user" "$pass"
done
echo ""
echo "SSH access: ssh <username>@$(hostname)"
echo ""
echo "Notes:"
echo "  - Users should change their password after first login: passwd"
echo "  - Or set up SSH key: ssh-copy-id <username>@$(hostname)"
if [ "$SKIP_BREW" -eq 0 ]; then
    echo "  - Homebrew is shared at $HOMEBREW_PREFIX (group: $GROUP_NAME)"
fi
echo ""
