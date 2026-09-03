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
| `always_install_elevated` | Policy / Registry | **Candidate** | Machine plus Rickon user installer policy pair, with previous values preserved |
| `registry_run_keys` | Registry / Autoruns | **Candidate** | HKLM Run value exists while BUILTIN\\Users can change values on the Run key; prior ACL/value are snapshotted |
| `writable_startup_folder` | Startup | **Candidate** | Common Startup folder grants BUILTIN\\Users Modify; original ACL and marker state are preserved for reset |
| `scheduled_task_binary_permissions` | Scheduled tasks | **Candidate** | SYSTEM startup task executable directly modifiable by Users |
| `scheduled_task_directory_permissions` | Scheduled tasks | **Candidate** | SYSTEM startup task executable replaceable through directory rights |
| `unattend_credentials` | Credentials | **Candidate** | Readable Panther answer-file credential for a local administrator |
| `powershell_history_credentials` | Credentials | **Candidate** | PSReadLine history exposes a dedicated local-admin credential, even before Rickon has an interactive profile |
| `hardcoded_application_credentials` | Credentials | **Candidate** | Readable application config contains a local-admin service credential |
| `stored_runas_credentials` | Credentials | **Candidate** | Rickon's Credential Manager stores a RunAs-compatible Interactive Logon credential for a dedicated local administrator |
| `stored_winlogon_credentials` | Credentials / Registry | **Candidate** | Plaintext Winlogon DefaultPassword for a dedicated local administrator |
| `sebackup_privilege` | User rights | **Candidate** | `NORTH\\rickon.stark` receives SeBackupPrivilege through a scoped LSA account-right assignment |
| `seimpersonate_privilege` | User rights / Tokens | **Candidate** | `NORTH\\rickon.stark` receives SeImpersonatePrivilege through a scoped LSA account-right assignment |
| `writable_program_directory` | Filesystem / Services | **Candidate** | Protected LocalSystem service binary is replaceable through writable Program Files directory rights |
| `insecure_service_registry` | Registry / Services | **Candidate** | Users can alter a custom registry value consumed by a LocalSystem service as an executable path |

The deterministic core target remains 20 techniques. Patch/build-dependent kernel CVEs are optional and are not part of the core catalog.

## Service Batch 1 — implemented

The first five service techniques passed the exact current-source live promotion gate on 2026-09-02 with `unreachable=0` and `failed=0`, ending applied/vulnerable for training.

## Current incremental state

Incremental candidate application has now taken the current WS01 construction state to **18 live scenarios**:

```text
unquoted_service_path
weak_service_dacl
weak_service_binary_permissions
weak_service_registry_permissions
service_dll_hijacking
path_search_order_hijacking
always_install_elevated
scheduled_task_binary_permissions
scheduled_task_directory_permissions
unattend_credentials
powershell_history_credentials
hardcoded_application_credentials
stored_runas_credentials
stored_winlogon_credentials
writable_program_directory
insecure_service_registry
sebackup_privilege
seimpersonate_privilege
```

The user-right candidates alter LSA account-right assignments, not already-issued access tokens. Manual training therefore needs a fresh Rickon interactive logon before `whoami /priv` is expected to expose the new privileges.

The stored RunAs candidate is seeded programmatically in Rickon's credential context using the Windows Interactive Logon credential format. The exact Windows 10 build was compatibility-proven from Rickon's real RDP session: `runas /savecred` launched `WS01\\kingdom.runas` without a password prompt and `whoami` confirmed the target identity. Automated lifecycle validation deliberately does not treat a Scheduled Task batch-logon session as equivalent to that interactive proof.

## Final candidate batch

The final two source-complete candidates are:

```text
registry_run_keys
writable_startup_folder
```

`registry_run_keys` snapshots the existing HKLM Run-key ACL and any pre-existing lab value, creates a harmless lab autorun value, and grants BUILTIN\\Users `SetValue` on the Run key. Reset restores the exact prior ACL/value state.

`writable_startup_folder` snapshots the Common Startup folder ACL and lab marker state, adds a harmless startup marker, and grants BUILTIN\\Users `Modify` on the folder. Reset restores the exact prior ACL and marker state.

All candidate resets remain scoped to their own artifacts/accounts/services/settings and do not reset previously installed scenarios.

Candidates remain **Candidate** until their current committed source passes the reversible live gate:

```text
apply -> vulnerable -> reset -> clean -> re-apply -> vulnerable
```

Current checkpoint:

- 20-technique catalog committed;
- five Service Batch 1 techniques are **Implemented**;
- fifteen additional source-complete techniques are **Candidate**;
- zero techniques remain Planned;
- eighteen scenarios are currently live on WS01 before the final batch is applied;
- normal profiles remain fail-closed while they include candidate members;
- Defender, UAC and Windows Firewall are not globally weakened.
