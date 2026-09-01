import time

from goad.log import Log
from goad.provider.provider import Provider


class VagrantProvider(Provider):

    def __init__(self, lab_name):
        super().__init__(lab_name)
        self.jumpbox_setup_script = 'setup_local_jumpbox.sh'

    def check(self):
        checks = [
            self.command.check_vagrant(),
            self.command.check_disk(),
            self.command.check_ram(),
            self.command.check_ansible(),
            self.command.check_vagrant_plugin('vagrant-reload')
        ]
        return all(checks)

    def install(self):
        return self.command.run_vagrant(['up'], self.path)

    def destroy(self):
        return self.command.run_vagrant(['destroy'], self.path)

    def start(self):
        # GOAD_NOMAD's segmented VMware provider needs more than a bare
        # ``vagrant up``.  Protected-zone routing may need to be opened
        # temporarily, older Windows guests may require VMware Tools recovery,
        # and all five Ansible/WinRM endpoints must be proven healthy before the
        # lifecycle command can report success.  Reuse that provider's hardened
        # install/bring-up path, then restore the mode that was recorded before
        # start.  All other Vagrant providers retain the upstream behaviour.
        segmented = getattr(self, 'is_goad_nomad_segmented', None)
        if callable(segmented) and segmented():
            get_mode = getattr(self, 'get_runtime_mode', None)
            set_mode = getattr(self, 'set_runtime_mode', None)
            original_mode = get_mode() if callable(get_mode) else 'unknown'
            started = time.monotonic()

            Log.info(
                f'GOAD_NOMAD: hardened start using segmented lifecycle '
                f'(recorded mode: {original_mode})'
            )

            # Dynamic dispatch intentionally calls GoadNomadVmwareProvider.install()
            # here, not this base implementation. That path is provider-only: it
            # brings the router/guests up and validates management readiness; it
            # does not run the GOAD Ansible curriculum provisioning.
            if not self.install():
                elapsed = int(time.monotonic() - started)
                Log.error(
                    f'GOAD_NOMAD: start failed after {elapsed}s; '
                    'lab readiness was not proven'
                )
                return False

            if original_mode == 'exercise':
                if not callable(set_mode) or not set_mode('exercise'):
                    elapsed = int(time.monotonic() - started)
                    Log.error(
                        f'GOAD_NOMAD: guests started but exercise isolation '
                        f'could not be restored after {elapsed}s'
                    )
                    return False

            current_mode = get_mode() if callable(get_mode) else original_mode
            elapsed = int(time.monotonic() - started)
            Log.success(
                f'GOAD_NOMAD: segmented lab started and readiness verified '
                f'in {elapsed}s (mode: {current_mode})'
            )
            return True

        return self.command.run_vagrant(['up'], self.path)

    def stop(self):
        return self.command.run_vagrant(['halt'], self.path)

    def status(self):
        return self.command.run_vagrant(['status'], self.path)

    def snapshot(self):
        return self.command.run_vagrant(['snapshot', 'push'], self.path)

    def reset(self):
        return self.command.run_vagrant(['snapshot', 'pop', '--no-delete'], self.path)

    def destroy_vm(self, vm_name):
        return self.command.run_vagrant(['destroy', vm_name], self.path)

    def start_vm(self, vm_name):
        return self.command.run_vagrant(['up', vm_name], self.path)

    def stop_vm(self, vm_name):
        return self.command.run_vagrant(['halt', vm_name], self.path)

    def remove_extension(self, extension_name):
        # TODO one day if possible
        pass

    def get_jumpbox_ip(self, ip_range=''):
        return ip_range + '.3'
