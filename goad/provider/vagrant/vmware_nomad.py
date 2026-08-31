import os
import subprocess

from goad.goadpath import GoadPath
from goad.log import Log
from goad.provider.vagrant.vmware import VmwareProvider


class GoadNomadVmwareProvider(VmwareProvider):
    """VMware provider with the GOAD_NOMAD segmented lifecycle.

    The normal GOAD lab on VMware is segmented by default in this fork. Other
    labs using the VMware provider retain the upstream Vagrant behaviour.
    """

    network_scope = '10.4.0.0/16 (segmented)'
    network_zones = (
        ('NORTH', 'vmnet10', '10.4.10.0/24'),
        ('SEVENKINGDOMS', 'vmnet20', '10.4.20.0/24'),
        ('ESSOS', 'vmnet30', '10.4.30.0/24'),
        ('MANAGEMENT', 'vmnet99', '10.4.99.0/24'),
    )

    def is_goad_nomad_segmented(self):
        return self.lab_name == 'GOAD'

    @staticmethod
    def _project_root_from_script(script):
        return os.path.dirname(os.path.dirname(script))

    def _script(self, name):
        script = GoadPath.get_script_file(name)
        if not os.path.isfile(script):
            Log.error(f'GOAD_NOMAD helper not found: {script}')
            return None
        return script

    def _provider_env(self):
        env = os.environ.copy()
        env['GOAD_PROVIDER_DIR'] = str(self.path)
        return env

    def prepare_install(self):
        """Ensure the four GOAD_NOMAD VMware networks exist before Vagrant."""
        if not self.is_goad_nomad_segmented():
            return True

        check_script = self._script('check-vmware-networks.sh')
        setup_script = self._script('setup-vmware-networks.sh')
        if check_script is None or setup_script is None:
            return False

        Log.info('GOAD_NOMAD: checking segmented VMware networks')
        check = subprocess.run(['bash', check_script], check=False)
        if check.returncode == 0:
            Log.success('GOAD_NOMAD: segmented VMware networks already ready')
            return True

        Log.info('GOAD_NOMAD: preparing vmnet10/vmnet20/vmnet30/vmnet99')
        setup = subprocess.run(['sudo', 'bash', setup_script], check=False)
        if setup.returncode != 0:
            Log.error('GOAD_NOMAD: VMware network setup failed')
            return False

        check = subprocess.run(['bash', check_script], check=False)
        if check.returncode != 0:
            Log.error('GOAD_NOMAD: VMware network validation failed after setup')
            return False

        Log.success('GOAD_NOMAD: segmented VMware networks prepared')
        return True

    def get_network_scope(self):
        if self.is_goad_nomad_segmented():
            return self.network_scope
        return None

    def get_network_details(self):
        if not self.is_goad_nomad_segmented():
            return []
        return list(self.network_zones)

    def get_runtime_mode(self):
        if not self.is_goad_nomad_segmented() or self.path is None:
            return '-'
        state_file = os.path.join(str(self.path), '.goad-nomad-mode')
        if not os.path.isfile(state_file):
            return 'unknown'
        with open(state_file, 'r', encoding='utf-8') as handle:
            value = handle.read().strip()
        return value if value else 'unknown'

    def set_runtime_mode(self, mode):
        if not self.is_goad_nomad_segmented():
            Log.error('Runtime modes are only available for GOAD_NOMAD GOAD/VMware instances')
            return False

        if mode not in ('provisioning', 'exercise'):
            Log.error('GOAD_NOMAD mode must be provisioning or exercise')
            return False

        mode_script = self._script('lab-mode.sh')
        if mode_script is None:
            return False

        Log.info(f'GOAD_NOMAD: switching to {mode} mode')
        result = subprocess.run(
            ['bash', mode_script, mode],
            env=self._provider_env(),
            check=False,
        )
        return result.returncode == 0

    def prepare_provisioning(self):
        """Make the Vagrant/Ansible management plane available."""
        if not self.is_goad_nomad_segmented():
            return True
        if self.get_runtime_mode() == 'provisioning':
            return True
        return self.set_runtime_mode('provisioning')

    def finalize_install(self):
        """A successful full GOAD provisioning run must end in exercise mode."""
        if not self.is_goad_nomad_segmented():
            return True
        Log.info('GOAD_NOMAD: provisioning complete; enforcing final exercise isolation')
        return self.set_runtime_mode('exercise')

    def validate_runtime(self):
        if not self.is_goad_nomad_segmented():
            Log.error('GOAD_NOMAD runtime validation is only available for GOAD/VMware')
            return False

        validator = self._script('validate-network-segmentation.sh')
        if validator is None:
            return False

        root = self._project_root_from_script(validator)
        Log.info('GOAD_NOMAD: launching clean network-segmentation runtime validation')
        result = subprocess.run(
            ['bash', validator],
            cwd=root,
            env=self._provider_env(),
            check=False,
        )
        return result.returncode == 0

    def status(self):
        result = super().status()
        if self.is_goad_nomad_segmented():
            Log.info(f'GOAD_NOMAD Network : {self.network_scope}')
            Log.info(f'GOAD_NOMAD Mode    : {self.get_runtime_mode()}')
        return result

    def install(self):
        if not self.is_goad_nomad_segmented():
            return super().install()

        if not self.prepare_install():
            return False

        # Reuse the already hardened GOAD VMware bring-up: router first,
        # per-Windows-VM VMware Tools recovery, then temporary provisioning
        # routes. Once Vagrant is healthy, make provisioning mode explicit and
        # persistent through the same controller used during training.
        if not super().install():
            return False

        return self.set_runtime_mode('provisioning')
