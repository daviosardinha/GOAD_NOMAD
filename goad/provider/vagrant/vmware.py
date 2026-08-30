import os
import subprocess

from goad.goadpath import GoadPath
from goad.log import Log
from goad.provider.vagrant.vagrant import VagrantProvider
from goad.utils import *


class VmwareProvider(VagrantProvider):
    provider_name = VMWARE
    default_provisioner = PROVISIONING_LOCAL
    allowed_provisioners = [PROVISIONING_LOCAL, PROVISIONING_RUNNER, PROVISIONING_DOCKER, PROVISIONING_VM]

    def check(self):
        checks = [
            super().check(),
            self.command.check_vmware(),
            self.command.check_vmware_utility(),
            self.command.check_vagrant_plugin('vagrant-vmware-desktop', True)
        ]
        return all(checks)

    def install(self):
        """Bring up VMware guests and prepare GOAD_NOMAD local provisioning reachability."""
        result = super().install()
        if not result:
            return False

        # GOAD_NOMAD's VMware GOAD lab is intentionally multi-subnet. The host
        # has no vmnet20/vmnet30 adapters, so local Ansible must temporarily
        # reach those protected networks through GOAD-ROUTER after Vagrant has
        # brought the complete instance up. Other labs/providers keep upstream
        # behaviour unchanged.
        if self.lab_name != 'GOAD':
            return True

        route_script = GoadPath.get_script_file('provisioning-routes.sh')
        if not os.path.isfile(route_script):
            Log.error(f'GOAD_NOMAD provisioning route helper not found: {route_script}')
            return False

        Log.info('GOAD_NOMAD: enabling temporary host routes for local Ansible provisioning')
        route_result = subprocess.run(['sudo', route_script, 'enable'], check=False)
        if route_result.returncode != 0:
            Log.error('GOAD_NOMAD: failed to enable temporary provisioning routes')
            return False

        Log.warning('GOAD_NOMAD: provisioning routes are temporary and must be removed before exercise mode')
        return True
