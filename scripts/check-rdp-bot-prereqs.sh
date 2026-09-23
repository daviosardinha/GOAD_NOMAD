#!/usr/bin/env bash
# Kingdoms RDP bot: read-only Linux operator-host prerequisite check.
# Does NOT connect to Windows, read credentials or modify the legacy bot.
set -euo pipefail

TARGET_IP=10.4.10.22
EXPECTED_INTERFACE=vmnet10
EXPECTED_SOURCE=10.4.10.254
failures=0
ok() { printf '[PASS] %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*" >&2; failures=$((failures + 1)); }

for executable in xfreerdp3 xvfb-run Xvfb xauth ip stat; do
    if command -v "$executable" >/dev/null 2>&1; then
        ok "$executable: $(command -v "$executable")"
    else
        bad "Missing $executable"
    fi
done

if command -v ip >/dev/null 2>&1; then
    route="$(ip -4 route get "$TARGET_IP" 2>&1)" || route=""
    printf '[INFO] CASTELBLACK route: %s\n' "$route"
    if [[ " $route " == *" dev $EXPECTED_INTERFACE "* &&
          " $route " == *" src $EXPECTED_SOURCE "* ]]; then
        ok "Lab route uses $EXPECTED_INTERFACE and source $EXPECTED_SOURCE"
    else
        bad "CASTELBLACK route must use $EXPECTED_INTERFACE from $EXPECTED_SOURCE; do not run bot outside the NORTH lab"
    fi
fi

if command -v xfreerdp3 >/dev/null 2>&1; then
    help_text="$(xfreerdp3 /help 2>&1 || true)"
    if [[ "$help_text" == *"/args-from"* ]]; then
        ok "FreeRDP supports argument input over stdin/file descriptors"
    else
        bad "FreeRDP /args-from support not confirmed; no password will be passed on the process command line"
    fi
    if [[ "$help_text" == *"fingerprint"* ]]; then
        ok "FreeRDP supports explicit certificate fingerprint pinning"
    else
        bad "FreeRDP certificate fingerprint pinning support not confirmed"
    fi
fi

if [[ "$failures" -ne 0 ]]; then
    printf '[FAIL] %s prerequisite(s) missing or unsafe; no lab state was changed\n' "$failures" >&2
    exit 1
fi
printf '[PASS] Headless RDP bot prerequisites satisfied; no lab state was changed\n'
