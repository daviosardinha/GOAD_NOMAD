#!/usr/bin/env bash
# Stop only the temporary Phase 03 WS01 WPAD/mitm6 runtime.
# Evidence files are intentionally preserved.
set -uo pipefail

IFACE="${IFACE:-vmnet10}"
PACDIR="${PACDIR:-/tmp/kingdoms-wpad}"
PCAP="${PCAP:-/tmp/kingdoms-wpad.pcap}"

stop_matching() {
  local label="$1"
  local pattern="$2"
  local -a pids=()

  mapfile -t pids < <(pgrep -f "$pattern" 2>/dev/null || true)

  if (( ${#pids[@]} == 0 )); then
    echo "PASS: $label is not running"
    return 0
  fi

  printf 'Stopping %s PID(s): %s\n' "$label" "${pids[*]}"
  sudo kill -TERM "${pids[@]}" 2>/dev/null || true
  sleep 2

  mapfile -t pids < <(pgrep -f "$pattern" 2>/dev/null || true)
  if (( ${#pids[@]} > 0 )); then
    printf 'Escalating %s PID(s): %s\n' "$label" "${pids[*]}"
    sudo kill -KILL "${pids[@]}" 2>/dev/null || true
    sleep 1
  fi

  mapfile -t pids < <(pgrep -f "$pattern" 2>/dev/null || true)
  if (( ${#pids[@]} > 0 )); then
    printf 'FAIL: %s still running: %s\n' "$label" "${pids[*]}" >&2
    return 1
  fi

  echo "PASS: $label stopped"
}

FAIL=0

echo '===== STOP MITM6 ====='
stop_matching   'scoped mitm6'   "(^|[ /])mitm6[ ]+-i[ ]+${IFACE}([ ]|$)" || FAIL=1

echo
echo '===== STOP WPAD HTTP SERVER ====='
stop_matching   'WPAD HTTP server'   "python3[ ]+-m[ ]+http[.]server[ ]+80[ ].*--directory[ ]+${PACDIR}([ ]|$)" || FAIL=1

echo
echo '===== STOP WPAD CAPTURE ====='
stop_matching   'WPAD tcpdump capture'   "tcpdump[ ].*-i[ ]+${IFACE}[ ].*-w[ ]+${PCAP}([ ]|$)" || FAIL=1

echo
echo '===== RELEVANT LISTENERS ====='
sudo ss -lntup | grep -E ':(80|53|547)\\b' || true

echo
echo '===== EXPECTED BASELINE NOTE ====='
echo 'dnsmasq on 127.0.0.1:53 / [::1]:53 is normal and should remain.'

exit "$FAIL"
