# Kingdoms — Phase 03 Runtime Checkpoint

Date: 2026-09-24
Branch: \`kingdoms/phase03-overlay\`
Lab instance: \`cebee3-goad-vmware\`
Scope: NORTH / \`10.4.10.0/24\` / \`vmnet10\`

This file records runtime evidence only. Raw credentials, hashes, tickets and other secret-bearing material stay outside Git.

## Baseline readiness

\`scripts/validate-phase03-readiness.sh\` completed with **58 PASS / 0 WARN / 0 FAIL** from a neutral operator state.

## Runtime techniques proven

- LLMNR/NBT-NS/mDNS poisoning behavior in NORTH.
- NetNTLMv2 capture for the built-in Robb Stark and Eddard Stark traffic generators.
- SMB relay of Eddard Stark authentication to CASTELBLACK.
- Administrative SMB relay impact on CASTELBLACK, including SAM extraction.
- CASTELBLACK MSSQL \`xp_dirtree\` outbound authentication as \`NORTH\sql_svc\`.
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
5. WS01 uses attacker IPv6 DNS \`fe80::250:56ff:fec0:a\`.
6. WS01 queries WPAD through that IPv6 path.
7. WS01 automatically requests \`GET /wpad.dat\`.

\`scripts/phase03/validate-wpad-chain.sh\` completed with **PASS: 8 / FAIL: 0**.

## LDAP / LDAPS relay

The NORTH HTTP/WPAD -> LDAPS relay path is **PROVEN**.

- WINTERFELL is reachable on TCP/389 and TCP/636.
- Mutation-disabled HTTP/WPAD relay authenticated successfully to \`ldaps://10.4.10.11\`.
- A WS01 machine-account authentication was relayed as \`NORTH\WS01$\`.
- Read-only privilege enumeration started successfully.
- The MSSQL \`sql_svc\` SMB-origin path is not the NORTH LDAP base path because the observed SMB client requested signing.

## RBCD end-to-end proof

Preflight established:

- target \`WS01$\`;
- RBCD attribute initially absent;
- \`ms-DS-MachineAccountQuota = 10\`;
- \`PHASE03RBCD$\` initially absent;
- WS01 SELF has \`WriteProperty\` on the exact RBCD attribute.

The exact pre-attack baseline is retained locally in mode-0600 \`~/.config/kingdoms/phase03-rbcd-baseline.json\`.

Stage 1 is **PROVEN**:

- \`PHASE03RBCD$\` was created;
- candidate SID: \`S-1-5-21-3668019051-2784807040-3421729346-1124\`;
- WS01 RBCD remained empty immediately afterward.

Stage 2 is **PROVEN**:

- deterministic LocalSystem HTTP callback from WS01 authenticated as \`NORTH\WS01$\`;
- ntlmrelayx reported delegation modification success;
- read-only verification confirmed the WS01 RBCD DACL contained the \`PHASE03RBCD$\` SID.

S4U consequence is **PROVEN**:

- \`PHASE03RBCD$\` obtained a forwardable TGT;
- Impacket completed S4U2Self and S4U2Proxy while impersonating \`Administrator\`;
- an Administrator CIFS service ticket for \`cifs/ws01.north.sevenkingdoms.local\` was created;
- Kerberos-authenticated SMB access listed \`ADMIN$\`, \`C$\` and \`IPC$\`;
- \`C$\` was opened and listed successfully without remote command execution.

Rollback is **PROVEN**:

- WS01 RBCD was restored to the captured baseline;
- \`PHASE03RBCD$\` was removed because it did not exist in the baseline;
- the local candidate password was removed;
- temporary RBCD Kerberos caches/helper files were removed;
- the mode-0600 baseline file was retained for audit/verification;
- rollback markers returned \`RBCD_MATCH=True\`, \`CANDIDATE_MATCH=True\` and \`RESET_COMPLETE=True\`.

RBCD is therefore closed end-to-end: **preflight -> relay -> mutation -> S4U consequence -> exact rollback**.

## Interactive SMB relay

Interactive SMB relay to CASTELBLACK is **PROVEN**.

- Responder operated as poisoner-only with SMB and HTTP servers disabled.
- ntlmrelayx relayed NORTH SMB authentication to \`smb://10.4.10.22\` with \`-i --keep-relaying\`.
- \`NORTH\ROBB.STARK\` produced retained interactive SMB sessions on \`127.0.0.1:11000+\`; share enumeration worked, but opening/listing \`C$\` was denied.
- \`NORTH\EDDARD.STARK\` produced retained interactive SMB sessions on \`127.0.0.1:11000+\`; an Eddard session was connected with netcat, \`C$\` was selected, and the root directory was listed successfully.
- This proves the authorization distinction cleanly: relay preserves the relayed principal's effective privileges rather than granting privileges by itself.

The interactive relay runtime was then stopped and verified clean: no listeners remained on TCP/445, TCP/80 or \`127.0.0.1:11000+\`, and no ntlmrelayx/Responder process remained.

## SOCKS SMB relay

SOCKS SMB relay to CASTELBLACK is **PROVEN**.

- ntlmrelayx exposed its SOCKS5 proxy on \`127.0.0.1:1080\` while relaying SMB authentication to \`smb://10.4.10.22\`.
- Responder remained poisoner-only with SMB and HTTP servers disabled.
- The built-in Robb/Eddard traffic generators naturally supplied repeatable NORTH authentication.
- ntlmrelayx retained both identities simultaneously:
  - \`NORTH\ROBB.STARK\` with \`AdminStatus FALSE\`;
  - \`NORTH\EDDARD.STARK\` with \`AdminStatus TRUE\`.
- A dedicated temporary ProxyChains configuration pointed only to \`socks5 127.0.0.1 1080\`; the global ProxyChains configuration was not modified.
- \`impacket-smbclient -no-pass\` reused Robb's retained session through SOCKS: share enumeration succeeded, while \`C$\` returned \`STATUS_ACCESS_DENIED\`.
- The same client then reused Eddard's retained session through SOCKS: \`C$\` opened and its root filesystem was listed successfully.
- ntlmrelayx logged the corresponding \`SOCKS: Proxying client session\` events for both identities.

This proves the same authorization rule as interactive relay: SOCKS retains and reuses the relayed identity; it does not create new privilege.

Cleanup is **PROVEN**:

- Responder and ntlmrelayx were stopped.
- No attack process remained.
- TCP/80, 135, 445, 1080, 5985, 5986, 6666 and 9389 were free.
- The temporary ProxyChains configuration was removed.

SOCKS SMB relay is therefore closed runtime-wise: **poison -> relay -> retained SOCKS session -> credential-less client reuse -> privilege-dependent authorization -> clean shutdown**.

## SMB share authorization consequence

SMB share authorization on CASTELBLACK is **PROVEN**.

- Relayed \`NORTH\ROBB.STARK\` could enumerate shares but could not open \`C$\`.
- Relayed \`NORTH\EDDARD.STARK\` could enumerate shares, open \`C$\`, and list the root filesystem.
- The same distinction was reproduced through both interactive relay and SOCKS session reuse.

This consequence is therefore closed: **relay succeeds for both identities, but share access follows target-side authorization**.

## SMB remote execution consequence

SMB remote execution on CASTELBLACK is **PROVEN**.

- ntlmrelayx relayed authentication to \`smb://10.4.10.22\` with \`-c 'cmd.exe /Q /c "whoami & hostname"'\`.
- \`NORTH\EDDARD.STARK\` authenticated successfully and the command executed on CASTELBLACK.
- Command output proved the remote execution context was \`NT AUTHORITY\SYSTEM\` on \`CASTELBLACK\`.
- ntlmrelayx temporarily started the stopped \`RemoteRegistry\` service as part of its SMB execution path and then stopped it again.
- \`NORTH\ROBB.STARK\` also authenticated successfully to the relay target, but the execution mechanism failed with \`rpc_s_access_denied\` / DCERPC error \`0x5\`.
- This proves that successful relay authentication alone is not enough for remote execution; the relayed principal must already have the required target-side administrative authorization.

Cleanup is **PROVEN**:

- Responder was stopped.
- ntlmrelayx was stopped.
- No ntlmrelayx/Responder process remained.
- TCP/80, 135, 445, 5985, 5986, 6666 and 9389 were free.

SMB remote execution is therefore closed runtime-wise: **relay -> administrative authorization -> service-backed command execution as SYSTEM -> clean shutdown**.

## LSASS credential-material consequence

LSASS credential-material access on CASTELBLACK is **PROVEN**.

- A relayed `NORTH\EDDARD.STARK` administrative session executed the controlled dump command on CASTELBLACK.
- CASTELBLACK produced `C:\Windows\Temp\kingdoms-phase03-lsass.dmp` with size `89,796,074` bytes.
- `NORTH\ROBB.STARK` relayed successfully but the privileged execution path failed with DCERPC `0x5 / rpc_s_access_denied`, preserving the limited-vs-administrative comparison.
- A retained Eddard SMB SOCKS session with `AdminStatus TRUE` was used to retrieve the dump from `C$\Windows\Temp`.
- The local copy matched the expected `89,796,074` byte size and was identified as a Windows MiniDump with the `MDMP` signature.
- Local pypykatz parsing completed with return code `0` and the sanitized result reported `username_count=27`, confirming parseable LSASS credential material without committing secrets to Git.
- The sanitized identity-only evidence included NORTH and CASTELBLACK principals as well as service identities; hashes, passwords and other secret-bearing parser output were not retained in Git.

Cleanup is **PROVEN**:

- The remote CASTELBLACK dump was deleted and a follow-up SMB listing returned `STATUS_NO_SUCH_FILE`.
- The local raw LSASS dump was deleted.
- The full secret-bearing pypykatz output was deleted.
- Only the sanitized local summary was retained outside Git.
- Responder and ntlmrelayx were stopped.
- No relay process remained and the relay/SOCKS listener ports were free.

LSASS is therefore closed end-to-end: **administrative relay -> SYSTEM-capable dump creation -> retained SOCKS retrieval -> MiniDump validation -> local credential parsing -> remote/local secret-bearing artifact cleanup**.

## DPAPI credential-material consequence

Native Windows DPAPI credential recovery on CASTELBLACK is **PROVEN**.

- The retained `NORTH\EDDARD.STARK` SMB SOCKS session had `AdminStatus TRUE` and was used to acquire native SYSTEM DPAPI material without modifying CASTELBLACK.
- Four root SYSTEM masterkeys and three SYSTEM User masterkeys were acquired from the existing Windows DPAPI protection store.
- The native Credential Manager artifact `DFBE70A7E5CC19A398EBF1B96859CE5D` was acquired with size `11,120` bytes.
- Credential metadata identified masterkey GUID `AB2516B4-FCD6-4E4E-8FFE-42BA0FB20641`, and the corresponding masterkey file was present in the acquired SYSTEM User store.
- `impacket-secretsdump` completed successfully through the retained Eddard session and recovered both DPAPI_SYSTEM `UserKey` and `MachineKey` material locally.
- The matching masterkey decrypted successfully with the DPAPI_SYSTEM `UserKey`.
- The native Windows Credential Manager artifact then decrypted successfully with Impacket; sanitized metadata showed a generic, local-machine-persisted Windows Credential Manager entry without retaining the underlying secret value.
- Raw DPAPI masterkeys, Credential Manager data and other secret-bearing local output were removed after validation; only the sanitized summary was retained outside Git.
- No native DPAPI or Credential Manager artifact was deleted from CASTELBLACK.

Cleanup is **PROVEN**:

- The local raw/secret-bearing DPAPI evidence directory was removed.
- The sanitized summary was retained.
- Responder and ntlmrelayx were stopped.
- No relay process remained and relay/SOCKS listener ports were free.
- The repository remained unchanged except for the pre-existing untracked `arp.cache`.

DPAPI is therefore closed end-to-end: **administrative relay -> retained SOCKS session -> native DPAPI artifact acquisition -> masterkey GUID correlation -> DPAPI_SYSTEM key recovery -> masterkey decryption -> Credential Manager decryption -> local secret-bearing artifact cleanup**.

## Remaining Phase 03 engineering

- Shadow Credentials controlled fixture.
- ADIDNS scenario.
- WebDAV/.lnk/.url victim-interaction scenario.
- Promote proven mitm6/WPAD and HTTP->LDAPS flows into permanent apply/prove/reset infrastructure.
- Final regression and Notion teaching sections/screenshots.

## Next acceptance gate

The next acceptance gate is **Shadow Credentials**, now that the SMB post-relay consequence family is closed through share access, SYSTEM execution, LSASS and native DPAPI recovery.

## Regression rule

Every Phase 03 state-changing fixture must be independently reversible and must not break Phases 00–02, the NORTH segmentation contract, existing traffic generators, the RDP contract, Phase 02 MSSQL behavior or later WS01 fixtures.
