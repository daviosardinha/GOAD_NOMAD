# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch baseline: `893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This document preserves the Phase 03 runtime work completed before the permanent Phase 03 overlay is implemented.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` passed from a neutral operator state with:

- PASS: 58
- WARN: 0
- FAIL: 0

The gate confirmed the clean Git source state, NORTH segmentation, SMB signing posture, bot prerequisites, IPv6 availability on WS01, LDAP/LDAPS target posture, MSSQL context and local listener availability.

## Runtime techniques already proven

The following were demonstrated in NORTH during Phase 03 validation sessions:

- LLMNR/NBT-NS/mDNS poisoning behavior.
- NetNTLMv2 capture for the built-in NORTH traffic generators, including Robb Stark and Eddard Stark.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative relay impact on CASTELBLACK.
- SAM extraction through the successful relayed SMB context.
- MSSQL `xp_dirtree` outbound-authentication callback from CASTELBLACK as the `NORTH\sql_svc` service identity.
- SMB-origin relay of that `sql_svc` authentication to WINTERFELL LDAP/LDAPS was tested and rejected because the SMB client requested signing; keep this as a documented non-viable base path rather than forcing a downgrade.
- HTTP/WPAD-origin relay from WS01 to WINTERFELL LDAPS succeeded twice in the controlled NORTH test. The relayed identity was the machine account `NORTH\WS01# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch baseline: `893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This document preserves the Phase 03 runtime work completed before the permanent Phase 03 overlay is implemented.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` passed from a neutral operator state with:

- PASS: 58
- WARN: 0
- FAIL: 0

The gate confirmed the clean Git source state, NORTH segmentation, SMB signing posture, bot prerequisites, IPv6 availability on WS01, LDAP/LDAPS target posture, MSSQL context and local listener availability.

## Runtime techniques already proven

The following were demonstrated in NORTH during Phase 03 validation sessions:

- LLMNR/NBT-NS/mDNS poisoning behavior.
- NetNTLMv2 capture for the built-in NORTH traffic generators, including Robb Stark and Eddard Stark.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative relay impact on CASTELBLACK.
- SAM extraction through the successful relayed SMB context.
, not Rickon Stark. ntlmrelayx reported successful LDAPS authentication and began read-only privilege enumeration.
- PrinterBug/MS-RPRN coercion callbacks against the tested NORTH hosts.
- MS-EFSR/PetitPotam-family callback proof on CASTELBLACK. Do not claim all NORTH hosts until each host has fresh evidence.
- Deterministic WS01 DHCPv6 takeover was captured during scoped mitm6 testing: Solicit -> Advertise -> Request -> Reply.
- After the DHCPv6 exchange, WS01 used the attacker link-local IPv6 address `fe80::250:56ff:fec0:a` as IPv6 DNS.
- WS01 then queried `wpad.north.sevenkingdoms.local` through the attacker-controlled IPv6 DNS path.
- Windows automatically requested `GET /wpad.dat` from WS01 (`10.4.10.31`) and received HTTP 200. No manual browser navigation was used for this acceptance proof.
- Rickon Stark authenticated graphical session on WS01 through a headless FreeRDP/Xvfb client.
- Clean headless RDP teardown: FreeRDP exits, its Xvfb display is removed, and the existing Robb/CASTELBLACK bot remains unaffected.
- Headless Rickon credential handling using a mode-0600 local credential file, with the password absent from FreeRDP argv and environment.

## WPAD status

The deterministic WS01 WPAD chain is **PROVEN**.

Validated acceptance sequence from the same packet capture:

1. Rickon is authenticated and Active on WS01.
2. WS01 emits DHCPv6 **Solicit**.
3. The scoped attacker path returns DHCPv6 **Advertise**.
4. WS01 emits DHCPv6 **Request**.
5. The attacker path returns DHCPv6 **Reply**.
6. WS01 reports attacker IPv6 DNS `fe80::250:56ff:fec0:a`.
7. WS01 sends WPAD DNS queries to that attacker-controlled IPv6 DNS path.
8. WS01 automatically sends `GET /wpad.dat` over HTTP and receives 200.

The proof is preserved as reproducible logic in `scripts/phase03/validate-wpad-chain.sh`. The final same-capture validator completed with **PASS: 8 / FAIL: 0**. Raw PCAP/log evidence remains operator-side and is intentionally not committed.

Manual navigation to `http://wpad/wpad.dat` is not used as acceptance evidence.

## LDAP / LDAPS relay status

The NORTH LDAP/LDAPS relay path is now **PROVEN** using the HTTP/WPAD source.

Validated sequence:

1. Rickon's permanent interactive session keeps WS01 active.
2. Scoped mitm6 steers WS01 DNS/WPAD traffic to the attacker.
3. ntlmrelayx serves the WPAD/proxy-auth path over HTTP.
4. WS01 authenticates as the computer account `NORTH\WS01# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch baseline: `893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This document preserves the Phase 03 runtime work completed before the permanent Phase 03 overlay is implemented.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` passed from a neutral operator state with:

- PASS: 58
- WARN: 0
- FAIL: 0

The gate confirmed the clean Git source state, NORTH segmentation, SMB signing posture, bot prerequisites, IPv6 availability on WS01, LDAP/LDAPS target posture, MSSQL context and local listener availability.

## Runtime techniques already proven

The following were demonstrated in NORTH during Phase 03 validation sessions:

- LLMNR/NBT-NS/mDNS poisoning behavior.
- NetNTLMv2 capture for the built-in NORTH traffic generators, including Robb Stark and Eddard Stark.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative relay impact on CASTELBLACK.
- SAM extraction through the successful relayed SMB context.
- MSSQL `xp_dirtree` outbound-authentication callback from CASTELBLACK as the `NORTH\sql_svc` service identity.
- SMB-origin relay of that `sql_svc` authentication to WINTERFELL LDAP/LDAPS was tested and rejected because the SMB client requested signing; keep this as a documented non-viable base path rather than forcing a downgrade.
- HTTP/WPAD-origin relay from WS01 to WINTERFELL LDAPS succeeded twice in the controlled NORTH test. The relayed identity was the machine account `NORTH\WS01# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch baseline: `893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This document preserves the Phase 03 runtime work completed before the permanent Phase 03 overlay is implemented.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` passed from a neutral operator state with:

- PASS: 58
- WARN: 0
- FAIL: 0

The gate confirmed the clean Git source state, NORTH segmentation, SMB signing posture, bot prerequisites, IPv6 availability on WS01, LDAP/LDAPS target posture, MSSQL context and local listener availability.

## Runtime techniques already proven

The following were demonstrated in NORTH during Phase 03 validation sessions:

- LLMNR/NBT-NS/mDNS poisoning behavior.
- NetNTLMv2 capture for the built-in NORTH traffic generators, including Robb Stark and Eddard Stark.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative relay impact on CASTELBLACK.
- SAM extraction through the successful relayed SMB context.
, not Rickon Stark. ntlmrelayx reported successful LDAPS authentication and began read-only privilege enumeration.
- PrinterBug/MS-RPRN coercion callbacks against the tested NORTH hosts.
- MS-EFSR/PetitPotam-family callback proof on CASTELBLACK. Do not claim all NORTH hosts until each host has fresh evidence.
- Deterministic WS01 DHCPv6 takeover was captured during scoped mitm6 testing: Solicit -> Advertise -> Request -> Reply.
- After the DHCPv6 exchange, WS01 used the attacker link-local IPv6 address `fe80::250:56ff:fec0:a` as IPv6 DNS.
- WS01 then queried `wpad.north.sevenkingdoms.local` through the attacker-controlled IPv6 DNS path.
- Windows automatically requested `GET /wpad.dat` from WS01 (`10.4.10.31`) and received HTTP 200. No manual browser navigation was used for this acceptance proof.
- Rickon Stark authenticated graphical session on WS01 through a headless FreeRDP/Xvfb client.
- Clean headless RDP teardown: FreeRDP exits, its Xvfb display is removed, and the existing Robb/CASTELBLACK bot remains unaffected.
- Headless Rickon credential handling using a mode-0600 local credential file, with the password absent from FreeRDP argv and environment.

## WPAD status

The deterministic WS01 WPAD chain is **PROVEN**.

Validated acceptance sequence from the same packet capture:

1. Rickon is authenticated and Active on WS01.
2. WS01 emits DHCPv6 **Solicit**.
3. The scoped attacker path returns DHCPv6 **Advertise**.
4. WS01 emits DHCPv6 **Request**.
5. The attacker path returns DHCPv6 **Reply**.
6. WS01 reports attacker IPv6 DNS `fe80::250:56ff:fec0:a`.
7. WS01 sends WPAD DNS queries to that attacker-controlled IPv6 DNS path.
8. WS01 automatically sends `GET /wpad.dat` over HTTP and receives 200.

The proof is preserved as reproducible logic in `scripts/phase03/validate-wpad-chain.sh`. The final same-capture validator completed with **PASS: 8 / FAIL: 0**. Raw PCAP/log evidence remains operator-side and is intentionally not committed.

Manual navigation to `http://wpad/wpad.dat` is not used as acceptance evidence.

.
5. ntlmrelayx relays that authentication to `ldaps://10.4.10.11` (WINTERFELL).
6. LDAPS authentication succeeds and ntlmrelayx performs read-only privilege enumeration.
7. No RBCD, ACL, Shadow Credentials, add-computer or directory mutation was enabled for this proof.

Important: this proof establishes the relay transport and authenticated directory context. It does **not** yet prove that `WS01# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch baseline: `893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This document preserves the Phase 03 runtime work completed before the permanent Phase 03 overlay is implemented.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` passed from a neutral operator state with:

- PASS: 58
- WARN: 0
- FAIL: 0

The gate confirmed the clean Git source state, NORTH segmentation, SMB signing posture, bot prerequisites, IPv6 availability on WS01, LDAP/LDAPS target posture, MSSQL context and local listener availability.

## Runtime techniques already proven

The following were demonstrated in NORTH during Phase 03 validation sessions:

- LLMNR/NBT-NS/mDNS poisoning behavior.
- NetNTLMv2 capture for the built-in NORTH traffic generators, including Robb Stark and Eddard Stark.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative relay impact on CASTELBLACK.
- SAM extraction through the successful relayed SMB context.
- MSSQL `xp_dirtree` outbound-authentication callback from CASTELBLACK as the `NORTH\sql_svc` service identity.
- SMB-origin relay of that `sql_svc` authentication to WINTERFELL LDAP/LDAPS was tested and rejected because the SMB client requested signing; keep this as a documented non-viable base path rather than forcing a downgrade.
- HTTP/WPAD-origin relay from WS01 to WINTERFELL LDAPS succeeded twice in the controlled NORTH test. The relayed identity was the machine account `NORTH\WS01# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch baseline: `893720a69bdd8464f1ceaeb0cf2fd81a8bdabaf3`
Lab instance: `cebee3-goad-vmware`
Scope: NORTH / `10.4.10.0/24` / `vmnet10`

This document preserves the Phase 03 runtime work completed before the permanent Phase 03 overlay is implemented.

## Baseline readiness

`scripts/validate-phase03-readiness.sh` passed from a neutral operator state with:

- PASS: 58
- WARN: 0
- FAIL: 0

The gate confirmed the clean Git source state, NORTH segmentation, SMB signing posture, bot prerequisites, IPv6 availability on WS01, LDAP/LDAPS target posture, MSSQL context and local listener availability.

## Runtime techniques already proven

The following were demonstrated in NORTH during Phase 03 validation sessions:

- LLMNR/NBT-NS/mDNS poisoning behavior.
- NetNTLMv2 capture for the built-in NORTH traffic generators, including Robb Stark and Eddard Stark.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative relay impact on CASTELBLACK.
- SAM extraction through the successful relayed SMB context.
, not Rickon Stark. ntlmrelayx reported successful LDAPS authentication and began read-only privilege enumeration.
- PrinterBug/MS-RPRN coercion callbacks against the tested NORTH hosts.
- MS-EFSR/PetitPotam-family callback proof on CASTELBLACK. Do not claim all NORTH hosts until each host has fresh evidence.
- Deterministic WS01 DHCPv6 takeover was captured during scoped mitm6 testing: Solicit -> Advertise -> Request -> Reply.
- After the DHCPv6 exchange, WS01 used the attacker link-local IPv6 address `fe80::250:56ff:fec0:a` as IPv6 DNS.
- WS01 then queried `wpad.north.sevenkingdoms.local` through the attacker-controlled IPv6 DNS path.
- Windows automatically requested `GET /wpad.dat` from WS01 (`10.4.10.31`) and received HTTP 200. No manual browser navigation was used for this acceptance proof.
- Rickon Stark authenticated graphical session on WS01 through a headless FreeRDP/Xvfb client.
- Clean headless RDP teardown: FreeRDP exits, its Xvfb display is removed, and the existing Robb/CASTELBLACK bot remains unaffected.
- Headless Rickon credential handling using a mode-0600 local credential file, with the password absent from FreeRDP argv and environment.

## WPAD status

The deterministic WS01 WPAD chain is **PROVEN**.

Validated acceptance sequence from the same packet capture:

1. Rickon is authenticated and Active on WS01.
2. WS01 emits DHCPv6 **Solicit**.
3. The scoped attacker path returns DHCPv6 **Advertise**.
4. WS01 emits DHCPv6 **Request**.
5. The attacker path returns DHCPv6 **Reply**.
6. WS01 reports attacker IPv6 DNS `fe80::250:56ff:fec0:a`.
7. WS01 sends WPAD DNS queries to that attacker-controlled IPv6 DNS path.
8. WS01 automatically sends `GET /wpad.dat` over HTTP and receives 200.

The proof is preserved as reproducible logic in `scripts/phase03/validate-wpad-chain.sh`. The final same-capture validator completed with **PASS: 8 / FAIL: 0**. Raw PCAP/log evidence remains operator-side and is intentionally not committed.

Manual navigation to `http://wpad/wpad.dat` is not used as acceptance evidence.

 has the rights needed to modify a chosen RBCD or Shadow Credentials target.

The MSSQL `sql_svc` SMB callback remains useful for SMB/coercion lessons, but SMB -> LDAP/LDAPS is not the base NORTH path because the observed SMB client requested signing.

## Headless victim architecture

The permanent Phase 03 Rickon victim candidate is now runtime-proven:

- Robb bot remains a separate systemd user service on CASTELBLACK and was not modified.
- Rickon runs through `kingdoms-phase03-rickon.service` and connects to WS01.
- Rickon and Robb use independent Xvfb process trees; observed displays may be reused after clean teardown and are not treated as stable identifiers.
- WS01 independently reported `rickon.stark` as an **Active** interactive RDP session.
- The Rickon service survived a controlled restart: the old service, xvfb-run, Xvfb and FreeRDP PIDs disappeared, a new service instance established exactly one WS01 RDP socket, and WS01 again reported Rickon Active.
- FreeRDP reads arguments from stdin; the password is absent from process argv.
- The Rickon password is stored outside the repository under the operator config directory with mode 0600.
- WS01 RDP certificate pinning is enforced using a locally stored, owner-only SHA-256 fingerprint verified independently from Windows and from a network-side TLS probe.
- No password or secret-bearing runtime material is stored in Git.

The temporary investigation helpers remain under `scripts/phase03/diagnostics/`; the permanent candidate is under `scripts/phase03/` and `ops/systemd/`.

## Remaining configuration work

The permanent NORTH Phase 03 overlay still needs:

- `ansible/phase03.yml`
- dedicated Phase 03 roles/fixtures
- `scripts/apply-phase03.sh`
- `scripts/validate-phase03-runtime.sh`
- `scripts/reset-phase03.sh`
- promote the proven WPAD/mitm6 diagnostics into a permanent apply/prove/reset scenario
- explicit LDAP/LDAPS training posture in source
- promote the proven HTTP/WPAD -> LDAPS relay profile into the permanent apply/prove/reset workflow
- controlled/reversible RBCD fixture
- optional Shadow Credentials fixture after ACL preflight
- scoped ADIDNS fixture
- WS01 Windows WebClient/WebDAV client scenario
- dedicated CASTELBLACK Phase 03 share artifacts
- mutually exclusive Kali operator profiles for capture, SMB relay, SOCKS/interactive relay and mitm6/LDAP relay

## Evidence handling

Do not commit raw credentials, NetNTLMv2 captures, NT hashes, Kerberos keys, PAC private material or other secret-bearing output.

Raw runtime evidence stays under the operator evidence directory. Git should contain sanitized summaries, deterministic validators and reusable infrastructure only.

## Regression requirement

Every Phase 03 state-changing fixture must be independently reversible and must not break Phases 00–02, the NORTH segmentation contract, existing DNS bots, RDP access contract, Phase 02 MSSQL behavior or later WS01 LPE fixtures.
