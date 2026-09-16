#!/usr/bin/env bash
set -Eeuo pipefail
readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
instance=''
while (( $# )); do
    case "$1" in
        --instance)
            [[ $# -ge 2 ]] || { echo '--instance requires an ID' >&2; exit 2; }
            instance="$2"; shift 2 ;;
        *) echo "Usage: $0 [--instance ID]" >&2; exit 2 ;;
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

probe() {
    local label="$1"; shift
    echo
    echo "===== ${label} ====="
    set +e
    "$@" 2>&1
    local rc=$?
    set -e
    echo "[exit_code=${rc}]"
}

probe 'rpcclient NULL lsaquery' rpcclient -U '%' -N 10.4.10.11 -c 'lsaquery'
probe 'rpcclient NULL enumdomusers' rpcclient -U '%' -N 10.4.10.11 -c 'enumdomusers'
probe 'rpcclient NULL enumdomgroups' rpcclient -U '%' -N 10.4.10.11 -c 'enumdomgroups'
probe 'rpcclient NULL getdompwinfo' rpcclient -U '%' -N 10.4.10.11 -c 'getdompwinfo'
probe 'smbclient NULL share listing' smbclient -g -N -U '%' -L '//10.4.10.11'

echo
echo '===== WINTERFELL effective controls and recent Remote SAM events ====='
readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"
[[ -x "$ANSIBLE_PLAYBOOK" ]] || { echo "Missing GOAD Ansible runtime: $ANSIBLE_PLAYBOOK" >&2; exit 1; }
ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" "$ANSIBLE_PLAYBOOK" \
    -i "$ROOT/ad/GOAD/data/inventory" -i "$ROOT/workspace/$instance/inventory" \
    -i "$ROOT/globalsettings.ini" "$ROOT/ansible/phase01-rpc-diagnostics.yml"
