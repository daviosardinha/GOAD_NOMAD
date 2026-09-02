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

**Status: ACTIVE DESIGN / IMPLEMENTATION NEXT**

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

### Planned WS01 baseline

| Property | Target |
| --- | --- |
| VMware VM | `GOAD-WS01` |
| Hostname | `WS01` |
| Zone | NORTH |
| Exercise NIC | `vmnet10` |
| Exercise address | `10.4.10.31/24` |
| Gateway | `10.4.10.1` |
| Domain | `north.sevenkingdoms.local` |
| Starting identity | existing NORTH domain identity, currently `NORTH\\rickon.stark` candidate |
| Provisioning | Vagrant NAT, same M1 lifecycle contract as existing Windows guests |

The exact Windows build must be selected and frozen before the LPE compatibility matrix is considered final.

### LPE architecture

GOAD Kingdoms will implement its own Ansible-native, resettable Windows LPE role rather than importing a destructive all-in-one Windows hardening-disable script.

Primary technique/reference sources include:

- Windows Local Privilege Escalation Cookbook;
- AutomatedBadLab's LocalPrivEscWorkshop automation model;
- Sagi Shahar's LPE Workshop for additional technique references;
- reset/cleanup patterns from modern lab seeders.

The implementation must preserve normal security controls except where a specific exercise intentionally changes them.

### Target technique catalog

The target is approximately **18–22 deterministic misconfiguration-based techniques**, with an initial validated subset before the full catalog is enabled.

Planned families include:

- unquoted service paths;
- weak service DACLs;
- weak service binary permissions;
- weak service registry permissions;
- service/DLL/PATH search-order abuse;
- AlwaysInstallElevated;
- registry run keys;
- writable startup folders;
- scheduled-task path/binary weaknesses;
- answer/unattend credential artifacts;
- PowerShell/history credential artifacts;
- hardcoded application credentials;
- stored RunAs credentials;
- stored Winlogon credentials;
- SeBackupPrivilege;
- SeImpersonatePrivilege;
- writable application/program directories;
- selected additional deterministic Windows misconfigurations that survive compatibility testing.

Patch/build-dependent kernel CVEs are optional additions, not part of the deterministic core catalog.

### Scenario profiles

The catalog and the active exercise set are separate concepts. Normal training profiles should expose a focused subset while a full profile can intentionally enable everything.

Planned profiles:

- `service-abuse`
- `credential-hunting`
- `registry-abuse`
- `token-abuse`
- `mixed`
- `full-lpe`

### Required M2 validation gates

Milestone 2 cannot close until all of the following are proven from committed, origin-synced source:

1. WS01 installs as a first-class GOAD workstation and joins `north.sevenkingdoms.local`.
2. WS01 follows the exact M1 provisioning/exercise NIC contract.
3. Start/stop/power-cycle behavior cannot restore its provisioning bypass.
4. The chosen existing NORTH user can obtain the intended low-privilege foothold without receiving unintended local-admin rights.
5. Every supported LPE technique has an explicit apply check and validation check.
6. Reset is deterministic: apply -> validate vulnerable -> reset -> validate clean -> reapply -> validate vulnerable.
7. Technique profiles do not accidentally collide or destroy unrelated scenarios.
8. Defender/UAC/Firewall baseline state is recorded and not globally weakened merely to make the lab easier.
9. The exact WS01 Windows build has a compatibility matrix for every advertised technique.
10. The intended progression from the starting NORTH account to SYSTEM and then into an existing GOAD AD attack path is demonstrated end to end.
11. M1 segmentation/trust/DNS/linked-SQL validation remains green after WS01 is added.
12. The final candidate is tested only after `scripts/verify-test-source.sh` proves the test checkout matches Git.

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
