#!/usr/bin/env bash
# Stop only the HTTP -> LDAPS ntlmrelayx instance.
# Handles both the normal PID file and an orphan left by an earlier wrapper-PID bug.
set -euo pipefail

WORK="${WORK:-$HOME/.config/kingdoms/phase03-http-ldaps}"
PIDFILE="$WORK/ntlmrelayx.pid"

listener_pid_80() {
  sudo ss -H -lntp 'sport = :80' 2>/dev/null     | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p'     | head -n1
}

pid_cmdline() {
  local pid="$1"
  sudo sh -c "tr '\\0' ' ' < /proc/$pid/cmdline" 2>/dev/null || true
}

stop_pid() {
  local pid="$1"
  local cmdline

  [[ -n "$pid" ]] || return 0

  if ! sudo kill -0 "$pid" 2>/dev/null; then
    return 0
  fi

  cmdline="$(pid_cmdline "$pid")"

  if ! grep -Eqi 'ntlmrelayx' <<<"$cmdline"; then
    echo "FAIL: refusing to kill PID $pid because it is not ntlmrelayx: $cmdline" >&2
    exit 1
  fi

  echo "Stopping ntlmrelayx PID=$pid"
  sudo kill -TERM "$pid" 2>/dev/null || true

  for _ in {1..10}; do
    sudo kill -0 "$pid" 2>/dev/null || return 0
    sleep 1
  done

  if sudo kill -0 "$pid" 2>/dev/null; then
    echo "Escalating ntlmrelayx PID=$pid"
    sudo kill -KILL "$pid" 2>/dev/null || true
  fi
}

sudo -v

PID=""
if [[ -f "$PIDFILE" ]]; then
  PID="$(cat "$PIDFILE")"
fi

if [[ -n "$PID" ]] && sudo kill -0 "$PID" 2>/dev/null; then
  stop_pid "$PID"
else
  ORPHAN_PID="$(listener_pid_80 || true)"

  if [[ -n "$ORPHAN_PID" ]]; then
    ORPHAN_CMDLINE="$(pid_cmdline "$ORPHAN_PID")"

    if grep -Eqi 'ntlmrelayx' <<<"$ORPHAN_CMDLINE"; then
      echo "INFO: recovered orphaned ntlmrelayx TCP/80 listener PID=$ORPHAN_PID"
      stop_pid "$ORPHAN_PID"
    fi
  fi
fi

rm -f -- "$PIDFILE"

sleep 1

REMAINING_PID="$(listener_pid_80 || true)"
if [[ -n "$REMAINING_PID" ]]; then
  REMAINING_CMDLINE="$(pid_cmdline "$REMAINING_PID")"

  if grep -Eqi 'ntlmrelayx' <<<"$REMAINING_CMDLINE"; then
    echo "FAIL: ntlmrelayx still owns TCP/80 after stop: PID=$REMAINING_PID" >&2
    exit 1
  fi

  echo "FAIL: TCP/80 is still occupied by another process: PID=$REMAINING_PID CMDLINE=$REMAINING_CMDLINE" >&2
  exit 1
fi

echo 'PHASE03_HTTP_LDAPS_RUNTIME_STOPPED=True'
