"""Source-only checks for the proposed Linux RDP bot prerequisite gate."""
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/check-rdp-bot-prereqs.sh"
DOC = ROOT / "docs/rdp-bot-recovery.md"


class RdpBotPrerequisitesTests(unittest.TestCase):
    def test_bash_syntax(self):
        result = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_doctor_is_read_only_and_north_scoped(self):
        source = SCRIPT.read_text()
        for expected in (
            "TARGET_IP=10.4.10.22",
            "EXPECTED_INTERFACE=vmnet10",
            "EXPECTED_SOURCE=10.4.10.254",
            "xfreerdp3",
            "xvfb-run",
            "Xvfb",
            "/from-stdin",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, source)
        for forbidden in (
            "Start-ScheduledTask",
            "Stop-ScheduledTask",
            "Disable-ScheduledTask",
            "systemctl start",
            "apt install",
            "/p:sexywolfy",
            "mstsc /",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)

    def test_handover_requires_evidence_and_preserves_legacy_bot(self):
        doc = DOC.read_text()
        for expected in (
            "does not replace, disable or modify",
            "Do not start the candidate alongside the legacy bot",
            "operator-host credentials",
            "bounded automatic reconnection",
            "fresh installation",
            "validate-rdp-runtime.sh --require-sessions --phase01",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, doc)


if __name__ == "__main__":
    unittest.main()
