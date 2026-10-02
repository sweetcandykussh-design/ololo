#!/bin/sh
# Bring up the miOS daemons at install time (no reboot — palera1n/rootless safe) and log verbosely so the
# result is readable in Filza without a terminal. No respring / userspace reboot is ever performed.
BASE=/var/mobile/Library/Preferences/MiOS
LOGDIR="$BASE/debug"
LOG="$LOGDIR/install.log"
mkdir -p "$LOGDIR"

# ---- STEP 1: restart the Crane-style support daemons FIRST, fully detached & independent -------------
# This MUST run no matter what happens in the rest of this script. It used to live at the very END, after
# a launchctl section for our own miosd that could HANG (launchctl kickstart/print against the
# user/foreground domain never returning). When that hung, this restart never executed — which is the
# real reason support_securityd.log / support_containermanagerd.log never appeared while support_lsd.log
# did (lsd respawns itself constantly via SpringBoard, so it eventually got an injected instance on its
# own; the on-demand daemons never did because nothing here ever re-execed them). Launching it first and
# detached guarantees it happens. Gated on enable_daemons so a default install never touches a daemon.
if [ -f "$BASE/enable_daemons" ]; then
  RS="$BASE/.mios-restart.sh"
  # NOTE: this logs to its OWN file (restart.log), with ps snapshots before/after, so we can PROVE
  # whether securityd/containermanagerd are actually (re)spawned — independent of install.log capture
  # timing. The first line is written immediately (before any sleep) so an early Filza grab still shows
  # that the script started.
  cat > "$RS" <<'RSEOF'
#!/bin/sh
RLOG="$1"
snap() {   # append a ps snapshot of our target daemons
  echo "-- $1 $(date) --" >> "$RLOG"
  ps -Axo pid,uid,comm 2>/dev/null | grep -iE 'securityd|containermanagerd|cfprefsd|[l]sd' >> "$RLOG" 2>/dev/null \
    || ps ax 2>/dev/null | grep -iE 'securityd|containermanagerd|cfprefsd|[l]sd' >> "$RLOG" 2>/dev/null \
    || echo "(ps unavailable)" >> "$RLOG"
}
echo "=== restart start $(date) ===" > "$RLOG"
snap "BEFORE"
sleep 8                        # let the installer finish and the filesystem settle
LCTL=""
for L in /var/jb/usr/bin/launchctl /usr/bin/launchctl /bin/launchctl; do [ -x "$L" ] && LCTL="$L" && break; done
echo "launchctl: ${LCTL:-NONE}" >> "$RLOG"
# Crane's own mechanism (killallProcessesWithName): kill a running instance so launchd respawns it
# injected on next demand. securityd is usually NOT running (spawns per keychain op), so expect "none".
for D in containermanagerd securityd cfprefsd lsd; do
  if killall -9 "$D" 2>/dev/null; then echo "killall $D: ok" >> "$RLOG"
  else echo "killall $D: not running" >> "$RLOG"; fi
done
# Force the on-demand daemons to start RIGHT NOW so a fresh (hopefully injected) process exists even
# before an app demands it. Each backgrounded so a stuck launchctl can't hang us; capture return code.
if [ -n "$LCTL" ]; then
  for S in system/com.apple.containermanagerd system/com.apple.securityd system/com.apple.cfprefsd.xpc.daemon; do
    ( "$LCTL" kickstart "$S" >/dev/null 2>&1; echo "kickstart $S rc=$?" >> "$RLOG" ) &
  done
fi
sleep 4
snap "AFTER"
echo "=== restart done $(date) ===" >> "$RLOG"
RSEOF
  chmod 0755 "$RS" 2>/dev/null
  RLOG="$LOGDIR/restart.log"
  if command -v setsid >/dev/null 2>&1; then
    setsid /bin/sh "$RS" "$RLOG" >/dev/null 2>&1 </dev/null &
  else
    /bin/sh "$RS" "$RLOG" >/dev/null 2>&1 </dev/null &
  fi
fi

# ---- STEP 2: bring up our own miosd container daemon. Non-fatal and NON-BLOCKING. -------------------
{
  echo "=== miOS bootstrap $(date) ==="

  # Clear any stale watchdog arm files. A fresh install is a clean slate; a leftover arm (e.g. an
  # on-demand daemon that exited before an older build cleared it) must not keep the new build disabled.
  rm -f "$BASE"/boot_armed* 2>/dev/null && echo "cleared stale boot_armed* files"

  if [ -f "$BASE/enable_daemons" ]; then
    echo "+ enable_daemons present → support-daemon restart launched (detached)"
  else
    echo "+ enable_daemons absent → NOT touching system daemons (safe default)"
  fi

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
    # palera1n loads /var/jb LaunchDaemons into the GUI (user/foreground) domain, not system. bootstrap
    # is a no-op once loaded. Each kickstart is BACKGROUNDED so a stuck launchctl on the user/foreground
    # domain can never hang bootstrap (that hang is exactly what broke STEP 1 before). We no longer run
    # `launchctl print` at all — it was the likely culprit and was only a diagnostic.
    echo "+ bootstrap system"; "$LCTL" bootstrap system "$PL" 2>&1
    for DOM in system gui/501 user/501; do
      echo "+ kickstart $DOM (detached)"
      ( "$LCTL" kickstart -k "$DOM/com.mios.containerd" >/dev/null 2>&1 ) &
    done
  fi

  echo "=== end ==="
} >> "$LOG" 2>&1

chown -R 501:501 "$LOGDIR" 2>/dev/null
exit 0
