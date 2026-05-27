#!/bin/bash
set -e

echo "=== Transparent Encryption Demo ==="
echo ""

BACKEND_DIR="$HOME/enc_backend"
MOUNT_DIR="$HOME/enc_mount"

cleanup() {
    echo "Cleaning up..."
    fusermount -u "$MOUNT_DIR" 2>/dev/null || true
}

trap cleanup EXIT

echo "1. Creating directories..."
rm -rf "$BACKEND_DIR" "$MOUNT_DIR"
mkdir -p "$BACKEND_DIR" "$MOUNT_DIR"

echo "2. Starting encrypted filesystem..."
./encfs "$BACKEND_DIR" "$MOUNT_DIR" &
ENCFS_PID=$!
sleep 2

if ! mountpoint -q "$MOUNT_DIR"; then
    echo "ERROR: Failed to mount. Check if FUSE is available."
    exit 1
fi

echo "   Mounted successfully (PID: $ENCFS_PID)"

echo ""
echo "3. Writing test file to encrypted directory..."
echo "Secret laboratory data 2026" > "$MOUNT_DIR/secret.txt"
echo "Password: SuperSecret123" >> "$MOUNT_DIR/secret.txt"

echo ""
echo "4. Reading file (transparent decryption)..."
echo "--- Content ---"
cat "$MOUNT_DIR/secret.txt"
echo "--- End ---"

echo ""
echo "5. Encrypted data on disk (backend):"
hexdump -C "$BACKEND_DIR/secret.txt" | head -8

echo ""
echo "6. Size comparison:"
echo "   Decrypted: $(stat -c%s "$MOUNT_DIR/secret.txt") bytes"
echo "   Encrypted: $(stat -c%s "$BACKEND_DIR/secret.txt") bytes (includes nonce + MAC)"

echo ""
echo "7. Files in mount point: $(ls "$MOUNT_DIR")"
echo "   Files in backend:    $(ls "$BACKEND_DIR")"

echo ""
echo "8. Unmounting..."
fusermount -u "$MOUNT_DIR"
wait $ENCFS_PID 2>/dev/null || true

echo ""
echo "9. After unmount:"
echo "   Backend still has: $(ls "$BACKEND_DIR" 2>&1)"
echo "   Mount point: $(ls "$MOUNT_DIR" 2>&1 || echo 'not accessible')"

echo ""
echo "=== Demo Complete ==="
trap - EXIT