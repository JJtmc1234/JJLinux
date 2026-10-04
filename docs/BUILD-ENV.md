# Build environment (LFS 13.1-systemd)

- Host machine: Nexus (Omarchy), VirtualBox 7.2.16
- VM: `LFS-13.1`, EFI, 16 vCPU, 16 GiB RAM, HPET on (AMD timer-bug fix), NAT SSH 127.0.0.1:2222 (`ssh lfs`)
- Build host OS: Debian 13.7.0 headless, GCC 14.2.0, Binutils 2.44
- LFS disk: `/dev/disk/by-id/ata-VBOX_HARDDISK_VB38b1eec0-46d9cf21` (100 GiB, GPT)
  - part1 1 GiB ESP vfat `LFS-ESP`
  - part2 4 GiB swap `lfs-swap`
  - part3 95 GiB ext4 `lfs-root`, UUID 98237595-85ef-4456-9093-30353d204ea4, mounted at /mnt/lfs
- SBU: 24.9 s (Binutils pass 1)
