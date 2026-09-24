#!/usr/bin/env bash
# Permanent Phase 03 apply entrypoint.
# Current checkpoint is intentionally guard-only and makes no lab changes.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
INSTANCE="${INSTANCE:-cebee3-goad-vmware}"
PROVIDER="${PROVIDER:-$ROOT/workspace/$INSTANCE/provider}"
PLAYBOOK="$ROOT/ansible/phase03.yml"
DATA_INVENTORY="$ROOT/ad/GOAD/data/inventory"
PROVIDER_INVENTORY="${KINGDOMS_PHASE03_INVENTORY:-$ROOT/ad/GOAD/providers/vmware/inventory}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/apply-phase03.sh --confirm

This checkpoint performs the Phase 03 readiness gate and the guarded
Ansible entrypoint only. It does not yet apply vulnerable fixtures.
EOF
}

[[ "${1:-}" == "--confirm" ]] || {
  usage
  exit 2
}

cd "$ROOT" || exit 1
export PATH="$HOME/.goad/.venv/bin:$PATH"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "FAIL: working tree must be clean before Phase 03 apply" >&2
  git status --short >&2
  exit 1
fi

branch="$(git branch --show-current)"
[[ "$branch" == "kingdoms/phase03-overlay" ]] || {
  echo "FAIL: expected kingdoms/phase03-overlay, got $branch" >&2
  exit 1
}

[[ -d "$PROVIDER" ]] || {
  echo "FAIL: provider directory missing: $PROVIDER" >&2
  exit 1
}

[[ -f "$DATA_INVENTORY" ]] || {
  echo "FAIL: GOAD data inventory missing: $DATA_INVENTORY" >&2
  exit 1
}

[[ -f "$PROVIDER_INVENTORY" ]] || {
  echo "FAIL: VMware inventory missing: $PROVIDER_INVENTORY" >&2
  exit 1
}

[[ -f "$PROVIDER/.goad-nomad-mode" ]] || {
  echo "FAIL: exercise-mode marker missing" >&2
  exit 1
}

mode="$(tr -d '[:space:]' < "$PROVIDER/.goad-nomad-mode")"
[[ "$mode" == "exercise" ]] || {
  echo "FAIL: expected exercise mode, got $mode" >&2
  exit 1
}

echo "===== PHASE 03 READINESS ====="
bash scripts/validate-phase03-readiness.sh || exit 1

echo
echo "===== GUARDED PHASE 03 ENTRYPOINT ====="
ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" ansible-playbook   -i "$PROVIDER/inventory"   "$PLAYBOOK"   -e phase03_apply=true

rc=$?
[[ $rc -eq 0 ]] || exit "$rc"

echo
echo "PASS: Phase 03 guarded apply checkpoint completed."
echo "INFO: no state-changing Phase 03 fixture exists in this checkpoint."
