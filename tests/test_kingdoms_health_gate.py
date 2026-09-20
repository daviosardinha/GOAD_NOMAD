"""Regression contract for Kingdoms AD health gates."""

from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]


class KingdomsHealthGateTests(unittest.TestCase):
    def test_goad_health_gates_wrap_vulnerability_and_final_stages(self):
        playbooks = yaml.safe_load((ROOT / "playbooks.yml").read_text(encoding="utf-8"))
        sequence = playbooks["GOAD"]

        self.assertLess(sequence.index("security.yml"), sequence.index("kingdoms-health.yml"))
        self.assertLess(sequence.index("kingdoms-health.yml"), sequence.index("vulnerabilities.yml"))
        self.assertLess(sequence.index("ws01-lpe-install.yml"), sequence.index("kingdoms-health-final.yml"))
        self.assertEqual("kingdoms-health-final.yml", sequence[-1])

    def test_member_health_can_repair_but_final_gate_cannot(self):
        pre = (ROOT / "ansible/kingdoms-health.yml").read_text(encoding="utf-8")
        final = (ROOT / "ansible/kingdoms-health-final.yml").read_text(encoding="utf-8")
        member = (
            ROOT / "ansible/roles/kingdoms_health/member/tasks/main.yml"
        ).read_text(encoding="utf-8")

        self.assertIn("kingdoms_health_repair: true", pre)
        self.assertIn("kingdoms_health_repair: false", final)
        for token in (
            "Test-ComputerSecureChannel",
            "Reset-ComputerMachinePassword",
            "nltest.exe",
            "Resolve-DnsName",
            "w32tm.exe",
            "AllowRepair",
        ):
            self.assertIn(token, member)

    def test_domain_controller_gate_is_validation_only(self):
        dc = (
            ROOT / "ansible/roles/kingdoms_health/dc/tasks/main.yml"
        ).read_text(encoding="utf-8")

        for token in (
            "NTDS",
            "DNS",
            "ADWS",
            "Netlogon",
            "Kdc",
            "W32Time",
            "SYSVOL",
            "NETLOGON",
            "Get-ADDomain",
            "Resolve-DnsName",
            "nltest.exe",
        ):
            self.assertIn(token, dc)
        self.assertNotIn("Reset-ComputerMachinePassword", dc)

    def test_health_powershell_uses_safe_variable_interpolation_before_colons(self):
        role_paths = (
            ROOT / "ansible/roles/kingdoms_health/dc/tasks/main.yml",
            ROOT / "ansible/roles/kingdoms_health/member/tasks/main.yml",
        )
        for path in role_paths:
            text = path.read_text(encoding="utf-8")
            with self.subTest(path=path):
                self.assertNotIn("$DomainName:", text)
                self.assertIn("${DomainName}:", text)


if __name__ == "__main__":
    unittest.main()