"""Exercise callback event semantics without requiring Ansible or a guest."""
import ast
import json
import os
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]


class CallbackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'tasks.jsonl'

        class Base:
            def __init__(self):
                self._display = Mock()

        file = ROOT / 'ansible/callback_plugins/kingdoms_install_timing.py'
        node = next(n for n in ast.parse(file.read_text()).body if isinstance(n, ast.ClassDef))
        namespace = dict(CallbackBase=Base, json=json, os=os, Path=Path, time=time)
        exec(compile(ast.Module(body=[node], type_ignores=[]), str(file), 'exec'), namespace)
        with patch.dict(os.environ, GOAD_INSTALL_TASK_TIMINGS=str(self.path)):
            self.callback = namespace['CallbackModule']()
        self.task = SimpleNamespace(_uuid='task-1', no_log=False,
                                    _role=SimpleNamespace(get_name=lambda: 'mssql_ssms'),
                                    get_name=lambda: 'mssql_ssms : Install SSMS')
        self.host = SimpleNamespace(get_name=lambda: 'srv02')

    def result(self, **values):
        return SimpleNamespace(_task=self.task, _host=self.host, _result=values)

    def test_async_launch_does_not_finish_timing_and_final_events_do_not_duplicate(self):
        self.callback.v2_runner_on_start(self.host, self.task)
        self.callback.v2_runner_on_ok(self.result(finished=0, ansible_job_id='123'))
        self.assertFalse(self.path.exists())
        self.callback.v2_runner_on_async_ok(self.result(finished=1, ansible_job_id='123'))
        self.callback.v2_runner_on_ok(self.result(finished=1, ansible_job_id='123'))
        rows = self.path.read_text().splitlines()
        self.assertEqual(len(rows), 1)
        self.assertEqual(json.loads(rows[0])['outcome'], 'ok')

    def test_records_metadata_without_arguments_or_results(self):
        self.task.args = {'password': 'do-not-record-this'}
        self.callback.v2_runner_on_start(self.host, self.task)
        self.callback.v2_runner_on_failed(self.result(stdout='do-not-record-this', secret='another-secret'))
        text = self.path.read_text()
        self.assertNotIn('do-not-record-this', text)
        self.assertNotIn('another-secret', text)
        self.assertEqual(json.loads(text)['outcome'], 'failed')

    def test_no_log_at_start_or_result_prevents_recording(self):
        self.task.no_log = True
        self.callback.v2_runner_on_start(self.host, self.task)
        self.callback.v2_runner_on_ok(self.result())
        self.task.no_log = False
        self.callback.v2_runner_on_start(self.host, self.task)
        self.callback.v2_runner_on_ok(self.result(_ansible_no_log=True))
        self.assertFalse(self.path.exists())

    def test_disabled_or_unrelated_role_is_inert(self):
        self.callback._path = None
        self.callback.v2_runner_on_start(self.host, self.task)
        self.callback.v2_runner_on_ok(self.result())
        self.callback._path = str(self.path)
        self.task._role.get_name = lambda: 'unrelated'
        self.callback.v2_runner_on_start(self.host, self.task)
        self.callback.v2_runner_on_ok(self.result())
        self.assertFalse(self.path.exists())

    def test_parallel_hosts_are_measured_independently(self):
        other = SimpleNamespace(get_name=lambda: 'srv03')
        self.callback.v2_runner_on_start(self.host, self.task)
        self.callback.v2_runner_on_start(other, self.task)
        self.callback.v2_runner_on_ok(self.result())
        self.callback.v2_runner_on_unreachable(SimpleNamespace(_task=self.task, _host=other, _result={}))
        rows = [json.loads(line) for line in self.path.read_text().splitlines()]
        self.assertEqual([row['host'] for row in rows], ['srv02', 'srv03'])
        self.assertEqual([row['outcome'] for row in rows], ['ok', 'unreachable'])

    def test_write_failure_disables_observer_without_raising(self):
        self.path.mkdir()
        self.callback.v2_runner_on_start(self.host, self.task)
        self.callback.v2_runner_on_ok(self.result())
        self.assertIsNone(self.callback._path)
        self.callback._display.warning.assert_called_once()
        self.callback.v2_playbook_on_stats(None)


if __name__ == '__main__':
    unittest.main()
