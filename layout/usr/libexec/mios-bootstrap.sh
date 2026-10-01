#!/bin/sh
# Bring up the miOS container daemon at install time (no reboot — palera1n/rootless safe) and log
# verbosely so the result is readable in Filza without a terminal. No respring is performed.
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
    # palera1n loads /var/jb LaunchDaemons into the GUI (user/foreground) domain, not system, so try
    # both. bootstrap is a no-op once it's loaded; kickstart -k restarts the running daemon so a
    # reinstall actually re-execs the new binary.
    echo "+ bootstrap system"; "$LCTL" bootstrap system "$PL" 2>&1
    for DOM in system gui/501 user/501; do
      echo "+ kickstart $DOM"; "$LCTL" kickstart -k "$DOM/com.mios.containerd" 2>&1
    done
    for DOM in system gui/501 user/501; do
      if "$LCTL" print "$DOM/com.mios.containerd" >/dev/null 2>&1; then
        echo "+ running in domain: $DOM"; break
      fi
    done
  fi

  # Force the Crane-style support daemons to reload so MiOSSupport.dylib is injected now, without a
  # reboot (palera1n can't reboot). launchd (KeepAlive) respawns each one immediately. securityd and
  # cfprefsd restart causes a brief hiccup for the foreground app only; they are back in <1s.
  echo "+ restart support daemons for injection"
  for D in containermanagerd cfprefsd securityd lsd; do
    echo "  killall $D"; killall -9 "$D" 2>&1
  done

  echo "=== end ==="
} >> "$LOG" 2>&1

chown -R 501:501 "$LOGDIR" 2>/dev/null
exit 0
