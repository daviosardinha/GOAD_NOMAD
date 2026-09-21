"""Source gates for the deterministic WS01 network-service baseline."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WS01_PLAYBOOK = ROOT / "ansible" / "ws01.yml"
DATA_PLAYBOOK = ROOT / "ansible" / "data.yml"
WORKSTATION_ROLE = ROOT / "ansible" / "roles" / "commonwkstn" / "tasks" / "main.yml"
VMWARE_INVENTORY = ROOT / "ad" / "GOAD" / "providers" / "vmware" / "inventory"
PHASE01_VALIDATOR = ROOT / "scripts" / "validate-phase01.py"
PHASE02_VALIDATOR = ROOT / "scripts" / "validate-phase02-readiness.sh"


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

    def test_runtime_validators_match_exposed_ws01_smb_baseline(self):
        phase01 = PHASE01_VALIDATOR.read_text()
        phase02 = PHASE02_VALIDATOR.read_text()

        self.assertIn('("WS01", args.ws01, "rejected", "rejected")', phase01)
        self.assertIn("pass 'WS01 SMB TCP/445 reachable as the workstation baseline requires'", phase02)
        self.assertNotIn("Phase 02 expects filtered/unreachable", phase02)

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

    def test_ws01_inventory_defines_north_gateway(self):
        inventory = VMWARE_INVENTORY.read_text()
        ws01_line = next(line for line in inventory.splitlines() if line.startswith("ws01 "))

        self.assertIn("ansible_host=10.4.10.31", ws01_line)
        self.assertIn("lab_gateway=10.4.10.1", ws01_line)

    def test_workstation_role_persists_gateway_before_domain_join(self):
        text = WORKSTATION_ROLE.read_text()

        gateway_task = text.index('Ensure the lab gateway is persistent')
        domain_join = text.index('Add workstation to {{member_domain}}')
        self.assertLess(gateway_task, domain_join)
        self.assertIn("route.exe -p add 0.0.0.0 mask 0.0.0.0", text)
        self.assertIn("GOAD_GATEWAY_ADDED", text)
        self.assertIn("changed_when: \"'GOAD_GATEWAY_ADDED' in lab_gateway_result.stdout\"", text)

    def test_workstation_role_requires_domain_authenticated_profile(self):
        text = WORKSTATION_ROLE.read_text()

        self.assertIn("NetworkCategory -eq 'DomainAuthenticated'", text)
        self.assertIn("GOAD_DOMAIN_PROFILE_READY", text)
        self.assertIn("remained $($profile.NetworkCategory) instead of DomainAuthenticated", text)


if __name__ == "__main__":
    unittest.main()
