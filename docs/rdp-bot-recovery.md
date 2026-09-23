# Kingdoms RDP bot: independent recovery work

Status: **design and read-only prerequisite gate only**. This branch deliberately
does not replace, disable or modify the live \connect_bot task. Do not mark the
bot repaired until the full acceptance sequence below is demonstrated on a
running instance and after an untouched fresh deployment.

## Evidence and failure mode

The scoped RDP contract allows only NORTH\\robb.stark on CASTELBLACK and
NORTH\\rickon.stark on WS01. The existing WINTERFELL task executes every minute
using password logon; the observed mstsc.exe ran as Robb in Windows Session 0.
The installed ad/GOAD/files/dc02/bot_rdp.ps1 tests for *any* remote Robb
session. It cannot distinguish Active from Disc, nor establish robust recovery
when it cannot remotely enumerate another host's sessions. The live host
repeatedly showed Robb's session as Disc although policy allowed the login.

A manually established FreeRDP session did pass the session-required and
Phase 01 regression when both desktop sessions remained connected. The
user-supplied results therefore verify Robb's authorization, not the
autonomous WINTERFELL bot lifecycle.

Windows Task Scheduler's InteractiveToken mode requires an already logged-on
user. Changing the existing password-logon task to InteractiveToken does not
solve unattended boot after a clean deployment and must not be used as a
drop-in repair.

## Proposed architecture to validate

Run a single headless FreeRDP client under Xvfb on the existing Linux operator
host connected to NORTH over vmnet10 (10.4.10.254). Use a supervisor with a
bounded retry delay. Store credentials outside source control with owner-only
permissions; use FreeRDP /from-stdin instead of a password in argv or logs.
Restrict the target to CASTELBLACK (10.4.10.22) and the identity to
NORTH\\robb.stark. This introduces no new VM and does not grant RDP to Robb on
WINTERFELL. Do not start the candidate alongside the legacy bot, because
competing Robb clients can disconnect each other's session.

The existing bot remains untouched until we have proved that the operator
host has the required packages and route, and reviewed an explicit rollback
procedure. Use the non-mutating check from the repository root:

`bash scripts/check-rdp-bot-prereqs.sh`

Only after prerequisites pass should a *separate reviewed change* add the
supervised runner, installation instructions and an explicit old-bot
handover. Do not bake operator-host credentials into Ansible, the repo, a
systemd unit or its command line. Do not change domain groups, RDP rights,
GPOs or the Phase 03 RBCD fixture.

## Acceptance contract for the subsequent implementation

1. Capture a backup of the existing WINTERFELL task, a CASTELBLACK snapshot
   and the pre-handover RDP authorization/session evidence. The old task stays
   enabled during read-only prerequisite testing.
2. Explicitly stop and disable only the old bot during a controlled
   handover; never terminate unrelated mstsc or RDP sessions. Do not run
   manual FreeRDP concurrently with the headless bot.
3. Demonstrate an unattended headless Robb RDP connection and an **Active**
   CASTELBLACK session, then force a controlled client disconnect and prove
   bounded automatic reconnection without changing the server's RDP policy.
4. Verify Rickon's independent WS01 session and rerun
   `validate-rdp-runtime.sh --require-sessions --phase01` while the new
   headless bot is the *only* Robb client. An active connection must stay
   stable for the agreed observation period.
5. Reboot/restart the operator host and demonstrate unattended recovery;
   test the documented rollback and ensure the prior bot can be restored.
   Repeat on a fresh installation. The new supervisor must not touch the
   Phase 03 RBCD apply/reset lifecycle.
6. If the course ultimately requires a Windows-native authentication trigger,
   add that as an explicit separate exercise; don't misrepresent a Linux
   operator-host RDP client as a WINTERFELL-origin session.

Nothing in this design alone proves a future bot will pass. Do not merge the
implementation before the live and clean-install evidence exists.
