#!/usr/bin/env bash
set -euo pipefail

WS01_IP="${WS01_IP:-10.4.10.31}"
CASTELBLACK_IP="${CASTELBLACK_IP:-10.4.10.22}"

RDP_PID="$(sudo ss -ntp | sed -n "s/.*${WS01_IP//./\\.}:3389.*pid=\\([0-9]\\+\\).*/\\1/p" | head -n1)"
[[ -n "${RDP_PID:-}" ]] || {
  echo "FAIL: no WS01 FreeRDP client found"
  exit 1
}

DISPLAY_VALUE="$(tr '\0' '\n' < "/proc/$RDP_PID/environ" | sed -n 's/^DISPLAY=//p')"

kill -TERM "$RDP_PID"
for _ in {1..10}; do
  kill -0 "$RDP_PID" 2>/dev/null || break
  sleep 1
done

kill -0 "$RDP_PID" 2>/dev/null && {
  echo "FAIL: WS01 FreeRDP PID $RDP_PID is still alive"
  exit 1
}

sudo ss -ntp | grep -q "${WS01_IP}:3389" && {
  echo "FAIL: WS01 RDP socket still exists"
  exit 1
}

sleep 2
if [[ -n "${DISPLAY_VALUE:-}" ]] && ps -eo cmd | grep -F "Xvfb $DISPLAY_VALUE" | grep -v grep >/dev/null; then
  echo "FAIL: Xvfb $DISPLAY_VALUE survived"
  exit 1
fi

systemctl --user show kingdoms-rdp-bot.service -p ActiveState -p SubState -p MainPID
sudo ss -ntp | grep "${CASTELBLACK_IP}:3389" || {
  echo "FAIL: Robb/CASTELBLACK socket missing"
  exit 1
}

echo "PASS: Rickon teardown clean and Robb bot unaffected"
