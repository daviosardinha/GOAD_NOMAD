#!/usr/bin/env bash
# Read-only inspection of the reserved ADIDNS record after a rollback failure.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
PLAYBOOK="$ROOT/ansible/phase03-adidns-diagnose-rollback.yml"
DATA_INVENTORY="$ROOT/ad/GOAD/data/inventory"
PROVIDER_INVENTORY="$ROOT/ad/GOAD/providers/vmware/inventory"
DC_IP="${DC_IP:-10.4.10.11}"
FQDN="${FQDN:-phase03-adidns.north.sevenkingdoms.local}"

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

echo '===== ADIDNS ROLLBACK STATE DIAGNOSTIC ====='

ANSWER="$(dig @"$DC_IP" "$FQDN" A +time=2 +tries=1 +short || true)"
if [[ -n "$ANSWER" ]]; then
  echo "PHASE03_ADIDNS_DIAG_DNS_ANSWER=$ANSWER"
else
  echo 'PHASE03_ADIDNS_DIAG_DNS_ANSWER=NONE'
fi

ANSIBLE_PLAYBOOK="$(find_ansible_playbook || true)"
[[ -n "$ANSIBLE_PLAYBOOK" ]] || {
  echo 'FAIL: ansible-playbook not found' >&2
  exit 1
}

ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" "$ANSIBLE_PLAYBOOK" \
  -i "$DATA_INVENTORY" \
  -i "$PROVIDER_INVENTORY" \
  "$PLAYBOOK"
