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

  echo "+ scheduling detached support-daemon restart (after install finishes)"
  echo "=== end ==="
} >> "$LOG" 2>&1

# Restart the Crane-style support daemons so MiOSSupport.dylib is injected, WITHOUT a reboot. This is
# done detached and delayed ON PURPOSE: killing securityd/cfprefsd/containermanagerd synchronously
# inside postinst blocks dpkg/Sileo (they use those daemons) → the long "Configuring" hang. We fully
# detach (new session, fds to /dev/null) so the installer's postinst returns immediately, then restart
# the daemons ~12s later once the install is done. launchd (KeepAlive) respawns each instantly.
RESTART='sleep 12; for D in containermanagerd cfprefsd securityd lsd; do killall -9 "$D" 2>/dev/null; done; echo "restarted $(date)" >> '"$LOG"
if command -v setsid >/dev/null 2>&1; then
  setsid /bin/sh -c "$RESTART" >/dev/null 2>&1 </dev/null &
else
  /bin/sh -c "$RESTART" >/dev/null 2>&1 </dev/null &
fi

chown -R 501:501 "$LOGDIR" 2>/dev/null
exit 0
