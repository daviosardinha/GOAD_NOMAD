#!/usr/bin/env bash
# Stop only the PID-scoped HTTP -> LDAPS relay runtime.
set -euo pipefail

WORK="${WORK:-$HOME/.config/kingdoms/phase03-http-ldaps}"
PIDFILE="$WORK/ntlmrelayx.pid"

if [[ ! -f "$PIDFILE" ]]; then
  echo 'PASS: HTTP -> LDAPS relay is already stopped'
  exit 0
fi

PID="$(cat "$PIDFILE")"

if sudo kill -0 "$PID" 2>/dev/null; then
  sudo kill -TERM "$PID" 2>/dev/null || true

  for _ in {1..10}; do
    sudo kill -0 "$PID" 2>/dev/null || break
    sleep 1
  done

  if sudo kill -0 "$PID" 2>/dev/null; then
    sudo kill -KILL "$PID" 2>/dev/null || true
  fi
fi

rm -f -- "$PIDFILE"

if sudo ss -H -lntp 2>/dev/null | grep -Eq ':80[[:space:]]'; then
  echo 'FAIL: TCP/80 still has a listener after relay stop' >&2
  sudo ss -H -lntp 2>/dev/null | grep -E ':80[[:space:]]' || true
  exit 1
fi

echo 'PHASE03_HTTP_LDAPS_RUNTIME_STOPPED=True'
