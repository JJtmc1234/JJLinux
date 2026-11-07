#!/bin/bash
# JJLinux -- BLFS stage C1: Linux-PAM, Shadow with PAM, systemd rebuilt with PAM (logind sessions), seatd with logind.
# This is the one RISKY stage: it changes how logins work. A wrong PAM config can lock you out of the console.
#
#   BEFORE YOU RUN IT -- on mother, with the VM shut off:
#       virsh -c qemu:///system snapshot-create-as LFS-13.1 pre-pam
#   Then (VM, as root):   bash blfs-c1-pam.sh
#   AFTER it finishes, KEEP your current ssh session open, open a second terminal and test:
#       ssh jl2   then   su -         (must ask for the root password and accept it)
#       and log in as jj on the VM console:   virsh -c qemu:///system console LFS-13.1
#   Only when both work, reboot the VM (systemctl reboot).  If anything fails: restore the snapshot.
#
# Versions/commands: BLFS 13.1-systemd (Linux-PAM 1.7.2, Shadow 4.20.2, Systemd 261.2). Resumable; logs in /var/log/blfs-c/.
set -euo pipefail

# ------------------------------------------------------------------ common settings
JJ_STAGE=c1
TOTAL=4
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
echo "JJLinux stage C1 (PAM + logind core) | RAM ${RAM_GB} GB, $NP CPUs -> $JOBS parallel jobs"

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
getent passwd jj >/dev/null || { echo "  user jj not found"; pf_fail=1; }
[ -s /home/jj/.ssh/authorized_keys ] || echo "  note: jj has no ssh key - ssh login stays password-less only if you set one up"
[ -f /etc/shadow ] || { echo "  /etc/shadow missing"; pf_fail=1; }
mkdir -p /root/pam-backup
cp -an /etc/login.defs /etc/passwd /etc/shadow /etc/group /etc/default /etc/pam.d /root/pam-backup/ 2>/dev/null || true
echo "  backup of login files: /root/pam-backup"
[ "$pf_fail" = 0 ] || { echo "Preflight failed - fix the above and re-run."; exit 1; }
echo "  ok (${FREE_GB} GB free)"

# ------------------------------------------------------------------ sources
# file|url[,mirror...]|md5   (md5 '-' = no published checksum; we sanity-check the archive and log our own md5)
cat > "$SRC/list-$JJ_STAGE.txt" << 'LISTEOF'
Linux-PAM-1.7.2.tar.xz|https://github.com/linux-pam/linux-pam/releases/download/v1.7.2/Linux-PAM-1.7.2.tar.xz|934c26eca3fada956356a30489e86291
shadow-4.20.2.tar.xz|https://github.com/shadow-maint/shadow/releases/download/4.20.2/shadow-4.20.2.tar.xz|f52e717bd330818c67bd57c897ec5a8e
systemd-261.2.tar.gz|https://github.com/systemd/systemd/archive/v261.2/systemd-261.2.tar.gz|e3f04ccc83a28ec5e80c5432bb8329f5
seatd-0.9.3.tar.gz|https://github.com/kennylevinsen/seatd/archive/0.9.3/seatd-0.9.3.tar.gz|c1cc200188d31214b88af015b1f19f7b
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
b_linuxpam() {
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release -D docs=disabled -D docdir=/usr/share/doc/Linux-PAM-1.7.2
  ninja
  ninja install
  chmod -v 4755 /usr/sbin/unix_chkpwd

  install -vdm755 /etc/pam.d
  cat > /etc/pam.d/system-account << "EOF"
# Begin /etc/pam.d/system-account

account   required    pam_unix.so

# End /etc/pam.d/system-account
EOF

  cat > /etc/pam.d/system-auth << "EOF"
# Begin /etc/pam.d/system-auth

auth      required    pam_unix.so

# End /etc/pam.d/system-auth
EOF

  cat > /etc/pam.d/system-session << "EOF"
# Begin /etc/pam.d/system-session

session   required    pam_unix.so

# End /etc/pam.d/system-session
EOF

  cat > /etc/pam.d/system-password << "EOF"
# Begin /etc/pam.d/system-password

# use yescrypt hash for encryption, use shadow, and try to use any
# previously defined authentication token (chosen password) set by any
# prior module.
password  required    pam_unix.so       yescrypt shadow try_first_pass

# End /etc/pam.d/system-password
EOF

  # restrictive default: PAM-aware programs without their own file are refused
  cat > /etc/pam.d/other << "EOF"
# Begin /etc/pam.d/other

auth        required        pam_warn.so
auth        required        pam_deny.so
account     required        pam_warn.so
account     required        pam_deny.so
password    required        pam_warn.so
password    required        pam_deny.so
session     required        pam_warn.so
session     required        pam_deny.so

# End /etc/pam.d/other
EOF
  ls -l /usr/lib/security/pam_unix.so /usr/sbin/unix_chkpwd
}

b_shadow() {
  # reinstall Shadow so login/su/passwd/useradd... speak PAM
  find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
  find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
  sed -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD YESCRYPT@' \
      -e 's@/var/spool/mail@/var/mail@'                   \
      -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
      -i etc/login.defs
  ./configure --sysconfdir=/etc   \
              --disable-static    \
              --without-libbsd    \
              --with-{b,yes}crypt
  make
  make exec_prefix=/usr pamddir= install
  make -C man install-man

  # login.defs: let PAM modules do what login used to do
  [ -f /etc/login.defs.orig ] || install -v -m644 /etc/login.defs /etc/login.defs.orig
  for FUNCTION in FAIL_DELAY               \
                  FAILLOG_ENAB             \
                  LASTLOG_ENAB             \
                  MAIL_CHECK_ENAB          \
                  OBSCURE_CHECKS_ENAB      \
                  PORTTIME_CHECKS_ENAB     \
                  QUOTAS_ENAB              \
                  CONSOLE MOTD_FILE        \
                  FTMP_FILE NOLOGINS_FILE  \
                  ENV_HZ PASS_MIN_LEN      \
                  SU_WHEEL_ONLY            \
                  PASS_CHANGE_TRIES        \
                  PASS_ALWAYS_WARN         \
                  CHFN_AUTH ENCRYPT_METHOD \
                  ENVIRON_FILE
  do
      sed -i "s/^${FUNCTION}/# &/" /etc/login.defs
  done

  cat > /etc/pam.d/login << "EOF"
# Begin /etc/pam.d/login

# Set failure delay before next prompt to 3 seconds
auth      optional    pam_faildelay.so  delay=3000000

# Check to make sure that the user is allowed to login
auth      requisite   pam_nologin.so

# Check to make sure that root is allowed to login
# Disabled by default. You will need to create /etc/securetty
# file for this module to function. See man 5 securetty.
#auth      required    pam_securetty.so

# Additional group memberships - disabled by default
#auth      optional    pam_group.so

# include system auth settings
auth      include     system-auth

# check access for the user
account   required    pam_access.so

# include system account settings
account   include     system-account

# Set default environment variables for the user
session   required    pam_env.so

# Set resource limits for the user
session   required    pam_limits.so

# Display the message of the day - Disabled by default
#session   optional    pam_motd.so

# Check user's mail - Disabled by default
#session   optional    pam_mail.so      standard quiet

# include system session and password settings
session   include     system-session
password  include     system-password

# End /etc/pam.d/login
EOF

  cat > /etc/pam.d/passwd << "EOF"
# Begin /etc/pam.d/passwd

password  include     system-password

# End /etc/pam.d/passwd
EOF

  cat > /etc/pam.d/su << "EOF"
# Begin /etc/pam.d/su

# always allow root
auth      sufficient  pam_rootok.so

# Allow users in the wheel group to execute su without a password
# disabled by default
#auth      sufficient  pam_wheel.so trust use_uid

# include system auth settings
auth      include     system-auth

# limit su to users in the wheel group
# disabled by default
#auth      required    pam_wheel.so use_uid

# include system account settings
account   include     system-account

# Set default environment variables for the service user
session   required    pam_env.so

# include system session settings
session   include     system-session

# End /etc/pam.d/su
EOF

  cat > /etc/pam.d/chpasswd << "EOF"
# Begin /etc/pam.d/chpasswd

# always allow root
auth      sufficient  pam_rootok.so

# include system auth and account settings
auth      include     system-auth
account   include     system-account
password  include     system-password

# End /etc/pam.d/chpasswd
EOF
  sed -e s/chpasswd/newusers/ /etc/pam.d/chpasswd > /etc/pam.d/newusers

  cat > /etc/pam.d/chage << "EOF"
# Begin /etc/pam.d/chage

# always allow root
auth      sufficient  pam_rootok.so

# include system auth and account settings
auth      include     system-auth
account   include     system-account

# End /etc/pam.d/chage
EOF

  for PROGRAM in chfn chgpasswd chsh groupadd groupdel \
                 groupmems groupmod useradd userdel usermod
  do
      install -v -m644 /etc/pam.d/chage /etc/pam.d/${PROGRAM}
      sed -i "s/chage/$PROGRAM/" /etc/pam.d/${PROGRAM}
  done

  # PAM replaces login.access / limits
  if [ -f /etc/login.access ]; then mv -v /etc/login.access{,.NOUSE}; fi
  if [ -f /etc/limits ]; then mv -v /etc/limits{,.NOUSE}; fi

  # safety checks before we touch systemd
  ldd /usr/bin/login | grep -q libpam || { echo "login is not linked with PAM!"; false; }
  ldd /usr/bin/su    | grep -q libpam || { echo "su is not linked with PAM!"; false; }
  su -s /bin/true jj && echo "su (root -> jj) through PAM works"
}

b_systemd() {
  rm -fv /usr/lib/systemd/system/systemd-update-utmp-runlevel.service
  sed -i -e 's/GROUP="render"/GROUP="video"/' \
         -e 's/GROUP="sgx", //' rules.d/50-udev-default.rules.in
  mkdir -p build; cd build
  meson setup ..                 \
        --prefix=/usr            \
        --buildtype=release      \
        -D default-dnssec=no     \
        -D firstboot=false       \
        -D install-tests=false   \
        -D ldconfig=false        \
        -D sysusers=false        \
        -D rpmmacrosdir=no       \
        -D homed=disabled        \
        -D man=disabled          \
        -D mode=release          \
        -D pam=enabled           \
        -D pamconfdir=/etc/pam.d \
        -D dev-kvm-mode=0660     \
        -D nobody-group=nogroup  \
        -D sysupdate=disabled    \
        -D ukify=disabled        \
        -D docdir=/usr/share/doc/systemd-261.2
  ninja
  ninja install

  ls -l /usr/lib/security/pam_systemd.so

  # logind needs these PAM lines (BLFS)
  grep -q pam_systemd /etc/pam.d/system-session || cat >> /etc/pam.d/system-session << "EOF"
# Begin Systemd addition

session  required    pam_loginuid.so
session  optional    pam_systemd.so

# End Systemd addition
EOF

  cat > /etc/pam.d/systemd-user << "EOF"
# Begin /etc/pam.d/systemd-user

account  required    pam_access.so
account  include     system-account

session  required    pam_env.so
session  required    pam_limits.so
session  required    pam_loginuid.so
session  optional    pam_keyinit.so force revoke
session  optional    pam_systemd.so

auth     required    pam_deny.so
password required    pam_deny.so

# End /etc/pam.d/systemd-user
EOF

  # user services (the desktop runs as systemd --user units) get the /etc/profile.d environment
  install -vdm755 /etc/systemd/user-environment-generators
  cat > /etc/systemd/user-environment-generators/50-profile.sh << "EOF"
#!/usr/bin/env -S -i /usr/bin/bash
# SPDX-License-Identifier: MIT

. /etc/profile

# Systemd should have already set a better value for them.
unset XDG_RUNTIME_DIR
for i in $(locale); do
  unset ${i%=*}
done

# Some shell magic that we don't want to expose.
unset SHLVL

# Systemd does not want to pass functions to the environment
for i in $(declare -pF | awk '{print $3}'); do
  unset -f $i
done

python3 << _EOF
import os
for var in os.environ:
  # Simply unsetting them in shell does not work.
  if var in ['LC_CTYPE', '_']:
    continue

  print(var + '=' + os.environ[var])
_EOF
EOF
  chmod -v 755 /etc/systemd/user-environment-generators/50-profile.sh

  # swap the running PID 1 for the new binary
  systemctl daemon-reexec
  sleep 2
  systemctl is-system-running || true
}

b_seatd2() {
  # seatd again, now that logind exists: libseat can use logind sessions OR the seatd daemon
  mkdir build; cd build
  meson setup .. --prefix=/usr --buildtype=release \
    -D server=enabled -D libseat-logind=systemd
  ninja
  ninja install
  systemctl restart seatd.service || true
  systemctl is-active seatd.service
}

pkg linuxpam  Linux-PAM-1.7.2.tar.xz   b_linuxpam
pkg shadow    shadow-4.20.2.tar.xz     b_shadow
pkg systemd   systemd-261.2.tar.gz     b_systemd
pkg seatd2    seatd-0.9.3.tar.gz       b_seatd2


# ------------------------------------------------------------------ verification (non-fatal)
echo
echo "=== verification ==="
setpath
ok=0; bad=0
chk login-uses-pam   sh -c 'ldd /usr/bin/login | grep -o "libpam[^ ]*" | head -n1'
chk su-uses-pam      sh -c 'ldd /usr/bin/su | grep -o "libpam[^ ]*" | head -n1'
chk pam_systemd.so   sh -c 'ls /usr/lib/security/pam_systemd.so'
chk system-session   sh -c 'grep -c pam_systemd /etc/pam.d/system-session'
chk pid1             sh -c 'systemctl is-system-running; true'
chk logind           sh -c 'systemctl is-active systemd-logind.service'
chk root-to-jj       sh -c 'su -s /bin/true jj && echo ok'
chk seatd            sh -c 'systemctl is-active seatd.service'
echo
if [ "$bad" = 0 ]; then
  echo "=== BLFS stage C1 DONE in $(( (SECONDS - T_ALL) / 60 )) min  ($ok checks passed) ==="
else
  echo "=== stage C1 built but $bad check(s) FAILED ($ok passed) -- paste the FAIL lines to me, DON'T reboot yet ==="
fi
cat << 'MSG'

NOW TEST BEFORE YOU REBOOT (keep this session open):
  1. second terminal on mother:    ssh jl2      then      su -        <- must accept the root password
  2. VM console on mother:         virsh -c qemu:///system console LFS-13.1
     press Enter, log in as jj with its password (Ctrl+] leaves the console)
  3. in the VM:  loginctl list-sessions     (your ssh session may show up after the reboot)
Both work -> reboot with:  systemctl reboot       Anything fails -> tell me before closing sessions.
Backup of the old login files: /root/pam-backup     Snapshot to roll back to: pre-pam
MSG
