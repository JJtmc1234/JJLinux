#!/bin/bash
# JJLinux - LFS 13.1-systemd: 7.2 (with --chown), 7.3 mounts (idempotent), 7.4 enter chroot.
# Run as root on the Debian host:   bash lfs-chroot.sh --chown   (first time only)
#                                   bash lfs-chroot.sh           (every re-entry, e.g. after a reboot)
set -e
die() { echo "!!! STOP: $*"; exit 1; }
[ "$(id -u)" = 0 ]        || die "not root"
[ "$LFS" = /mnt/lfs ]     || die "LFS is '$LFS'"
mountpoint -q $LFS        || die "$LFS is not mounted"

# 7.2 Changing Ownership (one time)
if [ "$1" = --chown ]; then
  chown --from lfs -R root:root $LFS/{usr,var,etc,tools}
  case $(uname -m) in
    x86_64) chown --from lfs -R root:root $LFS/lib64 ;;
  esac
  echo "=== 7.2 ownership changed to root"
fi

# 7.3 Virtual kernel file systems (skip any already mounted)
mkdir -pv $LFS/{dev,proc,sys,run}
mountpoint -q $LFS/dev     || mount -v --bind /dev $LFS/dev
mountpoint -q $LFS/dev/pts || mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mountpoint -q $LFS/proc    || mount -vt proc proc $LFS/proc
mountpoint -q $LFS/sys     || mount -vt sysfs sysfs $LFS/sys
mountpoint -q $LFS/run     || mount -vt tmpfs tmpfs $LFS/run
if [ -h $LFS/dev/shm ]; then
  install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
  mountpoint -q $LFS/dev/shm || mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi
findmnt -R $LFS -o TARGET,FSTYPE

# 7.4 Entering the chroot environment
echo "=== entering chroot (type 'exit' to leave)"
exec chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login
