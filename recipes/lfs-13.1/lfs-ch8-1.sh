#!/bin/bash
# JJLinux - LFS 13.1-systemd Chapter 8, batch 1: 8.3 Man-pages .. 8.21 Pkgconf (tracked by JPM v0)
# Run INSIDE the chroot as root:   bash /sources/lfs-ch8-1.sh
. /sources/jpm-track.sh

# ---- 8.3 Man-pages ----
p_manpages() {
  rm -v man3/crypt*
  make -R GIT=false prefix=/usr install
}

# ---- 8.4 Iana-Etc ----
p_ianaetc() {
  cp -v services protocols /etc
}

# ---- 8.5 Glibc ----
p_glibc() {
  patch -Np1 -i ../glibc-fhs-1.patch
  patch -Np1 -i ../glibc-2.44-upstream_fixes-1.patch
  mkdir -v build
  cd       build
  ../configure --prefix=/usr                   \
               --disable-werror                \
               --disable-nscd                  \
               libc_cv_slibdir=/usr/lib        \
               --enable-stack-protector=strong \
               --enable-kernel=5.10
  make
  chk make check
  grep "Timed out" $(find -name \*.out) || true
  touch /etc/ld.so.conf
  sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
  make install
  sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
  localedef -i C -f UTF-8 C.UTF-8
  localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
  localedef -i de_DE -f ISO-8859-1 de_DE
  localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
  localedef -i de_DE -f UTF-8 de_DE.UTF-8
  localedef -i el_GR -f ISO-8859-7 el_GR
  localedef -i en_GB -f ISO-8859-1 en_GB
  localedef -i en_GB -f UTF-8 en_GB.UTF-8
  localedef -i en_HK -f ISO-8859-1 en_HK
  localedef -i en_PH -f ISO-8859-1 en_PH
  localedef -i en_US -f ISO-8859-1 en_US
  localedef -i en_US -f UTF-8 en_US.UTF-8
  localedef -i es_ES -f ISO-8859-15 es_ES@euro
  localedef -i es_MX -f ISO-8859-1 es_MX
  localedef -i fa_IR -f UTF-8 fa_IR
  localedef -i fr_FR -f ISO-8859-1 fr_FR
  localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
  localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
  localedef -i is_IS -f ISO-8859-1 is_IS
  localedef -i is_IS -f UTF-8 is_IS.UTF-8
  localedef -i it_IT -f ISO-8859-1 it_IT
  localedef -i it_IT -f ISO-8859-15 it_IT@euro
  localedef -i it_IT -f UTF-8 it_IT.UTF-8
  localedef -i ja_JP -f EUC-JP ja_JP
  localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
  localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
  localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
  localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
  localedef -i se_NO -f UTF-8 se_NO.UTF-8
  localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
  localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
  localedef -i zh_CN -f GB18030 zh_CN.GB18030
  localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
  localedef -i zh_TW -f UTF-8 zh_TW.UTF-8
  # 8.5.2.1 nsswitch.conf
  cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files systemd
group: files systemd
shadow: files systemd

hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF
  # 8.5.2.2 time zone data (JJ's zone: America/Los_Angeles; tzselect is interactive, so the answer is filled in)
  tar -xf ../../tzdata2026c.tar.gz
  ZONEINFO=/usr/share/zoneinfo
  mkdir -pv $ZONEINFO/{posix,right}
  for tz in etcetera southamerica northamerica europe africa antarctica  \
            asia australasia backward; do
      zic -L /dev/null   -d $ZONEINFO       ${tz}
      zic -L /dev/null   -d $ZONEINFO/posix ${tz}
      zic -L leapseconds -d $ZONEINFO/right ${tz}
  done
  cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
  zic -d $ZONEINFO -p America/New_York
  unset ZONEINFO tz
  ln -sfv /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
  # 8.5.2.3 dynamic loader
  cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF
  cat >> /etc/ld.so.conf << "EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF
  mkdir -pv /etc/ld.so.conf.d
}

# ---- 8.6 Zlib ----
p_zlib() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
  rm -fv /usr/lib/libz.a
}

# ---- 8.7 Bzip2 ----
p_bzip2() {
  patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
  sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
  sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
  make -f Makefile-libbz2_so
  make clean
  make
  make PREFIX=/usr install
  cp -av libbz2.so.* /usr/lib
  ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
  ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
  cp -v bzip2-shared /usr/bin/bzip2
  for i in /usr/bin/{bzcat,bunzip2}; do
    ln -sfv bzip2 $i
  done
  rm -fv /usr/lib/libbz2.a
}

# ---- 8.8 Xz ----
p_xz() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/xz-5.8.3
  make
  chk make check
  make install
}

# ---- 8.9 Lz4 ----
p_lz4() {
  make BUILD_STATIC=no PREFIX=/usr
  chk make -j1 check
  make BUILD_STATIC=no PREFIX=/usr install
}

# ---- 8.10 Zstd ----
p_zstd() {
  make prefix=/usr
  chk make check
  make prefix=/usr install
  rm -v /usr/lib/libzstd.a
}

# ---- 8.11 File ----
p_file() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
}

# ---- 8.12 Readline ----
p_readline() {
  sed -i '/MV.*old/d' Makefile.in
  sed -i '/{OLDSUFF}/c:' support/shlib-install
  sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
  sed -e '270a\
     else\
       chars_avail = 1;'      \
      -e '288i\   result = -1;' \
      -i.orig input.c
  ./configure --prefix=/usr    \
              --disable-static \
              --with-curses    \
              --docdir=/usr/share/doc/readline-8.3
  make SHLIB_LIBS="-lncursesw"
  make install
  install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.3
}

# ---- 8.13 Pcre2 ----
p_pcre2() {
  ./configure --prefix=/usr                       \
              --docdir=/usr/share/doc/pcre2-10.47 \
              --enable-unicode                    \
              --enable-jit                        \
              --enable-pcre2-16                   \
              --enable-pcre2-32                   \
              --enable-pcre2grep-libz             \
              --enable-pcre2grep-libbz2           \
              --enable-pcre2test-libreadline      \
              --disable-static
  make
  chk make check
  make install
}

# ---- 8.14 M4 ----
p_m4() {
  ./configure --prefix=/usr
  make
  chk make check
  make install
}

# ---- 8.15 Bc ----
p_bc() {
  CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r
  make
  chk make test
  make install
}

# ---- 8.16 Flex ----
p_flex() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/flex-2.6.4
  make
  chk make check
  make install
  ln -sv flex   /usr/bin/lex
  ln -sv flex.1 /usr/share/man/man1/lex.1
}

# ---- 8.17 Tcl ----
p_tcl() {
  SRCDIR=$(pwd)
  cd unix
  ./configure --prefix=/usr           \
              --mandir=/usr/share/man \
              --disable-rpath
  make
  sed -e "s|$SRCDIR/unix|/usr/lib|" \
      -e "s|$SRCDIR|/usr/include|" \
      -i tclConfig.sh
  sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.13|/usr/lib/tdbc1.1.13|" \
      -e "s|$SRCDIR/pkgs/tdbc1.1.13/generic|/usr/include|"     \
      -e "s|$SRCDIR/pkgs/tdbc1.1.13/library|/usr/lib/tcl8.6|" \
      -e "s|$SRCDIR/pkgs/tdbc1.1.13|/usr/include|"             \
      -i pkgs/tdbc1.1.13/tdbcConfig.sh
  sed -e "s|$SRCDIR/unix/pkgs/itcl4.3.7|/usr/lib/itcl4.3.7|" \
      -e "s|$SRCDIR/pkgs/itcl4.3.7/generic|/usr/include|"    \
      -e "s|$SRCDIR/pkgs/itcl4.3.7|/usr/include|"            \
      -i pkgs/itcl4.3.7/itclConfig.sh
  unset SRCDIR
  LC_ALL=C.UTF-8 chk make test
  make install
  chmod 644 /usr/lib/libtclstub8.6.a
  chmod -v u+w /usr/lib/libtcl8.6.so
  make install-private-headers
  ln -sfv tclsh8.6 /usr/bin/tclsh
  mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3
  cd ..
  tar -xf ../tcl8.6.18-html.tar.gz --strip-components=1
  mkdir -v -p /usr/share/doc/tcl-8.6.18
  cp -v -r ./html/* /usr/share/doc/tcl-8.6.18
}

# ---- 8.18 Expect ----
p_expect() {
  # a PTY turns "\n" into "\r\n", so strip the \r before comparing
  [ "$(python3 -c 'from pty import spawn; spawn(["echo", "ok"])' | tr -d '\r')" = ok ] || { echo "PTY TEST FAILED (book 8.18)"; exit 1; }
  patch -Np1 -i ../expect-5.45.4-gcc15-1.patch
  ./configure --prefix=/usr           \
              --with-tcl=/usr/lib     \
              --enable-shared         \
              --disable-rpath         \
              --mandir=/usr/share/man \
              --with-tclinclude=/usr/include
  make
  chk make test
  make install
  ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
}

# ---- 8.19 DejaGNU ----
p_dejagnu() {
  mkdir -v build
  cd       build
  ../configure --prefix=/usr
  makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
  makeinfo --plaintext       -o doc/dejagnu.txt ../doc/dejagnu.texi
  chk make check
  make install
  install -v -dm755      /usr/share/doc/dejagnu-1.6.3
  install -v -m644       doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
}

# ---- 8.20 Ninja ----
p_ninja() {
  sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc
  python3 configure.py --bootstrap --verbose
  install -vm755 ninja /usr/bin/
  install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
  install -vDm644 misc/zsh-completion /usr/share/zsh/site-functions/_ninja
}

# ---- 8.21 Pkgconf ----
p_pkgconf() {
  tar -xf ../meson-1.12.0.tar.gz
  mkdir build
  cd    build
  python3 ../meson-1.12.0/meson.py setup --prefix=/usr --buildtype=release ..
  ninja
  chk ninja test
  ninja install
  mv /usr/share/doc/pkgconf{,-3.0.5}
  ln -sv pkgconf   /usr/bin/pkg-config
  ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
}

jpm_baseline
T0=$SECONDS
track 8.03 man-pages-6.18     man-pages-6.18.tar.xz     man-pages-6.18     p_manpages
track 8.04 iana-etc-20260805  iana-etc-20260805.tar.gz  iana-etc-20260805  p_ianaetc
track 8.05 glibc-2.44         glibc-2.44.tar.xz         glibc-2.44         p_glibc
track 8.06 zlib-1.3.2         zlib-1.3.2.tar.gz         zlib-1.3.2         p_zlib
track 8.07 bzip2-1.0.8        bzip2-1.0.8.tar.gz        bzip2-1.0.8        p_bzip2
track 8.08 xz-5.8.3           xz-5.8.3.tar.xz           xz-5.8.3           p_xz
track 8.09 lz4-1.10.0         lz4-1.10.0.tar.gz         lz4-1.10.0         p_lz4
track 8.10 zstd-1.5.7         zstd-1.5.7.tar.gz         zstd-1.5.7         p_zstd
track 8.11 file-5.48          file-5.48.tar.gz          file-5.48          p_file
track 8.12 readline-8.3       readline-8.3.tar.gz       readline-8.3       p_readline
track 8.13 pcre2-10.47        pcre2-10.47.tar.bz2       pcre2-10.47        p_pcre2
track 8.14 m4-1.4.21          m4-1.4.21.tar.xz          m4-1.4.21          p_m4
track 8.15 bc-7.0.3           bc-7.0.3.tar.xz           bc-7.0.3           p_bc
track 8.16 flex-2.6.4         flex-2.6.4.tar.gz         flex-2.6.4         p_flex
track 8.17 tcl-8.6.18         tcl8.6.18-src.tar.gz      tcl8.6.18          p_tcl
track 8.18 expect-5.45.4      expect5.45.4.tar.gz       expect5.45.4       p_expect
track 8.19 dejagnu-1.6.3      dejagnu-1.6.3.tar.gz      dejagnu-1.6.3      p_dejagnu
track 8.20 ninja-1.13.2       ninja-1.13.2.tar.gz       ninja-1.13.2       p_ninja
track 8.21 pkgconf-3.0.5      pkgconf-3.0.5.tar.xz      pkgconf-3.0.5      p_pkgconf
echo "=== BATCH 1 DONE in $((SECONDS-T0))s"
echo "--- test failures (review these):"; grep -l . $J/installed/*/testfail 2>/dev/null || echo "none"
echo "--- glibc failing tests:"; grep -E '^FAIL:' $L/8.05-glibc-2.44.log | head -30
