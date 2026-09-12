# Phase 01: unauthenticated enumeration

This is intentionally vulnerable **GOAD Kingdoms lab provisioning**. The GOAD
install sequence runs `phase01.yml` after ACLs, IIS content, security and existing
vulnerabilities. Other scenarios do not receive this stage. Targeted replay uses
only `dc02` and `srv02`; it does not gather facts from WS01 or other zones.

| Change | Location | Intended result |
| --- | --- | --- |
| `LSAAnonymousNameLookup=1` | WINTERFELL local security policy | Anonymous SID/name translation |
| Seventh `dSHeuristics` character set to `2` | Sevenkingdoms forest configuration, written on WINTERFELL | Anonymous operations authorized by existing ACLs |
| Windows Authentication enabled; anonymous disabled | CASTELBLACK `Default Web Site/internal` | HTTP 401 with Negotiate and NTLM; NTLM identity metadata |
| Kerbrute v1.0.3, pinned commit | Operator `~/.local/bin/kerbrute` | Kerberos username enumeration |

## Scope and idempotence

`dSHeuristics` is **forest-wide**, not a per-DC or NORTH-only switch. It applies
through configuration partition replication to the Sevenkingdoms forest. It
does not change the separate ESSOS forest. Read access remains bounded by ACLs;
this stage reuses the NORTH `ReadProperty`/`GenericExecute` ACEs and adds none.
The existing NORTH ACLs already inherit to descendants: this stage does not
claim a per-user or per-attribute allowlist. The forest-root administrator is
used for this operation, with the existing scenario password suppressed in logs.
All other characters, including long-value validation markers, are preserved.

Live hostname, domain and machine-role checks precede mutations. The scripts
compare current state, support Ansible check mode, and only commit differences.
The LDAP write is read back. Run the targeted playbook a second time to prove
live idempotence: expect `changed=0`, `failed=0`, `unreachable=0`. Check mode before
the IIS role service exists cannot fully validate its configuration sections.

The IIS script writes only the `/internal` location in ApplicationHost.config.
It retains the public root and existing Web.config. If the public root's
anonymous setting has drifted, it fails rather than silently reconfiguring it.
It does not enable WebDAV, alter share permissions, enable Guest, or change
LDAP signing, channel binding or IIS extended protection. An existing domain
GPO can override a local SID/name policy; a later failed readiness check is a
reason to inspect effective policy, not to weaken unrelated settings.

## Apply to an installed lab

From a clean checkout tracking the Phase 01 branch, with the lab running:

```bash
bash scripts/apply-phase01.sh --install-prerequisites
```

The command detects a single installed VMware Kingdoms instance. With multiple
instances append `--instance YOUR_INSTANCE_ID`. It checks repository source,
installs Debian/Kali operator prerequisites, builds pinned Kerbrute, runs the
targeted playbook with the existing GOAD Ansible runtime and three inventories,
then executes the runtime validator. Ansible failures stop the command. NORTH is
directly reachable in exercise mode; this command does not switch router modes. Omit
`--install-prerequisites` when system packages are already present. There is no
Windows rebuild or full-install replay.

The first operator setup requires Internet access for apt, git and Go modules.
Kerbrute is built from upstream commit
`9dad6e171abdc7491f587c793aa05411264a3393` (the commit behind annotated tag v1.0.3),
using its go.mod/go.sum. Dependency checksums and unchanged module files are
verified. A local binary checksum receipt allows later runs to skip downloading
or rebuilding; a mismatch triggers a rebuild. The system Go compiler is used,
so this is source/dependency pinning, not a bit-for-bit cross-toolchain guarantee.

For targeted replay or Ansible check mode, use the same three inventories as
the project's other maintenance scripts:

```bash
ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg" "$HOME/.goad/.venv/bin/ansible-playbook" \
  -i ad/GOAD/data/inventory -i workspace/YOUR_INSTANCE_ID/inventory \
  -i globalsettings.ini ansible/phase01.yml --check --diff
```

Remove `--check --diff` to apply directly. The LDAP task suppresses output because
it uses the existing forest credential. Changes need no forced AD replication or
global IIS restart; allow normal forest replication before checking other DCs.

## Final readiness check

```bash
bash scripts/validate-phase01.sh
```

Run from the Kali/operator network with NORTH reachable. Defaults are WINTERFELL
`10.4.10.11`, CASTELBLACK `10.4.10.22`, WS01 `10.4.10.31`; `--dc`, `--server` and
`--ws01` override addresses. All probes have a timeout. Each run creates a new,
private `~/kingdoms-phase01-TIMESTAMP/` with raw evidence, `results.json` and
`SUMMARY.txt`. Send `SUMMARY.txt` first. A missing tool, timeout, partial LDAP
result or inconclusive denial fails readiness; no stale output is reused.

### Corrected live SMB baseline (12 September 2026)

The initial validator incorrectly required NULL share names from both servers.
Explicit empty-username/password probes produced the following evidence:

| Host | NULL share-list request | Explicit Guest share-list request |
| --- | --- | --- |
| WINTERFELL | No share rows; exit zero, followed by failed SMB1 workgroup discovery | Rejected |
| CASTELBLACK | Session setup rejected with `NT_STATUS_ACCESS_DENIED` | Share names available |
| WS01 | Rejected | Rejected |

WINTERFELL's no-names result is an observation only; it does not prove access to
shares or the identity assigned to the SMB session. Anonymous domain SID and
SID/name translation are independently verified by RPC. The legacy SMB1
workgroup lookup is separate from share visibility and is not a readiness
requirement. No SMB1 enablement or Windows policy change follows from these
results. The classifier requires share rows for visibility, explicit rejection
for denied access, and evidence of the workgroup phase for the no-names result.
Empty output and network/tool failures remain inconclusive and fail the check.

Checks cover real RID mapping, RootDSE, user/group attributes, Samwell's exact
seeded description, the expected NULL/Guest share-listing matrix, Guest listing
files on `all`, public HTTP, the internal authentication boundary, NTLM identity
and valid/invalid Kerberos usernames. SMB requests use an explicit empty username
and password for NULL mode. They report requested credentials and observed share
access, **not** server-side session flags. No share write test is performed;
write capability and full Null/Guest identity attribution are not certified by
this validator. Earlier AS-REP, Kerberoasting, SQL and RDP results are not rerun.

Provisioning completion is not proof of live lesson readiness. The source and
parser tests can run here; Windows behavior, effective policy after GPO refresh,
second-run idempotence and fresh-install readiness require the VMware lab.

## References

- [Microsoft: anonymous LDAP operations and preservation of dSHeuristics](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/anonymous-ldap-operations-active-directory-disabled)
- [Microsoft: anonymous SID/name translation](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/jj852193(v=ws.11))
- [Microsoft: IIS Windows Authentication](https://learn.microsoft.com/en-us/iis/configuration/system.webserver/security/authentication/windowsauthentication/)
- [Nmap: HTTP NTLM information and the root path argument](https://nmap.org/nsedoc/scripts/http-ntlm-info.html)
- [Kerbrute upstream v1.0.3 source](https://github.com/ropnop/kerbrute/tree/9dad6e171abdc7491f587c793aa05411264a3393)
