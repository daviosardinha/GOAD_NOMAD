"""Regression coverage for CLI lifecycle exit-code propagation."""
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from goad import Goad
from goad_nomad import _dispatch_task


class LifecycleTaskExitCodeTests(unittest.TestCase):
    def _args(self, task):
        return SimpleNamespace(
            instance='6fdd5a-goad-vmware',
            run_playbook=None,
            ansible_only=None,
            task=task,
        )

    def test_cli_start_failure_returns_nonzero(self):
        goad = Mock()
        goad.do_start.return_value = False

        self.assertEqual(_dispatch_task(goad, self._args('start')), 1)
        goad.do_start.assert_called_once_with()

    def test_cli_stop_failure_returns_nonzero(self):
        goad = Mock()
        goad.do_stop.return_value = False

        self.assertEqual(_dispatch_task(goad, self._args('stop')), 1)
        goad.do_stop.assert_called_once_with()

    def test_cli_restart_stops_if_stop_fails(self):
        goad = Mock()
        goad.do_stop.return_value = False

        self.assertEqual(_dispatch_task(goad, self._args('restart')), 1)
        goad.do_start.assert_not_called()

    def test_cli_restart_propagates_start_failure(self):
        goad = Mock()
        goad.do_stop.return_value = True
        goad.do_start.return_value = False

        self.assertEqual(_dispatch_task(goad, self._args('restart')), 1)

    def test_cli_snapshot_failure_returns_nonzero(self):
        goad = Mock()
        goad.do_snapshot.return_value = False

        self.assertEqual(_dispatch_task(goad, self._args('snapshot')), 1)

    def test_cli_reset_failure_returns_nonzero(self):
        goad = Mock()
        goad.do_reset.return_value = False

        self.assertEqual(_dispatch_task(goad, self._args('reset')), 1)

    def test_base_start_and_stop_return_provider_results(self):
        goad = Goad.__new__(Goad)
        provider = Mock()
        manager = Mock()
        manager.get_current_instance_provider.return_value = provider
        goad.lab_manager = manager

        provider.start.return_value = True
        self.assertTrue(goad.do_start())

        provider.stop.return_value = False
        self.assertFalse(goad.do_stop())

    def test_snapshot_never_runs_when_stop_fails(self):
        goad = Goad.__new__(Goad)
        provider = Mock()
        manager = Mock()
        manager.get_current_instance_provider.return_value = provider
        goad.lab_manager = manager
        goad.do_stop = Mock(return_value=False)
        goad.do_start = Mock(return_value=True)

        self.assertFalse(goad.do_snapshot())
        provider.snapshot.assert_not_called()
        goad.do_start.assert_not_called()

    def test_snapshot_propagates_restart_failure(self):
        goad = Goad.__new__(Goad)
        provider = Mock()
        manager = Mock()
        manager.get_current_instance_provider.return_value = provider
        goad.lab_manager = manager
        goad.do_stop = Mock(return_value=True)
        goad.do_start = Mock(return_value=False)
        provider.snapshot.return_value = True

        self.assertFalse(goad.do_snapshot())
        provider.snapshot.assert_called_once_with()


if __name__ == '__main__':
    unittest.main()
