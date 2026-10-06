#!/bin/bash
# JJLinux - LFS 13.1-systemd Chapter 8, batch 4: 8.61 Coreutils .. 8.82 E2fsprogs, then 8.85 Cleaning Up
# (tracked by JPM v0). 8.84 Stripping is optional and NOT done here - decided separately.
# Run INSIDE the chroot as root (after 'exec /usr/bin/bash --login'):   bash /sources/lfs-ch8-4.sh
. /sources/jpm-track.sh

p_coreutils() {
  patch -Np1 -i ../coreutils-9.11-i18n-1.patch
  autoreconf -fv
  automake -af
  FORCE_UNSAFE_CONFIGURE=1 ./configure \
              --prefix=/usr
  make
  chk make NON_ROOT_USERNAME=tester check-root
  groupadd -g 102 dummy -U tester
  chown -R tester .
  chk su tester -c "PATH=$PATH make -k RUN_EXPENSIVE_TESTS=yes check" \
     < /dev/null
  groupdel dummy
  make install
  mv -v /usr/bin/chroot /usr/sbin
  mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
  sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
}

p_diffutils() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
}

p_findutils() {
  ./configure --prefix=/usr --localstatedir=/var/lib/locate
  make
  chown -R tester .
  chk su tester -c "PATH=$PATH make check -k"
  make install
}

p_groff() {
  PAGE=letter ./configure --prefix=/usr
  make -j1
  chk make check
  make install
}

# GRUB: book sections 8.65.1 (BIOS) then 8.65.2 (64-bit UEFI), exactly in book order.
p_grub() {
  unset {C,CPP,CXX,LD}FLAGS
  sed 's/--image-base/--nonexist-linker-option/' -i configure
  ./configure --prefix=/usr     \
              --sysconfdir=/etc \
              --disable-efiemu  \
              --disable-werror
  make
  make install
  make clean
  ./configure --prefix=/usr       \
              --sysconfdir=/etc   \
              --target=x86_64     \
              --with-platform=efi \
              --disable-efiemu    \
              --disable-werror
  make
  make install
}

p_gzip() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
}

p_iproute2() {
  sed -i /ARPD/d Makefile
  rm -fv man/man8/arpd.8
  make NETNS_RUN_DIR=/run/netns
  make SBINDIR=/usr/sbin install
  install -vDm644 COPYING README* -t /usr/share/doc/iproute2-7.1.0
}

p_kbd() {
  patch -Np1 -i ../kbd-2.10.0-backspace-1.patch
  sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
  sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
  ./configure --prefix=/usr --disable-vlock
  make
  chk make check
  make install
  cp -R -v docs/doc -T /usr/share/doc/kbd-2.10.0
}

p_libpipeline() {
  ./configure --prefix=/usr
  make
  make install
}

p_make() {
  ./configure --prefix=/usr
  make
  chown -R tester .
  chk su tester -c "PATH=$PATH make check"
  make install
}

p_patch() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
}

p_tar() {
  patch -Np1 -i ../tar-1.35-acl_fix-1.patch
  FORCE_UNSAFE_CONFIGURE=1  \
  ./configure --prefix=/usr
  make
  chk make check
  make install
  make -C doc install-html docdir=/usr/share/doc/tar-1.35
}

p_texinfo() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
  make TEXMF=/usr/share/texmf install-tex
}

p_vim() {
  echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
  ./configure --prefix=/usr
  make
  chown -R tester .
  sed '/test_plugin_glvs/d' -i src/testdir/Make_all.mak
  chk su tester -c "TERM=xterm-256color LANG=en_US.UTF-8 make -j1 test" \
     &> vim-test.log
  echo "=== vim test summary:"; grep -E 'FAILED|Executed|Skipped' vim-test.log | tail -5 || true
  cp vim-test.log /sources/logs/8.74-vim-test.log
  make install
  ln -sv vim /usr/bin/vi
  for L in /usr/share/man/{,*/}man1/vim.1; do
      ln -sv vim.1 $(dirname $L)/vi.1
  done
  ln -sv ../vim/vim92/doc /usr/share/doc/vim-9.2.1025
  cat > /etc/vimrc << "EOF"
" Begin /etc/vimrc

" Ensure defaults are set before customizing settings, not after
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF
}

p_markupsafe() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist Markupsafe
}

p_jinja2() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist Jinja2
}

p_systemd() {
  sed -e 's/GROUP="render"/GROUP="video"/' \
      -e 's/GROUP="sgx", //'               \
      -i rules.d/50-udev-default.rules.in
  mkdir -p build
  cd       build
  meson setup ..                \
        --prefix=/usr           \
        --buildtype=release     \
        -D default-dnssec=no    \
        -D firstboot=false      \
        -D install-tests=false  \
        -D ldconfig=false       \
        -D sysusers=false       \
        -D rpmmacrosdir=no      \
        -D homed=disabled       \
        -D man=disabled         \
        -D mode=release         \
        -D pamconfdir=no        \
        -D dev-kvm-mode=0660    \
        -D nobody-group=nogroup \
        -D sysupdate=disabled   \
        -D ukify=disabled       \
        -D docdir=/usr/share/doc/systemd-261.2
  ninja
  echo 'NAME="Linux From Scratch"' > /etc/os-release
  chk unshare -m ninja test
  ninja install
  tar -xf ../../systemd-man-pages-261.2.tar.xz \
      --no-same-owner --strip-components=1     \
      -C /usr/share/man
  systemd-machine-id-setup
  systemctl preset-all
}

p_dbus() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..
  ninja
  chk ninja test
  ninja install
  ln -sfv /etc/machine-id /var/lib/dbus
}

p_mandb() {
  ./configure --prefix=/usr                         \
              --docdir=/usr/share/doc/man-db-2.13.1 \
              --sysconfdir=/etc                     \
              --disable-setuid                      \
              --enable-cache-owner=bin              \
              --with-browser=/usr/bin/lynx          \
              --with-vgrind=/usr/bin/vgrind         \
              --with-grap=/usr/bin/grap
  make
  chk make check
  make install
}

p_procps() {
  ./configure --prefix=/usr                           \
              --docdir=/usr/share/doc/procps-ng-4.0.7 \
              --disable-static                        \
              --disable-kill                          \
              --enable-watch8bit                      \
              --with-systemd
  make
  chown -R tester .
  chk su tester -c "PATH=$PATH make check"
  make install
}

p_utillinux() {
  ./configure --bindir=/usr/bin     \
              --libdir=/usr/lib     \
              --runstatedir=/run    \
              --sbindir=/usr/sbin   \
              --disable-chfn-chsh   \
              --disable-login       \
              --disable-nologin     \
              --disable-su          \
              --disable-setpriv     \
              --disable-runuser     \
              --disable-pylibmount  \
              --disable-liblastlog2 \
              --disable-static      \
              --without-python      \
              ADJTIME_PATH=/var/lib/hwclock/adjtime \
              --docdir=/usr/share/doc/util-linux-2.42.2
  make
  touch /etc/fstab
  chown -R tester .
  chk su tester -c "make -k check"
  make install
}

p_e2fsprogs() {
  mkdir -v build
  cd       build
  ../configure --prefix=/usr       \
               --sysconfdir=/etc   \
               --enable-elf-shlibs \
               --disable-libblkid  \
               --disable-libuuid   \
               --disable-uuidd     \
               --disable-fsck
  make
  chk make check
  make install
  rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
  gunzip -v /usr/share/info/libext2fs.info.gz
  install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
  makeinfo -o      doc/com_err.info ../lib/et/com_err.texinfo
  install -v -m644 doc/com_err.info /usr/share/info
  install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
}

# 8.85 Cleaning Up - tracked too, so JPM's index learns about the deleted files
p_cleanup() {
  rm -rf /tmp/{*,.*}
  find /usr/lib /usr/libexec -name \*.la -delete
  find /usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf
  userdel -r tester
}

T0=$SECONDS
track 8.61 coreutils-9.11      coreutils-9.11.tar.xz     coreutils-9.11      p_coreutils
track 8.62 diffutils-3.12      diffutils-3.12.tar.xz     diffutils-3.12      p_diffutils
track 8.63 findutils-4.11.0    findutils-4.11.0.tar.xz   findutils-4.11.0    p_findutils
track 8.64 groff-1.24.1        groff-1.24.1.tar.gz       groff-1.24.1        p_groff
track 8.65 grub-2.14           grub-2.14.tar.xz          grub-2.14           p_grub
track 8.66 gzip-1.14           gzip-1.14.tar.xz          gzip-1.14           p_gzip
track 8.67 iproute2-7.1.0      iproute2-7.1.0.tar.xz     iproute2-7.1.0      p_iproute2
track 8.68 kbd-2.10.0          kbd-2.10.0.tar.xz         kbd-2.10.0          p_kbd
track 8.69 libpipeline-1.5.8   libpipeline-1.5.8.tar.gz  libpipeline-1.5.8   p_libpipeline
track 8.70 make-4.4.1          make-4.4.1.tar.gz         make-4.4.1          p_make
track 8.71 patch-2.8           patch-2.8.tar.xz          patch-2.8           p_patch
track 8.72 tar-1.35            tar-1.35.tar.xz           tar-1.35            p_tar
track 8.73 texinfo-7.3         texinfo-7.3.tar.xz        texinfo-7.3         p_texinfo
track 8.74 vim-9.2.1025        vim-9.2.1025.tar.gz       vim-9.2.1025        p_vim
track 8.75 markupsafe-3.0.3    markupsafe-3.0.3.tar.gz   markupsafe-3.0.3    p_markupsafe
track 8.76 jinja2-3.1.6        jinja2-3.1.6.tar.gz       jinja2-3.1.6        p_jinja2
track 8.77 systemd-261.2       systemd-261.2.tar.gz      systemd-261.2       p_systemd
track 8.78 dbus-1.16.2         dbus-1.16.2.tar.xz        dbus-1.16.2         p_dbus
track 8.79 man-db-2.13.1       man-db-2.13.1.tar.xz      man-db-2.13.1       p_mandb
track 8.80 procps-ng-4.0.7     procps-ng-4.0.7.tar.xz    procps-ng-4.0.7     p_procps
track 8.81 util-linux-2.42.2   util-linux-2.42.2.tar.xz  util-linux-2.42.2   p_utillinux
track 8.82 e2fsprogs-1.47.4    e2fsprogs-1.47.4.tar.gz   e2fsprogs-1.47.4    p_e2fsprogs
track 8.85 lfs-cleanup-8.85    -                         -                   p_cleanup
echo "=== BATCH 4 DONE in $((SECONDS-T0))s"
echo "--- packages with test failures:"; ls $J/installed/*/testfail 2>/dev/null | sed 's|.*/installed/||;s|/testfail||' || true
echo "--- JPM: $(ls $J/installed | wc -l) records, $(wc -l < $J/index) indexed paths"
echo "--- /usr/lib64 must not exist:"; ls -d /usr/lib64 2>&1 || true
