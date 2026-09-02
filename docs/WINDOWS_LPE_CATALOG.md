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

Technique state is explicit:

- **Planned** — catalog entry only; lifecycle operations fail closed.
- **Candidate** — source apply/validate/reset logic exists, but live re-apply validation is still pending.
- **Implemented** — the complete live gate passed on the pinned WS01 build.

Candidate techniques require an exact `windows_lpe_techniques` selection plus `windows_lpe_allow_candidate=true`. Profiles remain fail-closed while they contain planned or candidate-only members.

## Target catalog

| ID | Family | Status | Notes |
| --- | --- | --- | --- |
| `unquoted_service_path` | Services | **Candidate** | Source apply/vulnerable/reset/clean contract committed; live re-apply gate pending |
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

## Unquoted service path candidate contract

The first candidate uses a dedicated automatic LocalSystem service named `KingdomUpdaterSvc` with the deliberately unquoted image path:

```text
C:\Kingdom LPE\Unquoted Service\KingdomUpdater.exe
```

The intended ambiguous writable candidate is:

```text
C:\Kingdom LPE\Unquoted.exe
```

`BUILTIN\\Users` receives create/write permission on `C:\Kingdom LPE` **for that directory only**. The ACE does not inherit into `Unquoted Service`, and validation explicitly rejects the scenario if the legitimate service executable becomes writable by Users. That keeps this technique distinct from the later weak-service-binary-permissions exercise.

The service runs as LocalSystem and is automatic so the exercise can be triggered through a normal workstation restart rather than granting Rickon an unrelated weak service DACL.

During development, only this exact candidate may be exercised:

```bash
cd ~/Documents/GOAD_NOMAD/ansible

ansible-playbook \
  -i ../ad/GOAD/data/inventory \
  -i ../workspace/<instance-id>/inventory \
  -i ../globalsettings.ini \
  windows-lpe.yml \
  -e windows_lpe_action=apply \
  -e windows_lpe_allow_candidate=true \
  -e '{"windows_lpe_techniques":["unquoted_service_path"]}'
```

The promotion gate is:

```text
apply
  -> automatic vulnerable-state validation
reset
  -> automatic clean-state validation
re-apply
  -> automatic vulnerable-state validation
```

Only after that sequence passes on the pinned WS01 image does `unquoted_service_path` move from candidate to implemented.

## Planned profiles

- `service-abuse`
- `credential-hunting`
- `registry-abuse`
- `token-abuse`
- `mixed`
- `full-lpe`

`full-lpe` is intentionally a kitchen-sink profile. Normal learning paths should expose smaller focused sets so enumeration does not simply report every possible weakness at once.

## Current checkpoint

At the first technique-candidate checkpoint:

- the 20-technique catalog and profile names are committed;
- `unquoted_service_path` is the only candidate technique;
- `windows_lpe_implemented_techniques` remains empty until the live re-apply gate passes;
- all other LPE techniques remain planned and unavailable;
- normal profile apply/validate/reset remains fail-closed;
- candidate testing requires an exact selection and explicit opt-in;
- Defender, UAC and Windows Firewall are not globally weakened by the LPE framework.
