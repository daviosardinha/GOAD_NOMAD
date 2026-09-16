# Phase 01: unauthenticated enumeration

This is intentionally vulnerable **GOAD Kingdoms lab provisioning**. The GOAD
install sequence runs `phase01.yml` after ACLs, IIS content, security and existing
vulnerabilities. Other scenarios do not receive this stage. Targeted replay uses
only `dc02` and `srv02`; it does not gather facts from WS01 or other zones.

Phase 01 is a **curriculum contract**: a fresh Kingdoms installation must already
expose the exact protocol surfaces required by the walkthrough. Students should
not have to edit Windows policy, registry values, GPOs or lab modes to make a
lesson work.

| Change | Location | Intended result |
| --- | --- | --- |
| `LSAAnonymousNameLookup=1` | Dedicated `Kingdoms - Phase 01 - Anonymous SID Translation` GPO linked to the NORTH Domain Controllers OU at link order 1 | Anonymous SID/name translation that survives Group Policy refresh |
| `RestrictNullSessAccess=1`, `NullSessionPipes={samr,lsarpc}`, `EveryoneIncludesAnonymous=0` | Dedicated `Kingdoms - Phase 01 - Anonymous RPC Exposure` GPO linked to the NORTH Domain Controllers OU at link order 2 | Only the named RPC curriculum surface is opened; ordinary NULL shares and general Everyone permissions remain restricted |
| `ANONYMOUS LOGON` (`S-1-5-7`) membership | Builtin `Pre-Windows 2000 Compatible Access` (`S-1-5-32-554`) | Explicit AD compatibility read path for anonymous user/group information on the DC |
| Seventh `dSHeuristics` character set to `2` | Sevenkingdoms forest configuration, written on WINTERFELL | Anonymous operations authorized by existing LDAP ACLs |
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

Anonymous SID/name translation and anonymous RPC named-pipe exposure are managed
through **separate dedicated NORTH GPOs**. The SID-translation GPO contains only
the Security Settings client-side extension and the
`LSAAnonymousNameLookup=1` security-template entry. The anonymous-RPC GPO keeps
`RestrictNullSessAccess=1`, explicitly exposes only `samr` and `lsarpc` in
`NullSessionPipes`, and deliberately keeps `EveryoneIncludesAnonymous=0`. It does
not configure anonymous shares.

The DC role separately ensures that `ANONYMOUS LOGON` (`S-1-5-7`) is a member of
Builtin `Pre-Windows 2000 Compatible Access` (`S-1-5-32-554`). This is the narrow
compatibility path documented by Microsoft for anonymous user/group information
on Active Directory domain controllers. It is intentionally preferred over making
all `Everyone` permissions apply to anonymous users. The result is a lab that can
teach anonymous SAMR/LSARPC while avoiding a broader anonymous authorization model.

Both GPOs are linked to
`OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local`, with SID translation
at link order `1` and scoped RPC exposure at link order `2`. The role does not
modify Default Domain Policy or Default Domain Controllers Policy.

Live hostname, domain and machine-role checks precede mutations. The scripts
compare current state, support Ansible check mode, and only commit differences.
After provisioning, WINTERFELL performs a computer-policy refresh. Provisioning
fails unless the effective state is all of the following:

- `LSAAnonymousNameLookup=1`
- `EveryoneIncludesAnonymous=0`
- `RestrictNullSessAccess=1`
- `NullSessionPipes` contains exactly `samr` and `lsarpc`
- `NullSessionShares` contains no non-empty entries
- `ANONYMOUS LOGON` is a member of `Pre-Windows 2000 Compatible Access`

The LDAP write is also read back. Run the targeted playbook a second time to
prove live idempotence: expect `changed=0`, `failed=0`, `unreachable=0`. Check
mode skips the live policy refresh and effective-policy assertion because it
performs no changes.

The IIS script writes only the `/internal` location in ApplicationHost.config.
It retains the public root and existing Web.config. If the public root's
anonymous setting has drifted, it fails rather than silently reconfiguring it.
It does not enable WebDAV, alter share permissions, enable Guest, or change
LDAP signing, channel binding or IIS extended protection.

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

During the targeted playbook, the two dedicated NORTH GPOs are created or
repaired, linked on the NORTH Domain Controllers OU, and followed by
`gpupdate /target:computer /force` on WINTERFELL. The compatibility-group
membership is also repaired idempotently. The playbook then verifies the merged
SID-translation policy, the effective LanmanServer/LSA anonymous-RPC registry
state and the explicit `ANONYMOUS LOGON` group membership before moving on.

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
it uses the existing forest credential. The GPO and compatibility-membership
tasks suppress output because they use the NORTH domain administrator credential.
The policy refresh is local to WINTERFELL; allow normal forest replication before
checking other DCs for the separate forest-wide LDAP setting.

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

The persistence regression for anonymous SID/name translation is: apply Phase 01,
force a computer Group Policy refresh on WINTERFELL, and rerun the validator.
`Anonymous SID-to-name translation` must remain `PASS`; a refresh must not return
the effective policy to `LSAAnonymousNameLookup=0`.

### Protocol-boundary contract

WINTERFELL intentionally distinguishes anonymous RPC from ordinary anonymous SMB
share access. Phase 01 must support the documented LSA/SAMR curriculum operations
while leaving ordinary NULL share listing restricted. The compatibility-group
membership grants the AD read path; the named-pipe allowlist grants only the
intended RPC transport; `EveryoneIncludesAnonymous=0` prevents a wider grant of
all permissions assigned to `Everyone`.

Checks cover real RID mapping, RootDSE, user/group attributes, Samwell's exact
seeded description, anonymous SAMR user/group queries and password policy, the
expected NULL/Guest share-listing matrix, Guest listing files on `all`, public
HTTP, the internal authentication boundary, NTLM identity and valid/invalid
Kerberos usernames. SMB requests use an explicit empty username and password for
NULL mode. They report requested credentials and observed share access, **not**
server-side session flags. No share write test is performed; write capability and
full Null/Guest identity attribution are not certified by this validator. Earlier
AS-REP, Kerberoasting, SQL and RDP results are not rerun.

Provisioning completion is not proof of live lesson readiness. The source and
parser tests can run here; Windows behavior, effective policy after GPO refresh,
second-run idempotence and fresh-install readiness require the VMware lab.

## References

- [Microsoft: anonymous LDAP operations and preservation of dSHeuristics](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/anonymous-ldap-operations-active-directory-disabled)
- [Microsoft: anonymous SID/name translation](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/jj852193(v=ws.11))
- [Microsoft: Network Management Functions on Active Directory Domain Controllers](https://learn.microsoft.com/en-us/windows/win32/netmgmt/requirements-for-network-management-functions-on-active-directory-domain-controllers)
- [Microsoft: Pre-Windows 2000 Compatible Access group](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/7a76a403-ed8d-4c39-adb7-a3255cab82c5)
- [Microsoft: Group Policy Security Settings CSE identifiers](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gpsb/55bb803e-b35f-4ce8-b558-4c1e92ad77a4)
- [Microsoft: IIS Windows Authentication](https://learn.microsoft.com/en-us/iis/configuration/system.webserver/security/authentication/windowsauthentication/)
- [Nmap: HTTP NTLM information and the root path argument](https://nmap.org/nsedoc/scripts/http-ntlm-info.html)
- [Kerbrute upstream v1.0.3 source](https://github.com/ropnop/kerbrute/tree/9dad6e171abdc7491f587c793aa05411264a3393)
