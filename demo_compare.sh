#!/bin/bash
set -euo pipefail
TEST_DIR="$HOME/fscrypt_lab_test"
PASSPHRASE="lab_demo_2026"
PROTECTOR_NAME="lab_protector2"
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
    if [ -d "$TEST_DIR" ]; then
        printf "%s\n" "$PASSPHRASE" | fscrypt unlock "$TEST_DIR" 2>/dev/null || true
        fscrypt lock "$TEST_DIR" 2>/dev/null || true
    fi
    rm -rf "$TEST_DIR" 2>/dev/null || true
    PROT_ID=$(sudo fscrypt metadata list 2>/dev/null | awk -v name="$PROTECTOR_NAME" '$2 == name {print $1}')
    if [ -n "$PROT_ID" ]; then
        echo "  -> Destroying existing protector: $PROT_ID"
        sudo fscrypt metadata destroy-protector "$PROT_ID" --force 2>/dev/null || true
    fi
    set -e
    echo "  -> Cleanup complete."
}
cleanup_handler() {
    echo "Demo interrupted or errored. Cleaning up..."
    full_cleanup
}
trap cleanup_handler INT TERM ERR
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
printf "y\n%s\n%s\n" "$PASSPHRASE" "$PASSPHRASE" | fscrypt encrypt "$TEST_DIR" --name="$PROTECTOR_NAME"
pause
echo "5. Writing test data..."
echo "Confidential lab report 2026" > "$TEST_DIR/report.txt"
echo "AES-256-XTS encryption active" > "$TEST_DIR/notes.txt"
pause
echo "6. Reading data (transparent decryption)..."
echo "--- report.txt ---"
cat "$TEST_DIR/report.txt"
echo "--- notes.txt ---"
cat "$TEST_DIR/notes.txt"
pause
echo "7. Verifying encryption status..."
fscrypt status "$TEST_DIR"
pause
echo "8. Inspecting raw encrypted data on disk..."
RAW_FILE=$(find "$TEST_DIR" -maxdepth 1 -type f 2>/dev/null | head -1)
if [ -n "$RAW_FILE" ]; then
    echo "Hex dump of encrypted file:"
    sudo hexdump -C "$RAW_FILE" | head -6
else
    echo "No files found in directory."
fi
pause
echo "9. Locking directory (revoking access)..."
fscrypt lock "$TEST_DIR"
pause
echo "10. Attempting access while locked..."
cat "$TEST_DIR/report.txt" 2>&1 || echo "   [ACCESS DENIED - Directory locked]"
pause
echo "11. Unlocking directory..."
printf "%s\n" "$PASSPHRASE" | fscrypt unlock "$TEST_DIR"
pause
echo "12. Verifying access restored..."
cat "$TEST_DIR/report.txt"
pause
echo ""
echo "=== Demo Complete ==="
