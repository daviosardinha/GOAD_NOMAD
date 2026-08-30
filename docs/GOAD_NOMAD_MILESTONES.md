# GOAD_NOMAD — Major Project Milestones

This document tracks only the major GOAD_NOMAD project milestones. Individual implementation steps, fixes, and smoke tests belong in normal development history and do not become milestones by themselves.

A milestone is marked COMPLETE only when its full scope is integrated into the project and its end-to-end validation gates pass.

## Current architecture target

### VMware networks

| VMware network | Zone | Subnet | Host-side access | Router address |
| --- | --- | --- | --- | --- |
| `vmnet10` | NORTH | `10.4.10.0/24` | `10.4.10.254/24` | `10.4.10.1/24` |
| `vmnet20` | SEVENKINGDOMS | `10.4.20.0/24` | none | `10.4.20.1/24` |
| `vmnet30` | ESSOS | `10.4.30.0/24` | none | `10.4.30.1/24` |
| `vmnet99` | MANAGEMENT | `10.4.99.0/24` | `10.4.99.254/24` | `10.4.99.1/24` |

VMware DHCP and VMware NAT are disabled on the four GOAD_NOMAD networks. Existing VMware networks such as `vmnet1` and `vmnet8` are preserved.

The student attack host attaches directly to NORTH. There is no project-owned Kali VLAN. SEVENKINGDOMS and ESSOS deliberately have no host-side VMware adapters so the host cannot bypass the lab router and pivoting model.

### GOAD host placement target

| Host | Role | Zone | Target address |
| --- | --- | --- | --- |
| GOAD-DC02 / Winterfell | NORTH child-domain DC | NORTH | `10.4.10.11` |
| GOAD-SRV02 / Castelblack | NORTH member server / MSSQL | NORTH | `10.4.10.22` |
| GOAD-DC01 / Kingslanding | sevenkingdoms.local root DC | SEVENKINGDOMS | `10.4.20.10` |
| GOAD-DC03 / Meereen | essos.local DC | ESSOS | `10.4.30.12` |
| GOAD-SRV03 / Braavos | ESSOS member server / MSSQL / ADCS | ESSOS | `10.4.30.23` |
| GOAD-ROUTER | Debian 11 routing plane | all zones | `.1` on each zone |

`WS01` will be added later to NORTH after the segmented original five-host GOAD topology is fully validated.

## Major milestone status

### Milestone 1 — Network Segmentation

**Status: ACTIVE**

Goal: fully integrate realistic network segmentation into GOAD while preserving all original GOAD functionality required by the training path.

Current progress:

- VMware host networks `vmnet10`, `vmnet20`, `vmnet30`, and `vmnet99` are automated and validated.
- Debian 11 `GOAD-ROUTER` is implemented and survives reboot with all four lab interfaces.
- IPv4 forwarding and persistent `nftables` are working.
- NORTH and MANAGEMENT host-side access are working.
- SEVENKINGDOMS and ESSOS correctly have no host-side VMware adapters.
- Router forwarding is temporarily permissive while the original GOAD hosts are migrated and validated.

Remaining before this milestone can be marked COMPLETE:

- Move all five original GOAD Windows hosts into their target zones and addresses.
- Preserve Vagrant and Ansible provisioning in the segmented topology.
- Configure correct default gateways and DNS behavior.
- Validate NORTH child-domain health.
- Validate NORTH ↔ SEVENKINGDOMS parent/child Active Directory relationship.
- Validate SEVENKINGDOMS ↔ ESSOS forest trust.
- Validate Castelblack ↔ Braavos MSSQL linked-server relationship.
- Replace temporary allow-forward policy with deny-by-default segmentation rules.
- Confirm the student host in NORTH cannot directly route to SEVENKINGDOMS or ESSOS.
- Confirm legitimate DC-to-DC and server-to-server cross-zone relationships still function.
- Remove or harden temporary provisioning paths so they cannot become exercise-time segmentation bypasses.

Only after all of the above passes is **Network Segmentation** complete.

### Milestone 2 — Windows Foothold & Local Privilege Escalation

**Status: PLANNED**

Goal: add one Windows workstation (`WS01`) in NORTH and implement the PNPT-derived Windows Local Privilege Escalation curriculum using resettable vulnerability profiles instead of many extra VMs.

Target flow:

1. Reconnaissance and unauthenticated enumeration in NORTH.
2. Obtain a valid NORTH domain credential.
3. Use that credential to obtain a low-privilege foothold on WS01.
4. Pause broad AD exploitation.
5. Complete the Windows Local Privilege Escalation curriculum on WS01.
6. Reach local Administrator/SYSTEM.
7. Resume authenticated Active Directory enumeration.

### Milestone 3 — NORTH Domain Escalation & Persistence

**Status: PLANNED**

Goal: continue the GOAD attack path inside `north.sevenkingdoms.local`, reach Domain Admin, and add a dedicated domain-persistence curriculum before moving into the parent domain.

Planned persistence coverage includes the relevant Golden/Silver ticket concepts plus techniques such as Diamond Ticket, Sapphire Ticket, Skeleton Key, and AdminSDHolder where appropriate.

### Milestone 4 — Cross-Domain Progression

**Status: PLANNED**

Goal: enrich the NORTH child-domain → `sevenkingdoms.local` parent-domain progression so it combines Active Directory trust abuse with real network pivoting and constrained reachability.

### Milestone 5 — Cross-Forest Progression

**Status: PLANNED**

Goal: preserve and expand the SevenKingdoms/NORTH → `essos.local` attack paths, including realistic pivoting and selected CRTE-derived cross-forest scenarios.

The Castelblack ↔ Braavos MSSQL linked-server path remains a deliberate direct NORTH ↔ ESSOS service relationship across the segmented network.

### Milestone 6 — Advanced Operational Layers

**Status: PLANNED / OPTIONAL**

Potential later scope includes:

- Defender/MDE and endpoint-evasion exercises.
- LSASS credential-access stages and defense-bypass scenarios.
- richer gMSA abuse scenarios.
- additional constrained-delegation and cross-forest trust scenarios.
- PAM / Shadow Security Principal concepts.
- hybrid identity / Entra / PHS extension if the project scope expands that far.

## Curriculum progression target

The intended end-to-end student progression is:

1. GOAD reconnaissance and unauthenticated enumeration in NORTH.
2. Compromise a valid NORTH domain account.
3. Obtain a low-privilege foothold on WS01.
4. Complete Windows Local Privilege Escalation.
5. Resume authenticated AD enumeration.
6. Escalate through NORTH to Domain Admin.
7. Complete NORTH domain-persistence scenarios.
8. Cross the child/root boundary into SEVENKINGDOMS.
9. Cross the forest boundary into ESSOS using identity abuse plus realistic pivoting.
10. Continue into optional advanced operational/evasion layers.

## Documentation rule

Update this file only when a major milestone changes state, its scope materially changes, or a major architecture decision changes. Individual bug fixes, smoke tests, and implementation details should remain in commits, code comments, and focused technical documentation rather than creating new milestones.