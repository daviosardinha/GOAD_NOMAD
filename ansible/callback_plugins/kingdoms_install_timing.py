"""Observe SQL setup tasks only when the installation profiler supplies a path."""
import json
import os
from pathlib import Path
import time

from ansible.plugins.callback import CallbackBase


DOCUMENTATION = r'''
name: kingdoms_install_timing
type: aggregate
short_description: Record SQL installation task durations for KINGDOMS profiling
description:
  - Inert unless GOAD_INSTALL_TASK_TIMINGS is set by a profiled local installation.
  - Records task names, hosts, outcomes and elapsed seconds, never task arguments or results.
'''


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'aggregate'
    CALLBACK_NAME = 'kingdoms_install_timing'
    # Auto-discovered alongside ansible.cfg; the invocation-specific path is
    # the opt-in. Other plays/provisioners see an inert callback.
    CALLBACK_NEEDS_ENABLED = False

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._path = os.environ.get('GOAD_INSTALL_TASK_TIMINGS')
        self._pending = {}
        self._rows = []

    def v2_runner_on_start(self, host, task):
        if not self._path or task.no_log or task._role is None:
            return
        role = task._role.get_name()
        if role not in ('mssql', 'mssql_ssms'):
            return
        self._pending[(task._uuid, host.get_name())] = (
            time.monotonic(), role, task.get_name(),
        )

    def _finish(self, result, outcome):
        host = result._host.get_name()
        entry = self._pending.pop((result._task._uuid, host), None)
        if entry is None or not self._path:
            return
        if result._task.no_log or result._result.get('_ansible_no_log'):
            return
        # Asynchronous launch is not completion. Keep its original start time
        # through polling; an async/final runner event closes it only once.
        if outcome == 'ok' and result._result.get('finished') == 0:
            self._pending[(result._task._uuid, host)] = entry
            return
        started, role, task = entry
        row = {'host': host, 'role': role, 'task': task, 'outcome': outcome,
               'seconds': max(0, time.monotonic() - started)}
        try:
            path = Path(self._path)
            path.parent.mkdir(parents=True, exist_ok=True)
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(fd, 'a', encoding='utf-8') as handle:
                handle.write(json.dumps(row) + '\n')
            self._rows.append(row)
        except OSError as exc:
            self._display.warning(f'KINGDOMS task timing disabled: {exc}')
            self._path = None

    def v2_runner_on_ok(self, result):
        self._finish(result, 'ok')

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._finish(result, 'failed')

    def v2_runner_on_unreachable(self, result):
        self._finish(result, 'unreachable')

    def v2_runner_on_skipped(self, result):
        self._finish(result, 'skipped')

    def v2_runner_on_async_ok(self, result):
        self._finish(result, 'ok')

    def v2_runner_on_async_failed(self, result):
        self._finish(result, 'failed')

    def v2_playbook_on_stats(self, stats):
        if self._rows and self._path:
            self._display.display('KINGDOMS SQL setup task timings (slowest 10; may overlap across hosts):')
            for row in sorted(self._rows, key=lambda item: item['seconds'], reverse=True)[:10]:
                self._display.display(
                    f"  {row['seconds']:.1f}s | {row['host']} | {row['outcome']} | {row['task']}"
                )
            self._display.display('KINGDOMS task timing file: ' + self._path)
