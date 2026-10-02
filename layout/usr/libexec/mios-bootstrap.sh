#!/bin/sh
# Bring up the miOS container daemon at install time (no reboot — palera1n/rootless safe) and log
# verbosely so the result is readable in Filza without a terminal. No respring is performed.
BASE=/var/mobile/Library/Preferences/MiOS
LOGDIR="$BASE/debug"
LOG="$LOGDIR/install.log"
mkdir -p "$LOGDIR"

{
  echo "=== miOS bootstrap $(date) ==="

  # Clear any stale watchdog arm files. A fresh install is a clean slate; a leftover arm (e.g. an
  # on-demand daemon that exited before an older build cleared it) must not keep the new build disabled.
  rm -f "$BASE"/boot_armed* 2>/dev/null && echo "cleared stale boot_armed* files"

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

  if [ -f "$BASE/enable_daemons" ]; then
    echo "+ enable_daemons present → scheduling detached support-daemon restart"
  else
    echo "+ enable_daemons absent → NOT touching system daemons (safe default)"
  fi
  echo "=== end ==="
} >> "$LOG" 2>&1

# Only restart the Crane-style support daemons when daemon injection is explicitly opted in. By default
# (no enable_daemons file) we never touch system daemons, so a normal install can't affect boot at all.
# When opted in: do it detached + delayed so it never blocks the installer (killing securityd/cfprefsd
# synchronously inside postinst caused the long "Configuring" hang).
#
# IMPORTANT: a plain `killall` only re-execs a daemon that is CURRENTLY RUNNING. securityd and
# containermanagerd are on-demand (launchd starts them lazily), so if they are not running at install
# time, killall is a no-op and they never pick up the dylib until something demands them — which is why
# their support_*.log never appeared. `launchctl kickstart -k` FORCES launchd to (re)spawn the service
# even when it is not currently running, so the fresh process is injected right away. We fall back to
# killall if kickstart is unavailable or the label is unknown. MiOSSupport's own safe-mode +
# per-daemon boot-watchdog still protect against a bad hook on that forced spawn.
if [ -f "$BASE/enable_daemons" ]; then
  RS="$BASE/.mios-restart.sh"
  cat > "$RS" <<'RSEOF'
#!/bin/sh
LOG="$1"
LCTL=""
for L in /var/jb/usr/bin/launchctl /usr/bin/launchctl /bin/launchctl; do
  [ -x "$L" ] && LCTL="$L" && break
done
# Give the installer time to finish and the filesystem to settle before we touch system daemons.
sleep 12
# kick <launchd-label> <process-name>: force a fresh, injected (re)spawn; fall back to killall.
kick() {
  _done=0
  if [ -n "$LCTL" ]; then
    for DOM in system gui/501 user/501; do
      if "$LCTL" kickstart -k "$DOM/$1" 2>/dev/null; then
        echo "kickstart $DOM/$1 ok" >> "$LOG"; _done=1; break
      fi
    done
  fi
  if [ "$_done" = 0 ]; then
    killall -9 "$2" 2>/dev/null && echo "killall $2 ok" >> "$LOG" || echo "kick $2 noop (not running / no kickstart)" >> "$LOG"
  fi
}
kick com.apple.containermanagerd      containermanagerd
kick com.apple.securityd              securityd
kick com.apple.cfprefsd.xpc.daemon    cfprefsd
# lsd restarts itself constantly; a plain killall is enough and avoids guessing its label.
killall -9 lsd 2>/dev/null && echo "killall lsd ok" >> "$LOG"
echo "restart pass done $(date)" >> "$LOG"
RSEOF
  chmod 0755 "$RS" 2>/dev/null
  if command -v setsid >/dev/null 2>&1; then
    setsid /bin/sh "$RS" "$LOG" >/dev/null 2>&1 </dev/null &
  else
    /bin/sh "$RS" "$LOG" >/dev/null 2>&1 </dev/null &
  fi
fi

chown -R 501:501 "$LOGDIR" 2>/dev/null
exit 0
