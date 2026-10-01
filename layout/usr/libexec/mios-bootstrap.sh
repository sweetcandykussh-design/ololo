#!/bin/sh
# Bring up the miOS container daemon at install time (no reboot — palera1n/rootless safe) and log
# verbosely so the result is readable in Filza without a terminal.
LOGDIR=/var/mobile/Library/Preferences/MiOS/debug
LOG="$LOGDIR/install.log"
mkdir -p "$LOGDIR"

{
  echo "=== miOS bootstrap $(date) ==="

  LCTL=""
  for L in /var/jb/usr/bin/launchctl /usr/bin/launchctl /bin/launchctl; do
    if [ -x "$L" ]; then LCTL="$L"; echo "launchctl: $L"; break; fi
  done
  [ -z "$LCTL" ] && echo "launchctl: NOT FOUND"

  PL=/var/jb/Library/LaunchDaemons/com.mios.containerd.plist
  [ -f "$PL" ] || PL=/Library/LaunchDaemons/com.mios.containerd.plist
  echo "plist: $PL"
  ls -l "$PL" 2>&1
  echo "binary:"
  ls -l /var/jb/usr/libexec/miosd 2>&1

  if [ -n "$LCTL" ]; then
    echo "+ enable";    "$LCTL" enable system/com.mios.containerd 2>&1
    echo "+ bootout (clear any stale)"; "$LCTL" bootout system/com.mios.containerd 2>&1
    echo "+ bootstrap"; "$LCTL" bootstrap system "$PL" 2>&1
    echo "+ kickstart"; "$LCTL" kickstart -kp system/com.mios.containerd 2>&1
    echo "+ print";     "$LCTL" print system/com.mios.containerd 2>&1 | head -40
  fi

  echo "=== end ==="
} >> "$LOG" 2>&1

chown -R 501:501 "$LOGDIR" 2>/dev/null
# Respring only (not a reboot) so the tweak reloads cleanly.
killall -9 SpringBoard 2>/dev/null
exit 0
