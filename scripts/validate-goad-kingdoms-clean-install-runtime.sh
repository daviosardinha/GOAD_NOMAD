#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

normalize_goad_runtime() {
    # GOAD installs Ansible into its own managed virtualenv. Interactive shells
    # do not necessarily expose that directory in PATH, while several runtime
    # validators intentionally use command -v first. Normalize the canonical
    # GOAD runtime once here so the complete acceptance chain sees the same
    # Ansible installation that ./goad.sh uses.
    local goad_bin="${HOME}/.goad/.venv/bin"
    if [[ -x "${goad_bin}/ansible-playbook" ]]; then
        export PATH="${goad_bin}:${PATH}"
        printf '[INFO] GOAD Ansible runtime: %s\n' "${goad_bin}/ansible-playbook"
    fi
}

resolve_provider() {
    if [[ -n "${GOAD_PROVIDER_DIR:-}" ]]; then
        [[ -d "${GOAD_PROVIDER_DIR}" ]] || fail "GOAD_PROVIDER_DIR does not exist: ${GOAD_PROVIDER_DIR}"
        PROVIDER_DIR="${GOAD_PROVIDER_DIR}"
        return
    fi

    local -a ids=()
    mapfile -t ids < <(
        find "${ROOT}/workspace" \
            -type f \
            -path '*/provider/.vagrant/machines/GOAD-WS01/vmware_desktop/id' \
            -print 2>/dev/null
    )
    [[ ${#ids[@]} -eq 1 ]] || fail 'set GOAD_PROVIDER_DIR to the freshly installed GOAD/VMware provider directory'
    PROVIDER_DIR="${ids[0]%%/.vagrant/*}"
}

printf '\n============================================================\n'
printf 'GOAD KINGDOMS — CLEAN-INSTALL RUNTIME ACCEPTANCE GATE\n'
printf '============================================================\n\n'

normalize_goad_runtime

bash scripts/validate-goad-kingdoms-install-source.sh
pass 'clean-install source contract'

resolve_provider
export GOAD_PROVIDER_DIR="${PROVIDER_DIR}"
printf '[INFO] Provider: %s\n' "${GOAD_PROVIDER_DIR}"

[[ -f "${GOAD_PROVIDER_DIR}/.goad-nomad-mode" ]] || fail 'segmented provider mode state is missing after install'
[[ "$(<"${GOAD_PROVIDER_DIR}/.goad-nomad-mode")" == 'exercise' ]] || fail 'fresh install did not finalize into exercise mode'
pass 'fresh install finalized into exercise mode'

printf '\n=== 1. INHERITED M1 / SEGMENTATION / GOAD RELATIONSHIPS ===\n'
bash scripts/validate-network-segmentation-runtime.sh
pass 'M1 segmentation, trusts, DNS, bots, linked SQL and isolation'

printf '\n=== 2. WS01 FOUNDATION ===\n'
bash scripts/validate-ws01-runtime.sh
pass 'WS01 domain, Rickon foothold, native security and management contract'

printf '\n=== 3. PROMOTED 20-TECHNIQUE LPE PROFILE ===\n'
bash scripts/validate-windows-lpe-promoted-runtime.sh
pass 'all 20 implemented LPE techniques live and vulnerable'

printf '\n=== 4. FINAL EXERCISE ISOLATION ===\n'
status="$(GOAD_PROVIDER_DIR="${GOAD_PROVIDER_DIR}" bash scripts/lab-mode.sh status)"
printf '%s\n' "${status}"
printf '%s\n' "${status}" | grep -Fq 'Recorded mode: exercise' || fail 'final recorded mode is not exercise'
printf '%s\n' "${status}" | grep -Fq 'policy drop;' || fail 'final router policy is not deny-by-default exercise mode'
pass 'final exercise-mode isolation'

printf '\n============================================================\n'
printf '[READY] GOAD Kingdoms clean-install runtime acceptance gate passed.\n'
printf 'Fresh installation reproduced segmentation + GOAD relationships + WS01 + all 20 LPE scenarios.\n'
printf 'Final state: exercise mode; WS01 full-lpe APPLIED / VULNERABLE.\n'
printf '============================================================\n'
