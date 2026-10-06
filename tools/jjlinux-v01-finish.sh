#!/bin/bash
# JJLinux v0.1 - finish after jjlinux-v01.sh (no reboots): run on NEXUS
#   bash ~/Downloads/jjlinux-v01-finish.sh
# Reuses the boot/rescue/emergency results from the last run, redoes only the 'less' rebuild
# (now at the original build path + stripped-code comparison), fixes the repo, commits, tags v0.1.
set -u
H=jl1
REPO=~/Projects/jjlinux
V01=~/Downloads/jjlinux-v01.sh
UPD=~/Downloads/jjlinux-repo-update.tar.gz
rs(){ ssh -o ConnectTimeout=5 -o BatchMode=yes $H "$@"; }
say(){ printf '\n=== %s\n' "$*"; }

MD=$(ls -t /tmp/tmp.*/V0.1-VALIDATION.md 2>/dev/null | head -1)
[ -n "$MD" ] || { echo "!!! no V0.1-VALIDATION.md from the last run in /tmp"; exit 1; }
[ -f $V01 ] && grep -q code_differ $V01 || { echo "!!! re-download jjlinux-v01.sh (new version needed)"; exit 1; }
[ -f $UPD ] || { echo "!!! download jjlinux-repo-update.tar.gz to ~/Downloads first"; exit 1; }
echo "using results: $MD"

say "1/3 updating the remote helper and rebuilding 'less'"
sed -n "/<< 'REMOTE'/,/^REMOTE$/p" $V01 | sed '1d;$d' | rs 'sudo tee /sources/jjlinux-v01-remote.sh >/dev/null'
REB=$(rs 'sudo bash /sources/jjlinux-v01-remote.sh rebuild less-704' 2>&1 | tail -15); echo "$REB"
LINE=$(echo "$REB" | grep '^REBUILD' || echo "NOT VERIFIED")
sed -i "s#^| One package rebuilt.*#| One package rebuilt from documented steps | $LINE |#" $MD
grep -q '^Rebuild method' $MD || printf '\nRebuild method: JPM recipe re-run at the original build path into a DESTDIR, every file compared with the JPM sha256 record; ELF files that differ are stripped and compared with the installed file (debug-info-only differences are accepted, code differences are not).\n' >> $MD

say "2/3 checking criteria"
PASS=1
grep -q '| 10/10 |' $MD                          || { echo "FAIL: boots";     PASS=0; }
grep -q 'rescue.target state='  $MD              || { echo "FAIL: rescue";    PASS=0; }
grep -q 'emergency.target state=' $MD            || { echo "FAIL: emergency"; PASS=0; }
echo "$LINE" | grep -qE 'missing=0 extra=0 code_differ=0' || { echo "FAIL: rebuild"; PASS=0; }
cat $MD
[ $PASS = 1 ] || { say "NOT TAGGING - paste this output"; exit 1; }

say "3/3 ALL v0.1 CRITERIA PASSED - repo, commit, tag"
cd $REPO && git pull --ff-only || exit 1
tar -xzf $UPD                                    # recipes/, DEVIATIONS.md, docs/BASELINES.md (missing from the last push)
mkdir -p docs tools
cp $MD docs/V0.1-VALIDATION.md
cp $V01 ~/Downloads/jjlinux-v01-finish.sh tools/
rs 'cat /sources/jjlinux-v01-remote.sh' > tools/jjlinux-v01-remote.sh
grep -q '## v0.1 validation' DEVIATIONS.md || printf '\n## v0.1 validation\n- grub.cfg reads grubenv and honors a one-shot `next_entry`, so `grub-reboot` can select rescue/emergency boots (used for automated validation).\n- Rebuild check compares stripped code for ELF files: the original Ch. 8 binaries carry debug info that is not bit-reproducible.\n' >> DEVIATIONS.md
MED=$(grep -o 'Median boot time over the 10 boots: \*\*[0-9.]*s' $MD | grep -o '[0-9.]*s$')
grep -q '## v0.1 (' docs/BASELINES.md || printf '\n## v0.1 (%s)\n- Median boot over 10 boots: %s (range in V0.1-VALIDATION.md)\n' "$(date +%F)" "$MED" >> docs/BASELINES.md
git add -A && git status --short
git commit -m "JJLinux v0.1: validated (10/10 boots, rescue, emergency, recipe rebuild); add recipes, deviations, baselines" \
  && git tag -a v0.1 -m "JJLinux v0.1 - base system boots (median ${MED})" \
  && git push --follow-tags && say "v0.1 TAGGED AND PUSHED"
git ls-files | head -40
