<div align="center">

# GOAD Kingdoms
<img width="1122" height="1402" alt="goad" src="https://github.com/user-attachments/assets/f4f90c84-e145-4904-94ff-2167c91f33f3" />


### Segmented Active Directory Red Team Training Range

**Segment. Pivot. Escalate. Persist.**

GOAD Kingdoms transforms the original **Game Of Active Directory (GOAD)** environment into a routed, segmented Red Team training range built around realistic network boundaries, controlled management access, privilege escalation, pivoting, domain compromise, persistence, and cross-domain / cross-forest progression.

**Built on [Orange Cyberdefense GOAD](https://github.com/Orange-Cyberdefense/GOAD). Extended for a different training model.**

</div>

---

> [!NOTE]
> This project was named **GOAD_NOMAD** through Milestone 1 and the `v1.0.0 — Segmented Foundation` release. Historical v1.0.0 release notes intentionally keep that name. Development after v1.0.0 uses **GOAD Kingdoms** (`GOAD_Kingdoms` in repository/directory contexts).

## Why GOAD Kingdoms exists

GOAD is an excellent vulnerable Active Directory lab. GOAD Kingdoms keeps that foundation and changes the way the environment is deployed, reached, operated, and ultimately attacked.

The goal is not to replace GOAD or hide where this project came from. The goal is to turn the inherited environment into a coherent Red Team range where identity relationships and network reachability are separate concepts.

A compromised credential should not automatically mean every system is directly reachable. Moving from one security boundary to another should require the student to understand the environment, obtain the right access, and pivot through the paths intentionally exposed by the range.

## What GOAD Kingdoms changes

| Area | Upstream GOAD foundation | GOAD Kingdoms direction |
| --- | --- | --- |
| Network model | Primarily flat lab connectivity | Routed security zones with deny-by-default exercise policy |
| Address space | Traditional GOAD lab range | `10.4.0.0/16` segmented range |
| Student entry | Broad lab reachability | Student attack host starts in NORTH |
| Cross-zone access | Network reachability is largely implicit | Explicitly permitted relationships and real pivoting |
| Deployment access | Vagrant / Ansible management path | Separate provisioning plane, removed from the training surface |
| Runtime lifecycle | Standard GOAD / Vagrant operations | Kingdoms-aware `start`, `stop`, `install`, mode control, readiness gates and recovery |
| Windows privilege escalation | Not the primary curriculum focus | Dedicated resettable NORTH workstation curriculum |
| Domain persistence | Individual techniques can be practiced | Dedicated persistence phase planned after NORTH Domain Admin |
| Cross-domain / cross-forest | GOAD trust relationships | Trust abuse combined with network segmentation and pivoting |

## Current segmented architecture

GOAD Kingdoms places the five original GOAD Windows systems and the M2 WS01 workstation behind a dedicated Debian routing plane.
<img width="1536" height="1024" alt="topology" src="https://github.com/user-attachments/assets/7bd531d6-de4f-427f-8ca2-499fac183f37" />




| Zone | VMware network | Subnet | Systems |
| --- | --- | --- | --- |
| NORTH | `vmnet10` | `10.4.10.0/24` | Winterfell `10.4.10.11`, Castelblack `10.4.10.22`, WS01 `10.4.10.31` |
| SEVENKINGDOMS | `vmnet20` | `10.4.20.0/24` | Kingslanding `10.4.20.10` |
| ESSOS | `vmnet30` | `10.4.30.0/24` | Meereen `10.4.30.12`, Braavos `10.4.30.23` |
| MANAGEMENT | `vmnet99` | `10.4.99.0/24` | GOAD-ROUTER management plane |

`GOAD-ROUTER` uses `.1/24` on each project zone. The host has adapters only on NORTH (`10.4.10.254/24`) and MANAGEMENT (`10.4.99.254/24`). There are deliberately no host-side VMware adapters on SEVENKINGDOMS or ESSOS.

The student attack machine attaches directly to **NORTH**. GOAD Kingdoms does not ship a project-owned Kali VM.

## Identity relationships are not network reachability

The original GOAD relationships are intentionally preserved, but the router exposes only the communication required for those relationships and the designed attack paths.

The current exercise policy preserves:

- Winterfell `10.4.10.11` ↔ Kingslanding `10.4.20.10` for the NORTH child-domain / SevenKingdoms parent-domain relationship and required Active Directory traffic.
- Kingslanding `10.4.20.10` ↔ Meereen `10.4.30.12` for the SevenKingdoms / ESSOS forest trust.
- Winterfell `10.4.10.11` ↔ Meereen `10.4.30.12` on TCP/UDP 53 for GOAD's cross-forest conditional DNS behavior.
- Castelblack `10.4.10.22` ↔ Braavos `10.4.30.23` on TCP 1433 for the deliberate MSSQL linked-server path.
- Established and related return traffic.

Everything else traversing the routed exercise plane is denied by default.

## Two operating modes

GOAD Kingdoms separates **deployment connectivity** from the **student attack surface**.

### Provisioning mode

Used by Vagrant, Ansible and maintenance operations.

- Windows provisioning/NAT adapters are connected.
- Temporary host routes to protected zones are enabled through GOAD-ROUTER.
- The router uses the provisioning forwarding policy.
- Management readiness is checked before Ansible is allowed to run.

### Exercise mode

Used for the actual training environment.

- The router switches to a deny-by-default forwarding policy.
- Temporary protected-zone host routes are removed.
- Windows provisioning/NAT adapters are persistently disabled and disconnected at the VMware layer.
- NORTH remains the student entry zone.
- Direct host/student access to SEVENKINGDOMS and ESSOS is blocked.

The persistent adapter state prevents a simple VM power cycle from silently restoring the provisioning bypass.

## `goad.sh` is the control plane

GOAD Kingdoms keeps the familiar GOAD interactive console and extends it so the normal workflow remains centered on:

```bash
./goad.sh
```

For a segmented GOAD/VMware instance, the console understands the project network scope and runtime mode. The installation lifecycle prepares the segmented VMware networks, brings up the routing plane, validates Windows management readiness, runs provisioning, and transitions the completed range into exercise isolation.

Useful interactive commands include:

```text
install
start
stop
status
network
mode status
mode provisioning
mode exercise
validate
```

`start` and `stop` are hardened for the segmented VMware lifecycle rather than being treated as bare `vagrant up` / `vagrant halt` operations.

## Git is the source of truth

Project code is changed in Git **before** it is tested on a lab machine.

The required direction is:

```text
Git change -> commit -> push -> test checkout sync -> source gate -> test
```

A locally repaired test checkout is never considered the validated implementation until that repair exists in Git, has been pushed, pulled back into the test checkout, and revalidated.

Before milestone/reproducibility testing, run:

```bash
bash scripts/verify-test-source.sh
```

For an exact candidate commit:

```bash
bash scripts/verify-test-source.sh <commit-sha>
```

The gate fails when the worktree is dirty, the branch has no upstream, Git cannot fetch the remote state, or the local branch is ahead/behind/diverged from upstream. Detached-HEAD testing is accepted only when explicitly pinned to the expected commit.

See [`docs/DEVELOPMENT_WORKFLOW.md`](./docs/DEVELOPMENT_WORKFLOW.md) for the full policy.

## Project status

### Milestone 1 — Network Segmentation

**Status: COMPLETE — released as GOAD_NOMAD v1.0.0**

Final clean source/runtime validation was executed from source commit `35f592184e87ba25f427403fde4674b444aad6c8` and finished with **27 PASS / 0 WARN / 0 FAIL**. The fresh interactive install and subsequent validation returned the lab to persistent exercise isolation.

The historical detailed record remains in [`docs/GOAD_NOMAD_MILESTONES.md`](./docs/GOAD_NOMAD_MILESTONES.md), matching the project identity used when v1.0.0 was completed.

### Milestone 2 — NORTH Workstation & Windows Local Privilege Escalation

**Status: COMPLETE — RELEASED AS v1.1.0**

GOAD Kingdoms v1.1.0 adds a first-class NORTH workstation (`GOAD-WS01` / `WS01`, `10.4.10.31`) using the pinned `mayfly/windows10` `2024.01.06` box. `NORTH\\rickon.stark` receives Remote Desktop access but no local-administrator membership. WS01 participates in domain enrollment, VMware lifecycle control, management readiness and persistent provisioning-NAT isolation while Defender, UAC and Windows Firewall remain enabled.

The release ships exactly **20 deterministic Windows local-privilege-escalation techniques** through resettable Ansible-native profiles: `service-abuse`, `credential-hunting`, `registry-abuse`, `token-abuse`, `mixed`, and `full-lpe`. Every technique passed the complete apply → vulnerable → reset → clean → reapply → vulnerable lifecycle.

Final origin-synced acceptance at `6285838af4dca55704092e2a6c0cc6a131be798f` completed with the inherited segmentation, DNS, trusts, linked SQL, WS01 security baseline, all 20 LPE scenarios and final exercise isolation intact. The canonical record lives in [`docs/GOAD_KINGDOMS_MILESTONES.md`](./docs/GOAD_KINGDOMS_MILESTONES.md).

### Planned progression

| Milestone | Scope | Status |
| --- | --- | --- |
| 1 | Network segmentation and lifecycle | Complete / v1.0.0 |
| 2 | NORTH workstation foothold + Windows local privilege escalation | Complete / v1.1.0 |
| 3 | NORTH domain escalation + persistence | Planned |
| 4 | NORTH → SevenKingdoms cross-domain progression | Planned |
| 5 | SevenKingdoms / NORTH → ESSOS cross-forest progression | Planned |
| 6 | Advanced operational / defense-evasion layers | Optional / planned |

## Training progression target

The intended end-to-end student journey is:

1. Reconnaissance and unauthenticated enumeration from NORTH.
2. Compromise a valid NORTH domain account.
3. Obtain a low-privilege foothold on WS01.
4. Complete focused Windows local privilege escalation and reach local Administrator / SYSTEM.
5. Use privileged workstation access to continue into an existing GOAD identity/credential/ticket path.
6. Resume authenticated Active Directory enumeration.
7. Escalate through `north.sevenkingdoms.local` to Domain Admin.
8. Complete a dedicated NORTH domain-persistence phase.
9. Cross the child/root boundary into `sevenkingdoms.local`.
10. Cross the forest boundary into `essos.local` using identity abuse plus realistic pivoting.
11. Continue into optional advanced operational, defense-evasion and hybrid identity layers.

The intended scope progression is:

```text
Machine -> Domain -> Parent Domain -> Forest -> Foreign Forest
```

## Validation

Before running project validation on a test checkout:

```bash
bash scripts/verify-test-source.sh
```

Source-only segmentation preflight:

```bash
bash scripts/validate-network-segmentation-source.sh
```

WS01 source-contract validation:

```bash
bash scripts/validate-ws01-source.sh
```

Install or update the clean WS01 foundation in an existing GOAD/VMware instance:

```bash
./goad.sh -t ws01 -i <instance-id>
```

The command materializes WS01 from committed source, provisions only the workstation baseline, validates all six management endpoints and restores exercise isolation before returning.

Focused WS01 runtime validation:

```bash
export GOAD_PROVIDER_DIR="$HOME/Documents/GOAD_Kingdoms/workspace/<instance>/provider"
bash scripts/validate-ws01-runtime.sh
```

Complete runtime validation against a deployed provider:

```bash
export GOAD_PROVIDER_DIR="$HOME/Documents/GOAD_Kingdoms/workspace/<instance>/provider"
bash scripts/validate-goad-kingdoms-clean-install-runtime.sh
```

> [!IMPORTANT]
> Some internal compatibility identifiers still use `GOAD_NOMAD`, `goad_nomad.py`, `vmware_nomad.py`, and related names. These are intentionally retained during the first public-brand rename so the already validated M1 lifecycle is not changed cosmetically and behaviorally in one step. Internal identifiers will be migrated separately with regression tests and compatibility aliases where needed.

## Upstream GOAD foundation

GOAD Kingdoms is a modified fork of **[Orange Cyberdefense / GOAD](https://github.com/Orange-Cyberdefense/GOAD)** and continues to use the GOAD Active Directory environment, vulnerabilities, identities and domain relationships as its foundation.

The inherited full GOAD topology contains five Windows servers, three domains and two forests:

- `sevenkingdoms.local`
  - Kingslanding / DC01 — Windows Server 2019
- `north.sevenkingdoms.local`
  - Winterfell / DC02 — Windows Server 2019
  - Castelblack / SRV02 — Windows Server 2019, IIS, MSSQL
- `essos.local`
  - Meereen / DC03 — Windows Server 2016
  - Braavos / SRV03 — Windows Server 2016, MSSQL, ADCS

GOAD Kingdoms preserves the parent/child trust, the SevenKingdoms ↔ ESSOS forest trust, and the Castelblack ↔ Braavos MSSQL linked-server relationship while placing those systems behind explicit network security boundaries.

For the original project, documentation and full upstream lab family, visit:

- [Orange Cyberdefense GOAD repository](https://github.com/Orange-Cyberdefense/GOAD)
- [Official GOAD documentation](https://orange-cyberdefense.github.io/GOAD/)

## Safety

> [!CAUTION]
> GOAD Kingdoms is an intentionally vulnerable offensive-security training environment. Do not deploy it directly to the Internet or reuse its vulnerable configuration as a production Active Directory design. Run it only in an isolated lab environment you control and are authorized to test.

## License and attribution

GOAD Kingdoms remains licensed under the **GNU General Public License v3.0**, consistent with the upstream GOAD project. See [`LICENSE`](./LICENSE).

This repository contains substantial modifications to the upstream project. GOAD and the original lab design are credited to **Orange Cyberdefense and the GOAD contributors**; GOAD Kingdoms identifies the additional segmented range, lifecycle, curriculum and operational changes developed in this fork.
