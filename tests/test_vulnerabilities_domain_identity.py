"""Regression contract for vulnerability runas domain identity."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLAYBOOK = ROOT / "ansible/vulnerabilities.yml"


class VulnerabilitiesDomainIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = PLAYBOOK.read_text(encoding="utf-8")

    def test_runas_uses_netbios_domain_name(self):
        self.assertIn(
            r'domain_username: "{{lab.domains[domain].netbios_name}}\\{{admin_user}}"',
            self.text,
        )

    def test_runas_does_not_use_dns_domain_as_downlevel_name(self):
        self.assertNotIn(
            r'domain_username: "{{domain}}\\{{admin_user}}"',
            self.text,
        )


if __name__ == "__main__":
    unittest.main()
