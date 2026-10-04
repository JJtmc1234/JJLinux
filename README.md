# JJLinux

This distro is AGENTIC!

A from-scratch, agent-native Linux distribution built on Linux From Scratch 13.1-systemd,
with its own package manager (JPM), a maintained kernel patch series (jj-kernel), and an
AI agent layer (jjagentd) that observes and tunes the system.

## Status

Phase 1: building LFS 13.1-systemd in a VirtualBox VM (Chapter 5, cross-toolchain).
Next milestone: **v0.1** (base system boots in the VM).

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
