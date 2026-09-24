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
- PrinterBug/MS-RPRN coercion callbacks against the tested NORTH hosts.
- MS-EFSR/PetitPotam-family callback proof on CASTELBLACK. Do not claim all NORTH hosts until each host has fresh evidence.
- WS01 IPv6 support and previous acceptance of rogue DHCPv6 information during scoped mitm6 testing.
- WPAD-related DNS discovery behavior from WS01.
- Manual retrieval of a harmless `wpad.dat` over HTTP, proving connectivity only.
- Rickon Stark authenticated graphical session on WS01 through a headless FreeRDP/Xvfb client.
- Clean headless RDP teardown: FreeRDP exits, its Xvfb display is removed, and the existing Robb/CASTELBLACK bot remains unaffected.
- Headless Rickon credential handling using a mode-0600 local credential file, with the password absent from FreeRDP argv and environment.

## WPAD status

The WPAD chain is only partially complete.

Proven:

1. Rickon authenticated on WS01.
2. WPAD auto-detection enabled in the user session.
3. Manual proxy disabled and no manual PAC URL configured.
4. Automatic DNS lookups for:
   - `wpad.north.sevenkingdoms.local`
   - `wpad.sevenkingdoms.local`
5. Those queries were observed from WS01 (`10.4.10.31`).
6. A harmless PAC file can be served and fetched manually.

Not yet proven:

- A deterministic current-run DHCPv6 takeover by mitm6.
- WS01 using attacker-controlled DNS as part of that deterministic flow.
- An automatic HTTP `GET /wpad.dat` caused by Windows/browser auto-discovery.

Manual navigation to `http://wpad/wpad.dat` does not satisfy the acceptance criterion.

## Headless victim architecture

Validated temporary architecture:

- Robb bot: systemd user service, Xvfb display `:99`, CASTELBLACK.
- Rickon test session: separate Xvfb display (observed as `:100`), WS01.
- FreeRDP reads arguments from stdin.
- The Rickon password is stored outside the repository under the operator config directory with mode 0600.
- No password is permitted in Git, shell argv, process environment, documentation or evidence files.

The temporary diagnostics used for this validation are tracked under `scripts/phase03/diagnostics/`. They are not yet the production Phase 03 victim service.

## Remaining configuration work

The permanent NORTH Phase 03 overlay still needs:

- `ansible/phase03.yml`
- dedicated Phase 03 roles/fixtures
- `scripts/apply-phase03.sh`
- `scripts/validate-phase03-runtime.sh`
- `scripts/reset-phase03.sh`
- deterministic Rickon/WS01 victim automation with certificate pinning
- deterministic WPAD/mitm6 scenario
- explicit LDAP/LDAPS training posture in source
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
