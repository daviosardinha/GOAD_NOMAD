import os
import subprocess

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

    def _ensure_vmware_tools(self, machine):
        """Repair VMware Tools and finish the interrupted Vagrant provision cycle.

        On a genuinely fresh StefanScherer Windows box, ``vagrant up`` can boot
        far enough for forwarded WinRM to work but fail before the shell
        provisioners because VMware Tools are absent. Installing Tools repairs
        guest communication, but simply calling ``vagrant up`` again is not
        sufficient: Vagrant may already consider the machine provisioned and
        skip the WMF/WinRM/fix_ip shell stages.

        Therefore, only when Tools actually had to be installed, force a clean
        power cycle and explicitly rerun Vagrant provisioning. The outer
        VmwareProvider retry remains harmless and sees an already healthy guest.
        """
        vmx = self._vmx_path(machine)
        if not vmx:
            Log.error(f'GOAD_NOMAD: cannot locate VMX path for {machine}')
            return False

        port = self._winrm_forwarded_port(machine)
        if not port:
            Log.error(f'GOAD_NOMAD: cannot determine forwarded WinRM port for {machine}')
            return False

        if not self._wait_tcp(port, 120):
            Log.error(f'GOAD_NOMAD: forwarded WinRM port {port} is not reachable for {machine}')
            return False

        if self._guest_tools_healthy(port):
            if not self._wait_guest_ip(vmx, 60):
                Log.warning(
                    f'GOAD_NOMAD: {machine} VMware Tools are healthy but guest IP reporting is delayed'
                )
            return True

        if not self._install_vmware_tools(machine, vmx, port):
            return False

        Log.warning(
            f'GOAD Kingdoms: {machine} VMware Tools were recovered after an '
            'interrupted Vagrant bring-up; forcing a clean provision cycle'
        )
        if not self._run_vagrant_bounded(['halt', machine, '-f'], timeout=60):
            Log.error(
                f'GOAD Kingdoms: could not power-cycle {machine} after VMware Tools recovery'
            )
            return False

        if not self.command.run_vagrant(['up', machine, '--provision'], self.path):
            Log.error(
                f'GOAD Kingdoms: {machine} failed the post-Tools Vagrant --provision recovery cycle'
            )
            return False

        Log.success(
            f'GOAD Kingdoms: {machine} completed a clean post-Tools Vagrant provision cycle'
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
