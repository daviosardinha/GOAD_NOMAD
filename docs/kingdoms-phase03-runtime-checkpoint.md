# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch: `kingdoms/phase03-overlay`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This file records runtime evidence only. Raw credentials, hashes, tickets and other secret-bearing material stay outside Git.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` completed with **58 PASS / 0 WARN / 0 FAIL** from a neutral operator state.

## Runtime techniques proven

- LLMNR/NBT-NS/mDNS poisoning behavior in NORTH.
- NetNTLMv2 capture for the built-in Robb Stark and Eddard Stark traffic generators.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative SMB relay impact on CASTELBLACK, including SAM extraction.
- CASTELBLACK MSSQL `xp_dirtree` outbound authentication as `NORTH\sql_svc`.
- PrinterBug/MS-RPRN callback behavior in NORTH.
- MS-EFSR/PetitPotam-family callback proof on CASTELBLACK.
- Rickon Stark permanent headless RDP victim session on WS01 with credential and certificate-pin protections.

## mitm6 / WPAD status

The deterministic WS01 mitm6/WPAD chain is **PROVEN**.

Same-capture acceptance sequence:

1. WS01 DHCPv6 Solicit.
2. Attacker Advertise.
3. WS01 Request.
4. Attacker Reply.
5. WS01 uses attacker IPv6 DNS `fe80::250:56ff:fec0:a`.
6. WS01 queries WPAD over that IPv6 path.
7. WS01 automatically requests `GET /wpad.dat`.

`scripts/phase03/validate-wpad-chain.sh` completed with **PASS: 8 / FAIL: 0**.

## LDAP / LDAPS relay status

The NORTH HTTP/WPAD -> LDAPS relay path is **PROVEN**.

- WINTERFELL is reachable on TCP/389 and TCP/636.
- The mutation-disabled HTTP/WPAD relay authenticated successfully to `ldaps://10.4.10.11`.
- A relayed WS01 machine-account authentication was observed as `NORTH\WS01$`.
- Read-only privilege enumeration started successfully.
- The MSSQL `sql_svc` SMB-origin relay to LDAP/LDAPS is intentionally not used as the NORTH base path because the observed SMB client requested signing.

## RBCD staged proof

Preflight established:

- Target: `WS01$`.
- `msDS-AllowedToActOnBehalfOfOtherIdentity` initially absent.
- `ms-DS-MachineAccountQuota = 10`.
- `PHASE03RBCD$` initially absent.
- WS01 SELF has `WriteProperty` on the exact RBCD attribute GUID.

Rollback baseline is stored locally in mode-0600 file `~/.config/kingdoms/phase03-rbcd-baseline.json`.

Stage 1 is **PROVEN**:

- `PHASE03RBCD$` was created.
- Candidate SID observed as `S-1-5-21-3668019051-2784807040-3421729346-1124`.
- WS01 RBCD remained empty immediately after Stage 1.
- The first successful Stage-1 relay in that run was `NORTH\RICKON.STARK`; a later `NORTH\WS01$` relay succeeded but ntlmrelayx correctly refused to create a second computer.

Stage 2 is **PROVEN**:

- A deterministic LocalSystem HTTP callback from WS01 authenticated as `NORTH\WS01$`.
- ntlmrelayx reported `Delegation rights modified successfully!`.
- ntlmrelayx reported `PHASE03RBCD$ can now impersonate users on WS01$ via S4U2Proxy`.
- Read-only descriptor verification passed: the RBCD value is present on WS01 and its DACL contains exactly the `PHASE03RBCD# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch: `kingdoms/phase03-overlay`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This file records runtime evidence only. Raw credentials, hashes, tickets and other secret-bearing material stay outside Git.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` completed with **58 PASS / 0 WARN / 0 FAIL** from a neutral operator state.

## Runtime techniques proven

- LLMNR/NBT-NS/mDNS poisoning behavior in NORTH.
- NetNTLMv2 capture for the built-in Robb Stark and Eddard Stark traffic generators.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative SMB relay impact on CASTELBLACK, including SAM extraction.
- CASTELBLACK MSSQL `xp_dirtree` outbound authentication as `NORTH\sql_svc`.
- PrinterBug/MS-RPRN callback behavior in NORTH.
- MS-EFSR/PetitPotam-family callback proof on CASTELBLACK.
- Rickon Stark permanent headless RDP victim session on WS01 with credential and certificate-pin protections.

## mitm6 / WPAD status

The deterministic WS01 mitm6/WPAD chain is **PROVEN**.

Same-capture acceptance sequence:

1. WS01 DHCPv6 Solicit.
2. Attacker Advertise.
3. WS01 Request.
4. Attacker Reply.
5. WS01 uses attacker IPv6 DNS `fe80::250:56ff:fec0:a`.
6. WS01 queries WPAD over that IPv6 path.
7. WS01 automatically requests `GET /wpad.dat`.

`scripts/phase03/validate-wpad-chain.sh` completed with **PASS: 8 / FAIL: 0**.

## LDAP / LDAPS relay status

The NORTH HTTP/WPAD -> LDAPS relay path is **PROVEN**.

- WINTERFELL is reachable on TCP/389 and TCP/636.
- The mutation-disabled HTTP/WPAD relay authenticated successfully to `ldaps://10.4.10.11`.
- A relayed WS01 machine-account authentication was observed as `NORTH\WS01$`.
- Read-only privilege enumeration started successfully.
- The MSSQL `sql_svc` SMB-origin relay to LDAP/LDAPS is intentionally not used as the NORTH base path because the observed SMB client requested signing.

## RBCD staged proof

Preflight established:

- Target: `WS01$`.
- `msDS-AllowedToActOnBehalfOfOtherIdentity` initially absent.
- `ms-DS-MachineAccountQuota = 10`.
- `PHASE03RBCD$` initially absent.
- WS01 SELF has `WriteProperty` on the exact RBCD attribute GUID.

Rollback baseline is stored locally in mode-0600 file `~/.config/kingdoms/phase03-rbcd-baseline.json`.

Stage 1 is **PROVEN**:

- `PHASE03RBCD$` was created.
- Candidate SID observed as `S-1-5-21-3668019051-2784807040-3421729346-1124`.
- WS01 RBCD remained empty immediately after Stage 1.
- The first successful Stage-1 relay in that run was `NORTH\RICKON.STARK`; a later `NORTH\WS01$` relay succeeded but ntlmrelayx correctly refused to create a second computer.

Stage 2 is **PROVEN**:

- A deterministic LocalSystem HTTP callback from WS01 authenticated as `NORTH\WS01$`.
- ntlmrelayx reported `Delegation rights modified successfully!`.
- ntlmrelayx reported `PHASE03RBCD$ can now impersonate users on WS01$ via S4U2Proxy`.
 SID `S-1-5-21-3668019051-2784807040-3421729346-1124`.

## Remaining Phase 03 engineering

- Prove the S4U consequence with the controlled `PHASE03RBCD# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch: `kingdoms/phase03-overlay`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This file records runtime evidence only. Raw credentials, hashes, tickets and other secret-bearing material stay outside Git.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` completed with **58 PASS / 0 WARN / 0 FAIL** from a neutral operator state.

## Runtime techniques proven

- LLMNR/NBT-NS/mDNS poisoning behavior in NORTH.
- NetNTLMv2 capture for the built-in Robb Stark and Eddard Stark traffic generators.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative SMB relay impact on CASTELBLACK, including SAM extraction.
- CASTELBLACK MSSQL `xp_dirtree` outbound authentication as `NORTH\sql_svc`.
- PrinterBug/MS-RPRN callback behavior in NORTH.
- MS-EFSR/PetitPotam-family callback proof on CASTELBLACK.
- Rickon Stark permanent headless RDP victim session on WS01 with credential and certificate-pin protections.

## mitm6 / WPAD status

The deterministic WS01 mitm6/WPAD chain is **PROVEN**.

Same-capture acceptance sequence:

1. WS01 DHCPv6 Solicit.
2. Attacker Advertise.
3. WS01 Request.
4. Attacker Reply.
5. WS01 uses attacker IPv6 DNS `fe80::250:56ff:fec0:a`.
6. WS01 queries WPAD over that IPv6 path.
7. WS01 automatically requests `GET /wpad.dat`.

`scripts/phase03/validate-wpad-chain.sh` completed with **PASS: 8 / FAIL: 0**.

## LDAP / LDAPS relay status

The NORTH HTTP/WPAD -> LDAPS relay path is **PROVEN**.

- WINTERFELL is reachable on TCP/389 and TCP/636.
- The mutation-disabled HTTP/WPAD relay authenticated successfully to `ldaps://10.4.10.11`.
- A relayed WS01 machine-account authentication was observed as `NORTH\WS01$`.
- Read-only privilege enumeration started successfully.
- The MSSQL `sql_svc` SMB-origin relay to LDAP/LDAPS is intentionally not used as the NORTH base path because the observed SMB client requested signing.

## RBCD staged proof

Preflight established:

- Target: `WS01$`.
- `msDS-AllowedToActOnBehalfOfOtherIdentity` initially absent.
- `ms-DS-MachineAccountQuota = 10`.
- `PHASE03RBCD$` initially absent.
- WS01 SELF has `WriteProperty` on the exact RBCD attribute GUID.

Rollback baseline is stored locally in mode-0600 file `~/.config/kingdoms/phase03-rbcd-baseline.json`.

Stage 1 is **PROVEN**:

- `PHASE03RBCD$` was created.
- Candidate SID observed as `S-1-5-21-3668019051-2784807040-3421729346-1124`.
- WS01 RBCD remained empty immediately after Stage 1.
- The first successful Stage-1 relay in that run was `NORTH\RICKON.STARK`; a later `NORTH\WS01$` relay succeeded but ntlmrelayx correctly refused to create a second computer.

Stage 2 is **PROVEN**:

- A deterministic LocalSystem HTTP callback from WS01 authenticated as `NORTH\WS01$`.
- ntlmrelayx reported `Delegation rights modified successfully!`.
- ntlmrelayx reported `PHASE03RBCD$ can now impersonate users on WS01$ via S4U2Proxy`.
- Read-only descriptor verification passed: the RBCD value is present on WS01 and its DACL contains exactly the `PHASE03RBCD# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch: `kingdoms/phase03-overlay`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This file records runtime evidence only. Raw credentials, hashes, tickets and other secret-bearing material stay outside Git.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` completed with **58 PASS / 0 WARN / 0 FAIL** from a neutral operator state.

## Runtime techniques proven

- LLMNR/NBT-NS/mDNS poisoning behavior in NORTH.
- NetNTLMv2 capture for the built-in Robb Stark and Eddard Stark traffic generators.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative SMB relay impact on CASTELBLACK, including SAM extraction.
- CASTELBLACK MSSQL `xp_dirtree` outbound authentication as `NORTH\sql_svc`.
- PrinterBug/MS-RPRN callback behavior in NORTH.
- MS-EFSR/PetitPotam-family callback proof on CASTELBLACK.
- Rickon Stark permanent headless RDP victim session on WS01 with credential and certificate-pin protections.

## mitm6 / WPAD status

The deterministic WS01 mitm6/WPAD chain is **PROVEN**.

Same-capture acceptance sequence:

1. WS01 DHCPv6 Solicit.
2. Attacker Advertise.
3. WS01 Request.
4. Attacker Reply.
5. WS01 uses attacker IPv6 DNS `fe80::250:56ff:fec0:a`.
6. WS01 queries WPAD over that IPv6 path.
7. WS01 automatically requests `GET /wpad.dat`.

`scripts/phase03/validate-wpad-chain.sh` completed with **PASS: 8 / FAIL: 0**.

## LDAP / LDAPS relay status

The NORTH HTTP/WPAD -> LDAPS relay path is **PROVEN**.

- WINTERFELL is reachable on TCP/389 and TCP/636.
- The mutation-disabled HTTP/WPAD relay authenticated successfully to `ldaps://10.4.10.11`.
- A relayed WS01 machine-account authentication was observed as `NORTH\WS01$`.
- Read-only privilege enumeration started successfully.
- The MSSQL `sql_svc` SMB-origin relay to LDAP/LDAPS is intentionally not used as the NORTH base path because the observed SMB client requested signing.

## RBCD staged proof

Preflight established:

- Target: `WS01$`.
- `msDS-AllowedToActOnBehalfOfOtherIdentity` initially absent.
- `ms-DS-MachineAccountQuota = 10`.
- `PHASE03RBCD$` initially absent.
- WS01 SELF has `WriteProperty` on the exact RBCD attribute GUID.

Rollback baseline is stored locally in mode-0600 file `~/.config/kingdoms/phase03-rbcd-baseline.json`.

Stage 1 is **PROVEN**:

- `PHASE03RBCD$` was created.
- Candidate SID observed as `S-1-5-21-3668019051-2784807040-3421729346-1124`.
- WS01 RBCD remained empty immediately after Stage 1.
- The first successful Stage-1 relay in that run was `NORTH\RICKON.STARK`; a later `NORTH\WS01$` relay succeeded but ntlmrelayx correctly refused to create a second computer.

Stage 2 is **PROVEN**:

- A deterministic LocalSystem HTTP callback from WS01 authenticated as `NORTH\WS01$`.
- ntlmrelayx reported `Delegation rights modified successfully!`.
- ntlmrelayx reported `PHASE03RBCD$ can now impersonate users on WS01$ via S4U2Proxy`.
 SID `S-1-5-21-3668019051-2784807040-3421729346-1124`.

## Remaining Phase 03 engineering

 account.
- Restore the exact RBCD baseline and remove the temporary candidate/secret.
- Promote the proven mitm6/WPAD and HTTP->LDAPS flows into permanent apply/prove/reset infrastructure.
- Interactive/SOCKS relay proof.
- LSASS/DPAPI/share/SMB-execution consequences.
- Shadow Credentials controlled fixture.
- ADIDNS scenario.
- WebDAV/.lnk/.url victim-interaction scenario.
- Final regression and Notion teaching sections/screenshots.

## Regression rule

Every Phase 03 state-changing fixture must be independently reversible and must not break Phases 00–02, the NORTH segmentation contract, existing traffic generators, the RDP contract, Phase 02 MSSQL behavior or later WS01 fixtures.
