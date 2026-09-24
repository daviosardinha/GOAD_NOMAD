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

## mitm6 / WPAD

The deterministic WS01 mitm6/WPAD chain is **PROVEN**.

Same-capture acceptance sequence:

1. WS01 DHCPv6 Solicit.
2. Attacker Advertise.
3. WS01 Request.
4. Attacker Reply.
5. WS01 uses attacker IPv6 DNS `fe80::250:56ff:fec0:a`.
6. WS01 queries WPAD through that IPv6 path.
7. WS01 automatically requests `GET /wpad.dat`.

`scripts/phase03/validate-wpad-chain.sh` completed with **PASS: 8 / FAIL: 0**.

## LDAP / LDAPS relay

The NORTH HTTP/WPAD -> LDAPS relay path is **PROVEN**.

- WINTERFELL is reachable on TCP/389 and TCP/636.
- Mutation-disabled HTTP/WPAD relay authenticated successfully to `ldaps://10.4.10.11`.
- A WS01 machine-account authentication was relayed as `NORTH\WS01$`.
- Read-only privilege enumeration started successfully.
- The MSSQL `sql_svc` SMB-origin path is not the NORTH LDAP base path because the observed SMB client requested signing.

## RBCD end-to-end proof

Preflight established:

- target `WS01$`;
- RBCD attribute initially absent;
- `ms-DS-MachineAccountQuota = 10`;
- `PHASE03RBCD$` initially absent;
- WS01 SELF has `WriteProperty` on the exact RBCD attribute.

The exact pre-attack baseline is retained locally in mode-0600 `~/.config/kingdoms/phase03-rbcd-baseline.json`.

Stage 1 is **PROVEN**:

- `PHASE03RBCD$` was created;
- candidate SID: `S-1-5-21-3668019051-2784807040-3421729346-1124`;
- WS01 RBCD remained empty immediately afterward.

Stage 2 is **PROVEN**:

- deterministic LocalSystem HTTP callback from WS01 authenticated as `NORTH\WS01$`;
- ntlmrelayx reported delegation modification success;
- read-only verification confirmed the WS01 RBCD DACL contained the `PHASE03RBCD$` SID.

S4U consequence is **PROVEN**:

- `PHASE03RBCD$` obtained a forwardable TGT;
- Impacket completed S4U2Self and S4U2Proxy while impersonating `Administrator`;
- an Administrator CIFS service ticket for `cifs/ws01.north.sevenkingdoms.local` was created;
- Kerberos-authenticated SMB access listed `ADMIN$`, `C$` and `IPC$`;
- `C$` was opened and listed successfully without remote command execution.

Rollback is **PROVEN**:

- WS01 RBCD was restored to the captured baseline;
- `PHASE03RBCD$` was removed because it did not exist in the baseline;
- the local candidate password was removed;
- temporary RBCD Kerberos caches/helper files were removed;
- the mode-0600 baseline file was retained for audit/verification;
- rollback markers returned `RBCD_MATCH=True`, `CANDIDATE_MATCH=True` and `RESET_COMPLETE=True`.

RBCD is therefore closed end-to-end: **preflight -> relay -> mutation -> S4U consequence -> exact rollback**.

## Remaining Phase 03 engineering

- interactive/SOCKS relay proof;
- LSASS/DPAPI/share/SMB-execution consequences;
- Shadow Credentials controlled fixture;
- ADIDNS scenario;
- WebDAV/.lnk/.url victim-interaction scenario;
- promote proven mitm6/WPAD and HTTP->LDAPS flows into permanent apply/prove/reset infrastructure;
- final regression and Notion teaching sections/screenshots.

## Next acceptance gate

The next attack family is **interactive/SOCKS SMB relay** in NORTH. It should reuse the already-proven CASTELBLACK relay surface and must remain independently stoppable/resettable.

## Regression rule

Every Phase 03 state-changing fixture must be independently reversible and must not break Phases 00–02, the NORTH segmentation contract, existing traffic generators, the RDP contract, Phase 02 MSSQL behavior or later WS01 fixtures.
