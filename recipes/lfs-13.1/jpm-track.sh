# JJLinux - JPM tracking v0 ("snapshot diff"). Sourced by the Chapter 8 batch scripts.
# Runs inside the LFS chroot as root. Pure bash + coreutils + findutils (no Python: Ch. 8 rebuilds it).
#
# Records live in /var/lib/jpm:
#   baseline.files                  every file present before Ch. 8 (temporary system, untracked)
#   index                           path<TAB>owner  (owner = package id, or "temporary-system")
#   installed/<id>/meta             key=value: name, version, section, tarball, sha256, times, rc, tests, log
#   installed/<id>/recipe           the exact bash function that built and installed the package
#   installed/<id>/files            sha256<TAB>type<TAB>mode<TAB>owner:group<TAB>path   (created or changed)
#   installed/<id>/removed          paths that disappeared during the install
#   installed/<id>/modified-by      path<TAB>previous-owner  (files this package overwrote)

set +h
umask 022
S=/sources
L=$S/logs
J=/var/lib/jpm
BOOK="LFS-13.1-systemd"
die() { echo "!!! STOP: $*"; exit 1; }

[ "$(id -u)" = 0 ]                     || die "not root"
grep -q AGENTIC /README.md 2>/dev/null || die "not inside the LFS chroot"
[ -d /mnt/lfs ] && die "this looks like the host, not the chroot"
mkdir -p $J/installed $L

# List every tracked path (one per line, sorted). Build scratch, virtual fs, home dirs and JPM itself are excluded.
jpm_scan() {
  find / -xdev \( -path /sources -o -path /proc -o -path /sys -o -path /dev -o -path /run \
                  -o -path /tmp -o -path /var/tmp -o -path /root -o -path /home -o -path $J \
                  -o -path /var/log -o -path /var/cache -o -path /var/lib/systemd \) -prune \
         -o -print | LC_ALL=C sort
}

# One-time baseline: everything that exists now belongs to the Ch. 5-7 temporary system.
jpm_baseline() {
  [ -f $J/baseline.files ] && return 0
  jpm_scan > $J/baseline.files
  awk '{print $0 "\ttemporary-system"}' $J/baseline.files > $J/index
  echo "=== JPM baseline: $(wc -l < $J/baseline.files) pre-Ch.8 paths marked temporary-system"
}

# Test runner: tests never stop the build (the book expects some failures); results are recorded and reviewed.
chk() {
  echo ">>> TEST: $*"
  if "$@"; then echo ">>> TEST OK: $*"; else echo ">>> TEST FAILED (rc=$?): $*"; echo "$*" >> $TESTFAIL; fi
  return 0
}

# track <section> <id> <tarball|-> <srcdir|-> <function>
track() {
  local sec=$1 id=$2 tarball=$3 dir=$4 fn=$5 t0=$SECONDS
  local R=$J/installed/$id W=$J/work
  [ -e $R/meta ] && { echo "=== $sec $id already tracked, skipping"; return 0; }
  rm -rf $W && mkdir -p $W
  TESTFAIL=$W/testfail; : > $TESTFAIL
  cd $S || die "no $S"
  if [ "$dir" != - ]; then rm -rf $dir && tar -xf $tarball && cd $dir || die "$id: unpack failed"; fi

  jpm_scan > $W/before
  touch $W/marker; sleep 1
  echo "=== $sec $id ..."
  local start; start=$(date -u +%FT%TZ)
  ( set -e; $fn ) > $L/$sec-$id.log 2>&1
  local rc=$?
  [ $rc = 0 ] || { tail -40 $L/$sec-$id.log; die "$sec $id failed (rc=$rc). Source kept in $S/$dir, log $L/$sec-$id.log"; }
  jpm_scan > $W/after

  # created, removed, changed (ctime survives cp -a / install -p, so nothing slips through)
  LC_ALL=C comm -13 $W/before $W/after > $W/new
  LC_ALL=C comm -23 $W/before $W/after > $W/removed
  find / -xdev \( -path /sources -o -path /proc -o -path /sys -o -path /dev -o -path /run \
                  -o -path /tmp -o -path /var/tmp -o -path /root -o -path /home -o -path $J \
                  -o -path /var/log -o -path /var/cache -o -path /var/lib/systemd \) -prune \
         -o ! -type d -cnewer $W/marker -print | LC_ALL=C sort > $W/cnew
  LC_ALL=C comm -23 $W/cnew $W/new > $W/changed
  cat $W/new $W/changed | LC_ALL=C sort -u > $W/touched

  mkdir -p $R
  # file records: stat for everything, sha256 for regular files
  xargs -d '\n' -r stat -c '%n	%F	%a	%U:%G' < $W/touched > $W/stat
  awk -F'\t' '$2=="regular file" || $2=="regular empty file"{print $1}' $W/stat \
    | xargs -d '\n' -r sha256sum | sed 's/^\([0-9a-f]*\)  /\1\t/' > $W/sums
  awk -F'\t' 'FNR==NR{h[$2]=$1; next} {s=($1 in h)?h[$1]:"-"; print s "\t" $2 "\t" $3 "\t" $4 "\t" $1}' \
    $W/sums $W/stat > $R/files
  cp $W/removed $R/removed
  # who did we overwrite?
  awk -F'\t' 'FNR==NR{c[$0]=1; next} ($1 in c){print $1 "\t" $2}' $W/changed $J/index > $R/modified-by
  # update index: drop touched + removed paths, then claim touched paths
  cat $W/touched $W/removed | awk -F'\t' 'FNR==NR{d[$0]=1; next} !($1 in d)' - $J/index > $W/index.new
  awk -v o="$id" '{print $0 "\t" o}' $W/touched >> $W/index.new
  LC_ALL=C sort -t'	' -k1,1 $W/index.new > $J/index

  local tsha=-; [ "$tarball" != - ] && tsha=$(sha256sum $S/$tarball | cut -d' ' -f1)
  local tests=passed; [ -s $TESTFAIL ] && tests="failures:$(wc -l < $TESTFAIL)"
  grep -q '>>> TEST:' $L/$sec-$id.log || tests=none
  cat > $R/meta <<EOF
name=${id%-*}
version=${id##*-}
id=$id
book=$BOOK
section=$sec
tarball=$tarball
tarball_sha256=$tsha
started=$start
finished=$(date -u +%FT%TZ)
build_rc=$rc
tests=$tests
files=$(wc -l < $R/files)
removed=$(wc -l < $R/removed)
overwrote=$(wc -l < $R/modified-by)
log=$L/$sec-$id.log
EOF
  [ -s $TESTFAIL ] && cp $TESTFAIL $R/testfail
  declare -f $fn > $R/recipe

  cd $S
  [ "$dir" != - ] && rm -rf $S/$dir
  printf "=== %-6s %-24s OK %5ss  files=%-5s tests=%s\n" "$sec" "$id" $((SECONDS-t0)) "$(wc -l < $R/files)" "$tests" \
    | tee -a $L/ch8-summary.txt
}
