#!/bin/bash
# JJLinux - LFS 13.1-systemd Chapter 8, batch 2: 8.22 Binutils .. 8.32 GCC (tracked by JPM v0)
# Run INSIDE the chroot as root:   bash /sources/lfs-ch8-2.sh
# NOTE: 8.30.3 'passwd root' is interactive - run it yourself after this batch.
. /sources/jpm-track.sh

# ---- 8.22 Binutils ----
p_binutils() {
  mkdir -v build
  cd       build
  ../configure --prefix=/usr       \
               --sysconfdir=/etc   \
               --enable-ld=default \
               --enable-plugins    \
               --enable-shared     \
               --disable-werror    \
               --enable-64-bit-bfd \
               --enable-new-dtags  \
               --with-system-zlib  \
               --with-lib-path=/usr/lib \
               --enable-default-hash-style=gnu
  make tooldir=/usr
  chk make -k check
  echo "=== binutils FAIL list:"; grep '^FAIL:' $(find -name '*.log') || true
  make tooldir=/usr install
  rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
          /usr/share/doc/gprofng/
}

# ---- 8.23 GMP ----
p_gmp() {
  sed -i '/long long t1;/,+1s/()/(...)/' configure
  ./configure --prefix=/usr    \
              --enable-cxx     \
              --disable-static \
              --docdir=/usr/share/doc/gmp-6.3.0
  make
  make html
  chk make check
  n=$(cat $(find -name '*.log') | grep -c ^PASS)
  echo "=== GMP PASS count: $n (book: at least 199)"
  [ "$n" -ge 199 ] || { echo "GMP: fewer than 199 tests passed - critical per the book"; exit 1; }
  make install
  make install-html
}

# ---- 8.24 MPFR ----
p_mpfr() {
  ./configure --prefix=/usr        \
              --disable-static     \
              --enable-thread-safe \
              --docdir=/usr/share/doc/mpfr-4.2.2
  make
  make html
  chk make check
  grep -E '^# (TOTAL|PASS|FAIL|ERROR):' tests/test-suite.log || true
  make install
  make install-html
}

# ---- 8.25 MPC ----
p_mpc() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/mpc-1.4.1
  make
  make html
  chk make check
  make install
  make install-html
}

# ---- 8.26 Attr ----
p_attr() {
  ./configure --prefix=/usr     \
              --disable-static  \
              --sysconfdir=/etc \
              --docdir=/usr/share/doc/attr-2.6.0
  make
  chk make check
  make install
}

# ---- 8.27 Acl ----
p_acl() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/acl-2.4.0
  make
  chk make check
  make install
}

# ---- 8.28 Libcap ----
p_libcap() {
  sed -i '/install -m.*STA/d' libcap/Makefile
  make prefix=/usr lib=lib
  chk make test
  make prefix=/usr lib=lib install
}

# ---- 8.29 Libxcrypt ----
p_libxcrypt() {
  sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
  ./configure --prefix=/usr                \
              --enable-hashes=strong,glibc \
              --enable-obsolete-api=no     \
              --disable-static             \
              --disable-failure-tokens
  make
  chk make check
  make install
}

# ---- 8.30 Shadow ----
p_shadow() {
  find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
  find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
  sed -e 's:#ENCRYPT_METHOD SHA512:ENCRYPT_METHOD YESCRYPT:' \
      -e 's:/var/spool/mail:/var/mail:'                      \
      -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                     \
      -i etc/login.defs
  touch /usr/bin/passwd
  ./configure --sysconfdir=/etc   \
              --disable-static    \
              --with-{b,yes}crypt \
              --without-libbsd    \
              --disable-logind    \
              --with-group-name-max-length=32
  make
  make exec_prefix=/usr install
  make -C man install-man
  pwconv
  grpconv
  mkdir -p /etc/default
  useradd -D --gid 999
  touch /etc/sub{u,g}id
}

# ---- 8.31 Gawk ----
p_gawk() {
  sed -i 's/extras//' Makefile.in
  ./configure --prefix=/usr
  make
  chown -R tester .
  chk su tester -c "PATH=$PATH make check"
  rm -f /usr/bin/gawk-5.4.1
  make install
  ln -sv gawk.1 /usr/share/man/man1/awk.1
  install -vDm644 doc/{awkforai.txt,*.{eps,pdf,jpg}} -t /usr/share/doc/gawk-5.4.1
}

# ---- 8.32 GCC ----
p_gcc() {
  case $(uname -m) in
    x86_64)
      sed -e '/m64=/s/lib64/lib/' \
          -i.orig gcc/config/i386/t-linux64
    ;;
  esac
  mkdir -v build
  cd       build
  ../configure --prefix=/usr            \
               LD=ld                    \
               --enable-languages=c,c++ \
               --enable-default-pie     \
               --enable-default-ssp     \
               --enable-host-pie        \
               --enable-targets=all     \
               --disable-multilib       \
               --disable-bootstrap      \
               --disable-fixincludes    \
               --with-system-zlib
  make
  ulimit -s -H unlimited
  chown -R tester .
  chk su tester -c "PATH=$PATH make -k check"
  ../contrib/test_summary -t > /sources/logs/8.32-gcc-test-summary.txt 2>&1 || true
  grep -A7 Summ /sources/logs/8.32-gcc-test-summary.txt || true
  make install
  chown -v -R root:root $(gcc -print-file-name=include){,-fixed}
  ln -svr /usr/bin/cpp /usr/lib
  ln -sv gcc.1 /usr/share/man/man1/cc.1
  ln -sfvr $(gcc -print-prog-name=liblto_plugin.so) /usr/lib/bfd-plugins/
  # sanity checks (book 8.32), asserted
  echo 'int main(){}' | cc -x c - -v -Wl,--verbose &> dummy.log
  readelf -l a.out | grep ': /lib'
  readelf -l a.out | grep -q '\[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2\]' || { echo "SANITY: interp wrong"; exit 1; }
  grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log
  [ "$(grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log | wc -l)" = 3 ] || { echo "SANITY: start files"; exit 1; }
  grep -B4 '^ /usr/include' dummy.log
  grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
  grep "/lib.*/libc.so.6 " dummy.log
  grep -q "attempt to open /usr/lib/libc.so.6 succeeded" dummy.log || { echo "SANITY: wrong libc"; exit 1; }
  grep found dummy.log
  grep -q "found ld-linux-x86-64.so.2 at /usr/lib/ld-linux-x86-64.so.2" dummy.log || { echo "SANITY: wrong ld"; exit 1; }
  echo "=== GCC SANITY CHECKS PASSED"
  rm -v a.out dummy.log
  mkdir -pv /usr/share/gdb/auto-load/usr/lib
  mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
}

T0=$SECONDS
track 8.22 binutils-2.47      binutils-2.47.tar.xz      binutils-2.47      p_binutils
track 8.23 gmp-6.3.0          gmp-6.3.0.tar.xz          gmp-6.3.0          p_gmp
track 8.24 mpfr-4.2.2         mpfr-4.2.2.tar.xz         mpfr-4.2.2         p_mpfr
track 8.25 mpc-1.4.1          mpc-1.4.1.tar.xz          mpc-1.4.1          p_mpc
track 8.26 attr-2.6.0         attr-2.6.0.tar.gz         attr-2.6.0         p_attr
track 8.27 acl-2.4.0          acl-2.4.0.tar.xz          acl-2.4.0          p_acl
track 8.28 libcap-2.78        libcap-2.78.tar.xz        libcap-2.78        p_libcap
track 8.29 libxcrypt-4.5.2    libxcrypt-4.5.2.tar.xz    libxcrypt-4.5.2    p_libxcrypt
track 8.30 shadow-4.20.2      shadow-4.20.2.tar.xz      shadow-4.20.2      p_shadow
track 8.31 gawk-5.4.1         gawk-5.4.1.tar.xz         gawk-5.4.1         p_gawk
track 8.32 gcc-16.2.0         gcc-16.2.0.tar.xz         gcc-16.2.0         p_gcc
echo "=== BATCH 2 DONE in $((SECONDS-T0))s"
echo "--- packages with test failures:"; ls $J/installed/*/testfail 2>/dev/null | sed 's|.*/installed/||;s|/testfail||' || true
echo "--- binutils FAIL lines:"; grep '^FAIL:' $L/8.22-binutils-2.47.log | head -20
echo "--- GCC summary:"; grep -E '^# of (expected passes|unexpected failures|unexpected successes)|=== .* Summary' $L/8.32-gcc-test-summary.txt | head -40
echo "--- GCC unexpected FAILs:"; grep '^FAIL:' $L/8.32-gcc-test-summary.txt | head -60
echo ">>> NEXT: run 'passwd root' (book 8.30.3)"
