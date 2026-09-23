#!/usr/bin/env bash
# Single-shot, opt-in headless RDP client for the dedicated NORTH training bot.
# The user-level systemd unit (not this script) supervises restarts.
# Does not contact WINTERFELL or change the existing Windows connect_bot task.
set -Eeuo pipefail
umask 077

readonly TARGET_IP='10.4.10.22'
readonly EXPECTED_INTERFACE='vmnet10'
readonly EXPECTED_SOURCE='10.4.10.254'
readonly CREDENTIAL_FILE="${KINGDOMS_RDP_BOT_SECRET_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/kingdoms/robb-rdp.password}"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -ne 0 ]] || fail 'Run the bot under the unprivileged Kali operator account, never sudo.'
for cmd in ip stat xvfb-run xfreerdp3; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing prerequisite: $cmd"
done

# Do not resolve alternate destinations or leave the dedicated NORTH interface.
route="$(ip -4 route get "$TARGET_IP" 2>/dev/null)" || fail 'Cannot find the NORTH route.'
[[ " $route " == *" dev $EXPECTED_INTERFACE "* &&
   " $route " == *" src $EXPECTED_SOURCE "* ]] ||
    fail 'NORTH route changed: expected CASTELBLACK via vmnet10 from 10.4.10.254.'

# Never accept credentials on argv or in the process environment. A single
# newline-terminated file is read on stdin by FreeRDP, not by the shell.
[[ -f "$CREDENTIAL_FILE" && ! -L "$CREDENTIAL_FILE" && -r "$CREDENTIAL_FILE" ]] ||
    fail 'Create a readable, non-symlink, owner-only credential file before running.'
[[ "$(stat -c '%u' -- "$CREDENTIAL_FILE")" == "$(id -u)" ]] ||
    fail 'Credential file must be owned by the operator account.'
mode="$(stat -c '%a' -- "$CREDENTIAL_FILE")" || fail 'Cannot stat credential file.'
(( (8#$mode & 8#077) == 0 )) || fail 'Credential file grants group/other access (use chmod 600).'
[[ -s "$CREDENTIAL_FILE" ]] || fail 'Credential file is empty.'

printf '[INFO] Starting a single NORTH\\robb.stark headless session to CASTELBLACK; credentials are read from stdin.\n'
# TOFU pins the first observed certificate. Confirm the target certificate by
# a trusted management channel before handover; a changed pin must fail closed.
# The -clipboard option disables clipboard redirection in this dedicated session.
exec xvfb-run -a -s '-screen 0 1280x800x24 -nolisten tcp' \
    xfreerdp3 /v:"$TARGET_IP" /d:NORTH /u:robb.stark \
    /from-stdin:force /cert:tofu /size:1280x800 /audio-mode:2 \
    -clipboard /log-level:ERROR < "$CREDENTIAL_FILE"
