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

for file in \
    goad_nomad.py \
    goad/provisioner/ansible/ansible.py \
    scripts/lab-mode.sh \
    scripts/provisioning-routes.sh \
    scripts/setup-vmware-networks.sh \
    scripts/check-vmware-networks.sh \
    scripts/validate-network-segmentation.sh \
    scripts/validate-network-segmentation-runtime.sh \
    scripts/validate-network-segmentation-source.sh \
    ad/GOAD/providers/vmware/router/provision.sh \
    ad/GOAD/providers/vmware/router/nftables/provisioning.nft \
    ad/GOAD/providers/vmware/router/nftables/exercise.nft \
    ansible/roles/child_domain/tasks/main.yml
 do
    require_file "${file}"
 done
pass "required network-segmentation source files are present"

# lab-mode.sh is the user-facing mode controller and must retain its executable
# bit in Git. Supporting helpers are deliberately invoked through bash by the
# project so archive/copy operations cannot break them solely by stripping mode
# bits.
[[ -x scripts/lab-mode.sh ]] || fail "scripts/lab-mode.sh is not executable"
pass "lab-mode.sh executable bit"

for file in \
    scripts/lab-mode.sh \
    scripts/provisioning-routes.sh \
    scripts/setup-vmware-networks.sh \
    scripts/check-vmware-networks.sh \
    scripts/validate-network-segmentation.sh \
    scripts/validate-network-segmentation-runtime.sh \
    scripts/validate-network-segmentation-source.sh \
    ad/GOAD/providers/vmware/router/provision.sh
 do
    bash -n "${file}"
 done
pass "shell syntax"

python3 -m py_compile \
    goad/config.py \
    goad_nomad.py \
    goad/provider/vagrant/vmware.py \
    goad/provisioner/ansible/ansible.py
pass "Python syntax"

if command -v ruby >/dev/null 2>&1; then
    ruby -c ad/GOAD/providers/vmware/Vagrantfile >/dev/null
    ruby -c ad/GOAD/providers/vmware/router/Vagrantfile >/dev/null
    pass "VMware Vagrantfile syntax"
else
    warn "ruby not found; skipped Vagrantfile syntax check"
fi

if command -v nft >/dev/null 2>&1; then
    if sudo -n true >/dev/null 2>&1; then
        sudo nft -c -f ad/GOAD/providers/vmware/router/nftables/provisioning.nft
        sudo nft -c -f ad/GOAD/providers/vmware/router/nftables/exercise.nft
        pass "nftables syntax"
    else
        warn "passwordless sudo unavailable; run manually: sudo nft -c -f ad/GOAD/providers/vmware/router/nftables/provisioning.nft && sudo nft -c -f ad/GOAD/providers/vmware/router/nftables/exercise.nft"
    fi
else
    warn "nft not found; skipped nftables parser check"
fi

# A full Ansible run owns provider finalization. The console must not call the
# same finalizer again, otherwise a successful install enters exercise mode
# twice. The console also owns the GOAD_NOMAD human-readable elapsed timer and
# must not delegate to the upstream time.ctime-based provisioning wrapper.
python3 - <<'PY'
from pathlib import Path

console = Path('goad_nomad.py').read_text()
ansible = Path('goad/provisioner/ansible/ansible.py').read_text()

start = console.index('    def do_provision_lab(')
end = console.index('\n    def do_help(', start)
block = console[start:end]

if 'super().do_provision_lab' in block:
    raise SystemExit('GOAD_NOMAD do_provision_lab delegates to legacy upstream timer')
if 'finalize_install' in block:
    raise SystemExit('GOAD_NOMAD do_provision_lab performs duplicate provider finalization')
if 'get_current_instance_provisioner().run()' not in block:
    raise SystemExit('GOAD_NOMAD do_provision_lab does not invoke the provisioner directly')
if 'set_status(READY)' not in block:
    raise SystemExit('GOAD_NOMAD do_provision_lab does not set READY after successful finalization')
if '_format_elapsed' not in block:
    raise SystemExit('GOAD_NOMAD do_provision_lab does not use the human-readable timer')
if 'return self._finalize_provider_provisioning()' not in ansible:
    raise SystemExit('Ansible full-lab run no longer owns provider finalization')
PY
pass "single final-isolation owner and human-readable install timer"

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
grep -Fq 'name: ADWS' ansible/roles/child_domain/tasks/main.yml ||
    fail "child-domain role does not manage Active Directory Web Services"
grep -Fq 'state: started' ansible/roles/child_domain/tasks/main.yml ||
    fail "child-domain role does not ensure required Windows services are started"
pass "Winterfell DNS / ADWS hardening is present"

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
