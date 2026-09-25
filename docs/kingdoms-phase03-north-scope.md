# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

Status: runtime-validated working document
Branch: `kingdoms/phase03-overlay`
Reference lab: `cebee3-goad-vmware`

## Scope

- Attacker: Kali on `vmnet10`, IPv4 `10.4.10.254`.
- WINTERFELL: NORTH DC, `10.4.10.11`, SMB signing required.
- CASTELBLACK: NORTH member, `10.4.10.22`, SMB signing not required, MSSQL as `NORTH\sql_svc`.
- WS01: NORTH workstation, `10.4.10.31`, SMB signing not required, IPv6 enabled.
- Forest-root and ESSOS hosts remain outside the direct Phase 03 route.

## GOAD Part 4 concepts carried into NORTH

1. LLMNR/NBT-NS/mDNS poisoning and NetNTLMv2 capture.
2. SMB relay, interactive/SOCKS reuse, and privilege-dependent post-relay consequences.
3. mitm6/WPAD -> LDAP/LDAPS relay -> RBCD.
4. Authentication coercion with PrinterBug/PetitPotam-family paths.
5. Shadow Credentials as an advanced follow-on.

Historical Drop The MIC/NTLMv1 material remains optional/conditional. NORTH has no current AD CS CA, so ESC8 is outside this Phase 03 scope.

## Current NORTH status

| Technique | Current evidence | Status |
| --- | --- | --- |
| LLMNR/NBT-NS/mDNS | Poisoning and NetNTLMv2 capture observed | PROVEN |
| Robb/Eddard traffic generators | Scheduled SMB-auth traffic observed | PROVEN |
| SMB relay | Eddard relay to CASTELBLACK with administrative impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | Exact WS01 IPv6/DNS baseline captured; DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET reproduced; validator 8/0; exact IPv6/DNS reset verified | PROVEN / PERMANENTIZED |
| HTTP/WPAD -> LDAPS | Durable detached HTTP relay accepted deterministic LocalSystem auth as `NORTH\\WS01$`, relayed successfully to WINTERFELL LDAPS, performed read-only privilege enumeration, then stopped cleanly with callback task absent | PROVEN / PERMANENTIZED |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write the exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD remained empty | PROVEN |
| RBCD Stage 2 | `WS01$` relay wrote delegation for `PHASE03RBCD$`; descriptor verifier confirmed its SID | PROVEN |
| RBCD S4U consequence | `PHASE03RBCD$` completed S4U2Self/S4U2Proxy as Administrator and listed WS01 `C$` with a CIFS ticket | PROVEN |
| RBCD rollback | WS01 RBCD returned to baseline; `PHASE03RBCD$`, password and temporary ticket caches removed | PROVEN |
| PrinterBug | Callback behavior observed | PROVEN |
| PetitPotam/MS-EFSR | Callback proven on CASTELBLACK | PROVEN ON CASTELBLACK |
| Interactive SMB relay | Robb and Eddard relayed to CASTELBLACK; retained local SMB shells created; Robb could enumerate shares but C$ access was denied, while Eddard opened and listed C$ | PROVEN |
| SOCKS relay | Robb and Eddard sessions retained behind SOCKS5 on 127.0.0.1:1080 and reused with credential-less SMB clients; Robb C$ denied, Eddard C$ listed | PROVEN |
| SMB share authorization consequence | Robb could enumerate shares but C$ was denied; Eddard opened and listed C$ | PROVEN |
| SMB remote execution consequence | Eddard relay executed `whoami & hostname` as `NT AUTHORITY\SYSTEM` on CASTELBLACK; Robb relay authenticated but execution failed with DCERPC access denied | PROVEN |
| LSASS credential-material consequence | Eddard administrative relay created an 89,796,074-byte CASTELBLACK LSASS MiniDump; Eddard SOCKS reuse retrieved it; pypykatz parsed it successfully with 27 sanitized usernames; remote and local secret-bearing artifacts were removed | PROVEN |
| DPAPI credential-material consequence | Native SYSTEM Credential Manager artifact acquired and decrypted offline through the retained administrative SMB session; local secret-bearing evidence removed | PROVEN |
| Shadow Credentials | `WS01$` relayed over HTTP to WINTERFELL LDAPS; one KeyCredential injected and independently verified; Certipy obtained a TGT from the generated certificate; exact baseline restored to zero values and cryptographic ephemera removed | PROVEN |
| ADIDNS | Authenticated User `hodor` created `phase03-adidns` by Kerberos-secured dynamic update; DNS resolved to `10.4.10.254`; backing `dnsNode` was owned by Hodor; exact absent baseline restored including tombstone cleanup | PROVEN |
| WebDAV/.lnk | Rickon launched a controlled hostname-backed WebDAV shortcut; WebClient/MRxDAV produced an HTTP OPTIONS request from WS01 to Kali; exact shortcut/service and temporary ADIDNS support state were restored | PROVEN |

## Engineering rules

- Keep attack families independently apply/prove/reset-able.
- Scope poisoning to `vmnet10` and named NORTH targets.
- Do not run conflicting listener profiles simultaneously.
- Preserve exact pre-attack AD state before any mutation.
- Do not reset/destroy the reference lab to clear an exercise.
- Raw secret-bearing runtime evidence stays outside Git.
- Student screenshots must come from NORTH runtime proof, not historical ESSOS captures.

## Next acceptance gate

1. Keep the neutral runtime established after HTTP -> LDAPS acceptance cleanup.
2. Treat mitm6/WPAD and HTTP -> LDAPS permanentization as closed.
3. Run the final Phase 03 regression suite.
4. Run Phase 00–02, NORTH segmentation, RDP contract, MSSQL and traffic-generator regressions.
5. Verify no residual AD mutations, temporary callback tasks, attack listeners or attack processes remain.
6. Complete final screenshots and GOAD Part 4 parity review.
7. Move into final Notion teaching material and Phase 03 handoff.
8. Keep raw credentials, tickets, private keys and other secret-bearing evidence outside Git.
