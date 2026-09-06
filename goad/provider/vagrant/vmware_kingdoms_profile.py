import time

from goad.log import Log
from goad.provider.vagrant.vmware_kingdoms import GoadKingdomsVmwareProvider


class ProfiledGoadKingdomsVmwareProvider(GoadKingdomsVmwareProvider):
    """Instrumentation-only wrapper for fresh KINGDOMS installation timing.

    The underlying provider remains authoritative for every lifecycle decision.
    This subclass only measures existing calls and restores the original Vagrant
    command method after ``install`` returns. Normal installed start/stop paths
    are untouched.
    """

    @staticmethod
    def _format_install_elapsed(seconds):
        total = max(0, int(round(seconds)))
        minutes, secs = divmod(total, 60)
        hours, minutes = divmod(minutes, 60)
        if hours:
            return f'{hours}h {minutes:02d}m {secs:02d}s'
        return f'{minutes}m {secs:02d}s'

    def _record_install_profile(self, label, started):
        elapsed = time.monotonic() - started
        profile = getattr(self, '_kingdoms_install_profile', None)
        if isinstance(profile, dict):
            profile.setdefault('phases', []).append({
                'label': label,
                'seconds': elapsed,
            })
        Log.info(
            f'GOAD Kingdoms install timing: {label} = '
            f'{self._format_install_elapsed(elapsed)}'
        )
        return elapsed

    def _profile_call(self, label, func, *args, **kwargs):
        if not getattr(self, '_kingdoms_install_profile_active', False):
            return func(*args, **kwargs)
        started = time.monotonic()
        try:
            return func(*args, **kwargs)
        finally:
            self._record_install_profile(label, started)

    @staticmethod
    def _vagrant_profile_label(args):
        if isinstance(args, (list, tuple)):
            rendered = ' '.join(str(part) for part in args)
            if len(args) >= 2 and args[0] == 'up':
                if '--provision' in args:
                    return f'Vagrant recovery up --provision {args[1]}'
                return f'Vagrant first up {args[1]}'
            if len(args) >= 2 and args[0] == 'halt':
                return f'Vagrant halt {args[1]}'
            return f'Vagrant {rendered}'
        return 'Vagrant command'

    def install(self):
        if self.lab_name != 'GOAD':
            return super().install()

        started = time.monotonic()
        self._kingdoms_install_profile = {
            'started': started,
            'phases': [],
            'provider_success': False,
        }
        self._kingdoms_install_profile_active = True

        original_run_vagrant = self.command.run_vagrant

        def timed_run_vagrant(*args, **kwargs):
            command_args = args[0] if args else kwargs.get('args')
            phase_started = time.monotonic()
            try:
                return original_run_vagrant(*args, **kwargs)
            finally:
                self._record_install_profile(
                    self._vagrant_profile_label(command_args),
                    phase_started,
                )

        self.command.run_vagrant = timed_run_vagrant
        result = False
        try:
            result = super().install()
            return result
        finally:
            self.command.run_vagrant = original_run_vagrant
            elapsed = time.monotonic() - started
            profile = self._kingdoms_install_profile
            profile['provider_elapsed'] = elapsed
            profile['provider_success'] = bool(result)
            self._kingdoms_install_profile_active = False
            message = (
                'GOAD Kingdoms install timing: provider bring-up total = '
                f'{self._format_install_elapsed(elapsed)}'
            )
            if result:
                Log.success(message)
            else:
                Log.warning(message + ' (incomplete)')

    def prepare_install(self):
        return self._profile_call(
            'Host/network preflight',
            super().prepare_install,
        )

    def _sync_goad_nomad_inventories(self):
        return self._profile_call(
            'Generated inventory synchronization',
            super()._sync_goad_nomad_inventories,
        )

    def _sync_goad_nomad_vagrantfile_compatibility(self):
        return self._profile_call(
            'Generated Vagrantfile compatibility synchronization',
            super()._sync_goad_nomad_vagrantfile_compatibility,
        )

    def _bring_up_router(self):
        return self._profile_call(
            'GOAD-ROUTER bring-up',
            super()._bring_up_router,
        )

    def _ensure_vmware_tools(self, machine):
        return self._profile_call(
            f'{machine} VMware Tools / forwarded WinRM readiness',
            super()._ensure_vmware_tools,
            machine,
        )

    def _recover_failed_windows_vagrant_up(self, machine):
        return self._profile_call(
            f'{machine} failed-first-up recovery cycle',
            super()._recover_failed_windows_vagrant_up,
            machine,
        )

    def _run_vagrant_bounded(self, args, timeout):
        label = 'Bounded ' + self._vagrant_profile_label(args)
        return self._profile_call(
            label,
            super()._run_vagrant_bounded,
            args,
            timeout,
        )
