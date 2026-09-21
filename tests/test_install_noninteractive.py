"""Regression coverage for explicit non-interactive CLI installs."""
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from goad_nomad import GoadNomad, _dispatch_task


class InstallNonInteractiveTests(unittest.TestCase):
    def _args(self):
        return SimpleNamespace(
            instance=None,
            run_playbook=None,
            ansible_only=None,
            task='install',
        )

    def test_cli_install_uses_non_interactive_create_path(self):
        goad = Mock()
        goad.do_install.return_value = True

        self.assertEqual(_dispatch_task(goad, self._args()), 0)
        goad.do_install.assert_called_once_with('--non-interactive')

    def test_cli_install_failure_propagates(self):
        goad = Mock()
        goad.do_install.return_value = False

        self.assertEqual(_dispatch_task(goad, self._args()), 1)
        goad.do_install.assert_called_once_with('--non-interactive')

    def test_non_interactive_create_skips_confirmation_and_creates_instance(self):
        goad = GoadNomad.__new__(GoadNomad)
        manager = Mock()
        manager.get_current_instance.return_value = None
        manager.create_instance.return_value = True
        manager.current_settings = Mock()
        goad.lab_manager = manager
        goad.do_install_instance = Mock(return_value=True)

        self.assertTrue(goad.do_create('--non-interactive'))
        manager.current_settings.show.assert_called_once_with()
        manager.create_instance.assert_called_once_with()
        goad.do_install_instance.assert_called_once_with()

    def test_non_interactive_create_stops_if_instance_creation_fails(self):
        goad = GoadNomad.__new__(GoadNomad)
        manager = Mock()
        manager.get_current_instance.return_value = None
        manager.create_instance.return_value = False
        manager.current_settings = Mock()
        goad.lab_manager = manager
        goad.do_install_instance = Mock(return_value=True)

        self.assertFalse(goad.do_create('--non-interactive'))
        goad.do_install_instance.assert_not_called()


if __name__ == '__main__':
    unittest.main()
