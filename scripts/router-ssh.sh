#!/usr/bin/env bash
set -euo pipefail

# Direct management for an installed router; never ask VMware for a NAT IP.
provider="${GOAD_PROVIDER_DIR:?Set GOAD_PROVIDER_DIR to the instance provider directory}"
state="${provider}/.vagrant/machines/GOAD-ROUTER/vmware_desktop"
[[ -s "${state}/id" ]] || { echo 'Router instance is not materialized' >&2; exit 1; }

# Reject the known host/router address collision before authenticating.
addresses="$(ip -4 -o addr show dev vmnet99 | awk '{print $4}')"
if grep -Eq '^10\.4\.99\.1/' <<<"${addresses}"; then
    echo 'Host owns router address 10.4.99.1; repair vmnet99 first' >&2
    exit 1
fi
grep -Fxq '10.4.99.254/24' <<<"${addresses}" || {
    echo 'Host management address 10.4.99.254/24 is missing' >&2
    exit 1
}

declare -a candidate_keys=()
instance_key="${state}/private_key"
fallback_key="${VAGRANT_HOME:-${HOME}/.vagrant.d}/insecure_private_key"

[[ -s "${instance_key}" ]] && candidate_keys+=("${instance_key}")
if [[ -s "${fallback_key}" && "${fallback_key}" != "${instance_key}" ]]; then
    candidate_keys+=("${fallback_key}")
fi

(( ${#candidate_keys[@]} > 0 )) || {
    echo 'Router Vagrant SSH key is missing' >&2
    exit 1
}

ssh_common=(
    -p 22
    -o BatchMode=yes
    -o IdentitiesOnly=yes
    -o ConnectTimeout=5
    -o ServerAliveInterval=5
    -o ServerAliveCountMax=2
    -o StrictHostKeyChecking=accept-new
    -o "UserKnownHostsFile=${state}/management_known_hosts"
)

selected_key=''
for key in "${candidate_keys[@]}"; do
    # -n is critical here: authentication probing must never consume stdin
    # because callers pipe nftables policy content into the final SSH command.
    if ssh -n -i "${key}" "${ssh_common[@]}" vagrant@10.4.99.1 true >/dev/null 2>&1; then
        selected_key="${key}"
        break
    fi
done

if [[ -z "${selected_key}" ]]; then
    echo 'Router management SSH authentication failed for every known Vagrant key.' >&2
    printf 'Tried key: %s\n' "${candidate_keys[@]}" >&2
    exit 1
fi

if [[ "${selected_key}" != "${instance_key}" ]]; then
    echo "INFO: router management recovered with fallback Vagrant key: ${selected_key}" >&2
fi

exec ssh -i "${selected_key}" "${ssh_common[@]}" vagrant@10.4.99.1 "$@"
