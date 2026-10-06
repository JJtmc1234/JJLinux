#!/bin/bash
# JJLinux v0.1.1 - runs ON JJLinux as root (the Nexus driver does: sudo bash /sources/jjlinux-v011.sh)
#  1. less reinstalled as the normal build (book order installs the LESSTEST build)      -> JPM id less-704-r1
#  2. emergency mode never asks for a password, remounts / rw                           -> JPM id emergency-nopasswd-1
#  3. grub.cfg: emergency entry boots rw + new last-resort entry init=/bin/bash          -> JPM id grub-cfg-v011
. /sources/jpm-track.sh

p_less_r1() {
  ./configure --prefix=/usr --sysconfdir=/etc
  make
  chk make check
  # less 704's "make check" rebuilds less with LESSTEST=1; rebuild the normal binary before installing
  make clean
  make
  make install
}

c_emergency() {
  install -vdm755 /etc/systemd/system/emergency.service.d
  cat > /etc/systemd/system/emergency.service.d/10-jjlinux-nopasswd.conf << "EOF"
# JJLinux: emergency mode never asks for a password (like init=/bin/bash, but with systemd)
[Service]
ExecStartPre=-/usr/bin/mount -o remount,rw /
ExecStart=
ExecStart=-/bin/sh -c '/bin/bash --login; /usr/bin/systemctl --job-mode=fail --no-block default'
EOF
  systemctl daemon-reload
}

c_grub() {
  G=/boot/grub/grub.cfg
  cp -v $G $G.pre-v011
  sed -i 's| ro systemd.unit=emergency.target| rw systemd.unit=emergency.target|' $G
  if ! grep -q 'init=/bin/bash' $G; then
    L=$(grep 'systemd.unit=emergency.target' $G | sed 's| systemd.unit=emergency.target| init=/bin/bash|')
    sed -i "/^# End \/boot\/grub\/grub.cfg/i menuentry \"JJLinux - shell (init=/bin/bash, last resort)\" {\n$L\n}" $G
  fi
}

track 8.45     less-704-r1          less-704.tar.gz  less-704  p_less_r1
track jjlinux  emergency-nopasswd-1 -                -         c_emergency
track jjlinux  grub-cfg-v011        -                -         c_grub

echo "=== checks"
less -V | head -1
less -V | grep -q LESSTEST && echo "!!! less is still the LESSTEST build" || echo "less: normal build"
systemctl cat emergency.service | tail -6
systemctl show -p LoadState --value emergency.target emergency.service | tr '\n' ' '; echo "(must not say masked)"
grep -n -e menuentry -e '        linux' /boot/grub/grub.cfg
echo "=== v0.1.1 INSTALLED"
