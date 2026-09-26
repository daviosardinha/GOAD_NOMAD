#!/usr/bin/env bash
# Diagnose detached ntlmrelayx TCP/80 listener ownership without triggering WS01.
# This helper performs no AD mutation and cleans up only relay PIDs it can
# positively attribute to this diagnostic launch.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
TARGET="${TARGET:-10.4.10.11}"
WORK="${WORK:-$HOME/.config/kingdoms/phase03-http-ldaps-diagnostic}"
LOG="$WORK/ntlmrelayx.log"
CANDIDATES="$WORK/candidate-pids.txt"

find_ntlmrelayx() {
  local c
  for c in \
    "$(command -v impacket-ntlmrelayx 2>/dev/null || true)" \
    "$(command -v ntlmrelayx.py 2>/dev/null || true)" \
    /usr/share/doc/python3-impacket/examples/ntlmrelayx.py; do
    [[ -n "$c" && ( -f "$c" || -x "$c" ) ]] || continue
    printf '%s\n' "$c"
    return 0
  done
  return 1
}

pid_cmdline() {
  local pid="$1"
  sudo sh -c "tr '\\0' ' ' < /proc/$pid/cmdline" 2>/dev/null || true
}

record_pid() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  printf '%s\n' "$pid" >>"$CANDIDATES"
  sort -nu -o "$CANDIDATES" "$CANDIDATES"
}

capture_candidate_pids() {
  local line pid

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    pid="${line%% *}"
    record_pid "$pid"
  done < <(pgrep -af 'impacket-ntlmrelayx|ntlmrelayx[.]py' 2>/dev/null || true)

  while IFS= read -r pid; do
    record_pid "$pid"
  done < <(
    sudo ss -H -lntp 'sport = :80' 2>/dev/null |
      grep -oE 'pid=[0-9]+' |
      cut -d= -f2 || true
  )
}

is_our_relay() {
  local pid="$1"
  local cmdline

  cmdline="$(pid_cmdline "$pid")"
  grep -Eqi 'ntlmrelayx' <<<"$cmdline" &&
    grep -Fq -- "ldaps://$TARGET" <<<"$cmdline"
}

cleanup() {
  local pid
  set +e

  [[ -f "$CANDIDATES" ]] || return 0

  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    sudo kill -0 "$pid" 2>/dev/null || continue

    if is_our_relay "$pid"; then
      echo "CLEANUP: stopping diagnostic ntlmrelayx PID=$pid"
      sudo kill -TERM "$pid" 2>/dev/null || true

      for _ in {1..10}; do
        sudo kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
      done

      if sudo kill -0 "$pid" 2>/dev/null; then
        echo "CLEANUP: escalating diagnostic ntlmrelayx PID=$pid"
        sudo kill -KILL "$pid" 2>/dev/null || true
      fi
    else
      echo "CLEANUP REFUSED: PID=$pid is alive but cannot be positively attributed to this diagnostic relay" >&2
      echo "CMDLINE=$(pid_cmdline "$pid")" >&2
    fi
  done <"$CANDIDATES"
}
trap cleanup EXIT INT TERM

cd "$ROOT"

echo '===== HTTP -> LDAPS LISTENER DIAGNOSTIC ====='
echo 'NOTE: this helper does NOT trigger WS01 authentication.'

branch="$(git branch --show-current 2>/dev/null || true)"
[[ "$branch" == "kingdoms/phase03-overlay" ]] || {
  echo "FAIL: unexpected branch: $branch" >&2
  exit 1
}

sudo -v

echo
echo '===== BASELINE ====='
echo '-- pgrep ntlmrelayx --'
pgrep -af 'impacket-ntlmrelayx|ntlmrelayx[.]py' || true

echo '-- TCP/80 via exact ss filter --'
sudo ss -H -lntp 'sport = :80' 2>&1 || true

echo '-- TCP/80 via all-listener scan --'
sudo ss -H -lntp 2>&1 | grep -E '(:|])80[[:space:]]' || true

if pgrep -af 'impacket-ntlmrelayx|ntlmrelayx[.]py' >/dev/null 2>&1; then
  echo 'FAIL: an ntlmrelayx process already exists; clean it before running this diagnostic' >&2
  exit 1
fi

if sudo ss -H -lntp 2>/dev/null | grep -Eq '(:|])80[[:space:]]'; then
  echo 'FAIL: TCP/80 is already occupied; clean it before running this diagnostic' >&2
  exit 1
fi

NTLMRELAYX="$(find_ntlmrelayx || true)"
[[ -n "$NTLMRELAYX" ]] || {
  echo 'FAIL: ntlmrelayx not found' >&2
  exit 1
}

command -v setsid >/dev/null 2>&1 || {
  echo 'FAIL: setsid not found' >&2
  exit 1
}

umask 077
rm -rf -- "$WORK"
mkdir -p "$WORK"
: >"$LOG"
: >"$CANDIDATES"
chmod 600 "$LOG" "$CANDIDATES"

echo
echo '===== LAUNCH ====='
echo "NTLMRELAYX=$NTLMRELAYX"
echo "TARGET=ldaps://$TARGET"
echo "LOG=$LOG"

sudo -n setsid -f stdbuf -oL -eL "$NTLMRELAYX" \
  -t "ldaps://$TARGET" \
  --no-dump \
  --no-da \
  --no-acl \
  --no-smb-server \
  --no-wcf-server \
  --no-raw-server \
  </dev/null >>"$LOG" 2>&1

echo
echo '===== SURVIVAL WINDOW ====='

for second in 1 2 3 4 5 6 7 8; do
  sleep 1
  capture_candidate_pids

  echo
  echo "----- t=${second}s -----"

  echo '[pgrep relay/python]'
  pgrep -af 'ntlmrelayx|python' || true

  echo '[ss exact sport=:80]'
  sudo ss -H -lntp 'sport = :80' 2>&1 || true

  echo '[ss all listeners matching :80]'
  sudo ss -H -lntp 2>&1 | grep -E '(:|])80[[:space:]]' || true

  echo '[process tree]'
  ps -eo pid,ppid,sid,pgid,user,stat,etime,args --forest |
    grep -E 'PID|ntlmrelayx|python|setsid' || true

  echo '[known candidate cmdlines]'
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    sudo kill -0 "$pid" 2>/dev/null || continue
    echo "--- PID=$pid ---"
    ps -o pid=,ppid=,sid=,pgid=,user=,stat=,etime=,args= -p "$pid" 2>/dev/null || true
    printf 'CMDLINE='
    pid_cmdline "$pid"
    printf '\n'
  done <"$CANDIDATES"

  echo '[relay log tail]'
  tail -n 40 "$LOG" 2>/dev/null || true
done

echo
echo '===== FINAL CANDIDATES ====='
cat "$CANDIDATES" || true

echo
echo '===== FINAL RELAY LOG ====='
cat "$LOG" || true

echo
echo 'PHASE03_HTTP_LDAPS_LISTENER_DIAGNOSTIC_COMPLETE=True'
