#!/bin/bash
# JJLinux -- BLFS stage C7: the "platform" stage.  About 60-90 min of real work, all resumable.
#   1 display    caps the VM desktop at 1920x1080 (software rendering is the bottleneck, so fewer pixels = faster)
#   2 qga        QEMU guest agent (qemu-ga only) + udev rule + systemd unit  -> clean shutdown, fs-freeze snapshots, IP reporting
#   3 nodejs     newest Node LTS built from source (bundled deps), npm
#   4 claude     Claude Code (npm i -g @anthropic-ai/claude-code)  -> `claude` on every login
#   5 kernelws   AGENTIC KERNEL WORKSPACE: /usr/src/jj-kernel (git repo), kernel 7.1.8 source, jj_defconfig, CLAUDE.md agent brief,
#                jj-kernel-audit / jj-kernel-build / jj-agent-kernel helpers
#   6 kernelbuild first test kernel "7.1.8-jj" (adds virtio console/balloon/gpu + loadable modules). NEVER touches your current
#                kernel, grub.cfg or the default boot entry - it only stages /boot/vmlinuz-7.1.8-jj and prints a GRUB snippet.
#   7 nvstage    downloads the NVIDIA driver installer + writes jj-nvidia-install for later (needs the A1000 passed through)
# Run after C6:   sudo bash blfs-c7-platform.sh     (resumable; the kernel and Node compiles are the long parts)
# Optional steps (claude, nvstage) may fail without stopping the run.
set -euo pipefail

# ------------------------------------------------------------------ common settings
JJ_STAGE=c7
TOTAL=7
SRC=/sources/blfs-c
BUILD=/var/tmp/blfs-c-build
STATE=/var/lib/blfs-c
LOGD=/var/log/blfs-c
n=0
T_ALL=$SECONDS

[ "$(id -u)" = 0 ] || { echo "Run as root:  su -"; exit 1; }
BASEPATH=/usr/bin:/usr/sbin
export PATH=$BASEPATH
mkdir -p "$SRC" "$BUILD" "$STATE" "$LOGD"

# --redo NAME [NAME...]  : forget finished packages so they get rebuilt
if [ "${1:-}" = "--redo" ]; then
  shift
  for r in "$@"; do rm -fv "$STATE/$r.done"; done
fi

RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
JOBS=$(( RAM_GB / 2 )); NP=$(nproc)
[ "$JOBS" -le "$NP" ] || JOBS=$NP
[ "$JOBS" -ge 1 ] || JOBS=1
export MAKEFLAGS="-j$JOBS" NINJAJOBS="$JOBS" CARGO_BUILD_JOBS="$JOBS"
export XORG_PREFIX=/usr
export XORG_CONFIG="--prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static"
echo "JJLinux stage C7 (platform: guest agent, Node + Claude Code, agentic kernel workspace, GPU prep) | RAM ${RAM_GB} GB, $NP CPUs -> $JOBS parallel jobs"

# ------------------------------------------------------------------ preflight
echo "=== preflight ==="
pf_fail=0
for t in gcc g++ make meson ninja cmake python3 pip3 curl git patch pkg-config bison flex xz tar; do
  command -v "$t" >/dev/null 2>&1 || { echo "  MISSING tool: $t"; pf_fail=1; }
done
curl -fsS -o /dev/null --connect-timeout 15 -r 0-99 https://github.com/ \
  || { echo "  CANNOT reach github.com over HTTPS"; pf_fail=1; }
FREE_GB=$(df -BG --output=avail /var/tmp | tail -n1 | tr -dc 0-9)
[ "${FREE_GB:-0}" -ge 30 ] || { echo "  Only ${FREE_GB} GB free in /var/tmp (want 30+)"; pf_fail=1; }
[ -d /usr/share/omarchy ] || { echo "  stage C6 (blfs-c6-omarchy.sh) has not finished - run it first"; pf_fail=1; }
[ "$(uname -r | sed 's/-.*//')" = 7.1.8 ] || echo "  note: running kernel is $(uname -r); this stage builds 7.1.8 sources (fine, but check it matches your /boot kernel)"
command -v bc >/dev/null || { echo "  MISSING tool: bc (kernel build needs it)"; pf_fail=1; }
command -v perl >/dev/null || { echo "  MISSING tool: perl (kernel build needs it)"; pf_fail=1; }
curl -fsS -o /dev/null --connect-timeout 15 -r 0-99 https://cdn.kernel.org/ || { echo "  CANNOT reach cdn.kernel.org"; pf_fail=1; }
[ "$pf_fail" = 0 ] || { echo "Preflight failed - fix the above and re-run."; exit 1; }
echo "  ok (${FREE_GB} GB free)"

# ------------------------------------------------------------------ sources
# file|url[,mirror...]|md5   (md5 '-' = no published checksum; we sanity-check the archive and log our own md5)
cat > "$SRC/list-$JJ_STAGE.txt" << 'LISTEOF'
linux-7.1.8.tar.xz|https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.1.8.tar.xz|-
LISTEOF

fetch_one() {   # fetch_one FILE URL[,URL...] MD5
  local f=$1 u=$2 m=$3 got url okdl=0
  if [ -s "$SRC/$f" ]; then
    if [ "$m" = - ]; then return 0; fi
    got=$(md5sum "$SRC/$f" | cut -d' ' -f1)
    if [ "$got" = "$m" ]; then return 0; fi
    rm -f "$SRC/$f"
  fi
  echo "  get $f"
  for url in ${u//,/ }; do
    rm -f "$SRC/$f.part"
    if curl -fL --retry 3 --retry-delay 3 --connect-timeout 20 -sS -o "$SRC/$f.part" "$url"; then
      got=$(md5sum "$SRC/$f.part" | cut -d' ' -f1)
      if [ "$m" = - ] || [ "$got" = "$m" ]; then okdl=1; break; fi
      echo "  (bad MD5 from $url - got $got, want $m; trying next mirror)"
    else
      echo "  (download failed from $url; trying next mirror)"
    fi
  done
  if [ "$okdl" != 1 ]; then echo "  FAIL $f  <- $u"; rm -f "$SRC/$f.part"; return 1; fi
  mv "$SRC/$f.part" "$SRC/$f"
  if [ "$m" = - ]; then
    if head -c 512 "$SRC/$f" | grep -qiE '<html|<!doctype'; then
      echo "  BAD $f (got an HTML page instead of the file)"; rm -f "$SRC/$f"; return 1
    fi
    case $f in
      *.tar.*|*.tgz) tar -tf "$SRC/$f" >/dev/null 2>&1 || { echo "  BAD $f (corrupt archive)"; rm -f "$SRC/$f"; return 1; } ;;
      *.gz)          gzip -t "$SRC/$f" 2>/dev/null     || { echo "  BAD $f (corrupt gzip)"; rm -f "$SRC/$f"; return 1; } ;;
    esac
    echo "$(md5sum "$SRC/$f" | cut -d' ' -f1)  $f" >> "$SRC/unverified.md5"
  fi
  return 0
}

echo "=== sources ($(grep -c . "$SRC/list-$JJ_STAGE.txt") files) ==="
dl_fail=0
while IFS='|' read -r f u m; do
  [ -n "$f" ] || continue
  case $f in \#*) continue ;; esac
  fetch_one "$f" "$u" "$m" || dl_fail=1
done < "$SRC/list-$JJ_STAGE.txt"
[ "$dl_fail" = 0 ] || { echo "Some downloads failed (see FAIL/BAD lines). Re-run to retry; verified files are skipped."; exit 1; }
echo "  all sources present and verified"

# ------------------------------------------------------------------ runner
setpath() {
  local p=$BASEPATH
  [ -d /opt/qt6/bin ]   && p=/opt/qt6/bin:$p
  [ -d /opt/rustc/bin ] && p=/opt/rustc/bin:$p
  [ -d /opt/go/bin ]    && p=/opt/go/bin:$p
  export PATH=$p
  local pc=/usr/lib/pkgconfig:/usr/share/pkgconfig
  [ -d /opt/qt6/lib/pkgconfig ] && pc=/opt/qt6/lib/pkgconfig:$pc
  export PKG_CONFIG_PATH=$pc
  [ -d /opt/qt6 ] && export CMAKE_PREFIX_PATH=/opt/qt6 QT6PREFIX=/opt/qt6
  return 0
}

runfn() {   # runfn NAME FUNCTION   (subshell with its own errexit, logs to $LOGD/NAME.log)
  local name=$1 fn=$2 t=$SECONDS rc
  set +e
  ( set -euo pipefail; "$fn" ) > "$LOGD/$name.log" 2>&1
  rc=$?
  set -e
  if [ "$rc" != 0 ]; then
    echo "!! $name FAILED (exit $rc). Last lines of $LOGD/$name.log:"
    tail -n 30 "$LOGD/$name.log"
    echo "Paste me the lines above. After a fix, re-run:  bash $(basename "$0")   (finished packages are skipped)"
    exit 1
  fi
  ldconfig || true
  touch "$STATE/$name.done"
  echo "      ok in $(( SECONDS - t ))s"
}

pkg() {   # pkg NAME TARBALL FUNCTION
  local name=$1 tarball=$2 fn=$3 top
  n=$((n + 1))
  if [ -f "$STATE/$name.done" ]; then echo "[$n/$TOTAL] $name  (already done)"; return 0; fi
  echo "[$n/$TOTAL] $name  ($(( (SECONDS - T_ALL) / 60 )) min so far)"
  if declare -F "hint_$name" >/dev/null; then "hint_$name"; fi
  setpath
  rm -rf "${BUILD:?}/$name"; mkdir -p "$BUILD/$name"
  tar -xf "$SRC/$tarball" -C "$BUILD/$name"
  top=$( { tar -tf "$SRC/$tarball" 2>/dev/null || true; } | head -n1 | cut -d/ -f1 )
  top=${top#./}
  cd "$BUILD/$name/$top"
  runfn "$name" "$fn"
  cd /
  rm -rf "${BUILD:?}/$name"
}

step() {  # step NAME FUNCTION   (no tarball)
  local name=$1 fn=$2
  n=$((n + 1))
  if [ -f "$STATE/$name.done" ]; then echo "[$n/$TOTAL] $name  (already done)"; return 0; fi
  echo "[$n/$TOTAL] $name"
  setpath
  cd /
  runfn "$name" "$fn"
}

# ------------------------------------------------------------------ build helpers (the book's common patterns)
sh_meson() {      # sh_meson [extra meson args]  - the book's "mkdir build; meson setup ..; ninja; ninja install"
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release "$@"
  ninja
  ninja install
}
sh_auto() {       # sh_auto [extra configure args]
  ./configure --prefix=/usr "$@"
  make
  make install
}
sh_cmake() {      # sh_cmake [extra cmake args]
  mkdir -p build; cd build
  cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -G Ninja "$@" ..
  ninja
  ninja install
}
chk() {  # chk "label" command...   (verification only; never fatal)
  local label=$1 out; shift
  out=$( { "$@" 2>&1 || true; } | head -n1 )
  if [ -n "$out" ] && ! printf '%s' "$out" | grep -qiE 'not found|no such|error|cannot|unknown module|failed'; then
    printf '  ok   %-16s %s\n' "$label" "$out"; ok=$((ok+1))
  else
    printf '  FAIL %-16s %s\n' "$label" "${out:-<no output>}"; bad=$((bad+1))
  fi
}

# ================================================================== recipes
KV=7.1.8
KD=/usr/src/jj-kernel
JU=jj
JH=$(getent passwd "$JU" | cut -d: -f6)
OPTFAIL=$STATE/c7-optional-failed.txt
optfail() { echo "$1" >> "$OPTFAIL"; echo "  (optional step '$1' failed - the rest does not depend on it; see $LOGD/$1.log)"; }

# ---------------------------------------------------------------- 1. display cap
b_display() {
  local f=$JH/.config/hypr/monitors.lua own
  [ -f "$f" ] || { echo "no $f - skipping"; return 0; }
  grep -q 'JJLINUX-1080' "$f" && { echo "already capped"; return 0; }
  own=$(stat -c %u:%g "$f")
  cp -n "$f" "$f.pre-c7"
  sed -i 's|mode = "preferred"|mode = "1920x1080@60"|' "$f"
  printf '%s\n' '-- JJLINUX-1080: VM desktop capped at 1080p (software rendering). Lift after GPU passthrough.' >> "$f"
  chown "$own" "$f" "$f.pre-c7"
  grep -n 'hl.monitor' "$f"
}

# ---------------------------------------------------------------- 2. QEMU guest agent (only qemu-ga)
b_qga() {
  local idx f
  idx=$(curl -fsS https://download.qemu.org/)
  f=$(printf '%s' "$idx" | grep -o 'qemu-[0-9]*\.[0-9]*\.[0-9]*\.tar\.xz' | sort -uV | tail -n1)
  [ -n "$f" ] || { echo "could not find a qemu tarball on download.qemu.org"; return 1; }
  echo "using $f"
  fetch_one "$f" "https://download.qemu.org/$f" - || return 1
  rm -rf "$BUILD/qemu"; mkdir -p "$BUILD/qemu"
  tar -xf "$SRC/$f" -C "$BUILD/qemu"
  cd "$BUILD/qemu"/qemu-*
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --python="$(command -v python3)" \
      --disable-system --disable-user --disable-linux-user --disable-bsd-user --disable-tools --disable-docs \
      --disable-werror --enable-guest-agent
  make -j"$JOBS"
  install -Dm755 build/qga/qemu-ga /usr/bin/qemu-ga
  cat > /etc/udev/rules.d/99-qemu-guest-agent.rules << 'EOF'
SUBSYSTEM=="virtio-ports", ATTR{name}=="org.qemu.guest_agent.0", TAG+="systemd", ENV{SYSTEMD_WANTS}="qemu-guest-agent.service"
EOF
  cat > /etc/systemd/system/qemu-guest-agent.service << 'EOF'
[Unit]
Description=QEMU Guest Agent
BindsTo=dev-virtio\x2dports-org.qemu.guest_agent.0.device
After=dev-virtio\x2dports-org.qemu.guest_agent.0.device

[Service]
ExecStart=-/usr/bin/qemu-ga
Restart=always
RestartSec=0
EOF
  systemctl daemon-reload || true
  udevadm control --reload || true
  /usr/bin/qemu-ga --version
  cd /; rm -rf "$BUILD/qemu"
}

# ---------------------------------------------------------------- 3. Node.js LTS from source
b_nodejs() {
  local v f
  v=$(python3 - << 'PY'
import json, urllib.request
d = json.load(urllib.request.urlopen('https://nodejs.org/dist/index.json', timeout=40))
print(next(x['version'] for x in d if x['lts']))
PY
)
  f=node-$v.tar.xz
  echo "Node LTS: $v"
  fetch_one "$f" "https://nodejs.org/dist/$v/$f" - || return 1
  rm -rf "$BUILD/node"; mkdir -p "$BUILD/node"
  tar -xf "$SRC/$f" -C "$BUILD/node"
  cd "$BUILD/node/node-$v"
  ./configure --prefix=/usr
  make -j"$JOBS"
  make install
  node --version; npm --version
  cd /; rm -rf "$BUILD/node"
}

# ---------------------------------------------------------------- 4. Claude Code
b_claude() {
  npm install -g --no-fund --no-audit @anthropic-ai/claude-code
  command -v claude
  claude --version
}
b_claude_try() { if ( set -e; b_claude ); then :; else optfail claude; fi; }

# ---------------------------------------------------------------- 5. agentic kernel workspace
b_kernelws() {
  mkdir -p "$KD/configs" "$KD/audit" "$KD/scripts"
  [ -d "$KD/linux-$KV" ] || tar -xf "$SRC/linux-$KV.tar.xz" -C "$KD"
  ln -sfn "linux-$KV" "$KD/linux"
  cd "$KD/linux"
  if [ ! -f .config ]; then
    if [ -r /proc/config.gz ]; then zcat /proc/config.gz > .config; echo "base config: /proc/config.gz"
    elif ls /boot/config-* >/dev/null 2>&1; then cp "$(ls -t /boot/config-* | head -n1)" .config; echo "base config: $(ls -t /boot/config-* | head -n1)"
    else make defconfig; echo "base config: x86_64 defconfig (no running config found)"; fi
    cp .config "$KD/configs/base-config.txt"
    # JJLinux additions: virtio bits the hypervisor features need, loadable modules for the NVIDIA driver, and a separate version tag
    scripts/config --set-str LOCALVERSION "-jj" \
      -e MODULES -e MODULE_UNLOAD \
      -e VIRTIO_CONSOLE -e VIRTIO_BALLOON -e HW_RANDOM_VIRTIO -e VIRTIO_INPUT -e DRM_VIRTIO_GPU
    make olddefconfig
  fi
  make savedefconfig
  cp defconfig "$KD/configs/jj_defconfig"

  # ---- helper: facts for the agent (read-only)
  cat > /usr/bin/jj-kernel-audit << 'EOF'
#!/bin/bash
# jj-kernel-audit -- read-only facts about this machine for kernel tuning (humans and agents)
echo "== kernel";   uname -a
echo "== cmdline";  cat /proc/cmdline
echo "== cpu";      lscpu | sed -n '1,20p'
echo "== pci";      lspci -nnk 2>/dev/null
echo "== virtio";   ls /sys/bus/virtio/devices 2>/dev/null; ls /dev/virtio-ports 2>/dev/null
echo "== modules";  lsmod 2>/dev/null | head -n 40
echo "== block";    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
echo "== drm";      ls -l /dev/dri 2>/dev/null
echo "== config deltas vs base"
D=/usr/src/jj-kernel
[ -f "$D/linux/.config" ] && [ -f "$D/configs/base-config.txt" ] && diff <(grep -E '^(# )?CONFIG_' "$D/configs/base-config.txt" | sort) <(grep -E '^(# )?CONFIG_' "$D/linux/.config" | sort) | head -n 80
EOF
  chmod 755 /usr/bin/jj-kernel-audit

  # ---- helper: build a test kernel without touching the current boot
  cat > /usr/bin/jj-kernel-build << 'EOF'
#!/bin/bash
# jj-kernel-build [--menuconfig | --defconfig]
#   builds the tree in /usr/src/jj-kernel/linux, installs modules under /lib/modules/<release>, stages
#   /boot/vmlinuz-<release> + System.map + config, saves configs/jj_defconfig in git.
#   It NEVER edits grub.cfg and never overwrites an existing /boot file of another release.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
D=/usr/src/jj-kernel
cd "$D/linux"
case "${1:-}" in
  --menuconfig) make menuconfig ;;
  --defconfig)  cp "$D/configs/jj_defconfig" .config ;;
esac
make olddefconfig
make -j"$(nproc)"
REL=$(make -s kernelrelease)
if grep -q '^CONFIG_MODULES=y' .config; then make modules_install; fi
install -Dm644 arch/x86/boot/bzImage "/boot/vmlinuz-$REL"
install -Dm644 System.map "/boot/System.map-$REL"
install -Dm644 .config "/boot/config-$REL"
make savedefconfig
cp defconfig "$D/configs/jj_defconfig"
git -C "$D" add -A configs audit scripts CLAUDE.md 2>/dev/null || true
git -C "$D" -c user.name=JJLinux -c user.email=jjlinux@localhost commit -qm "kernel $REL built $(date -Is)" 2>/dev/null || true
echo
echo "built $REL -> /boot/vmlinuz-$REL"
echo "To try it (do NOT replace your working entry - add a second one to /boot/grub/grub.cfg by copying your current menuentry and changing only the kernel file name):"
echo "    linux /boot/vmlinuz-$REL $(sed 's/^BOOT_IMAGE=[^ ]* //' /proc/cmdline)"
EOF
  chmod 755 /usr/bin/jj-kernel-build

  cat > /usr/bin/jj-agent-kernel << 'EOF'
#!/bin/bash
# jj-agent-kernel -- start Claude Code inside the kernel workspace (it reads CLAUDE.md there)
cd /usr/src/jj-kernel && exec claude "$@"
EOF
  chmod 755 /usr/bin/jj-agent-kernel

  cat > "$KD/CLAUDE.md" << 'EOF'
# JJLinux kernel workspace (agent brief)

You are helping JJ build and tune the JJLinux kernel.  Source: ./linux (7.1.8).  Tracked config: configs/jj_defconfig.

## Rules (hard)
- Build only with `sudo jj-kernel-build` (add `--menuconfig` to edit).  Do not run `make install`, do not touch /boot files of the
  currently running kernel, and do not change which kernel boots by default.  Test kernels get a SECOND grub entry; JJ adds it.
- Emergency / rescue boot must never be locked and must never ask for a password.  Do not add boot passwords or lockdown that would.
- Use `scripts/config` for single options, then `make olddefconfig`.  Commit every meaningful config change to git here with a
  message that says WHY.  Never commit secrets.
- Prefer small, reversible steps.  Explain in plain words what each option is for before changing it.

## Targets
1. This libvirt/QEMU VM (virtio devices, no initramfs).
2. Later: bare metal (Threadripper PRO, NVIDIA RTX PRO 6000 Blackwell + RTX A1000).  Keep NVIDIA's open kernel modules in mind (loadable modules on).

## Useful commands
- `jj-kernel-audit` (read-only hardware/config facts), `git log --oneline`, `git diff HEAD~1 -- configs/`.
- Goals, in order: boot reliably -> trim drivers the machine does not have -> faster boot -> hardening that does not lock JJ out.
EOF
  cd "$KD"
  [ -d .git ] || git init -q
  printf 'linux-*/\nlinux\n*.log\n' > .gitignore
  git add -A
  git -c user.name=JJLinux -c user.email=jjlinux@localhost commit -qm "initial kernel workspace (kernel $KV)" || true
  git log --oneline | head -n 3
}

# ---------------------------------------------------------------- 6. first test kernel
b_kernelbuild() {
  /usr/bin/jj-kernel-build
}

# ---------------------------------------------------------------- 7. NVIDIA installer (for the passed-through A1000)
b_nvstage() {
  local line ver f
  line=$(curl -fsS https://download.nvidia.com/XFree86/Linux-x86_64/latest.txt)
  ver=${line%% *}
  [ -n "$ver" ] || { echo "no NVIDIA version"; return 1; }
  f=NVIDIA-Linux-x86_64-$ver.run
  echo "NVIDIA driver $ver"
  fetch_one "$f" "https://download.nvidia.com/XFree86/Linux-x86_64/$ver/$f" - || return 1
  cat > /usr/sbin/jj-nvidia-install << EOF
#!/bin/bash
# jj-nvidia-install -- install the NVIDIA kernel module + nvidia-smi/CUDA userspace (NO OpenGL files: Mesa stays the GL stack).
# Run only AFTER the A1000 is passed through and you booted the -jj kernel (needs /lib/modules/\$(uname -r)/build).
set -e
[ "\$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
lspci -nn | grep -qi nvidia || { echo "no NVIDIA device visible - pass the A1000 through first"; exit 1; }
[ -e /lib/modules/\$(uname -r)/build ] || ln -sfn /usr/src/jj-kernel/linux /lib/modules/\$(uname -r)/build
sh $SRC/$f --silent --no-x-check --no-nouveau-check --no-opengl-files --no-install-libglvnd --kernel-module-type=open
modprobe nvidia && nvidia-smi
EOF
  chmod 755 /usr/sbin/jj-nvidia-install
  echo "installer staged: $SRC/$f  ->  run later: sudo jj-nvidia-install"
}
b_nvstage_try() { if ( set -e; b_nvstage ); then :; else optfail nvstage; fi; }

step display      b_display
step qga          b_qga
step nodejs       b_nodejs
step claude       b_claude_try
step kernelws     b_kernelws
step kernelbuild  b_kernelbuild
step nvstage      b_nvstage_try


# ------------------------------------------------------------------ verification (non-fatal)
echo
echo "=== verification ==="
setpath
ok=0; bad=0
chk display      sh -c "grep -c JJLINUX-1080 $JH/.config/hypr/monitors.lua"
chk qemu-ga      sh -c 'qemu-ga --version'
chk qga-unit     sh -c 'ls /etc/systemd/system/qemu-guest-agent.service /etc/udev/rules.d/99-qemu-guest-agent.rules'
chk node         sh -c 'node --version'
chk npm          sh -c 'npm --version'
chk claude       sh -c 'claude --version'
chk kernel-repo  sh -c "git -C $KD log --oneline | head -n1"
chk kernel-img   sh -c 'ls /boot/vmlinuz-*-jj'
chk kernel-mods  sh -c 'ls -d /lib/modules/*-jj'
chk audit        sh -c 'jj-kernel-audit | head -n1'
chk nv-installer sh -c 'ls /usr/sbin/jj-nvidia-install'
echo
if [ -s "$OPTFAIL" ]; then
  echo "optional steps that failed (nothing else depends on them):"; sort -u "$OPTFAIL" | sed 's/^/   /'
fi
if [ "$bad" = 0 ]; then
  echo "=== BLFS stage C7 DONE in $(( (SECONDS - T_ALL) / 60 )) min  ($ok checks passed) ==="
else
  echo "=== stage C7 built but $bad check(s) FAILED ($ok passed) -- paste the FAIL lines to me ==="
fi
cat << 'MSG'

What you got:
  * VM desktop capped at 1080p (log out/in, or reboot, to apply)
  * qemu-ga installed.  It only wakes up once the running kernel has virtio-console and libvirt gives the VM an
    org.qemu.guest_agent.0 channel.  The -jj test kernel has the first; Mother's VM XML needs the second (check:
    virsh -c qemu:///system dumpxml LFS-13.1 | grep guest_agent).
  * Node + Claude Code:   claude            (log in once)
  * Agentic kernel:       jj-agent-kernel   (Claude Code inside /usr/src/jj-kernel with the rules in CLAUDE.md)
                          jj-kernel-audit   (read-only facts)     sudo jj-kernel-build [--menuconfig]
  * Test kernel staged:   /boot/vmlinuz-7.1.8-jj  (your current kernel and grub.cfg were NOT touched).
    To try it, add a SECOND menuentry to /boot/grub/grub.cfg (the exact `linux` line was printed above, in
    /var/log/blfs-c/kernelbuild.log).  Keep your old entry as the fallback.
  * GPU passthrough prep: run  bash jj-vfio-a1000.sh  on MOTHER (dry run first).  After the VM boots with the A1000:
    sudo jj-nvidia-install   (kernel module + nvidia-smi/CUDA; no OpenGL, Mesa stays)
MSG
