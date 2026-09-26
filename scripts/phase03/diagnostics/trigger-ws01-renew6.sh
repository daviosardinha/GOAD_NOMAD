#!/usr/bin/env bash
# Trigger DHCPv6 renewal on WS01 over the existing trusted management path,
# then show only new mitm6 / observer evidence produced by that action.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
PLAYBOOK="$ROOT/ansible/phase03-trigger-ws01-renew6.yml"
DATA_INVENTORY="$ROOT/ad/GOAD/data/inventory"
PROVIDER_INVENTORY="$ROOT/ad/GOAD/providers/vmware/inventory"
MITM6_LOG="${MITM6_LOG:-/tmp/kingdoms-mitm6.log}"
HTTP_LOG="${HTTP_LOG:-/tmp/kingdoms-wpad-http.log}"

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

pgrep -af '(^|[ /])mitm6([ ]|$)' >/dev/null || {
  echo 'FAIL: scoped mitm6 is not running' >&2
  exit 1
}

[[ -f "$PLAYBOOK" ]] || {
  echo "FAIL: missing playbook: $PLAYBOOK" >&2
  exit 1
}

mitm6_before="$(wc -l < "$MITM6_LOG" 2>/dev/null || printf '0')"
http_before="$(wc -l < "$HTTP_LOG" 2>/dev/null || printf '0')"

echo '===== BASELINE ====='
printf 'mitm6 lines: %s\nHTTP lines : %s\n' "$mitm6_before" "$http_before"

ANSIBLE_PLAYBOOK="$(find_ansible_playbook || true)"
[[ -n "$ANSIBLE_PLAYBOOK" ]] || {
  echo 'FAIL: ansible-playbook not found' >&2
  exit 1
}

echo
echo '===== TRIGGER WS01 DHCPV6 RENEWAL ====='
ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" \
"$ANSIBLE_PLAYBOOK" \
  -i "$DATA_INVENTORY" \
  -i "$PROVIDER_INVENTORY" \
  "$PLAYBOOK" || exit 1

echo
echo 'Waiting 8 seconds for mitm6 / WPAD activity...'
sleep 8

echo
echo '===== NEW MITM6 OUTPUT ====='
tail -n "+$((mitm6_before + 1))" "$MITM6_LOG" 2>/dev/null || true

echo
echo '===== NEW HTTP OUTPUT ====='
tail -n "+$((http_before + 1))" "$HTTP_LOG" 2>/dev/null || true

echo
echo '===== RICKON SESSION HEALTH ====='
bash "$ROOT/scripts/phase03/validate-rickon-session.sh"
