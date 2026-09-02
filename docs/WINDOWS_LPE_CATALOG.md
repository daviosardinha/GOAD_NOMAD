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
| `unquoted_service_path` | Services | **Candidate** | Original engine proof passed; current batch-safe reset refactor requires revalidation |
| `weak_service_dacl` | Services | **Candidate** | Dedicated LocalSystem service with low-privilege CHANGE_CONFIG/START/STOP rights |
| `weak_service_binary_permissions` | Services | **Candidate** | Dedicated quoted-path LocalSystem service with writable executable only |
| `weak_service_registry_permissions` | Services / Registry | **Candidate** | Dedicated quoted-path LocalSystem service with Users `SetValue` on its service key |
| `service_dll_hijacking` | Services / DLL | **Candidate** | Dedicated privileged service loads a missing DLL from a Users-writable parent path |
| `path_search_order_hijacking` | Services / PATH | Planned | Controlled PATH search-order scenario |
| `always_install_elevated` | Policy / Registry | Planned | Per-user and machine installer policy pair |
| `registry_run_keys` | Registry / Autoruns | Planned | Writable privileged autorun configuration |
| `writable_startup_folder` | Startup | Planned | Writable startup execution path |
| `scheduled_task_binary_permissions` | Scheduled tasks | Planned | Writable privileged task executable |
| `scheduled_task_directory_permissions` | Scheduled tasks | Planned | Writable task execution directory/path component |
| `unattend_credentials` | Credentials | Planned | Training-only answer-file credential artifact |
| `powershell_history_credentials` | Credentials | Planned | Training-only history artifact |
| `hardcoded_application_credentials` | Credentials | Planned | Training-only application/config secret |
| `stored_runas_credentials` | Credentials | Planned | Stored RunAs credential scenario |
| `stored_winlogon_credentials` | Credentials / Registry | Planned | Training-only Winlogon credential artifact |
| `sebackup_privilege` | User rights | Planned | Assigned privilege scenario |
| `seimpersonate_privilege` | User rights / Tokens | Planned | Assigned token-impersonation privilege scenario |
| `writable_program_directory` | Filesystem | Planned | Writable privileged application directory |
| `insecure_service_registry` | Registry / Services | Planned | Additional deterministic service-registry scenario |

The deterministic core target is approximately **18–22** techniques. Patch/build-dependent kernel CVEs are optional and are not part of the core catalog.

## Engine proof and current-source revalidation

The original `unquoted_service_path` implementation successfully proved the framework engine on 2026-09-02:

```text
apply -> vulnerable -> reset -> clean -> re-apply -> vulnerable
```

That proof established that the lifecycle controller, live validation, reset model, WS01 health guard, and Mayfly evaluation handling work.

After that proof, the technique was deliberately refactored to become **batch-safe**. The current unquoted service path is:

```text
C:\Kingdom LPE\Unquoted Path\Service\KingdomUpdater.exe
```

with the intended ambiguous candidate:

```text
C:\Kingdom LPE\Unquoted.exe
```

`BUILTIN\\Users` receives a create/write ACE on the shared `C:\Kingdom LPE` parent for that folder only. Reset removes only the unquoted service, its `Unquoted Path` subtree, its candidate file, and its exact ACL entry. It does not delete the shared parent or another scenario's files.

Because this is a material source change after the original live proof, `unquoted_service_path` is correctly back in **Candidate** state until the current code passes the service batch live promotion gate.

## Service Batch 1 candidate

The accelerated service batch contains:

```text
unquoted_service_path
weak_service_dacl
weak_service_binary_permissions
weak_service_registry_permissions
service_dll_hijacking
```

The scenarios are designed not to collapse into one another:

- unquoted service path keeps its real service executable non-writable;
- weak DACL does not make its binary writable;
- weak binary permissions uses a quoted ImagePath and default service DACL;
- weak service registry permissions uses a quoted ImagePath and non-writable binary;
- DLL hijacking permits creation of the missing DLL only in a dedicated writable parent location while the legitimate service executable stays non-writable.

The **service batch live promotion gate** executes all five in one lifecycle:

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

Only after this passes do all five current implementations become **Implemented**.

Development testing uses an exact list plus:

```text
windows_lpe_allow_candidate=true
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
- five Service Batch 1 techniques are Candidate;
- all other techniques are Planned;
- no current implementation is advertised as Implemented until the batch-safe source passes live validation;
- normal profiles remain fail-closed while they include candidate/planned members;
- candidate testing requires exact selection and explicit opt-in;
- the batch runner checks WS01 power and WinRM around every phase;
- Defender, UAC and Windows Firewall are not globally weakened.
