# Kingdoms NORTH RDP contract

Kingdoms defines the course baseline. GOAD supplies infrastructure, not a
requirement to preserve broad inherited RDP access.

| Host | Exact Remote Desktop Users membership |
| --- | --- |
| WINTERFELL | Empty |
| CASTELBLACK | `NORTH\robb.stark` |
| WS01 | `NORTH\rickon.stark` |

Robb is an explicit compatibility exception for the existing `connect_bot`;
it is not an additional recovered-user/student foothold. Existing administrator
paths remain intact. WINTERFELL is a DC: its BUILTIN groups belong to NORTH,
not an independent member-machine SAM. Do not apply this change to another domain.

The five recovered users are Hodor, Brandon, Jon, Samwell and Rickon. None may
RDP to WINTERFELL or CASTELBLACK. Only Rickon may RDP to WS01, without direct or
nested administrator membership. Domain groups, credentials, service permissions,
GPOs, ACLs, shares and Phase 00/01 behavior must remain unchanged.

## Deployment on an existing lab

Use the existing Kingdoms management host and configured Ansible credentials.
Do not rebuild the lab or run the general vulnerabilities playbook for this fix.
Keep a console/management session available and take a normal lab snapshot before
applying a permissions migration. Existing desktop sessions are not logged off.

From the repository root, after checking out the published branch/commit:

```bash
bash scripts/verify-test-source.sh
python3 -m unittest discover -s tests

# Preview changes. This does not validate Windows runtime behavior.
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i ad/GOAD/data/inventory -i ad/GOAD/providers/vmware/inventory \
  ansible/kingdoms-rdp.yml --check --diff

# Apply only the three-host RDP membership and RDP allow-right contract.
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  -i ad/GOAD/data/inventory -i ad/GOAD/providers/vmware/inventory \
  ansible/kingdoms-rdp.yml

# Repeat the same apply command. Require changed=0, unreachable=0, failed=0
# for each of dc02, srv02 and ws01 before accepting idempotence.
```

If Ansible is in the Kingdoms virtualenv, use that environment's
`ansible-playbook` executable. Do not install or upgrade the lab's collections
just for this change. The implementation supports the existing pinned Windows
collections; it does not change their versions.

The migration uses `state: pure` only on explicitly opted-in RDP groups. Empty
membership is an enforced state, not a skipped task. Other groups, including
Administrators, remain additive in the general role; the targeted migration does
not manage Administrators at all. No RDP deny right is written or cleared.

## Complete read-only validation entry point

```bash
# Static checks only, no Windows connections:
bash scripts/validate-rdp-runtime.sh --source-only

# Three hosts: listener reachability, effective rights, nested membership,
# all 15 recovered-user policy decisions, Robb policy/task checks, and GPO report:
bash scripts/validate-rdp-runtime.sh

# Also run the unchanged Phase 01 validator from a host with its existing tools:
bash scripts/validate-rdp-runtime.sh --phase01

# After a real Rickon RDP login to WS01 and a working Robb bot session:
bash scripts/validate-rdp-runtime.sh --require-sessions --phase01
```

Optional environment variables:

- `KINGDOMS_RDP_ANSIBLE`: absolute path to the existing Ansible executable.
- `KINGDOMS_RDP_INVENTORY`: alternate management inventory with the same host
  aliases. Exercise-plane reachability still checks canonical NORTH addresses.
- `KINGDOMS_RDP_LOG_DIR`: output directory; prefer a new directory for every run.
- `GOAD_KINGDOMS_EXPECTED_COMMIT`: pin the existing source-of-truth gate.
- `KINGDOMS_RDP_BOT_MODE`: network-segmentation lifecycle RDP bot contract; defaults to `legacy`, while Phase 03 final regression explicitly uses `headless`.

The validator reads directory evidence on WINTERFELL and effective LSA policy
on each selected host. It resolves domain security groups and host-local alias
membership, including indirect Administrators and deny-right membership. DC
BUILTIN aliases are resolved again on each host; Robb's DC administrator rights
must not be confused with WS01 administrator rights. An unexpected account,
membership, effective right, unavailable dependency or missing host evidence fails
the check. It never repairs policies, refreshes GPOs, restarts tasks, changes lab
mode, or tests a password. Ansible's normal temporary execution files and local
evidence logs are not persistent lab-configuration changes.

### Evidence boundaries

The offline collector regression (`tests/test_rdp_directory_evidence.ps1`) checks
base-scope queries, typed/binary/string SID values, duplicate removal and invalid
evidence rejection. AD calls are mocked; it needs no domain or credentials. On
Windows, run it with Windows PowerShell 5.1 to exercise native SID constructors:

```powershell
powershell.exe -NoProfile -NonInteractive -File tests/test_rdp_directory_evidence.ps1
```

The Python suite runs this regression when `pwsh` is available. On Linux, its
explicitly reported typed stand-in tests dispatch and constructor argument
binding only; it does not validate Windows SID APIs or live AD behavior.

`tests/test_rdp_transport.py` also uses the installed Ansible templating engine
in normal and native modes, JSON-encodes the resulting module parameters and
passes them to the host collector fixtures through PowerShell's
`AddScript`/`AddParameters` invocation. The final `from_json | to_json` filter
is intentional: without it, Ansible can turn JSON-looking text into a dictionary,
which binds to a PowerShell string as `System.Collections.Hashtable`.

`tests/test_rdp_host_evidence.ps1` exercises the production host-policy logic for
all three hosts, the six identities, twenty rejection cases and required-session
checks. Windows I/O (LSA, ADSI, account lookup, service/registry/task/session and
GPO reads) is replaced with explicit fixtures; this does not verify those native
APIs. Ansible/PowerShell-dependent tests report a skip if their runtime is absent.
The root `\connect_bot` task's run-as identity is resolved to a SID and compared
with the SID of `NORTH\robb.stark`, not matched against a name-format regex.
The collector reports the stored principal, resolved SID and expected SID;
unresolved or different identities still fail. Fixture tests cover equivalent
name/SID representations and wrong-domain or same-name/different-SID accounts.
Run the full offline integration suite from an environment with both installed:

```bash
python3 -m unittest discover -s tests -p 'test_rdp_*.py'
```

`RDP_POLICY_CONTRACT=...:PASS` proves the inspected authorization configuration;
it does **not** prove that a fresh desktop session can be opened. Existing session
evidence can predate a policy change. The script deliberately reports
`DESKTOP_LOGON_MATRIX=NOT_EXECUTED` rather than claiming a credential-login test.

Release acceptance must additionally record fresh RDP attempts using the known
lab identities through the normal client:

| NORTH identity | WINTERFELL | CASTELBLACK | WS01 |
| --- | --- | --- | --- |
| hodor | Deny | Deny | Deny |
| brandon.stark | Deny | Deny | Deny |
| jon.snow | Deny | Deny | Deny |
| samwell.tarly | Deny | Deny | Deny |
| rickon.stark | Deny | Deny | Allow, non-admin |

Record authorization rejection separately from bad credentials, unreachable
services, disabled/locked accounts, NLA failures or session-capacity limits. Do
not use an RDP tool's success banner as proof of local administrator status.
For the positive session, record the host, identity and non-admin token. Use a
fresh session/token after membership changes; the migration does not terminate
any existing user session.

Also record the existing Phase 00/01 and non-RDP service acceptance results after
migration, after a clean rebuild, and after a scenario reset. The broader network
runtime validator remains a separate lifecycle test and can change network mode;
the new read-only script does not invoke it automatically. Recheck policy after
the normal Group Policy refresh cycle to detect externally managed overrides.

## Optional Guacamole extension

The extension no longer overlays legacy CasterlyRock data onto first-class
Kingdoms WS01. Its connection generator uses the same host membership data,
retains administrator connections and the Robb exception, and removes obsolete
generator-owned user connections on opted-in hosts plus legacy CasterlyRock
connection names. The first-class WS01 local-admin password follows the same
domain-password fallback as `ansible/ws01.yml`.

On an already installed Guacamole extension, run its existing connection
provisioning workflow against this source with the extension inventory loaded;
the Windows-only migration does not contact or modify Guacamole. Back up the
Guacamole database before reconciliation. Removed generated definitions can be
recreated from source; unrelated hand-created connections are not deleted.
Validate the resulting connection list separately: the Windows policy validator
does not query the optional Guacamole server. Local/domain administrator
connections are expected and must not be mistaken for low-privileged footholds.

## Future phases and rollback

Future scenarios must start from this contract and return to it on reset. A
scenario-specific exception needs explicit apply/reset behavior and tests; never
permanently reintroduce Stark or Night Watch to a host's RDP group. Rickon's
interactive WS01 session remains available to the existing Windows-LPE lessons.

The protected-baseline hashes in `tests/test_rdp_access_contract.py` intentionally
fail if this RDP change also changes unrelated lab data or Phase 01 files. A
future intentional curriculum change may update those hashes only after review.

Reverting code alone will not undo already-applied local membership. Use the lab
snapshot or a reviewed reverse migration for a runtime rollback; do not assume
an additive role will remove Rickon's or Robb's explicit entries. This change does
not include an automatic rollback that reopens the old broad RDP grants.
