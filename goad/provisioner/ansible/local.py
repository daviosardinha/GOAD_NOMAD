from functools import partial
import os
from pathlib import Path

from goad.log import Log
from goad.utils import *
from goad.provisioner.ansible.ansible import Ansible


class LocalAnsibleProvisionerCmd(Ansible):
    provisioner_name = PROVISIONING_LOCAL

    def _install_task_timing_env(self, playbook, attempt):
        profile = getattr(self, '_active_install_profile', None)
        if profile is None or playbook != 'servers.yml':
            return None
        # Per-subprocess environment: do not alter the operator's Ansible
        # configuration or leave a callback active in later console commands.
        env = os.environ.copy()
        env['GOAD_INSTALL_TASK_TIMINGS'] = str(
            Path(profile['_path']).with_suffix(f'.servers-attempt-{attempt}.tasks.jsonl')
        )
        return env

    def run_playbook(self, playbook, inventories, tries=3, timeout=30, playbook_path=None):
        if playbook_path is None:
            playbook_path = self.path

        Log.info(f'Run playbook : {playbook} with inventory file(s) : {", ".join(inventories)}')

        args = f'-i {" -i ".join(inventories)} {playbook}'

        run_complete = False
        nb_try = 0
        while not run_complete:
            nb_try += 1
            env = self._install_task_timing_env(playbook, nb_try)
            execute = self.command.run_ansible
            if env is not None:
                execute = partial(self.command.run_ansible, env=env)
            run_complete = self._run_playbook_attempt(
                playbook, nb_try, execute, args, playbook_path,
            )
            if not run_complete and nb_try > tries:
                Log.error('3 fails abort.')
                break
        return run_complete
