# GOAD Kingdoms — Major Project Milestones

This is the canonical milestone tracker for **GOAD Kingdoms**.

The project was named **GOAD_NOMAD** through Milestone 1 and the `v1.0.0 — Segmented Foundation` release. Historical v1.0.0 release notes and the original Milestone 1 record keep that name intentionally. Development after v1.0.0 uses the GOAD Kingdoms identity.

A milestone is COMPLETE only after its implementation exists in committed Git source and its end-to-end validation gates pass from an origin-synced checkout. The mandatory development/test workflow is documented in [`DEVELOPMENT_WORKFLOW.md`](./DEVELOPMENT_WORKFLOW.md).

## Architecture baseline inherited from v1.0.0

| VMware network | Zone | Subnet | Host-side access | Router address |
| --- | --- | --- | --- | --- |
| `vmnet10` | NORTH | `10.4.10.0/24` | `10.4.10.254/24` | `10.4.10.1/24` |
| `vmnet20` | SEVENKINGDOMS | `10.4.20.0/24` | none | `10.4.20.1/24` |
| `vmnet30` | ESSOS | `10.4.30.0/24` | none | `10.4.30.1/24` |
| `vmnet99` | MANAGEMENT | `10.4.99.0/24` | `10.4.99.254/24` | `10.4.99.1/24` |

Existing Windows placement:

| Host | Role | Zone | Address |
| --- | --- | --- | --- |
| GOAD-DC02 / Winterfell | NORTH child-domain DC | NORTH | `10.4.10.11` |
| GOAD-SRV02 / Castelblack | NORTH member server / MSSQL | NORTH | `10.4.10.22` |
| GOAD-DC01 / Kingslanding | root-domain DC | SEVENKINGDOMS | `10.4.20.10` |
| GOAD-DC03 / Meereen | ESSOS DC | ESSOS | `10.4.30.12` |
| GOAD-SRV03 / Braavos | ESSOS server / MSSQL / ADCS | ESSOS | `10.4.30.23` |
| GOAD-ROUTER | Debian routing plane | all zones | `.1` on each zone |

The v1.0.0 exercise firewall remains the baseline contract:

- Winterfell ↔ Kingslanding: required parent/child DC communication.
- Kingslanding ↔ Meereen: required forest-trust DC communication.
- Winterfell ↔ Meereen: TCP/UDP 53 for the validated cross-forest DNS path.
- Castelblack ↔ Braavos: TCP 1433 for the intentional linked-SQL path.
- established/related return traffic.
- all other forwarded traffic denied by default.

## Source-of-truth rule

From the GOAD Kingdoms rename onward, testing follows one direction only:

```text
Git change -> commit -> push -> test checkout sync -> source gate -> test
```

Before any milestone/reproducibility test:

```bash
bash scripts/verify-test-source.sh
```

No milestone may be closed from a test checkout containing source changes that do not exist in Git.

---

## Milestone 1 — Network Segmentation

**Status: COMPLETE / RELEASED AS GOAD_NOMAD v1.0.0**

Release: **v1.0.0 — Segmented Foundation**  
Final validated source: `35f592184e87ba25f427403fde4674b444aad6c8`  
Final validation: **27 PASS / 0 WARN / 0 FAIL**  
Final runtime mode: **exercise**

Milestone 1 established:

- segmented NORTH / SEVENKINGDOMS / ESSOS / MANAGEMENT VMware networks;
- GOAD-ROUTER as the routed control plane;
- provisioning and exercise modes;
- persistent Windows provisioning-NAT isolation;
- deny-by-default exercise routing;
- router-first/fail-closed provider startup;
- bounded segmented `start` / `stop` lifecycle;
- VMware Tools/IP discovery recovery;
- deterministic WinRM management readiness;
- GOAD-compatible SSMS 18 provisioning;
- DNS/ADWS hardening exposed by clean-install testing;
- clean-source/runtime validation of trusts, GOAD bots, linked SQL and isolation.

The detailed historical M1 record remains at [`GOAD_NOMAD_MILESTONES.md`](./GOAD_NOMAD_MILESTONES.md) because it documents the project under the name used when v1.0.0 was built and released.

---

## Milestone 2 — NORTH Workstation Foothold & Windows Local Privilege Escalation

**Status: IMPLEMENTATION IN PROGRESS — WS01 FOUNDATION + 20/20 LPE CATALOG VALIDATED**

### Validated checkpoints

WS01 clean-foundation checkpoint validated on **2026-09-02** from origin-synced source:

- validated commit: `4003f8b41f5344650f82c746b83b2fe8fec32010`;
- runtime mode: `exercise`;
- WS01 address: `10.4.10.31/24` on NORTH (`vmnet10`);
- domain: `north.sevenkingdoms.local`;
- foothold identity: `NORTH\\rickon.stark`;
- Rickon has Remote Desktop access and is not a local administrator;
- provisioning NAT is persistently disabled in exercise mode;
- RDP (`3389/tcp`) and WinRM HTTPS (`5986/tcp`) are reachable from NORTH;
- UAC, Windows Firewall, and Defender remain enabled;
- focused runtime result: `WS01_FOUNDATION=PASS` with Ansible `unreachable=0` and `failed=0`.

The complete deterministic Windows LPE catalog passed its full reversible runtime gate on **2026-09-03** from origin-synced source with technique implementation HEAD `0f02199fdf07d425b89346664bcde67f7ba0033c`:

- all **20/20** techniques validated vulnerable together;
- all 20 reset successfully and validated clean;
- all 20 re-applied together and validated vulnerable again;
- final vulnerable-state Ansible recap completed with `unreachable=0` and `failed=0`;
- WS01 remained powered and WinRM healthy throughout the gate;
- post-cycle baseline passed for domain membership/secure channel, Rickon rights, RDP/WinRM reachability, UAC, Windows Firewall, Defender, and Windows evaluation grace;
- final runtime state intentionally remains **20 techniques APPLIED / VULNERABLE** for training.

The 20 techniques are now promoted from Candidate to **Implemented** in the framework metadata. No deterministic LPE technique remains Candidate or Planned.

ICMP echo is not a WS01 health requirement: the Windows client firewall may block echo while the intended RDP and WinRM services remain healthy. The runtime validator therefore uses the service contract rather than requiring ping.

### Goal

Add one first-class Windows workstation (`WS01`) to NORTH and extend the beginning of the existing GOAD progression:

```text
valid NORTH user
    -> WS01 low-privilege foothold
    -> Windows local privilege escalation
    -> local Administrator / SYSTEM
    -> privileged workstation discovery
    -> existing GOAD identity/credential/ticket path
    -> existing GOAD Active Directory attack surface
```

Milestone 2 is an extension to GOAD's attack journey, not a separate standalone CTF.

### Validated WS01 baseline

| Property | Validated value |
| --- | --- |
| VMware VM | `GOAD-WS01` |
| Hostname | `WS01` |
| Zone | NORTH |
| Exercise NIC | `vmnet10` |
| Exercise address | `10.4.10.31/24` |
| Gateway | `10.4.10.1` |
| Domain | `north.sevenkingdoms.local` |
| Windows baseline | Windows 10 Enterprise 22H2 (`mayfly/windows10`) |
| Vagrant box version | `2024.01.06` |
| Starting identity | `NORTH\\rickon.stark` |
| Provisioning | Vagrant NAT, same M1 lifecycle contract as existing Windows guests |

The WS01 box is pinned. The foundation keeps Defender, UAC and Windows Firewall at their native Windows client baseline; WS01 is excluded from both GOAD's server-oriented `defender_on` role and `defender_off`. `rickon.stark` receives Remote Desktop access but is not placed in local Administrators.

### LPE architecture

GOAD Kingdoms implements its own Ansible-native, resettable Windows LPE role rather than importing a destructive all-in-one Windows hardening-disable script.

Primary technique/reference sources include:

- Windows Local Privilege Escalation Cookbook;
- AutomatedBadLab's LocalPrivEscWorkshop automation model;
- Sagi Shahar's LPE Workshop for additional technique references;
- reset/cleanup patterns from modern lab seeders.

The implementation preserves normal security controls except where a specific exercise intentionally changes a narrowly scoped object.

### Implemented deterministic technique catalog

The validated core contains exactly **20 misconfiguration-based techniques** across these families:

- unquoted service paths;
- weak service DACLs;
- weak service binary permissions;
- weak service registry permissions;
- service DLL hijacking;
- PATH search-order hijacking;
- AlwaysInstallElevated;
- registry Run keys;
- writable Startup folder;
- scheduled-task binary permissions;
- scheduled-task directory permissions;
- unattend credential artifacts;
- PowerShell history credential artifacts;
- hardcoded application credentials;
- stored RunAs credentials;
- stored Winlogon credentials;
- SeBackupPrivilege;
- SeImpersonatePrivilege;
- writable Program Files directory;
- insecure custom service registry configuration.

Patch/build-dependent kernel CVEs are optional additions, not part of the deterministic core catalog.

### Scenario profiles

The catalog and the active exercise set are separate concepts. The implemented profiles expose focused subsets while `full-lpe` intentionally enables all 20.

Profiles:

- `service-abuse`
- `credential-hunting`
- `registry-abuse`
- `token-abuse`
- `mixed`
- `full-lpe`

Because all current catalog members are Implemented, normal profiles no longer require candidate opt-in.

### Required M2 validation gates

Milestone 2 cannot close until all of the following are proven from committed, origin-synced source:

1. WS01 installs as a first-class GOAD workstation and joins `north.sevenkingdoms.local`. **PASSED.**
2. WS01 follows the exact M1 provisioning/exercise NIC contract. **PASSED for the validated WS01 checkpoint.**
3. Start/stop/power-cycle behavior cannot restore its provisioning bypass.
4. The chosen existing NORTH user can obtain the intended low-privilege foothold without receiving unintended local-admin rights. **Baseline rights and real RDP foothold validated.**
5. Every supported LPE technique has an explicit apply check and validation check. **PASSED for all 20.**
6. Reset is deterministic: apply -> validate vulnerable -> reset -> validate clean -> reapply -> validate vulnerable. **PASSED for all 20 together.**
7. Technique profiles do not accidentally collide or destroy unrelated scenarios. **Full 20-scenario reversible cycle passed; focused profile acceptance remains available for final M2 regression.**
8. Defender/UAC/Firewall baseline state is recorded and not globally weakened merely to make the lab easier. **PASSED before and after the full 20-scenario cycle.**
9. The exact WS01 Windows build has compatibility evidence for every advertised technique. **PASSED for the deterministic 20-technique catalog, including interactive RunAs compatibility proof.**
10. The intended progression from the starting NORTH account to SYSTEM and then into an existing GOAD AD attack path is demonstrated end to end. **PENDING.**
11. M1 segmentation/trust/DNS/linked-SQL validation remains green after WS01 is added. **PENDING final M2 regression.**
12. The final candidate is tested only after `scripts/verify-test-source.sh` proves the test checkout matches Git. **PASSED and enforced by the source/runtime gates.**

The Windows LPE construction/promotion phase is complete. Milestone 2 remains open for the end-to-end attack-journey proof and final inherited-M1 regression gates rather than for additional local-LPE scenario construction.

---

## Milestone 3 — NORTH Domain Escalation & Persistence

**Status: PLANNED**

Continue from the M2 workstation/domain foothold through `north.sevenkingdoms.local`, reach Domain Admin, and add a dedicated domain-persistence curriculum before progressing to the parent domain.

---

## Milestone 4 — Cross-Domain Progression

**Status: PLANNED**

Expand NORTH child-domain -> `sevenkingdoms.local` parent-domain progression so identity/trust abuse must coexist with the validated segmented network model and realistic pivoting.

---

## Milestone 5 — Cross-Forest Progression

**Status: PLANNED**

Preserve and expand SevenKingdoms/NORTH -> `essos.local` attack paths, including the deliberate Castelblack ↔ Braavos MSSQL relationship and selected cross-forest techniques.

---

## Milestone 6 — Advanced Operational Layers

**Status: PLANNED / OPTIONAL**

Potential later scope includes endpoint-evasion exercises, richer gMSA/delegation scenarios, additional persistence concepts, PAM/Shadow Security Principals, and hybrid identity if the project expands that far.

## Intended end-to-end progression

```text
NORTH reconnaissance
    -> valid domain identity
    -> WS01 foothold
    -> Windows local privilege escalation
    -> NORTH authenticated AD attack path
    -> NORTH Domain Admin + persistence
    -> SEVENKINGDOMS parent-domain progression
    -> ESSOS cross-forest progression
```

The conceptual scope remains:

```text
Machine -> Domain -> Parent Domain -> Forest -> Foreign Forest
```
