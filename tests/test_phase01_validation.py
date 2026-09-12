"""Regression tests for false-positive results seen in the initial baselines."""
import base64
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("phase01", ROOT / "scripts/validate-phase01.py")
phase01 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phase01)

WINTERFELL_NULL = (
    'Reconnecting with SMB1 for workgroup listing.\n'
    'Unable to connect with SMB1 -- no workgroup available\n'
    'do_connect: Connection to 10.4.10.11 failed (Error NT_STATUS_RESOURCE_NAME_NOT_FOUND)\n'
)
CASTELBLACK_NULL = 'session setup failed: NT_STATUS_ACCESS_DENIED\n'


class EvidenceTests(unittest.TestCase):
    def test_live_null_results_are_not_share_access(self):
        self.assertEqual(phase01.share_listing_result(0, WINTERFELL_NULL), 'no share names returned')
        self.assertEqual(phase01.share_listing_result(1, CASTELBLACK_NULL), 'rejected')

    def test_share_rows_remain_required_for_available(self):
        self.assertEqual(phase01.share_listing_result(0, 'Disk|all|Public share\n'), 'available')
        self.assertEqual(phase01.share_listing_result(0, 'Disk|all|Public share\n' + WINTERFELL_NULL), 'available')
        self.assertEqual(phase01.share_listing_result(0, 'Sharename Type Comment\n'), 'inconclusive')

    def test_network_failure_and_empty_output_are_not_expected_denial_or_no_names(self):
        cases = [(0, ''), (1, 'NT_STATUS_IO_TIMEOUT'), (1, WINTERFELL_NULL),
                 (124, CASTELBLACK_NULL), (127, CASTELBLACK_NULL),
                 (0, CASTELBLACK_NULL), (0, 'Error returning browse list\n' + WINTERFELL_NULL)]
        for rc, text in cases:
            with self.subTest(rc=rc, text=text):
                self.assertEqual(phase01.share_listing_result(rc, text), 'inconclusive')

    def test_sid_echo_and_unknown_are_not_resolution(self):
        sid = "S-1-5-21-1-2-3-500"
        self.assertFalse(phase01.sid_resolved("lookupsids " + sid, sid))
        self.assertFalse(phase01.sid_resolved(sid + " *unknown*\\*unknown* (8)", sid))
        self.assertFalse(phase01.sid_resolved("NT_STATUS_ACCESS_DENIED", sid))
        self.assertTrue(phase01.sid_resolved(sid + " NORTH\\RenamedAdmin (1)", sid))

    def test_http_requires_status_and_both_schemes(self):
        headers = "WWW-Authenticate: Negotiate\nWWW-Authenticate: NTLM\n"
        self.assertTrue(phase01.http_boundary("HTTP/1.1 401 Unauthorized\n" + headers))
        self.assertTrue(phase01.http_boundary("HTTP/1.1 401 Unauthorized\nwww-authenticate: Negotiate, NTLM\n"))
        self.assertFalse(phase01.http_boundary("HTTP/1.1 200 OK\n" + headers))
        self.assertFalse(phase01.http_boundary("HTTP/1.1 401 Unauthorized\nWWW-Authenticate: Basic realm=NTLM\n"))
        self.assertFalse(phase01.http_boundary("HTTP/1.1 401 Unauthorized\nWWW-Authenticate: Negotiate\n"))

    def test_folded_base64_attributes_are_read(self):
        description = "Samwell Tarly (Password : Heartsbane)"
        encoded = base64.b64encode(description.encode()).decode()
        text = "dn: CN=Samwell,DC=north\nsAMAccountName: samwell.tarly\ndescription:: " + encoded[:24] + "\n " + encoded[24:] + "\n\n"
        records = phase01.ldif_records(text)
        self.assertEqual(records[0]["description"], [description])

    def test_ldap_errors_and_echoes_are_not_objects(self):
        self.assertEqual(phase01.ldif_records("Operations error (1)\nA successful bind must be completed\n"), [])
        self.assertEqual(phase01.ldif_records("sAMAccountName: samwell.tarly\n"), [])
        self.assertEqual(phase01.ldif_records("dn: CN=Samwell\ndescription:: invalid!\n")[0].get("description"), None)

    def test_timeout_with_partial_positive_output_stays_failed(self):
        with tempfile.TemporaryDirectory() as temp:
            v = phase01.Validator(Path(temp), 1)
            error = subprocess.TimeoutExpired(["rpcclient"], 1, output=b"Domain Sid: S-1-5-21-1-2-3\n")
            with patch.object(phase01.subprocess, "run", side_effect=error):
                rc, text = v.run("timeout", ["rpcclient"])
            self.assertEqual(rc, 124)
            self.assertIn("TIMEOUT", text)

    def test_missing_tools_do_not_pass_negative_security_checks(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch.object(phase01.subprocess, "run", side_effect=FileNotFoundError), contextlib.redirect_stdout(io.StringIO()):
                result = phase01.main(["--out", str(Path(temp) / "results")])
            self.assertEqual(result, 1)
            summary = (Path(temp) / "results/SUMMARY.txt").read_text()
            self.assertIn("PASS: 0", summary)
            self.assertNotIn("[PASS]", summary)

    def test_output_directory_cannot_reuse_old_results(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(FileExistsError):
                phase01.main(["--out", temp])

    def test_complete_protocol_evidence_can_pass(self):
        def response(command, **kwargs):
            rc = 0
            if command[0] == 'rpcclient':
                text = ('Domain Sid: S-1-5-21-1-2-3\n' if command[-1] == 'lsaquery'
                        else 'S-1-5-21-1-2-3-500 NORTH\\Administrator (1)\n')
            elif command[0] == 'ldapsearch':
                if command[-1] == 'defaultNamingContext':
                    text = 'dn:\ndefaultNamingContext: DC=north,DC=sevenkingdoms,DC=local\n'
                else:
                    text = ('dn: CN=Samwell,DC=north\nsAMAccountName: samwell.tarly\n'
                            'objectClass: user\ndescription: Samwell Tarly (Password : Heartsbane)\n\n'
                            'dn: CN=Night Watch,DC=north\nsAMAccountName: Night Watch\nobjectClass: group\n')
            elif command[0] == 'smbclient':
                if command[-1] == 'ls':
                    text = '123 blocks of size 4096. 42 blocks available\n'
                elif command[-1] == '//10.4.10.11' and '%' in command:
                    text = WINTERFELL_NULL
                elif command[-1] == '//10.4.10.22' and '%' in command:
                    rc, text = 1, CASTELBLACK_NULL
                elif command[-1] == '//10.4.10.31' or (command[-1] == '//10.4.10.11' and 'Guest%' in command):
                    rc, text = 1, 'session setup failed: NT_STATUS_ACCOUNT_DISABLED\n'
                else:
                    text = 'IPC|IPC$|Remote IPC\nDisk|all|\n'
            elif command[0] == 'curl':
                text = ('HTTP/1.1 401 Unauthorized\nWWW-Authenticate: Negotiate\nWWW-Authenticate: NTLM\n'
                        if command[-1].endswith('/internal/') else 'HTTP/1.1 200 OK\n')
            elif command[0] == 'nmap':
                text = '|   NetBIOS_Computer_Name: CASTELBLACK\n'
            else:
                text = ('[+] VALID USERNAME: hodor@north.sevenkingdoms.local\n'
                        '[+] VALID USERNAME: brandon.stark@north.sevenkingdoms.local\n'
                        'Done! Tested 3 usernames (2 valid) in 0.123 seconds\n')
            return subprocess.CompletedProcess(command, rc, text, '')

        with tempfile.TemporaryDirectory() as temp:
            with patch.object(phase01.subprocess, 'run', side_effect=response), contextlib.redirect_stdout(io.StringIO()):
                result = phase01.main(['--out', str(Path(temp) / 'results')])
            self.assertEqual(result, 0)
            self.assertIn('FAIL: 0', (Path(temp) / 'results/SUMMARY.txt').read_text())


if __name__ == "__main__":
    unittest.main()
