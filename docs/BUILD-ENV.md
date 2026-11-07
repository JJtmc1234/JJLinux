# Build environment (LFS 13.1-systemd)

## Current: QEMU/KVM (libvirt)

- Host machine: `mother` (Omarchy), libvirt `qemu:///system`
Two libvirt domains share the images in `/var/lib/libvirt/images/jj-linux/` (btrfs nocow directory):

- **`LFS-13.1`** - boots JJLinux itself. BIOS (i440fx), 36 vCPU, 64 GiB RAM, one VirtIO disk `lfs-boot.qcow2` (500 GiB overlay with `lfs.qcow2` as its backing file), NAT on the `default` network. This is the domain to start. As of 2026-11-07 it boots JJLinux 0.4 (Capsule), hostname `jjlinux2`, kernel 7.1.8, Hyprland installed, boot in about 3.3 s.
- **`jj-linux`** - the Debian 13.7.0 build host (GCC 14.2.0, Binutils 2.44). 36 vCPU (1 socket, 18 cores, 2 threads, host-passthrough), 128 GiB RAM, Q35. Disks: `jj-linux.qcow2` (100 GiB, `vda`) and `lfs.qcow2` (500 GiB, `vdb`, the LFS target).

Images:
- `jj-linux.qcow2` - Debian build host
- `lfs.qcow2` - LFS target disk and the overlay's backing file. Do not start `jj-linux` or write to `lfs.qcow2` while `lfs-boot.qcow2` holds newer state, or the overlay is corrupted.
- `lfs-boot.qcow2` - overlay used by `LFS-13.1`

Reach the guest: `ssh jj@$(virsh -c qemu:///system domifaddr LFS-13.1 | awk '/ipv4/{print $4}' | cut -d/ -f1)`

## Original: VirtualBox (through v0.1.1, 2026-10-04 to 2026-10-05)

- Host machine: Nexus (Omarchy), VirtualBox 7.2.16
- VM: `LFS-13.1`, EFI, 16 vCPU, 16 GiB RAM, HPET on (AMD timer-bug fix), NAT SSH 127.0.0.1:2222 (`ssh lfs`)
- Build host OS: Debian 13.7.0 headless, GCC 14.2.0, Binutils 2.44
- LFS disk: `/dev/disk/by-id/ata-VBOX_HARDDISK_VB38b1eec0-46d9cf21` (100 GiB, GPT)
  - part1 1 GiB ESP vfat `LFS-ESP`
  - part2 4 GiB swap `lfs-swap`
  - part3 95 GiB ext4 `lfs-root`, UUID 98237595-85ef-4456-9093-30353d204ea4, mounted at /mnt/lfs
- SBU: 24.9 s (Binutils pass 1)
