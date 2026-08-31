# GOAD_NOMAD — Major Project Milestones

This document tracks only the major GOAD_NOMAD project milestones. Individual implementation steps, fixes, and smoke tests belong in normal development history and do not become milestones by themselves.

A milestone is marked COMPLETE only when its full scope is integrated into the project and its end-to-end validation gates pass, including clean-checkout reproducibility for source changes that control deployment or isolation.

## Current architecture

### VMware networks

| VMware network | Zone | Subnet | Host-side access | Router address |
| --- | --- | --- | --- | --- |
| `vmnet10` | NORTH | `10.4.10.0/24` | `10.4.10.254/24` | `10.4.10.1/24` |
| `vmnet20` | SEVENKINGDOMS | `10.4.20.0/24` | none | `10.4.20.1/24` |
| `vmnet30` | ESSOS | `10.4.30.0/24` | none | `10.4.30.1/24` |
| `vmnet99` | MANAGEMENT | `10.4.99.0/24` | `10.4.99.254/24` | `10.4.99.1/24` |

VMware DHCP and VMware NAT are disabled on the four GOAD_NOMAD networks. Existing VMware networks such as `vmnet1` and `vmnet8` are preserved.

The student attack host attaches directly to NORTH. There is no project-owned Kali VLAN. SEVENKINGDOMS and ESSOS deliberately have no host-side VMware adapters so the host cannot bypass the lab router and pivoting model.

### GOAD host placement

| Host | Role | Zone | Target address |
| --- | --- | --- | --- |
| GOAD-DC02 / Winterfell | NORTH child-domain DC | NORTH | `10.4.10.11` |
| GOAD-SRV02 / Castelblack | NORTH member server / MSSQL | NORTH | `10.4.10.22` |
| GOAD-DC01 / Kingslanding | sevenkingdoms.local root DC | SEVENKINGDOMS | `10.4.20.10` |
| GOAD-DC03 / Meereen | essos.local DC | ESSOS | `10.4.30.12` |
| GOAD-SRV03 / Braavos | ESSOS member server / MSSQL / ADCS | ESSOS | `10.4.30.23` |
| GOAD-ROUTER | Debian 11 routing plane | all zones | `.1` on each zone |

`WS01` is planned for Milestone 2 and will be added to NORTH as the dedicated Windows foothold and local-privilege-escalation workstation. Milestone 2 does not begin until Milestone 1's clean-checkout gate is closed.

### Provisioning mode vs exercise mode

GOAD_NOMAD deliberately separates deployment connectivity from the student attack surface.

During **provisioning mode**, the five Windows VMware NAT adapters are persistently enabled and connected, the host receives temporary routes to SEVENKINGDOMS and ESSOS through `GOAD-ROUTER`, and the router uses the permissive provisioning firewall policy. This preserves Vagrant/Ansible and maintenance access without exposing permanent host adapters inside the protected zones.

During **exercise mode**, `scripts/lab-mode.sh` installs the deny-by-default router policy, removes the temporary protected-zone host routes, sets every Windows provisioning adapter to `ethernet0.startConnected = "FALSE"`, and disconnects those adapters at the VMware hypervisor layer. The persistent VMware flag ensures the provisioning bypass does not return after a Windows VM power cycle.

The supported controller is:

```bash
./scripts/lab-mode.sh status
./scripts/lab-mode.sh provisioning
./scripts/lab-mode.sh exercise
```

Run the controller as the normal desktop user. It invokes `sudo` only for host routing operations.

## Major milestone status

### Milestone 1 — Network Segmentation

**Status: VALIDATION PENDING**

Live implementation validated: **2026-08-31**

Goal: fully integrate realistic network segmentation into GOAD while preserving the original GOAD functionality required by the training path and proving that the committed source reproduces the validated behavior without manual repair.

#### Implemented changes

- Automated VMware networks `vmnet10` (NORTH), `vmnet20` (SEVENKINGDOMS), `vmnet30` (ESSOS), and `vmnet99` (MANAGEMENT).
- Preserved existing VMware networks such as `vmnet1` and `vmnet8`; GOAD_NOMAD owns only its four dedicated vmnets.
- Added persistent host addresses `10.4.10.254/24` on NORTH and `10.4.99.254/24` on MANAGEMENT without host adapters on SEVENKINGDOMS or ESSOS.
- Added Debian 11 `GOAD-ROUTER` with deterministic interfaces, `.1/24` gateway addresses, IPv4 forwarding, and persistent `nftables`.
- Moved the five original GOAD Windows systems to deterministic segmented `10.4.x.x` addresses while retaining Vagrant NAT only as a provisioning plane.
- Added explicit provisioning-only host routes to `10.4.20.0/24` and `10.4.30.0/24` through `10.4.10.1`.
- Added `scripts/lab-mode.sh` with reversible `status`, `provisioning`, and `exercise` operations.
- Added persistent Windows provisioning-NIC isolation using `ethernet0.startConnected = "FALSE"` plus immediate hypervisor-level disconnects with `vmrun`.
- Added `ad/GOAD/providers/vmware/router/nftables/provisioning.nft` for permissive deployment/maintenance forwarding.
- Added `ad/GOAD/providers/vmware/router/nftables/exercise.nft` for deny-by-default training enforcement.
- Added `scripts/validate-network-segmentation-source.sh` for clean-checkout source preflight.
- Hardened the child-domain provisioning role to install DNS Server plus management tools before promotion, explicitly request DNS during `Install-ADDSDomain`, disable IPv6 on the provisioning NIC, start the DNS service, and validate that the child DNS zone is AD-integrated.
- Preserved the parent-domain conditional forwarder and forest-replicated remote-DC conditional-forwarder design used by GOAD trusts.

#### Validated exercise-policy exceptions

- Winterfell `10.4.10.11` ↔ Kingslanding `10.4.20.10` for the NORTH child-domain / SevenKingdoms parent-domain relationship and Active Directory dynamic RPC.
- Kingslanding `10.4.20.10` ↔ Meereen `10.4.30.12` for the SevenKingdoms / ESSOS forest trust.
- Winterfell `10.4.10.11` ↔ Meereen `10.4.30.12` on TCP/UDP 53 for GOAD's cross-forest conditional DNS behavior.
- Castelblack `10.4.10.22` ↔ Braavos `10.4.30.23` on TCP 1433 for the deliberate MSSQL linked-server relationship.
- Established and related return traffic.
- All other forwarded traffic is denied by the exercise chain policy.

#### Live end-to-end validation gates passed

- All five original GOAD Windows hosts operate on their intended segmented addresses and routes.
- NORTH child-domain health is operational.
- NORTH ↔ SevenKingdoms DC discovery and bidirectional parent/child trust are operational.
- SevenKingdoms ↔ ESSOS DC discovery and bidirectional forest trust are operational.
- Cross-forest conditional DNS works through the explicitly permitted DC-to-DC DNS path.
- Castelblack → Braavos linked-server execution succeeds with remote login `sa`.
- Braavos → Castelblack linked-server execution succeeds with remote login `sa`.
- GOAD `connect_bot`, `ntlm_bot`, and `responder_bot` tasks remain healthy with `LastResult = 0`.
- The student/host side retains direct NORTH access.
- Direct student/host access to SevenKingdoms and ESSOS is blocked.
- Temporary protected-zone host routes are absent in exercise mode.
- All five Windows provisioning NAT paths are disconnected in exercise mode.
- NAT isolation survives repeated Windows VM power cycles.
- Provisioning → exercise → provisioning → exercise transitions are reversible and validated.
- The router exercise policy persists through `nftables`.

#### Clean-checkout reproducibility gate — pending

Milestone 1 is not COMPLETE until all of the following pass from a separate clone of `feat/network-segmentation`:

1. `scripts/validate-network-segmentation-source.sh` passes from the clean checkout.
2. The clean checkout operates the existing deployed provider through `GOAD_PROVIDER_DIR` without relying on files from the development checkout.
3. `status`, `provisioning`, and `exercise` mode transitions work from the clean checkout.
4. Exercise mode again proves persistent NAT isolation, removal of protected-zone host routes, NORTH reachability, and blocked direct access to SevenKingdoms/ESSOS.
5. The relevant child-domain DNS/trust Ansible configuration is rerun from committed source in provisioning mode and is idempotent.
6. Winterfell retains an AD-integrated `north.sevenkingdoms.local` DNS zone, the parent forwarder points to Kingslanding, and the forest-replicated `essos.local` forwarder points to Meereen without manual PowerShell repair.
7. Parent/child trust, forest trust, GOAD bots, and both linked-SQL execution paths remain healthy after the source-driven rerun.
8. The lab is returned to exercise mode and all five provisioning NAT adapters remain persistently isolated.

Only after these gates pass will this document be changed back to **Status: COMPLETE**.

#### Operational notes

- Windows Vagrant NAT addresses are DHCP-assigned and may change between boots; the mode controller does not depend on those addresses.
- In exercise mode, Vagrant may discover an exercise-side `10.4.x.x` address as a guest's primary IP. This is expected; normal Vagrant/Ansible maintenance belongs in provisioning mode.
- `GOAD-ROUTER` keeps its own Vagrant NAT adapter for operator SSH/control. The exercise firewall's deny-by-default forward policy prevents that management path from becoming a student inter-zone bypass.
- `vmnet99` remains a host-visible router management network; Windows guests are not attached to it and the exercise forward policy does not grant it arbitrary access to protected zones.

### Milestone 2 — Windows Foothold & Local Privilege Escalation

**Status: PLANNED / BLOCKED BY MILESTONE 1**

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