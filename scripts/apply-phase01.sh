#!/usr/bin/env bash
# One operator entry point: source gate, regressions, prerequisites, provisioning, evidence.
set -Eeuo pipefail
readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
prerequisites=()
instance=''
while (( $# )); do
    case "$1" in
        --install-prerequisites) prerequisites=(--install-prerequisites); shift ;;
        --instance)
            [[ $# -ge 2 ]] || { echo '--instance requires an ID' >&2; exit 2; }
            instance="$2"; shift 2 ;;
        *) echo "Usage: $0 [--instance ID] [--install-prerequisites]" >&2; exit 2 ;;
    esac
done
if [[ -z "$instance" ]]; then
    mapfile -t ids < <(find "$ROOT/workspace" -type f -path '*/provider/.vagrant/machines/GOAD-DC02/vmware_desktop/id' -print)
    [[ ${#ids[@]} -eq 1 ]] || { echo 'Cannot select one installed Kingdoms instance; supply --instance ID.' >&2; exit 1; }
    provider="${ids[0]%%/.vagrant/*}"
    instance="$(basename "$(dirname "$provider")")"
fi
[[ "$instance" =~ ^[A-Za-z0-9_-]+$ && -f "$ROOT/workspace/$instance/inventory" ]] || {
    echo 'Instance must name an existing repository workspace inventory.' >&2
    exit 1
}
bash scripts/verify-test-source.sh
python3 -m unittest tests.test_phase01_gpo_source tests.test_phase01_validation
bash scripts/setup-phase01-tools.sh "${prerequisites[@]}"
# NORTH is directly reachable in the Kingdoms exercise network. Use the same
# inventories as other maintenance scripts, and propagate Ansible's exit code.
# The console's do_provision currently discards that code; do not mask failures.
readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"
[[ -x "$ANSIBLE_PLAYBOOK" ]] || { echo "Missing GOAD Ansible runtime: $ANSIBLE_PLAYBOOK" >&2; exit 1; }
ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" "$ANSIBLE_PLAYBOOK" \
    -i "$ROOT/ad/GOAD/data/inventory" -i "$ROOT/workspace/$instance/inventory" \
    -i "$ROOT/globalsettings.ini" "$ROOT/ansible/phase01.yml"
bash scripts/validate-phase01.sh
