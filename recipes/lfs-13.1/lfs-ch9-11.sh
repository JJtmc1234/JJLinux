#!/bin/bash
# JJLinux - LFS 13.1-systemd Chapters 9, 10, 11 (config, fstab, kernel, GRUB, release files).
# Run INSIDE the chroot as root, AFTER 'passwd root':   bash /sources/lfs-ch9-11.sh
# The kernel is tracked by JPM. Its config is also saved as a defconfig for git.
. /sources/jpm-track.sh
set -e

# ---------- identify our own partitions (by partition label, never sdX) ----------
P=/dev/disk/by-partlabel
for l in lfs-esp lfs-swap lfs-root; do [ -b $P/$l ] || die "missing $P/$l"; done
ROOT_PARTUUID=$(blkid -s PARTUUID -o value $P/lfs-root)
ROOT_FSUUID=$(blkid -s UUID -o value $P/lfs-root)
SWAP_UUID=$(blkid -s UUID -o value $P/lfs-swap)
ESP_UUID=$(blkid -s UUID -o value $P/lfs-esp)
echo "root PARTUUID=$ROOT_PARTUUID fsUUID=$ROOT_FSUUID swap=$SWAP_UUID esp=$ESP_UUID"
[ "$ROOT_FSUUID" = 98237595-85ef-4456-9093-30353d204ea4 ] || die "root fs UUID mismatch - wrong disk?"

c_ch9() {
  # 9.2.1.3 DHCP (JJLinux: match any wired 'en*' NIC instead of one hard-coded name)
  cat > /etc/systemd/network/10-eth-dhcp.network << "EOF"
[Match]
Name=en*

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF
  # 9.2.2.1 systemd-resolved creates /etc/resolv.conf at boot; nothing to do
  # 9.2.3 hostname
  echo "jjlinux" > /etc/hostname
  # 9.2.4 hosts (DHCP: the address line is omitted, per the book)
  cat > /etc/hosts << "EOF"
# Begin /etc/hosts

::1       ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters

# End /etc/hosts
EOF
  # 9.5 clock: the VM's RTC is UTC, so no /etc/adjtime (systemd assumes UTC)
  # 9.6 console
  echo FONT=Lat2-Terminus16 > /etc/vconsole.conf
  # 9.7 locale
  cat > /etc/locale.conf << "EOF"
LANG=en_US.UTF-8
EOF
  cat > /etc/profile << "EOF"
# Begin /etc/profile

for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  source /etc/locale.conf

  for i in $(locale); do
    key=${i%=*}
    if [[ -v $key ]]; then
       export $key
    fi
  done
fi

# End /etc/profile
EOF
  # 9.8 inputrc
  cat > /etc/inputrc << "EOF"
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line

# End /etc/inputrc
EOF
  # 9.9 shells
  cat > /etc/shells << "EOF"
# Begin /etc/shells

/bin/sh
/bin/bash

# End /etc/shells
EOF
  # 9.10.2 keep boot messages on screen (useful while debugging first boots)
  mkdir -pv /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf << EOF
[Service]
TTYVTDisallocate=no
EOF
  # 10.2 fstab (PARTUUID/UUID per the book's notes, so sdX renames can't break boot)
  cat > /etc/fstab << EOF
# Begin /etc/fstab

# file system                               mount-point  type   options                                     dump  fsck
PARTUUID=$ROOT_PARTUUID  /            ext4   defaults                                    1     1
UUID=$SWAP_UUID       swap         swap   pri=1                                       0     0
UUID=$ESP_UUID                              /boot/efi    vfat   rw,relatime,codepage=437,iocharset=iso8859-1 0    2

# End /etc/fstab
EOF
  # 11.1 release files (JJLinux branding; the LFS version stays recorded)
  echo 13.1-systemd > /etc/lfs-release
  cat > /etc/lsb-release << "EOF"
DISTRIB_ID="JJLinux"
DISTRIB_RELEASE="0.1-dev"
DISTRIB_CODENAME="agentic"
DISTRIB_DESCRIPTION="JJLinux 0.1-dev (based on Linux From Scratch 13.1-systemd)"
EOF
  cat > /etc/os-release << "EOF"
NAME="JJLinux"
VERSION="0.1-dev"
ID=jjlinux
ID_LIKE=lfs
PRETTY_NAME="JJLinux 0.1-dev (LFS 13.1-systemd)"
VERSION_CODENAME="agentic"
HOME_URL="https://github.com/JJtmc1234/JJLinux"
RELEASE_TYPE="development"
EOF
}

# ---------- 10.3 kernel: defconfig + the book's required options, set non-interactively ----------
p_linux() {
  make mrproper
  make defconfig
  S=scripts/config
  $S --disable WERROR
  $S --enable PSI --disable PSI_DEFAULT_DISABLED
  $S --disable IKHEADERS
  $S --enable CGROUPS --enable MEMCG --enable CGROUP_SCHED --disable RT_GROUP_SCHED
  $S --disable EXPERT
  $S --enable RELOCATABLE --enable RANDOMIZE_BASE
  $S --enable STACKPROTECTOR --enable STACKPROTECTOR_STRONG
  $S --enable NET --enable INET --enable IPV6
  $S --disable UEVENT_HELPER --enable DEVTMPFS --enable DEVTMPFS_MOUNT
  $S --disable FW_LOADER_USER_HELPER
  $S --enable DMIID --enable SYSFB_SIMPLEFB
  $S --enable TTY --disable LEGACY_TIOCSTI
  $S --enable DRM --enable DRM_PANIC --set-str DRM_PANIC_SCREEN kmsg
  $S --enable DRM_FBDEV_EMULATION --enable DRM_SIMPLEDRM --enable FRAMEBUFFER_CONSOLE
  $S --enable INOTIFY_USER --enable TMPFS --enable TMPFS_POSIX_ACL
  # 64-bit extras (book): PCI_MSI, IRQ_REMAP, X86_X2APIC
  $S --enable PCI --enable PCI_MSI --enable IOMMU_SUPPORT --enable IRQ_REMAP --enable X86_X2APIC
  # UEFI (book)
  $S --enable EFI --enable EFI_STUB --enable EFI_PARTITION
  $S --enable VFAT_FS --enable EFIVAR_FS --enable NLS --enable NLS_CODEPAGE_437 --enable NLS_ISO8859_1
  # VirtualBox hardware for this VM: AHCI SATA disks, e1000 NIC
  $S --enable SATA_AHCI --enable E1000
  make olddefconfig
  # verify every required option actually stuck
  bad=0
  for o in PSI CGROUPS MEMCG CGROUP_SCHED RELOCATABLE RANDOMIZE_BASE STACKPROTECTOR STACKPROTECTOR_STRONG \
           NET INET IPV6 DEVTMPFS DEVTMPFS_MOUNT DMIID SYSFB_SIMPLEFB TTY DRM DRM_PANIC DRM_FBDEV_EMULATION \
           DRM_SIMPLEDRM FRAMEBUFFER_CONSOLE INOTIFY_USER TMPFS TMPFS_POSIX_ACL PCI_MSI IRQ_REMAP X86_X2APIC \
           EFI EFI_STUB EFI_PARTITION VFAT_FS EFIVAR_FS NLS_CODEPAGE_437 NLS_ISO8859_1 SATA_AHCI E1000 EXT4_FS; do
    grep -qE "^CONFIG_$o=(y|m)$" .config || { echo "KCONFIG MISSING: $o"; bad=1; }
  done
  for o in WERROR PSI_DEFAULT_DISABLED IKHEADERS RT_GROUP_SCHED EXPERT UEVENT_HELPER FW_LOADER_USER_HELPER LEGACY_TIOCSTI; do
    grep -qE "^CONFIG_$o=y$" .config && { echo "KCONFIG SHOULD BE OFF: $o"; bad=1; }
  done
  grep -q '^CONFIG_DRM_PANIC_SCREEN="kmsg"' .config || { echo "KCONFIG: DRM_PANIC_SCREEN not kmsg"; bad=1; }
  [ $bad = 0 ] || exit 1
  echo "=== kernel config verified"
  make
  make modules_install
  cp -iv arch/x86/boot/bzImage /boot/vmlinuz-7.1.8-lfs-13.1-systemd
  cp -iv System.map /boot/System.map-7.1.8
  cp -iv .config /boot/config-7.1.8
  cp -r Documentation -T /usr/share/doc/linux-7.1.8
  make savedefconfig
  cp -v defconfig /sources/jjlinux-kernel-7.1.8.defconfig
}

# ---------- 10.4 GRUB (UEFI, removable path) ----------
# JJLinux rule: emergency boot NEVER asks for a password and is never disabled (root shell, / remounted rw)
c_emergency() {
  install -vdm755 /etc/systemd/system/emergency.service.d
  cat > /etc/systemd/system/emergency.service.d/10-jjlinux-nopasswd.conf << "EOF"
# JJLinux: emergency mode never asks for a password (like init=/bin/bash, but with systemd)
[Service]
ExecStartPre=-/usr/bin/mount -o remount,rw /
ExecStart=
ExecStart=-/bin/sh -c '/bin/bash --login; /usr/bin/systemctl --job-mode=fail --no-block default'
EOF
}

p_grubsetup() {
  mkdir -pv /boot/efi
  mountpoint -q /boot/efi || mount -v /boot/efi
  [ "$(findmnt -no SOURCE /boot/efi)" = "$(readlink -f $P/lfs-esp)" ] || { echo "ESP mounted from the wrong device"; exit 1; }
  grub-install --target=x86_64-efi --removable
  cat > /boot/grub/grub.cfg << EOF
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

# JJLinux: one-shot boot selection (used by grub-reboot)
if [ -s \$prefix/grubenv ]; then
  load_env
fi
if [ "\${next_entry}" ] ; then
   set default="\${next_entry}"
   set next_entry=
   save_env next_entry
fi

insmod part_gpt
insmod ext2
search --set=root --fs-uuid $ROOT_FSUUID

set gfxpayload=1024x768x32

menuentry "JJLinux 0.1-dev (Linux 7.1.8, LFS 13.1-systemd)" {
        linux   /boot/vmlinuz-7.1.8-lfs-13.1-systemd root=PARTUUID=$ROOT_PARTUUID ro
}
menuentry "JJLinux - rescue (rescue.target)" {
        linux   /boot/vmlinuz-7.1.8-lfs-13.1-systemd root=PARTUUID=$ROOT_PARTUUID ro systemd.unit=rescue.target
}
menuentry "JJLinux - emergency (emergency.target)" {
        linux   /boot/vmlinuz-7.1.8-lfs-13.1-systemd root=PARTUUID=$ROOT_PARTUUID rw systemd.unit=emergency.target
}
menuentry "JJLinux - shell (init=/bin/bash, last resort)" {
        linux   /boot/vmlinuz-7.1.8-lfs-13.1-systemd root=PARTUUID=$ROOT_PARTUUID rw init=/bin/bash
}
# End /boot/grub/grub.cfg
EOF
  ls -l /boot/efi/EFI/BOOT/
}

echo "=== Chapter 9 + fstab + release files"; c_ch9; c_emergency
cat /etc/fstab
set +e
track 10.03 linux-7.1.8    linux-7.1.8.tar.xz  linux-7.1.8  p_linux
track 10.04 grub-setup-13.1 -                  -            p_grubsetup
echo "=== CH 9-11 DONE"
grep -q '^root:[^!*:][^:]*:' /etc/shadow && echo "root password: set" || echo "!!! root password NOT set - run: passwd root"
echo ">>> NEXT: leave the chroot, unmount, and boot the LFS disk"
