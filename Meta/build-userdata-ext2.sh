#!/usr/bin/env bash
# Build a proper ext2 userdata disk (instead of FAT virtual drive)
# This solves permission issues since ext2 supports Unix permissions

set -e

SCRIPT_DIR="$(dirname "${0}")"
BUILD_DIR="${SCRIPT_DIR}/../Build/${SERENITY_ARCH:-x86_64}"

cd "$BUILD_DIR"

if [ ! -d userdata ]; then
    echo "Error: userdata/ directory not found. Run build-dual-disk.sh first."
    exit 1
fi

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

# Calculate userdata size (default 512MB, or based on content)
USERDATA_SIZE_MB=${SERENITY_USERDATA_SIZE_MB:-512}
USERDATA_SIZE_BYTES=$((USERDATA_SIZE_MB * 1024 * 1024))

echo "Creating ext2 userdata disk (_userdata_disk_image, ${USERDATA_SIZE_MB}MB)..."
qemu-img create -q -f raw _userdata_disk_image "$USERDATA_SIZE_BYTES" || die "could not create userdata disk"
chown "$SUDO_UID":"$SUDO_GID" _userdata_disk_image || die "could not adjust permissions"

"${MKE2FS_PATH}" -q -I 256 -i 16384 _userdata_disk_image || die "could not create filesystem"

# Mount userdata disk
mkdir -p mnt_userdata
if [ $USE_FUSE2FS -eq 1 ]; then
    mount_cmd="$FUSE2FS_PATH _userdata_disk_image mnt_userdata/ -o fakeroot,rw"
else
    mount_cmd="mount _userdata_disk_image mnt_userdata/"
fi
eval "$mount_cmd" || die "could not mount userdata disk"

cleanup() {
    if [ -d mnt_userdata ]; then
        echo "Unmounting userdata disk..."
        if [ $USE_FUSE2FS -eq 1 ]; then
            fusermount -u mnt_userdata || (sleep 1 && sync && fusermount -u mnt_userdata)
        else
            umount mnt_userdata || (sleep 1 && sync && umount mnt_userdata)
        fi
        rm -rf mnt_userdata
    fi
}
trap cleanup EXIT

# Copy userdata content
echo "Copying user data..."
rsync -aH userdata/ mnt_userdata/

# Set proper ownership (anon = uid 100, gid 100)
echo "Setting permissions..."
chown -R 100:100 mnt_userdata/anon 2>/dev/null || true
chown -R 200:100 mnt_userdata/nona 2>/dev/null || true
chmod 700 mnt_userdata/anon 2>/dev/null || true
chmod 700 mnt_userdata/nona 2>/dev/null || true

echo ""
echo "=== Userdata Disk Created ==="
echo "File: _userdata_disk_image (ext2, ${USERDATA_SIZE_MB}MB)"
echo ""
echo "Update your /etc/fstab to use:"
echo "  /dev/hda0  /home  ext2  defaults"
echo ""
echo "Or mount manually:"
echo "  mount -t ext2 /dev/hda0 /home"
echo ""
echo "QEMU arguments:"
echo "  -drive file=_userdata_disk_image,format=raw,id=userdata,if=none"
echo "  -device ahci,id=ahci"
echo "  -device ide-hd,drive=userdata,bus=ahci.0"
