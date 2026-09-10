"""Source gates for the deterministic WS01 network-service baseline."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WS01_PLAYBOOK = ROOT / "ansible" / "ws01.yml"
DATA_PLAYBOOK = ROOT / "ansible" / "data.yml"


class Ws01NetworkBaselineTests(unittest.TestCase):
    def test_ws01_exposes_modern_smb_on_domain_profile(self):
        text = WS01_PLAYBOOK.read_text()

        self.assertIn("name: LanmanServer", text)
        self.assertIn("start_mode: auto", text)
        self.assertIn("state: started", text)
        self.assertIn('Name: "Kingdoms WS01 SMB (TCP-In)"', text)
        self.assertIn('Profile: "Domain"', text)
        self.assertIn('Direction: "Inbound"', text)
        self.assertIn('Localport: "445"', text)
        self.assertIn('Protocol: "TCP"', text)
        self.assertIn('Action: "Allow"', text)

    def test_ws01_smb_rule_does_not_explicitly_open_legacy_netbios_ports(self):
        text = WS01_PLAYBOOK.read_text()

        self.assertNotIn('Localport: "137"', text)
        self.assertNotIn('Localport: "138"', text)
        self.assertNotIn('Localport: "139"', text)

    def test_ws01_data_initialization_is_scoped_to_ws01(self):
        ws01 = WS01_PLAYBOOK.read_text()
        data = DATA_PLAYBOOK.read_text()

        self.assertIn("data_hosts: ws01", ws01)
        self.assertIn("hosts: \"{{ data_hosts | default('domain:linux_domain:extensions') }}\"", data)


if __name__ == "__main__":
    unittest.main()
