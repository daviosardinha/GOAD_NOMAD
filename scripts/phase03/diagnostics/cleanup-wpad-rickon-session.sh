#!/usr/bin/env bash
# Stop the Rickon victim session only when the WPAD exercise started it.
set -euo pipefail

SERVICE='kingdoms-phase03-rickon.service'
MARKER="${WPAD_RICKON_MARKER:-/tmp/kingdoms-wpad-rickon-started}"

if [[ ! -f "$MARKER" ]]; then
  echo 'PASS: Rickon victim session was not started by this WPAD exercise'
  exit 0
fi

if [[ "$(cat "$MARKER" 2>/dev/null || true)" != 'started-by-wpad' ]]; then
  echo "FAIL: unexpected WPAD Rickon ownership marker: $MARKER" >&2
  exit 1
fi

systemctl --user stop "$SERVICE"
rm -f -- "$MARKER"

if systemctl --user is-active --quiet "$SERVICE"; then
  echo 'FAIL: Rickon victim service is still active after cleanup' >&2
  exit 1
fi

echo 'PHASE03_WPAD_RICKON_CLEANUP_COMPLETE=True'
