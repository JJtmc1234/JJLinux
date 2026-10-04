#!/bin/bash
# JJLinux - LFS 13.1-systemd: 5.5 sanity gate, 5.6 Libstdc++, Chapter 6 (6.2-6.18)
# Book commands verbatim. Run as user lfs (in tmux):  bash ~/lfs-ch5-6.sh
set +h
umask 022
S=$LFS/sources
L=$S/logs
die() { echo "!!! STOP: $*"; exit 1; }

# ---- environment guard ----
[ "$(whoami)" = lfs ]             || die "not user lfs"
[ "$LFS" = /mnt/lfs ]             || die "LFS is '$LFS'"
[ "$LFS_TGT" = x86_64-lfs-linux-gnu ] || die "LFS_TGT is '$LFS_TGT'"
case "$PATH" in /mnt/lfs/tools/bin:*) ;; *) die "PATH is '$PATH'";; esac
mkdir -p $L

# ---- 5.5 sanity gate (book checks, asserted) ----
T=$(mktemp -d); cd $T
echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log || die "test compile failed"
$LFS_TGT-readelf -l a.out | grep -q '\[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2\]' || die "interp wrong"
[ "$(grep -E -o "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log | wc -l)" = 3 ] || die "start files wrong"
grep -q "attempt to open /mnt/lfs/usr/lib/libc.so.6 succeeded" dummy.log || die "wrong libc"
grep -q "found ld-linux-x86-64.so.2 at /mnt/lfs/usr/lib/ld-linux-x86-64.so.2" dummy.log || die "wrong dynamic linker"
grep 'SEARCH.*/usr/lib' dummy.log | sed 's|; |\n|g' | grep SEARCH_DIR | grep -qv 'SEARCH_DIR("=' && die "SEARCH_DIR without ="
cd /; rm -rf $T
rm -rf $S/glibc-2.44
echo "=== 5.5 sanity gate: PASS"

# ---- runner ----
# build <log-id> <tarball> <srcdir> <function>
build() {
  local id=$1 tarball=$2 dir=$3 fn=$4 t0=$SECONDS
  cd $S && rm -rf $dir && tar -xf $tarball && cd $dir || die "$id: unpack failed"
  echo "=== $id ..."
  ( set -e; $fn ) > $L/$id.log 2>&1
  local rc=$?
  [ $rc = 0 ] || { tail -30 $L/$id.log; die "$id failed (rc=$rc), source kept in $S/$dir, log $L/$id.log"; }
  cd $S && rm -rf $dir
  printf "=== %-28s OK  %4ss\n" "$id" $((SECONDS-t0)) | tee -a $L/ch5-6-summary.txt
}

# ---- 5.6 Libstdc++ ----
p_libstdcxx() {
  mkdir -v build
  cd       build
  ../libstdc++-v3/configure      \
      --host=$LFS_TGT            \
      --build=$(../config.guess) \
      CXX=$LFS_TGT-gcc           \
      --prefix=/usr              \
      --disable-multilib         \
      --disable-nls              \
      --disable-libstdcxx-pch    \
      --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/16.2.0
  make
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

# ---- 6.2 M4 ----
p_m4() {
  cat > $LFS/usr/share/config.site << EOF
ac_cv_func_posix_spawn_file_actions_addchdir=yes
ac_cv_func_posix_spawn_file_actions_addfchdir=yes
EOF
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.3 Ncurses ----
p_ncurses() {
  mkdir build
  pushd build
    ../configure --prefix=$LFS/tools AWK=gawk
    make -C include
    make -C progs tic
    install progs/tic $LFS/tools/bin
  popd
  ./configure --prefix=/usr                \
              --host=$LFS_TGT              \
              --build=$(./config.guess)    \
              --mandir=/usr/share/man      \
              --with-manpage-format=normal \
              --with-shared                \
              --without-normal             \
              --with-cxx-shared            \
              --without-debug              \
              --without-ada                \
              --disable-stripping          \
              AWK=gawk
  make
  make DESTDIR=$LFS install
  ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
  sed -e 's/^#if.*XOPEN.*$/#if 1/' \
      -i $LFS/usr/include/curses.h
}

# ---- 6.4 Bash ----
p_bash() {
  ./configure --prefix=/usr                      \
              --build=$(sh support/config.guess) \
              --host=$LFS_TGT                    \
              --without-bash-malloc              \
              --docdir=/usr/share/doc/bash-5.3
  make
  make DESTDIR=$LFS install
  ln -sv bash $LFS/bin/sh
}

# ---- 6.5 Coreutils ----
p_coreutils() {
  ./configure --prefix=/usr                     \
              --host=$LFS_TGT                   \
              --build=$(build-aux/config.guess) \
              --enable-install-program=hostname
  make
  make DESTDIR=$LFS install
  mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
  mkdir -pv $LFS/usr/share/man/man8
  mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
  sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
}

# ---- 6.6 Diffutils ----
p_diffutils() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              gl_cv_func_strcasecmp_works=yes \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.7 File ----
p_file() {
  mkdir build
  pushd build
    ../configure --disable-bzlib      \
                 --disable-libseccomp \
                 --disable-xzlib      \
                 --disable-zlib
    make
  popd
  ./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
  make FILE_COMPILE=$(pwd)/build/src/file
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/libmagic.la
}

# ---- 6.8 Findutils ----
p_findutils() {
  ./configure --prefix=/usr                   \
              --localstatedir=/var/lib/locate \
              --host=$LFS_TGT                 \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.9 Gawk ----
p_gawk() {
  sed -i 's/extras//' Makefile.in
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.10 Grep ----
p_grep() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.11 Gzip ----
p_gzip() {
  ./configure --prefix=/usr --host=$LFS_TGT
  make
  make DESTDIR=$LFS install
}

# ---- 6.12 Make ----
p_make() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.13 Patch ----
p_patch() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.14 Sed ----
p_sed() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.15 Tar ----
p_tar() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

# ---- 6.16 Xz ----
p_xz() {
  ./configure --prefix=/usr                     \
              --host=$LFS_TGT                   \
              --build=$(build-aux/config.guess) \
              --disable-static                  \
              --docdir=/usr/share/doc/xz-5.8.3
  make
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/liblzma.la
}

# ---- 6.17 Binutils pass 2 ----
p_binutils2() {
  sed '6031s/$add_dir//' -i ltmain.sh
  mkdir -v build
  cd       build
  ../configure                   \
      --prefix=/usr              \
      --build=$(../config.guess) \
      --host=$LFS_TGT            \
      --disable-nls              \
      --enable-shared            \
      --enable-gprofng=no        \
      --disable-werror           \
      --enable-64-bit-bfd        \
      --enable-new-dtags         \
      --enable-default-hash-style=gnu
  make
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

# ---- 6.18 GCC pass 2 ----
p_gcc2() {
  tar -xf ../mpfr-4.2.2.tar.xz
  mv -v mpfr-4.2.2 mpfr
  tar -xf ../gmp-6.3.0.tar.xz
  mv -v gmp-6.3.0 gmp
  tar -xf ../mpc-1.4.1.tar.xz
  mv -v mpc-1.4.1 mpc
  case $(uname -m) in
    x86_64)
      sed -e '/m64=/s/lib64/lib/' \
          -i.orig gcc/config/i386/t-linux64
    ;;
  esac
  mkdir -v build
  cd       build
  ../configure                   \
      --build=$(../config.guess) \
      --host=$LFS_TGT            \
      --target=$LFS_TGT          \
      --prefix=/usr              \
      --with-build-sysroot=$LFS  \
      --enable-default-pie       \
      --enable-default-ssp       \
      --disable-fixincludes      \
      --disable-nls              \
      --disable-multilib         \
      --disable-libatomic        \
      --disable-libgomp          \
      --disable-libquadmath      \
      --disable-libsanitizer     \
      --disable-libssp           \
      --disable-libvtv           \
      --enable-languages=c,c++   \
      CXX_FOR_TARGET="$LFS_TGT-gcc -nostdinc++" \
      LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc \
      target_configargs=gcc_cv_target_thread_file=posix
  make
  make DESTDIR=$LFS install
  ln -sv gcc $LFS/usr/bin/cc
}

: > $L/ch5-6-summary.txt
T0=$SECONDS
build 5.06-libstdcxx     gcc-16.2.0.tar.xz      gcc-16.2.0      p_libstdcxx
build 6.02-m4            m4-1.4.21.tar.xz       m4-1.4.21       p_m4
build 6.03-ncurses       ncurses-6.6.tar.gz     ncurses-6.6     p_ncurses
build 6.04-bash          bash-5.3.tar.gz        bash-5.3        p_bash
build 6.05-coreutils     coreutils-9.11.tar.xz  coreutils-9.11  p_coreutils
build 6.06-diffutils     diffutils-3.12.tar.xz  diffutils-3.12  p_diffutils
build 6.07-file          file-5.48.tar.gz       file-5.48       p_file
build 6.08-findutils     findutils-4.11.0.tar.xz findutils-4.11.0 p_findutils
build 6.09-gawk          gawk-5.4.1.tar.xz      gawk-5.4.1      p_gawk
build 6.10-grep          grep-3.12.tar.xz       grep-3.12       p_grep
build 6.11-gzip          gzip-1.14.tar.xz       gzip-1.14       p_gzip
build 6.12-make          make-4.4.1.tar.gz      make-4.4.1      p_make
build 6.13-patch         patch-2.8.tar.xz       patch-2.8       p_patch
build 6.14-sed           sed-4.10.tar.xz        sed-4.10        p_sed
build 6.15-tar           tar-1.35.tar.xz        tar-1.35        p_tar
build 6.16-xz            xz-5.8.3.tar.xz        xz-5.8.3        p_xz
build 6.17-binutils-p2   binutils-2.47.tar.xz   binutils-2.47   p_binutils2
build 6.18-gcc-p2        gcc-16.2.0.tar.xz      gcc-16.2.0      p_gcc2
echo "=== ALL DONE in $((SECONDS-T0))s"
ls -l $LFS/usr/bin/cc $LFS/bin/sh
