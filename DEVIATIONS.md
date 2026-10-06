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
- 7.3: `mount --make-private $LFS/dev` after the bind mount - Debian's /dev is a shared mount, so /dev/pts and /dev/shm mounted under $LFS propagated back onto the host's /dev.
- 7.15.2: backup compressed with `XZ_OPT=-T0` (all cores) - speed only. Backup taken at the start of Ch. 8 (after 8.3-8.4 and the JPM baseline) as `lfs-ch8-start-13.1.tar.xz`, because the first attempt overlapped a running build.

## Chapter 8
- Every package is tracked by JPM v0 (`jpm-track.sh`): file lists with sha256, mode and owner, the recipe, and test results in /var/lib/jpm.
- Test suites never abort a batch; failures are recorded per package and reviewed against the book's known-failure lists. Build or install failures stop the batch.
- 8.5.2.2: time zone set to America/Los_Angeles directly (`tzselect` is interactive).
- 8.18: the book's PTY check is asserted (with `\r` stripped, since a PTY outputs "ok\r\n").
- 8.23: GMP's ">= 199 PASS" requirement is asserted; 8.32: GCC's sanity checks are asserted.
- 8.30.3: `passwd root` is run by hand after batch 2 (interactive).
- 8.39: `exec /usr/bin/bash --login` is run in the interactive shell after batch 3, not inside the script.
- 8.54: the book's optional /etc/pip.conf is installed.

## Chapters 9-11
- 9.2.1.3: DHCP .network matches `Name=en*` instead of one hard-coded interface name.
- 9.2.3: hostname `jjlinux-1`; 11.1: /etc/os-release and /etc/lsb-release branded JJLinux 0.1-dev (the LFS version stays in /etc/lfs-release).
- 10.2: fstab uses PARTUUID (root) and UUID (swap, ESP), as the book's notes suggest.
- 10.3: kernel configured as `make defconfig` + `scripts/config` for every option the book requires (asserted after `olddefconfig`), instead of interactive menuconfig. Saved as `kernel/jjlinux-7.1.8.defconfig`.
- 10.4: grub.cfg uses `search --fs-uuid` + `root=PARTUUID=` (book note), plus rescue.target and emergency.target entries (scope v0.1).
- Console log level lowered via /etc/sysctl.d/10-console-loglevel.conf (`kernel.printk = 3 4 1 3`) - defconfig printed debug chatter on the console.

## BLFS
- OpenSSH 10.5p1 built from the Debian host in chroot (book 11.5.2.1), because LFS has no downloader. Root login and password login disabled (BLFS-recommended hardening).
- User `jj` (wheel, users) with key-only login; account set to `*` (not `!`), because OpenSSH without PAM rejects key logins to locked accounts.
- Sudo 1.9.17p2: book's /etc/sudoers.d/00-sudo, plus `jj ALL=(ALL) NOPASSWD: ALL` (jj has key-only login, so there is no password to type).
- BLFS packages are downloaded on Nexus and copied to /sources over SSH until wget/curl exist; builds run natively on JJLinux, tracked by JPM.
- JPM scans skip /var/log, /var/cache and /var/lib/systemd on the live system (journal and systemd state change constantly and are not package files).
- curl and git: optional BLFS test suites skipped (long); git built with NO_RUST=1 (rustc not installed - BLFS's own option).
- Long BLFS builds run as transient systemd units (`systemd-run --unit=...`) so they survive SSH disconnects.

## v0.1 validation
- grub.cfg reads grubenv and honors a one-shot `next_entry`, so `grub-reboot` can select rescue/emergency boots (used for automated validation).
- Rebuild check compares stripped code for ELF files: the original Ch. 8 binaries carry debug info that is not bit-reproducible.
