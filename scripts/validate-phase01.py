#!/usr/bin/env python3
"""Bounded, read-only Phase 01 checks from the Kali/operator network.

No share write probes, password spraying or Windows configuration writes.
PASS requires protocol evidence; unavailable tools/results make readiness fail.
"""
import argparse
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DENIED = re.compile(r"NT_STATUS_(?:LOGON_FAILURE|ACCOUNT_DISABLED|ACCESS_DENIED|ACCOUNT_RESTRICTION)", re.I)


def share_listing_result(rc, text):
    """Classify share-list evidence without equating exit zero with visibility.

    smbclient can return zero and proceed to legacy workgroup discovery without
    printing any share rows. That is a no-names observation, not proof of share
    access or of the identity assigned to the SMB session.
    """
    if rc in (124, 127) or rc < 0:
        return "inconclusive"
    if DENIED.search(text):
        return "rejected" if rc != 0 else "inconclusive"
    if rc != 0:
        return "inconclusive"
    if re.search(r"session setup failed|tree connect failed|Error returning browse list", text, re.I):
        return "inconclusive"
    if re.search(r"^(?:Disk|IPC|Printer)\|[^|]+\|", text, re.M):
        return "available"
    # Require evidence that smbclient reached its separate workgroup phase.
    # Empty output, missing tools and generic network failures cannot pass.
    if "Reconnecting with SMB1 for workgroup listing." in text:
        return "no share names returned"
    return "inconclusive"


def ldif_records(text):
    """Parse requested LDAP attributes, including folded and base64 values."""
    unfolded = re.sub(r"\r?\n ", "", text.replace("\r\n", "\n"))
    records = []
    for block in unfolded.split("\n\n"):
        attrs = {}
        for line in block.splitlines():
            match = re.match(r"^([\w;-]+)(::?) ?(.*)$", line)
            if not match:
                continue
            key, separator, value = match.groups()
            if separator == "::":
                try:
                    value = base64.b64decode(value, validate=True).decode("utf-8")
                except (ValueError, UnicodeError):
                    continue
            attrs.setdefault(key.lower(), []).append(value)
        if "dn" in attrs:
            records.append(attrs)
    return records


def sid_resolved(text, sid):
    # Require a SID followed by a qualified principal and a real SID_NAME_USE.
    # Neither an echoed command nor SID_NAME_UNKNOWN (8) is success.
    return bool(re.search(r"^" + re.escape(sid) + r"\s+[^\s\\]+\\[^\r\n]+\s+\([125]\)\s*$", text, re.M))


def rpc_named_rids(text, prefix):
    """Return rpcclient enumdomusers/enumdomgroups names mapped to integer RIDs."""
    pattern = re.compile(
        r"^" + re.escape(prefix) + r":\[([^\]]+)\]\s+rid:\[(0x[0-9a-f]+)\]\s*$",
        re.M | re.I,
    )
    return {name.lower(): int(rid, 16) for name, rid in pattern.findall(text)}


def http_boundary(text):
    statuses = re.findall(r"^HTTP/\S+\s+(\d{3})", text, re.M)
    auth = re.findall(r"^WWW-Authenticate:\s*([^\r\n]+)", text, re.M | re.I)
    schemes = {part.strip().split()[0].lower() for value in auth for part in value.split(",") if part.strip()}
    return bool(statuses and statuses[-1] == "401" and {"negotiate", "ntlm"} <= schemes)


class Validator:
    def __init__(self, out, timeout):
        self.out = out
        self.timeout = timeout
        self.results = []

    def result(self, name, ok, detail=""):
        state = "PASS" if ok else "FAIL"
        self.results.append({"check": name, "status": state, "detail": detail})
        print(f"[{state}] {name}" + (f" — {detail}" if detail else ""), flush=True)

    def run(self, name, command):
        try:
            proc = subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=self.timeout)
            rc, text = proc.returncode, proc.stdout + proc.stderr
        except FileNotFoundError:
            rc, text = 127, f"Missing tool: {command[0]}\n"
        except subprocess.TimeoutExpired as error:
            def decode(value):
                return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
            rc, text = 124, decode(error.stdout) + decode(error.stderr) + "\nTIMEOUT\n"
        text = ANSI.sub("", text).replace("\r", "")
        (self.out / f"{name}.txt").write_text(f"exit_code={rc}\n{text}")
        return rc, text

    def finish(self):
        failures = sum(row["status"] != "PASS" for row in self.results)
        summary = "KINGDOMS PHASE 01 READINESS\n" + "\n".join(
            f"[{row['status']}] {row['check']}" + (f" — {row['detail']}" if row['detail'] else "")
            for row in self.results
        )
        summary += f"\n\nPASS: {len(self.results) - failures}\nFAIL: {failures}\nArtifacts: {self.out}\n"
        (self.out / "SUMMARY.txt").write_text(summary)
        (self.out / "results.json").write_text(json.dumps(self.results, indent=2) + "\n")
        print(f"\n{summary}")
        return 1 if failures else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dc", default="10.4.10.11")
    parser.add_argument("--server", default="10.4.10.22")
    parser.add_argument("--ws01", default="10.4.10.31")
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    domain = "north.sevenkingdoms.local"
    base = "DC=north,DC=sevenkingdoms,DC=local"
    os.umask(0o077)
    out = args.out or Path.home() / ("kingdoms-phase01-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    # Do not reuse artifacts from an earlier run and accidentally report success.
    out = out.expanduser().resolve()
    out.mkdir(parents=True, exist_ok=False)
    v = Validator(out, args.timeout)

    # Curriculum contract: anonymous LSA/SID translation and selected SAMR calls
    # must work while normal SMB share listing remains restricted below.
    rc, text = v.run("rid_domain", ["rpcclient", "-U", "%", "-N", args.dc, "-c", "lsaquery"])
    sid = re.search(r"^Domain Sid:\s*(S-1-5-21-\d+-\d+-\d+)\s*$", text, re.M | re.I)
    v.result("Anonymous domain SID", rc == 0 and sid is not None)
    if rc == 0 and sid:
        target = sid.group(1) + "-500"
        rc, text = v.run("rid_name", ["rpcclient", "-U", "%", "-N", args.dc, "-c", "lookupsids " + target])
        v.result("Anonymous SID-to-name translation", rc == 0 and sid_resolved(text, target))
    else:
        v.result("Anonymous SID-to-name translation", False, "No domain SID; lookup not run")

    rc, text = v.run("samr_users", ["rpcclient", "-U", "%", "-N", args.dc, "-c", "enumdomusers"])
    samr_users = rpc_named_rids(text, "user")
    v.result(
        "Anonymous SAMR user enumeration",
        rc == 0 and {"guest", "samwell.tarly", "sql_svc"} <= set(samr_users),
        "Expected Guest, samwell.tarly and sql_svc",
    )

    rc, text = v.run("samr_groups", ["rpcclient", "-U", "%", "-N", args.dc, "-c", "enumdomgroups"])
    samr_groups = rpc_named_rids(text, "group")
    v.result(
        "Anonymous SAMR group enumeration",
        rc == 0 and {"domain users", "domain guests", "night watch"} <= set(samr_groups),
        "Expected Domain Users, Domain Guests and Night Watch",
    )

    rc, text = v.run("samr_queryuser", ["rpcclient", "-U", "%", "-N", args.dc, "-c", "queryuser 0x1f5"])
    v.result(
        "Anonymous SAMR individual user query",
        rc == 0 and bool(re.search(r"\bGuest\b", text, re.I)) and not DENIED.search(text),
        "Built-in Guest RID 0x1f5",
    )

    rc, text = v.run("samr_querygroup", ["rpcclient", "-U", "%", "-N", args.dc, "-c", "querygroup 0x202"])
    v.result(
        "Anonymous SAMR individual group query",
        rc == 0 and bool(re.search(r"\bDomain Guests\b", text, re.I)) and not DENIED.search(text),
        "Built-in Domain Guests RID 0x202",
    )

    rc, text = v.run("samr_passpol", ["rpcclient", "-U", "%", "-N", args.dc, "-c", "getdompwinfo"])
    v.result(
        "Anonymous SAMR password policy",
        rc == 0 and bool(re.search(r"^min_password_length:\s*5\s*$", text, re.M | re.I)) and not DENIED.search(text),
        "Expected NORTH minimum password length 5",
    )

    ldap = ["ldapsearch", "-LLL", "-x", "-o", "nettimeout=10", "-l", "20", "-H", "ldap://" + args.dc]
    rc, text = v.run("ldap_rootdse", ldap + ["-s", "base", "-b", "", "defaultNamingContext"])
    roots = ldif_records(text)
    v.result("Anonymous RootDSE", rc == 0 and any(base.lower() in [x.lower() for x in r.get("defaultnamingcontext", [])] for r in roots))
    rc, text = v.run("ldap_directory", ldap + ["-b", base, "(|(objectCategory=person)(objectCategory=group))", "sAMAccountName", "objectClass", "description"])
    records = ldif_records(text)
    v.result("Anonymous LDAP user enumeration", rc == 0 and any("user" in r.get("objectclass", []) and r.get("samaccountname") for r in records))
    v.result("Anonymous LDAP group enumeration", rc == 0 and any("group" in r.get("objectclass", []) and r.get("samaccountname") for r in records))
    config = json.loads((Path(__file__).resolve().parents[1] / "ad/GOAD/data/config.json").read_text())
    description = config["lab"]["domains"][domain]["users"]["samwell.tarly"]["description"]
    v.result("Samwell description leak", rc == 0 and any(
        "samwell.tarly" in r.get("samaccountname", []) and description in r.get("description", []) for r in records))

    # Explicitly empty username AND password. -N alone can use the local login.
    # These checks identify requested auth modes, not the server's session flags.
    # Selected RPC pipes are intentionally exposed; normal share names are not.
    for label, host, null_expected, guest_expected in [
        ("WINTERFELL", args.dc, "no share names returned", "rejected"),
        ("CASTELBLACK", args.server, "rejected", "available"),
        ("WS01", args.ws01, "rejected", "rejected"),
    ]:
        for mode, credential, expected in [("NULL", "%", null_expected), ("Guest", "Guest%", guest_expected)]:
            rc, text = v.run(f"smb_{label}_{mode}", ["smbclient", "-g", "-N", "-U", credential, "-L", "//" + host])
            observed = share_listing_result(rc, text)
            v.result(f"{label} {mode} share listing: {expected}", observed == expected,
                     "" if observed == expected else f"Observed: {observed}; exit_code={rc}")
    rc, text = v.run("guest_read", ["smbclient", "-N", "-U", "Guest%", "//" + args.server + "/all", "-c", "ls"])
    v.result("CASTELBLACK Guest can list files in all", rc == 0 and bool(re.search(r"\bblocks of size\b", text)) and not DENIED.search(text), "No write probe performed")

    for label, path in [("public", "/"), ("internal", "/internal/")]:
        rc, text = v.run("http_" + label, ["curl", "--noproxy", "*", "-sS", "--max-time", "15", "-D", "-", "-o", os.devnull, "http://" + args.server + path])
        if label == "public":
            ok = rc == 0 and bool(re.search(r"^HTTP/\S+\s+200\b", text, re.M))
        else:
            ok = rc == 0 and http_boundary(text)
        v.result("HTTP " + path + (" is public (200)" if label == "public" else " requires Windows auth (401, Negotiate + NTLM)"), ok)
    rc, text = v.run("http_ntlm", ["nmap", "-Pn", "-n", "-sT", "-p80", "--script=http-ntlm-info", "--script-args", "http-ntlm-info.root=/internal/", args.server])
    v.result("HTTP NTLM exposes CASTELBLACK identity", rc == 0 and bool(re.search(r"(?:DNS_Computer_Name|NetBIOS_Computer_Name):\s*castelblack(?:\.|\s|$)", text, re.I)))

    users = out / "known-users.txt"
    users.write_text("hodor\nbrandon.stark\nkingdoms.definitely.invalid.user\n")
    managed = Path.home() / ".local/bin/kerbrute"
    kerbrute = str(managed) if managed.is_file() else (shutil.which("kerbrute") or "kerbrute")
    rc, text = v.run("kerberos_users", [kerbrute, "userenum", "--dc", args.dc, "-d", domain, "--threads", "1", str(users)])
    valid = {name.lower() for name in re.findall(r"VALID USERNAME:\s*([^@\s]+)@" + re.escape(domain), text, re.I)}
    complete = bool(re.search(r"Done! Tested 3 usernames \(2 valid\)", text))
    v.result("Kerberos user enumeration distinguishes valid users", rc == 0 and complete and valid == {"hodor", "brandon.stark"})
    return v.finish()


if __name__ == "__main__":
    sys.exit(main())
