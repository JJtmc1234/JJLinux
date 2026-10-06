#!/bin/bash
# JJLinux v0.1.1 - run on NEXUS:   bash ~/Downloads/jjlinux-v011/jjlinux-v011-test.sh
# installs v0.1.1 on jl1, then proves: emergency gives a root shell with NO password and / rw,
# the init=/bin/bash entry works, a normal boot still has 0 failed units. Then commits + tags v0.1.1.
set -u
VM=LFS-13.1; H=jl1; REPO=~/Projects/jjlinux
K=$(cd "$(dirname "$0")" && pwd)
rs(){ ssh -o ConnectTimeout=5 -o BatchMode=yes -o ServerAliveInterval=2 -o ServerAliveCountMax=2 $H "$@"; }
rb(){ timeout 15 ssh -o ConnectTimeout=5 -o BatchMode=yes $H "$@" 2>/dev/null; true; }
say(){ printf '\n=== %s\n' "$*"; }
wait_down(){ for t in $(seq 60); do rs true 2>/dev/null || return 0; sleep 2; done; return 1; }
wait_up(){ for t in $(seq 90); do rs true 2>/dev/null && return 0; sleep 2; done; return 1; }
kb(){ VBoxManage controlvm $VM keyboardputstring "$1"; VBoxManage controlvm $VM keyboardputscancode 1c 9c; sleep 2; }
OUT=$(mktemp -d)
rs true || { echo "!!! cannot reach $H"; exit 1; }

say "1/4 installing v0.1.1 on JJLinux"
scp -q $K/jjlinux-v011.sh $H:/tmp/ && rs 'sudo install -m644 /tmp/jjlinux-v011.sh /sources/ && sudo bash /sources/jjlinux-v011.sh' | tee $OUT/install.log
grep -q '=== v0.1.1 INSTALLED' $OUT/install.log || { echo "!!! install failed"; exit 1; }

say "2/4 emergency boot - NO password is typed"
rb "sudo rm -f /root/v011-*.txt; sudo grub-reboot 2 && sudo systemctl reboot"; wait_down; sleep 35
VBoxManage controlvm $VM screenshotpng $OUT/emergency.png
kb 'echo "emergency: user=$(id -un) root=$(findmnt -no OPTIONS / | cut -d, -f1) state=$(systemctl is-system-running)" > /root/v011-emergency.txt; sync; systemctl reboot'
wait_up && EMER=$(rs 'sudo cat /root/v011-emergency.txt' 2>/dev/null); echo "marker: ${EMER:-MISSING}"

say "3/4 init=/bin/bash boot (entry 3)"
rb "sudo grub-reboot 3 && sudo systemctl reboot"; wait_down; sleep 25
VBoxManage controlvm $VM screenshotpng $OUT/shell.png
kb 'echo "shell: pid=$$ init=$0" > /root/v011-shell.txt; sync'
sleep 3; VBoxManage controlvm $VM reset                    # no systemd = no 'reboot'; data is synced
wait_up && SHELLM=$(rs 'sudo cat /root/v011-shell.txt' 2>/dev/null); echo "marker: ${SHELLM:-MISSING}"
sleep 10; FAILED=$(rs 'systemctl --failed --no-legend | wc -l'); echo "normal boot after reset: failed units: $FAILED"

say "4/4 verdict"
PASS=1
echo "${EMER:-}"   | grep -q 'user=root root=rw'      || { echo "FAIL: emergency (password prompt? check $OUT/emergency.png)"; PASS=0; }
echo "${SHELLM:-}" | grep -q 'pid=1 init=/bin/bash'   || { echo "FAIL: init=/bin/bash (check $OUT/shell.png)"; PASS=0; }
[ "$FAILED" = 0 ]                                     || { echo "FAIL: failed units after reset"; PASS=0; }
grep -q 'less: normal build' $OUT/install.log         || { echo "FAIL: less"; PASS=0; }
[ $PASS = 1 ] || { say "NOT TAGGING - paste this output"; exit 1; }

say "ALL v0.1.1 CHECKS PASSED - commit + tag"
cd $REPO && git pull --ff-only || exit 1
cp $K/lfs-ch8-3.sh $K/lfs-ch9-11.sh recipes/lfs-13.1/
mkdir -p recipes/jjlinux && cp $K/jjlinux-v011.sh recipes/jjlinux/ && cp $K/jjlinux-v011-test.sh tools/
cat >> DEVIATIONS.md << 'EOF'

## v0.1.1
- 8.45 less: `make clean && make` after `make check` - less 704's `make check` rebuilds less with LESSTEST=1 (-DLESSTEST -DUSE_TERMCAP), so the book's following `make install` installs the test build. Found by the v0.1 recipe-rebuild check; reinstalled as JPM id less-704-r1.
- JJLinux rule: emergency boot never asks for a password and is never disabled. emergency.service drop-in (10-jjlinux-nopasswd.conf) replaces sulogin with a root bash and remounts / rw. Anyone at the console gets root - intended.
- grub.cfg: emergency entry boots `rw`; new last-resort entry `rw init=/bin/bash` (works even if systemd is broken). The one-shot `next_entry` block is now part of the Ch. 10 recipe.
EOF
cat >> docs/V0.1-VALIDATION.md << EOF

## v0.1.1 ($(date +%F))
- Emergency, no password typed: \`$EMER\`
- init=/bin/bash entry: \`$SHELLM\`
- less: normal build installed (less-704-r1)
EOF
git add -A && git status --short
git commit -m "JJLinux v0.1.1: passwordless emergency + init=/bin/bash entry, less installs the normal build" \
  && git tag -a v0.1.1 -m "JJLinux v0.1.1 - emergency never locked" && git push --follow-tags && say "v0.1.1 TAGGED AND PUSHED"
