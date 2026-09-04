<div align="center">

# GOAD Kingdoms

<img width="1122" height="1402" alt="goad" src="https://github.com/user-attachments/assets/f4f90c84-e145-4904-94ff-2167c91f33f3" />

### Segmented Active Directory Red Team Training Range

**Segment. Pivot. Escalate. Persist.**

GOAD Kingdoms extends the original **Game Of Active Directory (GOAD)** into a routed, segmented Red Team training range while preserving the progressive learning model that makes GOAD such a strong Active Directory lab.

The project adds realistic network boundaries, a first-class Windows workstation, Windows local privilege escalation, hardened lifecycle automation, real pivoting opportunities, and an expandable advanced Active Directory curriculum.

**Built on [Orange Cyberdefense GOAD](https://github.com/Orange-Cyberdefense/GOAD). Extended for a broader training model.**

**Latest release: [v1.1.1 — Lifecycle Reliability](https://github.com/daviosardinha/GOAD_NOMAD/releases/tag/v1.1.1)**

</div>

---

> [!NOTE]
> This project was named **GOAD_NOMAD** through Milestone 1 and the `v1.0.0 — Segmented Foundation` release. Historical v1.0.0 release notes intentionally keep that name. Development after v1.0.0 uses the **GOAD Kingdoms** identity. Some internal compatibility identifiers still retain `GOAD_NOMAD` / `nomad` names so validated lifecycle behavior is not changed only for cosmetic reasons.

## Why GOAD Kingdoms exists

GOAD is an excellent vulnerable Active Directory lab and Mayfly's GOAD walkthrough provides a strong progressive learning path through reconnaissance, user discovery, authenticated enumeration, relay, exploitation, ADCS, MSSQL, privilege escalation, lateral movement, delegation, ACL abuse, trusts and advanced Active Directory attacks.

GOAD Kingdoms does **not** aim to replace that learning concept.

The goal is to preserve it and expand it.

The project changes the environment so a student does not immediately treat Active Directory as a flat collection of directly reachable servers. Instead, the student can learn the same core GOAD techniques while also learning what happens before, between and after those techniques:

- how a low-privilege domain user reaches a workstation;
- how authenticated enumeration differs from Linux and Windows;
- how to enumerate and escalate privileges on a real Windows workstation;
- how a compromised host becomes an internal attack position;
- how network segmentation affects reachability;
- how and when pivoting becomes necessary;
- how domain, parent-domain and foreign-forest compromise differ;
- how persistence and advanced identity abuse fit into a complete Red Team learning path.

The project therefore treats **identity relationships** and **network reachability** as separate concepts.

A compromised credential should not automatically mean every system is directly reachable. A compromised machine should not automatically mean the domain is owned. Moving from one security boundary to another should require the student to understand the environment, obtain the right access, and use the paths intentionally exposed by the range.

For the original GOAD learning path and Mayfly walkthrough, see:

- [GOAD walkthrough series by Mayfly](https://mayfly277.github.io/categories/goad/)
- [Orange Cyberdefense GOAD](https://github.com/Orange-Cyberdefense/GOAD)

## What GOAD Kingdoms changes

| Area | Upstream GOAD foundation | GOAD Kingdoms direction |
| --- | --- | --- |
| Learning model | Progressive GOAD technique walkthrough | Preserve the GOAD progression and add more learning layers around it |
| Network model | Primarily flat lab connectivity | Routed security zones with deny-by-default exercise policy |
| Address space | Traditional GOAD lab range | `10.4.0.0/16` segmented range |
| Student entry | Broad lab reachability | Student attack host starts in NORTH |
| Cross-zone access | Network reachability is largely implicit | Explicitly permitted relationships and real pivoting |
| Deployment access | Vagrant / Ansible management path | Separate provisioning plane removed from the training surface |
| Runtime lifecycle | Standard GOAD / Vagrant operations | Kingdoms-aware `start`, `stop`, `install`, mode control, readiness gates and recovery |
| Windows workstation | No dedicated workstation learning stage | First-class NORTH Windows 10 workstation (`WS01`) |
| Authenticated enumeration | Primarily technique/tool driven | Dedicated Linux and Windows authenticated-enumeration learning stages |
| Windows local privilege escalation | Not the primary curriculum focus | Dedicated resettable 20-technique workstation curriculum |
| Pivoting | Not forced by a flat topology | Dedicated pivoting opportunities created by segmentation |
| ADCS | Split across multiple upstream walkthrough stages | Planned unified GOAD Kingdoms ADCS chapter |
| Advanced AD attacks | Existing GOAD advanced material | Expandable catalog including additional CRTE-style domain, persistence and trust techniques |
| Cross-domain / cross-forest | GOAD trust relationships | Trust abuse combined with segmentation, routing and pivoting |

## Current segmented architecture

GOAD Kingdoms places the five original GOAD Windows systems and the GOAD-WS01 workstation behind a dedicated Debian routing plane.

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

The validated exercise policy preserves:

- Winterfell `10.4.10.11` ↔ Kingslanding `10.4.20.10` for the NORTH child-domain / SevenKingdoms parent-domain relationship and required Active Directory traffic.
- Kingslanding `10.4.20.10` ↔ Meereen `10.4.30.12` for the SevenKingdoms / ESSOS forest trust.
- Winterfell `10.4.10.11` ↔ Meereen `10.4.30.12` on TCP/UDP 53 for GOAD's cross-forest conditional DNS behavior.
- Castelblack `10.4.10.22` ↔ Braavos `10.4.30.23` on TCP 1433 for the deliberate MSSQL linked-server path.
- Established and related return traffic.

Everything else traversing the routed exercise plane is denied by default.

## Two operating modes

GOAD Kingdoms has **one segmented architecture** and two runtime modes inside that architecture.

> [!IMPORTANT]
> **Exercise mode does not mean original/flat GOAD.** There is no `mode flat`, `mode mayfly`, or `mode original-goad` switch. Both `provisioning` and `exercise` are GOAD Kingdoms segmented modes.

The difference is whether the temporary management paths required to build and maintain the range are enabled.

```text
GOAD Kingdoms segmented architecture
        |
        +-- provisioning mode  -> temporary deployment/maintenance access
        |
        +-- exercise mode      -> normal student-facing segmented attack surface
```

### Provisioning mode

**Provisioning mode is an operator/installer state, not the normal student state.**

It is used temporarily by Vagrant, Ansible and maintenance operations so GOAD Kingdoms can configure systems across the protected zones.

- The NORTH / SEVENKINGDOMS / ESSOS segmentation still exists.
- Windows provisioning/NAT adapters are connected.
- Temporary host routes to protected zones are enabled through GOAD-ROUTER.
- The router uses the provisioning forwarding policy.
- Management readiness is checked before Ansible is allowed to run.
- The host temporarily receives the reachability needed to configure protected systems.

Provisioning mode therefore creates a **temporary management bypass around the student isolation policy**. It does not convert the environment into the original flat GOAD topology.

### Exercise mode

**Exercise mode is the normal student-facing state of GOAD Kingdoms.**

This is the state in which the lab is intended to be attacked and studied.

- The router switches to the deny-by-default exercise forwarding policy.
- Temporary protected-zone host routes are removed.
- Windows provisioning/NAT adapters are persistently disabled and disconnected at the VMware layer.
- NORTH remains the student entry zone.
- Direct host/student access to SEVENKINGDOMS and ESSOS is blocked.
- Only the explicitly designed cross-zone relationships required by GOAD and the training paths remain reachable through GOAD-ROUTER.

The persistent adapter state prevents a simple VM power cycle from silently restoring the provisioning bypass.

In short:

```text
provisioning mode = GOAD Kingdoms segmented lab + temporary management access
exercise mode     = GOAD Kingdoms segmented lab + student isolation enforced
```

### What happens during `install`

A normal installation automatically uses both modes. The user does not need to switch modes manually.

```text
./goad.sh
    -> install
        -> provisioning connectivity is enabled
        -> Vagrant/Ansible build and configure the lab
        -> provisioning completes
        -> final isolation is applied
        -> exercise mode
        -> installation reports success
```

A successful `install` therefore **finishes in exercise mode by default**.

Likewise, normal `start` restores the installed segmented lab to its recorded student-facing exercise state before reporting readiness.

Manual `mode provisioning` and `mode exercise` commands exist for maintenance, development, debugging and recovery. They are not normally part of the student's everyday workflow.

## `goad.sh` is the control plane

GOAD Kingdoms keeps the familiar GOAD interactive console and extends it so the normal workflow remains centered on:

```bash
./goad.sh
```

### Normal workflow

For most users the normal lifecycle is simply:

```text
install   # first build; automatically finishes in exercise mode
start     # start an existing lab and restore its normal exercise state
stop      # safely stop the lab
status    # show instance state
network   # show the segmented network profile
validate  # validate the deployed environment
```

### Operator / maintenance mode controls

These commands expose the underlying network mode directly:

```text
mode status
mode provisioning
mode exercise
```

They are primarily intended for development, maintenance, debugging and recovery. A student following the normal lab workflow should not need to switch modes manually.

For a segmented GOAD/VMware instance, the lifecycle prepares the segmented VMware networks, brings up the routing plane, validates management readiness, runs provisioning when required, and returns the completed range to exercise isolation.

### Hardened start lifecycle

As of **v1.1.1**, segmented `start`:

- authenticates sudo before changing VM state;
- keeps the sudo ticket alive non-interactively during long startup operations;
- runs collision and network preflight before guest bring-up;
- enables temporary provisioning routes only when required;
- restores the recorded exercise mode before reporting success.

### Hardened stop lifecycle

As of **v1.1.1**, segmented `stop`:

- runs the bounded Vagrant controller in its own process group;
- fully reaps timed-out Vagrant/Ruby descendants before fallback;
- avoids racing a second Vagrant action against a still-locked VM;
- uses VMware soft shutdown as the lock-free fallback;
- uses hard stop only as a final fallback;
- verifies final VMware power state before reporting success.

The real 180-second timeout path was exercised during release validation and completed with all six Windows guests and `GOAD-ROUTER` powered off.

## Current release status

### v1.0.0 — Segmented Foundation

**Milestone 1 — COMPLETE**

Established the NORTH / SEVENKINGDOMS / ESSOS / MANAGEMENT network model, routed exercise plane, provisioning/exercise lifecycle, persistent Windows NAT isolation, trust-aware firewall relationships and source/runtime validation.

Historical project/release identity: **GOAD_NOMAD**.

### v1.1.0 — NORTH Workstation & Windows LPE

**Milestone 2 — COMPLETE**

Added the first-class NORTH workstation:

- `GOAD-WS01` / `WS01`
- `10.4.10.31/24`
- Windows 10 Enterprise 22H2
- pinned `mayfly/windows10` `2024.01.06` Vagrant box
- joined to `north.sevenkingdoms.local`
- `NORTH\\rickon.stark` receives RDP access but remains non-admin
- UAC, Defender and Windows Firewall remain enabled
- provisioning NAT follows the same persistent isolation contract as the original GOAD guests

The release also introduced exactly **20 deterministic Windows local-privilege-escalation scenarios** with resettable Ansible-native profiles:

- `service-abuse`
- `credential-hunting`
- `registry-abuse`
- `token-abuse`
- `mixed`
- `full-lpe`

Every implemented technique passed:

```text
apply -> vulnerable -> reset -> clean -> reapply -> vulnerable
```

Final clean-install acceptance preserved segmentation, DNS, trusts, linked SQL, the WS01 security baseline, all 20 LPE scenarios and final exercise isolation.

### v1.1.1 — Lifecycle Reliability

**MAINTENANCE RELEASE — COMPLETE**

v1.1.1 does not change the v1.1.0 student curriculum. It hardens the operator lifecycle after real VMware testing exposed two long-running lifecycle races.

Validated fixes include:

- sudo continuity throughout segmented startup;
- pre-start collision/network checks before guest state changes;
- no late provisioning-route failure from an expired sudo ticket;
- Vagrant/Ruby process-group reaping after bounded shutdown timeout;
- no second Vagrant action while the original controller may still own locks;
- lock-free VMware soft-stop fallback;
- final all-VM power-state verification.

Validated implementation commit: `e40f7d2e7fdbcdbe5de342787471ade4b4f54c9c`  
Release commit: `db4ca4cd3a84f3e13728ddc902117c9d16df2cce`

## GOAD Kingdoms learning path

The long-term curriculum is intended to preserve the style and progression of the GOAD walkthrough while adding new stages where the original flat/server-focused environment did not provide them.

This is a **learning path**, not a requirement that every exercise be solved through one rigid attack chain. Individual techniques remain useful as focused labs, while the full Kingdoms environment gives them context.

| Part | Learning stage | Direction |
| --- | --- | --- |
| 1 | Reconnaissance and scanning | Preserve / expand original GOAD Part 1 |
| 2 | Finding users and unauthenticated enumeration | Preserve / expand original GOAD Part 2 |
| 3 | Authenticated enumeration via Linux | Expanded GOAD authenticated-enumeration stage |
| 4 | Authenticated enumeration via Windows | **GOAD Kingdoms addition using WS01** |
| 5 | Windows local privilege escalation | **Implemented in v1.1.0 — 20-technique catalog** |
| 6 | Poisoning and relay | Preserve original GOAD poison/relay learning stage |
| 7 | Exploitation with a domain user | Preserve / expand original GOAD authenticated exploitation |
| 8 | Active Directory Certificate Services | **Unified GOAD Kingdoms ADCS chapter** instead of splitting the subject across two chapters |
| 9 | MSSQL attacks | Preserve / expand original GOAD MSSQL material |
| 10 | Server privilege escalation | Preserve server-side privilege-escalation context separately from WS01 LPE |
| 11 | Lateral movement | Preserve / expand original GOAD lateral-movement material |
| 12 | Network pivoting | **GOAD Kingdoms addition enabled by real segmentation** |
| 13 | Kerberos delegation | Preserve / expand unconstrained, constrained and RBCD learning |
| 14 | Active Directory ACL abuse | Preserve / expand GOAD ACL material |
| 15 | Domain and forest trusts | Preserve GOAD trust learning and combine it with network boundaries |
| 16 | Advanced domain attacks | Preserve GOAD advanced material and expand the technique catalog |
| 17 | Domain persistence | Expanded Kingdoms persistence curriculum |
| 18 | Cross-domain attacks | Expanded child/root and domain-boundary curriculum |
| 19 | Cross-forest attacks | Expanded foreign-forest curriculum plus pivoting requirements |

### Why Parts 3 and 4 are separate

The student should learn authenticated enumeration from **both sides**.

Part 3 keeps the student on Kali/Linux and teaches how to enumerate Active Directory with valid credentials from an attacker-controlled system.

Part 4 moves the student onto the domain-joined WS01 foothold and teaches the Windows-native view of the same environment: local/domain context, groups, privileges, Kerberos tickets, DNS, shares, PowerShell/AD tooling, SharpHound and related Windows-native discovery.

The student then moves naturally into Part 5 and asks a different question:

> I can access this Windows workstation as a normal domain user. How do I become local Administrator or SYSTEM?

That is the role of the v1.1.0 Windows LPE curriculum.

### Why Poison & Relay stays in the learning path

GOAD Kingdoms keeps the original poisoning/relay subject rather than removing it simply because the student has already learned authenticated enumeration.

The difference is that the segmented environment can give the subject more context: the student is now learning what can happen from an internal network position and how captured/relayed authentication can affect later movement.

### Why Windows workstation LPE and server privilege escalation are separate

They teach different contexts.

**Part 5** teaches local Windows privilege escalation from a normal interactive domain-user foothold on WS01.

**Part 10** preserves the server-side privilege-escalation stage where the initial context may be a service, application, web shell or other restricted server identity.

Both belong in the curriculum.

## Future advanced technique expansion

GOAD Kingdoms is intended to grow beyond the vulnerability catalog currently covered by the Mayfly GOAD walkthrough.

Future subject areas can be added to the relevant chapters instead of creating disconnected one-off labs. Planned expansion areas include techniques such as:

- targeted Kerberoasting;
- LAPS abuse;
- gMSA abuse;
- LSASS and credential-material discovery;
- Pass-the-Certificate and certificate-based identity abuse;
- unconstrained delegation;
- constrained delegation and protocol transition;
- Resource-Based Constrained Delegation (RBCD);
- Shadow Credentials;
- advanced Kerberos ticket attacks;
- AdminSDHolder and domain persistence;
- child-to-root-domain escalation;
- SIDHistory and trust-key abuse;
- cross-domain ADCS abuse;
- cross-forest Kerberoasting and delegation;
- Foreign Security Principals and cross-forest ACLs;
- MSSQL database-link trust paths;
- trust transitivity and SID-filtering concepts;
- PAM / Shadow Security Principals;
- additional advanced domain and cross-forest scenarios.

These are roadmap directions, **not a claim that every listed technique is currently implemented**.

## Milestone roadmap

Engineering milestones and student-learning Parts are deliberately separate concepts.

A milestone describes what is built and validated in the repository. A Part describes what the student learns.

| Milestone | Engineering scope | Status |
| --- | --- | --- |
| 1 | Network segmentation and lifecycle foundation | Complete / v1.0.0 |
| 2 | NORTH workstation + deterministic Windows LPE framework | Complete / v1.1.0 |
| 2.1 | Segmented start/stop lifecycle reliability | Complete / v1.1.1 |
| 3 | Learning-path integration: authenticated enumeration via Linux and Windows around the WS01 foothold | Next |
| 4 | Segmented movement and pivoting curriculum | Planned |
| 5 | Unified ADCS curriculum and expanded certificate-abuse scenarios | Planned |
| 6+ | Advanced domain, persistence, cross-domain and cross-forest expansion | Planned |

Milestone 3 is intentionally focused on the **student journey around the foothold we already built**, rather than immediately adding another large pile of vulnerabilities.

The goal is to make the transition coherent:

```text
Reconnaissance
    -> unauthenticated enumeration
    -> first valid NORTH identity
    -> authenticated enumeration from Linux
    -> discover / access WS01
    -> authenticated enumeration from Windows
    -> Windows local privilege escalation
    -> Administrator / SYSTEM
    -> continue into the wider GOAD attack surface
```

After that foundation is integrated, later milestones can add more advanced technique families without losing the learning structure.

## Git is the source of truth

Project code is changed in Git **before** it is considered validated on a lab machine.

The required direction is:

```text
Git change -> commit -> push -> test checkout sync -> source gate -> test
```

A locally repaired test checkout is never considered the validated implementation until that repair exists in Git, has been pushed, pulled back into the test checkout, and revalidated.

Before milestone/reproducibility testing:

```bash
bash scripts/verify-test-source.sh
```

For an exact candidate commit:

```bash
bash scripts/verify-test-source.sh <commit-sha>
```

See [`docs/DEVELOPMENT_WORKFLOW.md`](./docs/DEVELOPMENT_WORKFLOW.md) for the full policy.

## Validation

Complete clean-install source validation:

```bash
bash scripts/validate-goad-kingdoms-install-source.sh
```

Source-only segmentation preflight:

```bash
bash scripts/validate-network-segmentation-source.sh
```

WS01 source-contract validation:

```bash
bash scripts/validate-ws01-source.sh
```

Install or refresh the clean WS01 foundation in an existing GOAD/VMware instance:

```bash
./goad.sh -t ws01 -i <instance-id>
```

Focused WS01 runtime validation:

```bash
export GOAD_PROVIDER_DIR="$HOME/Documents/GOAD_NOMAD/workspace/<instance>/provider"
bash scripts/validate-ws01-runtime.sh
```

Complete runtime validation against a deployed provider:

```bash
export GOAD_PROVIDER_DIR="$HOME/Documents/GOAD_NOMAD/workspace/<instance>/provider"
bash scripts/validate-goad-kingdoms-clean-install-runtime.sh
```

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
- [Mayfly GOAD walkthrough](https://mayfly277.github.io/categories/goad/)

## Safety

> [!CAUTION]
> GOAD Kingdoms is an intentionally vulnerable offensive-security training environment. Do not deploy it directly to the Internet or reuse its vulnerable configuration as a production Active Directory design. Run it only in an isolated lab environment you control and are authorized to test.

## License and attribution

GOAD Kingdoms remains licensed under the **GNU General Public License v3.0**, consistent with the upstream GOAD project. See [`LICENSE`](./LICENSE).

This repository contains substantial modifications to the upstream project. GOAD and the original lab design are credited to **Orange Cyberdefense and the GOAD contributors**; GOAD Kingdoms identifies the additional segmented range, lifecycle, workstation, Windows LPE curriculum, pivoting model and future advanced-training extensions developed in this fork.
