#!/bin/bash
# JJLinux - LFS 13.1-systemd Chapter 8, batch 3: 8.33 Ncurses .. 8.60 Kmod (tracked by JPM v0)
# Run INSIDE the chroot as root:   bash /sources/lfs-ch8-3.sh
# NOTE: after this batch, run 'exec /usr/bin/bash --login' in your interactive shell (book 8.39).
. /sources/jpm-track.sh

p_ncurses() {
  ./configure --prefix=/usr           \
              --mandir=/usr/share/man \
              --with-shared           \
              --without-debug         \
              --without-normal        \
              --with-cxx-shared       \
              --enable-pc-files       \
              --with-pkg-config-libdir=/usr/lib/pkgconfig
  make
  make DESTDIR=$PWD/dest install
  sed -e 's/^#if.*XOPEN.*$/#if 1/' \
      -i dest/usr/include/curses.h
  cp --remove-destination -av dest/* /
  for lib in ncurses form panel menu ; do
      ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
      ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
  done
  ln -sfv libncursesw.so /usr/lib/libcurses.so
  cp -v -R doc -T /usr/share/doc/ncurses-6.6
}

p_sed() {
  ./configure --prefix=/usr
  make
  make html
  chown -R tester .
  chk su tester -c "PATH=$PATH make check"
  make install
  install -vDm644 doc/sed.html -t /usr/share/doc/sed-4.10
}

p_psmisc() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
}

p_gettext() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/gettext-1.0
  make
  chk make check
  make install
  chmod -v 0755 /usr/lib/preloadable_libintl.so
}

p_bison() {
  ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
  make
  chk make check
  make install
}

p_grep() {
  sed -i "s/echo/#echo/" src/egrep.sh
  ./configure --prefix=/usr
  make
  chk make check
  make install
}

p_bash() {
  ./configure --prefix=/usr             \
              --without-bash-malloc     \
              --with-installed-readline \
              --docdir=/usr/share/doc/bash-5.3
  make
  chown -R tester .
  LC_ALL=C.UTF-8 chk su -s /usr/bin/expect tester << "EOF"
set timeout -1
spawn make tests
expect eof
lassign [wait] _ _ _ value
exit $value
EOF
  make install
  # book: 'exec /usr/bin/bash --login' - done in the interactive shell after the batch
}

p_libtool() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
  rm -fv /usr/lib/libltdl.a
}

p_gdbm() {
  ./configure --prefix=/usr    \
              --disable-static \
              --enable-libgdbm-compat
  make
  chk make check
  make install
}

p_gperf() {
  ./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3
  make
  chk make check
  make install
}

p_expat() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/expat-2.8.3
  make
  chk make check
  make install
  install -v -m644 doc/*.{html,css} /usr/share/doc/expat-2.8.3
}

p_inetutils() {
  sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
  ./configure --prefix=/usr        \
              --bindir=/usr/bin    \
              --localstatedir=/var \
              --disable-logger     \
              --disable-whois      \
              --disable-rcp        \
              --disable-rexec      \
              --disable-rlogin     \
              --disable-rsh        \
              --disable-servers
  make
  chk make check
  make install
  mv -v /usr/{,s}bin/ifconfig
}

p_less() {
  ./configure --prefix=/usr --sysconfdir=/etc
  make
  chk make check
  # JJLinux: less 704's "make check" rebuilds less with LESSTEST=1; rebuild the normal binary before installing
  make clean
  make
  make install
}

p_perl() {
  export BUILD_ZLIB=False
  export BUILD_BZIP2=0
  sh Configure -des                                          \
               -D prefix=/usr                                \
               -D vendorprefix=/usr                          \
               -D privlib=/usr/lib/perl5/5.44/core_perl      \
               -D archlib=/usr/lib/perl5/5.44/core_perl      \
               -D sitelib=/usr/lib/perl5/5.44/site_perl      \
               -D sitearch=/usr/lib/perl5/5.44/site_perl     \
               -D vendorlib=/usr/lib/perl5/5.44/vendor_perl  \
               -D vendorarch=/usr/lib/perl5/5.44/vendor_perl \
               -D man1dir=/usr/share/man/man1                \
               -D man3dir=/usr/share/man/man3                \
               -D pager="/usr/bin/less -isR"                 \
               -D useshrplib                                 \
               -D usethreads
  make
  TEST_JOBS=$(nproc) chk make test_harness
  make install
  unset BUILD_ZLIB BUILD_BZIP2
}

p_autoconf() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
}

p_automake() {
  ./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1
  make
  chk make -j$(($(nproc)>4?$(nproc):4)) check
  make install
}

p_openssl() {
  ./config --prefix=/usr         \
           --openssldir=/etc/ssl \
           --libdir=lib          \
           shared                \
           zlib-dynamic
  make
  chk make test
  make INSTALL_LIBS= MANSUFFIX=ssl install
  mv -v /usr/share/doc/openssl /usr/share/doc/openssl-4.0.1
  cp -vfr doc/* /usr/share/doc/openssl-4.0.1
}

p_libelf() {
  ./configure --prefix=/usr        \
              --disable-debuginfod \
              --enable-libdebuginfod=dummy
  make -C lib
  make -C libelf
  chk make -k check
  make -C libelf install
  install -vm644 config/libelf.pc /usr/lib/pkgconfig
  rm /usr/lib/libelf.a
}

p_libffi() {
  ./configure --prefix=/usr    \
              --disable-static \
              --with-gcc-arch=native
  make
  chk make check
  make install
}

p_sqlite() {
  python3 -m zipfile -e ../sqlite-doc-3530400.zip .
  ./configure --prefix=/usr     \
              --disable-static  \
              --enable-fts{4,5} \
              CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 \
                        -D SQLITE_ENABLE_UNLOCK_NOTIFY=1   \
                        -D SQLITE_ENABLE_DBSTAT_VTAB=1     \
                        -D SQLITE_SECURE_DELETE=1"
  make LDFLAGS.rpath=""
  make install
  cp -v -R sqlite-doc-3530400 -T /usr/share/doc/sqlite-3.53.4
}

p_mpdecimal() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/mpdecimal-4.0.1
  make
  chk make check_local
  make install
}

p_python() {
  patch -Np1 -i ../Python-3.14.7-openssl_4-1.patch
  ./configure --prefix=/usr          \
              --enable-shared        \
              --with-system-expat    \
              --enable-optimizations \
              --without-static-libpython
  make
  chk make test TESTOPTS="--timeout 120"
  make install
  cat > /etc/pip.conf << EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF
  install -v -dm755 /usr/share/doc/python-3.14.7/html
  tar --strip-components=1  \
      --no-same-owner       \
      --no-same-permissions \
      -C /usr/share/doc/python-3.14.7/html \
      -xvf ../python-3.14.7-docs-html.tar.bz2
}

p_flitcore() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist flit_core
}
p_packaging() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist packaging
}
p_wheel() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist wheel
}
p_setuptools() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist setuptools
}
p_meson() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist meson
  install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
  install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
}

p_kmod() {
  mkdir -p build
  cd       build
  meson setup --prefix=/usr ..    \
              --buildtype=release \
              -D manpages=false
  ninja
  ninja install
}

T0=$SECONDS
track 8.33 ncurses-6.6        ncurses-6.6.tar.gz          ncurses-6.6          p_ncurses
track 8.34 sed-4.10           sed-4.10.tar.xz             sed-4.10             p_sed
track 8.35 psmisc-23.7        psmisc-23.7.tar.xz          psmisc-23.7          p_psmisc
track 8.36 gettext-1.0        gettext-1.0.tar.xz          gettext-1.0          p_gettext
track 8.37 bison-3.8.2        bison-3.8.2.tar.xz          bison-3.8.2          p_bison
track 8.38 grep-3.12          grep-3.12.tar.xz            grep-3.12            p_grep
track 8.39 bash-5.3           bash-5.3.tar.gz             bash-5.3             p_bash
track 8.40 libtool-2.6.2      libtool-2.6.2.tar.xz        libtool-2.6.2        p_libtool
track 8.41 gdbm-1.26          gdbm-1.26.tar.gz            gdbm-1.26            p_gdbm
track 8.42 gperf-3.3          gperf-3.3.tar.gz            gperf-3.3            p_gperf
track 8.43 expat-2.8.3        expat-2.8.3.tar.xz          expat-2.8.3          p_expat
track 8.44 inetutils-2.8      inetutils-2.8.tar.gz        inetutils-2.8        p_inetutils
track 8.45 less-704           less-704.tar.gz             less-704             p_less
track 8.46 perl-5.44.0        perl-5.44.0.tar.xz          perl-5.44.0          p_perl
track 8.47 autoconf-2.73      autoconf-2.73.tar.xz        autoconf-2.73        p_autoconf
track 8.48 automake-1.18.1    automake-1.18.1.tar.xz      automake-1.18.1      p_automake
track 8.49 openssl-4.0.1      openssl-4.0.1.tar.gz        openssl-4.0.1        p_openssl
track 8.50 libelf-0.195       elfutils-0.195.tar.bz2      elfutils-0.195       p_libelf
track 8.51 libffi-3.8.0       libffi-3.8.0.tar.gz         libffi-3.8.0         p_libffi
track 8.52 sqlite-3530400     sqlite-autoconf-3530400.tar.gz sqlite-autoconf-3530400 p_sqlite
track 8.53 mpdecimal-4.0.1    mpdecimal-4.0.1.tar.gz      mpdecimal-4.0.1      p_mpdecimal
track 8.54 python-3.14.7      Python-3.14.7.tar.xz        Python-3.14.7        p_python
track 8.55 flit_core-4.0.2    flit_core-4.0.2.tar.gz      flit_core-4.0.2      p_flitcore
track 8.56 packaging-26.3     packaging-26.3.tar.gz       packaging-26.3       p_packaging
track 8.57 wheel-0.48.0       wheel-0.48.0.tar.gz         wheel-0.48.0         p_wheel
track 8.58 setuptools-84.0.0  setuptools-84.0.0.tar.gz    setuptools-84.0.0    p_setuptools
track 8.59 meson-1.12.0       meson-1.12.0.tar.gz         meson-1.12.0         p_meson
track 8.60 kmod-34.2          kmod-34.2.tar.xz            kmod-34.2            p_kmod
echo "=== BATCH 3 DONE in $((SECONDS-T0))s"
echo "--- packages with test failures:"; ls $J/installed/*/testfail 2>/dev/null | sed 's|.*/installed/||;s|/testfail||' || true
echo ">>> NEXT: run 'exec /usr/bin/bash --login' (book 8.39)"
