#!/usr/bin/env bash
set -euo pipefail

TARGET="${TARGET:-ws01.north.sevenkingdoms.local}"
TARGET_IP="${TARGET_IP:-10.4.10.31}"
SECRET="${KINGDOMS_RICKON_RDP_SECRET_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/kingdoms/rickon-rdp.password}"
LOG="${LOG:-/tmp/rickon-ws01-headless.log}"

[[ -f "$SECRET" && ! -L "$SECRET" && -s "$SECRET" ]] || {
  echo "FAIL: missing/non-regular credential file: $SECRET"
  exit 1
}

[[ "$(stat -c '%u' "$SECRET")" == "$(id -u)" ]] || {
  echo "FAIL: credential file is not owned by current user"
  exit 1
}

mode="$(stat -c '%a' "$SECRET")"
(( (8#$mode & 8#077) == 0 )) || {
  echo "FAIL: credential file permits group/other access"
  exit 1
}

if sudo ss -ntp | grep -q "${TARGET_IP}:3389"; then
  echo "FAIL: WS01 already has an RDP client from this host"
  exit 1
fi

rm -f "$LOG"

{
  printf '%s\n' "/v:$TARGET" '/d:NORTH' '/u:rickon.stark'
  printf '/p:'
  cat "$SECRET"
  printf '\n'
  printf '%s\n' '/cert:ignore' '/size:1280x800'
} | xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp'       xfreerdp3 /args-from:stdin >"$LOG" 2>&1 &

sleep 5
sudo ss -ntp | grep "${TARGET_IP}:3389" || {
  echo "FAIL: no WS01 RDP connection"
  tail -n 40 "$LOG"
  exit 1
}

echo "PASS: Rickon headless WS01 session is running"
echo "NOTE: /cert:ignore is temporary. Production Phase 03 must pin the WS01 certificate."
