#!/usr/bin/env bash
# Read-only end-to-end proof for the permanent Phase 03 Rickon -> WS01 session.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
SERVICE='kingdoms-phase03-rickon.service'
WS01='10.4.10.31'
PLAYBOOK="$ROOT/ansible/phase03-validate-rickon-session.yml"
DATA_INVENTORY="$ROOT/ad/GOAD/data/inventory"
PROVIDER_INVENTORY="$ROOT/ad/GOAD/providers/vmware/inventory"

PASS=0
FAIL=0
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$*"; }
fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$*" >&2; }

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

echo '===== LOCAL SERVICE ====='
active="$(systemctl --user is-active "$SERVICE" 2>/dev/null || true)"
substate="$(systemctl --user show "$SERVICE" -p SubState --value 2>/dev/null || true)"
mainpid="$(systemctl --user show "$SERVICE" -p MainPID --value 2>/dev/null || true)"
restarts="$(systemctl --user show "$SERVICE" -p NRestarts --value 2>/dev/null || true)"
printf 'ActiveState=%s\nSubState=%s\nMainPID=%s\nNRestarts=%s\n' "$active" "$substate" "$mainpid" "$restarts"

[[ "$active" == active && "$substate" == running && "$mainpid" =~ ^[1-9][0-9]*$ ]] &&
  pass 'Rickon systemd user service is running' ||
  fail 'Rickon systemd user service is not healthy'

echo
echo '===== WS01 SOCKET ====='
all_socket_lines="$(ss -H -ntp 2>/dev/null | grep "${WS01}:3389" || true)"
printf '%s\n' "$all_socket_lines"
socket_lines="$(ss -H -ntp state established 2>/dev/null | grep "${WS01}:3389" || true)"
socket_count="$(grep -c . <<<"$socket_lines" || true)"
[[ "$socket_count" -eq 1 ]] &&
  pass 'Exactly one established WS01 RDP socket exists from the operator host' ||
  fail "Expected exactly one established WS01 RDP socket; observed $socket_count"

freerdp_pid="$(sed -n 's/.*pid=\([0-9]\+\).*/\1/p' <<<"$socket_lines" | head -n1)"
if [[ -n "$freerdp_pid" && -r "/proc/$freerdp_pid/cmdline" ]]; then
  cmdline="$(tr '\0' ' ' < "/proc/$freerdp_pid/cmdline")"
  printf 'FreeRDP PID=%s\nCMDLINE=%s\n' "$freerdp_pid" "$cmdline"
  [[ "$cmdline" == *'/args-from:stdin'* ]] &&
    pass 'FreeRDP uses /args-from:stdin' ||
    fail 'FreeRDP is not using /args-from:stdin'
  [[ "$cmdline" != *'/p:'* ]] &&
    pass 'FreeRDP password is absent from process argv' ||
    fail 'FreeRDP password-like argument is present in process argv'
else
  fail 'Could not identify the FreeRDP process behind the WS01 socket'
fi

echo
echo '===== WINDOWS SESSION ====='
ANSIBLE_PLAYBOOK="$(find_ansible_playbook || true)"
if [[ -z "$ANSIBLE_PLAYBOOK" ]]; then
  fail 'ansible-playbook not found'
else
  output="$(
    ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" \
    "$ANSIBLE_PLAYBOOK" \
      -i "$DATA_INVENTORY" \
      -i "$PROVIDER_INVENTORY" \
      "$PLAYBOOK" 2>&1
  )"
  rc=$?
  printf '%s\n' "$output"
  if [[ $rc -eq 0 ]] && grep -Fq 'PHASE03_RICKON_ACTIVE=TRUE' <<<"$output"; then
    pass 'WS01 reports Rickon as an Active interactive RDP session'
  else
    fail 'WS01 does not report Rickon as an Active interactive RDP session'
  fi
fi

echo
printf 'PASS: %d\nFAIL: %d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
