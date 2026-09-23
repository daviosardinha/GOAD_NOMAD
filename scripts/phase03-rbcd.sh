#!/usr/bin/env bash
# NORTH-only RBCD fixture operator entry point. Never selects a VMware instance implicitly.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ACTION=''
INSTANCE=''
CHECK=false

usage() {
    printf 'Usage: bash %s audit|apply|reset --instance WORKSPACE_ID [--check]\n' "$0" >&2
    exit 2
}

[[ $# -gt 0 ]] || usage
ACTION="$1"
shift
[[ "$ACTION" =~ ^(audit|apply|reset)$ ]] || usage

while (($#)); do
    case "$1" in
        --instance)
            (($# >= 2)) || usage
            INSTANCE="$2"
            shift 2
            ;;
        --check)
            CHECK=true
            shift
            ;;
        *) usage ;;
    esac
done

[[ "$INSTANCE" =~ ^[A-Za-z0-9_-]+$ ]] || {
    echo '[FAIL] Supply an explicit, existing workspace ID with --instance.' >&2
    exit 1
}
MANAGEMENT="$ROOT/workspace/$INSTANCE/inventory"
PROVIDER="$ROOT/workspace/$INSTANCE/provider"
[[ -f "$MANAGEMENT" && -d "$PROVIDER" ]] || {
    echo '[FAIL] Cannot find the exact instance inventory/provider.' >&2
    exit 1
}
[[ -f "$PROVIDER/.vagrant/machines/GOAD-DC02/vmware_desktop/id" ]] || {
    echo '[FAIL] Expected WINTERFELL VMware metadata missing in that workspace.' >&2
    exit 1
}

# Never apply/reset from a dirty, divergent or unpushed checkout.
bash "$ROOT/scripts/verify-test-source.sh"

PLAYBOOK="$HOME/.goad/.venv/bin/ansible-playbook"
[[ -x "$PLAYBOOK" ]] || {
    echo "[FAIL] Missing Kingdoms Ansible runtime: $PLAYBOOK" >&2
    exit 1
}

run_playbook() {
    ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" "$PLAYBOOK" \
        -i "$ROOT/ad/GOAD/data/inventory" \
        -i "$MANAGEMENT" \
        -i "$ROOT/globalsettings.ini" \
        "$ROOT/ansible/phase03-rbcd.yml" \
        -e "phase03_rbcd_action=$ACTION" \
        "$@"
}
printf '[INFO] Phase 03 RBCD action=%s instance=%s check=%s\n' "$ACTION" "$INSTANCE" "$CHECK"
if [[ "$CHECK" == true ]]; then
    run_playbook --check --diff
else
    run_playbook
fi
