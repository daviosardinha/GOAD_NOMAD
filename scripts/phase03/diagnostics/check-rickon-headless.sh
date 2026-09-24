#!/usr/bin/env bash
set -euo pipefail

WS01_IP="${WS01_IP:-10.4.10.31}"
OUT="${OUT:-/tmp/rickon-ws01-headless.png}"

RDP_PID="$(sudo ss -ntp | sed -n "s/.*${WS01_IP//./\\.}:3389.*pid=\\([0-9]\\+\\).*/\\1/p" | head -n1)"

if [[ -z "${RDP_PID:-}" ]]; then
  echo "FAIL: no FreeRDP connection to WS01"
  exit 1
fi

echo "WS01 FreeRDP PID: $RDP_PID"
ps -o pid,ppid,stat,etime,cmd -p "$RDP_PID"

DISPLAY_VALUE="$(tr '\0' '\n' < "/proc/$RDP_PID/environ" | sed -n 's/^DISPLAY=//p')"
XAUTH_VALUE="$(tr '\0' '\n' < "/proc/$RDP_PID/environ" | sed -n 's/^XAUTHORITY=//p')"

echo "DISPLAY=$DISPLAY_VALUE"
echo "XAUTHORITY=$XAUTH_VALUE"

[[ -n "$DISPLAY_VALUE" && -n "$XAUTH_VALUE" ]] || {
  echo "FAIL: FreeRDP is not attached to an Xvfb environment"
  exit 1
}

ps -eo pid,ppid,stat,etime,cmd | grep -F "Xvfb $DISPLAY_VALUE" | grep -v grep || true

if command -v xwininfo >/dev/null 2>&1; then
  DISPLAY="$DISPLAY_VALUE" XAUTHORITY="$XAUTH_VALUE"     xwininfo -root -tree 2>/dev/null | head -n 80
fi

rm -f "$OUT"
if command -v import >/dev/null 2>&1; then
  DISPLAY="$DISPLAY_VALUE" XAUTHORITY="$XAUTH_VALUE" import -window root "$OUT"
elif command -v scrot >/dev/null 2>&1; then
  DISPLAY="$DISPLAY_VALUE" XAUTHORITY="$XAUTH_VALUE" scrot "$OUT"
fi

[[ ! -f "$OUT" ]] || {
  echo "Screenshot: $OUT"
  file "$OUT"
}

sudo ss -ntp | grep "${WS01_IP}:3389" || true
