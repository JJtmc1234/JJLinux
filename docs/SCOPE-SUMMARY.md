# JJLinux scope summary (locked 2026-10-04)

The full scope lives in the "JJLinux Scope v1" doc. This is the build-relevant summary.

- Current build: LFS 13.1-systemd as written. Package tracking starts at Chapter 8;
  Chapters 5-6 temporary tools get logs only. Never restart the build to retrofit tracking.
- Keep build logs for every package (they feed JPM recipes later).
- Kernel: Chapter 10 kernel config goes into git as a defconfig. Later it becomes
  "jj-kernel" (our patch series), but v0.1 uses the book's kernel, unpatched.
- Bootloader: GRUB per the book. Final target is quad-boot on Nexus
  (Windows/Fedora/Omarchy+Limine), own EFI/JJLinux entry, Secure Boot off.
- Filesystem: ext4 root, swapfile on Nexus (the VM keeps its swap partition). x86_64 only.
- v0.1 done = boots to login 10/10 in the VM, network+DNS, non-root sudo user,
  rescue/emergency boot entry works, one package rebuilt from documented steps.
- Next after v0.1: package tracking + recipes, then BLFS toward Hyprland (v0.5).
- Every deviation from the book gets one line in DEVIATIONS.md.
