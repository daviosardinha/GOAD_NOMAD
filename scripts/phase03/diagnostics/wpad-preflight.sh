#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-vmnet10}"
WS01="${WS01:-10.4.10.31}"
PACDIR="${PACDIR:-/tmp/kingdoms-wpad}"

ip -br addr show "$IFACE"
ip route get "$WS01"
ip -6 addr show dev "$IFACE"

sudo ss -ntp | grep "${WS01}:3389" || {
  echo "FAIL: Rickon headless WS01 connection is not present"
  exit 1
}

sudo ss -lntup | grep -E '(:80 |:80$|:53 |:53$|:547 |:547$|:5355 |:5355$|:137 |:137$)' || true
pgrep -af 'mitm6|Responder|ntlmrelayx|python3.*http|dnsmasq' || true

mkdir -p "$PACDIR"
cat > "$PACDIR/wpad.dat" <<'PAC'
function FindProxyForURL(url, host) {
    return "DIRECT";
}
PAC

chmod 644 "$PACDIR/wpad.dat"
sha256sum "$PACDIR/wpad.dat"

echo "PASS: preflight completed; no network state changed"
