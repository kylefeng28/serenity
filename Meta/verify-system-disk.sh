#!/usr/bin/env bash
# Verify the system disk has all required directories

set -e

SCRIPT_DIR="$(dirname "${0}")"
BUILD_DIR="${SCRIPT_DIR}/../Build/${SERENITY_ARCH:-x86_64}"

cd "$BUILD_DIR"

if [ ! -f _system_disk_image ]; then
    echo "Error: _system_disk_image not found"
    exit 1
fi

echo "=== Verifying System Disk Structure ==="
echo ""

# Mount the disk temporarily
mkdir -p mnt_verify
if command -v fuse2fs >/dev/null 2>&1; then
    echo using fuse2fs
    fuse2fs _system_disk_image mnt_verify -o ro 2>/dev/null || sudo mount -o ro _system_disk_image mnt_verify
else
    echo using sudo
    sudo mount -o ro _system_disk_image mnt_verify
fi

cleanup() {
    if mountpoint -q mnt_verify 2>/dev/null; then
        if command -v fusermount >/dev/null 2>&1; then
            fusermount -u mnt_verify 2>/dev/null || sudo umount mnt_verify
        else
            sudo umount mnt_verify
        fi
    fi
    rmdir mnt_verify 2>/dev/null || true
}
trap cleanup EXIT

# Check essential directories
echo "Checking essential directories:"
for dir in proc sys dev tmp home bin usr/lib boot res etc var/run; do
    if [ -d "mnt_verify/$dir" ]; then
        echo "  ✓ /$dir"
    else
        echo "  ✗ /$dir (MISSING)"
    fi
done

echo ""
echo "Checking essential files:"
for file in bin/init boot/Kernel etc/passwd etc/shadow var/run/utmp; do
    if [ -e "mnt_verify/$file" ]; then
        echo "  ✓ /$file"
    else
        echo "  ✗ /$file (MISSING)"
    fi
done

echo ""
echo "Checking /home is empty:"
if [ -d "mnt_verify/home" ]; then
    count=$(ls -A mnt_verify/home 2>/dev/null | wc -l)
    if [ "$count" -eq 0 ]; then
        echo "  ✓ /home exists and is empty (ready for mount)"
    else
        echo "  ⚠ /home has $count items (should be empty)"
        ls -la mnt_verify/home/
    fi
else
    echo "  ✗ /home directory missing"
fi

echo ""
echo "=== Verification Complete ==="
