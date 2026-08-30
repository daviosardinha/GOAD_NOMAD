# GOAD_NOMAD — Project Milestones

This document is the living implementation tracker for GOAD_NOMAD. It must be updated whenever a milestone changes state, architecture decisions change, or validation results materially change.

## Current architecture

### VMware networks

| VMware network | Zone | Subnet | Host-side access | Router address |
| --- | --- | --- | --- | --- |
| `vmnet10` | NORTH | `10.4.10.0/24` | `10.4.10.254/24` | `10.4.10.1/24` |
| `vmnet20` | SEVENKINGDOMS | `10.4.20.0/24` | none | `10.4.20.1/24` |
| `vmnet30` | ESSOS | `10.4.30.0/24` | none | `10.4.30.1/24` |
| `vmnet99` | MANAGEMENT | `10.4.99.0/24` | `10.4.99.254/24` | `10.4.99.1/24` |

VMware DHCP and VMware NAT are disabled on `vmnet10`, `vmnet20`, `vmnet30`, and `vmnet99`. Existing VMware networks such as `vmnet1` and `vmnet8` are preserved.

The student attack host is intended to attach directly to NORTH. There is no project-owned Kali VLAN. SEVENKINGDOMS and ESSOS deliberately have no host-side VMware adapters so the host cannot bypass the lab router and pivoting model.

### GOAD host placement target

| Host | Role | Zone | Target address |
| --- | --- | --- | --- |
| GOAD-DC02 / Winterfell | NORTH child-domain DC | NORTH | `10.4.10.11` |
| GOAD-SRV02 / Castelblack | NORTH member server / MSSQL | NORTH | `10.4.10.22` |
| GOAD-DC01 / Kingslanding | sevenkingdoms.local root DC | SEVENKINGDOMS | `10.4.20.10` |
| GOAD-DC03 / Meereen | essos.local DC | ESSOS | `10.4.30.12` |
| GOAD-SRV03 / Braavos | ESSOS member server / MSSQL / ADCS | ESSOS | `10.4.30.23` |
| GOAD-ROUTER | Debian 11 routing plane | all zones | `.1` on each zone |

`WS01` will be added later to NORTH after the segmented original five-host GOAD topology is validated.

## Milestone status

### Milestone 1 — VMware segmented routing plane

**Status: COMPLETE**

Implemented:

- Automated VMware host network creation and validation.
- Existing VMware `vmnet1` and `vmnet8` preserved.
- `vmnet10`, `vmnet20`, `vmnet30`, and `vmnet99` created with deterministic addressing.
- Host adapters exposed only on NORTH and MANAGEMENT.
- Persistent host-side addresses:
  - `vmnet10` → `10.4.10.254/24`
  - `vmnet99` → `10.4.99.254/24`
- Debian 11 `GOAD-ROUTER` managed by Vagrant.
- Router NICs attached to all four GOAD_NOMAD VMware networks.
- Router addresses configured persistently:
  - NORTH → `10.4.10.1/24`
  - SEVENKINGDOMS → `10.4.20.1/24`
  - ESSOS → `10.4.30.1/24`
  - MANAGEMENT → `10.4.99.1/24`
- IPv4 forwarding enabled.
- `nftables` installed, enabled, and persistent.
- Temporary forwarding policy remains `ACCEPT` for topology validation.
- Vagrant NAT remains temporarily attached to the router for provisioning/SSH.

Validation completed:

- Host network checker returns `[READY]`.
- Kali host reaches `10.4.10.1` and `10.4.99.1`.
- No host adapters exist for `vmnet20` or `vmnet30`.
- Router survives `vagrant reload` without reprovisioning.
- All four router lab addresses survive reboot.
- `/proc/sys/net/ipv4/ip_forward` returns `1` after reboot.
- `nftables` returns `active` after reboot.

### Milestone 2 — Move original GOAD Windows hosts into segmented zones

**Status: ACTIVE**

Objectives:

- Replace the current flat VMware IP model with per-host zone/network definitions.
- Preserve Vagrant and Ansible provisioning while Windows hosts move to their final networks.
- Use the target addresses listed above.
- Set `10.4.x.1` as the default gateway where routing is required.
- Ensure DNS/domain-join behavior remains correct after segmentation.
- Avoid management-plane or Vagrant-NAT paths becoming exercise-time segmentation bypasses.

Validation gates before this milestone is complete:

- All five original GOAD Windows machines provision successfully.
- NORTH child domain remains healthy.
- `north.sevenkingdoms.local` parent/child relationship with `sevenkingdoms.local` remains healthy.
- `sevenkingdoms.local` ↔ `essos.local` forest trust remains healthy.
- Castelblack ↔ Braavos MSSQL linked-server relationship still works.
- Student host on NORTH cannot directly access SEVENKINGDOMS or ESSOS through a host-side bypass.

### Milestone 3 — Enforce segmentation policy

**Status: PLANNED**

Replace the temporary router `ACCEPT` forwarding policy with deny-by-default `nftables` rules. Preserve only legitimate required paths, including:

- Winterfell / DC02 ↔ Kingslanding / DC01 for parent-child AD operation.
- Kingslanding / DC01 ↔ Meereen / DC03 for forest-trust operation.
- Castelblack / SRV02 ↔ Braavos / SRV03 for the MSSQL linked-server path.
- Explicit management/provisioning flows required by the deployment system.

Student-originated traffic from NORTH must not gain direct routed access to SEVENKINGDOMS or ESSOS simply because legitimate server-to-server flows exist.

### Milestone 4 — Add WS01 and Windows Local Privilege Escalation curriculum

**Status: PLANNED**

- Add one Windows workstation in NORTH.
- Use resettable/reconfigurable vulnerability profiles rather than adding many Windows VMs.
- Implement the PNPT-derived local privilege escalation scenarios as a focused curriculum phase.
- Student flow: obtain NORTH domain credentials → foothold on WS01 → complete local privilege escalation curriculum → resume authenticated AD enumeration.

### Milestone 5 — NORTH domain escalation and persistence

**Status: PLANNED**

- Continue GOAD authenticated enumeration and AD privilege escalation inside NORTH.
- Reach NORTH Domain Admin.
- Add a dedicated domain-persistence curriculum before moving to the parent domain.
- Persistence scenarios include the relevant Golden/Silver ticket concepts and additional techniques such as Diamond Ticket, Sapphire Ticket, Skeleton Key, and AdminSDHolder where appropriate.

### Milestone 6 — Cross-domain progression to SEVENKINGDOMS

**Status: PLANNED**

- Preserve and enrich the NORTH child-domain → `sevenkingdoms.local` parent-domain attack path.
- Combine identity-trust abuse with real network pivoting rather than treating the trust as a flat-network exercise.

### Milestone 7 — Cross-forest progression to ESSOS

**Status: PLANNED**

- Preserve and enrich `sevenkingdoms.local` / NORTH → `essos.local` cross-forest scenarios.
- Retain the Castelblack ↔ Braavos MSSQL linked-server path as a deliberate cross-zone service relationship.
- Add selected CRTE-derived cross-forest techniques as original GOAD_NOMAD scenarios.

### Milestone 8 — Advanced operational layers

**Status: PLANNED / OPTIONAL**

Potential later layers:

- Defender/MDE and endpoint-evasion exercises.
- LSASS credential-access stages and defense-bypass scenarios.
- richer gMSA scenarios.
- additional cross-forest constrained delegation and PAM / Shadow Security Principal concepts.
- hybrid identity / Entra / PHS extension if the project scope expands that far.

## Curriculum progression target

The intended student progression is:

1. GOAD reconnaissance and unauthenticated enumeration in NORTH.
2. Compromise a valid NORTH domain account.
3. Use that credential to obtain a low-privilege foothold on WS01.
4. Pause broad AD exploitation and complete the Windows Local Privilege Escalation curriculum.
5. Resume authenticated AD enumeration.
6. Escalate through NORTH to Domain Admin.
7. Complete NORTH domain-persistence scenarios.
8. Cross the child/root boundary into SEVENKINGDOMS.
9. Cross the forest boundary into ESSOS using identity abuse plus realistic pivoting.
10. Continue into optional advanced operational/evasion layers.

## Documentation rule

Every implementation milestone must update this document in the same development branch before the milestone is considered complete. New architecture decisions should also be reflected here rather than existing only in chat history.