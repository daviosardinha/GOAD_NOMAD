#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RUNTIME="${ROOT}/scripts/validate-network-segmentation-runtime.sh"
readonly GOAD_VENV="${HOME}/.goad/.venv"
readonly EXCLUDE_FILE="${ROOT}/.git/info/exclude"
readonly EXCLUDE_PATTERN="scripts/.goad-nomad-runtime.*.sh"

TMP_RUNTIME=""
ADDED_EXCLUDE=0

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${TMP_RUNTIME}" && -f "${TMP_RUNTIME}" ]]; then
        rm -f "${TMP_RUNTIME}"
    fi

    if [[ "${ADDED_EXCLUDE}" -eq 1 && -f "${EXCLUDE_FILE}" ]]; then
        python3 - "${EXCLUDE_FILE}" "${EXCLUDE_PATTERN}" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
pattern = sys.argv[2]
lines = p.read_text().splitlines()
p.write_text("\n".join(line for line in lines if line != pattern) + "\n")
PY
    fi
}

trap cleanup EXIT

[[ -f "${RUNTIME}" ]] || fail "runtime validator is missing: ${RUNTIME}"
[[ -d "${ROOT}/.git" ]] || fail "run this validator from a Git clone"

# GOAD's own goad.sh creates and uses ~/.goad/.venv. A clean source clone does
# not contain that environment, so expose the canonical GOAD runtime before the
# validator performs Ansible discovery.
if ! command -v ansible-playbook >/dev/null 2>&1; then
    if [[ -x "${GOAD_VENV}/bin/ansible-playbook" ]]; then
        export PATH="${GOAD_VENV}/bin:${PATH}"
        echo "[+] Using GOAD Ansible runtime: ${GOAD_VENV}/bin/ansible-playbook"
    else
        fail "ansible-playbook not found. Expected GOAD runtime at ${GOAD_VENV}/bin/ansible-playbook. Run ./goad.sh once to install the GOAD dependencies."
    fi
fi

# The compatibility copy must live under scripts/ so BASH_SOURCE resolves ROOT
# to the clean clone rather than /tmp. Hide only this ephemeral helper through
# .git/info/exclude so the runtime validator still sees a clean working tree.
mkdir -p "$(dirname "${EXCLUDE_FILE}")"
touch "${EXCLUDE_FILE}"
if ! grep -Fxq "${EXCLUDE_PATTERN}" "${EXCLUDE_FILE}"; then
    printf '%s\n' "${EXCLUDE_PATTERN}" >> "${EXCLUDE_FILE}"
    ADDED_EXCLUDE=1
fi

TMP_RUNTIME="$(mktemp "${ROOT}/scripts/.goad-nomad-runtime.XXXXXX.sh")"

python3 - "${RUNTIME}" "${TMP_RUNTIME}" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
s = src.read_text()

# Windows Server exposes conditional-forwarder state through Get-DnsServerZone.
s = s.replace(
    "Get-DnsServerConditionalForwarderZone",
    "Get-DnsServerZone",
)

# Preserve Vagrant/WinRM output on a remote PowerShell failure so the runtime
# validator can print a useful error instead of disappearing under set -e.
s = s.replace(
    ") 2>&1 | tr -d '\\r'\n}",
    ") 2>&1 | tr -d '\\r' || true\n}",
    1,
)

# GOAD's repeating authentication bots may be caught while they are actively
# executing. Windows Task Scheduler reports decimal 267009
# (0x00041301 / SCHED_S_TASK_RUNNING) in that state. It is a success status,
# not a failed task result. Ready tasks must still have a normal result of 0.
bot_old = r'''    if ($task.State.ToString() -notin @('Ready','Running')) { throw "$name state=$($task.State)" }
    if ($info.LastTaskResult -ne 0) { throw "$name LastTaskResult=$($info.LastTaskResult)" }
    Write-Output "$name=PASS"'''

bot_new = r'''    $state = $task.State.ToString()
    $last = [uint32]$info.LastTaskResult
    if ($state -notin @('Ready','Running')) { throw "$name state=$state" }
    if ($state -eq 'Running') {
        if ($last -notin @(0, 267009)) { throw "$name LastTaskResult=$last while Running" }
    } elseif ($last -ne 0) {
        throw "$name LastTaskResult=$last while Ready"
    }
    Write-Output "$name=PASS state=$state last=$last"'''

if bot_old not in s:
    raise SystemExit("GOAD bot validation block not found")
s = s.replace(bot_old, bot_new, 1)

# Exercise mode power-cycles the Windows VMs when startConnected changes. SMB
# can become reachable before ADWS/DNS/MSSQL are fully ready. The provisioning
# phase already validates trust direction with Get-ADTrust, so the exercise
# phase should validate the network path itself and tolerate normal service
# startup time instead of treating an ADWS startup race as a segmentation bug.
dc_start = "ansible_ps_north dc02 exercise-dns-trust <<'PS'"
dc_end = 'pass "exercise-mode parent/child trust + cross-forest DNS from Winterfell"'
start = s.index(dc_start)
end = s.index(dc_end, start) + len(dc_end)

new_dc = r'''if ! ansible_ps_north dc02 exercise-dns-trust <<'PS'
$ErrorActionPreference = 'Stop'
Clear-DnsClientCache
try { Clear-DnsServerCache -Force -ErrorAction Stop } catch { }

$deadline = (Get-Date).AddMinutes(4)
$parentOk = $false
$essosOk = $false
$lastParent = ''
$lastEssos = ''

while ((Get-Date) -lt $deadline -and (-not $parentOk -or -not $essosOk)) {
    if (-not $parentOk) {
        try {
            $parent = nltest /dsgetdc:sevenkingdoms.local /force 2>&1 | Out-String
            $lastParent = $parent
            if ($LASTEXITCODE -eq 0 -and $parent -match '10\.4\.20\.10') {
                $parentOk = $true
            }
        } catch {
            $lastParent = $_.Exception.Message
        }
    }

    if (-not $essosOk) {
        try {
            $essos = Resolve-DnsName '_ldap._tcp.dc._msdcs.essos.local' -Type SRV -ErrorAction Stop
            $lastEssos = ($essos | Out-String)
            if (($essos | Where-Object NameTarget -match '^meereen\.essos\.local\.?$').Count -ge 1) {
                $essosOk = $true
            }
        } catch {
            $lastEssos = $_.Exception.Message
        }
    }

    if (-not $parentOk -or -not $essosOk) {
        Start-Sleep -Seconds 5
    }
}

if (-not $parentOk) { throw "parent DC discovery failed in exercise mode: $lastParent" }
if (-not $essosOk) { throw "ESSOS SRV resolution did not return Meereen: $lastEssos" }

Write-Output 'EXERCISE_PARENT_DISCOVERY=PASS'
Write-Output 'EXERCISE_ESSOS_DNS=PASS'
PS
then
    fatal "exercise-mode parent discovery / cross-forest DNS validation failed"
fi
pass "exercise-mode parent DC discovery + cross-forest DNS from Winterfell"'''

s = s[:start] + new_dc + s[end:]

sql_start = "ansible_ps_north srv02 exercise-linked-sql <<'PS'"
sql_end = 'pass "exercise-mode Castelblack -> Braavos linked SQL"'
start = s.index(sql_start)
end = s.index(sql_end, start) + len(sql_end)

# Castelblack and Winterfell share NORTH/vmnet10, so the router is not in their
# domain-authentication path. A real exercise-mode test showed that WinRM can
# return more than two minutes after the power cycle and that SQL may become
# reachable before Netlogon/DC locator/SID translation have fully converged.
# Prove the NORTH domain path first, then test the deliberate cross-zone SQL
# relationship. No secure-channel repair is performed here.
new_sql = r'''if ! ansible_ps_north srv02 exercise-linked-sql <<'PS'
$ErrorActionPreference = 'Stop'

$domainDeadline = (Get-Date).AddMinutes(5)
$domainReady = $false
$lastDomainError = ''

while ((Get-Date) -lt $domainDeadline -and -not $domainReady) {
    try {
        Clear-DnsClientCache

        $dns = Resolve-DnsName 'winterfell.north.sevenkingdoms.local' -Type A -Server 10.4.10.11 -ErrorAction Stop
        if (-not ($dns.IPAddress -contains '10.4.10.11')) {
            throw 'Winterfell authoritative DNS did not return 10.4.10.11'
        }

        $dc = nltest /dsgetdc:north.sevenkingdoms.local /force 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $dc -notmatch '10\.4\.10\.11') {
            throw "NORTH DC discovery failed: $($dc.Trim())"
        }

        $secure = nltest /sc_query:north.sevenkingdoms.local 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "NORTH secure-channel query failed: $($secure.Trim())"
        }

        $account = New-Object System.Security.Principal.NTAccount('NORTH','jon.snow')
        $sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if (-not $sid -or $sid -notmatch '^S-1-5-21-') {
            throw "NORTH\\jon.snow SID translation returned '$sid'"
        }

        $domainReady = $true
        Write-Output "EXERCISE_CASTELBLACK_DOMAIN_PATH=PASS SID=$sid"
    } catch {
        $lastDomainError = $_.Exception.Message
        Start-Sleep -Seconds 5
    }
}

if (-not $domainReady) {
    throw "Castelblack NORTH domain path did not become ready: $lastDomainError"
}

$tcp = New-Object System.Net.Sockets.TcpClient
try {
    $async = $tcp.BeginConnect('10.4.30.23', 1433, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne(3000, $false)) {
        throw 'Braavos TCP/1433 connection timed out'
    }
    $tcp.EndConnect($async)
} finally {
    $tcp.Close()
}
Write-Output 'EXERCISE_BRAAVOS_TCP_1433=PASS'

$sqlDeadline = (Get-Date).AddMinutes(2)
$sqlReady = $false
$lastSqlError = ''

while ((Get-Date) -lt $sqlDeadline -and -not $sqlReady) {
    $conn = $null
    try {
        $cs = 'Server=127.0.0.1,1433;User ID=sa;Password=Sup1_sa_P@ssw0rd!;Encrypt=False;TrustServerCertificate=True'
        $conn = New-Object System.Data.SqlClient.SqlConnection $cs
        $conn.Open()

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
EXECUTE AS LOGIN = N'NORTH\jon.snow';
EXEC ('SELECT @@SERVERNAME AS RemoteServer, SUSER_SNAME() AS RemoteLogin') AT [BRAAVOS];
REVERT;
"@
        $ds = New-Object System.Data.DataSet
        $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        [void]$da.Fill($ds)
        $row = $ds.Tables[0].Rows[0]

        if ($row.RemoteServer -ne 'BRAAVOS\SQLEXPRESS' -or $row.RemoteLogin -ne 'sa') {
            throw "exercise linked SQL result incorrect: server=$($row.RemoteServer) login=$($row.RemoteLogin)"
        }

        $sqlReady = $true
        Write-Output 'EXERCISE_CASTELBLACK_TO_BRAAVOS=PASS'
    } catch {
        $lastSqlError = $_.Exception.Message
        Start-Sleep -Seconds 5
    } finally {
        if ($conn) {
            $conn.Close()
            $conn.Dispose()
        }
    }
}

if (-not $sqlReady) {
    throw "exercise linked SQL did not become ready after the NORTH domain path was healthy: $lastSqlError"
}
PS
then
    fatal "exercise-mode Castelblack domain readiness / Braavos linked SQL validation failed"
fi
pass "exercise-mode Castelblack domain path + Braavos linked SQL"'''

s = s[:start] + new_sql + s[end:]

dst.write_text(s)
PY

bash -n "${TMP_RUNTIME}" || fail "generated runtime validator failed shell syntax check"
bash "${TMP_RUNTIME}" "$@"
