#!/usr/bin/env python3
"""Read the certificate presented by WS01's RDP service from the Kali network side.

This performs only the RDP negotiation required to reach the TLS handshake,
then prints the peer certificate SHA-256 fingerprint. It does not authenticate.
"""
from __future__ import annotations

import argparse
import hashlib
import socket
import ssl
import sys

DEFAULT_HOST = "10.4.10.31"
DEFAULT_PORT = 3389

# TPKT + X.224 Connection Request + RDP Negotiation Request.
# requestedProtocols=0x00000003 => TLS + CredSSP/NLA capable negotiation.
RDP_NEGOTIATION_REQUEST = bytes.fromhex(
    "030000130ee000000000000100080003000000"
)


def read_exact(sock: socket.socket, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("RDP peer closed before negotiation completed")
        data.extend(chunk)
    return bytes(data)


def negotiate_rdp_tls(sock: socket.socket) -> None:
    sock.sendall(RDP_NEGOTIATION_REQUEST)

    header = read_exact(sock, 4)
    if header[0] != 0x03:
        raise RuntimeError(f"unexpected TPKT version: 0x{header[0]:02x}")

    total_len = int.from_bytes(header[2:4], "big")
    if total_len < 4 or total_len > 8192:
        raise RuntimeError(f"invalid RDP negotiation length: {total_len}")

    body = read_exact(sock, total_len - 4)

    # RDP Negotiation Response is type 0x02. Failure is 0x03.
    if len(body) < 15:
        raise RuntimeError("short RDP negotiation response")

    nego_type = body[-8]
    if nego_type == 0x03:
        failure_code = int.from_bytes(body[-4:], "little")
        raise RuntimeError(f"RDP negotiation failed: 0x{failure_code:08x}")
    if nego_type != 0x02:
        raise RuntimeError(f"unexpected RDP negotiation response type: 0x{nego_type:02x}")

    selected_protocol = int.from_bytes(body[-4:], "little")
    if selected_protocol == 0:
        raise RuntimeError("server selected Standard RDP Security instead of TLS")

    print(f"RDP_SELECTED_PROTOCOL=0x{selected_protocol:08x}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    try:
        with socket.create_connection((args.host, args.port), timeout=args.timeout) as raw:
            raw.settimeout(args.timeout)
            negotiate_rdp_tls(raw)

            with context.wrap_socket(raw, server_hostname=args.host) as tls:
                der = tls.getpeercert(binary_form=True)
                if not der:
                    raise RuntimeError("RDP TLS peer did not present a certificate")

                sha256 = hashlib.sha256(der).hexdigest()
                cipher = tls.cipher()
                print(f"HOST={args.host}")
                print(f"PORT={args.port}")
                print(f"TLS_VERSION={tls.version()}")
                if cipher:
                    print(f"TLS_CIPHER={cipher[0]}")
                print(f"RDP_SHA256={sha256}")

    except (OSError, ssl.SSLError, RuntimeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
