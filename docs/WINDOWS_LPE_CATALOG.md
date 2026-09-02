# GOAD Kingdoms — Windows Local Privilege Escalation Catalog

This document tracks the deterministic Windows local-privilege-escalation curriculum for **GOAD-WS01**.

The starting identity is the existing domain user `NORTH\\rickon.stark`. The workstation must remain domain joined, reachable through NORTH, and protected by UAC, Windows Firewall, and Defender unless a specific scenario intentionally changes a narrowly scoped object.

## Framework rules

Every advertised technique must provide deterministic apply, vulnerable-state validation, reset, clean-state validation, successful re-apply, pinned-build compatibility evidence, and isolation from unrelated scenarios/security controls.

Technique state is explicit:

- **Planned** — catalog entry only; lifecycle operations fail closed.
- **Candidate** — source apply/validate/reset logic exists, but the live reversible gate is still pending for the current committed implementation.
- **Implemented** — the complete live gate passed on the exact current source.

Candidate techniques require an exact `windows_lpe_techniques` selection plus `windows_lpe_allow_candidate=true`.

## Target catalog

| ID | Family | Status | Notes |
| --- | --- | --- | --- |
| `unquoted_service_path` | Services | **Implemented** | Service Batch 1 live gate passed |
| `weak_service_dacl` | Services | **Implemented** | Dedicated LocalSystem service with CHANGE_CONFIG/START/STOP rights |
| `weak_service_binary_permissions` | Services | **Implemented** | Quoted LocalSystem service with directly writable executable |
| `weak_service_registry_permissions` | Services / Registry | **Implemented** | Users can alter SCM service registry configuration |
| `service_dll_hijacking` | Services / DLL | **Implemented** | Privileged service loads a missing DLL from a writable location |
| `path_search_order_hijacking` | Services / PATH | **Candidate** | Users-writable PATH preemption directory before protected helper |
| `always_install_elevated` | Policy / Registry | Planned | Per-user and machine installer policy pair |
| `registry_run_keys` | Registry / Autoruns | Planned | Writable privileged autorun configuration |
| `writable_startup_folder` | Startup | Planned | Writable startup execution path |
| `scheduled_task_binary_permissions` | Scheduled tasks | **Candidate** | SYSTEM startup task executable directly modifiable by Users |
| `scheduled_task_directory_permissions` | Scheduled tasks | **Candidate** | SYSTEM startup task executable replaceable through directory rights |
| `unattend_credentials` | Credentials | **Candidate** | Readable Panther answer-file credential for a local administrator |
| `powershell_history_credentials` | Credentials | **Candidate** | Rickon's PSReadLine history contains a dedicated local-admin credential |
| `hardcoded_application_credentials` | Credentials | **Candidate** | Readable application config contains a local-admin service credential |
| `stored_runas_credentials` | Credentials | Planned | Stored RunAs credential scenario |
| `stored_winlogon_credentials` | Credentials / Registry | **Candidate** | Plaintext Winlogon DefaultPassword for a dedicated local administrator |
| `sebackup_privilege` | User rights | Planned | Assigned privilege scenario |
| `seimpersonate_privilege` | User rights / Tokens | Planned | Assigned token-impersonation privilege scenario |
| `writable_program_directory` | Filesystem / Services | **Candidate** | Protected LocalSystem service binary is replaceable through writable Program Files directory rights |
| `insecure_service_registry` | Registry / Services | **Candidate** | Users can alter a custom registry value consumed by a LocalSystem service as an executable path |

The deterministic core target remains 20 techniques. Patch/build-dependent kernel CVEs are optional and are not part of the core catalog.

## Service Batch 1 — implemented

The first five service techniques passed the exact current-source live promotion gate on 2026-09-02 with `unreachable=0` and `failed=0`, ending applied/vulnerable for training.

## Current candidate set

Already applied during incremental construction:

```text
path_search_order_hijacking
scheduled_task_binary_permissions
scheduled_task_directory_permissions
unattend_credentials
hardcoded_application_credentials
stored_winlogon_credentials
```

The next incremental batch adds:

```text
powershell_history_credentials
writable_program_directory
insecure_service_registry
```

`powershell_history_credentials` resolves the actual `NORTH\\rickon.stark` profile through its SID/ProfileList entry and injects one unique PSReadLine history command containing credentials for a dedicated local administrator. Reset removes only that exact training line and account, preserving unrelated PowerShell history.

`writable_program_directory` creates a dedicated manual LocalSystem service under `C:\Program Files\Kingdom Agent`. The executable itself is protected and only readable by Users, while the containing directory grants create/delete-child capability. Users can START/STOP the service but cannot reconfigure it, keeping this distinct from the weak-service-DACL and direct-writable-binary scenarios.

`insecure_service_registry` creates a dedicated LocalSystem service whose protected binary reads `HelperPath` from `HKLM:\SOFTWARE\GOAD Kingdoms\KingdomConfigSvc`. BUILTIN\\Users receive only `SetValue` on that custom configuration key. The service executable and legitimate helper remain non-writable, separating this from the existing SCM service-registry weakness.

All candidate resets are scoped to their own artifacts/accounts/services and do not reset previously installed scenarios.

Candidates remain **Candidate** until their current committed source passes the reversible live gate:

```text
apply -> vulnerable -> reset -> clean -> re-apply -> vulnerable
```

## Remaining planned techniques

After this batch the remaining planned set is:

```text
always_install_elevated
registry_run_keys
writable_startup_folder
stored_runas_credentials
sebackup_privilege
seimpersonate_privilege
```

Current checkpoint:

- 20-technique catalog committed;
- five Service Batch 1 techniques are **Implemented**;
- nine additional source-complete techniques are **Candidate**;
- six techniques remain Planned;
- normal profiles remain fail-closed while they include candidate/planned members;
- Defender, UAC and Windows Firewall are not globally weakened.
