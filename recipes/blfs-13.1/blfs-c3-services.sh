#!/bin/bash
# JJLinux -- BLFS stage C3: the desktop services Omarchy's shell talks to.
#   polkit (+duktape), libgudev, UPower, ALSA, SBC, libical, BlueZ, NSPR/NSS, libndp, NetworkManager,
#   shared-mime-info, icon/desktop utils, gdk-pixbuf, json-glib, libnotify, Lua 5.4, PipeWire, WirePlumber,
#   Fuse3, bubblewrap, xdg-desktop-portal.
# Run after C2:   sudo bash blfs-c3-services.sh        (resumable; logs in /var/log/blfs-c/)
# NetworkManager is installed and enabled but told to leave the VM's ethernet (en*/eth*) to systemd-networkd,
# so your ssh session survives.  Remove /etc/NetworkManager/conf.d/10-jj-unmanaged.conf on bare metal.
# Skipped on purpose (for now): wpa_supplicant/libnl (no wifi on a VM), power-profiles-daemon (needs PyGObject),
# libsndfile chain, glycin, xdg-desktop-portal-gtk (needs GTK).
set -euo pipefail

# ------------------------------------------------------------------ common settings
JJ_STAGE=c3
TOTAL=26
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
echo "JJLinux stage C3 (polkit, UPower, NetworkManager, BlueZ, PipeWire, portals) | RAM ${RAM_GB} GB, $NP CPUs -> $JOBS parallel jobs"

# ------------------------------------------------------------------ preflight
echo "=== preflight ==="
pf_fail=0
for t in gcc g++ make meson ninja cmake python3 pip3 curl git patch pkg-config bison flex xz tar; do
  command -v "$t" >/dev/null 2>&1 || { echo "  MISSING tool: $t"; pf_fail=1; }
done
curl -fsS -o /dev/null --connect-timeout 15 -r 0-99 https://github.com/ \
  || { echo "  CANNOT reach github.com over HTTPS"; pf_fail=1; }
FREE_GB=$(df -BG --output=avail /var/tmp | tail -n1 | tr -dc 0-9)
[ "${FREE_GB:-0}" -ge 10 ] || { echo "  Only ${FREE_GB} GB free in /var/tmp (want 10+)"; pf_fail=1; }
[ -f "$STATE/xwayland.done" ] || { echo "  stage C2 (blfs-c2-xgfx.sh) has not finished - run it first"; pf_fail=1; }
[ "$pf_fail" = 0 ] || { echo "Preflight failed - fix the above and re-run."; exit 1; }
echo "  ok (${FREE_GB} GB free)"

# ------------------------------------------------------------------ sources
# file|url[,mirror...]|md5   (md5 '-' = no published checksum; we sanity-check the archive and log our own md5)
cat > "$SRC/list-$JJ_STAGE.txt" << 'LISTEOF'
nspr-4.40.tar.gz|https://archive.mozilla.org/pub/nspr/releases/v4.40/src/nspr-4.40.tar.gz|0c3c871158cc9af694f1f7d2b799ffd8
nss-3.126.tar.gz|https://archive.mozilla.org/pub/security/nss/releases/NSS_3_126_RTM/src/nss-3.126.tar.gz|0ca322cec564a53ac5a59ce130d96f46
nss-standalone-1.patch|https://www.linuxfromscratch.org/patches/blfs/13.1/nss-standalone-1.patch|-
lua-5.4.8.tar.gz|https://www.lua.org/ftp/lua-5.4.8.tar.gz|81cf5265b8634967d8a7480d238168ce
lua-5.4.8-shared_library-1.patch|https://www.linuxfromscratch.org/patches/blfs/13.1/lua-5.4.8-shared_library-1.patch|-
libical-4.0.5.tar.gz|https://github.com/libical/libical/releases/download/v4.0.5/libical-4.0.5.tar.gz|9896781cc82bad3b9a2c6c1ee8177347
sbc-2.2.tar.xz|https://www.kernel.org/pub/linux/bluetooth/sbc-2.2.tar.xz|f3f1a4e69249241801bc8ddd6050de23
bluez-5.87.tar.xz|https://www.kernel.org/pub/linux/bluetooth/bluez-5.87.tar.xz|6c6f8445ec3d2fa3cc570a671ccea9fa
alsa-lib-1.2.16.1.tar.bz2|https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.16.1.tar.bz2|c14c9f94f78f76924c13668954997a33
pipewire-1.6.8.tar.bz2|https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/1.6.8/pipewire-1.6.8.tar.bz2|9ae75812a76951c93210a26272c90ef3
wireplumber-0.5.15.tar.bz2|https://gitlab.freedesktop.org/pipewire/wireplumber/-/archive/0.5.15/wireplumber-0.5.15.tar.bz2|dba978afa67ba317d99ef03285ad4733
polkit-127.tar.gz|https://github.com/polkit-org/polkit/archive/127/polkit-127.tar.gz|2cc95f1b02fc1de6c9e52db986642ec4
duktape-2.7.0.tar.xz|https://duktape.org/duktape-2.7.0.tar.xz|b3200b02ab80125b694bae887d7c1ca6
libgudev-238.tar.xz|https://download.gnome.org/sources/libgudev/238/libgudev-238.tar.xz|46da30a1c69101c3a13fa660d9ab7b73
upower-v1.91.3.tar.bz2|https://gitlab.freedesktop.org/upower/upower/-/archive/v1.91.3/upower-v1.91.3.tar.bz2|bf09da2eb695224e249e38077460414c
libndp-1.9.tar.gz|http://libndp.org/files/libndp-1.9.tar.gz|9d486750569e7025e5d0afdcc509b93c
NetworkManager-1.58.1.tar.xz|https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/releases/1.58.1/downloads/NetworkManager-1.58.1.tar.xz|7b06b1dd7b56adffc1dbbf3d04bedf8e
gdk-pixbuf-2.44.7.tar.xz|https://download.gnome.org/sources/gdk-pixbuf/2.44/gdk-pixbuf-2.44.7.tar.xz|2a12da2133476b7b36fbfcadd7133315
shared-mime-info-2.5.1.tar.gz|https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/2.5.1/shared-mime-info-2.5.1.tar.gz|5f8baa7bac254ea9e65782f754a2880b
json-glib-1.10.8.tar.xz|https://download.gnome.org/sources/json-glib/1.10/json-glib-1.10.8.tar.xz|95c3d5dd56d4ada808480739889b75bc
fuse-3.18.2.tar.gz|https://github.com/libfuse/libfuse/releases/download/fuse-3.18.2/fuse-3.18.2.tar.gz|43c6f6cd2c1368d916f6fb080eb39cbb
bubblewrap-0.11.2.tar.xz|https://github.com/containers/bubblewrap/releases/download/v0.11.2/bubblewrap-0.11.2.tar.xz|6376255e2e505100e01b20c2dafa7faf
gstreamer-1.28.6.tar.xz|https://gstreamer.freedesktop.org/src/gstreamer/gstreamer-1.28.6.tar.xz|3d16d7912727ea85ab90b9e5f3bc6e8a
gst-plugins-base-1.28.6.tar.xz|https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-1.28.6.tar.xz|cd0b2bd13e8196d5bfb20459c12a5d9b
xdg-desktop-portal-1.22.1.tar.xz|https://github.com/flatpak/xdg-desktop-portal/releases/download/1.22.1/xdg-desktop-portal-1.22.1.tar.xz|edfbfffe55a35920a303404b6c5d49a0
libnotify-0.8.8.tar.xz|https://download.gnome.org/sources/libnotify/0.8/libnotify-0.8.8.tar.xz|35bef24dc1e9a336394556d09345e078
hicolor-icon-theme-0.18.tar.xz|https://icon-theme.freedesktop.org/releases/hicolor-icon-theme-0.18.tar.xz|ef14f3af03bcde9ed134aad626bdbaad
desktop-file-utils-0.28.tar.xz|https://www.freedesktop.org/software/desktop-file-utils/releases/desktop-file-utils-0.28.tar.xz|dec5d7265c802db1fde3980356931b7b
alsa-ucm-conf-1.2.16.1.tar.bz2|https://www.alsa-project.org/files/pub/lib/alsa-ucm-conf-1.2.16.1.tar.bz2|-
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
hint_nss()          { echo "      (NSS builds single-threaded on purpose, ~5 min)"; }
hint_pipewire()     { echo "      (PipeWire is big, ~3 min)"; }

b_duktape() {
  sed -i 's/-Os/-O2/' Makefile.sharedlibrary
  make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr
  make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr install
}
b_polkit() {
  getent group polkitd >/dev/null || groupadd -fg 27 polkitd
  getent passwd polkitd >/dev/null || useradd -c "PolicyKit Daemon Owner" -d /etc/polkit-1 -u 27 -g polkitd -s /bin/false polkitd
  sh_meson -D man=false -D session_tracking=logind -D tests=false
  cat > /etc/pam.d/polkit-1 << "EOF"
# Begin /etc/pam.d/polkit-1

auth     include        system-auth
account  include        system-account
password include        system-password
session  include        system-session

# End /etc/pam.d/polkit-1
EOF
  ls -l /usr/lib/polkit-1/polkit-agent-helper-1
}
b_libgudev()   { sh_meson; }
b_upower()     { sh_meson -D gtk-doc=false -D man=false; }
b_alsalib() {
  ./configure
  make
  make install
  mkdir -p /usr/share/alsa
  tar -C /usr/share/alsa --strip-components=1 -xf "$SRC/alsa-ucm-conf-1.2.16.1.tar.bz2"
}
b_sbc()        { sh_auto --disable-static --disable-tester; }
b_libical() {
  mkdir build; cd build
  cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -D LIBICAL_STATIC=NO \
        -D LIBICAL_BUILD_DOCS=false -D LIBICAL_GLIB_VAPI=false -D LIBICAL_JAVA_BINDINGS=OFF \
        -D LIBICAL_GOBJECT_INTROSPECTION=true ..
  make -j1
  make install
}
b_bluez() {
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-library
  make
  make install
  ln -svf ../libexec/bluetooth/bluetoothd /usr/sbin
  install -v -dm555 /etc/bluetooth
  install -v -m644 src/main.conf /etc/bluetooth/main.conf
  printf '# Start rfcomm.conf\n# End of rfcomm.conf\n' > /etc/bluetooth/rfcomm.conf
  printf '# Start uart.conf\n# End of uart.conf\n' > /etc/bluetooth/uart.conf
  systemctl enable bluetooth
  systemctl enable --global obex || true
}
b_nspr() {
  cd nspr
  sed -i '/^RELEASE/s|^|#|' pr/src/misc/Makefile.in
  sed -i 's|$(LIBRARY) ||'  config/rules.mk
  ./configure --prefix=/usr --with-mozilla --with-pthreads --enable-64bit
  make
  make install
}
b_nss() {
  patch -Np1 -i "$SRC/nss-standalone-1.patch"
  cd nss
  make -j1 BUILD_OPT=1 NSPR_INCLUDE_DIR=/usr/include/nspr USE_SYSTEM_ZLIB=1 ZLIB_LIBS=-lz \
       NSS_ENABLE_WERROR=0 NSS_USE_SYSTEM_SQLITE=1 USE_64=1
  cd ../dist
  install -v -m755 Linux*/lib/*.so  /usr/lib
  install -v -m644 Linux*/lib/*.chk /usr/lib
  install -v -m755 -d               /usr/include/nss
  cp -v -RL {public,private}/nss/*  /usr/include/nss
  install -v -m755 Linux*/bin/{certutil,nss-config,pk12util} /usr/bin
  install -v -m644 Linux*/lib/pkgconfig/nss.pc  /usr/lib/pkgconfig
  ln -sfv ./pkcs11/p11-kit-trust.so /usr/lib/libnssckbi.so
}
b_libndp()     { sh_auto --sysconfdir=/etc --localstatedir=/var --disable-static; }
b_nm() {
  grep -rl '^#!.*python$' . | xargs sed -i '1s/python/&3/' || true
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release \
        -D libaudit=no -D nmtui=false -D ovs=false -D ppp=false -D nbft=false -D selinux=false \
        -D qt=false -D session_tracking=systemd -D nm_cloud_setup=false -D clat=false \
        -D modem_manager=false -D introspection=false -D vapi=false -D docs=false -D tests=no
  ninja
  ninja install
  rm -rf /usr/share/doc/NetworkManager-1.58.1; mv -v /usr/share/doc/NetworkManager{,-1.58.1} 2>/dev/null || true
  install -dm755 /etc/NetworkManager/conf.d
  printf '[main]\nplugins=keyfile\n' > /etc/NetworkManager/NetworkManager.conf
  printf '[main]\nauth-polkit=true\n' > /etc/NetworkManager/conf.d/polkit.conf
  printf '[main]\ndns=none\n'         > /etc/NetworkManager/conf.d/no-dns-update.conf
  printf '[keyfile]\nunmanaged-devices=interface-name:en*;interface-name:eth*\n' > /etc/NetworkManager/conf.d/10-jj-unmanaged.conf
  getent group netdev >/dev/null || groupadd -fg 86 netdev
  usermod -a -G netdev jj
  mkdir -p /usr/share/polkit-1/rules.d
  cat > /usr/share/polkit-1/rules.d/org.freedesktop.NetworkManager.rules << "EOF"
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 && subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
EOF
  systemctl enable NetworkManager
  systemctl disable NetworkManager-wait-online || true
  systemctl start NetworkManager || true
}
b_sharedmime() { sh_meson -D update-mimedb=true -D build-tests=false -D build-spec=false; }
b_hicolor()    { sh_meson; }
b_dfu()        { sh_meson; }
b_gdkpixbuf()  { sh_meson -D glycin=disabled -D thumbnailer=disabled --wrap-mode=nofallback; gdk-pixbuf-query-loaders --update-cache || true; }
b_jsonglib()   { sh_meson; }
b_libnotify()  { sh_meson -D gtk_doc=false -D man=false -D tests=false; }
b_lua() {
  patch -Np1 -i "$SRC/lua-5.4.8-shared_library-1.patch"
  cat > lua.pc << "EOF"
V=5.4
R=5.4.8

prefix=/usr
INSTALL_BIN=${prefix}/bin
INSTALL_INC=${prefix}/include
INSTALL_LIB=${prefix}/lib
INSTALL_MAN=${prefix}/share/man/man1
INSTALL_LMOD=${prefix}/share/lua/${V}
INSTALL_CMOD=${prefix}/lib/lua/${V}
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: Lua
Description: An Extensible Extension Language
Version: ${R}
Requires:
Libs: -L${libdir} -llua -lm -ldl
Cflags: -I${includedir}
EOF
  make linux
  make INSTALL_TOP=/usr INSTALL_DATA="cp -d" INSTALL_MAN=/usr/share/man/man1 \
       TO_LIB="liblua.so liblua.so.5.4 liblua.so.5.4.8" install
  install -v -m644 -D lua.pc /usr/lib/pkgconfig/lua.pc
}
b_pipewire()   { sh_meson -D session-managers="[]"; }
b_wireplumber() {
  sh_meson -D system-lua=true
  systemctl enable --global pipewire.socket pipewire-pulse.socket wireplumber || true
}
b_fuse3() {
  sed -i '/^udev/,$ s/^/#/' util/meson.build
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release
  ninja
  ninja install
  chmod u+s /usr/bin/fusermount3
  printf '#mount_max = 1000\n#user_allow_other\n' > /etc/fuse.conf
}
b_bwrap()      { sh_meson; }
b_gstreamer()  { sh_meson -D gst_debug=false -D tests=disabled -D examples=disabled -D doc=disabled; }
b_gstbase()    { sh_meson --wrap-mode=nodownload -D tests=disabled -D examples=disabled -D doc=disabled; }
b_portal()     { sh_meson -D tests=disabled; }

pkg duktape     duktape-2.7.0.tar.xz          b_duktape
pkg polkit      polkit-127.tar.gz             b_polkit
pkg libgudev    libgudev-238.tar.xz           b_libgudev
pkg upower      upower-v1.91.3.tar.bz2        b_upower
pkg alsalib     alsa-lib-1.2.16.1.tar.bz2     b_alsalib
pkg sbc         sbc-2.2.tar.xz                b_sbc
pkg libical     libical-4.0.5.tar.gz          b_libical
pkg bluez       bluez-5.87.tar.xz             b_bluez
pkg nspr        nspr-4.40.tar.gz              b_nspr
pkg nss         nss-3.126.tar.gz              b_nss
pkg libndp      libndp-1.9.tar.gz             b_libndp
pkg nm          NetworkManager-1.58.1.tar.xz  b_nm
pkg sharedmime  shared-mime-info-2.5.1.tar.gz b_sharedmime
pkg hicolor     hicolor-icon-theme-0.18.tar.xz b_hicolor
pkg dfu         desktop-file-utils-0.28.tar.xz b_dfu
pkg gdkpixbuf   gdk-pixbuf-2.44.7.tar.xz     b_gdkpixbuf
pkg jsonglib    json-glib-1.10.8.tar.xz       b_jsonglib
pkg libnotify   libnotify-0.8.8.tar.xz        b_libnotify
pkg lua         lua-5.4.8.tar.gz              b_lua
pkg pipewire    pipewire-1.6.8.tar.bz2        b_pipewire
pkg wireplumber wireplumber-0.5.15.tar.bz2    b_wireplumber
pkg fuse3       fuse-3.18.2.tar.gz            b_fuse3
pkg bwrap       bubblewrap-0.11.2.tar.xz      b_bwrap
pkg gstreamer   gstreamer-1.28.6.tar.xz        b_gstreamer
pkg gstbase     gst-plugins-base-1.28.6.tar.xz b_gstbase
pkg portal      xdg-desktop-portal-1.22.1.tar.xz b_portal


# ------------------------------------------------------------------ verification (non-fatal)
echo
echo "=== verification ==="
setpath
ok=0; bad=0
for m in polkit-gobject-1 polkit-agent-1 gudev-1.0 upower-glib bluez libical nss nspr libnm \
         gdk-pixbuf-2.0 json-glib-1.0 libnotify lua libpipewire-0.3 wireplumber-0.5 alsa libndp xdg-desktop-portal fuse3; do
  chk "pc:$m" pkg-config --modversion "$m"
done
chk pkaction      sh -c 'pkaction --version'
chk polkit-unit   sh -c 'systemctl cat polkit.service >/dev/null && echo unit-present'
chk upower-unit   sh -c 'systemctl cat upower.service >/dev/null && echo unit-present'
chk NetworkManager sh -c 'systemctl is-active NetworkManager | grep -x active'
chk nmcli         sh -c 'nmcli -t general status | head -n1'
chk eth-still-up  sh -c 'ip -4 -o addr show scope global | head -n1'
chk bluetoothd    sh -c '/usr/libexec/bluetooth/bluetoothd --version'
chk pipewire      sh -c 'pipewire --version | tail -n1'
chk wpctl         sh -c 'wpctl --version | head -n1'
chk pw-units      sh -c 'ls /usr/lib/systemd/user/pipewire.socket /usr/lib/systemd/user/wireplumber.service'
chk portal-bin    sh -c 'ls /usr/libexec/xdg-desktop-portal'
chk pixbuf-png    sh -c 'gdk-pixbuf-query-loaders | grep -m1 -i png'
chk lua           sh -c 'lua -v'
echo
if [ "$bad" = 0 ]; then
  echo "=== BLFS stage C3 DONE in $(( (SECONDS - T_ALL) / 60 )) min  ($ok checks passed) ==="
else
  echo "=== stage C3 built but $bad check(s) FAILED ($ok passed) -- paste the FAIL lines to me ==="
fi
echo "Next: snapshot (virsh snapshot-create-as LFS-13.1 v0.6-services), then C4 (Qt6, trimmed)."
