#!/usr/bin/env bash
# Read-only correlation of the most recent RDP attempt for one NORTH user.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
ANSIBLE="${KINGDOMS_RDP_ANSIBLE:-$HOME/.goad/.venv/bin/ansible-playbook}"
INV1="$ROOT/ad/GOAD/data/inventory"
INV2="$ROOT/ad/GOAD/providers/vmware/inventory"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/diagnose-rdp-release-timeline.sh <WINTERFELL|CASTELBLACK|WS01> <user> [minutes]

Example:
  bash scripts/diagnose-rdp-release-timeline.sh WINTERFELL hodor 60

Read-only. Anchors on the newest Security 4624/4625 event for the exact NORTH
user/source and prints a tight target-side timeline from Security, Terminal
Services and relevant System logs. No new RDP connection is created.
EOF
}

[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 2; }

HOST="$1"
USER="$2"
MINUTES="${3:-60}"

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

ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg"     "$ANSIBLE"     -i "$INV1"     -i "$INV2"     ansible/diagnose-rdp-release-timeline.yml     -e "rdp_timeline_target=$TARGET"     -e "rdp_timeline_user=$USER"     -e "rdp_timeline_minutes=$MINUTES"     -e 'rdp_timeline_source=10.4.10.254'
