#!/usr/bin/env bash
set -euo pipefail

# Direct management for an installed router; never ask VMware for a NAT IP.
provider="${GOAD_PROVIDER_DIR:?Set GOAD_PROVIDER_DIR to the instance provider directory}"
state="${provider}/.vagrant/machines/GOAD-ROUTER/vmware_desktop"
[[ -s "${state}/id" ]] || { echo 'Router instance is not materialized' >&2; exit 1; }
key="${state}/private_key"
if [[ ! -s "${key}" ]]; then
    key="${VAGRANT_HOME:-${HOME}/.vagrant.d}/insecure_private_key"
fi
[[ -s "${key}" ]] || { echo 'Router Vagrant SSH key is missing' >&2; exit 1; }

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

exec ssh -i "${key}" -p 22 \
    -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=5 \
    -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
    -o StrictHostKeyChecking=accept-new \
    -o "UserKnownHostsFile=${state}/management_known_hosts" \
    vagrant@10.4.99.1 "$@"
