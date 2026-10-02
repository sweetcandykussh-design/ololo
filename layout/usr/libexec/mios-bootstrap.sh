#!/bin/sh
# Bring up the miOS daemons at install time (no reboot — palera1n/rootless safe) and log verbosely so the
# result is readable in Filza without a terminal. No respring / userspace reboot is ever performed.
#
# This whole script is already launched FULLY DETACHED by postinst (setsid, stdio to /dev/null, &), so it
# runs off the installer's critical path and "Configuring" returns instantly. Therefore we do all the
# work INLINE here — no further backgrounded grandchild processes. An earlier version launched the
# support-daemon restart as a detached grandchild (setsid sh restart.sh &); that grandchild never
# produced its restart.log at all — it was being torn down before it could write even its first line.
# Doing the work inline in this (proven-surviving) script fixes that: install.log always reaches
# "=== end ===", so inline restart code here runs to completion too.
BASE=/var/mobile/Library/Preferences/MiOS
LOGDIR="$BASE/debug"
LOG="$LOGDIR/install.log"
RLOG="$LOGDIR/restart.log"
mkdir -p "$LOGDIR"

find_launchctl() {
  for L in /var/jb/usr/bin/launchctl /usr/bin/launchctl /bin/launchctl; do
    [ -x "$L" ] && { echo "$L"; return; }
  done
}

# Snapshot the target daemons so we can PROVE whether they are actually (re)spawned.
snap() {
  echo "-- $1 $(date) --" >> "$RLOG"
  ps -Axo pid,uid,comm 2>/dev/null | grep -iE 'securityd|containermanagerd|cfprefsd|[l]sd' >> "$RLOG" 2>/dev/null \
    || ps ax 2>/dev/null | grep -iE 'securityd|containermanagerd|cfprefsd|[l]sd' >> "$RLOG" 2>/dev/null \
    || echo "(ps unavailable)" >> "$RLOG"
}

# ---- STEP 1: bring up our own miosd container daemon. Non-fatal and NON-BLOCKING. -------------------
{
  echo "=== miOS bootstrap $(date) ==="

  # Clear any stale watchdog arm files. A fresh install is a clean slate; a leftover arm (e.g. an
  # on-demand daemon that exited before an older build cleared it) must not keep the new build disabled.
  rm -f "$BASE"/boot_armed* 2>/dev/null && echo "cleared stale boot_armed* files"

  if [ -f "$BASE/enable_daemons" ]; then
    echo "+ enable_daemons present → will restart support daemons inline (see restart.log)"
  else
    echo "+ enable_daemons absent → NOT touching system daemons (safe default)"
  fi

  LCTL="$(find_launchctl)"
  echo "launchctl: ${LCTL:-NOT FOUND}"

  PL=/var/jb/Library/LaunchDaemons/com.mios.containerd.plist
  [ -f "$PL" ] || PL=/Library/LaunchDaemons/com.mios.containerd.plist
  echo "plist: $PL"
  ls -l "$PL" 2>&1
  echo "binary:"
  ls -l /var/jb/usr/libexec/miosd 2>&1

  if [ -n "$LCTL" ]; then
    # palera1n loads /var/jb LaunchDaemons into the GUI (user/foreground) domain, not system. bootstrap
    # is a no-op once loaded. Each kickstart is BACKGROUNDED so a stuck launchctl on the user/foreground
    # domain can never hang this script. We never run `launchctl print` (it was a hang culprit before).
    echo "+ bootstrap system"; "$LCTL" bootstrap system "$PL" 2>&1
    for DOM in system gui/501 user/501; do
      echo "+ kickstart $DOM (detached)"
      ( "$LCTL" kickstart -k "$DOM/com.mios.containerd" >/dev/null 2>&1 ) &
    done
  fi

  echo "=== end ==="
} >> "$LOG" 2>&1

# ---- STEP 2: restart the Crane-style support daemons INLINE (only when opted in) --------------------
# Gated on enable_daemons so a default install never touches a system daemon. Written to its own
# restart.log with ps snapshots before/after, so it is unambiguous whether securityd/containermanagerd
# are actually (re)spawned.
if [ -f "$BASE/enable_daemons" ]; then
  {
    echo "=== restart start $(date) ==="
    LCTL="$(find_launchctl)"
    echo "launchctl: ${LCTL:-NONE}"
    snap "BEFORE"

    # Crane's own mechanism (killallProcessesWithName): kill any running instance so launchd respawns it
    # injected on next demand. securityd is usually NOT running (it spawns per keychain op), so "none".
    for D in containermanagerd securityd cfprefsd lsd; do
      if killall -9 "$D" 2>/dev/null; then echo "killall $D: ok"
      else echo "killall $D: not running"; fi
    done

    # Force the on-demand daemons to start RIGHT NOW so a fresh (hopefully injected) process exists even
    # before an app demands it. Each backgrounded so a stuck launchctl can't hang us; capture rc.
    if [ -n "$LCTL" ]; then
      for S in system/com.apple.containermanagerd system/com.apple.securityd system/com.apple.cfprefsd.xpc.daemon; do
        ( "$LCTL" kickstart "$S" >/dev/null 2>&1; echo "kickstart $S rc=$?" >> "$RLOG" ) &
      done
    fi

    sleep 5
    snap "AFTER"
    echo "=== restart done $(date) ==="
  } >> "$RLOG" 2>&1
fi

chown -R 501:501 "$LOGDIR" 2>/dev/null
exit 0
