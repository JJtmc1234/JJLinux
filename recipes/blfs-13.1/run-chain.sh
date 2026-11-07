#!/bin/bash
# JJLinux -- run BLFS stages C3 -> C4 -> C5 in the background, fixing known prerequisites first.
# Usage (VM, as jj):  sudo bash run-chain.sh        then:  tail -f ~/chain.log
# Safe to re-run: finished packages are skipped, and it refuses to start a second copy.
set -u
[ "$(id -u)" = 0 ] || { echo "Run with sudo:  sudo bash run-chain.sh"; exit 1; }
U=${SUDO_USER:-jj}; H=$(getent passwd "$U" | cut -d: -f6); LOG=$H/chain.log
cd "$H"

if pgrep -f 'blfs-c[345]-' >/dev/null; then echo "A stage is already running - watch it with: tail -f $LOG"; exit 0; fi
for f in blfs-c3-services.sh blfs-c4-qt6.sh blfs-c5-hyprland.sh; do
  [ -f "$H/$f" ] || { echo "Missing $H/$f - scp it from mother first"; exit 1; }
done

# prerequisite: docutils (BlueZ needs rst2man)
if ! command -v rst2man >/dev/null && ! command -v rst2man.py >/dev/null; then
  pip3 install --no-cache-dir docutils || { echo "docutils install failed"; exit 1; }
fi
if ! command -v rst2man >/dev/null && command -v rst2man.py >/dev/null; then
  ln -sf "$(command -v rst2man.py)" /usr/local/bin/rst2man
fi
echo "rst2man: $(command -v rst2man || command -v rst2man.py)"

echo "launching chain in the background; log: $LOG"
nohup bash -c "
  for f in blfs-c3-services.sh blfs-c4-qt6.sh blfs-c5-hyprland.sh; do
    echo; echo \"########## \$f  \$(date +%I:%M:%S\ %p) ##########\"
    bash $H/\$f || { echo \"########## \$f FAILED - fix and re-run: sudo bash run-chain.sh ##########\"; exit 1; }
  done
  echo '########## ALL STAGES DONE ##########'
" >> "$LOG" 2>&1 &
chown "$U" "$LOG" 2>/dev/null
sleep 1
echo "started (pid $!). Watch with:  tail -f $LOG"
