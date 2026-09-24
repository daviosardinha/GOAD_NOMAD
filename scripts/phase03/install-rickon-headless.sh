#!/usr/bin/env bash
# Installs the Phase 03 Rickon user service definition. Does not enable/start it.
set -uo pipefail
umask 077

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
SOURCE="$ROOT/ops/systemd/kingdoms-phase03-rickon.service"
DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
DEST="$DEST_DIR/kingdoms-phase03-rickon.service"

[[ "${1:-}" == '--confirm' ]] || {
  printf '%s\n'     'Usage: bash scripts/phase03/install-rickon-headless.sh --confirm'     'Installs/replaces the user-unit file only. It does NOT enable or start the service.'
  exit 2
}

cd "$ROOT" || exit 1

[[ -f "$SOURCE" ]] || {
  echo "FAIL: source unit missing: $SOURCE" >&2
  exit 1
}

bash scripts/phase03/check-rickon-prereqs.sh || exit 1

install -d -m 700 "$DEST_DIR"
install -m 600 "$SOURCE" "$DEST"
systemctl --user daemon-reload

echo "PASS: installed $DEST"
echo "INFO: service was NOT enabled or started."
echo "NEXT: inspect with: systemctl --user cat kingdoms-phase03-rickon.service"
