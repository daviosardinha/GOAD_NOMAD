"""Focused lifecycle tests; no VMware, root privileges or GOAD dependencies."""
import ast
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]


def load_method(file, name, namespace):
    tree = ast.parse((ROOT / file).read_text())
    method = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == name)
    exec(compile(ast.Module(body=[method], type_ignores=[]), file, 'exec'), namespace)
    return namespace[name]


class RouterStartup(unittest.TestCase):
    def setUp(self):
        self.process = Mock()
        self.process.run.return_value = subprocess.CompletedProcess([], 0)
        self.process.TimeoutExpired = subprocess.TimeoutExpired
        self.clock = Mock()
        self.clock.monotonic.side_effect = [0, 0, 181]
        self.method = load_method('goad/provider/vagrant/vmware_kingdoms.py', '_bring_up_router', {
            'subprocess': self.process, 'time': self.clock, 'Log': Mock(),
        })
        self.provider = Mock()
        self.provider.path = '/instance/provider'
        self.provider.get_runtime_mode.return_value = 'exercise'
        self.provider._vmx_path.return_value = '/instance/router.vmx'
        self.provider._running_instance_vms.return_value = []
        self.provider._script.side_effect = lambda name: str(ROOT / 'scripts' / name)
        self.provider._provider_env.return_value = {}

    def test_installed_router_uses_vmrun_and_management(self):
        self.assertTrue(self.method(self.provider))
        commands = [c.args[0] for c in self.process.run.call_args_list]
        self.assertEqual(commands[0], ['vmrun', '-T', 'ws', 'start', '/instance/router.vmx', 'nogui'])
        self.assertIn('router-ssh.sh', commands[-1][1])
        self.provider.command.run_vagrant.assert_not_called()

    def test_running_router_is_not_powered_on_again(self):
        self.provider._running_instance_vms.return_value = ['GOAD-ROUTER']
        self.assertTrue(self.method(self.provider))
        self.assertFalse(any(c.args[0][0] == 'vmrun' for c in self.process.run.call_args_list))

    def test_fresh_router_retains_provisioning(self):
        self.provider.get_runtime_mode.return_value = 'unknown'
        self.provider.command.run_vagrant.return_value = True
        self.assertTrue(self.method(self.provider))
        self.provider.command.run_vagrant.assert_called_once_with(['up', 'GOAD-ROUTER'], self.provider.path)
        self.process.run.assert_not_called()

    def test_missing_vmx_fails_without_recreation(self):
        self.provider._vmx_path.return_value = None
        self.assertFalse(self.method(self.provider))
        self.provider.command.run_vagrant.assert_not_called()
        self.process.run.assert_not_called()

    def test_failed_power_on_stops_before_ssh(self):
        self.process.run.return_value = subprocess.CompletedProcess([], 1)
        self.assertFalse(self.method(self.provider))
        self.assertEqual(self.process.run.call_count, 1)

    def test_unreachable_management_has_no_nat_fallback(self):
        self.process.run.side_effect = [subprocess.CompletedProcess([], 0)] * 3 + [subprocess.CompletedProcess([], 255)]
        self.assertFalse(self.method(self.provider))
        self.provider.command.run_vagrant.assert_not_called()

    def test_failed_network_validation_stops_before_ssh(self):
        self.process.run.side_effect = [subprocess.CompletedProcess([], 0)] * 2 + [subprocess.CompletedProcess([], 1)]
        self.assertFalse(self.method(self.provider))
        self.assertEqual(self.process.run.call_count, 3)


class ShellContracts(unittest.TestCase):
    def test_timer_health_states(self):
        text = (ROOT / 'scripts/check-vmware-networks.sh').read_text()
        block = text[text.index('timer_state='):text.index('\nif systemctl is-failed')]
        prefix = '''
failures=0
ok() { :; }
fail() { failures=$((failures + 1)); }
systemctl() {
  if [[ "$1" == is-active ]]; then return 0; fi
  case "$4" in
    SubState) echo "$TEST_TIMER" ;;
    NextElapseUSecMonotonic) echo "$TEST_NEXT" ;;
    ActiveState) echo "$TEST_SERVICE" ;;
  esac
}
HOSTADDR_TIMER=timer
HOSTADDR_SERVICE=service
'''
        for timer, next_run, service, expected in [
            ('waiting', '45s', 'inactive', 0),
            ('elapsed', '0', 'inactive', 1),
            ('waiting', '0', 'inactive', 1),
            ('running', 'infinity', 'activating', 0),
            ('running', 'infinity', 'failed', 1),
        ]:
            with self.subTest(timer=timer, next_run=next_run, service=service):
                result = subprocess.run(['bash', '-c', prefix + block + '\nexit "$failures"'],
                    env={**os.environ, 'TEST_TIMER': timer, 'TEST_NEXT': next_run, 'TEST_SERVICE': service})
                self.assertEqual(result.returncode, expected)

    def test_ssh_key_and_collision_handling(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / 'provider/.vagrant/machines/GOAD-ROUTER/vmware_desktop'
            state.mkdir(parents=True)
            (state / 'id').write_text('/router.vmx')
            (state / 'private_key').write_text('test fixture, not a real key')
            bindir = root / 'bin'
            bindir.mkdir()
            (bindir / 'ip').write_text('#!/bin/bash\necho "1: vmnet99 inet ${TEST_ADDRESS}/24"\n')
            (bindir / 'ssh').write_text('#!/bin/bash\nprintf "%s\\n" "$@"\ncat\n')
            for file in bindir.iterdir():
                file.chmod(0o755)
            env = {**os.environ, 'GOAD_PROVIDER_DIR': str(root / 'provider'),
                   'VAGRANT_HOME': str(root / 'vagrant'), 'PATH': str(bindir) + ':' + os.environ['PATH'],
                   'TEST_ADDRESS': '10.4.99.254'}
            command = ['bash', str(ROOT / 'scripts/router-ssh.sh'), 'sudo nft list ruleset']
            result = subprocess.run(command, env=env, input='stdin preserved', capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(str(state / 'private_key'), result.stdout)
            self.assertIn('vagrant@10.4.99.1', result.stdout)
            self.assertIn('stdin preserved', result.stdout)
            env['TEST_ADDRESS'] = '10.4.99.1'
            self.assertNotEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)
            env['TEST_ADDRESS'] = '10.4.99.254'
            (state / 'private_key').unlink()
            self.assertNotEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)
            fallback = root / 'vagrant/insecure_private_key'
            fallback.parent.mkdir()
            fallback.write_text('test fallback')
            result = subprocess.run(command, env=env, input='', capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(str(fallback), result.stdout)


class Compatibility(unittest.TestCase):
    def test_old_workspace_migration_is_idempotent(self):
        method = load_method('goad/provider/vagrant/vmware.py', '_sync_goad_nomad_vagrantfile_compatibility', {
            'os': os, 're': re, 'Log': Mock(),
        })
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Vagrantfile'
            # Existing current layout, before offline box settings were added.
            text = ('Vagrant.configure("2") do |config|\n' +
                    (ROOT / 'ad/GOAD/providers/vmware/Vagrantfile').read_text() +
                    '\n        v.vmx["numvcpus"] = box[:cpus]\n' +
                    'v.enable_vmrun_ip_lookup = false\n' +
                    'v.vmx["ethernet0.startConnected"] = "TRUE"\nend\n')
            path.write_text(text)
            provider = Mock(path=directory)
            self.assertTrue(method(provider))
            first = path.read_text()
            self.assertIn('config.vm.box_check_update = false', first)
            self.assertTrue(method(provider))
            self.assertEqual(path.read_text(), first)


if __name__ == '__main__':
    unittest.main()
