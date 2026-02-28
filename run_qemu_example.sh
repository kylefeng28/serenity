#!/usr/bin/env bash
# Example run_qemu.sh for dual-disk setup
# Modify this to match your existing QEMU configuration

set -e

SCRIPT_DIR="$(dirname "${0}")"
BUILD_DIR="${SCRIPT_DIR}/Build/x86_64"

cd "$BUILD_DIR"

# Check if disks exist
if [ ! -f _system_disk_image ]; then
    echo "Error: _system_disk_image not found. Run Meta/build-dual-disk.sh first."
    exit 1
fi

if [ ! -d userdata ]; then
    echo "Error: userdata/ directory not found. Run Meta/build-dual-disk.sh first."
    exit 1
fi

# Your existing QEMU parameters + dual disk setup
set -x
qemu-system-x86_64 \
    -m 2G \
    -smp 2 \
    -enable-kvm \
    \
    `# System disk (ext2, read-only recommended for production)` \
    -drive file=_system_disk_image,format=raw,id=system,if=none \
    -device nvme,serial=system,drive=system \
    \
    `# User data (FAT virtual drive from directory)` \
    -drive file=fat:rw:userdata,id=userdata-fat,format=raw,if=none \
    -drive file=_userdata_disk_image,format=raw,id=userdata,if=none \
    -device ahci,id=ahci \
    -device ide-hd,drive=userdata,bus=ahci.0 \
    \
    `# Kernel and boot` \
    -kernel Kernel/Kernel \
    -append "root=nvme0:1:0 serial_debug" \
    \
    `# Your existing device configuration` \
    -device VGA,vgamem_mb=64 \
    -audiodev pa,id=audio0 \
    -device AC97,audiodev=audio0 \
    -device e1000,netdev=net0 \
    -netdev user,id=net0 \
    \
    `# Serial console for debugging` \
    -serial stdio \
    -display sdl,gl=off

# Note: The FAT drive will appear as /dev/hda0 or similar
# You'll need to mount it in SerenityOS with:
#   mkdir /home
#   mount -t fat /dev/hda0 /home
