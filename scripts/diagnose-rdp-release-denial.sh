#!/usr/bin/env bash
# Read-only diagnosis for an RDP release-matrix denial.
# It queries the target Windows Security log only; it does not make a new RDP
# connection, change policy, touch group membership, or change lab mode.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
ANSIBLE="${KINGDOMS_RDP_ANSIBLE:-$HOME/.goad/.venv/bin/ansible-playbook}"
INV1="$ROOT/ad/GOAD/data/inventory"
INV2="$ROOT/ad/GOAD/providers/vmware/inventory"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/diagnose-rdp-release-denial.sh <WINTERFELL|CASTELBLACK|WS01> <user> [minutes]

Example:
  bash scripts/diagnose-rdp-release-denial.sh WINTERFELL hodor 15

Read-only. Searches recent Event ID 4625 entries for the exact NORTH user,
RemoteInteractive logon type, attacker source 10.4.10.254, and reports whether
Windows recorded STATUS_LOGON_TYPE_NOT_GRANTED (0xC000015B).
EOF
}

[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 2; }

HOST="$1"
USER="$2"
MINUTES="${3:-15}"

case "$HOST" in
    WINTERFELL) TARGET='dc02' ;;
    CASTELBLACK) TARGET='srv02' ;;
    WS01) TARGET='ws01' ;;
    *) usage >&2; exit 2 ;;
esac

[[ "$MINUTES" =~ ^[0-9]+$ ]] || { echo 'minutes must be an integer' >&2; exit 2; }
[[ -x "$ANSIBLE" ]] || { echo "ansible-playbook not found: $ANSIBLE" >&2; exit 1; }

cd "$ROOT" || exit 1

SINCE="$(date -u -d "$MINUTES minutes ago" +%Y-%m-%dT%H:%M:%SZ)"

ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg"     "$ANSIBLE"     -i "$INV1"     -i "$INV2"     ansible/validate-rdp-denial-event.yml     -e "rdp_event_target=$TARGET"     -e "rdp_event_user=$USER"     -e "rdp_event_since_utc=$SINCE"     -e 'rdp_event_source=10.4.10.254'
