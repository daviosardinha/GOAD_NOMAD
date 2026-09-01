<div align="center">

# GOAD_NOMAD

### Segmented Active Directory Red Team Training Range

**Segment. Pivot. Escalate. Persist.**

GOAD_NOMAD transforms the original **Game Of Active Directory (GOAD)** environment into a routed, segmented Red Team training range built around realistic network boundaries, controlled management access, privilege escalation, pivoting, domain compromise, persistence, and cross-domain / cross-forest progression.

**Built on [Orange Cyberdefense GOAD](https://github.com/Orange-Cyberdefense/GOAD). Extended for a different training model.**

</div>

---

## Why GOAD_NOMAD exists

GOAD is an excellent vulnerable Active Directory lab. GOAD_NOMAD keeps that foundation and changes the way the environment is deployed, reached, operated, and ultimately attacked.

The goal is not to replace GOAD or hide where this project came from. The goal is to turn the inherited environment into a coherent Red Team range where identity relationships and network reachability are separate concepts.

A compromised credential should not automatically mean every system is directly reachable. Moving from one security boundary to another should require the student to understand the environment, obtain the right access, and pivot through the paths intentionally exposed by the range.

## What changes in GOAD_NOMAD

| Area | Upstream GOAD foundation | GOAD_NOMAD direction |
| --- | --- | --- |
| Network model | Primarily flat lab connectivity | Routed security zones with deny-by-default exercise policy |
| Address space | Traditional GOAD lab range | `10.4.0.0/16` segmented range |
| Student entry | Broad lab reachability | Student attack host starts in NORTH |
| Cross-zone access | Network reachability is largely implicit | Explicitly permitted relationships and real pivoting |
| Deployment access | Vagrant / Ansible management path | Separate provisioning plane, removed from the training surface |
| Runtime lifecycle | Standard GOAD / Vagrant operations | GOAD_NOMAD-aware `start`, `stop`, `install`, mode control, readiness gates and recovery |
| Windows privilege escalation | Not the primary curriculum focus | Dedicated resettable workstation curriculum planned |
| Domain persistence | Individual techniques can be practiced | Dedicated persistence phase planned after NORTH Domain Admin |
| Cross-domain / cross-forest | GOAD trust relationships | Trust abuse combined with network segmentation and pivoting |

## Current segmented architecture

GOAD_NOMAD currently places the five original GOAD Windows systems behind a dedicated Debian routing plane.

```text
                               GOAD_NOMAD
                               10.4.0.0/16

       NORTH                    SEVENKINGDOMS                    ESSOS
   vmnet10 /24                  vmnet20 /24                  vmnet30 /24
   10.4.10.0/24                 10.4.20.0/24                 10.4.30.0/24

   Winterfell                   Kingslanding                  Meereen
   10.4.10.11                   10.4.20.10                    10.4.30.12

   Castelblack                                                Braavos
   10.4.10.22                                                 10.4.30.23

          \                         |                         /
           \                        |                        /
            +------------------ GOAD-ROUTER ----------------+
                               .1 in each zone
                                      |
                                      |
                                MANAGEMENT
                                vmnet99 /24
                                10.4.99.0/24
```

| Zone | VMware network | Subnet | Systems |
| --- | --- | --- | --- |
| NORTH | `vmnet10` | `10.4.10.0/24` | Winterfell `10.4.10.11`, Castelblack `10.4.10.22` |
| SEVENKINGDOMS | `vmnet20` | `10.4.20.0/24` | Kingslanding `10.4.20.10` |
| ESSOS | `vmnet30` | `10.4.30.0/24` | Meereen `10.4.30.12`, Braavos `10.4.30.23` |
| MANAGEMENT | `vmnet99` | `10.4.99.0/24` | GOAD-ROUTER management plane |

`GOAD-ROUTER` uses `.1/24` on each GOAD_NOMAD zone. The host has adapters only on NORTH (`10.4.10.254/24`) and MANAGEMENT (`10.4.99.254/24`). There are deliberately no host-side VMware adapters on SEVENKINGDOMS or ESSOS.

The student attack machine attaches directly to **NORTH**. GOAD_NOMAD does not ship a project-owned Kali VM.

## Identity relationships are not network reachability

The original GOAD relationships are intentionally preserved, but the router exposes only the communication required for those relationships and the designed attack paths.

The current exercise policy preserves:

- Winterfell `10.4.10.11` ↔ Kingslanding `10.4.20.10` for the NORTH child-domain / SevenKingdoms parent-domain relationship and required Active Directory traffic.
- Kingslanding `10.4.20.10` ↔ Meereen `10.4.30.12` for the SevenKingdoms / ESSOS forest trust.
- Winterfell `10.4.10.11` ↔ Meereen `10.4.30.12` on TCP/UDP 53 for GOAD's cross-forest conditional DNS behavior.
- Castelblack `10.4.10.22` ↔ Braavos `10.4.30.23` on TCP 1433 for the deliberate MSSQL linked-server path.
- Established and related return traffic.

Everything else traversing the GOAD_NOMAD routing plane is denied by default during exercise mode.

## Two operating modes

GOAD_NOMAD separates **deployment connectivity** from the **student attack surface**.

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

GOAD_NOMAD keeps the familiar GOAD interactive console and extends it so the normal workflow remains centered on:

```bash
./goad.sh
```

For a segmented GOAD/VMware instance, the console now understands the GOAD_NOMAD network scope and runtime mode. The default installation lifecycle prepares the segmented VMware networks, brings up the routing plane, validates Windows management readiness, runs provisioning, and transitions the completed range into exercise isolation.

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

## Project status

### Milestone 1 — Network Segmentation

**Implementation: COMPLETE**  
**Latest lifecycle / fresh interactive install revalidation: IN PROGRESS**

The original Milestone 1 clean-checkout gate was completed on 2026-08-31 from source commit `3997cc44539b009577807cea9361842963af2000` with **27 PASS / 0 WARN / 0 FAIL**.

Since that gate, GOAD_NOMAD has received additional installer and lifecycle hardening around the default `goad.sh` workflow, segmented `start` / `stop`, VMware multi-NIC management selection, fail-closed provisioning readiness, bounded waits, human-readable lifecycle timers, and SSMS compatibility. Those changes are being revalidated through a fresh interactive installation before the milestone record is updated to its new final validated source commit.

The detailed milestone record lives in [`docs/GOAD_NOMAD_MILESTONES.md`](./docs/GOAD_NOMAD_MILESTONES.md).

### Planned progression

| Milestone | Scope | Status |
| --- | --- | --- |
| 1 | Network segmentation and lifecycle | Final revalidation in progress |
| 2 | Windows foothold + local privilege escalation on WS01 | Planned / not started |
| 3 | NORTH domain escalation + persistence | Planned |
| 4 | NORTH → SevenKingdoms cross-domain progression | Planned |
| 5 | SevenKingdoms / NORTH → ESSOS cross-forest progression | Planned |
| 6 | Advanced operational / defense-evasion layers | Optional / planned |

## Training progression target

The intended end-to-end student journey is:

1. Reconnaissance and unauthenticated enumeration from NORTH.
2. Compromise a valid NORTH domain account.
3. Obtain a low-privilege foothold on the planned WS01 workstation.
4. Complete focused Windows local privilege escalation and reach local Administrator / SYSTEM.
5. Resume authenticated Active Directory enumeration.
6. Escalate through `north.sevenkingdoms.local` to Domain Admin.
7. Complete a dedicated NORTH domain-persistence phase.
8. Cross the child/root boundary into `sevenkingdoms.local`.
9. Cross the forest boundary into `essos.local` using identity abuse plus realistic pivoting.
10. Continue into optional advanced operational, defense-evasion and hybrid identity layers.

The intended scope progression is:

```text
Machine → Domain → Parent Domain → Forest → Foreign Forest
```

## Validation

Source-only segmentation preflight:

```bash
bash scripts/validate-network-segmentation-source.sh
```

Complete runtime / clean-checkout validation against a deployed provider:

```bash
export GOAD_PROVIDER_DIR="$HOME/Documents/GOAD_NOMAD/workspace/<instance>/provider"
bash scripts/validate-network-segmentation.sh
```

The interactive installation path is intentionally being treated as a first-class validation target: a user cloning GOAD_NOMAD should not have to manually reconstruct the segmented architecture after launching `./goad.sh`.

## Upstream GOAD foundation

GOAD_NOMAD is a modified fork of **[Orange Cyberdefense / GOAD](https://github.com/Orange-Cyberdefense/GOAD)** and continues to use the GOAD Active Directory environment, vulnerabilities, identities and domain relationships as its foundation.

The inherited full GOAD topology contains five Windows servers, three domains and two forests:

- `sevenkingdoms.local`
  - Kingslanding / DC01 — Windows Server 2019
- `north.sevenkingdoms.local`
  - Winterfell / DC02 — Windows Server 2019
  - Castelblack / SRV02 — Windows Server 2019, IIS, MSSQL
- `essos.local`
  - Meereen / DC03 — Windows Server 2016
  - Braavos / SRV03 — Windows Server 2016, MSSQL, ADCS

GOAD_NOMAD preserves the parent/child trust, the SevenKingdoms ↔ ESSOS forest trust, and the Castelblack ↔ Braavos MSSQL linked-server relationship while placing those systems behind explicit network security boundaries.

For the original project, documentation and full upstream lab family, visit:

- [Orange Cyberdefense GOAD repository](https://github.com/Orange-Cyberdefense/GOAD)
- [Official GOAD documentation](https://orange-cyberdefense.github.io/GOAD/)

## Safety

> [!CAUTION]
> GOAD_NOMAD is an intentionally vulnerable offensive-security training environment. Do not deploy it directly to the Internet or reuse its vulnerable configuration as a production Active Directory design. Run it only in an isolated lab environment you control and are authorized to test.

## License and attribution

GOAD_NOMAD remains licensed under the **GNU General Public License v3.0**, consistent with the upstream GOAD project. See [`LICENSE`](./LICENSE).

This repository contains substantial modifications to the upstream project. GOAD and the original lab design are credited to **Orange Cyberdefense and the GOAD contributors**; GOAD_NOMAD identifies the additional segmented range, lifecycle, curriculum and operational changes developed in this fork.
