"""Offline source contract for the Phase 03 Rickon/WS01 victim client."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "phase03" / "rickon-headless.sh"
CHECK = ROOT / "scripts" / "phase03" / "check-rickon-prereqs.sh"
INSTALL = ROOT / "scripts" / "phase03" / "install-rickon-headless.sh"
UNIT = ROOT / "ops" / "systemd" / "kingdoms-phase03-rickon.service"
CERT_READ = ROOT / "scripts" / "phase03" / "read-ws01-rdp-cert.sh"
CERT_PLAYBOOK = ROOT / "ansible" / "phase03-read-ws01-rdp-cert.yml"


class Phase03RickonHeadlessTests(unittest.TestCase):
    def test_required_files_exist_and_parse(self):
        for path in (RUNNER, CHECK, INSTALL, UNIT, CERT_READ, CERT_PLAYBOOK):
            self.assertTrue(path.is_file(), path)
        for path in (RUNNER, CHECK, INSTALL, CERT_READ):
            result = subprocess.run(
                ["bash", "-n", str(path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_runner_scope_and_identity(self):
        text = RUNNER.read_text()
        for expected in (
            "TARGET_IP='10.4.10.31'",
            "EXPECTED_INTERFACE='vmnet10'",
            "EXPECTED_SOURCE='10.4.10.254'",
            "'/d:NORTH'",
            "'/u:rickon.stark'",
            "/args-from:stdin",
            "rickon-rdp.password",
            "ws01-rdp.sha256",
            "fingerprint:sha256",
            "-clipboard",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)

    def test_runner_fails_closed_on_duplicate_and_certificate(self):
        text = RUNNER.read_text()
        self.assertIn("refusing a duplicate victim session", text)
        self.assertIn("^[0-9a-f]{64}$", text)
        self.assertNotIn("/cert:ignore", text)
        self.assertNotIn("/p:Winter", text)

    def test_unit_is_rate_limited_and_opt_in(self):
        text = UNIT.read_text()
        self.assertIn("RestartSec=120", text)
        self.assertIn("StartLimitBurst=3", text)
        self.assertIn("NoNewPrivileges=true", text)
        self.assertIn("WantedBy=default.target", text)
        self.assertNotIn("/p:", text)

    def test_installer_does_not_start_or_enable_service(self):
        text = INSTALL.read_text()
        self.assertIn("--confirm", text)
        self.assertIn("daemon-reload", text)
        self.assertNotIn("systemctl --user start", text)
        self.assertNotIn("systemctl --user enable", text)
        self.assertIn("service was NOT enabled or started", text)

    def test_certificate_probe_is_read_only_and_emits_sha256(self):
        text = CERT_PLAYBOOK.read_text()
        self.assertIn("hosts: ws01", text)
        self.assertIn("register: ws01_rdp_cert", text)
        self.assertIn("RDP_SHA256=", text)
        self.assertIn("changed_when: false", text)
        self.assertIn("ws01_rdp_cert.output", text)

    def test_no_known_lab_passwords(self):
        corpus = "\n".join(p.read_text(errors="replace") for p in (RUNNER, CHECK, INSTALL, UNIT)).lower()
        for forbidden in (
            "winter2022",
            "sexywolfy",
            "fightp3aceandhonor!",
            "youwillnotkerboroast1ngmeeeeee",
        ):
            self.assertNotIn(forbidden, corpus)


if __name__ == "__main__":
    unittest.main()
