#!/bin/bash
set -e

echo "=== Transparent Encryption Demo ==="
echo ""

BACKEND_DIR="$HOME/enc_backend"
MOUNT_DIR="$HOME/enc_mount"

cleanup() {
    echo "Cleaning up..."
    fusermount -u "$MOUNT_DIR" 2>/dev/null || true
    rm -rf "$BACKEND_DIR" "$MOUNT_DIR"
}

trap cleanup EXIT

echo "1. Creating directories..."
rm -rf "$BACKEND_DIR" "$MOUNT_DIR"
mkdir -p "$BACKEND_DIR" "$MOUNT_DIR"

echo "2. Starting encrypted filesystem..."
./encfs "$BACKEND_DIR" "$MOUNT_DIR" -f &
ENCFS_PID=$!
sleep 3

if ! kill -0 $ENCFS_PID 2>/dev/null; then
    echo "ERROR: encfs failed to start"
    exit 1
fi

if ! mountpoint -q "$MOUNT_DIR"; then
    echo "ERROR: Directory not mounted"
    exit 1
fi

echo "   PID: $ENCFS_PID"
echo "   Mounted: $(mountpoint "$MOUNT_DIR")"

echo ""
echo "3. Writing test file..."
echo "Secret laboratory data 2026" > "$MOUNT_DIR/secret.txt"
echo "Password: SuperSecret123" >> "$MOUNT_DIR/secret.txt"

echo ""
echo "4. Reading file (decrypted view)..."
cat "$MOUNT_DIR/secret.txt"

echo ""
echo "5. Showing encrypted data on disk..."
echo "Raw bytes in backend:"
hexdump -C "$BACKEND_DIR/secret.txt" | head -10

echo ""
echo "6. File sizes comparison:"
echo "   Mount view: $(stat -c%s "$MOUNT_DIR/secret.txt") bytes"
echo "   Backend:    $(stat -c%s "$BACKEND_DIR/secret.txt") bytes"

echo ""
echo "7. Listing files..."
echo "   In mount:   $(ls -la "$MOUNT_DIR" 2>&1)"
echo "   In backend: $(ls -la "$BACKEND_DIR" 2>&1)"

echo ""
echo "8. Stopping encrypted filesystem..."
fusermount -u "$MOUNT_DIR"
wait $ENCFS_PID 2>/dev/null || true

echo ""
echo "9. Verifying files after unmount..."
echo "   Backend files: $(ls "$BACKEND_DIR" 2>&1)"
echo "   Mount dir: $(ls "$MOUNT_DIR" 2>&1 || echo 'empty')"

echo ""
echo "=== Demo Complete ==="
trap - EXIT
