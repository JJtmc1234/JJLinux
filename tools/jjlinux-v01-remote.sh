#!/bin/bash
# JJLinux v0.1 remote helper (runs on JJLinux as root)
set -e
case "$1" in
grubpatch)
  G=/boot/grub/grub.cfg
  [ -f /boot/grub/grubenv ] || grub-editenv /boot/grub/grubenv create
  if ! grep -q next_entry $G; then
    cp -v $G $G.pre-v01
    sed -i '/^set timeout=5$/r /dev/stdin' $G << 'EOG'

# JJLinux: one-shot boot selection (used by grub-reboot)
if [ -s $prefix/grubenv ]; then
  load_env
fi
if [ "${next_entry}" ] ; then
   set default="${next_entry}"
   set next_entry=
   save_env next_entry
fi
EOG
  fi
  grep -n -A9 'one-shot' $G
  grub-editenv /boot/grub/grubenv list
  ;;
rebuild)
  ID=$2; R=/var/lib/jpm/installed/$ID
  [ -f $R/recipe ] || { echo "no JPM record for $ID"; exit 1; }
  TB=$(grep '^tarball=' $R/meta | cut -d= -f2)
  DIR=$(tar -tf /sources/$TB | head -1 | cut -d/ -f1)
  W=$(mktemp -d /var/tmp/jpm-rebuild.XXXX); D=$W/dest; mkdir -p $D
  # build at the ORIGINAL path (/sources/<dir>): the build path is compiled into debug info
  cd /sources && rm -rf "$DIR" && tar -xf $TB && cd "$DIR"
  . $R/recipe
  FN=$(head -1 $R/recipe | awk '{print $1}')
  chk(){ "$@" || true; }   # tests RUN (less: make check rebuilds with LESSTEST=1)
  make(){ case " $* " in *" install "*) command make DESTDIR=$D "$@";; *) command make "$@";; esac; }
  ( set -e; $FN ) > $W/build.log 2>&1 || { tail -20 $W/build.log; exit 1; }
  rec=0; same=0; diff=0; miss=0; cdiff=0
  while IFS=$'\t' read -r sum type mode own path; do
    rec=$((rec+1))
    if [ ! -e "$D$path" ] && [ ! -L "$D$path" ]; then miss=$((miss+1)); echo "MISSING $path"; continue; fi
    if [ "$sum" = - ] || [ "$(sha256sum "$D$path" | cut -d' ' -f1)" = "$sum" ]; then same=$((same+1)); continue; fi
    diff=$((diff+1))
    # byte difference: is it only debug info/symbols? compare stripped code against the live file
    if [ "$(head -c4 "$D$path" | od -An -c | tr -d ' ')" = '177ELF' ] \
       && strip --strip-unneeded -o $W/a "$D$path" && strip --strip-unneeded -o $W/b "$path" && cmp -s $W/a $W/b; then
      echo "DIFFERS (debug info only, stripped code identical) $path"
    else cdiff=$((cdiff+1)); echo "DIFFERS (CODE) $path"; fi
  done < $R/files
  extra=$( (cd $D && find . ! -type d | sed 's|^\.||') | sort | comm -23 - <(cut -f5 $R/files | sort) | tee $W/extra | wc -l)
  echo "REBUILD $ID: recorded=$rec identical=$same differ=$diff missing=$miss extra=$extra code_differ=$cdiff"
  cd /sources && rm -rf "$DIR" $W
  ;;
esac
