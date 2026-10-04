# JJLinux DEVIATIONS

Every departure from LFS 13.1-systemd as written. One line each: what changed, and why.

## Build environment (outside the book)
- VM: VirtualBox `--hpet on` - fixes a VirtualBox timer bug on AMD Ryzen hosts that caused RCU stalls and multi-second sleep overruns (VirtualBox ticket #20131); measured before and after.
- Build host: passwordless sudo for `jj` on the Debian VM - convenience on a throwaway build host.
- Build host: DVD `cdrom:` apt source commented out - it broke `apt update`.

## Chapter 2
- 2.4: ESP is 1 GiB (book suggests 128-256 MB) - room for multiple kernels or a later systemd-boot without repartitioning.
- 2.4: Dedicated 4 GiB swap partition on the LFS disk (book allows sharing host swap) - so LFS boots with the Debian disk detached. NOTE: the scope doc says swapfile; the VM keeps this partition, and the Nexus install uses a swapfile.
- 2.5: Filesystem labels added (`lfs-root`, `lfs-swap`, `LFS-ESP`) - readable `lsblk -f`, plus a fallback identifier.
- 2.4/2.5: Every destructive command targeted `/dev/disk/by-id/ata-VBOX_HARDDISK_VB38b1eec0-46d9cf21` instead of `/dev/sdX` - sda/sdb swapped between the installer and the installed system.
- 2.7: Host fstab line uses `UUID=`, `nofail`, fsck pass `2` (book example: `/dev/<xxx> ... 1 1`) - stable naming; Debian still boots if the LFS disk is detached; pass 1 belongs to the host root.
- 2.7: `/mnt/lfs/README.md` ("This distro is AGENTIC!") added - JJ's request; no effect on the build.

## Chapter 3
- 3.1: Used `wget-list` (the 13.1 download dir has no `wget-list-systemd`) - it is a combined SysV and systemd list; the 4 SysV-only files (sysklogd, sysvinit tarball and patch, udev-lfs) were moved to `sources/unused-sysv/`. All 94 systemd `md5sums` entries verified OK.
- 3.1: `wget -nv` - quieter output only.

## Chapter 4
- 4.3: `passwd lfs` skipped - optional per the book; we only `su - lfs` from root.

## Chapters 5-7 (process, not commands)
- Builds run inside tmux on the build host - an SSH drop must not kill a compile.
- Every package is wrapped as `{ time { ... } ; } 2>&1 | tee logs/<section>-<pkg>.log` - build logs feed JPM recipes; `time` is the book's own SBU advice.
- 5.5: Glibc configure/make/install chain is prefixed with a guard (`whoami` = lfs and `LFS` = /mnt/lfs) - enforces the book's Warning about installing Glibc onto the host.
- 5.6 onward: packages are built by scripts in `recipes/lfs-13.1/` with the book's commands verbatim, stop-on-first-error, and per-package logs; the 5.5 sanity checks are asserted automatically.
- 7.6: `exec /usr/bin/bash --login` skipped inside the script - it only refreshes the interactive prompt.
- 7.3: virtual file system mounts are idempotent (`mountpoint -q || mount`) - safe re-entry after a reboot.
