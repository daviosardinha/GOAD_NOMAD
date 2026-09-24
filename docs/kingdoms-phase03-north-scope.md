# Kingdoms — Phase 03 NORTH scope and GOAD Part 4 parity audit

Status: SOURCE/READ-ONLY AUDIT; no vulnerability overlay applied by this document.
Reference: [GOAD Part 4 — Network Poisoning and NTLM Relaying](https://app.notion.com/p/30c79e9ad7c980beac23e1bb440a74e9)
Course: [03 — Poison the Wells](https://app.notion.com/p/3d679e9ad7c981eb80dbd1ea9dc69b81)
Repo basis: \`kingdoms/phase03-overlay\`, created from validated Phase 03 readiness baseline \`893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3\`.
Known-good live reference: \`cebee3-goad-vmware\` (do **not** reset/destroy). Old \`6ebce2-goad-vmware\` stays powered off when cebee3 runs.

## Decision

Consolidate GOAD Part 4 and useful Kingdoms additions into **one NORTH-specific, idempotent Phase 03 overlay** with independent proof/cleanup tasks, instead of progressively changing unrelated lab components. "One-shot" means deploy all supported prerequisites together; it does **not** mean run conflicting poisoners simultaneously or claim every exploit works before technique-specific proof.

- Attacker: Kali on vmnet10 (10.4.10.254); attacker IPv6 link-local also available on vmnet10.
- WINTERFELL: NORTH DC, 10.4.10.11; SMB signing **required**.
- CASTELBLACK: NORTH member, 10.4.10.22; SMB signing **not required**, MSSQL runs as NORTH sql_svc, IIS and shares exist.
- WS01: NORTH workstation, 10.4.10.31; SMB signing **not required**, IPv6 enabled.
- KINGSLANDING (forest root vmnet20), MEEREEN/BRAAVOS (ESSOS vmnet30) remain outside the student-side direct Phase 03 route. Do not silently open the router to teach Phase 03.

## What GOAD Part 4 actually contains

1. LLMNR/NBT-NS poisoning; Robb/Eddard scheduled UNC misses; Responder captures NetNTLMv2; crack Robb using Hashcat 5600.
2. SMB-signing discovery and ntlmrelayx: automated relay, interactive SMB relay, SOCKS reuse; then privilege-dependent SAM, LSASS, DPAPI, shares and SMB-pipe execution with smbexec/atexec.
3. IPv6 DNS takeover (mitm6) with WPAD, relay to LDAP/LDAPS, read-only directory extraction and RBCD (computer-account creation + delegation write).
4. Authentication coercion (PrinterBug/PetitPotam family) with a historical Drop The MIC path.
5. Shadow Credentials / msDS-KeyCredentialLink and PKINIT consequences.

Documented GOAD examples for IPv6/RBCD, Drop The MIC and Shadow Credentials use **ESSOS** (MEEREEN/BRAAVOS), not NORTH. The GOAD repository enables AD CS on KINGSLANDING and BRAAVOS; it does not currently provision an AD CS CA in NORTH. No requirement to involve another domain for the core poisoning/relay/RBCD concepts, but North-only AD CS/ESC8 would require **new CA infrastructure** and a separate release decision.

## Current NORTH source + runtime inventory

Legend: PROVEN = observed on cebee3 or supplied preflight; SOURCE = provisioned in tracked config, but exploit outcome not yet proved; GAP = needs Phase 03 overlay/tooling; CONDITIONAL = operating-system/rights dependent.

| Technique / prerequisite | NORTH source or runtime evidence | Status |
| --- | --- | --- |
| LLMNR + NBT-NS | \`ad/GOAD/data/config.json\` sets WINTERFELL vulns; live Responder poisoned both BRAVOS and MEREN | PROVEN |
| mDNS | Live Responder log shows poisoned requests; not an independent permanent victim vulnerability | PROVEN on test |
| Robb + Eddard SMB authentication | \`ad/GOAD/scripts/responder.ps1\` 2-min Robb; \`ntlm_relay.ps1\` 5-min Eddard; NetNTLMv2 captured | PROVEN |
| SMB relay | WINTERFELL signing True; CASTELBLACK and WS01 False. Eddard authentication was relayed to CASTELBLACK with administrative impact and SAM extraction | PROVEN on CASTELBLACK |
| MSSQL UNC trigger | CASTELBLACK sql_svc, Jon sysadmin, and xp_dirtree were validated; outbound SMB authentication was observed as NORTH\\sql_svc | PROVEN callback |
| LDAP/LDAPS target | WINTERFELL signing/CBT externally observed not enforced and 389/636 reachable. Controlled HTTP/WPAD relay from WS01 succeeded to LDAPS as `NORTH\WS01# Kingdoms — Phase 03 NORTH scope and GOAD Part 4 parity audit

Status: SOURCE/READ-ONLY AUDIT; no vulnerability overlay applied by this document.
Reference: [GOAD Part 4 — Network Poisoning and NTLM Relaying](https://app.notion.com/p/30c79e9ad7c980beac23e1bb440a74e9)
Course: [03 — Poison the Wells](https://app.notion.com/p/3d679e9ad7c981eb80dbd1ea9dc69b81)
Repo basis: \`kingdoms/phase03-overlay\`, created from validated Phase 03 readiness baseline \`893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3\`.
Known-good live reference: \`cebee3-goad-vmware\` (do **not** reset/destroy). Old \`6ebce2-goad-vmware\` stays powered off when cebee3 runs.

## Decision

Consolidate GOAD Part 4 and useful Kingdoms additions into **one NORTH-specific, idempotent Phase 03 overlay** with independent proof/cleanup tasks, instead of progressively changing unrelated lab components. "One-shot" means deploy all supported prerequisites together; it does **not** mean run conflicting poisoners simultaneously or claim every exploit works before technique-specific proof.

- Attacker: Kali on vmnet10 (10.4.10.254); attacker IPv6 link-local also available on vmnet10.
- WINTERFELL: NORTH DC, 10.4.10.11; SMB signing **required**.
- CASTELBLACK: NORTH member, 10.4.10.22; SMB signing **not required**, MSSQL runs as NORTH sql_svc, IIS and shares exist.
- WS01: NORTH workstation, 10.4.10.31; SMB signing **not required**, IPv6 enabled.
- KINGSLANDING (forest root vmnet20), MEEREEN/BRAAVOS (ESSOS vmnet30) remain outside the student-side direct Phase 03 route. Do not silently open the router to teach Phase 03.

## What GOAD Part 4 actually contains

1. LLMNR/NBT-NS poisoning; Robb/Eddard scheduled UNC misses; Responder captures NetNTLMv2; crack Robb using Hashcat 5600.
2. SMB-signing discovery and ntlmrelayx: automated relay, interactive SMB relay, SOCKS reuse; then privilege-dependent SAM, LSASS, DPAPI, shares and SMB-pipe execution with smbexec/atexec.
3. IPv6 DNS takeover (mitm6) with WPAD, relay to LDAP/LDAPS, read-only directory extraction and RBCD (computer-account creation + delegation write).
4. Authentication coercion (PrinterBug/PetitPotam family) with a historical Drop The MIC path.
5. Shadow Credentials / msDS-KeyCredentialLink and PKINIT consequences.

Documented GOAD examples for IPv6/RBCD, Drop The MIC and Shadow Credentials use **ESSOS** (MEEREEN/BRAAVOS), not NORTH. The GOAD repository enables AD CS on KINGSLANDING and BRAAVOS; it does not currently provision an AD CS CA in NORTH. No requirement to involve another domain for the core poisoning/relay/RBCD concepts, but North-only AD CS/ESC8 would require **new CA infrastructure** and a separate release decision.

## Current NORTH source + runtime inventory

Legend: PROVEN = observed on cebee3 or supplied preflight; SOURCE = provisioned in tracked config, but exploit outcome not yet proved; GAP = needs Phase 03 overlay/tooling; CONDITIONAL = operating-system/rights dependent.

| Technique / prerequisite | NORTH source or runtime evidence | Status |
| --- | --- | --- |
| LLMNR + NBT-NS | \`ad/GOAD/data/config.json\` sets WINTERFELL vulns; live Responder poisoned both BRAVOS and MEREN | PROVEN |
| mDNS | Live Responder log shows poisoned requests; not an independent permanent victim vulnerability | PROVEN on test |
| Robb + Eddard SMB authentication | \`ad/GOAD/scripts/responder.ps1\` 2-min Robb; \`ntlm_relay.ps1\` 5-min Eddard; NetNTLMv2 captured | PROVEN |
| SMB relay | WINTERFELL signing True; CASTELBLACK and WS01 False. Eddard authentication was relayed to CASTELBLACK with administrative impact and SAM extraction | PROVEN on CASTELBLACK |
| MSSQL UNC trigger | CASTELBLACK sql_svc, Jon sysadmin, and xp_dirtree were validated; outbound SMB authentication was observed as NORTH\\sql_svc | PROVEN callback |
; read-only privilege enumeration started successfully. Source config still does not explicitly pin the effective training posture | PROVEN relay path; source gap |
| MAQ | Phase03 readiness reports NORTH MachineAccountQuota = 10 | PROVEN prerequisite |
| PrinterBug | WINTERFELL Spooler is running; Phase 03 runtime testing produced PrinterBug/MS-RPRN callbacks in NORTH | PROVEN callback family; preserve fresh per-host evidence |
| Other RPC (PetitPotam/DFSCoerce/Coercer) | MS-EFSR/PetitPotam-family callback was proven on CASTELBLACK. Do not claim WINTERFELL/WS01 until each has fresh host-specific evidence | PARTIALLY PROVEN |
| WebDAV client | Existing \`[webdav]\` inventory targets CASTELBLACK/BRAAVOS Server WebDAV-Redirector; **not WS01** | GAP for WS01 HTTP/WebDAV lesson |
| mitm6 / WPAD | Same-capture proof now shows WS01 DHCPv6 Solicit/Advertise/Request/Reply, attacker IPv6 DNS `fe80::250:56ff:fec0:a`, WPAD DNS over that IPv6 path, and automatic `GET /wpad.dat` from 10.4.10.31 with HTTP 200 | PROVEN |
| ADIDNS | Generic \`add_dns_record\` Ansible role exists, but no Phase03 vulnerable scoped record/ACL in NORTH | GAP |
| Writable-share trigger | CASTELBLACK has \`openshares\` and existing file deployment; no dedicated .lnk/.url + victim interaction contract | GAP |
| LDAP relay → RBCD | HTTP/WPAD -> LDAPS transport is proven as `NORTH\WS01# Kingdoms — Phase 03 NORTH scope and GOAD Part 4 parity audit

Status: SOURCE/READ-ONLY AUDIT; no vulnerability overlay applied by this document.
Reference: [GOAD Part 4 — Network Poisoning and NTLM Relaying](https://app.notion.com/p/30c79e9ad7c980beac23e1bb440a74e9)
Course: [03 — Poison the Wells](https://app.notion.com/p/3d679e9ad7c981eb80dbd1ea9dc69b81)
Repo basis: \`kingdoms/phase03-overlay\`, created from validated Phase 03 readiness baseline \`893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3\`.
Known-good live reference: \`cebee3-goad-vmware\` (do **not** reset/destroy). Old \`6ebce2-goad-vmware\` stays powered off when cebee3 runs.

## Decision

Consolidate GOAD Part 4 and useful Kingdoms additions into **one NORTH-specific, idempotent Phase 03 overlay** with independent proof/cleanup tasks, instead of progressively changing unrelated lab components. "One-shot" means deploy all supported prerequisites together; it does **not** mean run conflicting poisoners simultaneously or claim every exploit works before technique-specific proof.

- Attacker: Kali on vmnet10 (10.4.10.254); attacker IPv6 link-local also available on vmnet10.
- WINTERFELL: NORTH DC, 10.4.10.11; SMB signing **required**.
- CASTELBLACK: NORTH member, 10.4.10.22; SMB signing **not required**, MSSQL runs as NORTH sql_svc, IIS and shares exist.
- WS01: NORTH workstation, 10.4.10.31; SMB signing **not required**, IPv6 enabled.
- KINGSLANDING (forest root vmnet20), MEEREEN/BRAAVOS (ESSOS vmnet30) remain outside the student-side direct Phase 03 route. Do not silently open the router to teach Phase 03.

## What GOAD Part 4 actually contains

1. LLMNR/NBT-NS poisoning; Robb/Eddard scheduled UNC misses; Responder captures NetNTLMv2; crack Robb using Hashcat 5600.
2. SMB-signing discovery and ntlmrelayx: automated relay, interactive SMB relay, SOCKS reuse; then privilege-dependent SAM, LSASS, DPAPI, shares and SMB-pipe execution with smbexec/atexec.
3. IPv6 DNS takeover (mitm6) with WPAD, relay to LDAP/LDAPS, read-only directory extraction and RBCD (computer-account creation + delegation write).
4. Authentication coercion (PrinterBug/PetitPotam family) with a historical Drop The MIC path.
5. Shadow Credentials / msDS-KeyCredentialLink and PKINIT consequences.

Documented GOAD examples for IPv6/RBCD, Drop The MIC and Shadow Credentials use **ESSOS** (MEEREEN/BRAAVOS), not NORTH. The GOAD repository enables AD CS on KINGSLANDING and BRAAVOS; it does not currently provision an AD CS CA in NORTH. No requirement to involve another domain for the core poisoning/relay/RBCD concepts, but North-only AD CS/ESC8 would require **new CA infrastructure** and a separate release decision.

## Current NORTH source + runtime inventory

Legend: PROVEN = observed on cebee3 or supplied preflight; SOURCE = provisioned in tracked config, but exploit outcome not yet proved; GAP = needs Phase 03 overlay/tooling; CONDITIONAL = operating-system/rights dependent.

| Technique / prerequisite | NORTH source or runtime evidence | Status |
| --- | --- | --- |
| LLMNR + NBT-NS | \`ad/GOAD/data/config.json\` sets WINTERFELL vulns; live Responder poisoned both BRAVOS and MEREN | PROVEN |
| mDNS | Live Responder log shows poisoned requests; not an independent permanent victim vulnerability | PROVEN on test |
| Robb + Eddard SMB authentication | \`ad/GOAD/scripts/responder.ps1\` 2-min Robb; \`ntlm_relay.ps1\` 5-min Eddard; NetNTLMv2 captured | PROVEN |
| SMB relay | WINTERFELL signing True; CASTELBLACK and WS01 False. Eddard authentication was relayed to CASTELBLACK with administrative impact and SAM extraction | PROVEN on CASTELBLACK |
| MSSQL UNC trigger | CASTELBLACK sql_svc, Jon sysadmin, and xp_dirtree were validated; outbound SMB authentication was observed as NORTH\\sql_svc | PROVEN callback |
| LDAP/LDAPS target | WINTERFELL signing/CBT externally observed not enforced and 389/636 reachable. Controlled HTTP/WPAD relay from WS01 succeeded to LDAPS as `NORTH\WS01# Kingdoms — Phase 03 NORTH scope and GOAD Part 4 parity audit

Status: SOURCE/READ-ONLY AUDIT; no vulnerability overlay applied by this document.
Reference: [GOAD Part 4 — Network Poisoning and NTLM Relaying](https://app.notion.com/p/30c79e9ad7c980beac23e1bb440a74e9)
Course: [03 — Poison the Wells](https://app.notion.com/p/3d679e9ad7c981eb80dbd1ea9dc69b81)
Repo basis: \`kingdoms/phase03-overlay\`, created from validated Phase 03 readiness baseline \`893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3\`.
Known-good live reference: \`cebee3-goad-vmware\` (do **not** reset/destroy). Old \`6ebce2-goad-vmware\` stays powered off when cebee3 runs.

## Decision

Consolidate GOAD Part 4 and useful Kingdoms additions into **one NORTH-specific, idempotent Phase 03 overlay** with independent proof/cleanup tasks, instead of progressively changing unrelated lab components. "One-shot" means deploy all supported prerequisites together; it does **not** mean run conflicting poisoners simultaneously or claim every exploit works before technique-specific proof.

- Attacker: Kali on vmnet10 (10.4.10.254); attacker IPv6 link-local also available on vmnet10.
- WINTERFELL: NORTH DC, 10.4.10.11; SMB signing **required**.
- CASTELBLACK: NORTH member, 10.4.10.22; SMB signing **not required**, MSSQL runs as NORTH sql_svc, IIS and shares exist.
- WS01: NORTH workstation, 10.4.10.31; SMB signing **not required**, IPv6 enabled.
- KINGSLANDING (forest root vmnet20), MEEREEN/BRAAVOS (ESSOS vmnet30) remain outside the student-side direct Phase 03 route. Do not silently open the router to teach Phase 03.

## What GOAD Part 4 actually contains

1. LLMNR/NBT-NS poisoning; Robb/Eddard scheduled UNC misses; Responder captures NetNTLMv2; crack Robb using Hashcat 5600.
2. SMB-signing discovery and ntlmrelayx: automated relay, interactive SMB relay, SOCKS reuse; then privilege-dependent SAM, LSASS, DPAPI, shares and SMB-pipe execution with smbexec/atexec.
3. IPv6 DNS takeover (mitm6) with WPAD, relay to LDAP/LDAPS, read-only directory extraction and RBCD (computer-account creation + delegation write).
4. Authentication coercion (PrinterBug/PetitPotam family) with a historical Drop The MIC path.
5. Shadow Credentials / msDS-KeyCredentialLink and PKINIT consequences.

Documented GOAD examples for IPv6/RBCD, Drop The MIC and Shadow Credentials use **ESSOS** (MEEREEN/BRAAVOS), not NORTH. The GOAD repository enables AD CS on KINGSLANDING and BRAAVOS; it does not currently provision an AD CS CA in NORTH. No requirement to involve another domain for the core poisoning/relay/RBCD concepts, but North-only AD CS/ESC8 would require **new CA infrastructure** and a separate release decision.

## Current NORTH source + runtime inventory

Legend: PROVEN = observed on cebee3 or supplied preflight; SOURCE = provisioned in tracked config, but exploit outcome not yet proved; GAP = needs Phase 03 overlay/tooling; CONDITIONAL = operating-system/rights dependent.

| Technique / prerequisite | NORTH source or runtime evidence | Status |
| --- | --- | --- |
| LLMNR + NBT-NS | \`ad/GOAD/data/config.json\` sets WINTERFELL vulns; live Responder poisoned both BRAVOS and MEREN | PROVEN |
| mDNS | Live Responder log shows poisoned requests; not an independent permanent victim vulnerability | PROVEN on test |
| Robb + Eddard SMB authentication | \`ad/GOAD/scripts/responder.ps1\` 2-min Robb; \`ntlm_relay.ps1\` 5-min Eddard; NetNTLMv2 captured | PROVEN |
| SMB relay | WINTERFELL signing True; CASTELBLACK and WS01 False. Eddard authentication was relayed to CASTELBLACK with administrative impact and SAM extraction | PROVEN on CASTELBLACK |
| MSSQL UNC trigger | CASTELBLACK sql_svc, Jon sysadmin, and xp_dirtree were validated; outbound SMB authentication was observed as NORTH\\sql_svc | PROVEN callback |
; read-only privilege enumeration started successfully. Source config still does not explicitly pin the effective training posture | PROVEN relay path; source gap |
| MAQ | Phase03 readiness reports NORTH MachineAccountQuota = 10 | PROVEN prerequisite |
| PrinterBug | WINTERFELL Spooler is running; Phase 03 runtime testing produced PrinterBug/MS-RPRN callbacks in NORTH | PROVEN callback family; preserve fresh per-host evidence |
| Other RPC (PetitPotam/DFSCoerce/Coercer) | MS-EFSR/PetitPotam-family callback was proven on CASTELBLACK. Do not claim WINTERFELL/WS01 until each has fresh host-specific evidence | PARTIALLY PROVEN |
| WebDAV client | Existing \`[webdav]\` inventory targets CASTELBLACK/BRAAVOS Server WebDAV-Redirector; **not WS01** | GAP for WS01 HTTP/WebDAV lesson |
| mitm6 / WPAD | Same-capture proof now shows WS01 DHCPv6 Solicit/Advertise/Request/Reply, attacker IPv6 DNS `fe80::250:56ff:fec0:a`, WPAD DNS over that IPv6 path, and automatic `GET /wpad.dat` from 10.4.10.31 with HTTP 200 | PROVEN |
| ADIDNS | Generic \`add_dns_record\` Ansible role exists, but no Phase03 vulnerable scoped record/ACL in NORTH | GAP |
| Writable-share trigger | CASTELBLACK has \`openshares\` and existing file deployment; no dedicated .lnk/.url + victim interaction contract | GAP |
; MAQ=10 is known. Rights on the intended RBCD target and reversible mutation are still unproven | GAP for target-rights + reversible RBCD proof |
| LDAP relay → Shadow Credentials | GOAD Part 4 demos ESSOS; no documented NORTH-specific controlled target/ACL and cleanup | GAP, advanced |
| NTLMv1 downgrade | \`ntlmdowngrade\` configured on MEEREEN (ESSOS), **not** NORTH | OUTSIDE NORTH, optional separate fixture |
| Drop The MIC / CVE-2019-1040 | GOAD Part 4 historical ESSOS demo; NTLMv1 configuration alone does not prove vulnerability to this patched CVE | CONDITIONAL historical only |
| AD CS / HTTP ESC8 | \`[adcs]\` lists KINGSLANDING and BRAAVOS, **not NORTH**; GOAD Part 4 discusses HTTP/ADCS but does not establish a NORTH CA | OUTSIDE NORTH; future infrastructure decision |

## Source / course discrepancies to correct before publishing student instructions

- GOAD Part 4 calls Robb a Domain Admin. The tracked NORTH \`domains[north].users[robb.stark].groups\` contains only \`Stark\`; WINTERFELL local Administrators explicitly contains Robb. This is **not equivalent to claiming his AD group is Domain Admins**, even though local admin access to a DC is highly consequential. Eddard **is** in NORTH Domain Admins.
- Old GOAD command examples use \`vmnet2\` or \`eth0\`; this segmented VMware student's NORTH interface is \`vmnet10\` (derive dynamically).
- Old text mentions a 3-min Robb bot; the current tracked script schedules **every 2 minutes**.
- The GOAD Part 4 command \`responder -dwP\` mixes \`-w\` and \`-P\`; lgandx Responder currently rejects simultaneous WPAD and ProxyAuth. Use separate controlled scenarios.
- Kali \`dnsmasq\` listening only on \`127.0.0.1:53\` and \`[::1]:53\` is the current baseline; it did not prevent the proven poison/capture. Do not globally disable Kali DNS as an alleged prerequisite. Use a dedicated Responder profile with DNS disabled in the relay lesson, verify exact listener conflicts (including IPv6), and bind tools to NORTH.
- Old GOAD screenshots are evidence for that original setup, **not proof that the same impact occurred in cebee3**. NetNTLMv2 is a challenge/response capture, not a reusable NT hash/PtH value or cleartext. SMB signing False is necessary for a typical SMB relay outcome but does not itself grant administrative permissions.
- Explicitly distinguish the documented ESSOS examples from NORTH reproductions; do not transplant ESSOS hostnames, addresses, or credentials into the student instructions.

## Proposed ONE-SHOT NORTH overlay (implementation design, not yet applied)

Use dedicated files such as \`ansible/phase03.yml\`, separate Phase03 DC/member/workstation roles, and \`scripts/apply-phase03.sh\`, \`scripts/validate-phase03-runtime.sh\`, \`scripts/reset-phase03.sh\`. Guard \`domain_name=GOAD\`, exact WINTERFELL/CASTELBLACK/WS01 FQDN and expected IPs, exercise mode, and instance identity before changing anything. Preserve the existing \`scripts/validate-phase03-readiness.sh\` as a read-only prerequisite gate.

**WINTERFELL (DC):** Preserve both functioning scheduled bots; explicitly pin/test the *effective* LDAP signing and channel-binding training posture via correct NTDS configuration (do not rely only on a legacy registry path). Verify rather than assume LDAP target rights, machine-account quota and Spooler. Create only narrowly scoped ADIDNS training records/permissions and dedicated test objects for controlled RBCD and (advanced) Shadow Credentials; record original object state so cleanup restores exact prior values. Do not modify domain-wide ACLs broadly.

**CASTELBLACK (member):** Retain existing unsigned SMB, sql_svc MSSQL, IIS and existing shares. Add only dedicated Phase03 exercise subdirectories, controlled .lnk/.url resources, and a limited auth-coercion test path. The sql_svc UNC callback and Eddard→CASTELBLACK administrative SMB relay with SAM extraction are already proven; preserve them as regression tests. LSASS/DPAPI/share consequences remain technique-specific proofs.

**WS01 (workstation):** Preserve Rickon's existing RDP contract and Phase04 LPE fixtures. Configure/test WebClient as a Windows **client** (the Server WebDAV-Redirector role is not a direct Windows10 drop-in), IPv6/DHCPv6 victim behavior, controlled WPAD discovery, and a noninteractive simulated browsing trigger scoped to the new Phase03 share artifacts. Keep all victim triggers enable/disable-able and deterministic.

**Kali/operator profiles:** Capture-only Responder profile, relay poisoning profile (Responder does not own SMB/HTTP or unnecessary DNS listener), ntlmrelayx single-target/target-list/interactive/SOCKS profiles, and a separate mitm6+HTTP→LDAPS profile. Avoid simultaneous port ownership; only one mutually exclusive profile runs for each teaching demo. Scope DHCPv6/DNS poisoning strictly to isolated vmnet10 and intended targets. Do not change host-wide DNS or routing.

**Outside NORTH / later:** Do not change forest root, ESSOS, cross-forest trusts or segmentation for Phase03. Original ESSOS Drop The MIC is historical/conditional and must not be recreated by claiming an NTLMv1 toggle guarantees CVE-2019-1040. A North CA for ESC8 is a substantive architectural addition; leave for a separately approved optional advanced module or dedicated later AD CS phase.

## Acceptance before calling the one-shot overlay complete

1. Source tests check scope, exact host inventory, bots' periodicity, no changes to previous phases, safe Ansible tags/role conditions, and planned apply/prove/reset coverage.
2. Runtime prerequisites pass \`validate-phase03-readiness.sh\` unchanged in purpose. Capture-only proof shows both bots and correct NetNTLMv2 labels without user-provided secrets appearing in evidence.
3. Technique-specific **runtime proof** preserves already-proven Eddard→CASTELBLACK administrative SMB relay + SAM extraction, Robb/Eddard capture behavior, MSSQL sql_svc callback and supported RPC callback(s), then adds the remaining scoped ADIDNS, .lnk/.url victim interaction, WebDAV client scenario and reversible RBCD. LDAP read-only relay is already proven through the HTTP/WPAD path. Deterministic mitm6 steering and automatic WPAD PAC retrieval are already proven in NORTH. Optional Shadow Credentials only after explicit ACL preflight and reset proof.
4. Each state-changing exercise backs up its exact prior AD/filesystem state, changes only named Phase03 objects, and restores them; no blanket deletion of unrelated records, GPOs, credentials or student work. Never reset/destroy cebee3 to clear an exercise.
5. Regression re-runs Phase00–02 source and runtime gates plus Phase03 validation; existing RDP contract, Phase02 MSSQL access, DNS bots, machine secure channels, time convergence, router isolation and WS01 later LPE fixtures must still work.
6. After runtime proof, update Kingdoms Notion Phase03 sections, using **new NORTH screenshots** rather than relabeling historical ESSOS captures as current evidence.

## Current checkpoint

The 2026-09-24 neutral-baseline rerun of \`scripts/validate-phase03-readiness.sh\` completed with **58 PASS / 0 WARN / 0 FAIL** on \`cebee3-goad-vmware\`. Runtime proof details and the safe headless/WPAD diagnostics are preserved in \`docs/kingdoms-phase03-runtime-checkpoint.md\` and \`scripts/phase03/diagnostics/\`. The permanent Phase 03 overlay is still not applied.
