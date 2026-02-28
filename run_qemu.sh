PREFIX=$(realpath $(dirname $0))
_kernel=$PREFIX/./Build/x86_64/Kernel/Kernel
_disk_image=$PREFIX/./Build/x86_64/_disk_image

qemu-system-x86_64 \
  -device i82801b11-bridge,id=bridge4 \
  -device nvme,serial=deadbeef,drive=boot-drive,bus=bridge4,logical_block_size=4096,physical_block_size=4096 \
  -device virtio-serial,max_ports=2 \
  -device virtconsole,chardev=stdout \
  -device isa-debugcon,chardev=stdout \
  -device virtio-rng-pci \
  -device pci-bridge,chassis_nr=1,id=bridge1 \
  -device i82801b11-bridge,bus=bridge1,id=bridge2 \
  -device i82801b11-bridge,id=bridge3 \
  -device ich9-ahci,bus=bridge3 \
  -kernel $_kernel \
  -machine pcspk-audiodev=snd0 \
  -gdb tcp:127.0.0.1:1234 \
  -qmp unix:qmp-sock,server,nowait \
  -name SerenityOS \
  -d guest_errors \
  -accel kvm \
  -append 'hello root=nvme0:1:0' \
  -m 2G \
  -cpu max,-x2apic \
  -smp 2 \
  -usb \
  -audiodev sdl,id=snd0 \
  -device ich9-intel-hda \
  -device hda-output,audiodev=snd0 \
  -vga none \
  -display sdl,gl=on \
  -device virtio-gpu-pci \
  -netdev user,id=breh,hostfwd=tcp:127.0.0.1:8888-10.0.2.15:8888,hostfwd=tcp:127.0.0.1:8823-10.0.2.15:23,hostfwd=tcp:127.0.0.1:8000-10.0.2.15:8000,hostfwd=tcp:127.0.0.1:2222-10.0.2.15:22 \
  -device e1000,netdev=breh,bus=bridge1 \
  -drive file=$_disk_image,if=none,format=raw,id=boot-drive \
  -drive file=fat:rw:userdata,id=userdata-fat,format=raw,if=none \
  -drive file=_userdata_disk_image,format=raw,id=userdata,if=none \
  -chardev stdio,id=stdout,mux=on

