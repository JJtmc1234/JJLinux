# JJLinux

This distro is AGENTIC!

A from-scratch, agent-native Linux distribution built on Linux From Scratch 13.1-systemd,
with its own package manager (JPM), a maintained kernel patch series (jj-kernel), and an
AI agent layer (jjagentd) that observes and tunes the system.

## Status

**v0.4 "Capsule"** runs in the `LFS-13.1` QEMU/KVM (libvirt) VM: LFS 13.1-systemd plus the BLFS
stack up to Hyprland and the Omarchy desktop (see `docs/STATE.md`, `docs/BUILD-ENV.md`, and the stage
scripts in `recipes/blfs-13.1/`). **v0.1.1** was validated first: 10/10 boots, rescue and emergency
entries, and a package rebuild that reproduces (`docs/V0.1-VALIDATION.md`). The build started in VirtualBox.

The agent layer (JLAF: `jjagentd`, policy engine, JPM, jash) is developed in a separate repo that
currently exists only on the VM; see `docs/STATE.md`. Direction: kernel first (a `sched_ext` scheduler
and in-kernel decision table), with the userspace agent as the support layer.

## Layout

| Path | What lives there |
|---|---|
| `docs/` | Scope, decisions, build notes, current state (`STATE.md`) |
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
