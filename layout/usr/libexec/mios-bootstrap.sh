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
  cat > "$RS" <<'RSEOF'
#!/bin/sh
LOG="$1"
sleep 10                       # let the installer finish and the filesystem settle
# Crane's own mechanism (killallProcessesWithName): kill the running instance so launchd respawns it
# injected the next time something demands it. For daemons that ARE running this is all that's needed.
for D in containermanagerd securityd cfprefsd lsd; do
  if killall -9 "$D" 2>/dev/null; then echo "killall $D ok $(date)" >> "$LOG"
  else echo "killall $D: not running $(date)" >> "$LOG"; fi
done
# Bonus: also force the on-demand daemons to start RIGHT NOW, so their support_*.log shows up even before
# an app demands them. Best-effort and each BACKGROUNDED so a slow/stuck launchctl can never hang us.
LCTL=""
for L in /var/jb/usr/bin/launchctl /usr/bin/launchctl /bin/launchctl; do [ -x "$L" ] && LCTL="$L" && break; done
if [ -n "$LCTL" ]; then
  for S in system/com.apple.containermanagerd system/com.apple.securityd system/com.apple.cfprefsd.xpc.daemon; do
    ( "$LCTL" kickstart "$S" >/dev/null 2>&1; echo "kickstart $S returned $(date)" >> "$LOG" ) &
  done
fi
echo "restart pass done $(date)" >> "$LOG"
RSEOF
  chmod 0755 "$RS" 2>/dev/null
  if command -v setsid >/dev/null 2>&1; then
    setsid /bin/sh "$RS" "$LOG" >/dev/null 2>&1 </dev/null &
  else
    /bin/sh "$RS" "$LOG" >/dev/null 2>&1 </dev/null &
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
