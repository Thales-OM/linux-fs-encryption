#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$HOME/fscrypt_lab_test"
PASSPHRASE="lab_demo_2026"
PROTECTOR_NAME="lab_protector"

pause() {
    if [ -t 0 ]; then
        read -p "Press Enter to continue..." -r
        echo ""
    fi
}

install_fscrypt() {
    command -v fscrypt &>/dev/null && return 0
    echo "Installing fscrypt..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq fscrypt
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y -q fscrypt
    elif command -v yum &>/dev/null; then
        sudo yum install -y -q fscrypt
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm fscrypt
    elif command -v zypper &>/dev/null; then
        sudo zypper --non-interactive install fscrypt
    elif command -v apk &>/dev/null; then
        sudo apk add --no-cache fscrypt
    else
        echo "ERROR: Unsupported package manager. Install fscrypt manually."
        exit 1
    fi
}

full_cleanup() {
    echo "Cleaning up previous run..."
    set +e

    # 1. Ensure directory is locked and remove it
    if [ -d "$TEST_DIR" ]; then
        printf "%s\n" "$PASSPHRASE" | fscrypt unlock "$TEST_DIR" 2>/dev/null || true
        fscrypt lock "$TEST_DIR" 2>/dev/null || true
        rm -rf "$TEST_DIR"
    fi

    # 2. Find & destroy protector by name (robust across fscrypt versions)
    # Output format typically: ID NAME TYPE
    PROT_ID=$(fscrypt metadata list 2>/dev/null | grep -w "$PROTECTOR_NAME" | head -1 | awk '{print $1}')
    
    if [ -n "$PROT_ID" ]; then
        echo "  -> Found existing protector: $PROT_ID"
        # Some fscrypt versions require --filesystem. Fallback gracefully.
        FS_MOUNT=$(df "$HOME" 2>/dev/null | tail -1 | awk '{print $NF}')
        if [ -n "$FS_MOUNT" ]; then
            sudo fscrypt metadata destroy-protector "$PROT_ID" --filesystem="$FS_MOUNT" 2>/dev/null || \
            sudo fscrypt metadata destroy-protector "$PROT_ID" 2>/dev/null || true
        else
            sudo fscrypt metadata destroy-protector "$PROT_ID" 2>/dev/null || true
        fi
        echo "  -> Protector destroyed."
    else
        echo "  -> No existing protector found."
    fi

    set -e
    echo "  -> Cleanup complete."
}

trap 'echo "Exiting..."; full_cleanup' EXIT

echo "=== Fscrypt Transparent Encryption Demo ==="
install_fscrypt
pause

echo "1. Initializing fscrypt configuration..."
sudo fscrypt setup 2>/dev/null || echo "  -> Already initialized or skipped."
pause

echo "2. Cleaning up any previous test data..."
full_cleanup
pause

echo "3. Creating test directory..."
mkdir -p "$TEST_DIR"
pause

echo "4. Enabling transparent encryption..."
# --name only prompts for passphrase twice. Removed erroneous 'y' input.
printf "%s\n%s\n" "$PASSPHRASE" "$PASSPHRASE" | fscrypt encrypt "$TEST_DIR" --name="$PROTECTOR_NAME"
pause

echo "5. Writing test data..."
echo "Confidential lab report 2026" > "$TEST_DIR/report.txt"
echo "AES-256-XTS encryption active" > "$TEST_DIR/notes.txt"
pause

echo "6. Reading data (transparent decryption)..."
echo "--- report.txt ---"
cat "$TEST_DIR/report.txt"
echo "--- notes.txt ---"
cat "$TEST_DIR/
