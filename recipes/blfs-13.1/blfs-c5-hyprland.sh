#!/bin/bash
# JJLinux -- BLFS stage C5: Hyprland 0.56.2 and everything Omarchy 4 needs around it.
#   Prereqs not in BLFS: abseil, re2, muparser, libzip, pugixml, iniparser, utf8proc, CLI11, sdbus-c++, libei,
#   Lua 5.5 (static, named lua5.5 so it never collides with Lua 5.4), glaze, libmagic.pc.
#   Hypr stack: hyprwayland-scanner, hyprutils, hyprlang, hyprland-protocols, hyprcursor, hyprgraphics, aquamarine,
#   Hyprland, xdg-desktop-portal-hyprland, hyprtoolkit + hyprland-guiutils, hyprpicker, hyprsunset.
#   Shell + terminal: Quickshell 0.3.1, tllist/fcft/foot 1.28.0.  Tools: grim, slurp, wl-clipboard, wtype,
#   xdg-terminal-exec, uwsm.
# Hypr library versions are picked inside the VM: the newest release published at or before Hyprland 0.56.2's release
# date (+3 days), so they match each other.  Choices are written to /sources/blfs-c/pins.txt and reused on re-runs.
# Run after C4:   sudo bash blfs-c5-hyprland.sh     (resumable; ~25-40 min)
# Steps marked (optional) are allowed to fail without stopping the run.
set -euo pipefail

# ------------------------------------------------------------------ common settings
JJ_STAGE=c5
TOTAL=40
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
echo "JJLinux stage C5 (Hyprland + Quickshell + foot + wayland tools) | RAM ${RAM_GB} GB, $NP CPUs -> $JOBS parallel jobs"

# ------------------------------------------------------------------ preflight
echo "=== preflight ==="
pf_fail=0
for t in gcc g++ make meson ninja cmake python3 pip3 curl git patch pkg-config bison flex xz tar; do
  command -v "$t" >/dev/null 2>&1 || { echo "  MISSING tool: $t"; pf_fail=1; }
done
curl -fsS -o /dev/null --connect-timeout 15 -r 0-99 https://github.com/ \
  || { echo "  CANNOT reach github.com over HTTPS"; pf_fail=1; }
FREE_GB=$(df -BG --output=avail /var/tmp | tail -n1 | tr -dc 0-9)
[ "${FREE_GB:-0}" -ge 20 ] || { echo "  Only ${FREE_GB} GB free in /var/tmp (want 20+)"; pf_fail=1; }
[ -f "$STATE/qt6.done" ] || { echo "  stage C4 (blfs-c4-qt6.sh) has not finished - run it first"; pf_fail=1; }
curl -fsS -o /dev/null --connect-timeout 15 https://api.github.com/rate_limit || { echo "  CANNOT reach api.github.com (needed to pick library versions)"; pf_fail=1; }
[ "$pf_fail" = 0 ] || { echo "Preflight failed - fix the above and re-run."; exit 1; }
echo "  ok (${FREE_GB} GB free)"

# ------------------------------------------------------------------ sources
# file|url[,mirror...]|md5   (md5 '-' = no published checksum; we sanity-check the archive and log our own md5)
cat > "$SRC/list-$JJ_STAGE.txt" << 'LISTEOF'
abseil-cpp-20260526.0.tar.gz|https://github.com/abseil/abseil-cpp/releases/download/20260526.0/abseil-cpp-20260526.0.tar.gz|a8a8a3de136df18dbe87b47c174e7c16
muparser-2.3.5.tar.gz|https://github.com/beltoforion/muparser/archive/v2.3.5/muparser-2.3.5.tar.gz|04d4224cb01712207b85af05a255b6fc
libei-1.6.0.tar.bz2|https://gitlab.freedesktop.org/libinput/libei/-/archive/1.6.0/libei-1.6.0.tar.bz2|08186470213bdba5a4e58d322368f31d
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
# ---------------------------------------------------------------- version pinning + source helpers
PINS=$SRC/pins.txt; touch "$PINS"
cat > "$SRC/resolve.py" << 'PY'
import sys, json, urllib.request, datetime
def get(u):
    req = urllib.request.Request(u, headers={'User-Agent': 'jjlinux-build', 'Accept': 'application/json'})
    return json.load(urllib.request.urlopen(req, timeout=40))
if sys.argv[1] == 'cutoff':
    r = get('https://api.github.com/repos/hyprwm/Hyprland/releases/tags/v0.56.2')
    d = datetime.datetime.strptime(r['published_at'], '%Y-%m-%dT%H:%M:%SZ') + datetime.timedelta(days=3)
    print(d.strftime('%Y-%m-%dT%H:%M:%SZ'))
else:
    forge, repo, mode, cutoff, prefix = sys.argv[2:7]
    if forge == 'github':
        rel = 'https://api.github.com/repos/%s/releases?per_page=60' % repo
        tags = 'https://api.github.com/repos/%s/tags?per_page=60' % repo
    else:
        rel = 'https://codeberg.org/api/v1/repos/%s/releases?limit=50' % repo
        tags = 'https://codeberg.org/api/v1/repos/%s/tags?limit=50' % repo
    best = ''
    for r in get(rel):
        if r.get('draft') or r.get('prerelease'):
            continue
        t = r['tag_name']
        if prefix and not t.startswith(prefix):
            continue
        if mode == 'cutoff' and r['published_at'] > cutoff:
            continue
        best = t
        break
    if not best and mode != 'cutoff':
        for t in get(tags):
            if prefix and not t['name'].startswith(prefix):
                continue
            best = t['name']
            break
    print(best)
PY

archive_url() { case $1 in github) echo "https://github.com/$2/archive/refs/tags/$3.tar.gz" ;; codeberg) echo "https://codeberg.org/$2/archive/$3.tar.gz" ;; esac; }

pin() {      # pin KEY FORGE REPO MODE [PREFIX]  -> prints tag (cached in pins.txt so re-runs never change versions)
  local key=$1 forge=$2 repo=$3 mode=$4 prefix=${5:-} tag cut=""
  tag=$(awk -v k="$key" '$1==k {print $2}' "$PINS" | tail -n1)
  if [ -z "$tag" ]; then
    if [ "$mode" = cutoff ]; then cut=$(python3 "$SRC/resolve.py" cutoff); fi
    tag=$(python3 "$SRC/resolve.py" tag "$forge" "$repo" "$mode" "$cut" "$prefix")
    [ -n "$tag" ] || { echo "cannot resolve a version for $repo" >&2; return 1; }
    echo "$key $tag" >> "$PINS"
  fi
  echo "$tag"
}
pin_ver() {  # pin_ver KEY FORGE REPO VERSION  -> tag that exists for a known version (tries v1.2.3 then 1.2.3)
  local key=$1 forge=$2 repo=$3 ver=$4 tag t
  tag=$(awk -v k="$key" '$1==k {print $2}' "$PINS" | tail -n1)
  if [ -z "$tag" ]; then
    for t in "v$ver" "$ver"; do
      if curl -fsL -r 0-0 -o /dev/null "$(archive_url "$forge" "$repo" "$t")"; then tag=$t; break; fi
    done
    [ -n "$tag" ] || { echo "no tag for $repo $ver" >&2; return 1; }
    echo "$key $tag" >> "$PINS"
  fi
  echo "$tag"
}
src_forge() { # src_forge NAME FORGE REPO TAG -> downloads (cached), extracts into $BUILD/NAME, cd into the source dir
  local name=$1 forge=$2 repo=$3 tag=$4 f
  f=${repo//\//_}-$tag.tar.gz
  fetch_one "$f" "$(archive_url "$forge" "$repo" "$tag")" -
  rm -rf "${BUILD:?}/$name"; mkdir -p "$BUILD/$name"
  tar -xf "$SRC/$f" -C "$BUILD/$name"
  cd "$BUILD/$name"/*/
}
cm_finish() { ninja -C build -j"$JOBS" || return 1; ninja -C build install || return 1; cd /; }
cm_pinned() { # cm_pinned NAME FORGE REPO MODE PREFIX [cmake args]   (MODE: cutoff | latest)
  local name=$1 forge=$2 repo=$3 mode=$4 prefix=$5 tag; shift 5
  tag=$(pin "$name" "$forge" "$repo" "$mode" "$prefix"); echo "  $name -> $tag"
  src_forge "$name" "$forge" "$repo" "$tag"
  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev "$@" || return 1
  cm_finish || return 1; rm -rf "${BUILD:?}/$name"
}
cm_ver() {    # cm_ver NAME FORGE REPO VERSION [cmake args]
  local name=$1 forge=$2 repo=$3 ver=$4 tag; shift 4
  tag=$(pin_ver "$name" "$forge" "$repo" "$ver"); echo "  $name -> $tag"
  src_forge "$name" "$forge" "$repo" "$tag"
  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev "$@" || return 1
  cm_finish || return 1; rm -rf "${BUILD:?}/$name"
}
ms_ver() {    # ms_ver NAME FORGE REPO VERSION [meson args]
  local name=$1 forge=$2 repo=$3 ver=$4 tag; shift 4
  tag=$(pin_ver "$name" "$forge" "$repo" "$ver"); echo "  $name -> $tag"
  src_forge "$name" "$forge" "$repo" "$tag"
  meson setup build --prefix=/usr --buildtype=release "$@" || return 1
  ninja -C build -j"$JOBS" || return 1; ninja -C build install || return 1; cd /; rm -rf "${BUILD:?}/$name"
}
ms_pinned() { # ms_pinned NAME FORGE REPO MODE PREFIX [meson args]
  local name=$1 forge=$2 repo=$3 mode=$4 prefix=$5 tag; shift 5
  tag=$(pin "$name" "$forge" "$repo" "$mode" "$prefix"); echo "  $name -> $tag"
  src_forge "$name" "$forge" "$repo" "$tag"
  meson setup build --prefix=/usr --buildtype=release "$@" || return 1
  ninja -C build -j"$JOBS" || return 1; ninja -C build install || return 1; cd /; rm -rf "${BUILD:?}/$name"
}
b_try() {     # b_try FUNCTION -- optional step: a failure is logged but does not stop the run
  local fn=$1
  if "$fn"; then :; else
    echo "!! OPTIONAL step $fn failed - continuing without it (retry later: rm $STATE/${fn#b_}.done and re-run)"
    echo "$fn" >> "$STATE/c5-optional-failed.txt"
  fi
}

# ---------------------------------------------------------------- prerequisites (not in BLFS)
b_abseil()  { mkdir build; cd build
              cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -D CMAKE_SKIP_INSTALL_RPATH=ON \
                    -D ABSL_PROPAGATE_CXX_STD=ON -D BUILD_SHARED_LIBS=ON -G Ninja ..
              ninja -j"$JOBS"; ninja install; }
b_muparser(){ mkdir -v build; cd build
              cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release ..
              make -j"$JOBS"; make install; }
b_libei() {   pip3 install --no-cache-dir jinja2 attrs || true
              mkdir build; cd build
              meson setup .. --prefix=/usr --buildtype=release -D tests=disabled
              ninja; ninja install; }
b_lua55() {
  local v ver
  v=$(curl -fsSL https://www.lua.org/ftp/ | grep -o 'lua-5\.5\.[0-9]*\.tar\.gz' | sort -uV | tail -n1)
  [ -n "$v" ] || { echo "no Lua 5.5 tarball found on lua.org"; false; }
  ver=${v#lua-}; ver=${ver%.tar.gz}; echo "  lua $ver"
  fetch_one "$v" "https://www.lua.org/ftp/$v" -
  rm -rf "$BUILD/lua55"; mkdir -p "$BUILD/lua55"; tar -xf "$SRC/$v" -C "$BUILD/lua55"; cd "$BUILD/lua55"/*/
  make linux MYCFLAGS="-fPIC" -j"$JOBS"
  install -d /usr/include/lua5.5
  install -m644 src/lua.h src/luaconf.h src/lualib.h src/lauxlib.h /usr/include/lua5.5/
  [ ! -f src/lua.hpp ] || install -m644 src/lua.hpp /usr/include/lua5.5/
  install -m644 src/liblua.a /usr/lib/liblua5.5.a
  install -m755 src/lua /usr/bin/lua5.5
  cat > /usr/lib/pkgconfig/lua5.5.pc << EOF
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include/lua5.5

Name: Lua
Description: Lua 5.5 (static, for Hyprland)
Version: $ver
Libs: -L\${libdir} -llua5.5 -lm -ldl
Cflags: -I\${includedir}
EOF
  pkg-config --modversion lua5.5
  cd /; rm -rf "$BUILD/lua55"
}
b_glaze()    { cm_ver glaze github stephenberry/glaze 7.2.0 -Dglaze_DEVELOPER_MODE=OFF -DBUILD_TESTING=OFF; }
b_re2()      { cm_pinned re2 github google/re2 latest "" -DBUILD_SHARED_LIBS=ON -DRE2_BUILD_TESTING=OFF; }
b_libzip()   { cm_pinned libzip github nih-at/libzip latest v1 -DBUILD_SHARED_LIBS=ON -DBUILD_DOC=OFF \
                 -DBUILD_EXAMPLES=OFF -DBUILD_REGRESS=OFF -DBUILD_TOOLS=OFF; }
b_pugixml()  { cm_pinned pugixml github zeux/pugixml latest v -DBUILD_SHARED_LIBS=ON -DPUGIXML_BUILD_TESTS=OFF; }
b_iniparser() {
  cm_pinned iniparser github ndevilla/iniparser latest v -DBUILD_SHARED_LIBS=ON -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF
  if ! pkg-config --exists iniparser; then
    echo "iniparser has no .pc - writing one"
    cat > /usr/lib/pkgconfig/iniparser.pc << "EOF"
prefix=/usr
libdir=${prefix}/lib
includedir=${prefix}/include

Name: iniparser
Description: ini file parser
Version: 4
Libs: -L${libdir} -liniparser
Cflags: -I${includedir} -I${includedir}/iniparser
EOF
  fi
}
b_utf8proc() { cm_pinned utf8proc github JuliaStrings/utf8proc latest v -DBUILD_SHARED_LIBS=ON -DUTF8PROC_ENABLE_TESTING=OFF; }
b_cli11()    { cm_pinned cli11 github CLIUtils/CLI11 latest v -DCLI11_BUILD_TESTS=OFF -DCLI11_BUILD_EXAMPLES=OFF -DCLI11_BUILD_DOCS=OFF; }
b_sdbus()    { cm_pinned sdbus github Kistler-Group/sdbus-cpp latest v2 -DBUILD_SHARED_LIBS=ON -DSDBUSCPP_BUILD_TESTS=OFF \
                 -DSDBUSCPP_BUILD_DOCS=OFF -DSDBUSCPP_BUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF; }
b_libmagicpc() {
  if pkg-config --exists libmagic; then echo "libmagic.pc already present"; return 0; fi
  cat > /usr/lib/pkgconfig/libmagic.pc << EOF
prefix=/usr
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libmagic
Description: File type identification library
Version: $(file --version | head -n1 | sed 's/file-//')
Libs: -L\${libdir} -lmagic
Cflags: -I\${includedir}
EOF
  pkg-config --modversion libmagic
}

# ---------------------------------------------------------------- the Hypr stack (versions = newest at Hyprland 0.56.2's release date)
b_tomlpp()    { cm_pinned tomlplusplus github marzer/tomlplusplus latest v -DBUILD_TESTING=OFF -Dtomlplusplus_BUILD_TESTS=OFF \
                  -Dtomlplusplus_BUILD_EXAMPLES=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF
              if ! pkg-config --exists tomlplusplus; then
                local v; v=$(sed -n 's/.*PACKAGE_VERSION "\(.*\)".*/\1/p' /usr/lib/cmake/tomlplusplus/tomlplusplusConfigVersion.cmake | head -n1)
                printf 'prefix=/usr\nincludedir=${prefix}/include\n\nName: tomlplusplus\nDescription: Header-only TOML parser for C++17\nVersion: %s\nCflags: -I${includedir}\n' "${v:-3.4.0}" > /usr/share/pkgconfig/tomlplusplus.pc
              fi
              pkg-config --modversion tomlplusplus; }
b_hwdata()    { local t; t=$(pin hwdata github vcrhonek/hwdata latest v); echo "  hwdata -> $t"
                src_forge hwdata github vcrhonek/hwdata "$t"
                ./configure --prefix=/usr --datadir=/usr/share
                make install
                pkg-config --modversion hwdata; cd /; rm -rf "$BUILD/hwdata"; }
b_glshim()    { [ -e /usr/lib/libOpenGL.so ] || ln -s libGL.so /usr/lib/libOpenGL.so; ls -l /usr/lib/libOpenGL.so; }
b_hwscanner() { cm_pinned hyprwayland-scanner github hyprwm/hyprwayland-scanner cutoff ""; }
b_hyprutils() { cm_pinned hyprutils github hyprwm/hyprutils cutoff "" -DBUILD_TESTING=OFF; }
b_hyprlang()  { cm_pinned hyprlang github hyprwm/hyprlang cutoff "" -DBUILD_TESTING=OFF; }
b_hlprotocols() { ms_pinned hyprland-protocols github hyprwm/hyprland-protocols cutoff ""; }
b_hyprcursor(){ cm_pinned hyprcursor github hyprwm/hyprcursor cutoff "" -DBUILD_TESTING=OFF; }
b_hyprgraphics() { cm_pinned hyprgraphics github hyprwm/hyprgraphics cutoff "" -DBUILD_TESTING=OFF; }
b_aquamarine(){ cm_pinned aquamarine github hyprwm/aquamarine cutoff "" -DBUILD_TESTING=OFF; }
b_hyprwire()  { cm_pinned hyprwire github hyprwm/hyprwire cutoff "" -DBUILD_TESTING=OFF; pkg-config --modversion hyprwire; }
b_hyprland() {
  local f=hyprland-source-0.56.2.tar.gz QJ=$JOBS
  [ "$QJ" -le 16 ] || QJ=16
  fetch_one "$f" "https://github.com/hyprwm/Hyprland/releases/download/v0.56.2/source-v0.56.2.tar.gz" -
  rm -rf "$BUILD/hyprland"; mkdir -p "$BUILD/hyprland"; tar -xf "$SRC/$f" -C "$BUILD/hyprland"
  cd "$BUILD/hyprland"/*/
  hl_build() {
    rm -rf build
    cmake --no-warn-unused-cli -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
          -DNO_HYPRPM=ON -DBUILD_TESTING=OFF -Wno-dev && ninja -C build -j"$QJ"
  }
  if ! hl_build; then
    echo "!! gcc build failed - retrying the whole thing with clang"
    CC=clang CXX=clang++ hl_build
  fi
  ninja -C build install
  ls -l /usr/bin/Hyprland /usr/bin/hyprctl
  cd /; rm -rf "$BUILD/hyprland"
}
b_xdph() {
  local tag; tag=$(pin_ver xdph github hyprwm/xdg-desktop-portal-hyprland 1.4.1)
  cm_ver xdph github hyprwm/xdg-desktop-portal-hyprland 1.4.1 -DCMAKE_INSTALL_LIBEXECDIR=/usr/libexec
}
b_hyprtoolkit()   { cm_pinned hyprtoolkit github hyprwm/hyprtoolkit cutoff "" -DBUILD_TESTING=OFF; }
b_guiutils()      { cm_ver hyprland-guiutils github hyprwm/hyprland-guiutils 0.2.2; }
b_hyprpicker()    { cm_ver hyprpicker github hyprwm/hyprpicker 0.4.7; }
b_hyprsunset()    { cm_ver hyprsunset github hyprwm/hyprsunset 0.4.0; }

# ---------------------------------------------------------------- shell + terminal + wayland tools
b_quickshell() {
  local QJ=$JOBS
  [ "$QJ" -le 12 ] || QJ=12
  local tag; tag=$(pin_ver quickshell github quickshell-mirror/quickshell 0.3.1); echo "  quickshell -> $tag"
  src_forge quickshell github quickshell-mirror/quickshell "$tag"
  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
        -DDISTRIBUTOR=JJLinux -DCRASH_HANDLER=OFF -DCRASH_REPORTER=OFF -DUSE_JEMALLOC=OFF -Wno-dev
  ninja -C build -j"$QJ"; ninja -C build install
  ls -l /usr/bin/quickshell /usr/bin/qs
  cd /; rm -rf "$BUILD/quickshell"
}
b_tllist() { local t; t=$(pin tllist codeberg dnkl/tllist latest ""); echo "  tllist -> $t"
             src_forge tllist codeberg dnkl/tllist "$t"
             meson setup build --prefix=/usr --buildtype=release; ninja -C build install; cd /; rm -rf "$BUILD/tllist"; }
b_fcft()   { ms_pinned fcft codeberg dnkl/fcft latest ""; }
b_foot()   { ms_ver foot codeberg dnkl/foot 1.28.0; }
b_grim()   { local f=grim-1.5.0.tar.gz
             fetch_one "$f" "https://git.sr.ht/~emersion/grim/refs/download/v1.5.0/grim-1.5.0.tar.gz,https://github.com/emersion/grim/archive/refs/tags/v1.5.0.tar.gz,https://gitlab.freedesktop.org/emersion/grim/-/archive/v1.5.0/grim-v1.5.0.tar.gz" -
             rm -rf "$BUILD/grim"; mkdir -p "$BUILD/grim"; tar -xf "$SRC/$f" -C "$BUILD/grim"; cd "$BUILD/grim"/*/
             meson setup build --prefix=/usr --buildtype=release; ninja -C build install; cd /; rm -rf "$BUILD/grim"; }
b_slurp()  { local f=slurp-1.5.0.tar.gz
             fetch_one "$f" "https://github.com/emersion/slurp/releases/download/v1.5.0/slurp-1.5.0.tar.gz,https://github.com/emersion/slurp/archive/refs/tags/v1.5.0.tar.gz,https://git.sr.ht/~emersion/slurp/refs/download/v1.5.0/slurp-1.5.0.tar.gz" -
             rm -rf "$BUILD/slurp"; mkdir -p "$BUILD/slurp"; tar -xf "$SRC/$f" -C "$BUILD/slurp"; cd "$BUILD/slurp"/*/
             meson setup build --prefix=/usr --buildtype=release; ninja -C build install; cd /; rm -rf "$BUILD/slurp"; }
b_wlclip() { ms_ver wl-clipboard github bugaevc/wl-clipboard 2.3.0; }
b_wtype()  { ms_ver wtype github atx/wtype 0.4; }
b_xdgterm() {
  local t; t=$(pin_ver xdg-terminal-exec github Vladimir-csp/xdg-terminal-exec 0.14.3)
  src_forge xdgterm github Vladimir-csp/xdg-terminal-exec "$t"
  install -Dm755 xdg-terminal-exec /usr/bin/xdg-terminal-exec
  cd /; rm -rf "$BUILD/xdgterm"
}
b_uwsm() {
  pip3 install --no-cache-dir pyxdg dbus-python || return 1
  ms_ver uwsm github Vladimir-csp/uwsm 0.26.7 -D man-pages=disabled || return 1
}
b_hlxdph()  { b_try b_xdph; }
b_hltk()    { b_try b_hyprtoolkit; }
b_hlgui()   { b_try b_guiutils; }
b_hlpick()  { b_try b_hyprpicker; }
b_hlsun()   { b_try b_hyprsunset; }
b_hluwsm()  { b_try b_uwsm; }
b_hliniparser() { b_try b_iniparser; }

hint_hyprland()  { echo "      (the big compile, ~8 min)"; }
hint_quickshell(){ echo "      (~5 min)"; }

pkg  absl        abseil-cpp-20260526.0.tar.gz   b_abseil
pkg  muparser    muparser-2.3.5.tar.gz          b_muparser
pkg  libei       libei-1.6.0.tar.bz2            b_libei
step lua55                                      b_lua55
step glaze                                      b_glaze
step re2                                        b_re2
step libzip                                     b_libzip
step pugixml                                    b_pugixml
step iniparser                                  b_hliniparser
step utf8proc                                   b_utf8proc
step cli11                                      b_cli11
step sdbus                                      b_sdbus
step libmagicpc                                 b_libmagicpc
step tomlpp                                     b_tomlpp
step hwdata                                     b_hwdata
step glshim                                     b_glshim
step hwscanner                                  b_hwscanner
step hyprutils                                  b_hyprutils
step hyprlang                                   b_hyprlang
step hlprotocols                                b_hlprotocols
step hyprcursor                                 b_hyprcursor
step hyprgraphics                               b_hyprgraphics
step aquamarine                                 b_aquamarine
step hyprwire                                   b_hyprwire
step hyprland                                   b_hyprland
step xdph                                       b_hlxdph
step hyprtoolkit                                b_hltk
step guiutils                                   b_hlgui
step hyprpicker                                 b_hlpick
step hyprsunset                                 b_hlsun
step quickshell                                 b_quickshell
step tllist                                     b_tllist
step fcft                                       b_fcft
step foot                                       b_foot
step grim                                       b_grim
step slurp                                      b_slurp
step wlclip                                     b_wlclip
step wtype                                      b_wtype
step xdgterm                                    b_xdgterm
step uwsm                                       b_hluwsm


# ------------------------------------------------------------------ verification (non-fatal)
echo
echo "=== verification ==="
setpath
ok=0; bad=0
for m in re2 muparser absl_flat_hash_map libzip pugixml libutf8proc libeis-1.0 lua5.5 hyprutils hyprlang hyprcursor \
         hyprgraphics aquamarine hyprland-protocols hyprland fcft libmagic; do
  chk "pc:$m" pkg-config --modversion "$m"
done
chk Hyprland      sh -c 'ls /usr/bin/Hyprland /usr/bin/start-hyprland'
chk hyprctl       sh -c 'hyprctl --version | head -n1'
chk xdph          sh -c 'ls /usr/libexec/xdg-desktop-portal-hyprland'
chk hyprpicker    sh -c 'hyprpicker --version'
chk hyprsunset    sh -c 'hyprsunset --version'
chk quickshell    sh -c 'quickshell --version'
chk foot          sh -c 'foot --version'
chk grim          sh -c 'ls /usr/bin/grim'
chk slurp         sh -c 'ls /usr/bin/slurp'
chk wl-copy       sh -c 'wl-copy --version'
chk wtype         sh -c 'ls /usr/bin/wtype'
chk xdg-term-exec sh -c 'ls /usr/bin/xdg-terminal-exec'
chk uwsm          sh -c 'uwsm --version'
chk wayland-sess  sh -c 'ls /usr/share/wayland-sessions/hyprland.desktop'
echo
if [ -s "$STATE/c5-optional-failed.txt" ]; then
  echo "optional steps that failed (Hyprland itself does not need them):"; sort -u "$STATE/c5-optional-failed.txt" | sed 's/^/   /'
fi
echo "pinned versions:"; sed 's/^/   /' "$PINS"
if [ "$bad" = 0 ]; then
  echo "=== BLFS stage C5 DONE in $(( (SECONDS - T_ALL) / 60 )) min  ($ok checks passed) ==="
else
  echo "=== stage C5 built but $bad check(s) FAILED ($ok passed) -- paste the FAIL lines to me ==="
fi
cat << 'MSG'

Snapshot first:  virsh -c qemu:///system snapshot-create-as LFS-13.1 v0.8-hyprland   (VM off)
First light, on the VM console (not ssh), logged in as jj on tty1:
    start-hyprland        (or just:  Hyprland)
With the virtio display set to 1920x1080 you should get Hyprland's default Lua config.  Super+Q quits (example config).
If it black-screens, run:   Hyprland 2>&1 | tee ~/hl.log   and paste ~/hl.log
Next: C6 = the Omarchy port (your configs, themes, Quickshell shell, LazyVim).
MSG
