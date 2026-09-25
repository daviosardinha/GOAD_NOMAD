#!/usr/bin/env bash
# Prove the deterministic WS01$ HTTP -> LDAPS relay from sanitized log markers only.
set -euo pipefail

WORK="${WORK:-$HOME/.config/kingdoms/phase03-http-ldaps}"
LOG="$WORK/ntlmrelayx.log"

[[ -r "$LOG" ]] || { echo "FAIL: relay log missing: $LOG" >&2; exit 1; }

echo '===== HTTP -> LDAPS RELAY PROOF ====='

AUTH_LINE="$(grep -Ei 'Authenticating connection from NORTH[/\\]WS01\$@10\.4\.10\.31 against ldaps://10\.4\.10\.11 SUCCEED' "$LOG" | tail -n1 || true)"
[[ -n "$AUTH_LINE" ]] || {
  echo 'FAIL: no successful NORTH\WS01$ HTTP -> LDAPS authentication found' >&2
  tail -n 80 "$LOG" >&2
  exit 1
}

ENUM_LINE="$(grep -Ei 'Enumerating relayed user.*privileges' "$LOG" | tail -n1 || true)"
[[ -n "$ENUM_LINE" ]] || {
  echo 'FAIL: successful relay found, but read-only privilege enumeration marker is missing' >&2
  tail -n 80 "$LOG" >&2
  exit 1
}

if grep -Eqi 'delegation rights modified successfully|shadow credentials attack|adding new computer|attribute.*updated|acl.*modified' "$LOG"; then
  echo 'FAIL: mutation-like ntlmrelayx output detected in read-only fixture' >&2
  exit 1
fi

echo "$AUTH_LINE"
echo "$ENUM_LINE"
echo 'PHASE03_HTTP_LDAPS_IDENTITY=NORTH\WS01$'
echo 'PHASE03_HTTP_LDAPS_TARGET=ldaps://10.4.10.11'
echo 'PHASE03_HTTP_LDAPS_AUTH_SUCCESS=True'
echo 'PHASE03_HTTP_LDAPS_READONLY_ENUMERATION=True'
echo 'PHASE03_HTTP_LDAPS_PROVEN=True'
