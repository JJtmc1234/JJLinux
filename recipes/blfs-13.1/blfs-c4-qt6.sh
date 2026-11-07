#!/bin/bash
# JJLinux -- BLFS stage C4: Qt 6.11.2 (only the parts Omarchy's Quickshell shell uses) into /opt/qt6.
#   Kept modules: qtbase, qtshadertools, qtdeclarative (QtQuick/Controls/Layouts/Shapes/Effects), qtsvg,
#   qtwayland, qtimageformats, qtlanguageserver.  Everything else (webengine, multimedia, 3d, ...) is dropped.
#   Also rebuilds libxkbcommon with X11 support (stage B had it off because xcb did not exist yet).
# Run after C3:   sudo bash blfs-c4-qt6.sh      (resumable; 972 MB download, then ~15-25 min of compile)
# Parallel jobs for Qt are capped at 20 so the 62 GB of RAM survive the heavy QtDeclarative files.
set -euo pipefail

# ------------------------------------------------------------------ common settings
JJ_STAGE=c4
TOTAL=2
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
echo "JJLinux stage C4 (Qt6 subset for Quickshell) | RAM ${RAM_GB} GB, $NP CPUs -> $JOBS parallel jobs"

# ------------------------------------------------------------------ preflight
echo "=== preflight ==="
pf_fail=0
for t in gcc g++ make meson ninja cmake python3 pip3 curl git patch pkg-config bison flex xz tar; do
  command -v "$t" >/dev/null 2>&1 || { echo "  MISSING tool: $t"; pf_fail=1; }
done
curl -fsS -o /dev/null --connect-timeout 15 -r 0-99 https://github.com/ \
  || { echo "  CANNOT reach github.com over HTTPS"; pf_fail=1; }
FREE_GB=$(df -BG --output=avail /var/tmp | tail -n1 | tr -dc 0-9)
[ "${FREE_GB:-0}" -ge 40 ] || { echo "  Only ${FREE_GB} GB free in /var/tmp (want 40+)"; pf_fail=1; }
[ -f "$STATE/portal.done" ] || { echo "  stage C3 (blfs-c3-services.sh) has not finished - run it first"; pf_fail=1; }
[ "$pf_fail" = 0 ] || { echo "Preflight failed - fix the above and re-run."; exit 1; }
echo "  ok (${FREE_GB} GB free)"

# ------------------------------------------------------------------ sources
# file|url[,mirror...]|md5   (md5 '-' = no published checksum; we sanity-check the archive and log our own md5)
cat > "$SRC/list-$JJ_STAGE.txt" << 'LISTEOF'
qt-everywhere-src-6.11.2.tar.xz|https://download.qt.io/archive/qt/6.11/6.11.2/single/qt-everywhere-src-6.11.2.tar.xz|669c1f3a41c37fdda389094882044d7a
libxkbcommon-1.13.2.tar.gz|https://github.com/lfs-book/libxkbcommon/archive/v1.13.2/libxkbcommon-1.13.2.tar.gz|07f838f575d62c267cfc53eaf5ee739b
libxkbcommon-1.13.2-upstream_fix-1.patch|https://www.linuxfromscratch.org/patches/blfs/13.1/libxkbcommon-1.13.2-upstream_fix-1.patch|-
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
hint_qt6() { echo "      (the long one: watch with  tail -f /var/log/blfs-c/qt6.log  in a second terminal)"; }

b_xkbcommon2() {
  patch -Np1 -i "$SRC/libxkbcommon-1.13.2-upstream_fix-1.patch"
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release -D enable-docs=false -D enable-x11=true
  ninja
  ninja install
  pkg-config --modversion xkbcommon-x11
}

b_qt6() {
  local QJ=$JOBS keep=" qtbase qtshadertools qtdeclarative qtsvg qtwayland qtimageformats qtlanguageserver " d
  [ "$QJ" -le 20 ] || QJ=20
  for d in qt*/; do
    d=${d%/}
    case "$keep" in *" $d "*) ;; *) echo "dropping $d"; rm -rf "$d" ;; esac
  done
  echo "keeping: $(ls -d qt* | tr '\n' ' ')"
  ./configure -prefix /opt/qt6 -release -sysconfdir /etc/xdg -dbus-linked -openssl-linked \
              -system-sqlite -nomake examples -nomake tests -no-rpath -no-sbom -journald
  ninja -j"$QJ"
  ninja install
  find /opt/qt6/ -name \*.prl -exec sed -i -e '/^QMAKE_PRL_BUILD_DIR/d' {} \;

  grep -q '/opt/qt6/lib' /etc/ld.so.conf || printf '# Begin Qt addition\n/opt/qt6/lib\n# End Qt addition\n' >> /etc/ld.so.conf
  cat > /etc/profile.d/qt6.sh << "EOF"
# Begin /etc/profile.d/qt6.sh
QT6DIR=/opt/qt6
pathappend $QT6DIR/bin PATH
pathappend $QT6DIR/lib/pkgconfig PKG_CONFIG_PATH
export QT6DIR
# End /etc/profile.d/qt6.sh
EOF
  printf 'Defaults env_keep += QT6DIR\n' > /etc/sudoers.d/qt
  chmod 440 /etc/sudoers.d/qt
}

pkg xkbcommon2 libxkbcommon-1.13.2.tar.gz        b_xkbcommon2
pkg qt6        qt-everywhere-src-6.11.2.tar.xz   b_qt6


# ------------------------------------------------------------------ verification (non-fatal)
echo
echo "=== verification ==="
setpath
ok=0; bad=0
chk xkbcommon-x11  pkg-config --modversion xkbcommon-x11
chk qmake          sh -c '/opt/qt6/bin/qmake -v | tail -n1'
chk qml-runtime    sh -c 'ls /opt/qt6/bin/qml'
chk wayland-plugin sh -c 'ls /opt/qt6/plugins/platforms/libqwayland*.so | head -n1'
chk xcb-plugin     sh -c 'ls /opt/qt6/plugins/platforms/libqxcb.so'
chk svg-plugin     sh -c 'ls /opt/qt6/plugins/imageformats/libqsvg.so'
chk qsb            sh -c '/opt/qt6/bin/qsb --version'
chk cmake-Quick    sh -c 'ls /opt/qt6/lib/cmake/Qt6Quick/Qt6QuickConfig.cmake'
chk cmake-Wayland  sh -c 'ls /opt/qt6/lib/cmake/Qt6WaylandClient/Qt6WaylandClientConfig.cmake'
cat > /tmp/jj-qt-test.qml << 'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
Item { Component.onCompleted: { console.log("QML-OK"); Qt.quit() } }
QML
chk qml-imports    sh -c 'QT_QPA_PLATFORM=offscreen timeout 60 /opt/qt6/bin/qml /tmp/jj-qt-test.qml 2>&1 | grep -m1 QML-OK'
rm -f /tmp/jj-qt-test.qml
echo
if [ "$bad" = 0 ]; then
  echo "=== BLFS stage C4 DONE in $(( (SECONDS - T_ALL) / 60 )) min  ($ok checks passed) ==="
else
  echo "=== stage C4 built but $bad check(s) FAILED ($ok passed) -- paste the FAIL lines to me ==="
fi
echo "Next: snapshot (virsh snapshot-create-as LFS-13.1 v0.7-qt6), then C5 (Hyprland ecosystem + Quickshell + foot)."
