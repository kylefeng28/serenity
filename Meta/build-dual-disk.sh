#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(dirname "${0}")"

# Prepend toolchain directories
PATH="$SCRIPT_DIR/../Toolchain/Local/qemu/bin:$PATH"
PATH="$SCRIPT_DIR/../Toolchain/Local/e2fsprogs/bin:$PATH"

. "${SCRIPT_DIR}/shell_include.sh"

USE_FUSE2FS=0

if [ "$(id -u)" != 0 ]; then
    if [ -x "$FUSE2FS_PATH" ] && $FUSE2FS_PATH --help 2>&1 |grep fakeroot > /dev/null; then
        USE_FUSE2FS=1
    else
        set +e
        ${SUDO} -- "${SHELL}" -c "\"$0\" $* || exit 42"
        case $? in
            1)
                die "this script needs to run as root"
                ;;
            42)
                exit 1
                ;;
            *)
                exit 0
                ;;
        esac
    fi
else
    : "${SUDO_UID:=0}" "${SUDO_GID:=0}"
fi

INODE_SIZE=256
BYTES_PER_INODE=11264

# Calculate system disk size (Base + Root without /home)
SYSTEM_SIZE_BYTES=$((($(disk_usage "$SERENITY_SOURCE_DIR/Base") + $(disk_usage Root)) * 1024 * 1024))
SYSTEM_INODE_COUNT=$(($(inode_usage "$SERENITY_SOURCE_DIR/Base") + $(inode_usage Root)))
SYSTEM_SIZE_BYTES=$((SYSTEM_SIZE_BYTES + (SYSTEM_INODE_COUNT * INODE_SIZE)))
SYSTEM_SIZE_BYTES=$((SYSTEM_SIZE_BYTES * 2))  # 2x for overhead

echo "Creating system disk image (_system_disk_image)..."
qemu-img create -q -f raw _system_disk_image "$SYSTEM_SIZE_BYTES" || die "could not create system disk"
chown "$SUDO_UID":"$SUDO_GID" _system_disk_image || die "could not adjust permissions"

"${MKE2FS_PATH}" -q -I "${INODE_SIZE}" -i "${BYTES_PER_INODE}" _system_disk_image || die "could not create filesystem"

# Mount system disk
mkdir -p mnt_system
if [ $USE_FUSE2FS -eq 1 ]; then
    mount_cmd="$FUSE2FS_PATH _system_disk_image mnt_system/ -o fakeroot,rw"
else
    mount_cmd="mount _system_disk_image mnt_system/"
fi
eval "$mount_cmd" || die "could not mount system disk"

cleanup() {
    if [ -d mnt_system ]; then
        echo "Unmounting system disk..."
        if [ $USE_FUSE2FS -eq 1 ]; then
            fusermount -u mnt_system || (sleep 1 && sync && fusermount -u mnt_system)
        else
            umount mnt_system || (sleep 1 && sync && umount mnt_system)
        fi
        echo NOT RUNNING rm -rf mnt_system
        # rm -rf mnt_system
    fi
}
trap cleanup EXIT

# Install system files (everything except /home content)
echo "Installing system files..."
if ! command -v rsync >/dev/null; then
    die "Please install rsync."
fi

umask 0022

if rsync --chown 2>&1 | grep "missing argument" >/dev/null; then
    rsync -aH --chown=0:0 --inplace --update --exclude="/home/*" "$SERENITY_SOURCE_DIR"/Base/ mnt_system/
    rsync -aH --chown=0:0 --exclude="/usr/include" --exclude="/home/*" --inplace --update Root/ mnt_system/
    rsync -aHL --chown=0:0 --inplace --update Root/usr/include/ mnt_system/usr/include/
else
    rsync -aH --inplace --update --exclude="/home/*" "$SERENITY_SOURCE_DIR"/Base/ mnt_system/
    rsync -aH --inplace --exclude="/usr/include" --exclude="/home/*" --update Root/ mnt_system/
    rsync -aHL --inplace --update Root/usr/include/ mnt_system/usr/include/
    chown -R 0:0 mnt_system/
fi

SERENITY_ARCH="${SERENITY_ARCH:-x86_64}"

# Copy toolchain files
if [ "$SERENITY_TOOLCHAIN" = "Clang" ]; then
    TOOLCHAIN_DIR="$SERENITY_SOURCE_DIR"/Toolchain/Local/clang/
    rsync -aH --update -t "$TOOLCHAIN_DIR"/lib/"$SERENITY_ARCH"-pc-serenity/* mnt_system/usr/lib
    mkdir -p mnt_system/usr/include/"$SERENITY_ARCH"-pc-serenity
    rsync -aH --update -t -r "$TOOLCHAIN_DIR"/include/c++ mnt_system/usr/include
    rsync -aH --update -t -r "$TOOLCHAIN_DIR"/include/"$SERENITY_ARCH"-pc-serenity/c++ mnt_system/usr/include/"$SERENITY_ARCH"-pc-serenity
else
    rsync -aH --update -t -r "$SERENITY_SOURCE_DIR"/Toolchain/Local/"$SERENITY_ARCH"/"$SERENITY_ARCH"-pc-serenity/lib/* mnt_system/usr/lib
    rsync -aH --update -t -r "$SERENITY_SOURCE_DIR"/Toolchain/Local/"$SERENITY_ARCH"/"$SERENITY_ARCH"-pc-serenity/include/c++ mnt_system/usr/include
fi

# Create essential filesystem structure
echo "Creating filesystem structure..."
for dir in proc sys dev tmp mnt var/run usr/local usr/Ports usr/bin; do
    mkdir -p mnt_system/$dir
done
chmod 700 mnt_system/boot 2>/dev/null || true
chmod 1777 mnt_system/tmp

# Create /init symlink to /bin/init
echo "Creating /init symlink..."
ln -sf bin/init mnt_system/init

# Create mount point for user data
mkdir -p mnt_system/home

# Create root home directory
mkdir -p mnt_system/root
chmod 700 mnt_system/root

# Create utmp file
echo "{}" > mnt_system/var/run/utmp
chown 0:5 mnt_system/var/run/utmp 2>/dev/null || true
chmod 664 mnt_system/var/run/utmp

# Fix permissions
wheel_gid=1
phys_gid=3
utmp_gid=5

if [ -f mnt_system/bin/utmpupdate ]; then
    chown 0:$utmp_gid mnt_system/bin/utmpupdate 2>/dev/null || true
    chmod 2755 mnt_system/bin/utmpupdate
fi

if [ -f mnt_system/bin/keymap ]; then
    chown 0:$phys_gid mnt_system/bin/keymap 2>/dev/null || true
    chmod 4750 mnt_system/bin/keymap
fi

if [ -f mnt_system/bin/timezone ]; then
    chown 0:$phys_gid mnt_system/bin/timezone 2>/dev/null || true
    chmod 4750 mnt_system/bin/timezone
fi

if [ -f mnt_system/bin/network-settings ]; then
    chown 0:0 mnt_system/bin/network-settings 2>/dev/null || true
    chmod 500 mnt_system/bin/network-settings
fi

chmod -f 0400 mnt_system/res/kernel.map 2>/dev/null || true
chmod -f 0400 mnt_system/boot/Kernel.debug 2>/dev/null || true
chmod -f 0400 mnt_system/boot/Kernel 2>/dev/null || true
chmod -f 0400 mnt_system/boot/Kernel.efi 2>/dev/null || true
chmod 600 mnt_system/etc/shadow 2>/dev/null || true

# Create custom fstab for dual-disk setup
echo "Creating custom fstab for dual-disk setup..."
cat > mnt_system/etc/fstab << 'EOF'
# Root file system. This is a fake entry which gets ignored by `mount -a`;
# the actual logic for mounting root is in the kernel.
/dev/hda	/	ext2	immutable,nodev,nosuid,ro
# Remount /bin, /root, and /var while adding the appropriate permissions.
/bin	/bin	bind	immutable,bind,nodev,ro
/etc	/etc	bind	immutable,bind,nodev,nosuid
/root	/root	bind	immutable,bind,nodev,nosuid
/var	/var	bind	immutable,bind,nodev,nosuid
/usr/Tests	/usr/Tests	bind	immutable,bind,nodev,ro
/usr/local	/usr/local	bind	immutable,bind,nodev,nosuid
/usr/Ports	/usr/Ports	bind	immutable,bind,nodev,nosuid
# User data partition (ext2 filesystem on second disk)
# Adjust device path based on your QEMU disk configuration:
# - For AHCI/IDE: /dev/hda0 or /dev/ata0:0:0
# - For second NVMe: /dev/nvme1:1:0
# Use ext2 for proper Unix permissions (recommended)
/dev/hda0	/home	ext2	defaults
# Or use FAT if you prefer (but has permission issues):
# /dev/hda0	/home	fat	defaults
EOF
chmod 644 mnt_system/etc/fstab

echo "System disk created successfully!"

# Create user data directory for FAT virtual drive
echo "Creating user data directory (userdata/)..."
mkdir -p userdata/anon/.config
mkdir -p userdata/anon/Desktop
mkdir -p userdata/anon/Documents
mkdir -p userdata/anon/Downloads
mkdir -p userdata/anon/Music
mkdir -p userdata/anon/Pictures
mkdir -p userdata/anon/Source
mkdir -p userdata/anon/Tests
mkdir -p userdata/anon/Videos
mkdir -p userdata/nona

# Copy home directory content from Base
if [ -d "$SERENITY_SOURCE_DIR/Base/home/anon" ]; then
    echo "Copying home directory structure from Base..."
    rsync -aH --update "$SERENITY_SOURCE_DIR"/Base/home/anon/ userdata/anon/
fi

# Copy any additional content from Root/home if it exists
if [ -d Root/home/anon ]; then
    rsync -aH --update Root/home/anon/ userdata/anon/
fi

# Set proper ownership
chown -R "$SUDO_UID":"$SUDO_GID" userdata/ || true
chmod -R u+w userdata/anon/.config || true

echo ""
echo "=== Build Complete ==="
echo "System disk: _system_disk_image (ext2)"
echo "User data:   userdata/ (directory for QEMU FAT virtual drive)"
echo ""
echo "⚠️  IMPORTANT: FAT filesystem limitation"
echo "The FAT virtual drive reports all files as owned by root (uid=0)."
echo "This may cause permission issues for user applications."
echo ""
echo "For production use, consider creating a real ext2 userdata disk:"
echo "  dd if=/dev/zero of=_userdata_disk_image bs=1M count=512"
echo "  mkfs.ext2 _userdata_disk_image"
echo "  mount _userdata_disk_image mnt_userdata"
echo "  cp -r userdata/* mnt_userdata/"
echo "  chown -R 100:100 mnt_userdata/anon"
echo "  umount mnt_userdata"
echo ""
echo "Then use in QEMU:"
echo "  -drive file=_userdata_disk_image,format=raw,id=userdata,if=none"
echo ""
echo "For now (development with FAT), the system disk includes a custom"
echo "/etc/fstab that will mount /dev/hda0 at /home during boot."
echo ""
echo "If /home doesn't mount, run inside SerenityOS:"
echo "  /usr/local/bin/check-userdata.sh"
echo ""
echo "To use with QEMU (FAT virtual drive):"
echo "  -drive file=_system_disk_image,format=raw,id=system,if=none"
echo "  -device nvme,serial=system,drive=system"
echo "  -drive file=fat:rw:userdata,id=userdata,format=raw,if=none"
echo "  -device ahci,id=ahci"
echo "  -device ide-hd,drive=userdata,bus=ahci.0"
echo ""
echo "Kernel cmdline should include: root=nvme0:1:0"
