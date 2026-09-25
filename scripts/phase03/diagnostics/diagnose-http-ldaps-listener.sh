#!/usr/bin/env bash
# Diagnose detached ntlmrelayx TCP/80 listener ownership without triggering WS01.
# This helper performs no AD mutation and cleans up only the relay instance it starts.
set -euo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
TARGET="${TARGET:-10.4.10.11}"
WORK="${WORK:-$HOME/.config/kingdoms/phase03-http-ldaps-diagnostic}"
LOG="$WORK/ntlmrelayx.log"

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

relay_pids() {
  pgrep -f '(^|[ /])(impacket-ntlmrelayx|ntlmrelayx[.]py)([ ]|$)' 2>/dev/null || true
}

pid_cmdline() {
  local pid="$1"
  sudo sh -c "tr '\\0' ' ' < /proc/$pid/cmdline" 2>/dev/null || true
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
  for pid in ${STARTED_PIDS:-}; do
    [[ -n "$pid" ]] || continue
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
      echo "CLEANUP REFUSED: PID=$pid no longer matches diagnostic relay identity" >&2
    fi
  done
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

BEFORE="$(relay_pids)"
[[ -z "$BEFORE" ]] || {
  echo 'FAIL: an ntlmrelayx process already exists; refusing ambiguous diagnostic cleanup' >&2
  pgrep -af '(^|[ /])(impacket-ntlmrelayx|ntlmrelayx[.]py)([ ]|$)' >&2 || true
  exit 1
}

if sudo ss -H -lntp 2>/dev/null | grep -Eq '(^|[[:space:]])([^[:space:]]*:)?80[[:space:]]'; then
  echo 'FAIL: TCP/80 is already occupied' >&2
  sudo ss -H -lntp 2>/dev/null | grep -E '(:|])80[[:space:]]' >&2 || true
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

sudo -v
umask 077
rm -rf -- "$WORK"
mkdir -p "$WORK"
: >"$LOG"
chmod 600 "$LOG"

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

sleep 2
STARTED_PIDS="$(relay_pids)"
[[ -n "$STARTED_PIDS" ]] || {
  echo 'FAIL: detached launch produced no ntlmrelayx PID' >&2
  cat "$LOG" >&2 || true
  exit 1
}

echo
echo '===== PROCESS SNAPSHOT t=2s ====='
ps -eo pid,ppid,sid,pgid,user,stat,lstart,args --forest | grep -E 'PID|ntlmrelayx|python|setsid' || true

echo
echo '===== PGREP SNAPSHOT t=2s ====='
pgrep -af 'ntlmrelayx|python' || true

echo
echo '===== SS TCP/80 FILTER USED BY PERMANENT LAUNCHER t=2s ====='
sudo ss -H -lntp 'sport = :80' 2>&1 || true

echo
echo '===== SS ALL LISTENERS MATCHING :80 t=2s ====='
sudo ss -H -lntp 2>&1 | grep -E '(:|])80[[:space:]]' || true

echo
echo '===== CANDIDATE /proc CMDLINES t=2s ====='
CANDIDATES="$(
  {
    printf '%s\n' "$STARTED_PIDS"
    sudo ss -H -lntp 'sport = :80' 2>/dev/null |
      grep -oE 'pid=[0-9]+' |
      cut -d= -f2
  } | awk 'NF' | sort -nu
)"

for pid in $CANDIDATES; do
  echo "--- PID=$pid ---"
  ps -o pid=,ppid=,sid=,pgid=,user=,stat=,etime=,args= -p "$pid" 2>/dev/null || true
  printf 'CMDLINE='
  pid_cmdline "$pid"
  printf '\n'
done

echo
echo '===== RELAY LOG t=2s ====='
cat "$LOG" || true

echo
echo '===== SURVIVAL WINDOW ====='
for second in 3 4 5 6 7 8; do
  sleep 1
  live="$(relay_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  ss80="$(sudo ss -H -lntp 'sport = :80' 2>/dev/null || true)"
  echo "t=${second}s RELAY_PIDS=${live:-NONE}"
  if [[ -n "$ss80" ]]; then
    printf 't=%ss SS80=%s\n' "$second" "$ss80"
  else
    echo "t=${second}s SS80=NONE"
  fi
done

echo
echo '===== FINAL /proc CMDLINES t=8s ====='
for pid in $STARTED_PIDS; do
  sudo kill -0 "$pid" 2>/dev/null || continue
  echo "--- PID=$pid ---"
  printf 'CMDLINE='
  pid_cmdline "$pid"
  printf '\n'
done

echo
echo '===== FINAL RELAY LOG t=8s ====='
cat "$LOG" || true

echo
echo 'PHASE03_HTTP_LDAPS_LISTENER_DIAGNOSTIC_COMPLETE=True'
