#!/usr/bin/env bash
# Controlled restart proof for the permanent Phase 03 Rickon -> WS01 victim service.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
SERVICE='kingdoms-phase03-rickon.service'
WS01='10.4.10.31'
VALIDATOR="$ROOT/scripts/phase03/validate-rickon-session.sh"

cd "$ROOT" || exit 1

old_main="$(systemctl --user show "$SERVICE" -p MainPID --value)"
old_socket="$(sudo ss -ntp 2>/dev/null | grep "${WS01}:3389" || true)"
old_freerdp="$(sed -n 's/.*pid=\([0-9]\+\).*/\1/p' <<<"$old_socket" | head -n1)"
old_runner="$(
  pgrep -P "$old_main" -f '/usr/bin/xvfb-run|xvfb-run' 2>/dev/null |
    head -n1
)"
old_xvfb=""
if [[ "$old_runner" =~ ^[1-9][0-9]*$ ]]; then
  old_xvfb="$(
    ps -eo pid=,ppid=,comm= |
      awk -v p="$old_runner" '$2 == p && $3 == "Xvfb" {print $1; exit}'
  )"
fi

echo '===== BEFORE ====='
printf 'MainPID=%s\nRunner_PID=%s\nFreeRDP_PID=%s\nXvfb_PID=%s\n' "$old_main" "$old_runner" "$old_freerdp" "$old_xvfb"
printf '%s\n' "$old_socket"

[[ "$old_main" =~ ^[1-9][0-9]*$ ]] || {
  echo 'FAIL: current Rickon systemd MainPID is invalid' >&2
  exit 1
}
[[ "$old_runner" =~ ^[1-9][0-9]*$ ]] || {
  echo 'FAIL: could not identify xvfb-run child of the Rickon service MainPID' >&2
  ps -o pid,ppid,stat,etime,cmd --forest -g "$(ps -o sid= -p "$old_main" | tr -d ' ')" 2>/dev/null || true
  exit 1
}
[[ "$old_freerdp" =~ ^[1-9][0-9]*$ ]] || {
  echo 'FAIL: could not identify FreeRDP from the WS01 socket' >&2
  exit 1
}
[[ "$old_xvfb" =~ ^[1-9][0-9]*$ ]] || {
  echo 'FAIL: could not identify Xvfb child of xvfb-run' >&2
  ps -eo pid,ppid,stat,comm,args | awk -v p="$old_runner" '$2 == p || $1 == p'
  exit 1
}

echo
echo '===== CONTROLLED RESTART ====='
systemctl --user restart "$SERVICE"
sleep 8

new_main="$(systemctl --user show "$SERVICE" -p MainPID --value)"
new_socket="$(sudo ss -ntp 2>/dev/null | grep "${WS01}:3389" || true)"
new_freerdp="$(sed -n 's/.*pid=\([0-9]\+\).*/\1/p' <<<"$new_socket" | head -n1)"

echo
echo '===== AFTER ====='
printf 'MainPID=%s\nFreeRDP_PID=%s\n' "$new_main" "$new_freerdp"
printf '%s\n' "$new_socket"

[[ "$new_main" =~ ^[1-9][0-9]*$ && "$new_main" != "$old_main" ]] || {
  echo 'FAIL: systemd MainPID did not change after restart' >&2
  exit 1
}

[[ "$new_freerdp" =~ ^[1-9][0-9]*$ && "$new_freerdp" != "$old_freerdp" ]] || {
  echo 'FAIL: FreeRDP PID did not change after restart' >&2
  exit 1
}

if kill -0 "$old_main" 2>/dev/null; then
  echo "FAIL: old service MainPID still exists: $old_main" >&2
  exit 1
fi

if kill -0 "$old_freerdp" 2>/dev/null; then
  echo "FAIL: old FreeRDP PID still exists: $old_freerdp" >&2
  exit 1
fi

if kill -0 "$old_runner" 2>/dev/null; then
  echo "FAIL: old xvfb-run PID still exists: $old_runner" >&2
  exit 1
fi

if kill -0 "$old_xvfb" 2>/dev/null; then
  echo "FAIL: old Xvfb PID still exists: $old_xvfb" >&2
  exit 1
fi

echo 'PASS: old Rickon process tree, xvfb-run and Xvfb were cleaned up'
echo

bash "$VALIDATOR"
