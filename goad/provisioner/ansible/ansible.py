import os.path
import time
import yaml
from goad.utils import *
from goad.log import Log
from goad.provisioner.provisioner import Provisioner
from goad.goadpath import GoadPath


class Ansible(Provisioner):

    @staticmethod
    def _format_install_elapsed(seconds):
        total = max(0, int(round(seconds)))
        minutes, secs = divmod(total, 60)
        hours, minutes = divmod(minutes, 60)
        if hours:
            return f'{hours}h {minutes:02d}m {secs:02d}s'
        return f'{minutes}m {secs:02d}s'

    def _kingdoms_install_profile(self):
        if self.lab_name != 'GOAD':
            return None
        profile = getattr(self.provider, '_kingdoms_install_profile', None)
        return profile if isinstance(profile, dict) else None

    def _record_kingdoms_ansible_timing(self, phases, label, started):
        elapsed = time.monotonic() - started
        phases.append({'label': label, 'seconds': elapsed})
        Log.info(
            f'GOAD Kingdoms install timing: {label} = '
            f'{self._format_install_elapsed(elapsed)}'
        )
        return elapsed

    def _emit_kingdoms_install_timing(self, profile, ansible_phases, ansible_started, success):
        if profile is None:
            return

        ansible_elapsed = time.monotonic() - ansible_started
        provider_elapsed = profile.get('provider_elapsed')
        overall_started = profile.get('started')
        overall_elapsed = (
            time.monotonic() - overall_started
            if isinstance(overall_started, (int, float))
            else None
        )

        Log.info('=== KINGDOMS INSTALL TIMING SUMMARY ===')
        for phase in profile.get('phases', []):
            Log.info(
                f"  provider | {phase['label']:<52} "
                f"{self._format_install_elapsed(phase['seconds'])}"
            )
        if isinstance(provider_elapsed, (int, float)):
            Log.info(
                '  provider | TOTAL'.ljust(65)
                + self._format_install_elapsed(provider_elapsed)
            )

        for phase in ansible_phases:
            Log.info(
                f"  ansible  | {phase['label']:<52} "
                f"{self._format_install_elapsed(phase['seconds'])}"
            )
        Log.info(
            '  ansible  | TOTAL'.ljust(65)
            + self._format_install_elapsed(ansible_elapsed)
        )
        if isinstance(overall_elapsed, (int, float)):
            Log.info(
                '  measured | END-TO-END'.ljust(65)
                + self._format_install_elapsed(overall_elapsed)
            )

        message = 'GOAD Kingdoms installation timing capture complete'
        if success:
            Log.success(message)
        else:
            Log.warning(message + ' (installation incomplete)')

    def _get_lab_inventory(self, lab_name, provider_name):
        inventory = []
        # Lab inventory
        lab_inventory = GoadPath.get_lab_inventory_file(lab_name)
        if os.path.isfile(lab_inventory):
            inventory.append(lab_inventory)
            Log.success(f'Lab inventory : {lab_inventory} file found')
        # lab instance inventory
        instance_inventory = self.instance_path + os.path.sep + 'inventory'
        if os.path.isfile(instance_inventory):
            inventory.append(instance_inventory)
            Log.success(f'Provider inventory : {instance_inventory} file found')
        return inventory

    def _get_global_inventory(self):
        # Global inventory
        global_inventory = GoadPath.get_global_inventory_path()
        if os.path.isfile(global_inventory):
            Log.success(f'Global inventory : {global_inventory} file found')
            return global_inventory
        return None

    def _prepare_provider_provisioning(self):
        prepare = getattr(self.provider, 'prepare_provisioning', None)
        if callable(prepare) and not prepare():
            Log.error('Provider failed to prepare the provisioning network state')
            return False
        return True

    def _finalize_provider_provisioning(self):
        finalize = getattr(self.provider, 'finalize_install', None)
        if callable(finalize) and not finalize():
            Log.error('Provider failed to finalize the installed lab state')
            return False
        return True

    def get_inventory(self, lab_name, provider_name):
        Log.info('Loading inventory')
        inventory = self._get_lab_inventory(lab_name, provider_name)
        global_inventory = self._get_global_inventory()
        if global_inventory is not None:
            inventory.append(global_inventory)
        return inventory

    def get_playbook_list(self, lab_name):
        Log.info('Loading playbook list')
        playbook_organisation_file = GoadPath.get_playbooks_lab_config()
        playbook_list = []
        with open(playbook_organisation_file, 'r') as playbooks:
            data_loaded = yaml.safe_load(playbooks)
        if lab_name in data_loaded:
            playbook_datas = data_loaded[lab_name]
        else:
            playbook_datas = data_loaded['default']

        # validate playbooks
        for playbook in playbook_datas:
            playbook_path = GoadPath.get_provisioner_path() + playbook
            if not os.path.isfile(playbook_path):
                Log.error(f'{playbook} not valid, file {playbook_path} not found')
            else:
                playbook_list.append(playbook)
                Log.success(f'{playbook} file found')
        return playbook_list

    def run(self, playbook=None):
        full_lab_run = playbook is None
        profile = self._kingdoms_install_profile() if full_lab_run else None
        ansible_started = time.monotonic() if profile is not None else None
        ansible_phases = []

        def finish_profile(success):
            if profile is not None:
                self._emit_kingdoms_install_timing(
                    profile,
                    ansible_phases,
                    ansible_started,
                    success,
                )
            return success

        # GOAD_NOMAD providers may need to rebuild an out-of-band management
        # plane before a complete Ansible run. For normal providers the hook is
        # absent and upstream behaviour is unchanged.
        if full_lab_run:
            phase_started = time.monotonic()
            prepared = self._prepare_provider_provisioning()
            if profile is not None:
                self._record_kingdoms_ansible_timing(
                    ansible_phases,
                    'Provisioning management-plane preparation',
                    phase_started,
                )
            if not prepared:
                return finish_profile(False)

        inventory = self.get_inventory(self.lab_name, self.provider_name)
        provision_result = False
        if playbook is None:
            playbooks = self.get_playbook_list(self.lab_name)
            for playbook in playbooks:
                phase_started = time.monotonic()
                provision_result = self.run_playbook(playbook, inventory)
                if profile is not None:
                    self._record_kingdoms_ansible_timing(
                        ansible_phases,
                        f'Playbook {playbook}',
                        phase_started,
                    )
                if not provision_result:
                    Log.error(f'Something wrong during the provisioning task : {playbook}')
                    return finish_profile(False)
        else:
            provision_result = self.run_playbook(playbook, inventory)

        # A successful full GOAD_NOMAD installation must never leave the
        # provisioning bypasses enabled. Provider-specific finalization moves
        # the lab into its normal exercise/training state before READY is set by
        # the controller.
        if full_lab_run and provision_result:
            phase_started = time.monotonic()
            finalized = self._finalize_provider_provisioning()
            if profile is not None:
                self._record_kingdoms_ansible_timing(
                    ansible_phases,
                    'Final exercise-mode transition',
                    phase_started,
                )
            return finish_profile(finalized)

        return provision_result

    def run_extension(self, extension, current_instance_extensions_name, install=True):
        # Extension installation can call provider.install() first, which opens
        # the GOAD_NOMAD management plane. Keep the Ansible phase inside the
        # same reversible lifecycle and always close the provisioning bypasses
        # after a successful extension deployment.
        if not self._prepare_provider_provisioning():
            return False

        inventory = self._get_lab_inventory(self.lab_name, self.provider_name)

        # add the inventory of other enabled extensions
        for instances_extension_name in current_instance_extensions_name:
            if instances_extension_name != extension.name:
                other_extension_inventory = self.instance_path + os.path.sep + instances_extension_name + '_inventory'
                if other_extension_inventory is not None:
                    inventory.append(other_extension_inventory)

        # add the current extension inventory at the end
        extension_inventory = self.instance_path + os.path.sep + extension.name + '_inventory'
        if extension_inventory is not None:
            inventory.append(extension_inventory)

        global_inventory = self._get_global_inventory()
        if global_inventory is not None:
            inventory.append(global_inventory)

        playbook = extension.get_playbook(install)
        extension_ansible_path = extension.get_ansible_path()

        provision_result = self.run_playbook(playbook, inventory, playbook_path=extension_ansible_path)
        if not provision_result:
            Log.error(f'Something wrong during the provisioning task : {playbook}')
            return False
        return self._finalize_provider_provisioning()

    def run_from(self, task):
        if task == '' or task is None:
            Log.error('Missing playbook to start from')
            playbooks = self.get_playbook_list(self.lab_name)
            Log.info('Playbook list :')
            for playbook in playbooks:
                Log.info(f' - {playbook}')
            return False

        if not self._prepare_provider_provisioning():
            return False

        inventory = self.get_inventory(self.lab_name, self.provider_name)
        playbooks = self.get_playbook_list(self.lab_name)

        skip = True
        for playbook in playbooks:
            if playbook == task:
                skip = False
            if skip:
                Log.info(f'skip {playbook}')
            else:
                provision_result = self.run_playbook(playbook, inventory)
                if not provision_result:
                    Log.error(f'Something wrong during the provisioning task : {playbook}')
                    return False
        return self._finalize_provider_provisioning()

    def run_playbook(self, playbook, inventories, tries=3, timeout=30, playbook_path=None):
        # abstract
        pass

    def get_disable_vagrant_inventory(self):
        Log.info('Loading inventory')
        inventory = []
        lab_inventory = self.instance_path + os.path.sep + 'inventory_disable_vagrant'
        if os.path.isfile(lab_inventory):
            inventory.append(lab_inventory)
            Log.success(f'Lab inventory disable_vagrant : {lab_inventory} file found')
        global_inventory = self._get_global_inventory()
        if global_inventory is not None:
            inventory.append(global_inventory)
        return inventory

    def run_disable_vagrant(self, disable_vagrant=True):
        inventory = self.get_disable_vagrant_inventory()
        if disable_vagrant:
            playbook = 'disable_vagrant.yml'
        else:
            playbook = 'enable_vagrant.yml'
        provision_result = self.run_playbook(playbook, inventory)
        if not provision_result:
            Log.error(f'Something wrong during the provisioning task : {playbook}')
            return False
        return provision_result
