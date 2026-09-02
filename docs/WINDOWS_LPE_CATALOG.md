# GOAD Kingdoms — Windows Local Privilege Escalation Catalog

This document tracks the deterministic Windows local-privilege-escalation curriculum for **GOAD-WS01**.

The starting identity is the existing domain user `NORTH\\rickon.stark`. The workstation baseline must remain domain joined, reachable through NORTH, and protected by UAC, Windows Firewall, and Defender unless a specific scenario explicitly requires a narrowly scoped change.

## Framework rules

Every advertised technique must provide all of the following before it is marked implemented:

1. deterministic apply logic;
2. vulnerable-state validation;
3. deterministic reset/cleanup logic;
4. clean-state validation;
5. successful re-apply after reset;
6. Windows-build compatibility evidence for the pinned WS01 image;
7. no accidental weakening of unrelated scenarios or global security controls.

The framework is fail-closed. Profiles may describe the planned curriculum before every member is implemented, but `apply` and `reset` must refuse to continue if a selected technique lacks the complete contract above.

## Target catalog

| ID | Family | Status | Notes |
| --- | --- | --- | --- |
| `unquoted_service_path` | Services | Planned | Deterministic service-path misconfiguration |
| `weak_service_dacl` | Services | Planned | Low-privilege service-control permission abuse |
| `weak_service_binary_permissions` | Services | Planned | Writable privileged service executable |
| `weak_service_registry_permissions` | Services / Registry | Planned | Writable service registry configuration |
| `service_dll_hijacking` | Services | Planned | Controlled privileged DLL search-order scenario |
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

The initial target is approximately **18–22** deterministic techniques. Additional techniques may be added only after compatibility testing; patch/build-dependent kernel CVEs are optional and are not part of the deterministic core.

## Planned profiles

- `service-abuse`
- `credential-hunting`
- `registry-abuse`
- `token-abuse`
- `mixed`
- `full-lpe`

`full-lpe` is intentionally a kitchen-sink profile. Normal learning paths should expose smaller focused sets so enumeration does not simply report every possible weakness at once.

## Current checkpoint

At the initial framework checkpoint:

- the catalog and profile names are committed;
- `windows_lpe_implemented_techniques` is empty;
- no LPE vulnerability is planted on WS01;
- `status` is allowed;
- `apply` and `reset` fail closed until the first technique gains the full apply/validate/reset contract.
