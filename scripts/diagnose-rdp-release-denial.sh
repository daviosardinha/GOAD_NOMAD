#!/usr/bin/env bash
# Read-only diagnosis for one RDP release-matrix attempt.
# It inspects Windows Security auditing, Terminal Services operational logs and
# domain credential-validation evidence. It does not create a new RDP session or
# change policy, group membership, services, GPOs or lab mode.
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
  bash scripts/diagnose-rdp-release-denial.sh WINTERFELL hodor 30

Read-only. Reviews the already-performed RDP attempt using:
  - target Security 4624/4625 evidence;
  - effective Logon audit policy;
  - Terminal Services RemoteConnectionManager/LocalSessionManager logs;
  - WINTERFELL Security 4776 credential-validation evidence;
  - target/DC clock values so time-window problems are visible.

No new RDP login is performed.
EOF
}

[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 2; }

HOST="$1"
USER="$2"
MINUTES="${3:-30}"

case "$HOST" in
    WINTERFELL) TARGET='dc02' ;;
    CASTELBLACK) TARGET='srv02' ;;
    WS01) TARGET='ws01' ;;
    *) usage >&2; exit 2 ;;
esac

[[ "$MINUTES" =~ ^[0-9]+$ ]] || {
    echo 'minutes must be an integer' >&2
    exit 2
}
[[ -x "$ANSIBLE" ]] || {
    echo "ansible-playbook not found: $ANSIBLE" >&2
    exit 1
}
[[ -f "$INV1" && -f "$INV2" ]] || {
    echo 'Kingdoms VMware inventories are missing' >&2
    exit 1
}

cd "$ROOT" || exit 1

ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg"     "$ANSIBLE"     -i "$INV1"     -i "$INV2"     ansible/diagnose-rdp-release-attempt.yml     -e "rdp_diag_target=$TARGET"     -e "rdp_diag_user=$USER"     -e "rdp_diag_minutes=$MINUTES"     -e 'rdp_diag_source=10.4.10.254'
