# JJLinux measurements

Rule (scope): at least 5 runs, report the median, compare on the same machine.

## v0.1-dev, first boot (2026-10-05, VM LFS-13.1: 16 vCPU, 16 GiB, HPET on)
- `systemd-analyze`: 1.359s (kernel) + 2.551s (userspace) = 3.911s (single run - baseline to be repeated 5x)
- Slowest units: dev-sda3.device 1.161s, systemd-resolved 1.046s, systemd-userdbd 993ms, systemd-nsresourced 990ms, systemd-timesyncd 907ms
- Build: SBU = 24.9s (Binutils pass 1). LFS Ch. 8 ~ 81 packages tracked by JPM, 58,638 indexed paths.

## v0.1 (2026-10-05)
- Median boot over 10 boots: 3.900s (range in V0.1-VALIDATION.md)
