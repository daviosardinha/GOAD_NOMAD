#!/usr/bin/env bash
# Read-only capability snapshot for the permanent mitm6/WPAD -> HTTP -> LDAPS runtime.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"

find_ntlmrelayx() {
  local candidate
  for candidate in     "$(command -v impacket-ntlmrelayx 2>/dev/null || true)"     "$(command -v ntlmrelayx.py 2>/dev/null || true)"     /usr/share/doc/python3-impacket/examples/ntlmrelayx.py; do
    [[ -n "$candidate" && ( -f "$candidate" || -x "$candidate" ) ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

cd "$ROOT"

echo '===== WPAD RUNTIME CAPABILITY SNAPSHOT ====='

MITM6="$(command -v mitm6 2>/dev/null || true)"
NTLMRELAYX="$(find_ntlmrelayx || true)"

[[ -n "$MITM6" ]] || { echo 'FAIL: mitm6 not found' >&2; exit 1; }
[[ -n "$NTLMRELAYX" ]] || { echo 'FAIL: ntlmrelayx not found' >&2; exit 1; }

echo "MITM6=$MITM6"
echo "NTLMRELAYX=$NTLMRELAYX"

echo
echo '===== MITM6 VERSION / HELP ====='
"$MITM6" --version 2>&1 || true
MITM6_HELP="$("$MITM6" -h 2>&1 || true)"
printf '%s\n' "$MITM6_HELP"

echo
echo '===== MITM6 EXPECTED OPTIONS ====='
for opt in '-d' '-i'; do
  if grep -Fq -- "$opt" <<<"$MITM6_HELP"; then
    echo "PASS: mitm6 supports $opt"
  else
    echo "FAIL: mitm6 missing expected option $opt" >&2
    exit 1
  fi
done

echo
echo '===== NTLMRELAYX VERSION / HELP ====='
NTLM_HELP="$("$NTLMRELAYX" -h 2>&1 || true)"
printf '%s\n' "$NTLM_HELP" | sed -n '1,220p'

echo
echo '===== NTLMRELAYX WPAD / HTTP / LDAPS OPTIONS ====='
for opt in   '-t'   '-6'   '-wh'   '--wpad-auth-num'   '--no-dump'   '--no-da'   '--no-acl'   '--no-smb-server'   '--no-wcf-server'   '--no-raw-server'; do
  if grep -Fq -- "$opt" <<<"$NTLM_HELP"; then
    echo "SUPPORTED: $opt"
  else
    echo "NOT_SUPPORTED: $opt"
  fi
done

if grep -Eq -- '--http-port|HTTP.*port' <<<"$NTLM_HELP"; then
  echo 'INFO: ntlmrelayx advertises an HTTP port option'
fi

echo
echo '===== NEUTRAL RUNTIME CHECK ====='
if pgrep -af '(^|[ /])(mitm6|impacket-ntlmrelayx|ntlmrelayx[.]py|Responder[.]py|responder)([ ]|$)' >/dev/null; then
  echo 'FAIL: conflicting attack runtime is active' >&2
  pgrep -af '(^|[ /])(mitm6|impacket-ntlmrelayx|ntlmrelayx[.]py|Responder[.]py|responder)([ ]|$)' || true
  exit 1
fi

echo 'PASS: neutral Phase 03 runtime'
echo 'PHASE03_WPAD_CAPABILITY_SNAPSHOT_COMPLETE=True'
