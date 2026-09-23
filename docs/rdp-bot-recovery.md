# Kingdoms RDP bot: isolated headless recovery candidate

Status: **operator prerequisites passed on Kali; candidate implemented in source,
not installed or live-tested**. This branch never automatically replaces,
disables or modifies the WINTERFELL `connect_bot` task. Do not mark the bot
repaired until its runtime and fresh-install acceptance tests pass.

This work is separate from the Phase 03 RBCD fixture and protected NORTH RDP
contract. It adds no VM and makes no changes to domain groups, RDP permissions,
Phase 01 settings, GPOs or RBCD.

## Root-cause evidence

The existing WINTERFELL `connect_bot` runs as NORTH\\robb.stark using Task
Scheduler password logon. Its observed `mstsc.exe` runs in Windows Session 0,
rather than a user's interactive desktop. The original
`ad/GOAD/files/dc02/bot_rdp.ps1` checks only whether a remote Robb session
exists, so it incorrectly treats CASTELBLACK's `Disc` state as healthy.
A remote `quser` from the existing task also returned access denied.

Robb's manually created FreeRDP session, with Rickon's WS01 session open,
passed the existing `--require-sessions --phase01` regression. That proves
authorization and live session evidence during that run, **not automatic bot
recovery**. Avoid changing the source validator to accept disconnected sessions.

Changing the old Task Scheduler task to `InteractiveToken` alone is not an
unattended fix: that logon type needs a user to be logged on to WINTERFELL.

## Candidate implementation

- `scripts/rdp-bot-headless.sh`: single-shot Xvfb + FreeRDP3 client, restricted
  to CASTELBLACK `10.4.10.22` via `vmnet10` from `10.4.10.254`, using
  `NORTH\\robb.stark`.
- `ops/systemd/kingdoms-rdp-bot.service`: **opt-in** systemd **user** service,
  with restart delay 120 seconds, maximum three starts per hour. This rate
  limit prevents rapid retry loops on bad credentials. It can require manual
  restart after the limit is hit; check the journal.
- `scripts/check-rdp-bot-prereqs.sh`: non-mutating package, routing and
  credential-stdin support check.
- `tests/test_rdp_bot_runner.py`: mocked offline execution and negative
  checks, including restrictive file permissions and rejection of an
  unexpected network source.

The FreeRDP password is read from a local user-owned credential file through
`/from-stdin:force`. It is never stored in this branch, the systemd unit,
process arguments or the command history. The file does remain readable to
the account that runs the bot and anyone with sufficient local privileges;
protect the Kali host and use a **lab-only** account. Set the file's mode to
0600 (0400 also works) and its parent directory to 0700.

FreeRDP uses `/cert:tofu`, not `/cert:ignore`. Trust on first use is *not*
independent certificate validation: check the server certificate fingerprint
through a trusted management channel before the first candidate connection.
A later unexpected certificate change must stop the rollout pending review.
After a legitimate lab rebuild, reverify the new fingerprint before
re-establishing trust. This service's source path assumes the operator checkout
is `~/Documents/GOAD_NOMAD`; edit the local unit if that changes.

**Important curriculum distinction:** the new client originates from the
Kali operator host, not WINTERFELL. If a future exercise explicitly needs
Windows-origin authentication from WINTERFELL, it needs a separate, scoped
traffic generator. Do not substitute this headless bot as evidence of
WINTERFELL-origin authentication.

## Gates and controlled handover

All commands below are single-line examples from the dedicated Kali
operator. Avoid copying commands that would start two Robb RDP clients.

**Gate 1 — offline/source tests only.** From the already checked-out
`kingdoms/rdp-bot-recovery` branch, after normal source verification:

`python3 -m unittest discover -s tests -p 'test_rdp_bot_*.py'`

`bash scripts/check-rdp-bot-prereqs.sh`

No Windows state changes occur during Gate 1. Stop here if the source gate,
tests or prerequisite checks fail. Do not run the live bot yet.

**Gate 2 — preparation, after review.** Capture the existing WINTERFELL
scheduled-task XML and a normal lab snapshot first. A scheduled-task XML
export does not include its stored password, so the original authorized
operator must retain the existing recovery procedure. Capture the
CASTELBLACK session list and the original task principal, trigger and state.
Verify CASTELBLACK's RDP certificate fingerprint through a trusted channel.

Create the dedicated credential file interactively without entering the
password in command history:

`install -d -m 700 "$HOME/.config/kingdoms" && bash -c 'umask 077; IFS= read -rsp "Robb LAB password: " p; printf "\\n"; test -n "$p" && printf "%s\\n" "$p" > "$HOME/.config/kingdoms/robb-rdp.password"; unset p'`

Do not place any credentials inside the Git repository or an Ansible extra
var. Never paste its contents into evidence.

**Gate 3 — one-client handover, explicit operator action.** Before starting
the candidate, stop and disable only WINTERFELL's `connect_bot` task and
inspect/stop only its identified legacy Session 0 `mstsc.exe` process.
Close any manual Robb FreeRDP window. Keep Rickon's WS01 desktop and
management access available; do not terminate unrelated processes or log
off other users. Verify the old task is disabled and the legacy process gone.
Only then copy the user-unit template into
`~/.config/systemd/user/kingdoms-rdp-bot.service`, reload the user manager
and start it. The files in Git do not install or start themselves. To keep
a user service alive without an interactive Kali login, separately approve
and configure systemd user lingering; do not enable it implicitly.

**Gate 4 — live proof.** Confirm `quser` on CASTELBLACK shows Robb
`Active`. Keep Rickon's WS01 RDP session `Active` and run
`validate-rdp-runtime.sh --require-sessions --phase01` with the existing
runtime inventory while the new bot is the *only* Robb RDP client. Confirm
that Robb stays connected over an agreed observation interval. Force a
controlled client exit and measure automatic reconnection. A permanently
invalid password must not be retried in a tight loop. Review any failure
in `journalctl --user -u kingdoms-rdp-bot`.

**Gate 5 — rollback and release.** Stop and disable the *new* user service
first, then restore or enable only the original documented Windows task.
Verify no duplicate Robb RDP client exists. Repeat the apply/rollback on a
fresh-install instance, plus the complete 15-identity/host login matrix,
baseline Phase 00/01, SQL/DNS segmentation and RBCD apply/reset acceptance.
No test in this PR alone proves those live gates.

## Separation and limitations

This branch does not modify the legacy `bot_rdp.ps1` or
`rdp_scheduler.ps1`, does not touch Phase 03 RBCD configuration and is not
automatically installed by the existing GOAD Ansible pipeline. Updating
the bootstrap/fresh-install lifecycle is a subsequent reviewed step after
live candidate acceptance. The staged PR stays draft until that evidence
exists. The user-unit's restart limit intentionally trades continuous
retrying for protection against repeated invalid credential attempts.
