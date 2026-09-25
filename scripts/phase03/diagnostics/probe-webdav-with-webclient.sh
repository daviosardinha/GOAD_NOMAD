#!/usr/bin/env bash
# Transiently start WebClient, probe the hostname-backed UNC path, then restore the captured stopped state.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
PLAYBOOK="$ROOT/ansible/phase03-webdav-service-probe.yml"
DATA_INVENTORY="$ROOT/ad/GOAD/data/inventory"
PROVIDER_INVENTORY="$ROOT/ad/GOAD/providers/vmware/inventory"

find_ansible_playbook() {
  local candidate_file
  for candidate_file in \
    "$(command -v ansible-playbook 2>/dev/null || true)" \
    "$ROOT/.venv/bin/ansible-playbook" \
    "$ROOT/venv/bin/ansible-playbook" \
    "$HOME/.goad/.venv/bin/ansible-playbook" \
    "$HOME/.local/bin/ansible-playbook"; do
    [[ -n "$candidate_file" && -x "$candidate_file" ]] || continue
    printf '%s\n' "$candidate_file"
    return 0
  done
  return 1
}

cd "$ROOT"

if ! sudo ss -H -lntp 2>/dev/null | grep -Eq ':80[[:space:]]'; then
  echo 'FAIL: WebDAV observer is not listening on TCP/80'
  exit 1
fi

ANSWER="$(dig @10.4.10.11 phase03-webdav.north.sevenkingdoms.local A +time=2 +tries=1 +short | tail -n1)"
[[ "$ANSWER" == "10.4.10.254" ]] || { echo "FAIL: WebDAV support hostname does not resolve to 10.4.10.254" >&2; exit 1; }

ANSIBLE_PLAYBOOK="$(find_ansible_playbook || true)"
[[ -n "$ANSIBLE_PLAYBOOK" ]] || { echo "FAIL: ansible-playbook not found" >&2; exit 1; }

ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" "$ANSIBLE_PLAYBOOK" \
  -i "$DATA_INVENTORY" \
  -i "$PROVIDER_INVENTORY" \
  "$PLAYBOOK"
