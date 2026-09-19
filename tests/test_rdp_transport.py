"""Actual Ansible templating -> module JSON -> PowerShell collector fixtures."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

try:
    import yaml
    from ansible.parsing.dataloader import DataLoader
    from ansible.template import AnsibleNativeEnvironment, Templar
except ImportError:
    Templar = None

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(Templar, 'Ansible required for real template transport tests')
class RdpTransportTests(unittest.TestCase):
    def render(self, native):
        payload = (ROOT / 'tests/fixtures/rdp-directory-evidence.json').read_text()
        playbook = yaml.safe_load((ROOT / 'ansible/validate-kingdoms-rdp.yml').read_text())
        template = playbook[1]['tasks'][0]['ansible.windows.win_powershell']['parameters']
        rendered = {}
        for name in ('WINTERFELL', 'CASTELBLACK', 'WS01'):
            variables = {
                'hostvars': {'dc02': {'rdp_directory': {'output': [payload]}}},
                'lab': {'hosts': {'test': {'hostname': name}}}, 'dict_key': 'test',
                'rdp_require_sessions': False,
            }
            templar = Templar(loader=DataLoader(), variables=variables)
            if native:
                templar = templar.copy_with_new_env(environment_class=AnsibleNativeEnvironment)
            parameters = templar.template(template)
            # The module arguments are JSON encoded on the control node.
            parameters = json.loads(json.dumps(parameters))
            self.assertIsInstance(parameters['DirectoryJson'], str)
            self.assertEqual(json.loads(parameters['DirectoryJson']), json.loads(payload))
            self.assertIs(parameters['RequireSessions'], False)
            rendered[name] = parameters
        return rendered

    def test_real_ansible_parameter_types(self):
        for native in (False, True):
            with self.subTest(native=native):
                self.render(native)

    @unittest.skipUnless(shutil.which('pwsh'), 'PowerShell required for transport integration')
    def test_rendered_parameters_reach_host_policy_checks(self):
        for native in (False, True):
            with self.subTest(native=native):
                result = subprocess.run(
                    ['pwsh', '-NoProfile', '-NonInteractive', '-File',
                     str(ROOT / 'tests/test_rdp_host_evidence.ps1'), '-FromStdin'],
                    input=json.dumps(self.render(native)), text=True,
                    capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
