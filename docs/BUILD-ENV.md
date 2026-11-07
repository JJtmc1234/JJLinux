# Build environment (LFS 13.1-systemd)

## Current: QEMU/KVM (libvirt)

- Host machine: `mother` (Omarchy), libvirt `qemu:///system`
- VM: libvirt domain `jj-linux`, 36 vCPU (1 socket, 18 cores, 2 threads, host-passthrough), 128 GiB RAM, VirtIO disks/net/video, SPICE display, NAT on the `default` network
- Images live in `/var/lib/libvirt/images/jj-linux/` (btrfs nocow directory):
  - `jj-linux.qcow2` - 100 GiB, `vda`, Debian 13.7.0 build host (GCC 14.2.0, Binutils 2.44)
  - `lfs.qcow2` - 500 GiB, `vdb`, LFS target disk
  - `lfs-boot.qcow2` - 500 GiB overlay with `lfs.qcow2` as its backing file. Not attached to the domain. Do not write to `lfs.qcow2` directly while the overlay exists.
- Reach the guest: `ssh jj@$(virsh -c qemu:///system domifaddr jj-linux | awk '/ipv4/{print $4}' | cut -d/ -f1)`

## Original: VirtualBox (through v0.1.1, 2026-10-04 to 2026-10-05)

- Host machine: Nexus (Omarchy), VirtualBox 7.2.16
- VM: `LFS-13.1`, EFI, 16 vCPU, 16 GiB RAM, HPET on (AMD timer-bug fix), NAT SSH 127.0.0.1:2222 (`ssh lfs`)
- Build host OS: Debian 13.7.0 headless, GCC 14.2.0, Binutils 2.44
- LFS disk: `/dev/disk/by-id/ata-VBOX_HARDDISK_VB38b1eec0-46d9cf21` (100 GiB, GPT)
  - part1 1 GiB ESP vfat `LFS-ESP`
  - part2 4 GiB swap `lfs-swap`
  - part3 95 GiB ext4 `lfs-root`, UUID 98237595-85ef-4456-9093-30353d204ea4, mounted at /mnt/lfs
- SBU: 24.9 s (Binutils pass 1)
