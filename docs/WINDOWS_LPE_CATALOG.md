# GOAD Kingdoms — Windows Local Privilege Escalation Catalog

This document tracks the deterministic Windows local-privilege-escalation curriculum for **GOAD-WS01**.

The starting identity is the existing domain user `NORTH\\rickon.stark`. The workstation must remain domain joined, reachable through NORTH, and protected by UAC, Windows Firewall, and Defender unless a specific scenario intentionally changes a narrowly scoped object.

## Framework rules

Every advertised technique must provide deterministic apply, vulnerable-state validation, reset, clean-state validation, successful re-apply, pinned-build compatibility evidence, and isolation from unrelated scenarios/security controls.

Technique state is explicit:

- **Planned** — catalog entry only; lifecycle operations fail closed.
- **Candidate** — source apply/validate/reset logic exists, but the live reversible gate is still pending for the current committed implementation.
- **Implemented** — the complete live gate passed on the exact technique source.

Candidate techniques require an exact `windows_lpe_techniques` selection plus `windows_lpe_allow_candidate=true`.

## Target catalog

| ID | Family | Status | Notes |
| --- | --- | --- | --- |
| `unquoted_service_path` | Services | **Implemented** | Unquoted LocalSystem service path with writable preemption point |
| `weak_service_dacl` | Services | **Implemented** | Dedicated LocalSystem service with CHANGE_CONFIG/START/STOP rights |
| `weak_service_binary_permissions` | Services | **Implemented** | Quoted LocalSystem service with directly writable executable |
| `weak_service_registry_permissions` | Services / Registry | **Implemented** | Users can alter SCM service registry configuration |
| `service_dll_hijacking` | Services / DLL | **Implemented** | Privileged service loads a missing DLL from a writable location |
| `path_search_order_hijacking` | Services / PATH | **Implemented** | Users-writable PATH preemption directory before protected helper |
| `always_install_elevated` | Policy / Registry | **Implemented** | Machine plus Rickon user installer policy pair, with previous values preserved |
| `registry_run_keys` | Registry / Autoruns | **Implemented** | HKLM Run value exists while BUILTIN\\Users can change values on the Run key; prior ACL/value are snapshotted |
| `writable_startup_folder` | Startup | **Implemented** | Common Startup folder grants BUILTIN\\Users Modify; original ACL and marker state are preserved for reset |
| `scheduled_task_binary_permissions` | Scheduled tasks | **Implemented** | SYSTEM startup task executable directly modifiable by Users |
| `scheduled_task_directory_permissions` | Scheduled tasks | **Implemented** | SYSTEM startup task executable replaceable through directory rights |
| `unattend_credentials` | Credentials | **Implemented** | Readable Panther answer-file credential for a local administrator |
| `powershell_history_credentials` | Credentials | **Implemented** | PSReadLine history exposes a dedicated local-admin credential; validation survives Rickon profile creation between lifecycle phases |
| `hardcoded_application_credentials` | Credentials | **Implemented** | Readable application config contains a local-admin service credential |
| `stored_runas_credentials` | Credentials | **Implemented** | Rickon's Credential Manager stores a RunAs-compatible Interactive Logon credential for a dedicated local administrator |
| `stored_winlogon_credentials` | Credentials / Registry | **Implemented** | Plaintext Winlogon DefaultPassword for a dedicated local administrator |
| `sebackup_privilege` | User rights | **Implemented** | `NORTH\\rickon.stark` receives SeBackupPrivilege through a scoped LSA account-right assignment |
| `seimpersonate_privilege` | User rights / Tokens | **Implemented** | `NORTH\\rickon.stark` receives SeImpersonatePrivilege through a scoped LSA account-right assignment |
| `writable_program_directory` | Filesystem / Services | **Implemented** | Protected LocalSystem service binary is replaceable through writable Program Files directory rights |
| `insecure_service_registry` | Registry / Services | **Implemented** | Users can alter a custom registry value consumed by a LocalSystem service as an executable path |

The deterministic core is exactly 20 techniques. Patch/build-dependent kernel CVEs are optional and are not part of the core catalog.

## Full 20-technique promotion checkpoint

On **2026-09-03**, the complete WS01 catalog passed the full reversible runtime gate from an origin-synced checkout:

```text
source gate
    -> WS01 security/domain baseline
    -> validate all 20 vulnerable
    -> reset all 20
    -> validate all 20 clean
    -> re-apply all 20 together
    -> validate all 20 vulnerable
    -> WS01 security/domain baseline
```

The final runtime state was deliberately left with all 20 techniques **APPLIED / VULNERABLE** for training. The final vulnerable-state batch completed with `unreachable=0` and `failed=0`, and the post-cycle WS01 baseline confirmed the domain secure channel, Rickon rights, RDP/WinRM reachability, UAC, Windows Firewall, Defender, and Windows evaluation grace remained healthy.

No deterministic technique remains Candidate or Planned.

## Compatibility notes

The user-right techniques alter LSA account-right assignments, not already-issued access tokens. Manual training therefore needs a fresh Rickon interactive logon before `whoami /priv` is expected to expose newly assigned privileges.

The stored RunAs technique is seeded programmatically in Rickon's credential context using the Windows Interactive Logon credential format with a UTF-16LE password blob. The exact Windows 10 build was compatibility-proven from Rickon's real RDP session: `runas /savecred` launched `WS01\\kingdom.runas` without a password prompt and `whoami` confirmed the target identity. Automated lifecycle validation deliberately does not treat a Scheduled Task batch-logon session as equivalent to that interactive proof.

The PowerShell-history scenario may initially use its managed fallback profile artifact if Rickon has never logged on interactively. If Rickon's real profile appears later, vulnerable-state validation first checks the real profile for the injected artifact and otherwise continues to validate the managed fallback that was actually seeded. A reset removes the managed fallback, and a subsequent re-apply naturally uses Rickon's real profile when present.

`registry_run_keys` uses the native .NET registry API against the 64-bit HKLM view so lifecycle behavior does not depend on inconsistent PowerShell Registry-provider path resolution. It snapshots the prior Run-key ACL/value state, creates the key only when necessary, and restores or removes only scenario-owned state.

All resets remain scoped to their own artifacts/accounts/services/settings and do not reset unrelated scenarios.

## Current checkpoint

- 20-technique catalog committed;
- **20 techniques Implemented**;
- **0 Candidate**;
- **0 Planned**;
- all 20 scenarios currently live on WS01 for training;
- normal scenario profiles can now be used without candidate opt-in;
- Defender, UAC and Windows Firewall are not globally weakened.
