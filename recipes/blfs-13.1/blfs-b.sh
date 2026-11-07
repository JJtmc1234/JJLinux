#!/bin/bash
# JJLinux 0.4 "Capsule" -- BLFS stage B: toolchain + graphics base (run INSIDE the JJLinux VM as root).
#
#   scp ~/Downloads/blfs-b.sh jl2:       (from mother)
#   ssh jl2   then   su -   then   bash /home/jj/blfs-b.sh
#
# Downloads its own sources (the VM has working HTTPS since stage A) and checks the BLFS MD5s.
# Builds, in order (versions/commands from the BLFS 13.1-systemd book unless noted):
#   libxml2 libssh2  LLVM+clang  Rust+cargo-c  Mako PyYAML
#   libdrm wayland wayland-protocols  Mesa (llvmpipe, no libglvnd, Wayland only)
#   seatd (daemon + systemd unit; NOT in the 13.1 book -> svn page, daemon enabled)
#   xkeyboard-config libxkbcommon pixman  libpng freetype harfbuzz fontconfig fribidi DejaVu
# then bumps the identity to 0.4 "Capsule" and runs a real EGL/GLES check (llvmpipe).
# RESUMABLE: finished packages leave a marker in /var/lib/blfs-b; re-run after a failure.
# Logs: /var/log/blfs-b/<package>.log     Tests are skipped on purpose (speed).
set -euo pipefail

JJ_VERSION=0.4
JJ_CODENAME=Capsule

SRC=/sources/blfs-b
BUILD=/var/tmp/blfs-b-build
STATE=/var/lib/blfs-b
LOGD=/var/log/blfs-b
TOTAL=22
n=0
T_ALL=$SECONDS

[ "$(id -u)" = 0 ] || { echo "Run as root:  su -"; exit 1; }
BASEPATH=/usr/bin:/usr/sbin
export PATH=$BASEPATH
mkdir -p "$SRC" "$BUILD" "$STATE" "$LOGD"

RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
JOBS=$(( RAM_GB / 2 )); NP=$(nproc)
[ "$JOBS" -le "$NP" ] || JOBS=$NP
[ "$JOBS" -ge 1 ] || JOBS=1
export MAKEFLAGS="-j$JOBS" NINJAJOBS="$JOBS" CARGO_BUILD_JOBS="$JOBS"
echo "JJLinux $JJ_VERSION \"$JJ_CODENAME\" -- BLFS stage B | RAM ${RAM_GB} GB, $NP CPUs -> $JOBS parallel jobs"
echo "Expect roughly 1 to 1.5 hours total (LLVM and Rust are most of it)."

# ------------------------------------------------------------------ preflight (fail early, not at minute 40)
echo "=== preflight ==="
pf_fail=0
for t in gcc g++ make meson ninja cmake python3 pip3 curl git patch pkg-config bison flex xz; do
  command -v "$t" >/dev/null 2>&1 || { echo "  MISSING tool: $t"; pf_fail=1; }
done
python3 -c 'import markupsafe, setuptools' 2>/dev/null || { echo "  MISSING python module(s): markupsafe/setuptools"; pf_fail=1; }
curl -fsS -o /dev/null --connect-timeout 15 -r 0-99 https://static.rust-lang.org/dist/channel-rust-stable.toml \
  || { echo "  CANNOT reach static.rust-lang.org over HTTPS (Rust's bootstrap downloads its stage0 compiler)"; pf_fail=1; }
FREE_GB=$(df -BG --output=avail /var/tmp | tail -n1 | tr -dc 0-9)
[ "${FREE_GB:-0}" -ge 40 ] || { echo "  Only ${FREE_GB} GB free in /var/tmp (want 40+)"; pf_fail=1; }
[ "$pf_fail" = 0 ] || { echo "Preflight failed - fix the above and re-run."; exit 1; }
echo "  ok (${FREE_GB} GB free)"

# ------------------------------------------------------------------ sources
# file|url|md5   (md5 '-' = book gives none; we log our own in $SRC/unverified.md5)
cat > "$SRC/list.txt" << 'EOF'
libxml2-2.15.3.tar.xz|https://download.gnome.org/sources/libxml2/2.15/libxml2-2.15.3.tar.xz|b7b0123654f86ebf630a5cbedaafdece
libssh2-1.11.1.tar.gz|https://www.libssh2.org/download/libssh2-1.11.1.tar.gz|38857d10b5c5deb198d6989dacace2e6
libssh2-1.11.1-security_fixes-1.patch|https://www.linuxfromscratch.org/patches/blfs/13.1/libssh2-1.11.1-security_fixes-1.patch|-
llvm-project-22.1.8.src.tar.xz|https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz|69065494ebcb1150b2a329c1b3db7584
llvm-22.1.8-upstream_fix-1.patch|https://www.linuxfromscratch.org/patches/blfs/13.1/llvm-22.1.8-upstream_fix-1.patch|-
rustc-1.97.1-src.tar.xz|https://static.rust-lang.org/dist/rustc-1.97.1-src.tar.xz|c6fc3febcd3b1235cf4f00c3e05559b3
cargo-c-0.10.24.tar.gz|https://github.com/lu-zero/cargo-c/archive/v0.10.24/cargo-c-0.10.24.tar.gz|b6247bf8f5eac962f001ee8a37f1c25f
cargo-c-Cargo.lock|https://github.com/lu-zero/cargo-c/releases/download/v0.10.24/Cargo.lock|fd58412b6d608a57a7d9a7bf384dca03
mako-1.4.1.tar.gz|https://files.pythonhosted.org/packages/source/M/Mako/mako-1.4.1.tar.gz|9c09a897c23a34df7ba614ec2d7229e1
pyyaml-6.0.3.tar.gz|https://files.pythonhosted.org/packages/source/p/pyyaml/pyyaml-6.0.3.tar.gz|dbc6f815cd75160ccf12e470be1c8d6e
libdrm-2.4.134.tar.xz|https://dri.freedesktop.org/libdrm/libdrm-2.4.134.tar.xz|0e70607bb5c2f7ecbc411e6a2fab8b22
wayland-1.26.0.tar.xz|https://gitlab.freedesktop.org/wayland/wayland/-/releases/1.26.0/downloads/wayland-1.26.0.tar.xz|64c593ccf6820635765a952ec5f34fbb
wayland-protocols-1.49.tar.xz|https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/1.49/downloads/wayland-protocols-1.49.tar.xz|5685f769a227f2d4143d983ad07edaba
mesa-26.1.7.tar.xz|https://mesa.freedesktop.org/archive/mesa-26.1.7.tar.xz|1a3ea044abc823e2db8c6041e5adcc4f
seatd-0.9.3.tar.gz|https://github.com/kennylevinsen/seatd/archive/0.9.3/seatd-0.9.3.tar.gz|c1cc200188d31214b88af015b1f19f7b
xkeyboard-config-2.48.tar.xz|https://www.x.org/pub/individual/data/xkeyboard-config/xkeyboard-config-2.48.tar.xz|575106aff79b589abe4aff6c4bff4782
libxkbcommon-1.13.2.tar.gz|https://github.com/lfs-book/libxkbcommon/archive/v1.13.2/libxkbcommon-1.13.2.tar.gz|07f838f575d62c267cfc53eaf5ee739b
libxkbcommon-1.13.2-upstream_fix-1.patch|https://www.linuxfromscratch.org/patches/blfs/13.1/libxkbcommon-1.13.2-upstream_fix-1.patch|-
pixman-0.46.4.tar.gz|https://www.cairographics.org/releases/pixman-0.46.4.tar.gz|c08173c8e1d2cc79428d931c13ffda59
libpng-1.6.58.tar.xz|https://downloads.sourceforge.net/libpng/libpng-1.6.58.tar.xz|c6c372a9d7754c66e0b77a8d34987a3b
libpng-1.6.58-apng.patch.gz|https://downloads.sourceforge.net/sourceforge/libpng-apng/libpng-1.6.58-apng.patch.gz|1eef1ddd6def88814d1a65ce1f4dceb9
freetype-2.14.3.tar.xz|https://downloads.sourceforge.net/freetype/freetype-2.14.3.tar.xz|5e78e6fdce5a61d3075e4c25e9852f84
harfbuzz-14.3.1.tar.xz|https://github.com/harfbuzz/harfbuzz/releases/download/14.3.1/harfbuzz-14.3.1.tar.xz|4baccda978c92e5f27702ed8b3ceefa7
fontconfig-2.18.3.tar.xz|https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/2.18.3/fontconfig-2.18.3.tar.xz|ce819e229ca6fb7d1be47a192d6681a3
fribidi-1.0.16.tar.xz|https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz|333ad150991097a627755b752b87f9ff
dejavu-fonts-ttf-2.37.tar.bz2|https://downloads.sourceforge.net/dejavu/dejavu-fonts-ttf-2.37.tar.bz2|-
EOF

fetch_one() {   # fetch_one FILE URL MD5
  local f=$1 u=$2 m=$3 got
  if [ -s "$SRC/$f" ]; then
    if [ "$m" = - ]; then return 0; fi
    got=$(md5sum "$SRC/$f" | cut -d' ' -f1)
    if [ "$got" = "$m" ]; then return 0; fi
    rm -f "$SRC/$f"
  fi
  echo "  get $f"
  rm -f "$SRC/$f.part"
  if ! curl -fL --retry 3 --retry-delay 3 --connect-timeout 20 -o "$SRC/$f.part" "$u"; then
    echo "  FAIL $f  <- $u"; rm -f "$SRC/$f.part"; return 1
  fi
  mv "$SRC/$f.part" "$SRC/$f"
  got=$(md5sum "$SRC/$f" | cut -d' ' -f1)
  if [ "$m" = - ]; then
    # no book checksum: at least make sure we didn't save an HTML error page / a truncated archive
    if head -c 512 "$SRC/$f" | grep -qiE '<html|<!doctype'; then
      echo "  BAD $f (got an HTML page instead of the file)"; rm -f "$SRC/$f"; return 1
    fi
    case $f in
      *.tar.*) tar -tf "$SRC/$f" >/dev/null 2>&1 || { echo "  BAD $f (corrupt archive)"; rm -f "$SRC/$f"; return 1; } ;;
      *.gz)    gzip -t "$SRC/$f" 2>/dev/null     || { echo "  BAD $f (corrupt gzip)"; rm -f "$SRC/$f"; return 1; } ;;
    esac
    echo "$got  $f" >> "$SRC/unverified.md5"
  elif [ "$got" != "$m" ]; then
    echo "  BAD MD5 $f (book $m, got $got)"; rm -f "$SRC/$f"; return 1
  fi
  return 0
}

echo "=== sources ($(wc -l < "$SRC/list.txt") files) ==="
dl_fail=0
while IFS='|' read -r f u m; do
  [ -n "$f" ] || continue
  fetch_one "$f" "$u" "$m" || dl_fail=1
done < "$SRC/list.txt"
[ "$dl_fail" = 0 ] || { echo "Some downloads failed (see FAIL/BAD lines). Re-run to retry; verified files are skipped."; exit 1; }
echo "  all sources present and verified"

# ------------------------------------------------------------------ runner
setpath() { if [ -d /opt/rustc/bin ]; then export PATH=/opt/rustc/bin:$BASEPATH; else export PATH=$BASEPATH; fi; }

runfn() {   # runfn NAME FUNCTION   (subshell with its own errexit, logs to $LOGD/NAME.log)
  local name=$1 fn=$2 t=$SECONDS rc
  set +e
  ( set -euo pipefail; "$fn" ) > "$LOGD/$name.log" 2>&1
  rc=$?
  set -e
  if [ "$rc" != 0 ]; then
    echo "!! $name FAILED (exit $rc). Last lines of $LOGD/$name.log:"
    tail -n 30 "$LOGD/$name.log"
    echo "Fix it (or paste me the lines above), then re-run:  bash blfs-b.sh   (finished packages are skipped)"
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
  case $name in
    llvm) echo "      (long one: ~10-20 min of ninja. Fans may audition for a jet engine.)" ;;
    rust) echo "      (the longest: ~25-45 min, and it goes mostly single-threaded near the end. Be patient.)" ;;
  esac
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

# ================================================================== package build functions
b_libxml2() {
  sed -i "/'git'/,+3d" meson.build
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release -D history=enabled -D icu=disabled
  ninja
  ninja install
  sed "s/--static/--shared/" -i /usr/bin/xml2-config
}

b_libssh2() {
  patch -Np1 -i "$SRC/libssh2-1.11.1-security_fixes-1.patch"
  ./configure --prefix=/usr --disable-docker-tests --disable-static
  make
  make install
}

b_llvm() {
  patch -Np1 -i "$SRC/llvm-22.1.8-upstream_fix-1.patch"
  { grep -rIl '#!.*python$' . || true; } | xargs -r sed -i '1s/python$/python3/'
  sed 's/utility/tool/' -i llvm/utils/FileCheck/CMakeLists.txt
  mkdir -pv /etc/clang
  for i in clang clang++; do
    echo -fstack-protector-strong > /etc/clang/$i.cfg
  done
  mkdir -v llvm/build
  cd llvm/build
  CC=gcc CXX=g++ \
  cmake -D CMAKE_INSTALL_PREFIX=/usr \
        -D CMAKE_SKIP_INSTALL_RPATH=ON \
        -D LLVM_ENABLE_FFI=ON \
        -D CMAKE_BUILD_TYPE=Release \
        -D LLVM_BUILD_LLVM_DYLIB=ON \
        -D LLVM_LINK_LLVM_DYLIB=ON \
        -D LLVM_ENABLE_RTTI=ON \
        -D LLVM_TARGETS_TO_BUILD="host;AMDGPU" \
        -D LLVM_ENABLE_PROJECTS=clang \
        -D LLVM_ENABLE_RUNTIMES=compiler-rt \
        -D LLVM_BINUTILS_INCDIR=/usr/include \
        -D LLVM_INCLUDE_BENCHMARKS=OFF \
        -D CLANG_DEFAULT_PIE_ON_LINUX=ON \
        -D CLANG_CONFIG_FILE_SYSTEM_DIR=/etc/clang \
        -Wno-dev -G Ninja ..
  ninja -j"$JOBS"
  ninja install
  llvm-config --version
}

b_rust() {
  mkdir -pv /opt/rustc-1.97.1
  ln -svfn rustc-1.97.1 /opt/rustc
  cat > bootstrap.toml << "EOF"
change-id = 154587

[llvm]
link-shared = true
targets = "X86"

[build]
description = "for JJLinux (BLFS 13.1)"
docs = false
tools = ["cargo", "clippy", "rustdoc", "rustfmt", "src"]

[install]
prefix = "/opt/rustc-1.97.1"
docdir = "share/doc/rustc-1.97.1"

[rust]
channel = "stable"
lto = "thin"
codegen-units = 1
llvm-bitcode-linker = false

[target.x86_64-unknown-linux-gnu]
llvm-config = "/usr/bin/llvm-config"

[target.i686-unknown-linux-gnu]
llvm-config = "/usr/bin/llvm-config"
EOF
  export LIBSSH2_SYS_USE_PKG_CONFIG=1
  export LIBSQLITE3_SYS_USE_PKG_CONFIG=1
  ./x.py build --jobs "$JOBS"
  ./x.py install --jobs "$JOBS"

  rm -fv /opt/rustc-1.97.1/share/doc/rustc-1.97.1/*.old
  install -vm644 README.md /opt/rustc-1.97.1/share/doc/rustc-1.97.1
  install -vdm755 /usr/share/zsh/site-functions
  ln -sfv /opt/rustc/share/zsh/site-functions/_cargo /usr/share/zsh/site-functions
  if [ -f /etc/bash_completion.d/cargo ]; then
    install -vdm755 /usr/share/bash-completion/completions
    mv -v /etc/bash_completion.d/cargo /usr/share/bash-completion/completions
  fi
  cat > /etc/profile.d/rustc.sh << "EOF"
# Rust (BLFS rustc, installed under /opt/rustc)
case ":$PATH:" in *:/opt/rustc/bin:*) ;; *) PATH=/opt/rustc/bin:$PATH ;; esac
export PATH
EOF
  /opt/rustc/bin/rustc --version
  /opt/rustc/bin/cargo --version
}

b_cargoc() {
  cp -v "$SRC/cargo-c-Cargo.lock" Cargo.lock
  export LIBSSH2_SYS_USE_PKG_CONFIG=1
  export LIBSQLITE3_SYS_USE_PKG_CONFIG=1
  cargo build --release
  install -vm755 target/release/cargo-{capi,cbuild,cinstall,ctest} /usr/bin/
}

b_mako() {
  pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir "$PWD"
  pip3 install --no-index --find-links dist --no-user Mako
}

b_pyyaml() {
  # no libyaml/Cython here: PyYAML falls back to its pure-Python loader, which is all Mesa needs
  pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir "$PWD"
  pip3 install --no-index --find-links dist --no-user PyYAML
  python3 -c 'import yaml; print("PyYAML", yaml.__version__)'
}

b_libdrm() {
  mkdir build; cd build
  meson setup --prefix=/usr --buildtype=release -D udev=true -D valgrind=disabled ..
  ninja
  ninja install
}

b_wayland() {
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release -D documentation=false
  ninja
  ninja install
}

b_waylandproto() {
  mkdir build; cd build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  ninja install
}

b_mesa() {
  mkdir build; cd build
  # Wayland only for now (X11 platform returns with Xwayland in stage C). No libglvnd, no Vulkan yet.
  meson setup .. \
    --prefix=/usr \
    --buildtype=release \
    -D platforms=wayland \
    -D glx=disabled \
    -D gallium-drivers=llvmpipe,softpipe,radeonsi,svga,virgl \
    -D vulkan-drivers="" \
    -D valgrind=disabled \
    -D libunwind=disabled \
    -D llvm=enabled \
    -D shared-llvm=enabled
  ninja -j"$JOBS"
  ninja install
}

b_seatd() {
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release \
    -D server=enabled -D libseat-logind=disabled
  ninja
  ninja install

  getent group seat >/dev/null || groupadd -r seat
  for g in seat video input audio render; do
    getent group "$g" >/dev/null && usermod -aG "$g" jj || true
  done
  cat > /etc/systemd/system/seatd.service << "EOF"
[Unit]
Description=Seat management daemon
Documentation=man:seatd(1)

[Service]
Type=simple
ExecStart=/usr/bin/seatd -g seat
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now seatd.service
  sleep 1
  systemctl is-active seatd.service
}

b_xkbconfig() {
  mkdir build; cd build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  ninja install
}

b_libxkbcommon() {
  patch -Np1 -i "$SRC/libxkbcommon-1.13.2-upstream_fix-1.patch"
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release \
    -D enable-docs=false -D enable-x11=false
  ninja
  ninja install
}

b_pixman() {
  mkdir build; cd build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  ninja install
}

b_libpng() {
  zcat "$SRC/libpng-1.6.58-apng.patch.gz" | patch -p1
  ./configure --prefix=/usr --disable-static
  make
  make install
  install -vDm644 README libpng-manual.txt -t /usr/share/doc/libpng-1.6.58
}

b_freetype() {
  sed -ri "s:.*(AUX_MODULES.*valid):\1:" modules.cfg
  sed -r "s:.*(#.*SUBPIXEL_RENDERING) .*:\1:" -i include/freetype/config/ftoption.h
  ./configure --prefix=/usr --disable-static --enable-freetype-config --with-harfbuzz=dynamic
  make
  make install
}

b_harfbuzz() {
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release -D docs=disabled
  ninja
  ninja install
}

b_fontconfig() {
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    --disable-docs --docdir=/usr/share/doc/fontconfig-2.18.3
  make
  make install
}

b_fribidi() {
  mkdir build; cd build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  ninja install
}

b_dejavu() {
  install -v -d -m755 /usr/share/fonts/dejavu
  install -v -m644 ttf/*.ttf /usr/share/fonts/dejavu
  fc-cache -v /usr/share/fonts/dejavu
  fc-list | grep -ci dejavu
}

# ================================================================== run it all
pkg libxml2        libxml2-2.15.3.tar.xz         b_libxml2
pkg libssh2        libssh2-1.11.1.tar.gz         b_libssh2
pkg llvm           llvm-project-22.1.8.src.tar.xz b_llvm
pkg rust           rustc-1.97.1-src.tar.xz       b_rust
pkg cargoc         cargo-c-0.10.24.tar.gz        b_cargoc
pkg mako           mako-1.4.1.tar.gz             b_mako
pkg pyyaml         pyyaml-6.0.3.tar.gz           b_pyyaml
pkg libdrm         libdrm-2.4.134.tar.xz         b_libdrm
pkg wayland        wayland-1.26.0.tar.xz         b_wayland
pkg waylandproto   wayland-protocols-1.49.tar.xz b_waylandproto
pkg mesa           mesa-26.1.7.tar.xz            b_mesa
pkg seatd          seatd-0.9.3.tar.gz            b_seatd
pkg xkbconfig      xkeyboard-config-2.48.tar.xz  b_xkbconfig
pkg libxkbcommon   libxkbcommon-1.13.2.tar.gz    b_libxkbcommon
pkg pixman         pixman-0.46.4.tar.gz          b_pixman
pkg libpng         libpng-1.6.58.tar.xz          b_libpng
pkg freetype       freetype-2.14.3.tar.xz        b_freetype
pkg harfbuzz       harfbuzz-14.3.1.tar.xz        b_harfbuzz
pkg fontconfig     fontconfig-2.18.3.tar.xz      b_fontconfig
pkg fribidi        fribidi-1.0.16.tar.xz         b_fribidi
pkg dejavu         dejavu-fonts-ttf-2.37.tar.bz2 b_dejavu

# ------------------------------------------------------------------ identity bump 0.3 Namek -> 0.4 Capsule
b_identity() {
  CODE_LC=${JJ_CODENAME,,}
  sed -i -e "s/^VERSION=.*/VERSION=\"$JJ_VERSION ($JJ_CODENAME)\"/" \
         -e "s/^VERSION_ID=.*/VERSION_ID=\"$JJ_VERSION\"/" \
         -e "s/^VERSION_CODENAME=.*/VERSION_CODENAME=$CODE_LC/" \
         -e "s/^PRETTY_NAME=.*/PRETTY_NAME=\"JJLinux $JJ_VERSION ($JJ_CODENAME)\"/" /etc/os-release
  sed -i -e "s/^DISTRIB_RELEASE=.*/DISTRIB_RELEASE=\"$JJ_VERSION\"/" \
         -e "s/^DISTRIB_CODENAME=.*/DISTRIB_CODENAME=\"$CODE_LC\"/" \
         -e "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION=\"JJLinux $JJ_VERSION ($JJ_CODENAME)\"/" /etc/lsb-release
  echo "JJLinux $JJ_VERSION ($JJ_CODENAME)" > /etc/jjlinux-release
  printf 'JJLinux %s "%s" \\n \\l\n\n' "$JJ_VERSION" "$JJ_CODENAME" > /etc/issue
  sed -i -E "s/JJLinux [0-9.]+ \"[A-Za-z ]+\"/JJLinux $JJ_VERSION \"$JJ_CODENAME\"/" /etc/motd
  grep -E '^(VERSION|PRETTY_NAME)=' /etc/os-release
}
step identity b_identity

# ------------------------------------------------------------------ verification (non-fatal; prints a report)
echo
echo "=== verification ==="
setpath
ok=0; bad=0
chk() {  # chk "label" command...
  local label=$1 out; shift
  out=$( { "$@" 2>&1 || true; } | head -n1 )
  if [ -n "$out" ] && ! printf '%s' "$out" | grep -qiE 'not found|no such|error|cannot|unknown module'; then
    printf '  ok   %-14s %s\n' "$label" "$out"; ok=$((ok+1))
  else
    printf '  FAIL %-14s %s\n' "$label" "${out:-<no output>}"; bad=$((bad+1))
  fi
}
chk clang        clang --version
chk llvm         llvm-config --version
chk rustc        rustc --version
chk cargo        cargo --version
chk cargo-c      cargo-cbuild --version
chk mako         python3 -c 'import mako; print("Mako", mako.__version__)'
chk pyyaml       python3 -c 'import yaml; print("PyYAML", yaml.__version__)'
for p in wayland-client wayland-protocols libdrm egl gbm glesv2 xkbcommon pixman-1 libpng freetype2 harfbuzz fontconfig fribidi libseat; do
  chk "$p" pkg-config --modversion "$p"
done
chk seatd        sh -c 'systemctl is-active seatd.service | grep -x active'
chk fonts        sh -c 'fc-list | grep -i dejavu | head -n1'

echo "=== real EGL/GLES check (software renderer, no display needed) ==="
cat > /tmp/egltest.c << 'CEOF'
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <stdio.h>
int main(void) {
  PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
  EGLDisplay d = gpd ? gpd(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL) : EGL_NO_DISPLAY;
  if (d == EGL_NO_DISPLAY) { puts("no surfaceless display"); return 2; }
  EGLint maj, min;
  if (!eglInitialize(d, &maj, &min)) { puts("eglInitialize failed"); return 3; }
  eglBindAPI(EGL_OPENGL_ES_API);
  EGLint ca[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE };
  EGLConfig c; EGLint nc = 0;
  if (!eglChooseConfig(d, ca, &c, 1, &nc) || nc < 1) { puts("no EGL config"); return 4; }
  EGLint cx[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
  EGLContext ctx = eglCreateContext(d, c, EGL_NO_CONTEXT, cx);
  if (ctx == EGL_NO_CONTEXT) { puts("no context"); return 5; }
  if (!eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) { puts("makecurrent failed"); return 6; }
  printf("EGL %d.%d | GL_VENDOR=%s | GL_RENDERER=%s\n", maj, min, glGetString(GL_VENDOR), glGetString(GL_RENDERER));
  return 0;
}
CEOF
if gcc /tmp/egltest.c -o /tmp/egltest -lEGL -lGLESv2 2>/tmp/egltest.err && /tmp/egltest; then
  ok=$((ok+1))
else
  echo "  FAIL EGL/GLES test (compile or run). Details:"; head -n 8 /tmp/egltest.err 2>/dev/null || true
  bad=$((bad+1))
fi
rm -f /tmp/egltest /tmp/egltest.c /tmp/egltest.err

echo
if [ "$bad" = 0 ]; then
  echo "=== BLFS stage B DONE in $(( (SECONDS - T_ALL) / 60 )) min -- JJLinux $JJ_VERSION \"$JJ_CODENAME\"  ($ok checks passed) ==="
else
  echo "=== stage B built, but $bad check(s) FAILED ($ok passed) -- paste the FAIL lines to me ==="
fi
echo "Log out and back in (ssh jl2) so /etc/profile.d/rustc.sh puts Rust on your PATH."
