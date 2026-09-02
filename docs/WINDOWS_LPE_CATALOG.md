# GOAD Kingdoms — Windows Local Privilege Escalation Catalog

This document tracks the deterministic Windows local-privilege-escalation curriculum for **GOAD-WS01**.

The starting identity is the existing domain user `NORTH\\rickon.stark`. The workstation must remain domain joined, reachable through NORTH, and protected by UAC, Windows Firewall, and Defender unless a specific scenario intentionally changes a narrowly scoped object.

## Framework rules

Every advertised technique must provide all of the following before it is marked implemented:

1. deterministic apply logic;
2. vulnerable-state validation;
3. deterministic reset/cleanup logic;
4. clean-state validation;
5. successful re-apply after reset;
6. Windows-build compatibility evidence for the pinned WS01 image;
7. no accidental weakening of unrelated scenarios or global security controls.

Technique state is explicit:

- **Planned** — catalog entry only; lifecycle operations fail closed.
- **Candidate** — source apply/validate/reset logic exists, but the live reversible gate is still pending for the current committed implementation.
- **Implemented** — the complete live gate passed on the exact current source.

Candidate techniques require an exact `windows_lpe_techniques` selection plus `windows_lpe_allow_candidate=true`. Profiles remain fail-closed while they contain planned or candidate-only members.

## Target catalog

| ID | Family | Status | Notes |
| --- | --- | --- | --- |
| `unquoted_service_path` | Services | **Implemented** | Current batch-safe source passed the Service Batch 1 live promotion gate on 2026-09-02 |
| `weak_service_dacl` | Services | **Implemented** | Dedicated LocalSystem service with low-privilege CHANGE_CONFIG/START/STOP rights; live gate passed |
| `weak_service_binary_permissions` | Services | **Implemented** | Dedicated quoted-path LocalSystem service with writable executable only; live gate passed |
| `weak_service_registry_permissions` | Services / Registry | **Implemented** | Dedicated quoted-path LocalSystem service with Users `SetValue` on its service key; live gate passed |
| `service_dll_hijacking` | Services / DLL | **Implemented** | Dedicated privileged service loads a missing DLL from a Users-writable parent path; live gate passed |
| `path_search_order_hijacking` | Services / PATH | **Candidate** | Isolated LocalSystem PATH lookup with Users-writable preemption directory and protected fallback helper |
| `always_install_elevated` | Policy / Registry | Planned | Per-user and machine installer policy pair |
| `registry_run_keys` | Registry / Autoruns | Planned | Writable privileged autorun configuration |
| `writable_startup_folder` | Startup | Planned | Writable startup execution path |
| `scheduled_task_binary_permissions` | Scheduled tasks | **Candidate** | SYSTEM startup task whose executable is directly modifiable by BUILTIN\\Users |
| `scheduled_task_directory_permissions` | Scheduled tasks | **Candidate** | SYSTEM startup task whose protected executable sits in a directory where Users can delete/create children |
| `unattend_credentials` | Credentials | **Candidate** | Readable Panther answer-file artifact containing credentials for a dedicated local administrator |
| `powershell_history_credentials` | Credentials | Planned | Training-only history artifact |
| `hardcoded_application_credentials` | Credentials | **Candidate** | Readable ProgramData application config containing credentials for a dedicated local administrator |
| `stored_runas_credentials` | Credentials | Planned | Stored RunAs credential scenario |
| `stored_winlogon_credentials` | Credentials / Registry | **Candidate** | Plaintext Winlogon DefaultPassword for a dedicated local administrator; AutoAdminLogon remains disabled |
| `sebackup_privilege` | User rights | Planned | Assigned privilege scenario |
| `seimpersonate_privilege` | User rights / Tokens | Planned | Assigned token-impersonation privilege scenario |
| `writable_program_directory` | Filesystem | Planned | Writable privileged application directory |
| `insecure_service_registry` | Registry / Services | Planned | Additional deterministic service-registry scenario |

The deterministic core target is approximately **18–22** techniques. Patch/build-dependent kernel CVEs are optional and are not part of the core catalog.

## Service Batch 1 — implemented

The first accelerated service batch contains:

```text
unquoted_service_path
weak_service_dacl
weak_service_binary_permissions
weak_service_registry_permissions
service_dll_hijacking
```

The **service batch live promotion gate** executed all five in one lifecycle:

```text
clean WS01 baseline
  -> apply all five
  -> validate all five vulnerable
  -> reset all five
  -> validate all five clean
  -> re-apply all five
  -> validate all five vulnerable
  -> validate WS01 domain/UAC/Firewall/Defender/evaluation baseline
```

On 2026-09-02 the exact origin-synced source at commit `dc1b82fee451a921b53ebae16c0edd2923df2ca3` passed that gate with `unreachable=0` and `failed=0`. The final runtime state intentionally kept all five scenarios applied and vulnerable for training. They are therefore promoted to **Implemented**.

## Current candidate set

### PATH search-order hijacking

`path_search_order_hijacking` completes the planned `service-abuse` family without weakening the five already-live scenarios. A dedicated manual LocalSystem service launches a uniquely named helper by filename. A Users-writable PATH directory precedes a protected fallback directory, while the service binary and fallback helper remain non-writable.

### Scheduled-task permissions batch

`scheduled_task_binary_permissions` grants BUILTIN\\Users Modify on only the executable referenced by a SYSTEM startup task.

`scheduled_task_directory_permissions` keeps its SYSTEM task executable non-writable but grants Users create/delete-child capability on the containing directory, modeling path replacement without collapsing into the direct writable-binary case.

### Credential-discovery batch

The next credential batch contains:

```text
unattend_credentials
hardcoded_application_credentials
stored_winlogon_credentials
```

Each artifact maps to its own dedicated local administrator so discovering one scenario does not automatically solve the others.

`unattend_credentials` places a readable `Kingdom-Unattend.xml` under `C:\Windows\Panther` with a plaintext deployment credential.

`hardcoded_application_credentials` places a readable `monitoring.ini` under `C:\ProgramData\KingdomMonitor` with a local-admin service credential.

`stored_winlogon_credentials` stores a dedicated local-admin username/password in the normal Winlogon `DefaultUserName` / `DefaultPassword` values. It deliberately does **not** enable `AutoAdminLogon`; the vulnerability is credential disclosure, not forced automatic sign-in. The apply path preserves the pre-existing Winlogon values so reset can restore them.

All candidate resets are scoped to their own artifacts/accounts and do not reset the service, PATH, or scheduled-task scenarios already installed.

Candidate testing remains exact and explicit, for example:

```text
windows_lpe_techniques=['unattend_credentials','hardcoded_application_credentials','stored_winlogon_credentials']
windows_lpe_allow_candidate=true
```

Candidates remain **Candidate** until their current committed source passes the reversible live gate:

```text
apply -> vulnerable -> reset -> clean -> re-apply -> vulnerable
```

## Remaining planned profiles and techniques

Profiles remain:

- `service-abuse`
- `credential-hunting`
- `registry-abuse`
- `token-abuse`
- `mixed`
- `full-lpe`

`full-lpe` is intentionally a kitchen-sink profile. Normal learning paths should expose smaller focused sets so enumeration does not simply report every possible weakness at once.

Current checkpoint:

- 20-technique catalog committed;
- five Service Batch 1 techniques are **Implemented** and live on the validated training WS01;
- six additional source-complete techniques are **Candidate**;
- nine techniques remain Planned;
- normal profiles remain fail-closed while they include candidate/planned members;
- candidate testing requires exact selection and explicit opt-in;
- Defender, UAC and Windows Firewall are not globally weakened.
