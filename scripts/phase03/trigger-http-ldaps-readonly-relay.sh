#!/usr/bin/env bash
# Trigger one deterministic WS01 LocalSystem HTTP authentication against the read-only relay.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
WORK="${WORK:-$HOME/.config/kingdoms/phase03-http-ldaps}"
PLAYBOOK="$ROOT/ansible/phase03-trigger-ws01-system-http.yml"
DATA_INVENTORY="$ROOT/ad/GOAD/data/inventory"
PROVIDER_INVENTORY="$ROOT/ad/GOAD/providers/vmware/inventory"

find_ansible_playbook() {
  local c
  for c in     "$(command -v ansible-playbook 2>/dev/null || true)"     "$ROOT/.venv/bin/ansible-playbook"     "$HOME/.goad/.venv/bin/ansible-playbook"; do
    [[ -n "$c" && -x "$c" ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

cd "$ROOT"

[[ -f "$WORK/ntlmrelayx.pid" ]] || { echo 'FAIL: HTTP relay pid file missing' >&2; exit 1; }
PID="$(cat "$WORK/ntlmrelayx.pid")"
sudo kill -0 "$PID" 2>/dev/null || { echo 'FAIL: HTTP relay runtime is not active' >&2; exit 1; }

ANSIBLE_PLAYBOOK="$(find_ansible_playbook || true)"
[[ -n "$ANSIBLE_PLAYBOOK" ]] || { echo 'FAIL: ansible-playbook not found' >&2; exit 1; }

ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" "$ANSIBLE_PLAYBOOK"   -i "$DATA_INVENTORY"   -i "$PROVIDER_INVENTORY"   "$PLAYBOOK"

echo 'PHASE03_HTTP_LDAPS_TRIGGER_COMPLETE=True'
