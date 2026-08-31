#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

warn() {
    echo "[WARN] $*"
}

require_file() {
    [[ -f "$1" ]] || fail "missing required file: $1"
}

require_exec() {
    [[ -x "$1" ]] || fail "expected executable file: $1"
}

for file in \
    scripts/lab-mode.sh \
    scripts/provisioning-routes.sh \
    scripts/setup-vmware-networks.sh \
    scripts/check-vmware-networks.sh \
    ad/GOAD/providers/vmware/router/provision.sh \
    ad/GOAD/providers/vmware/router/nftables/provisioning.nft \
    ad/GOAD/providers/vmware/router/nftables/exercise.nft \
    ansible/roles/child_domain/tasks/main.yml
 do
    require_file "${file}"
 done

for file in \
    scripts/lab-mode.sh \
    scripts/provisioning-routes.sh \
    scripts/setup-vmware-networks.sh \
    scripts/check-vmware-networks.sh \
    scripts/validate-network-segmentation-source.sh
 do
    require_exec "${file}"
 done
pass "user-facing network scripts are executable"

for file in \
    scripts/lab-mode.sh \
    scripts/provisioning-routes.sh \
    scripts/setup-vmware-networks.sh \
    scripts/check-vmware-networks.sh \
    ad/GOAD/providers/vmware/router/provision.sh
 do
    bash -n "${file}"
 done
pass "shell syntax"

python3 -m py_compile \
    goad/config.py \
    goad/provider/vagrant/vmware.py
pass "Python syntax"

if command -v ruby >/dev/null 2>&1; then
    ruby -c ad/GOAD/providers/vmware/Vagrantfile >/dev/null
    ruby -c ad/GOAD/providers/vmware/router/Vagrantfile >/dev/null
    pass "generated VMware Vagrantfile syntax"
else
    warn "ruby not found; skipped Vagrantfile syntax check"
fi

if command -v nft >/dev/null 2>&1; then
    if sudo -n true >/dev/null 2>&1; then
        sudo nft -c -f ad/GOAD/providers/vmware/router/nftables/provisioning.nft
        sudo nft -c -f ad/GOAD/providers/vmware/router/nftables/exercise.nft
        pass "nftables syntax"
    else
        warn "passwordless sudo unavailable; run manually: sudo nft -c -f ad/GOAD/providers/vmware/router/nftables/{provisioning,exercise}.nft"
    fi
else
    warn "nft not found; skipped nftables parser check"
fi

grep -Fq 'name: DNS' ansible/roles/child_domain/tasks/main.yml ||
    fail "child-domain role does not explicitly install DNS"
grep -Fq 'include_management_tools: yes' ansible/roles/child_domain/tasks/main.yml ||
    fail "child-domain role does not install DNS management tools"
grep -Fq -- '-InstallDns:$true' ansible/roles/child_domain/tasks/main.yml ||
    fail "child-domain promotion does not explicitly install DNS"
grep -Fq 'ms_tcpip6' ansible/roles/child_domain/tasks/main.yml ||
    fail "child-domain role does not harden IPv6 on the provisioning NIC"
grep -Fq 'Get-DnsServerZone' ansible/roles/child_domain/tasks/main.yml ||
    fail "child-domain role does not validate the AD-integrated child DNS zone"
pass "Winterfell DNS hardening is present"

grep -Fq 'policy drop;' ad/GOAD/providers/vmware/router/nftables/exercise.nft ||
    fail "exercise policy is not deny-by-default"
grep -Fq '10.4.10.22 ip daddr 10.4.30.23 tcp dport 1433' ad/GOAD/providers/vmware/router/nftables/exercise.nft ||
    fail "Castelblack -> Braavos linked-SQL rule is missing"
grep -Fq '10.4.10.11 ip daddr 10.4.30.12 udp dport 53' ad/GOAD/providers/vmware/router/nftables/exercise.nft ||
    fail "Winterfell -> Meereen conditional-DNS rule is missing"
pass "validated exercise firewall relationships are present"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --check
    pass "git whitespace check"
fi

echo
echo "[READY] GOAD_NOMAD network-segmentation source preflight passed."
