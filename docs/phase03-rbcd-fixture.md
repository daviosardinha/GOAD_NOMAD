# Kingdoms Phase 03 — CASTELBLACK RBCD attribute fixture (draft)

Branch: kingdom/phase03-rbcd-fixture (dependent on kingdoms/rdp-access-contract).
This is an opt-in, NORTH-only feature branch. Do **not** merge or import the
playbook into ansible/main.yml until the runtime acceptance below passes.

## Why this fixture is necessary

- WINTERFELL (10.4.10.11) accepts the observed controlled Rickon HTTP-to-LDAP
  and HTTP-to-LDAPS relay. The latter is our intended interactive LDAP session.
- CASTELBLACK (10.4.10.22) can be coerced via MS-RPRN and returns NTLM as its
  machine account, but Impacket reported that the incoming SMB session requested
  signing. That SMB-to-LDAP relay was **not** demonstrated; do not claim that it
  succeeded or weaken signing as a workaround.
- The original CASTELBLACK and WS01 computer-object RBCD attributes were empty.
  No existing Rickon-to-CASTELBLACK WriteProperty ACE was identified in the
  read-only audit. NORTH's machine-account quota was measured at 10.
- Important tool limitation: ntlmrelayx's automatic --delegate-access attack
  requires a relayed *computer* account. It is **not** a valid automatic RBCD
  command for Rickon's relayed HTTP user context. This lesson uses the supported
  interactive LDAP shell's add_computer and set_rbcd commands instead.

## Scope and stored preimage

The playbook is ansible/phase03-rbcd.yml. It contacts only the inventory's
dc02, checks that the guest is WINTERFELL in NORTH, and resolves the exact
CASTELBLACK object in the default NORTH Computers container. The operator
must explicitly pin an existing VMware workspace with --instance; nothing
ever selects the currently running or most recently created instance implicitly.

APPLY adds a single explicit, non-inherited Allow / WriteProperty ACE for
NORTH\rickon.stark, restricted to attribute
msDS-AllowedToActOnBehalfOfOtherIdentity (schema GUID
3f78c3e5-f79a-46bd-a0b8-9d18116ddc79), on CASTELBLACK's computer object.
It adds no GenericAll, WriteDacl, group memberships, GPOs, service permission,
DNS change, or change to WS01. APPLY refuses an occupied RBCD attribute,
pre-existing fixture ACE or a pre-existing K03RBCD$ account on first use.

Before modifying the ACL it writes a fail-closed preimage ledger to the DC's
C:\ProgramData\GOAD-Kingdoms\phase03-rbcd\castelblack-preimage.json. The
directory is intended to be SYSTEM/Administrators-only. The ledger records
CASTELBLACK's object GUID, Rickon's SID and the original and installed DACL
SDDL. In this first version, the *original RBCD attribute must be absent*;
the fixture explicitly refuses to overwrite an existing RBCD value. The
initial DACL must match exactly when resetting; unrelated DACL changes
cause an abort for manual review rather than a destructive restore.

The reserved lesson account name K03RBCD$ must be **absent** before APPLY.
The optional training account may be created through the relayed Rickon
LDAP session; RESET removes it only if its name, DN, group membership and
mS-DS-CreatorSID prove it is the account Rickon created for this exercise.
RESET also checks that any RBCD descriptor has exactly that account as its
sole trustee. A different trustee or unrelated AD change stops automated
cleanup. Never delete arbitrary machine accounts or clear a pre-existing
delegation attribute merely to make this lesson pass.

## Source-first deployment

Complete the existing RDP-contract PR acceptance independently; this
feature branch currently layers on top of it. Use Git as the only source
of testable code. Do not fix repository code directly in the test checkout.
Inspect and preserve any untracked or edited local files before switching
branches: the mandatory source gate rejects a dirty checkout.

From the exact upstream-synchronized checkout of this feature branch:

    bash scripts/verify-test-source.sh
    python3 -m unittest discover -s tests -p 'test_phase03_rbcd*.py'

The known-good runtime reference is cebee3-goad-vmware. Preserve the
running VMs and their snapshots; do not destroy or reset the instance
to clear a single exercise. To inspect current state and preview changes:

    bash scripts/phase03-rbcd.sh audit --instance cebee3-goad-vmware
    bash scripts/phase03-rbcd.sh apply --instance cebee3-goad-vmware --check

Only after the audit confirms **no existing RBCD** and zero fixture ACEs,
and the normal lab snapshot is retained, apply the isolated change:

    bash scripts/phase03-rbcd.sh apply --instance cebee3-goad-vmware
    bash scripts/phase03-rbcd.sh apply --instance cebee3-goad-vmware
    bash scripts/phase03-rbcd.sh audit --instance cebee3-goad-vmware

The second APPLY must return zero changes; the read-only audit must report
one exact ACE and no RBCD attribute before exercise execution.

## Controlled lesson proof

1. Start an HTTP-only ntlmrelayx listener on Kali that targets
   ldaps://10.4.10.11 in interactive mode. Disable automatic directory
   dump, Domain Admin, ACL and other attack modes.
2. In Rickon's existing WS01 session, deliberately authenticate to the
   controlled HTTP listener using his own default Windows credentials.
   Observe a successful LDAPS relay as NORTH\RICKON.STARK. This is NOT
   automatic WPAD NTLM authentication, which wasn't demonstrated.
3. Connect to the local interactive LDAP shell exposed by ntlmrelayx.
   Inspect the help output for add_computer and set_rbcd. Use the known
   exercise name K03RBCD$ for the new computer created as Rickon, keep
   its generated secret out of screenshots, then authorize that account
   on CASTELBLACK with set_rbcd.
4. Validate the resulting RBCD security descriptor on WINTERFELL. Stop
   before Kerberos service-ticket or impersonation actions; those need
   a separate, explicit lesson proof.
5. Use the guarded reset below. Do not run bulk domain cleanup or
   delete arbitrary machine accounts.

If any intermediate operation fails, do not rerun the entire chain
blindly; audit the current object and ledger first.

## Reset and regression gate

    bash scripts/phase03-rbcd.sh audit --instance cebee3-goad-vmware
    bash scripts/phase03-rbcd.sh reset --instance cebee3-goad-vmware --check
    bash scripts/phase03-rbcd.sh reset --instance cebee3-goad-vmware
    bash scripts/phase03-rbcd.sh reset --instance cebee3-goad-vmware
    bash scripts/phase03-rbcd.sh audit --instance cebee3-goad-vmware

RESET checks object identity, ACL drift, the RBCD trustee and the
training-computer creator before any destructive change. It restores the
original empty RBCD state, removes only the exact fixture ACE and,
only when its ownership is proven, deletes K03RBCD$. The second RESET
must change nothing. Failure or ambiguity requires manual investigation
while preserving the preimage file.

Verify the preexisting Phase 00–02 gates, WINTERFELL's scheduled bots,
Rickon's WS01 RDP foothold, CASTELBLACK MSSQL access, segmentation,
existing ADCS placement and WS01 LPE fixtures. Do not import this
fixture into fresh-install provisioning until those checks pass.
Record runtime proof in Kingdoms Notion 03 only after the committed
source has been tested on the lab.
