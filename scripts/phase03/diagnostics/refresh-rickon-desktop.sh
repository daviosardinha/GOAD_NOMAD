#!/usr/bin/env bash
# Refresh Rickon's visible WS01 desktop through the existing headless RDP session.
# This simulates the user-session interaction that makes Explorer enumerate the new shortcut.
set -euo pipefail

WS01_IP="${WS01_IP:-10.4.10.31}"

command -v xdotool >/dev/null 2>&1 || {
  echo 'FAIL: xdotool is not installed'
  echo 'Install it with: sudo apt install -y xdotool'
  exit 1
}

RDP_PID="$(sudo ss -ntp 2>/dev/null | sed -n "s/.*${WS01_IP//./\\.}:3389.*pid=\\([0-9]\\+\\).*/\\1/p" | head -n1)"

[[ -n "${RDP_PID:-}" ]] || {
  echo 'FAIL: no active FreeRDP connection to WS01'
  exit 1
}

DISPLAY_VALUE="$(sudo tr '\\0' '\\n' < "/proc/$RDP_PID/environ" 2>/dev/null | sed -n 's/^DISPLAY=//p')"
XAUTH_VALUE="$(sudo tr '\\0' '\\n' < "/proc/$RDP_PID/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p')"

[[ -n "$DISPLAY_VALUE" && -n "$XAUTH_VALUE" ]] || {
  echo 'FAIL: could not recover DISPLAY/XAUTHORITY from the WS01 FreeRDP process'
  exit 1
}

export DISPLAY="$DISPLAY_VALUE"
export XAUTHORITY="$XAUTH_VALUE"

WINDOW_ID="$(xdotool search --onlyvisible --pid "$RDP_PID" 2>/dev/null | head -n1 || true)"

if [[ -z "$WINDOW_ID" ]]; then
  WINDOW_ID="$(xdotool search --onlyvisible --name 'FreeRDP|WS01|ws01' 2>/dev/null | head -n1 || true)"
fi

[[ -n "$WINDOW_ID" ]] || {
  echo 'FAIL: could not locate the WS01 FreeRDP window'
  exit 1
}

echo "RDP_PID=$RDP_PID"
echo "DISPLAY=$DISPLAY"
echo "WINDOW_ID=$WINDOW_ID"
echo 'INFO: activating Rickon RDP window, showing Desktop, then issuing F5'

xdotool windowactivate --sync "$WINDOW_ID"
sleep 1
xdotool key --window "$WINDOW_ID" --clearmodifiers Super_L+d
sleep 2
xdotool key --window "$WINDOW_ID" --clearmodifiers F5

sleep 8

echo 'PHASE03_WEBDAV_RICKON_DESKTOP_REFRESH=True'
