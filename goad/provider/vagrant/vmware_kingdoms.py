import os
import signal
import subprocess
import time

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
        transition waiting for an unexpected password prompt. Long install/ws01
        lifecycles prime sudo once at the console boundary and refresh it with a
        non-interactive keepalive. Direct provider/mode operations still require
        an existing sudo cache. Every privileged transition re-checks the cache
        non-interactively and fails before changing runtime state if credentials
        are unavailable or expired.
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

    @staticmethod
    def _process_group_alive(pgid):
        """Return whether a locally-owned process group still has members."""
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        return True

    def _wait_process_group_gone(self, process, timeout):
        """Reap the direct child and wait until its whole process group is gone."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            process.poll()
            if not self._process_group_alive(process.pid):
                return True
            time.sleep(0.2)

        process.poll()
        return not self._process_group_alive(process.pid)

    def _reap_vagrant_process_group(self, process, command):
        """Terminate every process from a timed-out Vagrant controller.

        ``subprocess.run(..., timeout=...)`` only guarantees that Python reaps
        the direct Vagrant process. Vagrant/Ruby descendants can outlive that
        parent and retain per-machine action locks. The shutdown fallback must
        never start while the timed-out controller can still mutate the same VM.
        """
        rendered = ' '.join(command)
        pgid = process.pid

        if not self._process_group_alive(pgid):
            process.poll()
            return True

        Log.warning(
            f'GOAD Kingdoms: terminating timed-out Vagrant process group for: {rendered}'
        )
        try:
            os.killpg(pgid, signal.SIGTERM)
        except ProcessLookupError:
            process.poll()
            return True
        except OSError as exc:
            Log.error(
                f'GOAD Kingdoms: could not terminate Vagrant process group {pgid}: {exc}'
            )
            return False

        if self._wait_process_group_gone(process, 5):
            Log.success('GOAD Kingdoms: timed-out Vagrant process group fully reaped')
            return True

        Log.warning(
            'GOAD Kingdoms: Vagrant descendants survived SIGTERM; '
            'sending SIGKILL before any fallback'
        )
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            process.poll()
            return True
        except OSError as exc:
            Log.error(
                f'GOAD Kingdoms: could not kill Vagrant process group {pgid}: {exc}'
            )
            return False

        if not self._wait_process_group_gone(process, 5):
            Log.error(
                'GOAD Kingdoms: timed-out Vagrant process group is still alive; '
                'refusing to race a second lifecycle action'
            )
            return False

        Log.success('GOAD Kingdoms: timed-out Vagrant process group fully reaped')
        return True

    def _run_vagrant_bounded(self, args, timeout):
        """Run Vagrant in an isolated process group and fully reap it on timeout."""
        command = [self.command.vagrant_bin] + args
        Log.info(f'GOAD_NOMAD: running bounded command: {" ".join(command)}')
        self._last_bounded_vagrant_reaped = True

        try:
            process = subprocess.Popen(
                command,
                cwd=self.path,
                start_new_session=True,
            )
        except OSError as exc:
            Log.error(f'GOAD Kingdoms: failed to start {" ".join(command)}: {exc}')
            return False

        try:
            return process.wait(timeout=timeout) == 0
        except subprocess.TimeoutExpired:
            Log.warning(
                f'GOAD_NOMAD: {" ".join(command)} exceeded {timeout}s; '
                'reaping the entire Vagrant process group before fallback'
            )
            self._last_bounded_vagrant_reaped = self._reap_vagrant_process_group(
                process,
                command,
            )
            return False

    def _wait_machine_stopped(self, machine, timeout=120):
        """Wait until VMware no longer reports ``machine`` as running."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            running = self._running_instance_vms()
            if running is None:
                return False
            if machine not in running:
                return True
            time.sleep(3)
        return False

    def _stop_machine_via_vmware(self, machine):
        """Stop one leftover guest without entering Vagrant's action-lock path."""
        vmx = self._vmx_path(machine)
        if not vmx:
            Log.error(f'GOAD Kingdoms: cannot locate VMX for shutdown fallback: {machine}')
            return False

        Log.warning(
            f'GOAD Kingdoms: {machine} still running after bounded Vagrant halt; '
            'trying VMware Tools soft shutdown'
        )
        try:
            soft = subprocess.run(
                ['vmrun', '-T', 'ws', 'stop', vmx, 'soft'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=45,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            Log.warning(f'GOAD Kingdoms: VMware soft stop failed for {machine}: {exc}')
        else:
            if self._wait_machine_stopped(machine, 60):
                Log.success(f'GOAD Kingdoms: {machine} completed VMware soft shutdown')
                return True
            detail = soft.stderr.strip() or soft.stdout.strip()
            if detail:
                Log.warning(f'GOAD Kingdoms: VMware soft stop for {machine}: {detail}')

        Log.warning(
            f'GOAD Kingdoms: {machine} did not stop softly; '
            'using VMware hard stop as the final fallback'
        )
        try:
            hard = subprocess.run(
                ['vmrun', '-T', 'ws', 'stop', vmx, 'hard'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=30,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            Log.error(f'GOAD Kingdoms: VMware hard stop failed for {machine}: {exc}')
            return False

        if self._wait_machine_stopped(machine, 30):
            Log.success(f'GOAD Kingdoms: {machine} stopped by VMware hard fallback')
            return True

        detail = hard.stderr.strip() or hard.stdout.strip()
        if detail:
            Log.error(f'GOAD Kingdoms: VMware hard stop for {machine}: {detail}')
        Log.error(f'GOAD Kingdoms: {machine} is still running after VMware hard fallback')
        return False

    def _stop_failed_windows_guest_cleanly(self, machine):
        """Stop a recoverable Windows guest without hard-powering it off first.

        Older StefanScherer Windows Server 2016 boxes can reach the desktop while
        VMware Tools/WSMan becomes unhealthy after an unconditional ``halt -f``.
        At this point ``_ensure_vmware_tools`` has already proved WinRM/Tools
        readiness, so prefer an in-guest Windows shutdown. If the transport tears
        down before returning, VMware power state remains authoritative. A VMware
        Tools soft stop is the second graceful path; forced Vagrant halt is only
        the final bounded fallback.
        """
        port = self._winrm_forwarded_port(machine)
        if port and self._wait_winrm_ready(port, 30):
            Log.info(f'GOAD Kingdoms: requesting graceful in-guest shutdown for {machine}')
            try:
                self._winrm_session(port).run_ps(
                    "shutdown.exe /s /t 0 /f | Out-Null"
                )
            except Exception as exc:
                # A successful shutdown normally destroys WinRM before pywinrm
                # receives a response. Power state below decides success.
                Log.warning(
                    f'GOAD Kingdoms: {machine} shutdown command interrupted WinRM: {exc}'
                )

            if self._wait_machine_stopped(machine, 120):
                Log.success(f'GOAD Kingdoms: {machine} completed graceful Windows shutdown')
                return True

        vmx = self._vmx_path(machine)
        if vmx:
            Log.warning(
                f'GOAD Kingdoms: {machine} did not stop through WinRM; '
                'trying VMware Tools soft shutdown'
            )
            try:
                soft = subprocess.run(
                    ['vmrun', '-T', 'ws', 'stop', vmx, 'soft'],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                    timeout=45,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                Log.warning(f'GOAD Kingdoms: VMware soft stop failed for {machine}: {exc}')
            else:
                if soft.returncode == 0 and self._wait_machine_stopped(machine, 120):
                    Log.success(f'GOAD Kingdoms: {machine} completed VMware soft shutdown')
                    return True
                detail = soft.stderr.strip() or soft.stdout.strip()
                if detail:
                    Log.warning(f'GOAD Kingdoms: VMware soft stop for {machine}: {detail}')

        Log.warning(
            f'GOAD Kingdoms: graceful shutdown paths did not stop {machine}; '
            'using bounded forced halt as final fallback'
        )
        if not self._run_vagrant_bounded(['halt', machine, '-f'], timeout=45):
            Log.error(f'GOAD Kingdoms: forced halt failed for {machine}')
            return False
        if not self._wait_machine_stopped(machine, 60):
            Log.error(f'GOAD Kingdoms: {machine} is still running after forced halt')
            return False
        return True

    def _recover_failed_windows_vagrant_up(self, machine):
        """Recover a failed fresh Windows ``vagrant up`` deterministically.

        A failed first bring-up does not necessarily mean VMware Tools are
        absent. Fresh StefanScherer guests can already have healthy Tools and a
        working forwarded WinRM endpoint while Vagrant's VMware guest channel
        still fails during adapter/provisioner setup.

        Recovery therefore preserves the now-proven guest state: shut Windows
        down gracefully first, verify VMware reports it stopped, then execute one
        bounded ``vagrant up --provision`` cycle. Finally re-prove VMware Tools
        and authenticated WinRM readiness before allowing installation to move to
        the next machine.
        """
        Log.warning(
            f'GOAD Kingdoms: {machine} first Vagrant bring-up failed despite '
            'recoverable guest readiness; starting a clean recovery provision cycle'
        )

        if not self._stop_failed_windows_guest_cleanly(machine):
            Log.error(
                f'GOAD Kingdoms: could not stop {machine} safely after failed Vagrant bring-up'
            )
            return False

        if not self._run_vagrant_bounded(['up', machine, '--provision'], timeout=600):
            Log.error(
                f'GOAD Kingdoms: {machine} failed the bounded Vagrant --provision recovery cycle'
            )
            return False

        if not self._ensure_vmware_tools(machine):
            Log.error(
                f'GOAD Kingdoms: {machine} completed Vagrant recovery but VMware Tools/WinRM '
                'did not return healthy'
            )
            return False

        Log.success(
            f'GOAD Kingdoms: {machine} completed a clean failed-bring-up recovery provision cycle'
        )
        return True

    def stop(self):
        """Stop GOAD Kingdoms without racing a timed-out Vagrant controller."""
        if self.lab_name != 'GOAD':
            return super().stop()

        running = self._running_instance_vms()
        if running is None:
            return False
        if not running:
            Log.success('GOAD_NOMAD: all instance VMs are already stopped')
            return True

        Log.info(
            'GOAD_NOMAD: stopping lab gracefully with a bounded controller timeout '
            f'({", ".join(running)})'
        )
        graceful = self._run_vagrant_bounded(['halt'], timeout=180)

        if not graceful and not getattr(self, '_last_bounded_vagrant_reaped', True):
            Log.error(
                'GOAD Kingdoms: timed-out Vagrant controller could not be fully reaped; '
                'refusing shutdown fallback to avoid a per-machine action-lock race'
            )
            return False

        remaining = self._running_instance_vms()
        if remaining is None:
            return False

        if remaining and not graceful:
            Log.info(
                'GOAD Kingdoms: bounded Vagrant halt ended; allowing 30s for '
                'already-requested guest shutdowns to finish'
            )
            deadline = time.time() + 30
            while remaining and time.time() < deadline:
                time.sleep(3)
                remaining = self._running_instance_vms()
                if remaining is None:
                    return False

        if remaining:
            Log.warning(
                'GOAD Kingdoms: graceful shutdown did not finish for: '
                + ', '.join(remaining)
                + '; using lock-free VMware fallback only for those guests'
            )
            for machine in list(remaining):
                self._stop_machine_via_vmware(machine)

        remaining = self._running_instance_vms()
        if remaining is None:
            return False
        if remaining:
            Log.error(
                'GOAD Kingdoms: shutdown incomplete; still running: '
                + ', '.join(remaining)
            )
            return False

        Log.success(
            'GOAD Kingdoms: all instance VMs stopped and VMware state verified'
        )
        return True

    def install(self):
        """Bring up a segmented GOAD instance with fail-closed Windows recovery."""
        if self.lab_name != 'GOAD':
            return super().install()

        # This override owns the complete Kingdoms bring-up path, so it must
        # explicitly retain the inherited host-network preflight.  Without it,
        # a missing host-address helper/timer was discovered only after every
        # guest had spent minutes coming up and provisioning routes were finally
        # enabled.  Fail (or repair the host setup) before touching any VM.
        if not self.prepare_install():
            Log.error(
                'GOAD Kingdoms: segmented VMware host-network preflight failed; '
                'no guest bring-up was attempted'
            )
            return False

        if not self._sync_goad_nomad_inventories():
            return False

        if not self._sync_goad_nomad_vagrantfile_compatibility():
            return False

        # Bring up the router independently so a Windows guest failure cannot
        # prevent creation of the routing plane. Linux keeps the normal SSH path.
        Log.info('GOAD_NOMAD: bringing up segmented router')
        if not self._bring_up_router():
            Log.error('GOAD_NOMAD: failed to bring up GOAD-ROUTER')
            return False

        # A fresh Windows box can fail its first VMware/Vagrant guest operation
        # for two different reasons: Tools may genuinely be absent, or Tools may
        # already be healthy while Vagrant's guest-communication/provisioner
        # transition is still unstable. _ensure_vmware_tools() covers the first
        # case and proves baseline guest readiness for both. Any failed first
        # vagrant up then gets one clean graceful-stop -> up --provision recovery.
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
        route_result = subprocess.run(
            ['sudo', '-n', 'bash', route_script, 'enable'],
            check=False,
        )
        if route_result.returncode != 0:
            Log.error('GOAD_NOMAD: failed to enable temporary provisioning routes')
            return False

        Log.warning(
            'GOAD_NOMAD: provisioning routes are temporary and must be removed before exercise mode'
        )
        return True

    def _bring_up_router(self):
        """Installed ranges use local power-on and deterministic management SSH.

        A recorded mode identifies an existing managed deployment. An unknown
        or fresh deployment retains the Vagrant provisioning path. Never fall
        back to NAT after a management failure and obscure the original error.
        """
        if self.get_runtime_mode() not in ('exercise', 'provisioning'):
            return self.command.run_vagrant(['up', 'GOAD-ROUTER'], self.path)

        vmx = self._vmx_path('GOAD-ROUTER')
        if not vmx:
            Log.error('GOAD Kingdoms: installed router VMX is missing; refusing to recreate it during start')
            return False
        running = self._running_instance_vms()
        if running is None:
            return False
        try:
            if 'GOAD-ROUTER' not in running:
                result = subprocess.run(
                    ['vmrun', '-T', 'ws', 'start', vmx, 'nogui'],
                    check=False, timeout=60,
                )
                if result.returncode != 0:
                    Log.error('GOAD Kingdoms: local router power-on failed')
                    return False

            # VMware can recreate the host interfaces during power-on. Repair
            # synchronously, then validate before using the router's .1 address.
            repair = subprocess.run(
                ['sudo', '-n', 'systemctl', 'restart',
                 'goad-nomad-vmnet-hostaddrs.service'],
                check=False, timeout=50,
            )
            checker = self._script('check-vmware-networks.sh')
            ssh = self._script('router-ssh.sh')
            if repair.returncode != 0 or checker is None or ssh is None:
                return False
            if subprocess.run(['bash', checker], check=False, timeout=30).returncode != 0:
                return False

            Log.info('GOAD Kingdoms: waiting for router management SSH at 10.4.99.1:22')
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                try:
                    ready = subprocess.run(
                        ['bash', ssh,
                         'test "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 && '
                         'sudo -n systemctl is-active --quiet nftables'],
                        env=self._provider_env(), check=False, timeout=15,
                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                        text=True,
                    )
                    if ready.returncode == 0:
                        Log.success('GOAD Kingdoms: router management ready without NAT discovery')
                        return True
                except subprocess.TimeoutExpired:
                    pass
                time.sleep(3)
        except (OSError, subprocess.TimeoutExpired) as exc:
            Log.error(f'GOAD Kingdoms: local router startup failed: {exc}')
            return False

        Log.error(
            'GOAD Kingdoms: router management did not become ready within 180s; '
            'check vmnet99, the router SSH service/key and nftables. '
            'No NAT fallback or router reprovisioning was attempted.'
        )
        return False

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
