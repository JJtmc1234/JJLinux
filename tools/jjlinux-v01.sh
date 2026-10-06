#!/bin/bash
# JJLinux v0.1 validation - run on NEXUS (not in the VM):   bash ~/Downloads/jjlinux-v01.sh
#  1. GRUB: honor one-shot "next_entry" (so grub-reboot can pick rescue/emergency without a keyboard)
#  2. 10 normal reboots: each must come back over SSH with 0 failed units; boot time recorded
#  3. rescue.target and emergency.target boots, proven by a marker file written from inside each mode
#  4. rebuild one package (less) from its JPM recipe into a staging dir and compare with the JPM record
#  5. median boot time, results written to the repo, commit, tag v0.1, push
set -u
VM=LFS-13.1
H=jl1
REPO=$(ls -d ~/Projects/jjlinux ~/Projects/JJLinux 2>/dev/null | head -1)
OUT=$(mktemp -d); CSV=$OUT/boots.csv; echo "boot,total_s,failed_units" > $CSV
say(){ printf '\n=== %s\n' "$*"; }
rs(){ ssh -o ConnectTimeout=5 -o BatchMode=yes -o ServerAliveInterval=2 -o ServerAliveCountMax=2 $H "$@"; }
rb(){ timeout 15 ssh -o ConnectTimeout=5 -o BatchMode=yes $H "$@" 2>/dev/null; true; }   # reboot commands: never wait on a dying sshd

wait_down(){ for t in $(seq 60); do rs true 2>/dev/null || return 0; sleep 2; done; return 1; }
wait_up(){ for t in $(seq 90); do rs true 2>/dev/null && return 0; sleep 2; done; return 1; }
boot_time(){ # seconds as a decimal, waits until systemd says boot is finished
  for t in $(seq 30); do
    l=$(rs 'systemd-analyze 2>/dev/null | head -1')
    case "$l" in *"Startup finished"*)
      v=$(echo "$l" | grep -oE '= [0-9.]+m?s' | tr -d '= ')
      case "$v" in *ms) echo "$v" | awk '{printf "%.3f", $1/1000}';; *) echo "${v%s}";; esac; return;;
    esac; sleep 2; done; echo NA; }
kb(){ VBoxManage controlvm $VM keyboardputstring "$1"; VBoxManage controlvm $VM keyboardputscancode 1c 9c; sleep 2; }

read -rsp "JJLinux root password (for rescue/emergency mode): " RP; echo
rs true || { echo "!!! cannot reach $H - is JJLinux running?"; exit 1; }

say "1/5 installing the remote helper + GRUB one-shot boot support"
rs 'sudo tee /sources/jjlinux-v01-remote.sh >/dev/null' << 'REMOTE'
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
REMOTE
rs 'sudo bash /sources/jjlinux-v01-remote.sh grubpatch' || { echo "!!! GRUB patch failed"; exit 1; }

say "2/5 ten normal boots"
for i in $(seq 10); do
  rb 'sudo systemctl reboot'; wait_down; sleep 3
  if wait_up; then
    t=$(boot_time); f=$(rs 'systemctl --failed --no-legend | wc -l')
    echo "$i,$t,$f" >> $CSV; echo "boot $i: ${t}s, failed units: $f"
  else echo "$i,FAIL,NA" >> $CSV; echo "boot $i: DID NOT COME BACK"; break; fi
done

for mode in rescue emergency; do
  n=1; [ $mode = emergency ] && n=2
  say "3/5 $mode boot (GRUB entry $n)"
  rb "sudo rm -f /root/v01-$mode.txt; sudo grub-reboot $n && sudo systemctl reboot"; wait_down
  sleep 35
  VBoxManage controlvm $VM screenshotpng $OUT/$mode.png
  kb "$RP"; sleep 3
  kb "mount -o remount,rw / ; echo \"\$(cat /proc/cmdline | grep -o 'systemd.unit=[a-z.]*') state=\$(systemctl is-system-running)\" > /root/v01-$mode.txt ; sync ; systemctl reboot"
  if wait_up; then echo "$mode marker: $(rs "sudo cat /root/v01-$mode.txt" 2>/dev/null || echo MISSING)"
  else echo "!!! JJLinux did not come back after $mode - check $OUT/$mode.png"; fi
done
unset RP

say "4/5 rebuild 'less' from its JPM recipe and compare"
REB=$(rs 'sudo bash /sources/jjlinux-v01-remote.sh rebuild less-704' 2>&1 | tail -15); echo "$REB"

say "5/5 results"
MED=$(tail -n +2 $CSV | cut -d, -f2 | grep -v -e FAIL -e NA | sort -n | awk '{a[NR]=$1} END{if(NR==0){print "NA"} else if(NR%2){print a[(NR+1)/2]} else {printf "%.3f", (a[NR/2]+a[NR/2+1])/2}}')
OK=$(tail -n +2 $CSV | awk -F, '$2!="FAIL" && $3=="0"' | wc -l)
RESC=$(rs 'sudo cat /root/v01-rescue.txt' 2>/dev/null); EMER=$(rs 'sudo cat /root/v01-emergency.txt' 2>/dev/null)
cat > $OUT/V0.1-VALIDATION.md << EOF
# JJLinux v0.1 validation ($(date +%F))

| Criterion | Result |
|---|---|
| Boots to login, 10/10, 0 failed units | $OK/10 |
| Rescue entry (rescue.target) | ${RESC:-NOT VERIFIED} |
| Emergency entry (emergency.target) | ${EMER:-NOT VERIFIED} |
| Network + DNS | verified 2026-10-05 (DHCP 10.0.2.15, linuxfromscratch.org resolves) |
| Non-root user with sudo | jj, NOPASSWD sudo verified |
| One package rebuilt from documented steps | $(echo "$REB" | grep '^REBUILD' || echo NOT VERIFIED) |

Median boot time over the 10 boots: **${MED}s**

Raw boot data:
\`\`\`
$(cat $CSV)
\`\`\`
EOF
cat $OUT/V0.1-VALIDATION.md
echo "screenshots: $OUT/rescue.png $OUT/emergency.png"

if [ -n "$REPO" ] && [ "$OK" = 10 ] && [ -n "$RESC" ] && [ -n "$EMER" ] && echo "$REB" | grep -qE 'missing=0 extra=0 code_differ=0'; then
  say "ALL v0.1 CRITERIA PASSED - committing and tagging"
  cd "$REPO" && git pull --ff-only
  mkdir -p docs tools && cp $OUT/V0.1-VALIDATION.md docs/ && rs 'cat /sources/jjlinux-v01-remote.sh' > tools/jjlinux-v01-remote.sh
  cp ~/Downloads/jjlinux-v01.sh tools/ 2>/dev/null
  printf '\n## v0.1 validation\n- grub.cfg reads grubenv and honors a one-shot `next_entry`, so `grub-reboot` can select rescue/emergency boots (used for automated validation).\n' >> DEVIATIONS.md
  printf '\n## v0.1 (%s)\n- Median boot over 10 boots: %ss\n' "$(date +%F)" "$MED" >> docs/BASELINES.md
  git add -A && git commit -m "JJLinux v0.1: validated (10/10 boots, rescue, emergency, recipe rebuild)" && git tag -a v0.1 -m "JJLinux v0.1 - base system boots" && git push --follow-tags
else
  say "NOT TAGGING - at least one criterion failed or repo not found (REPO=$REPO). Paste this output."
fi
