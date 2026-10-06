#!/bin/bash
# JJLinux - BLFS 13.1-systemd: Sudo-1.9.17p2 (tracked by JPM). Run on JJLinux as root:
#   su - -c 'bash /sources/blfs-sudo.sh'
. /sources/jpm-track.sh

p_sudo() {
  sed -e 's/\([->.a-zA-Z_]*\)->length/ASN1_STRING_length(\1)/' \
      -i lib/iolog/hostcheck.c
  ./configure --prefix=/usr         \
              --libexecdir=/usr/lib \
              --with-secure-path    \
              --with-env-editor     \
              --docdir=/usr/share/doc/sudo-1.9.17p2 \
              --with-passprompt="[sudo] password for %p: "
  make
  env LC_ALL=C make check |& tee make-check.log
  grep failed make-check.log || true
  make install
  cat > /etc/sudoers.d/00-sudo << "EOT"
Defaults secure_path="/usr/sbin:/usr/bin"
%wheel ALL=(ALL) ALL
EOT
  # JJLinux dev VM: jj has key-only login (no password), so sudo must not ask for one
  echo 'jj ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-jj-nopasswd
  chmod 440 /etc/sudoers.d/00-sudo /etc/sudoers.d/10-jj-nopasswd
  visudo -c
}

track blfs sudo-1.9.17p2 sudo-1.9.17p2.tar.gz sudo-1.9.17p2 p_sudo
