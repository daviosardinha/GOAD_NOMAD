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
| `registry_run_keys` | Registry / Autoruns | Planned | Writable privileged autorun configuration |
| `writable_startup_folder` | Startup | Planned | Writable startup execution path |
| `scheduled_task_binary_permissions` | Scheduled tasks | **Candidate** | SYSTEM startup task executable directly modifiable by Users |
| `scheduled_task_directory_permissions` | Scheduled tasks | **Candidate** | SYSTEM startup task executable replaceable through directory rights |
| `unattend_credentials` | Credentials | **Candidate** | Readable Panther answer-file credential for a local administrator |
| `powershell_history_credentials` | Credentials | **Candidate** | PSReadLine history exposes a dedicated local-admin credential, even before Rickon has an interactive profile |
| `hardcoded_application_credentials` | Credentials | **Candidate** | Readable application config contains a local-admin service credential |
| `stored_runas_credentials` | Credentials | **Candidate** | Rickon's Windows Credential Manager stores a credential for a dedicated local administrator |
| `stored_winlogon_credentials` | Credentials / Registry | **Candidate** | Plaintext Winlogon DefaultPassword for a dedicated local administrator |
| `sebackup_privilege` | User rights | **Candidate** | `NORTH\\rickon.stark` receives SeBackupPrivilege through a scoped LSA account-right assignment |
| `seimpersonate_privilege` | User rights / Tokens | **Candidate** | `NORTH\\rickon.stark` receives SeImpersonatePrivilege through a scoped LSA account-right assignment |
| `writable_program_directory` | Filesystem / Services | **Candidate** | Protected LocalSystem service binary is replaceable through writable Program Files directory rights |
| `insecure_service_registry` | Registry / Services | **Candidate** | Users can alter a custom registry value consumed by a LocalSystem service as an executable path |

The deterministic core target remains 20 techniques. Patch/build-dependent kernel CVEs are optional and are not part of the core catalog.

## Service Batch 1 — implemented

The first five service techniques passed the exact current-source live promotion gate on 2026-09-02 with `unreachable=0` and `failed=0`, ending applied/vulnerable for training.

## Current incremental state

The two user-right candidates have now also passed incremental apply + vulnerable-state validation, taking the current WS01 construction state to **16 live scenarios**:

```text
unquoted_service_path
weak_service_dacl
weak_service_binary_permissions
weak_service_registry_permissions
service_dll_hijacking
path_search_order_hijacking
scheduled_task_binary_permissions
scheduled_task_directory_permissions
unattend_credentials
powershell_history_credentials
hardcoded_application_credentials
stored_winlogon_credentials
writable_program_directory
insecure_service_registry
sebackup_privilege
seimpersonate_privilege
```

The user-right candidates alter LSA account-right assignments, not already-issued access tokens. Manual training therefore needs a fresh Rickon interactive logon before `whoami /priv` is expected to expose the new privileges.

## Next candidate batch — installer policy + saved credentials

The next incremental batch contains:

```text
always_install_elevated
stored_runas_credentials
```

`always_install_elevated` sets the machine Windows Installer policy and Rickon's actual per-user policy to `1`. When Rickon has never logged on, the candidate creates his normal Windows profile first so the HKCU setting can be persisted in his `NTUSER.DAT`. Existing machine/user policy values are snapshotted and reset restores those values rather than blindly deleting registry state.

`stored_runas_credentials` creates a dedicated local administrator (`kingdom.runas`) and seeds a Credential Manager target while executing `cmdkey.exe` in Rickon's user/profile context. Validation enumerates Rickon's credential manager rather than the Ansible management account's vault. Reset deletes only that stored target, dedicated account and scenario artifacts.

All candidate resets remain scoped to their own artifacts/accounts/services/settings and do not reset previously installed scenarios.

Candidates remain **Candidate** until their current committed source passes the reversible live gate:

```text
apply -> vulnerable -> reset -> clean -> re-apply -> vulnerable
```

## Remaining planned techniques

After this batch, the only remaining planned techniques are:

```text
registry_run_keys
writable_startup_folder
```

Current checkpoint:

- 20-technique catalog committed;
- five Service Batch 1 techniques are **Implemented**;
- thirteen additional source-complete techniques are **Candidate**;
- two techniques remain Planned;
- sixteen scenarios are currently live on WS01 before the next batch is applied;
- normal profiles remain fail-closed while they include candidate/planned members;
- Defender, UAC and Windows Firewall are not globally weakened.
