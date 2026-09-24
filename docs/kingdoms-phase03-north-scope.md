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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
| RBCD Stage 2 | `WS01# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
 relay wrote delegation for `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
; descriptor verifier confirmed its SID in WS01 RBCD | PROVEN |
| RBCD S4U consequence | `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
| RBCD Stage 2 | `WS01# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
 relay wrote delegation for `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
; descriptor verifier confirmed its SID in WS01 RBCD | PROVEN |
 completed S4U2Self/S4U2Proxy as Administrator and listed WS01 `C# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
| RBCD Stage 2 | `WS01# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
 relay wrote delegation for `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
; descriptor verifier confirmed its SID in WS01 RBCD | PROVEN |
 with a CIFS ticket | PROVEN |
| PrinterBug | Callback behavior observed | PROVEN |
| PetitPotam/MS-EFSR | Callback proven on CASTELBLACK | PROVEN ON CASTELBLACK |
| Interactive/SOCKS relay | Not yet runtime-proven in NORTH | GAP |
| LSASS/DPAPI/shares/execution consequences | Not yet runtime-proven | GAP |
| Shadow Credentials | Not yet configured/proven | GAP |
| ADIDNS | Generic capability exists, no Phase 03 fixture yet | GAP |
| WebDAV/.lnk/.url | No dedicated WS01 Phase 03 victim flow yet | GAP |

## Engineering rules

- Keep attack families independently apply/prove/reset-able.
- Scope poisoning to `vmnet10` and named NORTH targets.
- Do not run conflicting listener profiles simultaneously.
- Preserve exact pre-attack AD state before any mutation.
- Do not reset/destroy the reference lab to clear an exercise.
- Raw secret-bearing runtime evidence stays outside Git.
- Student screenshots must come from NORTH runtime proof, not historical ESSOS captures.

## Next acceptance gate

1. Restore the captured RBCD baseline and confirm `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
| RBCD Stage 2 | `WS01# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
 relay wrote delegation for `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
; descriptor verifier confirmed its SID in WS01 RBCD | PROVEN |
| RBCD S4U consequence | `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
| RBCD Stage 2 | `WS01# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
 relay wrote delegation for `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
; descriptor verifier confirmed its SID in WS01 RBCD | PROVEN |
 completed S4U2Self/S4U2Proxy as Administrator and listed WS01 `C# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
| RBCD Stage 2 | `WS01# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
 relay wrote delegation for `PHASE03RBCD# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity

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
| SMB relay | Eddard relay to CASTELBLACK with admin impact and SAM extraction | PROVEN |
| MSSQL callback | `xp_dirtree` produced outbound `NORTH\sql_svc` SMB auth | PROVEN |
| mitm6/WPAD | DHCPv6 takeover, attacker DNS, WPAD DNS and automatic PAC GET; validator 8/0 | PROVEN |
| HTTP/WPAD -> LDAPS | `NORTH\WS01$` relayed successfully to WINTERFELL LDAPS | PROVEN |
| SMB -> LDAP/LDAPS | `sql_svc` path rejected because SMB client requested signing | NOT BASE PATH |
| MachineAccountQuota | NORTH value observed as 10 | PROVEN |
| RBCD prerequisite | WS01 SELF can write exact RBCD attribute | PROVEN |
| RBCD Stage 1 | `PHASE03RBCD$` created; WS01 RBCD still empty | PROVEN |
; descriptor verifier confirmed its SID in WS01 RBCD | PROVEN |
 with a CIFS ticket | PROVEN |
| PrinterBug | Callback behavior observed | PROVEN |
| PetitPotam/MS-EFSR | Callback proven on CASTELBLACK | PROVEN ON CASTELBLACK |
| Interactive/SOCKS relay | Not yet runtime-proven in NORTH | GAP |
| LSASS/DPAPI/shares/execution consequences | Not yet runtime-proven | GAP |
| Shadow Credentials | Not yet configured/proven | GAP |
| ADIDNS | Generic capability exists, no Phase 03 fixture yet | GAP |
| WebDAV/.lnk/.url | No dedicated WS01 Phase 03 victim flow yet | GAP |

## Engineering rules

- Keep attack families independently apply/prove/reset-able.
- Scope poisoning to `vmnet10` and named NORTH targets.
- Do not run conflicting listener profiles simultaneously.
- Preserve exact pre-attack AD state before any mutation.
- Do not reset/destroy the reference lab to clear an exercise.
- Raw secret-bearing runtime evidence stays outside Git.
- Student screenshots must come from NORTH runtime proof, not historical ESSOS captures.

## Next acceptance gate

 is removed.
2. Confirm the local RBCD password and temporary Kerberos caches are gone.
3. Continue to the remaining relay/post-relay families.
