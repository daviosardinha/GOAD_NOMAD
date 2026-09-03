#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

bash scripts/verify-test-source.sh
pass "Git source-of-truth gate"

python3 -m py_compile goad/provider/vagrant/vmware_kingdoms.py
pass "GOAD Kingdoms VMware provider syntax"

python3 - <<'PY'
import ast
from pathlib import Path

source = Path('goad/provider/vagrant/vmware_kingdoms.py').read_text()
tree = ast.parse(source)
provider = next(
    node for node in tree.body
    if isinstance(node, ast.ClassDef) and node.name == 'GoadKingdomsVmwareProvider'
)

methods = {
    node.name: node
    for node in provider.body
    if isinstance(node, ast.FunctionDef)
}

required = {'_require_cached_sudo', 'prepare_install', 'set_runtime_mode'}
missing = sorted(required - methods.keys())
if missing:
    raise SystemExit(f'missing sudo-preflight methods: {missing}')

sudo_method = methods['_require_cached_sudo']
valid_probe = False
for call in ast.walk(sudo_method):
    if not isinstance(call, ast.Call):
        continue
    if not (
        isinstance(call.func, ast.Attribute)
        and isinstance(call.func.value, ast.Name)
        and call.func.value.id == 'subprocess'
        and call.func.attr == 'run'
    ):
        continue
    if not call.args or not isinstance(call.args[0], (ast.List, ast.Tuple)):
        continue
    values = []
    for item in call.args[0].elts:
        if not isinstance(item, ast.Constant):
            break
        values.append(item.value)
    if values == ['sudo', '-n', '-v']:
        valid_probe = True
        break

if not valid_probe:
    raise SystemExit('sudo preflight is not exactly `sudo -n -v`')

if 'run `sudo -v` in this terminal' not in source:
    raise SystemExit('sudo failure does not give an explicit operator recovery instruction')

for method_name in ('prepare_install', 'set_runtime_mode'):
    method = methods[method_name]
    calls = [
        node for node in ast.walk(method)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == 'self'
        and node.func.attr == '_require_cached_sudo'
    ]
    if not calls:
        raise SystemExit(f'{method_name} does not enforce cached sudo')

# prepare_install must perform the sudo check before delegating to the M1
# implementation, so a missing sudo cache cannot power on/configure guests.
prepare_text = ast.unparse(methods['prepare_install'])
if prepare_text.find('_require_cached_sudo') > prepare_text.find('super().prepare_install'):
    raise SystemExit('prepare_install enters the M1 lifecycle before sudo preflight')

# set_runtime_mode must gate every provisioning/exercise transition before the
# compatibility controller can execute its legacy sudo calls.
mode_text = ast.unparse(methods['set_runtime_mode'])
if mode_text.find('_require_cached_sudo') > mode_text.find('super().set_runtime_mode'):
    raise SystemExit('set_runtime_mode enters compatibility controller before sudo preflight')
PY
pass "non-interactive sudo lifecycle contract"

git diff --check
pass "Git whitespace check"

printf '\n[READY] GOAD Kingdoms sudo preflight source validation passed.\n'
