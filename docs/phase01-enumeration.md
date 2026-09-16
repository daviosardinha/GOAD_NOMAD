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
| `RestrictNullSessAccess=1` and `NullSessionPipes={samr,lsarpc}` | Dedicated `Kingdoms - Phase 01 - Anonymous RPC Exposure` GPO linked to the NORTH Domain Controllers OU at link order 2 | Anonymous SAMR/LSARPC curriculum operations while ordinary NULL share access stays restricted |
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
`RestrictNullSessAccess=1` and explicitly exposes only `samr` and `lsarpc` in
`NullSessionPipes`. It does not configure anonymous shares. This distinction is
intentional: accepting selected anonymous RPC operations is not the same thing
as exposing ordinary SMB shares.

Both GPOs are linked to
`OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local`, with SID translation
at link order `1` and scoped RPC exposure at link order `2`. The role does not
modify Default Domain Policy or Default Domain Controllers Policy.

Live hostname, domain and machine-role checks precede mutations. The scripts
compare current state, support Ansible check mode, and only commit differences.
After provisioning, WINTERFELL performs a computer-policy refresh. Provisioning
fails unless the effective state is all of the following:

- `LSAAnonymousNameLookup=1`
- `RestrictNullSessAccess=1`
- `NullSessionPipes` contains exactly `samr` and `lsarpc`
- `NullSessionShares` contains no non-empty entries

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
directly reachable in exercise mode; this command does not switch router modes.
Omit `--install-prerequisites` when system packages are already present. There is
no Windows rebuild or full-install replay.

During the targeted playbook, the two dedicated NORTH GPOs are created or
repaired, linked on the NORTH Domain Controllers OU, and followed by
`gpupdate /target:computer /force` on WINTERFELL. The playbook then verifies the
merged SID-translation policy and the effective LanmanServer anonymous-RPC
registry state before moving on. This prevents two earlier classes of drift:
Group Policy resetting `LSAAnonymousNameLookup`, and the walkthrough expecting
SAMR/LSARPC operations that the live NULL-session pipe list no longer exposes.

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
it uses the existing forest credential. The GPO tasks suppress output because
they use the NORTH domain administrator credential. The policy refresh is local
to WINTERFELL; allow normal forest replication before checking other DCs for the
separate forest-wide LDAP setting.

## Final readiness check

```bash
bash scripts/validate-phase01.sh
```

Run from the Kali/operator network with NORTH reachable. Defaults are WINTERFELL
`10.4.10.11`, CASTELBLACK `10.4.10.22`, WS01 `10.4.10.31`; `--dc`, `--server` and
`--ws01` override addresses. All probes have a timeout. Each run creates a new,
private `~/kingdoms-phase01-TIMESTAMP/` with raw evidence, `results.json` and
`SUMMARY.txt`. Send `SUMMARY.txt` first. A missing tool, timeout, partial result
or inconclusive denial fails readiness; no stale output is reused.

The validator checks the protocol capabilities the walkthrough depends on, not
just whether provisioning completed. On WINTERFELL it requires anonymous
`lsaquery`, SID-to-name translation, `enumdomusers`, `enumdomgroups`, focused
`queryuser`/`querygroup` calls and `getdompwinfo`. It separately requires
anonymous LDAP user/group visibility and the seeded Samwell description leak.
Normal NULL share listing remains a separate negative boundary and is not treated
as proof of RPC availability.

### NULL SMB boundary and selected RPC exposure

The 12 September 2026 live baseline showed why these checks must remain separate.
Explicit empty-username/password share-list probes produced:

| Host | NULL share-list request | Explicit Guest share-list request |
| --- | --- | --- |
| WINTERFELL | No share rows; exit zero, followed by failed SMB1 workgroup discovery | Rejected |
| CASTELBLACK | Session setup rejected with `NT_STATUS_ACCESS_DENIED` | Share names available |
| WS01 | Rejected | Rejected |

WINTERFELL's no-names result does not prove access to ordinary shares or identify
the server-side SMB session token. Phase 01 therefore keeps normal NULL share
visibility restricted while deliberately exposing only the `samr` and `lsarpc`
named pipes needed by the curriculum. Anonymous LDAP is configured independently.
Students can consequently observe that SMB share authorization, RPC named-pipe
authorization, SID/name translation and LDAP anonymous access are separate
Windows/AD security decisions.

The legacy SMB1 workgroup lookup is separate from share visibility and is not a
readiness requirement. The classifier requires share rows for visibility,
explicit rejection for denied access, and evidence of the workgroup phase for
the no-names result. Empty output and network/tool failures remain inconclusive
and fail the check.

Checks also cover real RID mapping, RootDSE, user/group attributes, Samwell's
exact seeded description, the expected NULL/Guest share-listing matrix, Guest
listing files on `all`, public HTTP, the internal authentication boundary, NTLM
identity and valid/invalid Kerberos usernames. SMB requests use an explicit empty
username and password for NULL mode. They report requested credentials and
observed share access, **not** server-side session flags. No share write test is
performed; write capability and full Null/Guest identity attribution are not
certified by this validator. Earlier AS-REP, Kerberoasting, SQL and RDP results
are not rerun.

Provisioning completion is not proof of live lesson readiness. The source and
parser tests can run without VMware; Windows behavior, effective policy after
GPO refresh, second-run idempotence and fresh-install readiness require the live
Kingdoms lab.

## References

- [Microsoft: IPC$ share and null session behavior](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/inter-process-communication-share-null-session)
- [Microsoft: Named Pipes that can be accessed anonymously](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/network-access-named-pipes-that-can-be-accessed-anonymously)
- [Microsoft: Restrict anonymous access to Named Pipes and Shares](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/network-access-restrict-anonymous-access-to-named-pipes-and-shares)
- [Microsoft: anonymous LDAP operations and preservation of dSHeuristics](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/anonymous-ldap-operations-active-directory-disabled)
- [Microsoft: anonymous SID/name translation](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/jj852193(v=ws.11))
- [Microsoft: Group Policy Security Settings CSE identifiers](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gpsb/55bb803e-b35f-4ce8-b558-4c1e92ad77a4)
- [Microsoft: IIS Windows Authentication](https://learn.microsoft.com/en-us/iis/configuration/system.webserver/security/authentication/windowsauthentication/)
- [Nmap: HTTP NTLM information and the root path argument](https://nmap.org/nsedoc/scripts/http-ntlm-info.html)
- [Kerbrute upstream v1.0.3 source](https://github.com/ropnop/kerbrute/tree/9dad6e171abdc7491f587c793aa05411264a3393)
