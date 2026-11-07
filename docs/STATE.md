# JJLinux state (as of 2026-11-07; last VM activity 2026-11-01)

The VM `LFS-13.1` boots **JJLinux 0.4 "Capsule"** (`BUILD_ID="LFS 13.1-systemd + BLFS 13.1-systemd"`), hostname `jjlinux2`, kernel 7.1.8, boot about 3.3 s. How to start it: `BUILD-ENV.md`.

## What is installed

Built on top of v0.1.1 with the BLFS stage scripts in `recipes/blfs-13.1/`. Run in order, each is resumable and logs under `/var/log/blfs-c/`:

| Script | Stage |
|---|---|
| `blfs-b.sh` | B: toolchain and graphics base |
| `blfs-c1-pam.sh` | C1: Linux-PAM, Shadow with PAM, systemd rebuilt with PAM, seatd with logind. The risky one: snapshot first (`virsh snapshot-create-as LFS-13.1 pre-pam`). |
| `blfs-c2-xgfx.sh` | C2: Xorg libs, GLib, image libs, Cairo, Pango, Vulkan loader, Mesa (X11 + lavapipe) |
| `blfs-c3-services.sh` | C3: polkit, UPower, BlueZ, NetworkManager, PipeWire, WirePlumber and related services |
| `blfs-c4-qt6.sh` | C4: Qt 6.11.2 (only the modules Quickshell uses) into `/opt/qt6` |
| `blfs-c5-hyprland.sh` | C5: Hyprland 0.56.2 and its prerequisites |
| `blfs-c6-omarchy.sh` | C6: the Omarchy 4.0.0.alpha desktop. Needs `jj-omarchy-bundle.tgz`, which is not in this repo. |
| `blfs-c7-platform.sh` | C7: VM display cap, QEMU guest agent, other platform items |
| `run-chain.sh` | Runs C3 to C5 in the background |
| `ssh-pam.sh` | Rebuilds OpenSSH 10.5p1 with PAM so SSH logins get logind sessions |

Running now: systemd, NetworkManager, polkit, seatd, sshd. The VM is TTY-only (`~/.no-autostart`). Hyprland is installed but not started.

## What is not in this repo and not on the VM's PATH

- **JPM, jash and jjagentd are not installed.** `/var/lib/jpm` does not exist. The `jpm/`, `jash/` and `jjagentd/` directories here are still empty. The code is in JLAF (below).
- The JPM tracking database that `V0.1-VALIDATION.md` describes is not on this disk (`/var/lib/jpm` is missing).

## JLAF (JJLinux Agentic Features)

JLAF is a separate git repo that lives **only on the VM** at `~/jlaf` (branch `main`, 419 commits, last commit 2026-11-01, **no remote**). It holds:

- `daemon/` - `jjagentd`, a Go daemon (stdlib only) with `jlaf-ask`. JSON-RPC 2.0 on `/run/user/UID/jjagentd.sock`.
- `policy/` - the tier engine (T0 to T3). The model can only request a tier; the engine computes the real one and can only raise it. Append-only audit log.
- `tools/` - MCP servers: system, files, hypr, pkg.
- `jpm/`, `jash/`, `shell/` (Quickshell launcher), `sched/`, `kernel/`, `install/`, `tests/`.
- Coordination files: `PLAN.md` (36 work packages, then 8 kernel work packages), `STATUS.md`, `MORNING.md`, `QUESTIONS.md`, `REQUESTS.md`.
- `~/jlaf-kernel` is a pristine Linux 7.1.8 tree, with worktrees `~/jlaf-kernel-wt/k37..k44` for the kernel patch series. `~/jlaf-wt/` has one worktree per work package.

Direction as of 2026-11-01: **kernel first**. The agentic kernel is the main piece (a `sched_ext` scheduler and an in-kernel decision table in BPF, with a `jjguard` LSM skeleton). The userspace agent observes, tunes and explains. No model runs in kernel space.

Status of the JLAF work:
- Merged on JLAF `main`: the daemon, policy engine, tools, JPM install db and verify, the installer, the gate, the launcher. All build and pass the gate.
- Not done: nothing has run as real root, with a real API key, or against a real polkit prompt. The installer was only read and dry-run.
- Blocked until the kernel proposal (`kernel/sched/PROPOSAL.md`) is approved: any kernel or BPF build, any boot entry or GRUB change, any benchmark run, anything loaded into a running kernel.
- The VM has no QEMU or `/dev/kvm`, and its clang has no BPF backend, so BPF C is written and reviewed but cannot be compiled there yet.

## Open items

- Back up JLAF: it has no remote and is only on the VM disk.
- Fill the TODO values in the N2 media script before running it (`~/jlaf/overnight/blfs-n2-media.sh`).
- 59 programs the Omarchy scripts need have no JPM recipe.
- Decide on the open items in `~/jlaf/MORNING.md` section 4 and `QUESTIONS.md`.
