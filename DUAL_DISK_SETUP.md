# Dual-Disk SerenityOS Setup

This setup separates system files from user data for easier development and bare metal deployment.

## Architecture

1. **System Disk** (`_system_disk_image`) - ext2 filesystem
   - Contains: `/bin`, `/usr`, `/boot`, `/res`, `/etc`
   - Can be mounted read-only in production
   - Updated when you rebuild SerenityOS

2. **User Data** (`userdata/` directory) - FAT virtual drive
   - Contains: `/home` directory
   - Writable by users
   - Persists across system rebuilds
   - QEMU presents this directory as a FAT filesystem

## Building

```bash
cd Build/x86_64

# Build system disk and userdata directory
../../Meta/build-dual-disk.sh

# Build ext2 userdata disk (recommended for proper permissions)
../../Meta/build-userdata-ext2.sh
```

This creates:
- `_system_disk_image` - System disk (ext2) with:
  - `/bin`, `/usr`, `/boot`, `/res`, `/etc` - System files
  - `/proc`, `/sys`, `/dev`, `/tmp` - Empty mount points
  - `/home` - Empty directory for user data mount
  - `/var/run/utmp` - Runtime state
  - `/init` -> `/bin/init` symlink
- `userdata/` - User data directory (for development)
- `_userdata_disk_image` - User data disk (ext2, recommended)

To verify the system disk was built correctly:
```bash
../../Meta/verify-system-disk.sh
```

### FAT vs ext2 for User Data

**ext2 (recommended)**:
- ✅ Proper Unix permissions (files owned by anon user)
- ✅ No permission errors
- ✅ Ready for bare metal
- ❌ Requires separate disk image file

**FAT virtual drive (development only)**:
- ✅ Easy to edit from host (just edit `userdata/` directory)
- ✅ No mounting needed on host
- ❌ All files owned by root (permission issues)
- ❌ Services may fail to write config files

## Running

Update your `run_qemu.sh` with these disk parameters:

### Option 1: ext2 userdata (recommended)

```bash
# System disk (ext2)
-drive file=_system_disk_image,format=raw,id=system,if=none \
-device nvme,serial=system,drive=system \

# User data (ext2 disk image)
-drive file=_userdata_disk_image,format=raw,id=userdata,if=none \
-device ahci,id=ahci \
-device ide-hd,drive=userdata,bus=ahci.0 \

# Boot from system disk
-kernel Kernel/Kernel \
-append "root=nvme0:1:0 serial_debug"
```

### Option 2: FAT virtual drive (development, has permission issues)

```bash
# System disk (ext2)
-drive file=_system_disk_image,format=raw,id=system,if=none \
-device nvme,serial=system,drive=system \

# User data (FAT virtual drive from directory)
-drive file=fat:rw:userdata,id=userdata,format=raw,if=none \
-device ahci,id=ahci \
-device ide-hd,drive=userdata,bus=ahci.0 \

# Boot from system disk
-kernel Kernel/Kernel \
-append "root=nvme0:1:0 serial_debug"
```

**Note**: With FAT, you'll need to edit `/etc/fstab` to change `ext2` to `fat` for the `/home` mount.

**Important**: The user data disk will appear as `/dev/hda0` (for AHCI/IDE) in SerenityOS. The custom `fstab` is configured to automatically mount it at `/home` during boot.

### Device Naming

Depending on your QEMU configuration, the FAT drive may appear as:
- `/dev/hda0` - AHCI/IDE (default in example)
- `/dev/ata0:0:0` - Alternative AHCI naming
- `/dev/nvme1:1:0` - If using second NVMe device

If the mount fails, check `/dev/` for available devices and update `/etc/fstab` accordingly.

## Mounting User Data in SerenityOS

The user data partition is **automatically mounted** at boot via `/etc/fstab`.

If automatic mounting fails (e.g., wrong device path), you can mount manually:

```bash
# Find the device (usually /dev/hda0 for AHCI/IDE)
ls /dev/hd* /dev/block* /dev/ata*

# Mount it manually
mount -t fat /dev/hda0 /home
```

To fix the device path permanently, edit `/etc/fstab` and change the device name for the `/home` mount point.

Or use the helper script:
```bash
/usr/local/bin/mount-userdata.sh
```

## Development Workflow

1. **Modify system code** → Rebuild → Run `build-dual-disk.sh`
   - Only system disk is recreated
   - User data remains untouched

2. **Modify user files** → Edit files in `userdata/` directory
   - Changes immediately visible in QEMU
   - No rebuild needed

## Bare Metal Deployment

For bare metal, replace the FAT virtual drive with a real FAT partition:

1. Create two partitions on your disk:
   - Partition 1: ext2 for system (e.g., 2GB)
   - Partition 2: FAT32 for user data (remaining space)

2. Write `_system_disk_image` to partition 1:
   ```bash
   dd if=_system_disk_image of=/dev/sdX1 bs=4M
   ```

3. Format partition 2 as FAT32:
   ```bash
   mkfs.vfat -F 32 /dev/sdX2
   ```

4. Copy `userdata/*` to partition 2:
   ```bash
   mount /dev/sdX2 /mnt
   cp -r userdata/* /mnt/
   umount /mnt
   ```

5. Update kernel cmdline to mount both:
   ```
   root=ata0:0:0 init=/bin/SystemServer
   ```

6. Add to `/etc/fstab` (if SerenityOS supports it) or init script:
   ```
   mount -t fat /dev/ata0:1:0 /home
   ```

## Benefits

- **System upgrades**: Replace system disk without touching user data
- **Development**: Faster iteration (no need to rebuild user files)
- **Bare metal ready**: Easy to deploy to real hardware
- **Cross-platform**: FAT user data readable from any OS

## Notes

- QEMU's FAT virtual drive is **not persistent** across QEMU restarts by default
  - Changes are written to the `userdata/` directory on your host
  - This is actually a feature for development!

- For production/bare metal, use a real FAT partition instead

- The system disk can be mounted read-only for extra safety:
  ```bash
  mount -o ro /dev/nvme0:1:0 /
  ```
