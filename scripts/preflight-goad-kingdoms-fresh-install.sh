#!/usr/bin/env bash
# Read-only preflight before creating a fresh GOAD Kingdoms VMware instance.
# It changes no VM, network, instance or repository state.
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly VAGRANTFILE="${ROOT}/ad/GOAD/providers/vmware/Vagrantfile"

PASS=0
WARN=0
FAIL=0
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$*"; }
warn(){ WARN=$((WARN+1)); printf '[WARN] %s\n' "$*" >&2; }
fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$*" >&2; }

cd "${ROOT}"

printf '%s\n' '============================================================'
printf '%s\n' 'GOAD KINGDOMS — FRESH INSTALL PREFLIGHT'
printf '%s\n' '============================================================'

printf '\n===== 1. RELEASE SOURCE =====\n'
branch="$(git branch --show-current)"
if [[ "${branch}" == main ]]; then
    pass 'release branch is main'
else
    fail "fresh install must start from main (current: ${branch:-detached})"
fi

if bash scripts/verify-test-source.sh; then
    pass 'main source matches configured upstream and working tree is clean'
else
    fail 'repository source gate failed'
fi

printf '\n===== 2. CLEAN-INSTALL SOURCE CONTRACT =====\n'
if bash scripts/validate-goad-kingdoms-install-source.sh; then
    pass 'clean-install source contract'
else
    fail 'clean-install source contract failed'
fi

printf '\n===== 3. COMPLETE SOURCE REGRESSION =====\n'
if python3 -m unittest discover -s tests -p 'test_*.py'; then
    pass 'complete Python source regression'
else
    fail 'Python source regression failed'
fi

printf '\n===== 4. HOST TOOLING =====\n'
for command_name in git python3 vagrant vmrun; do
    if command -v "${command_name}" >/dev/null 2>&1; then
        pass "${command_name}: $(command -v "${command_name}")"
    else
        fail "required command missing: ${command_name}"
    fi
done

if sudo -n -v >/dev/null 2>&1; then
    pass 'sudo credential cache is ready'
else
    warn 'sudo is not currently cached; run sudo -v immediately before the install'
fi

printf '\n===== 5. SEGMENTED VMWARE COLLISION PREFLIGHT =====\n'
if [[ ! -f "${VAGRANTFILE}" ]]; then
    fail "canonical VMware Vagrantfile missing: ${VAGRANTFILE}"
else
    mapfile -t protected_macs < <(
        grep -Eo ':mac[[:space:]]*=>[[:space:]]*"([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}"' "${VAGRANTFILE}" |
            sed -E 's/.*"(([[:xdigit:]]{2}:){5}[[:xdigit:]]{2})"/\1/' |
            tr '[:upper:]' '[:lower:]' |
            sort -u
    )

    if [[ ${#protected_macs[@]} -eq 0 ]]; then
        fail 'no deterministic Kingdoms MAC identities found'
    else
        declare -A protected=()
        for mac in "${protected_macs[@]}"; do
            protected["${mac}"]=1
        done

        running_output="$(vmrun -T ws list 2>&1)" || {
            fail 'vmrun could not enumerate running guests'
            running_output=''
        }

        conflicts=()
        while IFS= read -r vmx; do
            [[ -n "${vmx}" ]] || continue
            [[ -f "${vmx}" ]] || {
                fail "running VMX is unreadable: ${vmx}"
                continue
            }

            while IFS= read -r mac; do
                mac="${mac,,}"
                if [[ -n "${protected[${mac}]:-}" ]]; then
                    conflicts+=("${mac}|${vmx}")
                fi
            done < <(
                sed -nE 's/^[Ee][Tt][Hh][Ee][Rr][Nn][Ee][Tt][0-9]+\.[Aa][Dd][Dd][Rr][Ee][Ss][Ss][[:space:]]*=[[:space:]]*"(([[:xdigit:]]{2}:){5}[[:xdigit:]]{2})".*/\1/p' "${vmx}"
            )
        done < <(printf '%s\n' "${running_output}" | tail -n +2)

        if [[ ${#conflicts[@]} -eq 0 ]]; then
            pass 'no running VMware guest owns a deterministic Kingdoms MAC'
        else
            fail 'one or more existing Kingdoms guests are still running'
            for conflict in "${conflicts[@]}"; do
                printf '       MAC=%s VMX=%s\n' "${conflict%%|*}" "${conflict#*|}" >&2
            done
            printf '       Power off the existing segmented instance(s) before creating the fresh one.\n' >&2
        fi
    fi
fi

printf '\n===== 6. EXISTING INSTANCE CONTEXT =====\n'
mapfile -t providers < <(
    find "${ROOT}/workspace" -type f         -path '*/provider/.vagrant/machines/GOAD-WS01/vmware_desktop/id'         -printf '%h\n' 2>/dev/null |
        sed 's#/\.vagrant/machines/GOAD-WS01/vmware_desktop##' |
        sort -u
)

printf 'INSTALLED_PROVIDER_COUNT=%d\n' "${#providers[@]}"
for provider in "${providers[@]}"; do
    printf 'INSTALLED_PROVIDER=%s\n' "${provider}"
done

if [[ ${#providers[@]} -gt 1 ]]; then
    warn 'multiple installed providers exist; post-install runtime validators must receive GOAD_PROVIDER_DIR explicitly'
else
    pass 'provider selection is unambiguous'
fi

printf '\n===== RESULT =====\n'
printf 'PASS: %d\nWARN: %d\nFAIL: %d\n' "${PASS}" "${WARN}" "${FAIL}"

if (( FAIL == 0 )); then
    printf 'KINGDOMS_FRESH_INSTALL_PREFLIGHT_READY=True\n'
    exit 0
fi

printf 'KINGDOMS_FRESH_INSTALL_PREFLIGHT_READY=False\n' >&2
exit 1
