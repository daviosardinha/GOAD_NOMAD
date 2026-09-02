#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SOURCE_GATE="${ROOT}/scripts/verify-test-source.sh"
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

# Git is the source of truth for GOAD Kingdoms. Refuse to validate a local
# repair, dirty checkout, unpushed commit, stale branch, or divergent branch.
# An exact detached candidate can be tested by exporting
# GOAD_KINGDOMS_EXPECTED_COMMIT=<sha> before running this preflight.
[[ -f "${SOURCE_GATE}" ]] || fail "source-of-truth gate is missing: ${SOURCE_GATE}"
bash "${SOURCE_GATE}"
pass "Git source-of-truth gate"

for file in \
    goad_nomad.py \
    goad/provisioner/ansible/ansible.py \
    scripts/lab-mode.sh \
    scripts/provisioning-routes.sh \
    scripts/setup-vmware-networks.sh \
    scripts/check-vmware-networks.sh \
    scripts/verify-test-source.sh \
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
    scripts/verify-test-source.sh \
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
# twice. Inspect executable Python with the AST so comments/docstrings cannot
# create false positives. The console also owns the legacy-compatible NOMAD
# human-readable elapsed timer and must not delegate to the upstream time.ctime
# wrapper. Internal NOMAD identifiers remain compatibility names during the
# public GOAD Kingdoms rename.
python3 - <<'PY'
import ast
from pathlib import Path

console_source = Path('goad_nomad.py').read_text()
ansible_source = Path('goad/provisioner/ansible/ansible.py').read_text()
console_tree = ast.parse(console_source)

method = None
for node in console_tree.body:
    if isinstance(node, ast.ClassDef) and node.name == 'GoadNomad':
        method = next(
            (
                child
                for child in node.body
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef))
                and child.name == 'do_provision_lab'
            ),
            None,
        )
        break

if method is None:
    raise SystemExit('GOAD_NOMAD compatibility do_provision_lab not found')

finalize_calls = [
    node
    for node in ast.walk(method)
    if isinstance(node, ast.Call)
    and (
        (isinstance(node.func, ast.Name) and node.func.id == 'finalize_install')
        or (isinstance(node.func, ast.Attribute) and node.func.attr == 'finalize_install')
    )
]
if finalize_calls:
    raise SystemExit('GOAD_NOMAD compatibility do_provision_lab performs duplicate provider finalization')

legacy_super_calls = [
    node
    for node in ast.walk(method)
    if isinstance(node, ast.Call)
    and isinstance(node.func, ast.Attribute)
    and node.func.attr == 'do_provision_lab'
    and isinstance(node.func.value, ast.Call)
    and isinstance(node.func.value.func, ast.Name)
    and node.func.value.func.id == 'super'
]
if legacy_super_calls:
    raise SystemExit('GOAD_NOMAD compatibility do_provision_lab delegates to legacy upstream timer')

# Remove the function docstring before text checks so explanatory prose cannot
# satisfy or invalidate executable-code assertions.
body = list(method.body)
if (
    body
    and isinstance(body[0], ast.Expr)
    and isinstance(body[0].value, ast.Constant)
    and isinstance(body[0].value.value, str)
):
    body = body[1:]
executable = '\n'.join(ast.unparse(node) for node in body)

if 'get_current_instance_provisioner().run()' not in executable:
    raise SystemExit('GOAD_NOMAD compatibility do_provision_lab does not invoke the provisioner directly')
if 'set_status(READY)' not in executable:
    raise SystemExit('GOAD_NOMAD compatibility do_provision_lab does not set READY after successful finalization')
if '_format_elapsed' not in executable:
    raise SystemExit('GOAD_NOMAD compatibility do_provision_lab does not use the human-readable timer')
if 'return self._finalize_provider_provisioning()' not in ansible_source:
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
echo "[READY] GOAD Kingdoms network-segmentation source preflight passed."
