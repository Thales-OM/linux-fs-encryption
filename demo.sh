#!/bin/bash
set -e

echo "=== Transparent Encryption Demo ==="
echo ""

BACKEND_DIR="$HOME/enc_backend"
MOUNT_DIR="$HOME/enc_mount"

echo "1. Creating directories..."
mkdir -p "$BACKEND_DIR" "$MOUNT_DIR"

echo "2. Starting encrypted filesystem..."
./encfs "$BACKEND_DIR" "$MOUNT_DIR" &
ENCFS_PID=$!
sleep 2

echo "3. Writing test file..."
echo "Secret laboratory data 2026" > "$MOUNT_DIR/secret.txt"
echo "Password: SuperSecret123" >> "$MOUNT_DIR/secret.txt"

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
echo "   In mount:   $(ls -la "$MOUNT_DIR")"
echo "   In backend: $(ls -la "$BACKEND_DIR")"

echo ""
echo "8. Stopping encrypted filesystem..."
fusermount -u "$MOUNT_DIR" 2>/dev/null || true
wait $ENCFS_PID 2>/dev/null || true

echo ""
echo "9. Verifying files are inaccessible after unmount..."
ls "$MOUNT_DIR" 2>&1 || echo "   Mount point is empty (as expected)"

echo ""
echo "=== Demo Complete ==="
