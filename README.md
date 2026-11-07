# JJLinux

This distro is AGENTIC!

A from-scratch, agent-native Linux distribution built on Linux From Scratch 13.1-systemd,
with its own package manager (JPM), a maintained kernel patch series (jj-kernel), and an
AI agent layer (jjagentd) that observes and tunes the system.

## Status

**v0.1.1** is done: LFS 13.1-systemd boots 10/10, rescue and emergency entries work, and a
package rebuild reproduces (see `docs/V0.1-VALIDATION.md`). The build started in VirtualBox and
now lives in a QEMU/KVM (libvirt) VM (see `docs/BUILD-ENV.md`).
Next: package tracking + recipes (JPM), then BLFS toward Hyprland (v0.5).

## Layout

| Path | What lives there |
|---|---|
| `docs/` | Scope, decisions, build notes |
| `DEVIATIONS.md` | Every departure from the LFS/BLFS books, one line each, with the reason |
| `logs/lfs-13.1/` | Build logs from the LFS build (feed future JPM recipes) |
| `recipes/` | JPM build recipes (TOML), from Phase 3 |
| `kernel/` | Kernel defconfig and the jj-kernel patch series |
| `jpm/` | JPM package manager (Python) |
| `jjagentd/` | Agent daemon |
| `jash/` | Agentic shell layer over bash |

## Rules

- Follow the book by default; every deviation gets a line in `DEVIATIONS.md`.
- Work happens on branches and arrives as PRs; JJ merges to `main`.
