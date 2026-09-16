# Phase 01: unauthenticated enumeration

This is intentionally vulnerable **GOAD Kingdoms lab provisioning**. The GOAD
install sequence runs `phase01.yml` after ACLs, IIS content, security and existing
vulnerabilities. Other scenarios do not receive this stage. Targeted replay uses
only `dc02` and `srv02`; it does not gather facts from WS01 or other zones.

The Phase 01 source is also a **curriculum contract**: a fresh Kingdoms lab must
support the unauthenticated techniques taught in `01 - Outside The Wall` without
requiring the student to edit Windows policy, the registry, GPOs or lab modes.
The runtime validator therefore checks the underlying protocol paths required by
the walkthrough rather than treating one successful NULL operation as proof that
all anonymous access is available.

| Change | Location | Intended result |
| --- | --- | --- |
| `LSAAnonymousNameLookup=1` | Dedicated `Kingdoms - Phase 01 - Anonymous SID Translation` GPO linked to the NORTH Domain Controllers OU at link order 1 | Anonymous SID/name translation that survives Group Policy refresh |
| Scoped NULL RPC settings | Dedicated `Kingdoms - Phase 01 - Anonymous RPC Exposure` GPO linked to the NORTH Domain Controllers OU at link order 2 | Anonymous `lsarpc`/`samr` curriculum paths while normal NULL share listing remains restricted |
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

Anonymous SID/name translation is deliberately managed through a dedicated
NORTH Group Policy object instead of WINTERFELL's local security database. The
policy is linked to `OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local`
at link order `1`, giving the intentionally vulnerable setting precedence over
other policy at the same OU. The role does not modify Default Domain Policy or
Default Domain Controllers Policy. The SID-translation GPO contains only the
Security Settings client-side extension and the `LSAAnonymousNameLookup=1`
security-template entry.

The anonymous RPC lesson is managed independently by `Kingdoms - Phase 01 -
Anonymous RPC Exposure`. Its registry policy keeps `RestrictNullSessAccess=1`
and `EveryoneIncludesAnonymous=0`, explicitly allows the NULL-session account
surface required by the course (`RestrictAnonymous=0`, `RestrictAnonymousSAM=0`)
and restricts `NullSessionPipes` to exactly `samr` and `lsarpc`. It does not add
`NullSessionShares`, enable SMB1 or make ordinary file shares anonymously
readable. This separation is intentional: SID/name translation, named-pipe RPC
access and anonymous LDAP are distinct Windows/AD controls and are taught as
separate attack-surface decisions.

Live hostname, domain and machine-role checks precede mutations. The scripts
compare current state, support Ansible check mode, and only commit differences.
The GPO content, registry policy and link state are idempotent. After
provisioning, WINTERFELL performs a computer-policy refresh; the role then
verifies both `LSAAnonymousNameLookup=1` and the exact effective anonymous-RPC
registry state. The LDAP write is also read back. Run the targeted playbook a
second time to prove live idempotence: expect `changed=0`, `failed=0`,
`unreachable=0`. Check mode skips the live policy refresh and effective-policy
assertions because it performs no changes.

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

During the targeted playbook, the dedicated NORTH SID-translation and
anonymous-RPC GPOs are created or repaired and linked ahead of the default Domain
Controllers policy, followed by `gpupdate /target:computer /force` on
WINTERFELL. The playbook then verifies the merged/effective settings before
moving on. This prevents the earlier failure mode where a later Group Policy
refresh reset a local `LSAAnonymousNameLookup=1` value back to `0` and also makes
the RPC surface required by the walkthrough an explicit, reproducible part of
the lab instead of an accidental Windows baseline.

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

The runtime contract now verifies the anonymous RPC lessons independently:
`lsaquery`, SID-to-name translation, `enumdomusers`, `queryuser`,
`enumdomgroups`, `querygroup` and `getdompwinfo` must all produce real protocol
evidence. Those checks sit alongside anonymous LDAP, the NULL/Guest share matrix,
CASTELBLACK Guest file access, the HTTP authentication boundary, NTLM identity
and Kerberos username enumeration. This means a future build cannot claim Phase
01 readiness merely because RID translation works while SAMR password-policy or
user/group enumeration is broken.

The persistence regression is: apply Phase 01, force a computer Group Policy
refresh on WINTERFELL, and rerun the validator. Anonymous SID/name translation
and the selected LSA/SAMR curriculum operations must remain available; normal
NULL share listing must remain restricted.

### Corrected live SMB baseline (12 September 2026)

The initial validator incorrectly required NULL share names from both servers.
Explicit empty-username/password probes produced the following evidence:

| Host | NULL share-list request | Explicit Guest share-list request |
| --- | --- | --- |
| WINTERFELL | No share rows; exit zero, followed by failed SMB1 workgroup discovery | Rejected |
| CASTELBLACK | Session setup rejected with `NT_STATUS_ACCESS_DENIED` | Share names available |
| WS01 | Rejected | Rejected |

WINTERFELL's no-names result is an observation only; it does not prove access to
shares or the identity assigned to the SMB session. Selected anonymous RPC
operations are tested independently and do not imply anonymous file-share
visibility. The legacy SMB1 workgroup lookup is separate from share visibility
and is not a readiness requirement. No SMB1 enablement follows from these
results. The classifier requires share rows for visibility, explicit rejection
for denied access, and evidence of the workgroup phase for the no-names result.
Empty output and network/tool failures remain inconclusive and fail the check.

No share write test is performed; write capability and full Null/Guest identity
attribution are not certified by this validator. Earlier AS-REP, Kerberoasting,
SQL and RDP results are not rerun because the Phase 01 readiness check is bounded
to the unauthenticated enumeration curriculum surface.

Provisioning completion is not proof of live lesson readiness. The source and
parser tests can run here; Windows behavior, effective policy after GPO refresh,
second-run idempotence and fresh-install readiness require the VMware lab.

## References

- [Microsoft: anonymous LDAP operations and preservation of dSHeuristics](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/anonymous-ldap-operations-active-directory-disabled)
- [Microsoft: anonymous SID/name translation](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/jj852193(v=ws.11))
- [Microsoft: Group Policy Security Settings CSE identifiers](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gpsb/55bb803e-b35f-4ce8-b558-4c1e92ad77a4)
- [Microsoft: IIS Windows Authentication](https://learn.microsoft.com/en-us/iis/configuration/system.webserver/security/authentication/windowsauthentication/)
- [Nmap: HTTP NTLM information and the root path argument](https://nmap.org/nsedoc/scripts/http-ntlm-info.html)
- [Kerbrute upstream v1.0.3 source](https://github.com/ropnop/kerbrute/tree/9dad6e171abdc7491f587c793aa05411264a3393)
