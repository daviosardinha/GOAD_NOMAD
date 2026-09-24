#!/usr/bin/env bash
set -euo pipefail

PCAP="${PCAP:-/tmp/kingdoms-wpad.pcap}"
WS01="${WS01:-10.4.10.31}"

echo '===== WPAD DNS QUERIES ====='
sudo tshark -r "$PCAP"   -Y 'dns.qry.name contains "wpad"'   -T fields -E separator=' | '   -e frame.number -e frame.time -e eth.src -e eth.dst   -e ip.src -e ip.dst -e ipv6.src -e ipv6.dst -e dns.qry.name 2>/dev/null

echo
echo '===== WPAD QUERIES FROM WS01 ====='
sudo tshark -r "$PCAP"   -Y "ip.src == $WS01 && dns.qry.name contains \"wpad\""   -T fields -E separator=' | '   -e frame.number -e frame.time -e ip.src -e ip.dst -e dns.qry.name 2>/dev/null || true

echo
echo '===== DHCPV6 ====='
sudo tshark -r "$PCAP"   -Y 'dhcpv6'   -T fields -E separator=' | '   -e frame.number -e frame.time -e eth.src -e eth.dst   -e ipv6.src -e ipv6.dst -e dhcpv6.msgtype 2>/dev/null || true

echo
echo '===== HTTP REQUESTS ====='
sudo tshark -r "$PCAP"   -Y 'http.request'   -T fields -E separator=' | '   -e frame.number -e frame.time -e ip.src -e ipv6.src   -e http.host -e http.request.method -e http.request.uri 2>/dev/null || true
