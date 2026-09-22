#!/usr/bin/env bash
# Phase 03 readiness contract: read-only prerequisite validation for
# "03 - Poison the Wells". This script does NOT start Responder, ntlmrelayx,
# mitm6, trigger coercion, relay credentials, or modify Active Directory.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
INSTANCE="${INSTANCE:-cebee3-goad-vmware}"
PROVIDER="${PROVIDER:-$ROOT/workspace/$INSTANCE/provider}"
DOMAIN_FQDN='north.sevenkingdoms.local'
WINTERFELL='10.4.10.11'
CASTELBLACK='10.4.10.22'
WS01='10.4.10.31'
KINGSLANDING='10.4.20.10'
MEEREEN='10.4.30.12'
STAMP="$(date +%Y%m%d-%H%M%S)"
EVIDENCE="${EVIDENCE:-$HOME/Kingdoms-evidence/phase03-readiness-$STAMP}"

mkdir -p "$EVIDENCE"
cd "$ROOT" || exit 1
export PATH="$HOME/.goad/.venv/bin:$PATH"

PASS=0
WARN=0
FAIL=0
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$*"; }
warn(){ WARN=$((WARN+1)); printf '[WARN] %s\n' "$*" >&2; }
fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$*" >&2; }
info(){ printf '[INFO] %s\n' "$*"; }
section(){ printf '\n============================================================\n%s\n============================================================\n' "$*"; }
strip_ansi(){ sed -E 's/\x1B\[[0-9;?]*[ -\/]*[@-~]//g'; }
tcp_open(){ timeout 4 nc -z -w3 "$1" "$2" >/dev/null 2>&1; }

find_ansible_playbook(){
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

NXC=()
if command -v netexec >/dev/null 2>&1; then
  NXC=(netexec)
elif command -v nxc >/dev/null 2>&1; then
  NXC=(nxc)
elif command -v poetry >/dev/null 2>&1 && poetry run netexec --version >/dev/null 2>&1; then
  NXC=(poetry run netexec)
fi

MSSQLCLIENT=''
if command -v impacket-mssqlclient >/dev/null 2>&1; then
  MSSQLCLIENT="$(command -v impacket-mssqlclient)"
elif command -v mssqlclient.py >/dev/null 2>&1; then
  MSSQLCLIENT="$(command -v mssqlclient.py)"
fi

LDAP_CHECKER=''
for c in \
  /usr/share/doc/python3-impacket/examples/CheckLDAPStatus.py \
  /usr/share/doc/python3-impacket/examples/CheckLDAPStatus.py.gz; do
  [[ -f "$c" ]] || continue
  LDAP_CHECKER="$c"
  break
done
if [[ -z "$LDAP_CHECKER" ]] && command -v dpkg >/dev/null 2>&1; then
  LDAP_CHECKER="$(dpkg -L python3-impacket 2>/dev/null | grep '/CheckLDAPStatus.py$' | head -n1 || true)"
fi

section 'KINGDOMS — 03 POISON THE WELLS — READ-ONLY READINESS CONTRACT'
printf 'Instance : %s\nEvidence : %s\n' "$INSTANCE" "$EVIDENCE"
printf '%s\n' '[INFO] No poisoning, relay, coercion, directory modification, capture or credential dumping is performed.'

section '0. SOURCE / INSTANCE / TOOL PRECHECK'
if bash scripts/verify-test-source.sh 2>&1 | tee "$EVIDENCE/source-gate.log"; then
  pass 'Git source gate passed'
else
  fail 'Git source gate failed'
fi

[[ -d "$PROVIDER" ]] && pass "provider exists: $PROVIDER" || fail "provider missing: $PROVIDER"
if [[ -f "$PROVIDER/.goad-nomad-mode" ]]; then
  MODE="$(tr -d '[:space:]' < "$PROVIDER/.goad-nomad-mode")"
  [[ "$MODE" == exercise ]] && pass 'instance is recorded in exercise mode' || fail "instance mode=$MODE (expected exercise)"
else
  fail 'exercise-mode marker missing'
fi

for c in git ip nc timeout grep awk sed python3 ss nslookup; do
  command -v "$c" >/dev/null 2>&1 && pass "tool available: $c" || fail "tool missing: $c"
done
[[ ${#NXC[@]} -gt 0 ]] && pass "NetExec available: ${NXC[*]}" || fail 'NetExec/nxc unavailable'
[[ -n "$MSSQLCLIENT" ]] && pass "MSSQL client available: $MSSQLCLIENT" || fail 'Impacket mssqlclient unavailable'
