#!/bin/bash
# JJLinux - BLFS 13.1-systemd: OpenSSH-10.5p1 + sshd unit, plus user 'jj' with key-only SSH login.
# Run INSIDE the chroot as root:   bash /sources/blfs-openssh.sh
# Needs in /sources: openssh-10.5p1.tar.gz, blfs-systemd-units-20251204.tar.xz, jj.authorized_keys
. /sources/jpm-track.sh

[ -s /sources/jj.authorized_keys ] || die "missing /sources/jj.authorized_keys"

p_openssh() {
  install -v -g sys -m700 -d /var/lib/sshd
  getent group sshd  >/dev/null || groupadd -g 50 sshd
  getent passwd sshd >/dev/null || useradd -c 'sshd PrivSep' \
         -d /var/lib/sshd  \
         -g sshd           \
         -s /bin/false     \
         -u 50 sshd
  ./configure --prefix=/usr                            \
              --sysconfdir=/etc/ssh                    \
              --with-privsep-path=/var/lib/sshd        \
              --with-default-path=/usr/bin             \
              --with-superuser-path=/usr/sbin:/usr/bin \
              --with-pid-dir=/run
  make
  make install
  install -v -m755    contrib/ssh-copy-id /usr/bin
  install -v -m644    contrib/ssh-copy-id.1 \
                      /usr/share/man/man1
  install -v -m755 -d /usr/share/doc/openssh-10.5p1
  install -v -m644    INSTALL LICENCE OVERVIEW README* \
                      /usr/share/doc/openssh-10.5p1
  # BLFS recommended hardening: no root login, keys only
  echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
  echo "KbdInteractiveAuthentication no" >> /etc/ssh/sshd_config
}

p_sshdunit() {
  # BLFS keeps this source tree around; we keep a copy in /usr/src for later units
  make install-sshd
  rm -rf /usr/src/blfs-systemd-units-20251204
  cp -a . /usr/src/blfs-systemd-units-20251204
}

c_user() {
  # v0.1 needs a non-root user; key-only SSH login, same key as the Debian build host
  getent passwd jj >/dev/null || useradd -m -G wheel,users -s /bin/bash jj
  # useradd leaves the account locked ('!'); OpenSSH without PAM rejects even key logins for locked accounts
  usermod -p '*' jj
  install -v -d -m700 -o jj -g jj /home/jj/.ssh
  install -v -m600 -o jj -g jj /sources/jj.authorized_keys /home/jj/.ssh/authorized_keys
  # quiet console (JJLinux deviation): only errors reach the screen
  echo 'kernel.printk = 3 4 1 3' > /etc/sysctl.d/10-console-loglevel.conf
}

track blfs openssh-10.5p1             openssh-10.5p1.tar.gz              openssh-10.5p1             p_openssh
track blfs blfs-systemd-units-20251204 blfs-systemd-units-20251204.tar.xz blfs-systemd-units-20251204 p_sshdunit
c_user
systemctl is-enabled sshd && echo "=== sshd enabled"
id jj; ls -l /home/jj/.ssh/authorized_keys
echo ">>> OpenSSH ready. Leave chroot, unmount, boot JJLinux, then: ssh jjlinux"
