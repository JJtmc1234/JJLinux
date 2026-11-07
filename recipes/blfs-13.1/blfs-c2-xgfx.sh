#!/bin/bash
# JJLinux -- BLFS stage C2: the graphics and input foundation under the Omarchy desktop.
#   Xorg protocol/libs + xcb-util, GLib (+GObject Introspection), image libs (jpeg/gif/tiff/webp/lcms2),
#   HarfBuzz(+glib), Cairo, Pango, librsvg, SPIRV/glslang, Vulkan loader, Mesa rebuilt with X11 + lavapipe,
#   libepoxy, libdisplay-info, libliftoff, mtdev, libevdev, libinput, libtirpc, Xorg apps, Xwayland.
# Run after C1 (PAM) is done and rebooted:   su -   then   bash blfs-c2-xgfx.sh
# Resumable (finished packages are skipped).  Logs: /var/log/blfs-c/<name>.log   (e.g. tail -f /var/log/blfs-c/xlibs.log)
# Versions/commands: BLFS 13.1-systemd.  Skipped on purpose: gdk-pixbuf, Xorg Fonts, Xorg server, libei, libwacom.
set -euo pipefail

# ------------------------------------------------------------------ common settings
JJ_STAGE=c2
TOTAL=36
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
echo "JJLinux stage C2 (Xorg libs, GLib/Cairo/Pango, Vulkan, Mesa+X11, input stack, Xwayland) | RAM ${RAM_GB} GB, $NP CPUs -> $JOBS parallel jobs"

# ------------------------------------------------------------------ preflight
echo "=== preflight ==="
pf_fail=0
for t in gcc g++ make meson ninja cmake python3 pip3 curl git patch pkg-config bison flex xz tar; do
  command -v "$t" >/dev/null 2>&1 || { echo "  MISSING tool: $t"; pf_fail=1; }
done
curl -fsS -o /dev/null --connect-timeout 15 -r 0-99 https://github.com/ \
  || { echo "  CANNOT reach github.com over HTTPS"; pf_fail=1; }
FREE_GB=$(df -BG --output=avail /var/tmp | tail -n1 | tr -dc 0-9)
[ "${FREE_GB:-0}" -ge 15 ] || { echo "  Only ${FREE_GB} GB free in /var/tmp (want 15+)"; pf_fail=1; }
[ -f "$STATE/seatd2.done" ] || { echo "  stage C1 (blfs-c1-pam.sh) has not finished - run it first"; pf_fail=1; }
[ "$pf_fail" = 0 ] || { echo "Preflight failed - fix the above and re-run."; exit 1; }
echo "  ok (${FREE_GB} GB free)"

# ------------------------------------------------------------------ sources
# file|url[,mirror...]|md5   (md5 '-' = no published checksum; we sanity-check the archive and log our own md5)
cat > "$SRC/list-$JJ_STAGE.txt" << 'LISTEOF'
util-macros-1.20.2.tar.xz|https://www.x.org/pub/individual/util/util-macros-1.20.2.tar.xz|5f683a1966834b0a6ae07b3680bcb863
xorgproto-2025.1.tar.xz|https://xorg.freedesktop.org/archive/individual/proto/xorgproto-2025.1.tar.xz|15534fa6fb13a6a70afe7561c1424f3c
libXau-1.0.12.tar.xz|https://www.x.org/pub/individual/lib/libXau-1.0.12.tar.xz|4c9f81acf00b62e5de56a912691bd737
libXdmcp-1.1.5.tar.xz|https://www.x.org/pub/individual/lib/libXdmcp-1.1.5.tar.xz|ce0af51de211e4c99a111e64ae1df290
xcb-proto-1.17.0.tar.xz|https://xorg.freedesktop.org/archive/individual/proto/xcb-proto-1.17.0.tar.xz|c415553d2ee1a8cea43c3234a079b53f
libxcb-1.17.0.tar.xz|https://xorg.freedesktop.org/archive/individual/lib/libxcb-1.17.0.tar.xz|96565523e9f9b701fcb35d31f1d4086e
xcb-util-0.4.1.tar.xz|https://xcb.freedesktop.org/dist/xcb-util-0.4.1.tar.xz|34d749eab0fd0ffd519ac64798d79847
libxcvt-0.1.3.tar.xz|https://www.x.org/pub/individual/lib/libxcvt-0.1.3.tar.xz|7fb9c51d33a680f724f34da41768b1d0
xbitmaps-1.1.4.tar.xz|https://www.x.org/pub/individual/data/xbitmaps-1.1.4.tar.xz|793992635c45250028eaec226af416fc
glib-2.88.3.tar.xz|https://download.gnome.org/sources/glib/2.88/glib-2.88.3.tar.xz|b61c04cfbf55b0d24fbe64e4ac9e9d56
nasm-3.02.tar.xz|https://www.nasm.us/pub/nasm/releasebuilds/3.02/nasm-3.02.tar.xz|31ba022fff8de3065b5bc5ad5559188c
libjpeg-turbo-3.2.0.tar.gz|https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz|a80f9f1c735b57d3cdd66daed1ba6bb4
giflib-6.1.3.tar.gz|https://downloads.sourceforge.net/giflib/giflib-6.1.3.tar.gz,https://sourceforge.net/projects/giflib/files/giflib-6.1.3.tar.gz|a70e90ff780e9ebee9cb84b82bbd46a7
tiff-4.7.2.tar.gz|https://download.osgeo.org/libtiff/tiff-4.7.2.tar.gz|a2a65ea450b8f469c667128848ffebfc
libwebp-1.6.0.tar.gz|https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz|cceb6447180f961473b181c9ef38b630
lcms2-2.19.1.tar.gz|https://github.com/mm2/Little-CMS/releases/download/lcms2.19.1/lcms2-2.19.1.tar.gz|541978f73749499e9e0277bfe5a3c868
cairo-1.18.4.tar.xz|https://www.cairographics.org/releases/cairo-1.18.4.tar.xz|db575fb41bbda127e0147e401f36f8ac
pango-1.58.2.tar.xz|https://download.gnome.org/sources/pango/1.58/pango-1.58.2.tar.xz|7b5640fd9adfa24554a88b2b9a6cd3f3
librsvg-2.62.3.tar.xz|https://download.gnome.org/sources/librsvg/2.62/librsvg-2.62.3.tar.xz|bf6d56ffe4cfa5426cf1a67bcabdf5ce
libepoxy-1.5.10.tar.xz|https://download.gnome.org/sources/libepoxy/1.5/libepoxy-1.5.10.tar.xz|10c635557904aed5239a4885a7c4efb7
libdisplay-info-0.4.0.tar.xz|https://gitlab.freedesktop.org/emersion/libdisplay-info/-/releases/0.4.0/downloads/libdisplay-info-0.4.0.tar.xz|af9f07493bd5ff560a98b95ea4c5c129
libliftoff-v0.5.0.tar.gz|https://gitlab.freedesktop.org/emersion/libliftoff/-/archive/v0.5.0/libliftoff-v0.5.0.tar.gz|e26483537eea0db5469b71c783189f74
mtdev-1.1.7.tar.bz2|https://bitmath.org/code/mtdev/mtdev-1.1.7.tar.bz2|483ed7fdf7c1e7b7375c05a62848cce7
SPIRV-Headers-vulkan-sdk-1.4.357.0.tar.gz|https://github.com/KhronosGroup/SPIRV-Headers/archive/vulkan-sdk-1.4.357.0/SPIRV-Headers-vulkan-sdk-1.4.357.0.tar.gz|085dd07d487c165c0ca7713d726eb6de
SPIRV-Tools-vulkan-sdk-1.4.357.0.tar.gz|https://github.com/KhronosGroup/SPIRV-Tools/archive/vulkan-sdk-1.4.357.0/SPIRV-Tools-vulkan-sdk-1.4.357.0.tar.gz|c357eec1e33bc95e650aa4c8efdd3b13
glslang-16.5.0.tar.gz|https://github.com/KhronosGroup/glslang/archive/16.5.0/glslang-16.5.0.tar.gz|79e949d6d50cc167e7d5307afb04c41a
xwayland-24.1.13.tar.xz|https://www.x.org/pub/individual/xserver/xwayland-24.1.13.tar.xz|f84a91c4d3aee2b18b1864fe2bbe78c3
mesa-26.1.7.tar.xz|https://mesa.freedesktop.org/archive/mesa-26.1.7.tar.xz|1a3ea044abc823e2db8c6041e5adcc4f
harfbuzz-14.3.1.tar.xz|https://github.com/harfbuzz/harfbuzz/releases/download/14.3.1/harfbuzz-14.3.1.tar.xz|4baccda978c92e5f27702ed8b3ceefa7
gobject-introspection-1.86.0.tar.xz|https://download.gnome.org/sources/gobject-introspection/1.86/gobject-introspection-1.86.0.tar.xz|fa0f2ae76868bf35ff725f940d75ec16
libevdev-1.13.6.tar.xz|https://www.freedesktop.org/software/libevdev/libevdev-1.13.6.tar.xz|4202ff132e3efe95fe9ca2c4f8f119f7
libinput-1.31.3.tar.gz|https://gitlab.freedesktop.org/libinput/libinput/-/archive/1.31.3/libinput-1.31.3.tar.gz|022aa3838b0cf8b932c0e4a4dbeac150
xtrans-1.6.0.tar.xz|https://www.x.org/pub/individual/lib/xtrans-1.6.0.tar.xz|6ad67d4858814ac24e618b8072900664
libX11-1.8.13.tar.xz|https://www.x.org/pub/individual/lib/libX11-1.8.13.tar.xz|b617a053d2003cc81309f4e13d01379c
libXext-1.3.7.tar.xz|https://www.x.org/pub/individual/lib/libXext-1.3.7.tar.xz|ea8149187a26e9df6dbd94a60b3d8da0
libFS-1.0.10.tar.xz|https://www.x.org/pub/individual/lib/libFS-1.0.10.tar.xz|c5cc0942ed39c49b8fcd47a427bd4305
libICE-1.1.2.tar.xz|https://www.x.org/pub/individual/lib/libICE-1.1.2.tar.xz|d1ffde0a07709654b20bada3f9abdd16
libSM-1.2.6.tar.xz|https://www.x.org/pub/individual/lib/libSM-1.2.6.tar.xz|3aeeea05091db1c69e6f768e0950a431
libXScrnSaver-1.2.5.tar.xz|https://www.x.org/pub/individual/lib/libXScrnSaver-1.2.5.tar.xz|ec09c90a1cfd2c0630321d366a5e7203
libXt-1.3.1.tar.xz|https://www.x.org/pub/individual/lib/libXt-1.3.1.tar.xz|9acd189c68750b5028cf120e53c68009
libXmu-1.3.1.tar.xz|https://www.x.org/pub/individual/lib/libXmu-1.3.1.tar.xz|1ef8065f0284e76c2238770365012ab2
libXpm-3.5.19.tar.xz|https://www.x.org/pub/individual/lib/libXpm-3.5.19.tar.xz|cdc7a83243dba674b1ea3c365a1deab1
libXaw-1.0.16.tar.xz|https://www.x.org/pub/individual/lib/libXaw-1.0.16.tar.xz|2a9793533224f92ddad256492265dd82
libXfixes-6.0.2.tar.xz|https://www.x.org/pub/individual/lib/libXfixes-6.0.2.tar.xz|baa39ada682dd524491a165bb0dfc708
libXcomposite-0.4.7.tar.xz|https://www.x.org/pub/individual/lib/libXcomposite-0.4.7.tar.xz|132816d5efccb883bbc2bf45eb905770
libXrender-0.9.12.tar.xz|https://www.x.org/pub/individual/lib/libXrender-0.9.12.tar.xz|4c54dce455d96e3bdee90823b0869f89
libXcursor-1.2.3.tar.xz|https://www.x.org/pub/individual/lib/libXcursor-1.2.3.tar.xz|5ce55e952ec2d84d9817169d5fdb7865
libXdamage-1.1.7.tar.xz|https://www.x.org/pub/individual/lib/libXdamage-1.1.7.tar.xz|72bb73f2a07f81784ad69a39d7df1da2
libfontenc-1.1.9.tar.xz|https://www.x.org/pub/individual/lib/libfontenc-1.1.9.tar.xz|3cba344d6b351cf308114865afa0d91e
libXfont2-2.0.9.tar.xz|https://www.x.org/pub/individual/lib/libXfont2-2.0.9.tar.xz|134b3f673f6ecd3e67c0e892dd1a89e8
libXft-2.3.9.tar.xz|https://www.x.org/pub/individual/lib/libXft-2.3.9.tar.xz|d378be0fcbd1f689f9a132e0d642bc4b
libXi-1.8.3.tar.xz|https://www.x.org/pub/individual/lib/libXi-1.8.3.tar.xz|2b1cde310bc361464df43276fb969adf
libXinerama-1.1.6.tar.xz|https://www.x.org/pub/individual/lib/libXinerama-1.1.6.tar.xz|5f3f5754a40730d1518233a60ba5c48e
libXrandr-1.5.5.tar.xz|https://www.x.org/pub/individual/lib/libXrandr-1.5.5.tar.xz|b550dfa388292a821aecdd52acecc94c
libXres-1.2.3.tar.xz|https://www.x.org/pub/individual/lib/libXres-1.2.3.tar.xz|5014282a08b54ec0edfa73c5cf9ae2c1
libXtst-1.2.5.tar.xz|https://www.x.org/pub/individual/lib/libXtst-1.2.5.tar.xz|b62dc44d8e63a67bb10230d54c44dcb7
libXv-1.0.13.tar.xz|https://www.x.org/pub/individual/lib/libXv-1.0.13.tar.xz|8a26503185afcb1bbd2c65e43f775a67
libXvMC-1.0.15.tar.xz|https://www.x.org/pub/individual/lib/libXvMC-1.0.15.tar.xz|de4227c5722a8f5ca5748f3ef524aeee
libXxf86dga-1.1.7.tar.xz|https://www.x.org/pub/individual/lib/libXxf86dga-1.1.7.tar.xz|543164f1239fbe92cc0a9128d8da88e9
libXxf86vm-1.1.7.tar.xz|https://www.x.org/pub/individual/lib/libXxf86vm-1.1.7.tar.xz|bea9e3707fae6c3275769e771006fa0f
libpciaccess-0.19.tar.xz|https://www.x.org/pub/individual/lib/libpciaccess-0.19.tar.xz|0c11ea502b531e59563a9aa7979146fc
libxkbfile-1.2.0.tar.xz|https://www.x.org/pub/individual/lib/libxkbfile-1.2.0.tar.xz|fa0faa5b6a8e726186c535d73712ccea
libxshmfence-1.3.3.tar.xz|https://www.x.org/pub/individual/lib/libxshmfence-1.3.3.tar.xz|9805be7e18f858bed9938542ed2905dc
libXpresent-1.0.2.tar.xz|https://www.x.org/pub/individual/lib/libXpresent-1.0.2.tar.xz|53b72ce969745f8d3e41175d6549ce0b
xcb-util-image-0.4.1.tar.xz|https://xorg.freedesktop.org/archive/individual/lib/xcb-util-image-0.4.1.tar.xz|a67bfac2eff696170259ef1f5ce1b611
xcb-util-keysyms-0.4.1.tar.xz|https://xorg.freedesktop.org/archive/individual/lib/xcb-util-keysyms-0.4.1.tar.xz|fbdc05f86f72f287ed71b162f1a9725a
xcb-util-renderutil-0.3.10.tar.xz|https://xorg.freedesktop.org/archive/individual/lib/xcb-util-renderutil-0.3.10.tar.xz|193b890e2a89a53c31e2ece3afcbd55f
xcb-util-wm-0.4.2.tar.xz|https://xorg.freedesktop.org/archive/individual/lib/xcb-util-wm-0.4.2.tar.xz|581b3a092e3c0c1b4de6416d90b969c3
xcb-util-cursor-0.1.6.tar.xz|https://xorg.freedesktop.org/archive/individual/lib/xcb-util-cursor-0.1.6.tar.xz|e85bccd1993992be07232f8b80a814c8
xcb-util-errors-1.0.1.tar.xz|https://xorg.freedesktop.org/archive/individual/lib/xcb-util-errors-1.0.1.tar.xz|322cf9df283625223933ffcecb4a1cca
iceauth-1.0.11.tar.xz|https://www.x.org/pub/individual/app/iceauth-1.0.11.tar.xz|36936e5bcf04b982ea87b4556d082061
mkfontscale-1.2.4.tar.xz|https://www.x.org/pub/individual/app/mkfontscale-1.2.4.tar.xz|83d943bbb0e3ab868cb0a7438e135544
sessreg-1.1.4.tar.xz|https://www.x.org/pub/individual/app/sessreg-1.1.4.tar.xz|b9efe1d21615c474b22439d41981beef
setxkbmap-1.3.5.tar.xz|https://www.x.org/pub/individual/app/setxkbmap-1.3.5.tar.xz|5a10223c3305f48bfb3b09e0a7a139d1
smproxy-1.0.8.tar.xz|https://www.x.org/pub/individual/app/smproxy-1.0.8.tar.xz|6484cd8ee30354aaaf8f490988f5f6ef
xauth-1.1.5.tar.xz|https://www.x.org/pub/individual/app/xauth-1.1.5.tar.xz|9cfdec89ad7bd86bcdfda150ae995955
xcmsdb-1.0.7.tar.xz|https://www.x.org/pub/individual/app/xcmsdb-1.0.7.tar.xz|37063ccf902fe3d55a90f387ed62fe1f
xcursorgen-1.0.9.tar.xz|https://www.x.org/pub/individual/app/xcursorgen-1.0.9.tar.xz|f97e81b2c063f6ae9b18d4b4be7543f6
xdpyinfo-1.4.0.tar.xz|https://www.x.org/pub/individual/app/xdpyinfo-1.4.0.tar.xz|700556957773d378fa16a65a4406be0a
xdriinfo-1.0.8.tar.xz|https://www.x.org/pub/individual/app/xdriinfo-1.0.8.tar.xz|830a54ef3ba338013e06a1b5b012b4bd
xev-1.2.7.tar.xz|https://www.x.org/pub/individual/app/xev-1.2.7.tar.xz|6d2309b05267e31923b11ed2b83f33ae
xgamma-1.0.8.tar.xz|https://www.x.org/pub/individual/app/xgamma-1.0.8.tar.xz|687e42aa5afaec37f14da3072651c635
xhost-1.0.10.tar.xz|https://www.x.org/pub/individual/app/xhost-1.0.10.tar.xz|45c7e956941194e5f06a9c7307f5f971
xinput-1.6.4.tar.xz|https://www.x.org/pub/individual/app/xinput-1.6.4.tar.xz|8e4d14823b7cbefe1581c398c6ab0035
xkbcomp-1.5.0.tar.xz|https://www.x.org/pub/individual/app/xkbcomp-1.5.0.tar.xz|b8128ff6816897bd385ca437cd2886ee
xkbevd-1.1.6.tar.xz|https://www.x.org/pub/individual/app/xkbevd-1.1.6.tar.xz|543c0535367ca30e0b0dbcfa90fefdf9
xkbutils-1.0.7.tar.xz|https://www.x.org/pub/individual/app/xkbutils-1.0.7.tar.xz|c572508053297094995f1fc4bc681624
xkill-1.0.7.tar.xz|https://www.x.org/pub/individual/app/xkill-1.0.7.tar.xz|294db9393a9d8e6613e1e3dd4fe0273f
xlsatoms-1.1.5.tar.xz|https://www.x.org/pub/individual/app/xlsatoms-1.1.5.tar.xz|a98d83568d19cc606b114b133d6ed8be
xlsclients-1.1.6.tar.xz|https://www.x.org/pub/individual/app/xlsclients-1.1.6.tar.xz|cf2fc9e9d298c149253cfc77faaa475e
xmessage-1.0.7.tar.xz|https://www.x.org/pub/individual/app/xmessage-1.0.7.tar.xz|ba2dd3db3361e374fefe2b1c797c46eb
xmodmap-1.0.12.tar.xz|https://www.x.org/pub/individual/app/xmodmap-1.0.12.tar.xz|4e6b8655260cca88252e86f5431041c0
xpr-1.2.0.tar.xz|https://www.x.org/pub/individual/app/xpr-1.2.0.tar.xz|ab6c9d17eb1940afcfb80a72319270ae
xprop-1.2.8.tar.xz|https://www.x.org/pub/individual/app/xprop-1.2.8.tar.xz|5ef4784b406d11bed0fdf07cc6fba16c
xrandr-1.5.4.tar.xz|https://www.x.org/pub/individual/app/xrandr-1.5.4.tar.xz|211abd989eef11708cc0a4978d101014
xrdb-1.2.3.tar.xz|https://www.x.org/pub/individual/app/xrdb-1.2.3.tar.xz|44894ebd60a40c54ccc44c67ad3b7de8
xrefresh-1.1.1.tar.xz|https://www.x.org/pub/individual/app/xrefresh-1.1.1.tar.xz|af26f2a7f128f27e0df30ef246687726
xset-1.2.6.tar.xz|https://www.x.org/pub/individual/app/xset-1.2.6.tar.xz|95fcb2ae70ee7e7ef7fe70b096b3d254
xsetroot-1.1.4.tar.xz|https://www.x.org/pub/individual/app/xsetroot-1.1.4.tar.xz|33c80b7744f9a452bf9e39ea7303650e
xvinfo-1.1.6.tar.xz|https://www.x.org/pub/individual/app/xvinfo-1.1.6.tar.xz|5076c46fe4f6da29377e462ad25c893d
xwd-1.0.10.tar.xz|https://www.x.org/pub/individual/app/xwd-1.0.10.tar.xz|ee94a7722c8b9e37a28f1ac0fc371454
xwininfo-1.1.7.tar.xz|https://www.x.org/pub/individual/app/xwininfo-1.1.7.tar.xz|e24406c671ab09a7ab0e13a7d1ef2752
xwud-1.0.8.tar.xz|https://www.x.org/pub/individual/app/xwud-1.0.8.tar.xz|53d99fe7077b162b0cb87189f7ed71ce
libtirpc-1.3.7.tar.bz2|https://downloads.sourceforge.net/libtirpc/libtirpc-1.3.7.tar.bz2|74f97df306b8d6149d3d9898a1d44c6e
Vulkan-Headers-vulkan-sdk-1.4.357.0.tar.gz|https://github.com/KhronosGroup/Vulkan-Headers/archive/vulkan-sdk-1.4.357.0/Vulkan-Headers-vulkan-sdk-1.4.357.0.tar.gz|64a23bb12e95a2017004d72569132929
Vulkan-Loader-vulkan-sdk-1.4.357.0.tar.gz|https://github.com/KhronosGroup/Vulkan-Loader/archive/vulkan-sdk-1.4.357.0/Vulkan-Loader-vulkan-sdk-1.4.357.0.tar.gz|ce35f16bee47e9faf0a50d682a2db77d
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
XLIBS=(
  xtrans-1.6.0.tar.xz
  libX11-1.8.13.tar.xz
  libXext-1.3.7.tar.xz
  libFS-1.0.10.tar.xz
  libICE-1.1.2.tar.xz
  libSM-1.2.6.tar.xz
  libXScrnSaver-1.2.5.tar.xz
  libXt-1.3.1.tar.xz
  libXmu-1.3.1.tar.xz
  libXpm-3.5.19.tar.xz
  libXaw-1.0.16.tar.xz
  libXfixes-6.0.2.tar.xz
  libXcomposite-0.4.7.tar.xz
  libXrender-0.9.12.tar.xz
  libXcursor-1.2.3.tar.xz
  libXdamage-1.1.7.tar.xz
  libfontenc-1.1.9.tar.xz
  libXfont2-2.0.9.tar.xz
  libXft-2.3.9.tar.xz
  libXi-1.8.3.tar.xz
  libXinerama-1.1.6.tar.xz
  libXrandr-1.5.5.tar.xz
  libXres-1.2.3.tar.xz
  libXtst-1.2.5.tar.xz
  libXv-1.0.13.tar.xz
  libXvMC-1.0.15.tar.xz
  libXxf86dga-1.1.7.tar.xz
  libXxf86vm-1.1.7.tar.xz
  libpciaccess-0.19.tar.xz
  libxkbfile-1.2.0.tar.xz
  libxshmfence-1.3.3.tar.xz
  libXpresent-1.0.2.tar.xz
)

XCBUTILS=(
  xcb-util-image-0.4.1.tar.xz
  xcb-util-keysyms-0.4.1.tar.xz
  xcb-util-renderutil-0.3.10.tar.xz
  xcb-util-wm-0.4.2.tar.xz
  xcb-util-cursor-0.1.6.tar.xz
  xcb-util-errors-1.0.1.tar.xz
)

XAPPS=(
  iceauth-1.0.11.tar.xz
  mkfontscale-1.2.4.tar.xz
  sessreg-1.1.4.tar.xz
  setxkbmap-1.3.5.tar.xz
  smproxy-1.0.8.tar.xz
  xauth-1.1.5.tar.xz
  xcmsdb-1.0.7.tar.xz
  xcursorgen-1.0.9.tar.xz
  xdpyinfo-1.4.0.tar.xz
  xdriinfo-1.0.8.tar.xz
  xev-1.2.7.tar.xz
  xgamma-1.0.8.tar.xz
  xhost-1.0.10.tar.xz
  xinput-1.6.4.tar.xz
  xkbcomp-1.5.0.tar.xz
  xkbevd-1.1.6.tar.xz
  xkbutils-1.0.7.tar.xz
  xkill-1.0.7.tar.xz
  xlsatoms-1.1.5.tar.xz
  xlsclients-1.1.6.tar.xz
  xmessage-1.0.7.tar.xz
  xmodmap-1.0.12.tar.xz
  xpr-1.2.0.tar.xz
  xprop-1.2.8.tar.xz
  xrandr-1.5.4.tar.xz
  xrdb-1.2.3.tar.xz
  xrefresh-1.1.1.tar.xz
  xset-1.2.6.tar.xz
  xsetroot-1.1.4.tar.xz
  xvinfo-1.1.6.tar.xz
  xwd-1.0.10.tar.xz
  xwininfo-1.1.7.tar.xz
  xwud-1.0.8.tar.xz
)

# ---------------------------------------------------------------- helpers for the Xorg "loop" packages
xbuild() {   # xbuild TARBALL  -- one Xorg lib/app/xcb-util from a loop; own marker so a re-run resumes mid-loop
  local f=$1 d=${1%.tar.?z*} w
  [ -f "$STATE/x-$d.done" ] && { echo "skip $d"; return 0; }
  echo "Building $d"
  w=$BUILD/x-$d; rm -rf "$w"; mkdir -p "$w"
  tar -xf "$SRC/$f" -C "$w"
  pushd "$w/$d" >/dev/null
  case $d in
    libXfont2-[0-9]*) ./configure $XORG_CONFIG --docdir=$XORG_PREFIX/share/doc/$d --disable-devel-docs; make; make install ;;
    libXt-[0-9]*)     ./configure $XORG_CONFIG --docdir=$XORG_PREFIX/share/doc/$d --with-appdefaultdir=/etc/X11/app-defaults; make; make install ;;
    libXpm-[0-9]*)    ./configure $XORG_CONFIG --docdir=$XORG_PREFIX/share/doc/$d --disable-open-zfile; make; make install ;;
    libpciaccess*|libxkbfile*)
                      meson setup --prefix=$XORG_PREFIX --buildtype=release build; ninja -C build; ninja -C build install ;;
    *)
                      if [ -n "${XDOC:-}" ]; then ./configure $XORG_CONFIG --docdir=$XORG_PREFIX/share/doc/$d; else ./configure $XORG_CONFIG; fi
                      make; make install ;;
  esac
  popd >/dev/null
  rm -rf "$w"
  ldconfig || true
  touch "$STATE/x-$d.done"
}

# ---------------------------------------------------------------- recipes
hint_xlibs()  { echo "      (31 libraries, ~10 min: watch with  tail -f /var/log/blfs-c/xlibs.log  in a second terminal)"; }
hint_xapps()  { echo "      (35 small X apps, ~5 min: tail -f /var/log/blfs-c/xapps.log)"; }
hint_mesa2()  { echo "      (Mesa again with X11 + Vulkan lavapipe: the big one, ~10 min)"; }
hint_librsvg(){ echo "      (Rust + cargo downloads crates; ~5 min)"; }
b_xutil()   { ./configure $XORG_CONFIG; make install; }
b_xproto()  { mkdir build; cd build; meson setup --prefix=$XORG_PREFIX ..; ninja; ninja install
              mv -v $XORG_PREFIX/share/doc/xorgproto{,-2025.1} 2>/dev/null || true; }
b_libXau()  { ./configure $XORG_CONFIG; make; make install; }
b_libXdmcp(){ ./configure $XORG_CONFIG --docdir='${datadir}'/doc/libXdmcp-1.1.5; make; make install; }
b_xcbproto(){ PYTHON=python3 ./configure $XORG_CONFIG; make install; }
b_libxcb()  { ./configure $XORG_CONFIG --without-doxygen --docdir='${datadir}'/doc/libxcb-1.17.0
              LC_ALL=C.UTF-8 make; make install; }
b_xlibs()   { XDOC=1; for f in "${XLIBS[@]}"; do xbuild "$f"; done; }
b_xcbutil() { ./configure $XORG_CONFIG; make; make install
              for f in "${XCBUTILS[@]}"; do xbuild "$f"; done; }
b_libxcvt() { mkdir build; cd build; meson setup --prefix=$XORG_PREFIX --buildtype=release ..; ninja; ninja install; }
b_xbitmaps(){ ./configure $XORG_CONFIG; make install; }

b_glib2() {
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release \
        -D introspection=disabled -D glib_debug=disabled -D man-pages=disabled -D sysprof=disabled
  ninja
  ninja install
  # GObject Introspection needs glib first, then glib gets rebuilt with introspection data
  tar xf "$SRC/gobject-introspection-1.86.0.tar.xz"
  meson setup gobject-introspection-1.86.0 gi-build --prefix=/usr --buildtype=release
  ninja -C gi-build
  ninja -C gi-build install
  meson configure -D introspection=enabled
  ninja
  ninja install
  pkg-config --modversion glib-2.0 gobject-introspection-1.0
}

b_nasm()    { sh_auto; }
b_libjpeg() {
  mkdir build; cd build
  cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=RELEASE -D ENABLE_STATIC=FALSE \
        -D CMAKE_INSTALL_DEFAULT_LIBDIR=lib -D CMAKE_SKIP_INSTALL_RPATH=ON \
        -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/libjpeg-turbo-3.2.0 ..
  make
  make install
}
b_giflib()  { make; make PREFIX=/usr DOCDIR=/usr/share/doc/giflib-6.1.3 install; rm -fv /usr/lib/libgif.a; }
b_tiff()    { mkdir -p tiff-build; cd tiff-build
              cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -Wno-dev -G Ninja ..
              ninja; ninja install; mv -v /usr/share/doc/tiff{,-4.7.2} 2>/dev/null || true; }
b_libwebp() { sh_auto --enable-libwebpmux --enable-libwebpdemux --enable-libwebpdecoder \
                      --enable-libwebpextras --enable-swap-16bit-csp --disable-static; }
b_lcms2()   { sh_meson; }

b_harfbuzz2() {   # same as stage B but now with GLib/GObject (Pango needs harfbuzz-gobject)
  sh_meson -D docs=disabled -D tests=disabled -D glib=enabled -D gobject=enabled -D introspection=enabled
}
b_cairo()   { sh_meson; }
b_pango()   { sh_meson --wrap-mode=nofallback -D introspection=enabled; }
b_librsvg() {
  sed -e "/OUTDIR/s|,| / 'librsvg-2.62.3', '--no-namespace-dir',|" \
      -e '/output/s|Rsvg-2.0|librsvg-2.62.3|' -i doc/meson.build || true
  sh_meson -D pixbuf=disabled -D pixbuf-loader=disabled -D introspection=disabled \
           -D vala=disabled -D docs=disabled -D tests=false
}

b_spvheaders() { sh_cmake; }
b_spvtools()   { sh_cmake -D CMAKE_BUILD_TYPE=Release -D SPIRV_WERROR=OFF -D BUILD_SHARED_LIBS=ON \
                          -D SPIRV_TOOLS_BUILD_STATIC=OFF -D SPIRV-Headers_SOURCE_DIR=/usr; }
b_glslang()    { sh_cmake -D ALLOW_EXTERNAL_SPIRV_TOOLS=ON -D BUILD_SHARED_LIBS=ON -D GLSLANG_TESTS=OFF; }
b_vkheaders()  { sh_cmake; }
b_vkloader()   { sh_cmake -D CMAKE_SKIP_INSTALL_RPATH=ON; }

b_mesa2() {
  mkdir build; cd build
  meson setup .. \
    --prefix=/usr --buildtype=release \
    -D platforms=x11,wayland \
    -D gallium-drivers=llvmpipe,softpipe,radeonsi,svga,virgl \
    -D vulkan-drivers=swrast \
    -D valgrind=disabled -D libunwind=disabled \
    -D llvm=enabled -D shared-llvm=enabled
  ninja -j"$JOBS"
  ninja install
}

b_libepoxy()  { sh_meson; }
b_libdispinfo(){ sh_meson; }
b_libliftoff(){ sh_meson; }
b_mtdev()     { sh_auto --disable-static; }
b_libevdev()  { mkdir build; cd build
                meson setup .. --prefix=$XORG_PREFIX --buildtype=release -D documentation=disabled -D tests=disabled
                ninja; ninja install; }
b_libinput()  { mkdir build; cd build
                meson setup .. --prefix=$XORG_PREFIX --buildtype=release \
                  -D debug-gui=false -D tests=false -D libwacom=false -D udev-dir=/usr/lib/udev
                ninja; ninja install; }
b_libtirpc()  { sh_auto --sysconfdir=/etc --disable-static --disable-gssapi; }
b_xapps()     { XDOC=; for f in "${XAPPS[@]}"; do xbuild "$f"; done; }

b_xwayland() {
  sed -i '/install_man/,$d' meson.build
  mkdir -p /var/lib/xkb
  # xserver's option set shifts a bit between releases; try the book command first, then variants
  local ok=0 v
  for v in "" "-D sha1=libcrypto" "-D sha1=libcrypto -D secure-rpc=false"; do
    rm -rf build; mkdir build
    if ( cd build && meson setup .. --prefix=$XORG_PREFIX --buildtype=release -D xkb_output_dir=/var/lib/xkb $v ); then ok=1; echo "meson ok with variant: [$v]"; break; fi
  done
  [ "$ok" = 1 ]
  cd build
  ninja
  ninja install
  install -vm755 hw/vfb/Xvfb /usr/bin 2>/dev/null || true
}

pkg xutil      util-macros-1.20.2.tar.xz              b_xutil
pkg xproto     xorgproto-2025.1.tar.xz                b_xproto
pkg libxau     libXau-1.0.12.tar.xz                   b_libXau
pkg libxdmcp   libXdmcp-1.1.5.tar.xz                  b_libXdmcp
pkg xcbproto   xcb-proto-1.17.0.tar.xz                b_xcbproto
pkg libxcb     libxcb-1.17.0.tar.xz                   b_libxcb
step xlibs                                            b_xlibs
pkg xcbutil    xcb-util-0.4.1.tar.xz                  b_xcbutil
pkg libxcvt    libxcvt-0.1.3.tar.xz                   b_libxcvt
pkg xbitmaps   xbitmaps-1.1.4.tar.xz                  b_xbitmaps
pkg glib2      glib-2.88.3.tar.xz                     b_glib2
pkg nasm       nasm-3.02.tar.xz                       b_nasm
pkg libjpeg    libjpeg-turbo-3.2.0.tar.gz             b_libjpeg
pkg giflib     giflib-6.1.3.tar.gz                    b_giflib
pkg tiff       tiff-4.7.2.tar.gz                      b_tiff
pkg libwebp    libwebp-1.6.0.tar.gz                   b_libwebp
pkg lcms2      lcms2-2.19.1.tar.gz                    b_lcms2
pkg harfbuzz2  harfbuzz-14.3.1.tar.xz                 b_harfbuzz2
pkg cairo      cairo-1.18.4.tar.xz                    b_cairo
pkg pango      pango-1.58.2.tar.xz                    b_pango
pkg librsvg    librsvg-2.62.3.tar.xz                  b_librsvg
pkg spvheaders SPIRV-Headers-vulkan-sdk-1.4.357.0.tar.gz  b_spvheaders
pkg spvtools   SPIRV-Tools-vulkan-sdk-1.4.357.0.tar.gz    b_spvtools
pkg glslang    glslang-16.5.0.tar.gz                  b_glslang
pkg vkheaders  Vulkan-Headers-vulkan-sdk-1.4.357.0.tar.gz b_vkheaders
pkg vkloader   Vulkan-Loader-vulkan-sdk-1.4.357.0.tar.gz  b_vkloader
pkg mesa2      mesa-26.1.7.tar.xz                     b_mesa2
pkg libepoxy   libepoxy-1.5.10.tar.xz                 b_libepoxy
pkg libdispinfo libdisplay-info-0.4.0.tar.xz          b_libdispinfo
pkg libliftoff libliftoff-v0.5.0.tar.gz               b_libliftoff
pkg mtdev      mtdev-1.1.7.tar.bz2                    b_mtdev
pkg libevdev   libevdev-1.13.6.tar.xz                 b_libevdev
pkg libinput   libinput-1.31.3.tar.gz                 b_libinput
pkg libtirpc   libtirpc-1.3.7.tar.bz2                 b_libtirpc
step xapps                                            b_xapps
pkg xwayland   xwayland-24.1.13.tar.xz                b_xwayland


# ------------------------------------------------------------------ verification (non-fatal)
echo
echo "=== verification ==="
setpath
ok=0; bad=0
for m in x11 xcb xkbfile xi xrandr xcursor xext xfixes glib-2.0 gobject-2.0 gobject-introspection-1.0 \
         cairo pango pangocairo harfbuzz harfbuzz-gobject librsvg-2.0 libjpeg libtiff-4 libwebp lcms2 \
         vulkan egl gbm gl glesv2 epoxy libdisplay-info libliftoff mtdev libevdev libinput libdrm xcb-icccm xcb-cursor; do
  chk "pc:$m" pkg-config --modversion "$m"
done
chk Xwayland       sh -c 'Xwayland -version 2>&1 | grep -m1 -i "xwayland"'
chk xkbcomp        sh -c 'xkbcomp -version 2>&1 | head -n1; command -v xkbcomp'
chk lavapipe-icd   sh -c 'ls /usr/share/vulkan/icd.d/lvp_icd*.json'
chk glslang        sh -c 'glslang --version 2>&1 | head -n1'
chk mesa-glx       sh -c 'ls /usr/lib/libGLX_mesa.so* | head -n1'
chk rsvg-convert   sh -c 'rsvg-convert --version'
chk libinput-cli   sh -c 'libinput --version'
echo
if [ "$bad" = 0 ]; then
  echo "=== BLFS stage C2 DONE in $(( (SECONDS - T_ALL) / 60 )) min  ($ok checks passed) ==="
else
  echo "=== stage C2 built but $bad check(s) FAILED ($ok passed) -- paste the FAIL lines to me ==="
fi
echo "Next: snapshot (virsh snapshot-create-as LFS-13.1 v0.5-xgfx), then stage C3 (services: polkit, NetworkManager, bluez, pipewire...)."
