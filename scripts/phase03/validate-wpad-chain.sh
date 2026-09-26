#!/usr/bin/env bash
# Validate the deterministic WS01 mitm6 -> WPAD chain from an existing packet capture.
set -uo pipefail

PCAP="${PCAP:-/tmp/kingdoms-wpad.pcap}"
WS01_V4="${WS01_V4:-10.4.10.31}"
WS01_MAC="${WS01_MAC:-00:50:56:20:10:31}"
ATTACKER_V6="${ATTACKER_V6:-fe80::250:56ff:fec0:a}"

PASS=0
FAIL=0
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$*"; }
fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$*" >&2; }

command -v tshark >/dev/null 2>&1 || {
  echo 'FAIL: tshark is required' >&2
  exit 1
}

[[ -r "$PCAP" ]] || {
  echo "FAIL: capture not readable: $PCAP" >&2
  exit 1
}

echo '===== DHCPV6 CHAIN ====='
dhcp="$(
  tshark -r "$PCAP"     -Y 'dhcpv6'     -T fields -E separator='|'     -e frame.number     -e frame.time_epoch     -e eth.src     -e eth.dst     -e ipv6.src     -e ipv6.dst     -e dhcpv6.msgtype     2>/dev/null || true
)"
printf '%s\n' "$dhcp"

solicit="$(awk -F'|' -v mac="$WS01_MAC" '$3==mac && $7=="1"{print $2; exit}' <<<"$dhcp")"
advertise="$(awk -F'|' -v atk="$ATTACKER_V6" '$5==atk && $7=="2"{print $2; exit}' <<<"$dhcp")"
request="$(awk -F'|' -v mac="$WS01_MAC" '$3==mac && $7=="3"{print $2; exit}' <<<"$dhcp")"
reply="$(awk -F'|' -v atk="$ATTACKER_V6" '$5==atk && $7=="7"{print $2; exit}' <<<"$dhcp")"

[[ -n "$solicit" ]] && pass 'WS01 DHCPv6 Solicit observed' || fail 'WS01 DHCPv6 Solicit missing'
[[ -n "$advertise" ]] && pass 'Attacker DHCPv6 Advertise observed' || fail 'Attacker DHCPv6 Advertise missing'
[[ -n "$request" ]] && pass 'WS01 DHCPv6 Request observed' || fail 'WS01 DHCPv6 Request missing'
[[ -n "$reply" ]] && pass 'Attacker DHCPv6 Reply observed' || fail 'Attacker DHCPv6 Reply missing'

if [[ -n "$solicit" && -n "$advertise" && -n "$request" && -n "$reply" ]]; then
  if python3 - "$solicit" "$advertise" "$request" "$reply" <<'PY'
import sys
s, a, r, q = map(float, sys.argv[1:])
raise SystemExit(0 if s <= a <= r <= q else 1)
PY
  then
    pass 'DHCPv6 Solicit -> Advertise -> Request -> Reply ordering'
  else
    fail 'DHCPv6 ordering is invalid'
  fi
fi

echo
echo '===== WPAD DNS OVER ATTACKER IPV6 ====='
dns="$(
  tshark -r "$PCAP"     -Y "eth.src == $WS01_MAC && ipv6.dst == $ATTACKER_V6 && dns.qry.name contains \"wpad\""     -T fields -E separator='|'     -e frame.number     -e frame.time_epoch     -e eth.src     -e ipv6.src     -e ipv6.dst     -e dns.qry.name     2>/dev/null || true
)"
printf '%s\n' "$dns"

dns_time="$(awk -F'|' 'NF>=6{print $2; exit}' <<<"$dns")"
[[ -n "$dns_time" ]] &&
  pass 'WS01 queried WPAD through attacker-controlled IPv6 DNS' ||
  fail 'No WS01 WPAD query to attacker IPv6 DNS'

echo
echo '===== PAC RETRIEVAL ====='
http="$(
  tshark -r "$PCAP"     -Y "ip.src == $WS01_V4 && http.request.method == \"GET\" && http.request.uri == \"/wpad.dat\""     -T fields -E separator='|'     -e frame.number     -e frame.time_epoch     -e ip.src     -e http.host     -e http.request.method     -e http.request.uri     2>/dev/null || true
)"
printf '%s\n' "$http"

http_time="$(awk -F'|' 'NF>=6{print $2; exit}' <<<"$http")"
[[ -n "$http_time" ]] &&
  pass 'WS01 requested GET /wpad.dat' ||
  fail 'GET /wpad.dat from WS01 missing'

if [[ -n "$reply" && -n "$dns_time" && -n "$http_time" ]]; then
  if python3 - "$reply" "$dns_time" "$http_time" <<'PY'
import sys
reply, dns, http = map(float, sys.argv[1:])
raise SystemExit(0 if reply <= dns <= http else 1)
PY
  then
    pass 'DHCPv6 Reply -> WPAD DNS -> HTTP GET ordering'
  else
    fail 'WPAD sequence ordering is invalid'
  fi
fi

echo
printf 'PASS: %d\nFAIL: %d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
