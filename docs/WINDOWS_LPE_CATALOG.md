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
- **Candidate** — source apply/validate/reset logic exists, but the live reversible gate is still pending.
- **Implemented** — the complete live gate passed on the pinned WS01 build.

Candidate techniques require an exact `windows_lpe_techniques` selection plus `windows_lpe_allow_candidate=true`. Profiles remain fail-closed while they contain planned or candidate-only members.

## Target catalog

| ID | Family | Status | Notes |
| --- | --- | --- | --- |
| `unquoted_service_path` | Services | **Implemented** | Live apply → vulnerable → reset → clean → reapply → vulnerable gate passed on WS01 |
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

## First implemented technique — unquoted service path

The implemented technique uses an automatic LocalSystem service named `KingdomUpdaterSvc` with the deliberately unquoted image path:

```text
C:\Kingdom LPE\Unquoted Path\Service\KingdomUpdater.exe
```

The intended ambiguous writable candidate is:

```text
C:\Kingdom LPE\Unquoted.exe
```

`BUILTIN\\Users` receives a create/write ACE on the shared `C:\Kingdom LPE` parent **for that folder only**. The ACE does not inherit into the scenario/service directory, and validation rejects the scenario if the legitimate service executable becomes writable by Users.

For batch safety, reset removes only the unquoted-path service, its own `Unquoted Path` subtree, its candidate executable, and its exact parent-directory ACE. It never recursively deletes the shared `C:\Kingdom LPE` parent, so other LPE scenarios remain independently resettable.

The live promotion gate passed on 2026-09-02 using the pinned Mayfly Windows 10 WS01 image. The gate proved:

```text
apply
  -> vulnerable
  -> reset
  -> clean
  -> re-apply
  -> vulnerable
  -> WS01 domain/UAC/Firewall/Defender/evaluation baseline still healthy
```

## Service Batch 1 candidate

The first accelerated batch deliberately groups five related service scenarios:

```text
unquoted_service_path              implemented
weak_service_dacl                  candidate
weak_service_binary_permissions    candidate
weak_service_registry_permissions  candidate
service_dll_hijacking              candidate
```

The four new candidates are intentionally isolated from one another:

- weak DACL does not make its binary writable;
- weak binary permissions uses a quoted ImagePath and keeps the service DACL at its normal default;
- weak service registry permissions uses a quoted ImagePath and keeps the service binary non-writable;
- DLL hijacking gives Users write/create capability only on the missing-DLL parent path, not on the legitimate service executable.

The **service batch live promotion gate** executes all five in one lifecycle:

```text
clean WS01 baseline
  -> apply batch
  -> validate all vulnerable
  -> reset batch
  -> validate all clean
  -> re-apply batch
  -> validate all vulnerable
  -> clean WS01 security/domain baseline
```

Candidates remain development-only until that complete batch gate passes. Development testing therefore uses an exact list plus:

```text
windows_lpe_allow_candidate=true
```

## Planned profiles

- `service-abuse`
- `credential-hunting`
- `registry-abuse`
- `token-abuse`
- `mixed`
- `full-lpe`

`full-lpe` is intentionally a kitchen-sink profile. Normal learning paths should expose smaller focused sets so enumeration does not simply report every possible weakness at once.

## Current checkpoint

At the Service Batch 1 candidate checkpoint:

- the 20-technique catalog remains committed;
- `unquoted_service_path` is **Implemented** after its complete live reversible gate;
- four additional service techniques are **Candidate**;
- all other techniques remain Planned and unavailable;
- normal profiles remain fail-closed while they include candidate/planned members;
- candidate testing requires exact selection and explicit opt-in;
- the batch runner checks WS01 power and WinRM around every phase;
- the Mayfly Windows evaluation rearm is part of the reproducible WS01 baseline;
- Defender, UAC and Windows Firewall are not globally weakened by the LPE framework.
