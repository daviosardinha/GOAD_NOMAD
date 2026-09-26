#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROUTES="${ROOT}/scripts/provisioning-routes.sh"
readonly POLICY_DIR="${ROOT}/ad/GOAD/providers/vmware/router/nftables"

readonly DOMAIN_CONTROLLERS=(
    GOAD-DC01
    GOAD-DC02
    GOAD-DC03
)

# When entering exercise mode, restart the child DC before its parent so
# WINTERFELL can initialize while KINGSLANDING is still fully online.
readonly EXERCISE_DOMAIN_CONTROLLERS=(
    GOAD-DC02
    GOAD-DC03
    GOAD-DC01
)

readonly DOMAIN_MEMBERS=(
    GOAD-SRV02
    GOAD-SRV03
    GOAD-WS01
)

# Keep the canonical six-machine list explicit. Several source/runtime
# validators consume this as a compatibility contract, while the grouped arrays
# above control AD-aware transition ordering.
readonly WINDOWS_VMS=(
    GOAD-DC01
    GOAD-DC02
    GOAD-DC03
    GOAD-SRV02
    GOAD-SRV03
    GOAD-WS01
)

declare -A DC_DOMAIN=(
    [GOAD-DC01]="sevenkingdoms.local"
    [GOAD-DC02]="north.sevenkingdoms.local"
    [GOAD-DC03]="essos.local"
)

declare -A DC_FQDN=(
    [GOAD-DC01]="kingslanding.sevenkingdoms.local"
    [GOAD-DC02]="winterfell.north.sevenkingdoms.local"
    [GOAD-DC03]="meereen.essos.local"
)

declare -A MEMBER_DOMAIN=(
    [GOAD-SRV02]="north.sevenkingdoms.local"
    [GOAD-SRV03]="essos.local"
    [GOAD-WS01]="north.sevenkingdoms.local"
)

declare -A MEMBER_DC=(
    [GOAD-SRV02]="winterfell.north.sevenkingdoms.local"
    [GOAD-SRV03]="meereen.essos.local"
    [GOAD-WS01]="winterfell.north.sevenkingdoms.local"
)

declare -A MEMBER_NETBIOS=(
    [GOAD-SRV02]="NORTH"
    [GOAD-SRV03]="ESSOS"
    [GOAD-WS01]="NORTH"
)

fail() {
    echo "[!] $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "Required command not found: $1"
}

resolve_provider() {
    if [[ -n "${GOAD_PROVIDER_DIR:-}" ]]; then
        [[ -d "${GOAD_PROVIDER_DIR}" ]] ||
            fail "GOAD_PROVIDER_DIR does not exist: ${GOAD_PROVIDER_DIR}"

        PROVIDER="${GOAD_PROVIDER_DIR}"
        return
    fi

    local -a ids=()

    mapfile -t ids < <(
        find "${ROOT}/workspace" \
            -type f \
            -path '*/provider/.vagrant/machines/GOAD-ROUTER/vmware_desktop/id' \
            -print 2>/dev/null
    )

    if [[ ${#ids[@]} -eq 0 ]]; then
        fail "No deployed GOAD-ROUTER Vagrant instance found."
    fi

    if [[ ${#ids[@]} -gt 1 ]]; then
        echo "[!] Multiple deployed provider instances found:" >&2
        printf '    %s\n' "${ids[@]}" >&2
        echo >&2
        echo "Set GOAD_PROVIDER_DIR explicitly." >&2
        exit 1
    fi

    PROVIDER="${ids[0]%%/.vagrant/*}"
}

vmx_for() {
    local vm="$1"
    local id_file="${PROVIDER}/.vagrant/machines/${vm}/vmware_desktop/id"

    [[ -f "${id_file}" ]] ||
        fail "Missing Vagrant VM id file for ${vm}"

    local vmx
    vmx="$(cat "${id_file}")"

    [[ -f "${vmx}" ]] ||
        fail "VMX does not exist for ${vm}: ${vmx}"

    printf '%s\n' "${vmx}"
}

is_running() {
    local vmx="$1"

    vmrun -T ws list 2>/dev/null |
        tail -n +2 |
        grep -Fxq "${vmx}"
}

wait_stopped() {
    local vmx="$1"

    for _ in {1..90}; do
        if ! is_running "${vmx}"; then
            return 0
        fi

        sleep 2
    done

    return 1
}

wait_started() {
    local vmx="$1"

    for _ in {1..60}; do
        if is_running "${vmx}"; then
            return 0
        fi

        sleep 2
    done

    return 1
}

get_start_connected() {
    local vmx="$1"
    local line

    line="$(
        grep -Ei \
            '^ethernet0\.startConnected[[:space:]]*=' \
            "${vmx}" |
            tail -n 1 || true
    )"

    if [[ -z "${line}" ]]; then
        echo "UNSET"
        return
    fi

    printf '%s\n' "${line}" |
        sed -E 's/.*"([^"]+)".*/\1/' |
        tr '[:lower:]' '[:upper:]'
}

set_start_connected() {
    local vmx="$1"
    local desired="$2"

    python3 - "${vmx}" "${desired}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
desired = sys.argv[2].upper()

if desired not in {"TRUE", "FALSE"}:
    raise SystemExit(f"Invalid startConnected value: {desired}")

text = path.read_text()

pattern = r'(?im)^\s*ethernet0\.startConnected\s*=.*$'
replacement = f'ethernet0.startConnected = "{desired}"'

if re.search(pattern, text):
    text = re.sub(pattern, replacement, text)
else:
    if not text.endswith("\n"):
        text += "\n"

    text += replacement + "\n"

path.write_text(text)
PY
}

verify_windows_layout() {
    local vm vmx

    for vm in "${WINDOWS_VMS[@]}"; do
        vmx="$(vmx_for "${vm}")"

        grep -Eiq \
            '^ethernet0\.connectiontype = "nat"' \
            "${vmx}" ||
            fail "${vm}: ethernet0 is not VMware NAT; refusing to continue."

        grep -Eiq \
            '^ethernet1\.connectiontype = "custom"' \
            "${vmx}" ||
            fail "${vm}: ethernet1 is not a custom exercise adapter."
    done
}

apply_router_policy() {
    local mode="$1"
    local policy="${POLICY_DIR}/${mode}.nft"

    [[ -f "${policy}" ]] ||
        fail "Missing router policy: ${policy}"

    echo "[*] Applying router ${mode} policy"

    (
        cd "${PROVIDER}"

        cat "${policy}" |
            GOAD_PROVIDER_DIR="${PROVIDER}" bash "${ROOT}/scripts/router-ssh.sh" '
                set -e

                cat > /tmp/goad-nomad-mode.nft

                sudo nft -c \
                    -f /tmp/goad-nomad-mode.nft

                sudo install \
                    -m 0644 \
                    /tmp/goad-nomad-mode.nft \
                    /etc/nftables.conf

                sudo systemctl restart nftables
            '
    )

    echo "[+] Router ${mode} policy active and persistent"
}

ensure_vm_nat_state() {
    local vm="$1"
    local desired="$2"
    local action="$3"

    local vmx
    local current
    local was_running=0

    vmx="$(vmx_for "${vm}")"
    current="$(get_start_connected "${vmx}")"

    printf '    %-12s persistent=%-5s -> %-5s ' \
        "${vm}" \
        "${current}" \
        "${desired}"

    if [[ "${current}" != "${desired}" ]]; then
        if is_running "${vmx}"; then
            was_running=1

            echo
            echo "        [*] stopping VM to update persistent NIC state"

            vmrun -T ws stop "${vmx}" soft >/dev/null

            wait_stopped "${vmx}" ||
                fail "${vm} did not stop cleanly."
        fi

        set_start_connected "${vmx}" "${desired}"

        current="$(get_start_connected "${vmx}")"

        [[ "${current}" == "${desired}" ]] ||
            fail "${vm}: failed to persist ethernet0.startConnected=${desired}"

        if [[ "${was_running}" -eq 1 ]]; then
            echo "        [*] starting VM"

            vmrun -T ws start "${vmx}" nogui >/dev/null

            wait_started "${vmx}" ||
                fail "${vm} did not start."

            sleep 2
        fi
    else
        echo
    fi

    if is_running "${vmx}"; then
        case "${action}" in
            connect)
                vmrun -T ws \
                    connectNamedDevice \
                    "${vmx}" \
                    ethernet0 >/dev/null 2>&1 || true
                ;;

            disconnect)
                vmrun -T ws \
                    disconnectNamedDevice \
                    "${vmx}" \
                    ethernet0 >/dev/null 2>&1 || true
                ;;

            *)
                fail "Unknown VMware device action: ${action}"
                ;;
        esac
    fi

    printf '        [+] ethernet0 startConnected=%s, runtime=%s\n' \
        "${desired}" \
        "${action}"
}

vagrant_powershell_ready() {
    local vm="$1"
    local script="$2"
    local encoded

    encoded="$(
        printf '%s' "${script}" |
            iconv -f UTF-8 -t UTF-16LE |
            base64 -w0
    )"

    (
        cd "${PROVIDER}"
        timeout 90 vagrant winrm "${vm}" -c \
            "powershell.exe -NoProfile -NonInteractive -EncodedCommand ${encoded}"
    ) >/dev/null 2>&1
}

wait_domain_controller_ready() {
    local vm="$1"
    local domain="${DC_DOMAIN[${vm}]}"
    local fqdn="${DC_FQDN[${vm}]}"
    local script
    local attempt

    script="$(cat <<POWERSHELL
\$ErrorActionPreference = 'Stop'
\$Env:ADPS_LoadDefaultDrive = '0'

foreach (\$serviceName in @('NTDS','DNS','ADWS','Netlogon','Kdc','W32Time')) {
    \$service = Get-Service -Name \$serviceName -ErrorAction Stop
    if (\$service.Status -ne 'Running') {
        throw "\$serviceName is \$(\$service.Status)"
    }
}

foreach (\$shareName in @('SYSVOL','NETLOGON')) {
    if (-not (Get-SmbShare -Name \$shareName -ErrorAction SilentlyContinue)) {
        throw "\$shareName share is missing"
    }
}

Import-Module ActiveDirectory -ErrorAction Stop
Get-ADRootDSE -Server '${fqdn}' -ErrorAction Stop | Out-Null
Resolve-DnsName '_ldap._tcp.dc._msdcs.${domain}' -Server 127.0.0.1 -ErrorAction Stop | Out-Null

\$savedPreference = \$ErrorActionPreference
try {
    \$ErrorActionPreference = 'Continue'
    \$nltest = @(& nltest.exe '/dsgetdc:${domain}' /force 2>&1 | ForEach-Object { "\$_" })
    \$nltestRc = \$LASTEXITCODE
}
finally {
    \$ErrorActionPreference = \$savedPreference
}

if (\$nltestRc -ne 0) {
    throw "DC Locator is not ready: \$(\$nltest -join ' ')"
}

Write-Output 'KINGDOMS_DC_RUNTIME_READY'
POWERSHELL
)"

    for attempt in {1..60}; do
        if vagrant_powershell_ready "${vm}" "${script}"; then
            echo "        [+] ${vm} AD runtime ready (${fqdn})"
            return 0
        fi

        if (( attempt % 6 == 0 )); then
            echo "        [*] waiting for ${vm} AD runtime readiness ($((attempt * 5))s)"
        fi

        sleep 5
    done

    fail "${vm} did not regain AD/DC Locator readiness for ${domain} within 300s"
}

wait_domain_member_ready() {
    local vm="$1"
    local domain="${MEMBER_DOMAIN[${vm}]}"
    local dc="${MEMBER_DC[${vm}]}"
    local netbios="${MEMBER_NETBIOS[${vm}]}"
    local script
    local attempt

    script="$(cat <<POWERSHELL
\$ErrorActionPreference = 'Stop'

Resolve-DnsName '${dc}' -ErrorAction Stop | Out-Null

\$healthy = Test-ComputerSecureChannel -Server '${dc}' -ErrorAction Stop
if (-not \$healthy) {
    throw 'computer secure channel is unhealthy'
}

\$account = New-Object System.Security.Principal.NTAccount('${netbios}', 'administrator')
\$null = \$account.Translate([System.Security.Principal.SecurityIdentifier])

\$savedPreference = \$ErrorActionPreference
try {
    \$ErrorActionPreference = 'Continue'
    \$source = (& w32tm.exe /query /source 2>\$null | Out-String).Trim()
    \$sourceRc = \$LASTEXITCODE
}
finally {
    \$ErrorActionPreference = \$savedPreference
}

if (\$sourceRc -ne 0 -or -not \$source -or \$source -match 'Local CMOS Clock') {
    throw "domain time is not ready: \$source"
}

Write-Output 'KINGDOMS_MEMBER_RUNTIME_READY'
POWERSHELL
)"

    for attempt in {1..60}; do
        if vagrant_powershell_ready "${vm}" "${script}"; then
            echo "        [+] ${vm} domain runtime ready (${domain})"
            return 0
        fi

        if (( attempt % 6 == 0 )); then
            echo "        [*] waiting for ${vm} domain runtime readiness ($((attempt * 5))s)"
        fi

        sleep 5
    done

    fail "${vm} did not regain domain identity readiness for ${domain} within 300s"
}

preflight_domain_health() {
    local vm

    echo "[*] Proving AD identity health before isolation restarts"

    for vm in "${DOMAIN_CONTROLLERS[@]}"; do
        wait_domain_controller_ready "${vm}"
    done

    for vm in "${DOMAIN_MEMBERS[@]}"; do
        wait_domain_member_ready "${vm}"
    done

    echo "[+] AD identity preflight passed"
}

configure_windows_nat_provisioning() {
    local vm

    # DCs must be fully advertising before any dependent member is rebooted.
    # Merely seeing the VM process or WinRM is not enough for Netlogon.
    for vm in "${DOMAIN_CONTROLLERS[@]}"; do
        ensure_vm_nat_state "${vm}" TRUE connect
        wait_domain_controller_ready "${vm}"
    done

    for vm in "${DOMAIN_MEMBERS[@]}"; do
        ensure_vm_nat_state "${vm}" TRUE connect
        wait_domain_member_ready "${vm}"
    done
}

prove_isolated_guest_ready() (
    local vm="$1"
    local kind="$2"
    local vmx
    local persistent

    vmx="$(vmx_for "${vm}")"
    persistent="$(get_start_connected "${vmx}")"

    [[ "${persistent}" == "FALSE" ]] ||
        fail "${vm}: exercise readiness probe requires persistent NAT to remain FALSE"

    echo "        [*] temporarily connecting runtime NAT for authenticated readiness"

    vmrun -T ws connectNamedDevice "${vmx}" ethernet0 >/dev/null 2>&1 ||
        fail "${vm}: could not temporarily connect runtime NAT for readiness"

    cleanup_runtime_nat() {
        vmrun -T ws disconnectNamedDevice "${vmx}" ethernet0 >/dev/null 2>&1 || true
    }
    trap cleanup_runtime_nat EXIT

    case "${kind}" in
        member)
            wait_domain_member_ready "${vm}"
            ;;
        dc)
            wait_domain_controller_ready "${vm}"
            ;;
        *)
            fail "Unknown isolated readiness kind for ${vm}: ${kind}"
            ;;
    esac

    cleanup_runtime_nat
    trap - EXIT

    persistent="$(get_start_connected "${vmx}")"
    [[ "${persistent}" == "FALSE" ]] ||
        fail "${vm}: readiness probe changed persistent NAT isolation"

    echo "        [+] ${vm} authenticated post-reboot readiness proven; runtime NAT disconnected"
)

configure_windows_nat_exercise() {
    local vm

    # Members reboot first while their DCs are still healthy. Every restarted
    # guest keeps ethernet0.startConnected=FALSE. The management NIC is then
    # connected only long enough to prove authenticated Windows/domain
    # readiness through Vagrant WinRM and is immediately disconnected again.
    for vm in "${DOMAIN_MEMBERS[@]}"; do
        ensure_vm_nat_state "${vm}" FALSE disconnect
        prove_isolated_guest_ready "${vm}" member
    done

    # Keep parent/child dependencies available while DCs are restarted. The
    # child DC is validated before KINGSLANDING is cycled; MEEREEN is
    # independent; KINGSLANDING is restarted last.
    for vm in "${EXERCISE_DOMAIN_CONTROLLERS[@]}"; do
        ensure_vm_nat_state "${vm}" FALSE disconnect
        prove_isolated_guest_ready "${vm}" dc
    done
}

verify_persistent_state() {
    local desired="$1"
    local vm vmx current
    local failed=0

    echo
    echo "=== PERSISTENT WINDOWS NAT STATE ==="

    for vm in "${WINDOWS_VMS[@]}"; do
        vmx="$(vmx_for "${vm}")"
        current="$(get_start_connected "${vmx}")"

        printf '%-12s ethernet0.startConnected=%s' \
            "${vm}" \
            "${current}"

        if [[ "${current}" == "${desired}" ]]; then
            echo " [OK]"
        else
            echo " [FAIL]"
            failed=1
        fi
    done

    [[ "${failed}" -eq 0 ]] ||
        fail "Persistent Windows NAT state is inconsistent."
}

set_state() {
    printf '%s\n' "$1" > "${PROVIDER}/.goad-nomad-mode"
}

show_status() {
    echo "============================================================"
    echo "GOAD_NOMAD LAB MODE"
    echo "============================================================"

    echo
    printf 'Provider: %s\n' "${PROVIDER}"

    if [[ -f "${PROVIDER}/.goad-nomad-mode" ]]; then
        printf 'Recorded mode: %s\n' \
            "$(cat "${PROVIDER}/.goad-nomad-mode")"
    else
        echo "Recorded mode: unknown / not yet managed"
    fi

    echo
    echo "=== HOST PROVISIONING ROUTES ==="
    bash "${ROUTES}" status

    echo
    echo "=== ROUTER FORWARD POLICY ==="

    (
        cd "${PROVIDER}"

        GOAD_PROVIDER_DIR="${PROVIDER}" bash "${ROOT}/scripts/router-ssh.sh" \
            'sudo nft list chain inet goad_nomad forward'
    )

    echo
    echo "=== WINDOWS VM NETWORK STATE ==="

    local vm vmx current runtime

    for vm in "${WINDOWS_VMS[@]}"; do
        vmx="$(vmx_for "${vm}")"
        current="$(get_start_connected "${vmx}")"

        if is_running "${vmx}"; then
            runtime="running"
        else
            runtime="powered-off"
        fi

        echo "--- ${vm} ---"
        echo "power=${runtime}"
        echo "ethernet0.startConnected=${current}"

        grep -Ei \
            '^ethernet(0|1)\.(connectionType|vnet|present)' \
            "${vmx}" || true
    done
}

enter_exercise_mode() {
    echo "============================================================"
    echo "ENTERING GOAD_NOMAD EXERCISE MODE"
    echo "============================================================"

    sudo -v

    verify_windows_layout

    # While NAT management is still available, prove every DC and member has a
    # working domain identity. This fails closed before any isolation restart.
    if [[ "$(cat "${PROVIDER}/.goad-nomad-mode" 2>/dev/null || true)" != "exercise" ]]; then
        preflight_domain_health
    fi

    #
    # Close routing first so there is never an intermediate
    # state where the host can freely reach protected zones.
    #
    apply_router_policy exercise

    echo
    sudo bash "${ROUTES}" disable

    echo
    echo "[*] Persisting and disconnecting Windows NAT adapters"
    echo "    member/workstation guests first; domain controllers last"

    configure_windows_nat_exercise

    verify_persistent_state FALSE

    set_state exercise

    echo
    echo "[+] GOAD_NOMAD is now in EXERCISE mode."
    echo "    Windows NAT adapters: persistent OFF + disconnected"
    echo "    Protected-zone host routes: removed"
    echo "    Router forwarding: deny-by-default"
}

enter_provisioning_mode() {
    echo "============================================================"
    echo "ENTERING GOAD_NOMAD PROVISIONING MODE"
    echo "============================================================"

    sudo -v

    verify_windows_layout

    #
    # Rebuild the Windows provisioning management plane first.
    #
    echo "[*] Persisting and connecting Windows NAT adapters"
    echo "    domain controllers first with AD readiness; members second"

    configure_windows_nat_provisioning

    verify_persistent_state TRUE

    echo
    apply_router_policy provisioning

    echo
    sudo bash "${ROUTES}" enable

    set_state provisioning

    echo
    echo "[+] GOAD_NOMAD is now in PROVISIONING mode."
    echo "    Windows NAT adapters: persistent ON + connected"
    echo "    Protected-zone host routes: enabled"
    echo "    Router forwarding: temporarily permissive"
}

main() {
    require_command vmrun
    require_command vagrant
    require_command python3
    require_command ip
    require_command timeout
    require_command iconv
    require_command base64

    [[ -f "${ROUTES}" ]] ||
        fail "${ROUTES} is missing."

    [[ -d "${POLICY_DIR}" ]] ||
        fail "${POLICY_DIR} is missing."

    resolve_provider

    case "${1:-status}" in
        exercise)
            enter_exercise_mode
            ;;

        provisioning)
            enter_provisioning_mode
            ;;

        status)
            show_status
            ;;

        *)
            echo "Usage: $0 {exercise|provisioning|status}" >&2
            exit 2
            ;;
    esac
}

main "$@"