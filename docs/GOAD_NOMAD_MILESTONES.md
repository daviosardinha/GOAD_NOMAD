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

`WS01` is planned for Milestone 2 and will be added to NORTH as the dedicated Windows foothold and local-privilege-escalation workstation. Milestone 2 remains planned and is not automatically started by completion of Milestone 1.

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

**Status: COMPLETE**

Fresh interactive installation validated: **2026-09-01**  
Final clean source/runtime validation: **2026-09-01**  
Validated source commit: `35f592184e87ba25f427403fde4674b444aad6c8`  
Final validation result: **27 PASS / 0 WARN / 0 FAIL**

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
- Integrated the segmented lifecycle into the canonical `./goad.sh` workflow so normal `install`, `start`, `stop`, `status`, `network`, `mode`, and `validate` operations understand GOAD_NOMAD.
- Hardened provider bring-up so `GOAD-ROUTER`, provisioning policy, and temporary routes are established before protected-zone Windows guests are started.
- Added fail-closed management readiness: all five Ansible WinRM endpoints must pass before provisioning is allowed to begin.
- Hardened segmented `start` and `stop` with bounded controller waits, VMware state verification, targeted recovery, and preservation/restoration of the recorded runtime mode.
- Stabilized Vagrant on multi-NIC Windows guests by preferring the NAT/provisioning management path rather than allowing VMware guest-IP discovery to select a protected-zone address and consume the boot timeout.
- Removed redundant Windows restart churn by keeping the Vagrant NAT adapter persistent state synchronized with provisioning mode.
- Added human-readable lifecycle timers that automatically format elapsed time in seconds, minutes, or hours.
- Pinned the GOAD-compatible SSMS 18 installer so the current `aka.ms` redirect cannot silently introduce an incompatible newer SSMS release.
- Ensured a successful full Ansible run has one authoritative final exercise-isolation transition instead of applying exercise mode twice.
- Added `scripts/validate-network-segmentation-source.sh` for clean-checkout static/source preflight, including lifecycle-ownership regression checks using the Python AST.
- Added `scripts/validate-network-segmentation.sh` and the runtime validator for the complete clean-source reproducibility gate against an existing deployed provider.
- Hardened the child-domain provisioning role to install DNS Server plus management tools before promotion, explicitly request DNS during `Install-ADDSDomain`, disable IPv6 on the provisioning NIC, start the DNS service, validate that the child DNS zone is AD-integrated, and keep Active Directory Web Services enabled and running.
- Preserved the parent-domain conditional forwarder and forest-replicated remote-DC conditional-forwarder design used by GOAD trusts.
- Hardened runtime validation around normal Windows service startup races after exercise-mode power cycling rather than confusing service readiness with a segmentation failure.
- Correctly treats repeating GOAD scheduled tasks in Task Scheduler `Running` state (`0x00041301` / decimal `267009`) as healthy when appropriate instead of misclassifying an actively executing bot as failed.

#### Validated exercise-policy exceptions

- Winterfell `10.4.10.11` ↔ Kingslanding `10.4.20.10` for the NORTH child-domain / SevenKingdoms parent-domain relationship and Active Directory dynamic RPC.
- Kingslanding `10.4.20.10` ↔ Meereen `10.4.30.12` for the SevenKingdoms / ESSOS forest trust.
- Winterfell `10.4.10.11` ↔ Meereen `10.4.30.12` on TCP/UDP 53 for GOAD's cross-forest conditional DNS behavior.
- Castelblack `10.4.10.22` ↔ Braavos `10.4.30.23` on TCP 1433 for the deliberate MSSQL linked-server relationship.
- Established and related return traffic.
- All other forwarded traffic is denied by the exercise chain policy.

#### End-to-end validation gates passed

- A fresh interactive `./goad.sh install` completed against the separate test clone and automatically returned the finished range to exercise isolation.
- All five original GOAD Windows hosts operate on their intended segmented addresses and routes.
- NORTH child-domain health is operational.
- NORTH ↔ SevenKingdoms DC discovery and bidirectional parent/child trust are operational.
- SevenKingdoms ↔ ESSOS DC discovery and bidirectional forest trust are operational.
- Cross-forest conditional DNS works through the explicitly permitted DC-to-DC DNS path.
- Castelblack → Braavos linked-server execution succeeds with remote login `sa`.
- Braavos → Castelblack linked-server execution succeeds with remote login `sa`.
- GOAD `connect_bot`, `ntlm_bot`, and `responder_bot` scheduled tasks remain healthy; validation accepts the repeating responder task while legitimately in Task Scheduler `Running` state.
- The student/host side retains direct NORTH access.
- Direct student/host access to SevenKingdoms and ESSOS is blocked.
- Temporary protected-zone host routes are absent in exercise mode.
- All five Windows provisioning NAT paths are disconnected in exercise mode.
- NAT isolation survives repeated Windows VM power cycles.
- Provisioning → exercise → provisioning → exercise transitions are reversible and validated.
- The router exercise policy persists through `nftables`.
- Firewall counters confirm traffic traverses the intended parent/child AD, forest-trust, cross-forest DNS, and linked-MSSQL exceptions rather than an unintended flat path.

#### Final clean-source reproducibility gate — PASSED

The final validation cycle used a separate `GOAD_NOMAD-fresh-test` clone to build the fresh deployed provider. After the interactive installation completed, the final runtime/reproducibility gate was executed from a clean, origin-synced checkout at source commit `35f592184e87ba25f427403fde4674b444aad6c8` against that deployed provider through `GOAD_PROVIDER_DIR`. All required checks passed:

1. Source preflight completed successfully with a clean Git working tree and valid Bash, Python, Ruby/Vagrant, and `nftables` syntax.
2. The lifecycle regression gate confirmed one authoritative final exercise transition and the GOAD_NOMAD human-readable timer path.
3. `provisioning` and `exercise` transitions worked from committed source, including persistent VMware `startConnected` changes.
4. All five Vagrant/WinRM management paths worked in provisioning mode and all five NAT management paths were isolated again in exercise mode.
5. The committed `ad-child_domain.yml` configuration was replayed twice; the second child-domain promotion task was idempotent (`ok`) rather than re-promoting the domain.
6. The committed `ad-trusts.yml` configuration replayed successfully with no unreachable or failed hosts.
7. Winterfell retained the AD-integrated child DNS zone, parent forwarder to Kingslanding `10.4.20.10`, and ESSOS forwarder to Meereen `10.4.30.12`; the forest-replicated ESSOS forwarder on Kingslanding was also correct.
8. Parent/child trust, forest trust, GOAD bots, and both linked-SQL directions passed in provisioning mode.
9. After returning to exercise mode, NORTH remained directly reachable while direct SevenKingdoms and ESSOS access remained blocked and protected-zone host routes were absent.
10. Exercise-path validation from NORTH succeeded for parent DC discovery, cross-forest ESSOS DNS, and Castelblack → Braavos linked SQL after the power-cycle transition.
11. Final firewall counters recorded traffic on the explicitly intended inter-zone rules, with the router still using a `policy drop` forward chain.
12. The lab finished in recorded `exercise` mode with all five Windows `ethernet0.startConnected = "FALSE"` and provisioning NAT paths isolated.

The final validator reported **27 PASS / 0 WARN / 0 FAIL** and ended with `CLEAN-CHECKOUT NETWORK SEGMENTATION RUNTIME VALIDATION PASSED`.

#### Validation commands

Source-only preflight:

```bash
bash scripts/validate-network-segmentation-source.sh
```

Complete runtime/reproducibility gate against a deployed provider:

```bash
export GOAD_PROVIDER_DIR="$HOME/Documents/GOAD_NOMAD/workspace/<instance>/provider"
bash scripts/validate-network-segmentation.sh
```

#### Operational notes

- Windows Vagrant NAT addresses are DHCP-assigned and may change between boots; the mode controller does not depend on those addresses.
- In exercise mode, Vagrant may discover an exercise-side `10.4.x.x` address as a guest's primary IP. This is expected; normal Vagrant/Ansible maintenance belongs in provisioning mode.
- `GOAD-ROUTER` keeps its own Vagrant NAT adapter for operator SSH/control. The exercise firewall's deny-by-default forward policy prevents that management path from becoming a student inter-zone bypass.
- `vmnet99` remains a host-visible router management network; Windows guests are not attached to it and the exercise forward policy does not grant it arbitrary access to protected zones.

### Milestone 2 — Windows Foothold & Local Privilege Escalation

**Status: PLANNED / NOT STARTED**

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
