#!/bin/bash
# JJLinux - LFS 13.1-systemd: 7.5-7.14 and 7.15.1 (Cleaning). Book commands verbatim.
# Run INSIDE the chroot as root:   bash /sources/lfs-ch7.sh
set +h
umask 022
S=/sources
L=$S/logs
die() { echo "!!! STOP: $*"; exit 1; }

# ---- guard: must be root inside the LFS chroot ----
[ "$(id -u)" = 0 ]                       || die "not root"
grep -q AGENTIC /README.md 2>/dev/null   || die "not inside the LFS chroot (/README.md missing)"
[ -d /mnt/lfs ] && die "/mnt/lfs exists here - this looks like the host, not the chroot"
[ ! -e /usr/lib64 ]                      || die "/usr/lib64 exists (book 7.5.1 warning)"

# ---- 7.5 Creating Directories ----
mkdir -pv /{boot,home,mnt,opt,srv}
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{,local/}{include,src}
mkdir -pv /usr/lib/locale
mkdir -pv /usr/local/{bin,lib,sbin}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}
ln -sfv /run /var/run
ln -sfv /run/lock /var/lock
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp

# ---- 7.6 Creating Essential Files and Symlinks ----
ln -sv /proc/self/mounts /etc/mtab
cat > /etc/hosts << EOF
127.0.0.1 localhost $(hostname)
::1        localhost
EOF
cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF
cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF
echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
echo "tester:x:101:" >> /etc/group
install -o tester -d /home/tester
# (book: 'exec /usr/bin/bash --login' only refreshes the interactive prompt; not needed in a script)
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664 /var/log/lastlog
chmod -v 600 /var/log/btmp
echo "=== 7.5-7.6 done"

# ---- runner ----
build() {
  local id=$1 tarball=$2 dir=$3 fn=$4 t0=$SECONDS
  cd $S && rm -rf $dir && tar -xf $tarball && cd $dir || die "$id: unpack failed"
  echo "=== $id ..."
  ( set -e; $fn ) > $L/$id.log 2>&1
  local rc=$?
  [ $rc = 0 ] || { tail -30 $L/$id.log; die "$id failed (rc=$rc), source kept in $S/$dir, log $L/$id.log"; }
  cd $S && rm -rf $dir
  printf "=== %-24s OK  %4ss\n" "$id" $((SECONDS-t0)) | tee -a $L/ch7-summary.txt
}

p_gettext() {
  ./configure --disable-shared
  make
  cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}
p_bison() {
  ./configure --prefix=/usr \
              --docdir=/usr/share/doc/bison-3.8.2
  make
  make install
}
p_perl() {
  sh Configure -des                                         \
               -D prefix=/usr                               \
               -D vendorprefix=/usr                         \
               -D useshrplib                                \
               -D privlib=/usr/lib/perl5/5.44/core_perl     \
               -D archlib=/usr/lib/perl5/5.44/core_perl     \
               -D sitelib=/usr/lib/perl5/5.44/site_perl     \
               -D sitearch=/usr/lib/perl5/5.44/site_perl    \
               -D vendorlib=/usr/lib/perl5/5.44/vendor_perl \
               -D vendorarch=/usr/lib/perl5/5.44/vendor_perl
  make
  make install
}
p_zlib() {
  ./configure --prefix=/usr
  make
  make install
  rm -fv /usr/lib/libz.a
}
p_mpdecimal() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/mpdecimal-4.0.1
  make
  make install
}
p_python() {
  ./configure --prefix=/usr       \
              --enable-shared     \
              --without-ensurepip \
              --without-static-libpython
  make
  make install
}
p_texinfo() {
  ./configure --prefix=/usr
  make
  make install
}
p_utillinux() {
  mkdir -pv /var/lib/hwclock
  ./configure --libdir=/usr/lib     \
              --runstatedir=/run    \
              --disable-chfn-chsh   \
              --disable-login       \
              --disable-nologin     \
              --disable-su          \
              --disable-setpriv     \
              --disable-runuser     \
              --disable-pylibmount  \
              --disable-static      \
              --disable-liblastlog2 \
              --without-python      \
              ADJTIME_PATH=/var/lib/hwclock/adjtime \
              --docdir=/usr/share/doc/util-linux-2.42.2
  make
  make install
}

: > $L/ch7-summary.txt
T0=$SECONDS
build 7.07-gettext    gettext-1.0.tar.xz        gettext-1.0        p_gettext
build 7.08-bison      bison-3.8.2.tar.xz        bison-3.8.2        p_bison
build 7.09-perl       perl-5.44.0.tar.xz        perl-5.44.0        p_perl
build 7.10-zlib       zlib-1.3.2.tar.gz         zlib-1.3.2         p_zlib
build 7.11-mpdecimal  mpdecimal-4.0.1.tar.gz    mpdecimal-4.0.1    p_mpdecimal
build 7.12-python     Python-3.14.7.tar.xz      Python-3.14.7      p_python
build 7.13-texinfo    texinfo-7.3.tar.xz        texinfo-7.3        p_texinfo
build 7.14-util-linux util-linux-2.42.2.tar.xz  util-linux-2.42.2  p_utillinux

# ---- 7.15.1 Cleaning ----
rm -rf /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name \*.la -delete
rm -rf /tools
echo "=== 7.15.1 cleaning done"
echo "=== ALL DONE in $((SECONDS-T0))s"
python3 --version; perl -v | sed -n 2p; ls /tools 2>&1 | head -1
