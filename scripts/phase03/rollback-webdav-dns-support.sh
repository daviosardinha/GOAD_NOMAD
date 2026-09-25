#!/usr/bin/env bash
# Remove the temporary WebDAV DNS support record and any owner-created tombstone.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
BASELINE="${BASELINE:-$HOME/.config/kingdoms/phase03-webdav-dns-baseline.json}"
WORK="${WORK:-$HOME/.config/kingdoms/phase03-webdav-dns}"
ZONE="${ZONE:-north.sevenkingdoms.local}"
RECORD="${RECORD:-phase03-webdav}"
FQDN="$RECORD.$ZONE"
DNS_SERVER="${DNS_SERVER:-winterfell.north.sevenkingdoms.local}"
LDAP_URI="${LDAP_URI:-ldap://winterfell.north.sevenkingdoms.local}"
NODE_DN="DC=$RECORD,DC=$ZONE,CN=MicrosoftDNS,DC=DomainDnsZones,DC=north,DC=sevenkingdoms,DC=local"
KRB5_CONFIG_FILE="$WORK/krb5.conf"
TGT_CACHE="$WORK/webdav-dns.ccache"
UPDATE_FILE="$WORK/nsupdate-delete.txt"
VERIFY_PLAYBOOK="$ROOT/ansible/phase03-webdav-dns-verify.yml"
DATA_INVENTORY="$ROOT/ad/GOAD/data/inventory"
PROVIDER_INVENTORY="$ROOT/ad/GOAD/providers/vmware/inventory"

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

[[ -f "$KRB5_CONFIG_FILE" && -f "$TGT_CACHE" ]] || { echo "FAIL: retained WebDAV DNS Kerberos context missing" >&2; exit 1; }
export KRB5_CONFIG="$KRB5_CONFIG_FILE"
export KRB5CCNAME="FILE:$TGT_CACHE"

cat >"$UPDATE_FILE" <<EOF
server $DNS_SERVER
zone $ZONE.
update delete $FQDN. A
send
answer
EOF

nsupdate -g -v "$UPDATE_FILE" || true

set +e
LDAP_RESULT="$(ldapsearch -LLL -Y GSSAPI -Q -H "$LDAP_URI" -b "$NODE_DN" -s base '(objectClass=dnsNode)' dn dNSTombstoned 2>&1)"
LDAP_RC=$?
set -e

if [[ "$LDAP_RC" -eq 0 ]]; then
  printf '%s\n' "$LDAP_RESULT"
  ldapdelete -Y GSSAPI -Q -H "$LDAP_URI" "$NODE_DN"
elif [[ "$LDAP_RC" -ne 32 ]]; then
  printf '%s\n' "$LDAP_RESULT" >&2
  echo "FAIL: could not determine WebDAV DNS node state" >&2
  exit 1
fi

ANSWER="$(dig @10.4.10.11 "$FQDN" A +time=2 +tries=1 +short || true)"
[[ -z "$ANSWER" ]] || { echo "FAIL: DNS still resolves to $ANSWER" >&2; exit 1; }

rm -rf -- "$WORK"
echo 'PHASE03_WEBDAV_DNS_SUPPORT_ROLLBACK_COMPLETE=True'
