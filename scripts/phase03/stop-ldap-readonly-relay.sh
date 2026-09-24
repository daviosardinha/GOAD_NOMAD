#!/usr/bin/env bash
# Stop only the Phase 03 read-only ntlmrelayx instance.
set -uo pipefail

pattern='(^|[ /])(impacket-ntlmrelayx|ntlmrelayx[.]py)([ ]|$)'
mapfile -t pids < <(pgrep -f "$pattern" 2>/dev/null || true)

if (( ${#pids[@]} == 0 )); then
  echo 'PASS: no ntlmrelayx process is running'
  exit 0
fi

printf 'Stopping ntlmrelayx PID(s): %s\n' "${pids[*]}"
sudo kill -TERM "${pids[@]}" 2>/dev/null || true
sleep 2

mapfile -t pids < <(pgrep -f "$pattern" 2>/dev/null || true)
if (( ${#pids[@]} > 0 )); then
  printf 'Escalating ntlmrelayx PID(s): %s\n' "${pids[*]}"
  sudo kill -KILL "${pids[@]}" 2>/dev/null || true
  sleep 1
fi

if pgrep -f "$pattern" >/dev/null 2>&1; then
  echo 'FAIL: ntlmrelayx is still running' >&2
  exit 1
fi

echo 'PASS: ntlmrelayx stopped'
