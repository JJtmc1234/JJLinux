#!/bin/bash
# JJLinux - BLFS 13.1-systemd chunk 1: "self-sufficient networking"
#   libtasn1 -> p11-kit -> make-ca (+ CA store) -> libunistring -> libidn2 -> libpsl -> curl -> wget -> git
# Run on JJLinux as root (it survives SSH drops):
#   sudo systemd-run --unit=blfs-net --setenv=MAKEFLAGS=-j$(nproc) bash /sources/blfs-net.sh
#   journalctl -fu blfs-net
. /sources/jpm-track.sh
export MAKEFLAGS=${MAKEFLAGS:--j$(nproc)}

p_libtasn1() {
  ./configure --prefix=/usr --disable-static
  make
  chk make check
  make install
  make -C doc/reference install-data-local
}

p_p11kit() {
  sed '20,$ d' -i trust/trust-extract-compat
  cat >> trust/trust-extract-compat << "EOF"
# Copy existing anchor modifications to /etc/ssl/local
/usr/libexec/make-ca/copy-trust-modifications

# Update trust stores
/usr/sbin/make-ca -r
EOF
  mkdir p11-build
  cd    p11-build
  meson setup ..            \
        --prefix=/usr       \
        --buildtype=release \
        -D trust_paths=/etc/pki/anchors
  ninja
  chk ninja test
  ninja install
  ln -sfv /usr/libexec/p11-kit/trust-extract-compat \
          /usr/bin/update-ca-certificates
}

p_makeca() {
  sed '/mktemp/s/-t //' -i make-ca
  make install
  install -vdm755 /etc/ssl/local
  /usr/sbin/make-ca -g
  systemctl enable update-pki.timer
}

p_libunistring() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/libunistring-1.4.2
  make
  chk make check
  make install
}

p_libidn2() {
  ./configure --prefix=/usr --disable-static
  make
  chk make check
  make install
}

p_libpsl() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release
  ninja
  chk ninja test
  ninja install
}

p_curl() {
  ./configure --prefix=/usr    \
              --disable-static \
              --with-openssl   \
              --with-ca-path=/etc/ssl/certs
  make
  # test suite is optional in BLFS and long; skipped here
  make install
  rm -rf docs/examples/.deps
  find docs \( -name Makefile\* -o  \
               -name \*.1       -o  \
               -name \*.3       -o  \
               -name CMakeLists.txt \) -delete
  cp -v -R docs -T /usr/share/doc/curl-8.21.0
}

p_wget() {
  NEW_LINE='#if !defined OPENSSL_NO_SSL3_METHOD '
  NEW_LINE+='&& OPENSSL_VERSION_NUMBER < 0x40000000L'
  sed -i "/SSL3/c $NEW_LINE" src/openssl.c
  unset NEW_LINE
  ./configure --prefix=/usr      \
              --sysconfdir=/etc  \
              --with-ssl=openssl
  make
  chk make check
  make install
}

p_git() {
  # NO_RUST=1: rustc is not installed (BLFS command explanation)
  ./configure --prefix=/usr                   \
              --with-gitconfig=/etc/gitconfig \
              --with-python=python3           \
              --with-libpcre2
  make NO_RUST=1
  make NO_RUST=1 perllibdir=/usr/lib/perl5/5.44/site_perl install
}

T0=$SECONDS
track blfs libtasn1-4.21.0      libtasn1-4.21.0.tar.gz      libtasn1-4.21.0      p_libtasn1
track blfs p11-kit-0.26.5       p11-kit-0.26.5.tar.xz       p11-kit-0.26.5       p_p11kit
track blfs make-ca-1.16.1       make-ca-1.16.1.tar.gz       make-ca-1.16.1       p_makeca
track blfs libunistring-1.4.2   libunistring-1.4.2.tar.xz   libunistring-1.4.2   p_libunistring
track blfs libidn2-2.3.8        libidn2-2.3.8.tar.gz        libidn2-2.3.8        p_libidn2
track blfs libpsl-0.23.3        libpsl-0.23.3.tar.gz        libpsl-0.23.3        p_libpsl
track blfs curl-8.21.0          curl-8.21.0.tar.xz          curl-8.21.0          p_curl
track blfs wget-1.25.0          wget-1.25.0.tar.gz          wget-1.25.0          p_wget
track blfs git-2.55.0           git-2.55.0.tar.xz           git-2.55.0           p_git
echo "=== BLFS NET CHUNK DONE in $((SECONDS-T0))s"
curl -sI https://www.linuxfromscratch.org/ | head -1
git --version; wget --version | head -1
