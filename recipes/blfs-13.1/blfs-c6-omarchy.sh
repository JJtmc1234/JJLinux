#!/bin/bash
# JJLinux -- BLFS stage C6: put JJ's Omarchy 4.0.0.alpha desktop on top of the C5 Hyprland/Quickshell stack.
#   Needs, next to this script:  jj-omarchy-bundle.tgz   (Omarchy payload + the 446 omarchy-* scripts + your sanitized
#   dotfiles; the bundle deliberately holds NO secrets: no gh token, secrets.zsh, windows creds, pulse cookie, opencode).
#   Tools: jq, libevent+tmux, btop, fastfetch, brightnessctl; Rust tools (ripgrep fd bat eza zoxide starship
#   tree-sitter); Go tools (gum fzf lazygit); Neovim from source + LazyVim plugin sync.
#   Fonts: JetBrainsMono Nerd Font, Noto Color Emoji, DejaVu.
#   Omarchy: /usr/share/omarchy, /usr/bin/omarchy*, uwsm env.d, profile.d, your ~/.config, a tty1 -> uwsm -> Hyprland login.
# VM-specific overrides: monitors.lua (single virtual display), uwsm/env (no Mother GPU pinning), xdg-terminals.list (foot).
# Run after C5, as: sudo bash blfs-c6-omarchy.sh     (resumable; ~35-60 min, mostly Rust + Neovim)
# Steps marked (optional) may fail without stopping the run.
set -euo pipefail

# ------------------------------------------------------------------ common settings
JJ_STAGE=c6
TOTAL=24
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
echo "JJLinux stage C6 (Omarchy port: tools, fonts, your configs, LazyVim, uwsm session) | RAM ${RAM_GB} GB, $NP CPUs -> $JOBS parallel jobs"

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
BUNDLE=$(dirname "$(readlink -f "$0")")/jj-omarchy-bundle.tgz
[ -f "$BUNDLE" ] || { echo "  missing $BUNDLE - scp jj-omarchy-bundle.tgz next to this script"; pf_fail=1; }
for m in quickshell uwsm foot hyprland; do [ -f "$STATE/$m.done" ] || { echo "  stage C5 step '$m' has not finished - run blfs-c5-hyprland.sh first"; pf_fail=1; }; done
for u in https://index.crates.io/config.json https://go.dev/dl/?mode=json https://proxy.golang.org/ https://api.github.com/rate_limit; do
  curl -fsS -o /dev/null --connect-timeout 15 "$u" || { echo "  CANNOT reach $u"; pf_fail=1; }
done
PATH=$PATH:/opt/rustc/bin:/opt/go/bin
for t in cargo; do command -v $t >/dev/null || { echo "  MISSING $t"; pf_fail=1; }; done
getent passwd "${SUDO_USER:-jj}" >/dev/null || { echo "  user ${SUDO_USER:-jj} not found"; pf_fail=1; }
[ "$pf_fail" = 0 ] || { echo "Preflight failed - fix the above and re-run."; exit 1; }
echo "  ok (${FREE_GB} GB free)"

# ------------------------------------------------------------------ sources
# file|url[,mirror...]|md5   (md5 '-' = no published checksum; we sanity-check the archive and log our own md5)
cat > "$SRC/list-$JJ_STAGE.txt" << 'LISTEOF'
JetBrainsMono.tar.xz|https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz|-
NotoColorEmoji.ttf|https://github.com/googlefonts/noto-emoji/raw/main/2D/fonts/NotoColorEmoji.ttf|-
dejavu-fonts-ttf-2.37.tar.bz2|https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2|-
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


# ---------------------------------------------------------------- C6 specifics
BUNDLE=$(dirname "$(readlink -f "$0")")/jj-omarchy-bundle.tgz
JU=${SUDO_USER:-jj}; JH=$(getent passwd "$JU" | cut -d: -f6)

tool_src() {    # tool_src NAME REPO FILEFMT [PREFIX]   FILEFMT uses @T@ for the tag and @V@ for the tag without PREFIX
  local name=$1 repo=$2 fmt=$3 prefix=${4:-} tag ver f url
  tag=$(pin "$name" github "$repo" latest "$prefix") || return 1
  ver=${tag#"$prefix"}
  f=${fmt//@V@/$ver}; f=${f//@T@/$tag}
  echo "  $name -> $tag"
  fetch_one "$f" "https://github.com/$repo/releases/download/$tag/$f" - || return 1
  rm -rf "${BUILD:?}/$name"; mkdir -p "$BUILD/$name"; tar -xf "$SRC/$f" -C "$BUILD/$name" || return 1
  cd "$BUILD/$name"/*/
}
cargo_inst() {  # cargo_inst CRATE...
  export CARGO_HOME=$BUILD/cargo-home
  cargo install --locked --root /usr --jobs "$JOBS" "$@" || return 1
}
go_inst() {     # go_inst MODULE
  export GOPATH=$BUILD/gopath GOCACHE=$BUILD/gocache GOBIN=/usr/bin GOFLAGS=-buildvcs=false
  go install "$1@latest" || return 1
}
as_user() { su - "$JU" -c "$1"; }

b_jq()       { tool_src jq jqlang/jq 'jq-@V@.tar.gz' jq- || return 1
               ./configure --prefix=/usr --disable-docs --disable-static --with-oniguruma=builtin --disable-maintainer-mode || return 1
               make -j"$JOBS" || return 1; make install || return 1; jq --version; cd /; rm -rf "$BUILD/jq"; }
b_libevent() { tool_src libevent libevent/libevent 'libevent-@V@.tar.gz' release- || return 1
               ./configure --prefix=/usr --disable-static --disable-samples || return 1
               make -j"$JOBS" || return 1; make install || return 1; cd /; rm -rf "$BUILD/libevent"; }
b_tmux()     { tool_src tmux tmux/tmux 'tmux-@V@.tar.gz' "" || return 1
               ./configure --prefix=/usr || return 1
               make -j"$JOBS" || return 1; make install || return 1; tmux -V; cd /; rm -rf "$BUILD/tmux"; }
b_btop()     { local t; t=$(pin btop github aristocratos/btop latest v) || return 1; echo "  btop -> $t"
               src_forge btop github aristocratos/btop "$t" || return 1
               make -j"$JOBS" || return 1; make install PREFIX=/usr || return 1; btop --version; cd /; rm -rf "$BUILD/btop"; }
b_fastfetch(){ cm_pinned fastfetch github fastfetch-cli/fastfetch latest "" -DBUILD_TESTS=OFF || return 1; fastfetch --version; }
b_brightnessctl() { local t; t=$(pin_ver brightnessctl github Hummer12007/brightnessctl 0.5.1) || return 1
               src_forge brightnessctl github Hummer12007/brightnessctl "$t" || return 1
               make -j"$JOBS" || return 1; make install PREFIX=/usr || return 1; cd /; rm -rf "$BUILD/brightnessctl"; }
b_rg()       { cargo_inst ripgrep || return 1; rg --version | head -n1; }
b_fd()       { cargo_inst fd-find || return 1; fd --version; }
b_bat()      { cargo_inst bat || return 1; }
b_eza()      { cargo_inst eza || return 1; }
b_zoxide()   { cargo_inst zoxide || return 1; }
b_starship() { cargo_inst starship || return 1; }
b_tsitter()  { cargo_inst tree-sitter-cli || return 1; tree-sitter --version; }
b_golang() {
  local j fn sha
  j=$(curl -fsSL 'https://go.dev/dl/?mode=json') || return 1
  read -r fn sha < <(python3 -c 'import sys,json; d=json.load(sys.stdin)[0]; f=[x for x in d["files"] if x["os"]=="linux" and x["arch"]=="amd64" and x["kind"]=="archive"][0]; print(f["filename"], f["sha256"])' <<<"$j") || return 1
  echo "  go -> $fn"
  fetch_one "$fn" "https://go.dev/dl/$fn" - || return 1
  echo "$sha  $SRC/$fn" | sha256sum -c - || return 1
  rm -rf /opt/go; tar -xzf "$SRC/$fn" -C /opt || return 1
  /opt/go/bin/go version
}
b_gum()      { go_inst github.com/charmbracelet/gum || return 1; }
b_fzf()      { go_inst github.com/junegunn/fzf || return 1; }
b_lazygit()  { go_inst github.com/jesseduffield/lazygit || return 1; }
b_neovim() {
  local QJ=$JOBS t; t=$(pin neovim github neovim/neovim latest v) || return 1; echo "  neovim -> $t"
  src_forge neovim github neovim/neovim "$t" || return 1
  make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX=/usr || return 1
  make install || return 1
  nvim --version | head -n1
  cd /; rm -rf "$BUILD/neovim"
}
b_fonts() {
  install -d /usr/share/fonts/JetBrainsMonoNerd /usr/share/fonts/NotoEmoji /usr/share/fonts/DejaVu
  tar -xf "$SRC/JetBrainsMono.tar.xz" -C /usr/share/fonts/JetBrainsMonoNerd --wildcards '*.ttf' || return 1
  install -m644 "$SRC/NotoColorEmoji.ttf" /usr/share/fonts/NotoEmoji/
  local d=$BUILD/dejavu; rm -rf "$d"; mkdir -p "$d"; tar -xf "$SRC/dejavu-fonts-ttf-2.37.tar.bz2" -C "$d" || return 1
  install -m644 "$d"/*/ttf/*.ttf /usr/share/fonts/DejaVu/; rm -rf "$d"
  fc-cache -f
  fc-list | grep -c 'JetBrainsMono Nerd' || true
}
b_payload() {
  [ -f "$BUNDLE" ] || { echo "missing $BUNDLE"; return 1; }
  rm -rf /usr/share/omarchy
  tar --no-same-owner --no-overwrite-dir -xzf "$BUNDLE" -C / usr || return 1
  chmod 0755 /usr/bin/omarchy* 2>/dev/null || true
  install -Dm644 /usr/share/omarchy/default/uwsm/env.d/10-omarchy /usr/share/uwsm/env.d/10-omarchy
  printf '%s\n' '# Omarchy env (OMARCHY_PATH + PATH)' '[ -r /usr/share/omarchy/default/bash/env-bootstrap ] && . /usr/share/omarchy/default/bash/env-bootstrap' > /etc/profile.d/omarchy.sh
  install -Dm644 /usr/share/omarchy/default/wayland-sessions/omarchy.desktop /usr/share/wayland-sessions/omarchy.desktop
  # Quickshell installs its QML modules outside Qt's own tree: tell Qt where they are
  local q; q=$(find /usr/lib /usr/lib64 -type d -name Quickshell -path '*qml*' 2>/dev/null | head -n1 || true)
  if [ -n "$q" ]; then
    q=$(dirname "$q"); echo "  Quickshell QML modules in $q"
    printf '%s\n' "# Quickshell QML modules" "export QML_IMPORT_PATH=$q\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}" "export QML2_IMPORT_PATH=\$QML_IMPORT_PATH" > /etc/profile.d/quickshell-qml.sh
  else
    echo "  WARNING: could not find Quickshell's QML module dir"
  fi
  ls /usr/bin/omarchy* | wc -l
}
b_userconf() {
  local ov; ov=$(mktemp -d); tar -xzf "$BUNDLE" -C "$ov" overrides skel || return 1
  mkdir -p "$JH/.config" "$JH/.local/state/omarchy" "$JH/.local/share" "$JH/.local/bin" "$JH/.cache"
  cp -rn "$ov/skel/.config/." "$JH/.config/"
  cp -rn /usr/share/omarchy/config/. "$JH/.config/"
  # VM-specific overrides always win over Mother's copies
  install -Dm644 "$ov/overrides/monitors.lua"        "$JH/.config/hypr/monitors.lua"
  install -Dm644 "$ov/overrides/uwsm-env"            "$JH/.config/uwsm/env"
  install -Dm644 "$ov/overrides/xdg-terminals.list"  "$JH/.config/xdg-terminals.list"
  [ ! -f "$JH/.bashrc" ] || [ -f "$JH/.bashrc.jjlinux" ] || cp "$JH/.bashrc" "$JH/.bashrc.jjlinux"
  install -m644 "$ov/overrides/dot.bashrc"   "$JH/.bashrc"
  [ ! -f "$JH/.bash_profile" ] || [ -f "$JH/.bash_profile.jjlinux" ] || cp "$JH/.bash_profile" "$JH/.bash_profile.jjlinux"
  install -m644 "$ov/overrides/bash_profile" "$JH/.bash_profile"
  install -Dm644 "$ov/overrides/dot.bashrc" /etc/skel/.bashrc
  chown -R "$JU:$(id -gn "$JU")" "$JH/.config" "$JH/.local" "$JH/.cache" "$JH/.bashrc" "$JH/.bash_profile"
  rm -rf "$ov"
  ls "$JH/.config" | tr '\n' ' '; echo
}
b_theme() {
  as_user 'OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "Tokyo Night"' || return 1
  as_user 'ls ~/.local/state/omarchy/current/theme/ | tr "\n" " "; echo; cat ~/.local/state/omarchy/current/theme.name' || true
}
b_lazyvim() {
  as_user 'TERM=xterm-256color timeout 1500 nvim --headless "+Lazy! sync" +qa' || return 1
  as_user 'ls ~/.local/share/nvim/lazy | wc -l'
}
b_units() {
  local u
  for u in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    systemctl --global enable "$u" 2>&1 | tail -n1 || true
  done
  return 0
}
b_o_btop() { b_try b_btop; }
b_o_fastfetch() { b_try b_fastfetch; }
b_o_brightnessctl() { b_try b_brightnessctl; }
b_o_bat() { b_try b_bat; }
b_o_eza() { b_try b_eza; }
b_o_zoxide() { b_try b_zoxide; }
b_o_starship() { b_try b_starship; }
b_o_tsitter() { b_try b_tsitter; }
b_o_golang() { b_try b_golang; }
b_o_gum() { b_try b_gum; }
b_o_fzf() { b_try b_fzf; }
b_o_lazygit() { b_try b_lazygit; }
b_o_theme() { b_try b_theme; }
b_o_lazyvim() { b_try b_lazyvim; }

hint_neovim()  { echo "      (builds LuaJIT + friends first, ~5 min)"; }
hint_lazyvim() { echo "      (git-clones ~40 plugins, ~3 min; treesitter parsers compile on first nvim use)"; }

step jq          b_jq
step libevent    b_libevent
step tmux        b_tmux
step btop        b_o_btop
step fastfetch   b_o_fastfetch
step brightnessctl b_o_brightnessctl
step rg          b_rg
step fd          b_fd
step bat         b_o_bat
step eza         b_o_eza
step zoxide      b_o_zoxide
step starship    b_o_starship
step golang      b_o_golang
step gum         b_o_gum
step fzf         b_o_fzf
step lazygit     b_o_lazygit
step tsitter     b_o_tsitter
step neovim      b_neovim
step fonts       b_fonts
step payload     b_payload
step userconf    b_userconf
step theme       b_o_theme
step lazyvim     b_o_lazyvim
step units       b_units


# ------------------------------------------------------------------ verification (non-fatal)
echo
echo "=== verification ==="
setpath
ok=0; bad=0
for t in jq tmux nvim rg fd bat eza zoxide starship gum fzf lazygit btop fastfetch brightnessctl tree-sitter; do
  chk "tool:$t" sh -c "command -v $t >/dev/null && echo present"
done
chk omarchy-bin   sh -c 'ls /usr/bin/omarchy* | wc -l'
chk omarchy-path  sh -c 'ls -d /usr/share/omarchy/shell/shell.qml /usr/share/omarchy/default/hypr/omarchy.lua'
chk uwsm-envd     sh -c 'ls /usr/share/uwsm/env.d/10-omarchy'
chk quickshell-qml sh -c 'cat /etc/profile.d/quickshell-qml.sh | tail -n1'
chk font-nerd     sh -c "fc-list | grep -c 'JetBrainsMono Nerd'"
chk font-emoji    sh -c "fc-list | grep -c 'Noto Color Emoji'"
chk user-hypr     sh -c "ls $JH/.config/hypr/hyprland.lua $JH/.config/hypr/monitors.lua"
chk user-nvim     sh -c "ls $JH/.config/nvim/init.lua"
chk theme-foot    sh -c "ls $JH/.local/state/omarchy/current/theme/foot.ini"
chk lazy-plugins  sh -c "ls $JH/.local/share/nvim/lazy | wc -l"
chk omarchy-env   su - "$JU" -c 'echo OMARCHY_PATH=$OMARCHY_PATH; command -v omarchy-menu'
chk hypr-config   su - "$JU" -c 'Hyprland --verify-config -c ~/.config/hypr/hyprland.lua 2>&1 | tail -n 3'
chk uwsm-can-start su - "$JU" -c 'uwsm check may-start >/dev/null 2>&1 && echo yes || echo "no (expected over ssh - needs tty1)"'
echo
if [ -s "$STATE/c5-optional-failed.txt" ]; then
  echo "optional steps that failed (the desktop does not need them):"; sort -u "$STATE/c5-optional-failed.txt" | sed 's/^/   /'
fi
rm -rf "$BUILD/cargo-home" "$BUILD/gopath" "$BUILD/gocache" 2>/dev/null || true
if [ "$bad" = 0 ]; then
  echo "=== BLFS stage C6 DONE in $(( (SECONDS - T_ALL) / 60 )) min  ($ok checks passed) ==="
else
  echo "=== stage C6 built but $bad check(s) FAILED ($ok passed) -- paste the FAIL lines to me ==="
fi
cat << 'MSG'

Snapshot first (VM off):  virsh -c qemu:///system snapshot-create-as LFS-13.1 v0.9-omarchy
Then on the VM CONSOLE (not ssh): log in as jj on tty1.  It now starts Omarchy by itself (bash_profile -> uwsm -> Hyprland).
If it dumps you back to a prompt:   touch ~/.no-autostart   (turns autostart off), then paste:
    journalctl --user -b --no-pager | tail -n 60
    journalctl -t omarchy-shell --no-pager | tail -n 40
MSG
