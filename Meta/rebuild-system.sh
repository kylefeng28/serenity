#!/usr/bin/env bash
# Quick rebuild script - only rebuilds changed system files

set -e

SCRIPT_DIR=$(realpath "$(dirname "${0}")")
BUILD_DIR="${SCRIPT_DIR}/../Build/${SERENITY_ARCH:-x86_64}"

echo "=== Incremental System Rebuild ==="

# Build only changed files
cd "$SCRIPT_DIR/.."
cmake --build "$BUILD_DIR"

# Update only system disk (userdata/ is untouched)
cd "$BUILD_DIR"
echo "Updating system disk..."
# "$SCRIPT_DIR/build-dual-disk.sh"
set -x
/usr/bin/cmake -E env SERENITY_SOURCE_DIR=/home/kylef/git/serenity SERENITY_ARCH=x86_64 SERENITY_TOOLCHAIN=GNU $SCRIPT_DIR/build-dual-disk.sh

echo ""
echo "=== Rebuild Complete ==="
echo "System disk updated. User data preserved."
echo "Run your QEMU script to test."
