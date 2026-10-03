#!/usr/bin/env bash
# Ensure the Phase 03 Rickon victim session exists for deterministic WPAD discovery.
# If this helper starts the service, it records ownership so the exercise cleanup
# can stop only the session it created.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
SERVICE='kingdoms-phase03-rickon.service'
MARKER="${WPAD_RICKON_MARKER:-/tmp/kingdoms-wpad-rickon-started}"
WS01='10.4.10.31'

cd "$ROOT"

if systemctl --user is-active --quiet "$SERVICE"; then
  if [[ -f "$MARKER" && "$(cat "$MARKER" 2>/dev/null || true)" == 'started-by-wpad' ]]; then
    echo 'PASS: Rickon victim service is already active and remains owned by this WPAD exercise'
  else
    echo 'PASS: Rickon victim service was already active before this WPAD exercise'
  fi
  bash scripts/phase03/validate-rickon-session.sh
  exit 0
fi

systemctl --user cat "$SERVICE" >/dev/null 2>&1 || {
  echo "FAIL: $SERVICE is not installed for the operator user" >&2
  echo 'Install the existing Kingdoms Phase 03 Rickon user service before running this exercise.' >&2
  exit 1
}

bash scripts/phase03/check-rickon-prereqs.sh

rm -f -- "$MARKER"
systemctl --user start "$SERVICE"
printf '%s\n' started-by-wpad > "$MARKER"
chmod 600 "$MARKER"

echo 'Waiting for the Rickon -> WS01 victim session...'
for _ in $(seq 1 30); do
  if systemctl --user is-active --quiet "$SERVICE" &&
     ss -H -nt state established 2>/dev/null | grep -Eq "[[:space:]]$WS01:3389([[:space:]]|$)"; then
    break
  fi
  sleep 1
done

if ! bash scripts/phase03/validate-rickon-session.sh; then
  echo 'FAIL: Rickon victim session did not become healthy' >&2
  systemctl --user stop "$SERVICE" >/dev/null 2>&1 || true
  rm -f -- "$MARKER"
  exit 1
fi

echo 'PHASE03_WPAD_RICKON_STARTED_BY_EXERCISE=True'
