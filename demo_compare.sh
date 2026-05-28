#!/bin/bash
set -eo pipefail

TEST_DIR="$HOME/fscrypt_lab_test"
PASSPHRASE="lab_demo_2026"

pause() {
    read -p "Press Enter to continue..." -r
    echo ""
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

cleanup() {
    fscrypt lock "$TEST_DIR" 2>/dev/null || true
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

echo "=== Fscrypt Transparent Encryption Demo ==="
install_fscrypt
pause

echo "1. Initializing fscrypt configuration..."
sudo fscrypt setup 2>/dev/null || true
pause

echo "2. Creating test directory..."
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
pause

echo "3. Enabling transparent encryption..."
printf "%s\n" "$PASSPHRASE" | fscrypt encrypt "$TEST_DIR" --name="lab_protector"
pause

echo "4. Writing test data..."
echo "Confidential lab report 2026" > "$TEST_DIR/report.txt"
echo "AES-256-XTS encryption active" > "$TEST_DIR/notes.txt"
pause

echo "5. Reading data (transparent decryption)..."
echo "--- report.txt ---"
cat "$TEST_DIR/report.txt"
echo "--- notes.txt ---"
cat "$TEST_DIR/notes.txt"
pause

echo "6. Verifying encryption status..."
fscrypt status "$TEST_DIR"
pause

echo "7. Inspecting raw encrypted data on disk..."
RAW_FILE=$(find "$TEST_DIR" -maxdepth 1 -type f | head -1)
if [ -n "$RAW_FILE" ]; then
    echo "Hex dump of encrypted file:"
    sudo hexdump -C "$RAW_FILE" | head -6
fi
pause

echo "8. Locking directory (revoking access)..."
fscrypt lock "$TEST_DIR"
pause

echo "9. Attempting access while locked..."
cat "$TEST_DIR/report.txt" 2>&1 || echo "   [ACCESS DENIED - Directory locked]"
pause

echo "10. Unlocking directory..."
printf "%s\n" "$PASSPHRASE" | fscrypt unlock "$TEST_DIR"
pause

echo "11. Verifying access restored..."
cat "$TEST_DIR/report.txt"
pause

echo ""
echo "=== Demo Complete ==="
