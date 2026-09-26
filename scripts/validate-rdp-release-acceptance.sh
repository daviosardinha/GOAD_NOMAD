#!/usr/bin/env bash
# Release-only fresh RDP desktop-logon acceptance for the five recovered NORTH
# identities across WINTERFELL, CASTELBLACK and WS01.
#
# This is intentionally separate from validate-rdp-runtime.sh: the normal
# validator is read-only and must never claim that policy evidence proves a
# fresh desktop logon. This release gate performs 15 real RDP attempts.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
DOMAIN_FQDN='north.sevenkingdoms.local'
DOMAIN_NB='NORTH'
RICKON_SERVICE='kingdoms-phase03-rickon.service'

WINTERFELL='10.4.10.11'
CASTELBLACK='10.4.10.22'
WS01='10.4.10.31'

STAMP="$(date +%Y%m%d-%H%M%S)"
EVIDENCE="${KINGDOMS_RDP_RELEASE_EVIDENCE:-$HOME/Kingdoms-evidence/rdp-release-acceptance-$STAMP}"

usage() {
    cat <<'EOF'
Usage: bash scripts/validate-rdp-release-acceptance.sh

Release-only runtime gate. Performs:
  - a five-user SMB credential preflight with isolated NetExec state;
  - fourteen fresh RDP attempts that must end in authorization denial;
  - one fresh NORTH\rickon.stark -> WS01 RDP desktop login;
  - Windows-side proof that the fresh Rickon desktop token is non-admin;
  - restoration and validation of the permanent Phase 03 Rickon session.

No RDP policy/group configuration is changed.
Evidence defaults to ~/Kingdoms-evidence/rdp-release-acceptance-<timestamp>.
Override with KINGDOMS_RDP_RELEASE_EVIDENCE.
EOF
}

if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
    usage
    exit 0
fi
[[ $# -eq 0 ]] || { usage >&2; exit 2; }

cd "$ROOT" || exit 1
mkdir -p "$EVIDENCE"
chmod 700 "$EVIDENCE"

ANSIBLE="${KINGDOMS_RDP_ANSIBLE:-$HOME/.goad/.venv/bin/ansible-playbook}"
INV1="$ROOT/ad/GOAD/data/inventory"
INV2="$ROOT/ad/GOAD/providers/vmware/inventory"

USERS=(hodor brandon.stark jon.snow samwell.tarly rickon.stark)
declare -A PASSWD=(
    [hodor]='hodor'
    [brandon.stark]='iseedeadpeople'
    [jon.snow]='iknownothing'
    [samwell.tarly]='Heartsbane'
    [rickon.stark]='Winter2022'
)

NXC=()
if command -v netexec >/dev/null 2>&1; then
    NXC=(netexec)
elif command -v nxc >/dev/null 2>&1; then
    NXC=(nxc)
fi

TMP_LOGOFF="$(mktemp /tmp/kingdoms-rdp-release-logoff.XXXXXX.yml)"
TMP_PROBE="$(mktemp /tmp/kingdoms-rdp-release-probe.XXXXXX.yml)"
RICKON_RESTORE_REQUIRED=0
RDP_TEST_PID=''

best_effort_restore() {
    local rc=$?

    if [[ -n "$RDP_TEST_PID" ]] && kill -0 "$RDP_TEST_PID" 2>/dev/null; then
        kill -TERM "$RDP_TEST_PID" 2>/dev/null || true
        wait "$RDP_TEST_PID" 2>/dev/null || true
    fi

    if [[ "$RICKON_RESTORE_REQUIRED" -eq 1 ]]; then
        if [[ -x "$ANSIBLE" && -f "$TMP_LOGOFF" ]]; then
            ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg"                 "$ANSIBLE" -i "$INV1" -i "$INV2" "$TMP_LOGOFF"                 >/dev/null 2>&1 || true
        fi
        systemctl --user start "$RICKON_SERVICE" >/dev/null 2>&1 || true
    fi

    rm -f "$TMP_LOGOFF" "$TMP_PROBE"
    return "$rc"
}
trap best_effort_restore EXIT INT TERM

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

for cmd in git nc timeout xvfb-run xfreerdp3 systemctl ss; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing prerequisite: $cmd"
done
[[ -x "$ANSIBLE" ]] || fail "ansible-playbook not found: $ANSIBLE"
[[ -f "$INV1" && -f "$INV2" ]] || fail 'Kingdoms VMware inventories are missing'
[[ ${#NXC[@]} -gt 0 ]] || fail 'NetExec/nxc is required for the credential preflight'

cat >"$TMP_LOGOFF" <<'YAML'
---
- name: Remove only Rickon's WS01 RDP sessions
  hosts: ws01
  gather_facts: false

  tasks:
    - name: Log off Rickon RDP sessions
      ansible.windows.win_powershell:
        script: |
          $ErrorActionPreference = 'Stop'
          $Ansible.Changed = $false
          $lines = @(& quser.exe 2>$null)

          foreach ($line in $lines) {
              if ($line -notmatch '(?i)rickon\.stark') {
                  continue
              }

              if ($line -match '\s+(?<id>\d+)\s+(Active|Disc|Disconnected)\s+') {
                  $id = [int]$Matches['id']
                  Write-Output "LOGOFF_RICKON_SESSION_ID=$id"
                  & logoff.exe $id
                  if ($LASTEXITCODE -ne 0) {
                      throw "logoff.exe failed for Rickon session $id"
                  }
                  $Ansible.Changed = $true
              }
          }

          Write-Output 'RICKON_LOGOFF_COMPLETE=True'
      register: result

    - name: Emit Rickon logoff evidence
      ansible.builtin.debug:
        var: result.output
YAML

cat >"$TMP_PROBE" <<'YAML'
---
- name: Validate fresh Rickon RDP desktop and token
  hosts: ws01
  gather_facts: false

  tasks:
    - name: Inspect fresh Rickon desktop token
      ansible.windows.win_powershell:
        script: |
          $ErrorActionPreference = 'Stop'
          $Ansible.Changed = $false

          $deadline = (Get-Date).AddSeconds(25)
          $active = $null
          $explorer = $null

          while ((Get-Date) -lt $deadline) {
              $sessions = @(& quser.exe 2>$null)
              $active = @(
                  $sessions |
                      Where-Object {
                          $_ -match '(?i)rickon\.stark' -and
                          $_ -match '(?i)\bActive\b'
                      }
              ) | Select-Object -First 1

              $explorer = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue |
                  Where-Object { $_.UserName -ieq 'NORTH\rickon.stark' } |
                  Select-Object -First 1

              if ($active -and $explorer) {
                  break
              }

              Start-Sleep -Seconds 1
          }

          if (-not $active) {
              throw 'No fresh Active Rickon RDP session is visible'
          }
          if (-not $explorer) {
              throw 'Rickon Explorer process is not visible in the fresh desktop session'
          }

          if (-not ('KingdomsFreshTokenProbe' -as [type])) {
              Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class KingdomsFreshTokenProbe {
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(
        IntPtr ProcessHandle,
        UInt32 DesiredAccess,
        out IntPtr TokenHandle
    );

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr Handle);
}
'@
          }

          $token = [IntPtr]::Zero
          if (-not [KingdomsFreshTokenProbe]::OpenProcessToken(
              $explorer.Handle,
              0x0008,
              [ref]$token
          )) {
              throw "OpenProcessToken failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
          }

          try {
              $identity = [System.Security.Principal.WindowsIdentity]::new($token)
              $groups = @($identity.Groups | ForEach-Object { $_.Value })
              $isAdmin = $groups -contains 'S-1-5-32-544'

              Write-Output "FRESH_RDP_SESSION=$($active.Trim())"
              Write-Output "TOKEN_IDENTITY=$($identity.Name)"
              Write-Output "TOKEN_EXPLORER_PID=$($explorer.Id)"
              Write-Output "TOKEN_ADMIN_SID_PRESENT=$isAdmin"

              if ($identity.Name -ine 'NORTH\rickon.stark') {
                  throw "Unexpected token identity: $($identity.Name)"
              }
              if ($isAdmin) {
                  throw 'Rickon fresh desktop token contains BUILTIN\Administrators'
              }
          }
          finally {
              if ($token -ne [IntPtr]::Zero) {
                  [void][KingdomsFreshTokenProbe]::CloseHandle($token)
              }
          }

          Write-Output 'RDP_FRESH_SESSION=PASS'
          Write-Output 'RDP_FRESH_TOKEN_NONADMIN=PASS'
      register: probe

    - name: Emit fresh Rickon token evidence
      ansible.builtin.debug:
        var: probe.output
YAML

run_nxc() {
    local logfile="$1"
    shift
    local raw="${logfile}.raw"
    local nxc_path="$EVIDENCE/nxc"
    mkdir -p "$nxc_path"

    env NXC_PATH="$nxc_path" timeout 45 "${NXC[@]}" "$@" >"$raw" 2>&1
    local rc=$?
    sed -E 's/\x1B\[[0-9;?]*[ -\/]*[@-~]//g' <"$raw" >"$logfile"
    return "$rc"
}

credential_preflight() {
    local user log
    printf '\n===== VALID-CREDENTIAL PRECONDITION =====\n'

    for user in "${USERS[@]}"; do
        log="$EVIDENCE/credential-$user.log"
        run_nxc "$log" smb "$WINTERFELL" -d "$DOMAIN_FQDN"             -u "$user" -p "${PASSWD[$user]}" >/dev/null 2>&1 || true

        if grep -Fq '[+]' "$log"; then
            pass "Credential is valid before RDP testing: $DOMAIN_NB\\$user"
        else
            printf 'Credential preflight evidence: %s\n' "$log" >&2
            fail "Cannot classify later RDP rejection while $DOMAIN_NB\\$user credential validity is unproven"
        fi
    done
}

rdp_client_args() {
    local ip="$1" user="$2"
    printf '%s\n'         "/v:$ip"         "/d:$DOMAIN_NB"         "/u:$user"
    printf '/p:%s\n' "${PASSWD[$user]}"
    printf '%s\n'         '/cert:ignore'         '/size:1024x768'         '/audio-mode:2'         '-clipboard'         '/log-level:INFO'
}

inventory_host_for() {
    case "$1" in
        WINTERFELL) printf '%s' 'dc02' ;;
        CASTELBLACK) printf '%s' 'srv02' ;;
        WS01) printf '%s' 'ws01' ;;
        *) return 1 ;;
    esac
}

run_expected_deny() {
    local host="$1" ip="$2" user="$3"
    local log="$EVIDENCE/${host,,}-$user.log"
    local baseline_log="$EVIDENCE/${host,,}-$user-event-baseline.log"
    local event_log="$EVIDENCE/${host,,}-$user-denial-event.log"
    local inventory_host security_baseline rdpcore_baseline rc event_rc

    inventory_host="$(inventory_host_for "$host")" ||
        fail "No Ansible inventory mapping for $host"

    printf '\n===== EXPECT DENY: %s\\%s -> %s =====\n' "$DOMAIN_NB" "$user" "$host"

    ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" \
        "$ANSIBLE" \
        -i "$INV1" \
        -i "$INV2" \
        ansible/capture-rdp-release-event-baseline.yml \
        -e "rdp_event_target=$inventory_host" \
        >"$baseline_log" 2>&1
    if [[ $? -ne 0 ]]; then
        printf 'Event baseline evidence: %s\n' "$baseline_log" >&2
        tail -80 "$baseline_log" >&2 || true
        fail "Could not capture fresh-event baseline for $host"
    fi

    security_baseline="$(
        grep -oE 'RDP_SECURITY_BASELINE_RECORD_ID=[0-9]+' "$baseline_log" |
            tail -1 | cut -d= -f2
    )"
    rdpcore_baseline="$(
        grep -oE 'RDP_RDPCORE_BASELINE_RECORD_ID=[0-9]+' "$baseline_log" |
            tail -1 | cut -d= -f2
    )"

    [[ "$security_baseline" =~ ^[0-9]+$ ]] ||
        fail "Missing Security event baseline for $host"
    [[ "$rdpcore_baseline" =~ ^[0-9]+$ ]] ||
        fail "Missing RdpCoreTS event baseline for $host"

    rdp_client_args "$ip" "$user" |
        timeout --signal=TERM --kill-after=3s 15s \
            xvfb-run -a -s '-screen 0 1024x768x24 -nolisten tcp' \
            xfreerdp3 /args-from:stdin \
            >"$log" 2>&1
    rc=${PIPESTATUS[1]}

    if [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
        printf 'Unexpected live-session evidence: %s\n' "$log" >&2
        fail "$host unexpectedly kept $DOMAIN_NB\\$user RDP alive"
    fi

    ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg" \
        "$ANSIBLE" \
        -i "$INV1" \
        -i "$INV2" \
        ansible/validate-rdp-denial-event.yml \
        -e "rdp_event_target=$inventory_host" \
        -e "rdp_event_user=$user" \
        -e "rdp_security_after_record_id=$security_baseline" \
        -e "rdp_rdpcore_after_record_id=$rdpcore_baseline" \
        -e 'rdp_event_source=10.4.10.254' \
        >"$event_log" 2>&1
    event_rc=$?

    if [[ "$event_rc" -eq 0 ]] &&
       grep -Fq "RDP_DENIAL_EVENT=PASS|USER=$DOMAIN_NB\\$user|HOST=$host|" "$event_log"; then
        printf 'RDP_MATRIX=%s:%s\\%s:DENY:PASS\n' "$host" "$DOMAIN_NB" "$user"
        return 0
    fi

    printf 'Client evidence: %s\n' "$log" >&2
    printf 'Event baseline evidence: %s\n' "$baseline_log" >&2
    printf 'Server denial evidence: %s\n' "$event_log" >&2
    tail -80 "$event_log" >&2 || true
    fail "$host -> $DOMAIN_NB\\$user did not produce authoritative fresh server-side RDP denial evidence"
}

run_ansible_playbook() {
    local playbook="$1" logfile="$2"
    ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg"         "$ANSIBLE" -i "$INV1" -i "$INV2" "$playbook" 2>&1 | tee "$logfile"
    return ${PIPESTATUS[0]}
}

wait_for_permanent_rickon() {
    local attempt active socket
    for attempt in {1..30}; do
        active="$(systemctl --user is-active "$RICKON_SERVICE" 2>/dev/null || true)"
        socket="$(
            ss -H -nt state established 2>/dev/null |
                grep -E '[[:space:]]10\.4\.10\.31:3389([[:space:]]|$)' ||
                true
        )"

        if [[ "$active" == active && -n "$socket" ]]; then
            pass "Permanent Rickon session restored on attempt $attempt"
            return 0
        fi

        sleep 2
    done

    return 1
}

printf '============================================================\n'
printf 'KINGDOMS — NORTH RDP RELEASE ACCEPTANCE\n'
printf '============================================================\n'
printf 'Evidence: %s\n' "$EVIDENCE"

printf '\n===== SOURCE GATE =====\n'
bash scripts/verify-test-source.sh || fail 'Git source gate failed'

printf '\n===== RDP POLICY PRECONDITION =====\n'
KINGDOMS_RDP_LOG_DIR="$EVIDENCE/policy"     bash scripts/validate-rdp-runtime.sh --bot-mode headless     | tee "$EVIDENCE/rdp-policy.log"
[[ ${PIPESTATUS[0]} -eq 0 ]] || fail 'RDP policy precondition failed'

printf '\n===== RDP LISTENER REACHABILITY =====\n'
for rec in     "WINTERFELL:$WINTERFELL"     "CASTELBLACK:$CASTELBLACK"     "WS01:$WS01"
do
    host="${rec%%:*}"
    ip="${rec##*:}"
    timeout 5 nc -zw3 "$ip" 3389         && pass "$host TCP/3389 reachable"         || fail "$host TCP/3389 unreachable; this is not an authorization denial"
done

credential_preflight

MATRIX_PASS=0
MATRIX_FAIL=0

printf '\n============================================================\n'
printf 'FOURTEEN EXPECTED DENIALS\n'
printf '============================================================\n'

for rec in     "WINTERFELL:$WINTERFELL"     "CASTELBLACK:$CASTELBLACK"     "WS01:$WS01"
do
    host="${rec%%:*}"
    ip="${rec##*:}"

    for user in "${USERS[@]}"; do
        if [[ "$host" == WS01 && "$user" == rickon.stark ]]; then
            continue
        fi

        if run_expected_deny "$host" "$ip" "$user"; then
            MATRIX_PASS=$((MATRIX_PASS + 1))
        else
            MATRIX_FAIL=$((MATRIX_FAIL + 1))
            fail 'Expected-denial matrix stopped at first mismatch'
        fi
    done
done

printf 'EXPECTED_DENIALS_PASS=%d\n' "$MATRIX_PASS"
printf 'EXPECTED_DENIALS_FAIL=%d\n' "$MATRIX_FAIL"
[[ "$MATRIX_PASS" -eq 14 && "$MATRIX_FAIL" -eq 0 ]] ||
    fail 'The fourteen expected RDP denials were not all proven'

printf '\n============================================================\n'
printf 'FRESH ALLOW — NORTH\\rickon.stark -> WS01\n'
printf '============================================================\n'

[[ "$(systemctl --user is-active "$RICKON_SERVICE" 2>/dev/null || true)" == active ]] ||
    fail 'Permanent Rickon service must be healthy before the release-only fresh-login test'

systemctl --user stop "$RICKON_SERVICE" ||
    fail 'Could not stop the permanent Rickon service for the fresh-login test'
RICKON_RESTORE_REQUIRED=1

run_ansible_playbook "$TMP_LOGOFF" "$EVIDENCE/rickon-pre-logoff.log" ||
    fail 'Could not remove the pre-existing Rickon Windows session'

sleep 3
if ss -H -nt state established 2>/dev/null |
    grep -Eq '[[:space:]]10\.4\.10\.31:3389([[:space:]]|$)'; then
    fail 'An operator-host -> WS01 RDP socket still exists after fresh-login preparation'
fi

rdp_client_args "$WS01" rickon.stark |
    timeout --signal=TERM --kill-after=3s 35s         xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp'         xfreerdp3 /args-from:stdin         >"$EVIDENCE/ws01-rickon.stark-fresh.log" 2>&1 &
RDP_TEST_PID=$!

run_ansible_playbook "$TMP_PROBE" "$EVIDENCE/rickon-fresh-token.log" ||
    fail 'Fresh Rickon WS01 desktop/token proof failed'

grep -Fq 'RDP_FRESH_SESSION=PASS' "$EVIDENCE/rickon-fresh-token.log" ||
    fail 'Fresh Rickon desktop marker missing'
grep -Fq 'RDP_FRESH_TOKEN_NONADMIN=PASS' "$EVIDENCE/rickon-fresh-token.log" ||
    fail 'Fresh Rickon non-admin token marker missing'
grep -Fq 'TOKEN_IDENTITY=NORTH\\rickon.stark' "$EVIDENCE/rickon-fresh-token.log" ||
    fail 'Fresh desktop token does not belong to NORTH\\rickon.stark'
grep -Fq 'TOKEN_ADMIN_SID_PRESENT=False' "$EVIDENCE/rickon-fresh-token.log" ||
    fail 'Fresh Rickon desktop token unexpectedly contains BUILTIN\\Administrators'

printf 'RDP_MATRIX=WS01:NORTH\\rickon.stark:ALLOW_NONADMIN:PASS\n'
MATRIX_PASS=$((MATRIX_PASS + 1))

# Allow the bounded temporary client to close, then remove its Windows session.
wait "$RDP_TEST_PID" 2>/dev/null || true
RDP_TEST_PID=''

run_ansible_playbook "$TMP_LOGOFF" "$EVIDENCE/rickon-post-logoff.log" ||
    fail 'Could not clean the temporary fresh Rickon Windows session'

systemctl --user start "$RICKON_SERVICE" ||
    fail 'Could not restore the permanent Rickon service'

wait_for_permanent_rickon ||
    fail 'Permanent Rickon service did not restore its WS01 session'

bash scripts/phase03/validate-rickon-session.sh     | tee "$EVIDENCE/rickon-restored-baseline.log"
[[ ${PIPESTATUS[0]} -eq 0 ]] ||
    fail 'Permanent Rickon baseline did not validate after release acceptance'

RICKON_RESTORE_REQUIRED=0

printf '\n============================================================\n'
printf 'RDP RELEASE ACCEPTANCE RESULT\n'
printf '============================================================\n'
printf 'MATRIX_PASS=%d\n' "$MATRIX_PASS"
printf 'MATRIX_FAIL=%d\n' "$MATRIX_FAIL"
printf 'Evidence=%s\n' "$EVIDENCE"

if [[ "$MATRIX_PASS" -eq 15 && "$MATRIX_FAIL" -eq 0 ]]; then
    printf 'RDP_DESKTOP_LOGON_MATRIX=PASS:15/15\n'
    printf 'RDP_RELEASE_ACCEPTANCE_COMPLETE=True\n'
    exit 0
fi

printf 'RDP_DESKTOP_LOGON_MATRIX=FAIL\n' >&2
exit 1
