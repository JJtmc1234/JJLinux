#!/bin/bash
# JJLinux -- rebuild OpenSSH 10.5p1 with PAM so ssh logins get logind sessions (XDG_RUNTIME_DIR, systemd --user).
# Run in the VM as root:  sudo bash ssh-pam.sh      (keep your current ssh session open until a NEW login works)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)"; exit 1; }
VER=10.5p1; TAR=openssh-$VER.tar.gz; MD5=a95119f402dfa0166c9dd1237239085c
[ -f /usr/lib/libpam.so ] || { echo "Linux-PAM is not installed - finish stage C1 first"; exit 1; }
W=$(mktemp -d /var/tmp/ssh-pam.XXXXXX); cd "$W"
echo "=== download ==="
curl -fL --retry 3 -sS -o "$TAR" "https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/$TAR" \
  || curl -fL --retry 3 -sS -o "$TAR" "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/$TAR"
echo "$MD5  $TAR" | md5sum -c -
tar -xf "$TAR"; cd "openssh-$VER"
echo "=== build (with PAM) ==="
./configure --prefix=/usr --sysconfdir=/etc/ssh --with-privsep-path=/var/lib/sshd \
            --with-default-path=/usr/bin --with-superuser-path=/usr/sbin:/usr/bin \
            --with-pid-dir=/run --with-pam > "$W/configure.log" 2>&1 \
  || { tail -n 20 "$W/configure.log"; exit 1; }
make -j"$(nproc)" > "$W/make.log" 2>&1 || { tail -n 20 "$W/make.log"; exit 1; }
make install > "$W/install.log" 2>&1
echo "=== PAM config ==="
sed 's@d/login@d/sshd@g' /etc/pam.d/login > /etc/pam.d/sshd
chmod 644 /etc/pam.d/sshd
grep -q '^UsePAM' /etc/ssh/sshd_config || echo "UsePAM yes" >> /etc/ssh/sshd_config
/usr/sbin/sshd -t
ldd /usr/sbin/sshd | grep -q libpam || { echo "sshd still has no libpam!"; exit 1; }
echo "=== restart sshd (your current session stays alive) ==="
systemctl restart sshd
sleep 2
systemctl is-active sshd
cd /; rm -rf "$W"
echo
echo "DONE. Now open a NEW ssh session from mother (ssh jl2) and run:  loginctl --no-pager list-sessions; echo \$XDG_RUNTIME_DIR"
echo "You want a session for jj and /run/user/1000. If login is refused, use the VM console and tell me."
