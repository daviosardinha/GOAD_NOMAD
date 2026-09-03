import os
import subprocess

from goad.goadpath import GoadPath
from goad.log import Log
from goad.provider.vagrant.vmware_nomad import GoadNomadVmwareProvider


class GoadKingdomsVmwareProvider(GoadNomadVmwareProvider):
    """GOAD Kingdoms VMware provider policy layered over the M1 lifecycle.

    ``GoadNomadVmwareProvider`` remains the compatibility implementation that
    owns the already-validated segmented lifecycle. New GOAD Kingdoms safety
    policy is added here so M2 changes do not casually rewrite the M1 core.
    """

    def _require_cached_sudo(self):
        """Require an already-authenticated sudo timestamp without prompting.

        GOAD Kingdoms lifecycle commands must never stop deep inside a provider
        transition waiting for an unexpected password prompt. The operator owns
        interactive authentication explicitly with ``sudo -v`` before invoking
        install/start/ws01. Every provider entry/mode transition refreshes that
        timestamp non-interactively and fails before changing runtime state if
        credentials are unavailable or expired.
        """
        result = subprocess.run(
            ['sudo', '-n', '-v'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = result.stderr.strip()
            if detail:
                Log.error(f'GOAD Kingdoms: sudo cache unavailable: {detail}')
            Log.error(
                'GOAD Kingdoms: administrative credentials are not cached; '
                'run `sudo -v` in this terminal, then repeat the command'
            )
            return False

        return True

    def _check_segmented_instance_conflicts(self):
        if not self.is_goad_nomad_segmented():
            return True

        if self.path is None:
            Log.error('GOAD Kingdoms: provider path is unavailable for collision preflight')
            return False

        guard = self._script('check-vmware-instance-conflicts.sh')
        if guard is None:
            return False

        Log.info('GOAD Kingdoms: checking for conflicting running segmented VMware instances')
        result = subprocess.run(
            ['bash', guard, os.path.realpath(str(self.path))],
            check=False,
        )
        if result.returncode != 0:
            Log.error(
                'GOAD Kingdoms: VMware bring-up blocked because another running '
                'guest owns one or more deterministic segmented MAC identities'
            )
            return False

        Log.success('GOAD Kingdoms: segmented VMware instance collision preflight passed')
        return True

    def _recover_failed_windows_vagrant_up(self, machine):
        """Recover a failed fresh Windows ``vagrant up`` deterministically.

        A failed first bring-up does not necessarily mean VMware Tools are
        absent. Fresh StefanScherer guests can already have healthy Tools and a
        working forwarded WinRM endpoint while Vagrant's VMware guest channel
        still fails during adapter/provisioner setup. Retrying ``vagrant up`` on
        the running VM is unreliable and may either skip provisioning or fail
        again in the first shell provisioner.

        After the common Tools/readiness gate has succeeded, every failed first
        bring-up therefore receives the same recovery treatment: force the VM
        off, boot it through a clean Vagrant communicator lifecycle, and rerun
        all shell provisioners explicitly.
        """
        Log.warning(
            f'GOAD Kingdoms: {machine} first Vagrant bring-up failed despite '
            'recoverable guest readiness; forcing a clean provision cycle'
        )

        if not self._run_vagrant_bounded(['halt', machine, '-f'], timeout=60):
            Log.error(
                f'GOAD Kingdoms: could not power-cycle {machine} after failed Vagrant bring-up'
            )
            return False

        if not self.command.run_vagrant(['up', machine, '--provision'], self.path):
            Log.error(
                f'GOAD Kingdoms: {machine} failed the clean Vagrant --provision recovery cycle'
            )
            return False

        Log.success(
            f'GOAD Kingdoms: {machine} completed a clean failed-bring-up recovery provision cycle'
        )
        return True

    def install(self):
        """Bring up a segmented GOAD instance with fail-closed Windows recovery."""
        if self.lab_name != 'GOAD':
            return super().install()

        if not self._sync_goad_nomad_inventories():
            return False

        if not self._sync_goad_nomad_vagrantfile_compatibility():
            return False

        # Bring up the router independently so a Windows guest failure cannot
        # prevent creation of the routing plane. Linux keeps the normal SSH path.
        Log.info('GOAD_NOMAD: bringing up segmented router')
        if not self.command.run_vagrant(['up', 'GOAD-ROUTER'], self.path):
            Log.error('GOAD_NOMAD: failed to bring up GOAD-ROUTER')
            return False

        # A fresh Windows box can fail its first VMware/Vagrant guest operation
        # for two different reasons: Tools may genuinely be absent, or Tools may
        # already be healthy while Vagrant's guest-communication/provisioner
        # transition is still unstable. _ensure_vmware_tools() covers the first
        # case and proves baseline guest readiness for both. Any failed first
        # vagrant up then gets one clean halt -> up --provision recovery cycle.
        for machine in self.goad_nomad_windows:
            Log.info(f'GOAD_NOMAD: bringing up {machine}')
            first_up = self.command.run_vagrant(['up', machine], self.path)

            if not self._ensure_vmware_tools(machine):
                return False

            if not first_up:
                if not self._recover_failed_windows_vagrant_up(machine):
                    Log.error(
                        f'GOAD_NOMAD: {machine} still failed after clean Vagrant recovery'
                    )
                    return False

        # The host has no vmnet20/vmnet30 adapters, so local Ansible must
        # temporarily reach those protected networks through GOAD-ROUTER after
        # Vagrant has brought the complete instance up.
        route_script = GoadPath.get_script_file('provisioning-routes.sh')
        if not os.path.isfile(route_script):
            Log.error(f'GOAD_NOMAD provisioning route helper not found: {route_script}')
            return False

        Log.info('GOAD_NOMAD: enabling temporary host routes for local Ansible provisioning')
        route_result = subprocess.run(['sudo', 'bash', route_script, 'enable'], check=False)
        if route_result.returncode != 0:
            Log.error('GOAD_NOMAD: failed to enable temporary provisioning routes')
            return False

        Log.warning(
            'GOAD_NOMAD: provisioning routes are temporary and must be removed before exercise mode'
        )
        return True

    def prepare_install(self):
        # This method is the first provider hook executed by the hardened
        # install/start/ws01 paths, before GOAD-ROUTER or any Windows guest is
        # powered on. Refuse to create a duplicate-MAC condition before VMware
        # has an opportunity to register the conflicting adapter. Require the
        # operator to prime sudo before entering the lifecycle as well.
        if not self._check_segmented_instance_conflicts():
            return False
        if not self._require_cached_sudo():
            return False
        return super().prepare_install()

    def set_runtime_mode(self, mode):
        # Re-check immediately before every provisioning/exercise transition.
        # This covers long-running starts where the sudo timestamp may have
        # expired since prepare_install() and prevents the compatibility mode
        # controller from ever becoming an interactive password prompt.
        if self.is_goad_nomad_segmented() and not self._require_cached_sudo():
            return False
        return super().set_runtime_mode(mode)
