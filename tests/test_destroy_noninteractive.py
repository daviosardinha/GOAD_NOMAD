"""Regression coverage for non-interactive Vagrant destroy."""
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from goad.provider.vagrant.vagrant import VagrantProvider
from goad_nomad import _dispatch_task


class DestroyNonInteractiveTests(unittest.TestCase):
    def test_vagrant_force_destroy_never_requires_tty(self):
        provider = VagrantProvider.__new__(VagrantProvider)
        provider.command = Mock()
        provider.command.run_vagrant.return_value = True
        provider.path = '/provider'

        self.assertTrue(provider.destroy_non_interactive())
        provider.command.run_vagrant.assert_called_once_with(
            ['destroy', '-f'], '/provider'
        )

    def _args(self):
        return SimpleNamespace(
            instance='e4ad27-goad-vmware',
            run_playbook=None,
            ansible_only=None,
            task='destroy',
        )

    def test_cli_destroy_uses_non_interactive_path_and_propagates_success(self):
        goad = Mock()
        goad.do_destroy.return_value = True

        self.assertEqual(_dispatch_task(goad, self._args()), 0)
        goad.do_load.assert_called_once_with('e4ad27-goad-vmware')
        goad.do_destroy.assert_called_once_with('--non-interactive')

    def test_cli_destroy_propagates_failure(self):
        goad = Mock()
        goad.do_destroy.return_value = False

        self.assertEqual(_dispatch_task(goad, self._args()), 1)
        goad.do_destroy.assert_called_once_with('--non-interactive')


if __name__ == '__main__':
    unittest.main()
