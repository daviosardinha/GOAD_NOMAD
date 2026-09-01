"""GOAD_NOMAD console entry point.

This module deliberately subclasses the upstream-style ``goad.py`` console
rather than duplicating the project controller. ``./goad.sh`` remains the
canonical entry point while GOAD_NOMAD can add segmented-network operations
without making future upstream merges unnecessarily invasive.
"""

import argparse
from pathlib import Path
import runpy
import sys
import threading
import time

from goad.log import Log
from goad.menu import print_menu_entry, print_menu_title
from goad.utils import PROVIDED, READY


_upstream = runpy.run_path(
    str(Path(__file__).with_name('goad.py')),
    run_name='goad_upstream_console',
)

BaseGoad = _upstream['Goad']
print_logo = _upstream['print_logo']


class GoadNomad(BaseGoad):
    """GOAD console plus GOAD_NOMAD segmented-network lifecycle commands."""

    @staticmethod
    def _format_elapsed(seconds):
        total = max(0, int(seconds))
        hours, remainder = divmod(total, 3600)
        minutes, secs = divmod(remainder, 60)
        return f'{hours:02d}:{minutes:02d}:{secs:02d}'

    def _run_with_install_timer(self, operation):
        """Run an install operation with a visible one-minute heartbeat.

        Vagrant/WinRM can legitimately spend many minutes booting older Windows
        guests.  A periodic elapsed-time line keeps that wait observable without
        changing Vagrant's own output or timeout semantics.
        """
        if getattr(self, '_install_timer_active', False):
            return operation()

        self._install_timer_active = True
        self._install_phase = 'starting'
        started = time.monotonic()
        stop_event = threading.Event()

        def heartbeat():
            while not stop_event.wait(60):
                elapsed = self._format_elapsed(time.monotonic() - started)
                phase = getattr(self, '_install_phase', 'unknown')
                Log.info(f'GOAD_NOMAD TIMER: {elapsed} elapsed | phase: {phase}')

        timer_thread = threading.Thread(
            target=heartbeat,
            name='goad-nomad-install-timer',
            daemon=True,
        )
        timer_thread.start()
        Log.info('GOAD_NOMAD TIMER: install timer started (heartbeat every 60s)')

        try:
            return operation()
        finally:
            stop_event.set()
            timer_thread.join(timeout=1)
            elapsed = self._format_elapsed(time.monotonic() - started)
            Log.info(f'GOAD_NOMAD TIMER: install command finished after {elapsed}')
            self._install_phase = 'idle'
            self._install_timer_active = False

    def _configured_provider(self):
        current = self.lab_manager.get_current_instance_provider()
        if current is not None:
            return current

        lab = self.lab_manager.get_lab(self.lab_manager.get_current_lab_name())
        if lab is None:
            return None
        return lab.get_provider(self.lab_manager.get_current_provider_name())

    def _nomad_provider(self, require_instance=False):
        if require_instance:
            provider = self.lab_manager.get_current_instance_provider()
        else:
            provider = self._configured_provider()

        if provider is None:
            return None

        check = getattr(provider, 'is_goad_nomad_segmented', None)
        if callable(check) and check():
            return provider
        return None

    def do_install(self, arg=''):
        """Run the canonical interactive install with a total elapsed timer."""
        return self._run_with_install_timer(lambda: self.do_create(arg))

    def do_provide(self, arg=''):
        """Run the provider and return the result from *this* attempt.

        Stock GOAD's interactive install path historically checks the persisted
        instance status after ``do_provide``.  On a retry, an instance may still
        carry ``ready for provisioning`` from an earlier successful provider
        run.  If the current provider attempt then fails, that stale status can
        incorrectly allow Ansible to start against partially available VMs.

        GOAD_NOMAD treats the current provider return value as authoritative.
        """
        provider = self.lab_manager.get_current_instance_provider()
        if provider is None:
            Log.error('No provider loaded for the current instance')
            return False

        self._install_phase = 'provider bring-up / VM readiness'
        phase_started = time.monotonic()
        result = provider.install()
        phase_elapsed = self._format_elapsed(time.monotonic() - phase_started)

        if not result:
            Log.error(
                f'GOAD_NOMAD: provider bring-up failed after {phase_elapsed}; '
                'Ansible provisioning will not start'
            )
            return False

        Log.success(f'GOAD_NOMAD TIMER: provider bring-up completed in {phase_elapsed}')
        self.lab_manager.get_current_instance().set_status(PROVIDED)

        # Preserve upstream dynamic-IP behaviour for providers that need it.
        if getattr(provider, 'update_ip_range', False):
            Log.info('Update IP range')
            new_range = provider.get_ip_range()
            if new_range is not None:
                Log.info(f'new range : {new_range}')
                self.lab_manager.get_current_instance().update_ip_range(new_range)
                Log.info('reload instance')
                instance_id = self.lab_manager.get_current_instance_id()
                self.do_load(instance_id)
                self.refresh_prompt()

        return True

    def do_install_instance(self, arg=''):
        """Install/retry an existing instance without trusting stale status."""
        if not getattr(self, '_install_timer_active', False):
            return self._run_with_install_timer(
                lambda: self._do_install_instance(arg)
            )
        return self._do_install_instance(arg)

    def _do_install_instance(self, arg=''):
        Log.info('Launch providing')
        if not self.do_provide():
            Log.error('Providing error stop')
            self.refresh_prompt()
            return False

        Log.info('Prepare jumpbox if needed')
        self.do_prepare_jumpbox()
        Log.info('Launch provisioning')
        provision_result = self.do_provision_lab()
        if provision_result:
            for extension_name in self.lab_manager.current_settings.extensions_name:
                self._install_phase = f'extension provisioning: {extension_name}'
                Log.info(f'Start installation of extension : {extension_name}')
                self.do_install_extension(extension_name)
        self.refresh_prompt()
        return provision_result

    def do_provision_lab(self, arg=''):
        """Provision only with a healthy management plane and isolate on success."""
        provider = self.lab_manager.get_current_instance_provider()
        if provider is None:
            Log.error('No provider loaded for the current instance')
            return False

        phase_started = time.monotonic()
        self._install_phase = 'provisioning management-plane validation'
        prepare = getattr(provider, 'prepare_provisioning', None)
        if callable(prepare) and not prepare():
            elapsed = self._format_elapsed(time.monotonic() - phase_started)
            Log.error(
                f'GOAD_NOMAD: failed to prepare provisioning mode after {elapsed}; '
                'aborting Ansible'
            )
            return False

        self._install_phase = 'Ansible provisioning'
        provision_result = super().do_provision_lab(arg)
        if not provision_result:
            elapsed = self._format_elapsed(time.monotonic() - phase_started)
            Log.error(f'GOAD_NOMAD TIMER: provisioning failed after {elapsed}')
            # Keep provisioning mode available for diagnosis/retry.  Do not
            # claim the instance is installed and do not silently isolate it.
            return False

        self._install_phase = 'exercise-mode finalization'
        finalize = getattr(provider, 'finalize_install', None)
        if callable(finalize) and not finalize():
            # super().do_provision_lab() has already set READY. Roll that back
            # because a GOAD_NOMAD install is not complete until exercise
            # isolation has been successfully enforced.
            self.lab_manager.get_current_instance().set_status(PROVIDED)
            elapsed = self._format_elapsed(time.monotonic() - phase_started)
            Log.error(
                f'GOAD_NOMAD: provisioning succeeded but final exercise isolation '
                f'failed after {elapsed}'
            )
            return False

        elapsed = self._format_elapsed(time.monotonic() - phase_started)
        Log.success(
            f'GOAD_NOMAD TIMER: provisioning + final isolation completed in {elapsed}'
        )
        return True

    def do_help(self, arg):
        super().do_help(arg)
        if self._nomad_provider() is not None:
            print_menu_title('GOAD_NOMAD Network')
            print_menu_entry('network', 'show the segmented network profile')
            if self.lab_manager.get_current_instance() is not None:
                print_menu_entry('mode [status|provisioning|exercise]', 'show or change the lab network mode')
                print_menu_entry('validate', 'run the complete Milestone 1 network validation')

    def do_network(self, arg=''):
        provider = self._nomad_provider()
        if provider is None:
            Log.error('The current lab/provider does not use the GOAD_NOMAD segmented profile')
            return

        scope = provider.get_network_scope()
        Log.success(f'GOAD_NOMAD Network Scope: {scope}')
        for zone, vmnet, subnet in provider.get_network_details():
            Log.info(f'{zone:<15} {vmnet:<8} {subnet}')

        if self.lab_manager.get_current_instance() is not None:
            Log.info(f'Runtime Mode     : {provider.get_runtime_mode()}')

    def do_mode(self, arg='status'):
        provider = self._nomad_provider(require_instance=True)
        if provider is None:
            Log.error('Load a GOAD/VMware instance before managing GOAD_NOMAD mode')
            return

        mode = (arg or 'status').strip().lower()
        if mode == 'status':
            Log.info(f'GOAD_NOMAD Mode: {provider.get_runtime_mode()}')
            return

        if mode not in ('provisioning', 'exercise'):
            Log.error('Usage: mode [status|provisioning|exercise]')
            return

        if provider.set_runtime_mode(mode):
            Log.success(f'GOAD_NOMAD mode is now {mode}')
        else:
            Log.error(f'Failed to enter GOAD_NOMAD {mode} mode')

    def complete_mode(self, text, line, begidx, endidx):
        options = ['status', 'provisioning', 'exercise']
        if not text:
            return options
        return [option for option in options if option.startswith(text)]

    def do_validate(self, arg=''):
        provider = self._nomad_provider(require_instance=True)
        if provider is None:
            Log.error('Load a GOAD/VMware instance before running GOAD_NOMAD validation')
            return

        if provider.validate_runtime():
            # A full runtime validation proves the instance is provisioned and
            # finishes in exercise mode. Repair stale stock-GOAD metadata from
            # development-era instances only after that proof succeeds.
            self.lab_manager.get_current_instance().set_status(READY)
            Log.success('GOAD_NOMAD runtime validation passed; instance status is installed')
        else:
            Log.error('GOAD_NOMAD runtime validation failed')

    def do_status(self, arg=''):
        super().do_status(arg)
        provider = self._nomad_provider(require_instance=True)
        if provider is not None:
            Log.info(f'Network Scope : {provider.get_network_scope()}')
            Log.info(f'Network Mode  : {provider.get_runtime_mode()}')

    def do_set_ip_range(self, arg):
        if self._nomad_provider() is not None:
            Log.warning('GOAD/VMware uses the fixed GOAD_NOMAD segmented profile')
            Log.info('Network scope: 10.4.0.0/16; use "network" to show its four zones')
            return
        super().do_set_ip_range(arg)


def parse_args():
    task_help = 'tasks available: install/check/start/stop/restart/destroy/status/snapshot/reset/validate'
    parser = argparse.ArgumentParser(
        prog='goad_nomad.py',
        description='GOAD_NOMAD lab management console.',
        epilog='''
Examples:
 - Launch GOAD_NOMAD interactive console: ./goad.sh
 - Install default segmented GOAD on VMware: ./goad.sh -t install -l GOAD -p vmware
 - Validate an installed instance: ./goad.sh -t validate -i <instance_id>
''',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('-t', '--task', help=task_help, required=False)
    parser.add_argument('-l', '--lab', help='lab to use (default: GOAD)', default='GOAD', required=False)
    parser.add_argument('-p', '--provider', help='provider to use (default: vmware)', default='vmware', required=False)
    parser.add_argument('-ip', '--ip_range', help='legacy flat-network prefix; ignored by segmented GOAD/VMware', default='', required=False)
    parser.add_argument('-m', '--method', help='deploy method to use (default: local)', default='local', required=False)
    parser.add_argument('-i', '--instance', help='use a specific instance (use default if not selected)', required=False)
    parser.add_argument('-e', '--extensions', help='extensions to use', action='append', required=False)
    parser.add_argument('-a', '--ansible_only', help='run only provisioning (ansible) on instance (-i) (for task install only)', required=False)
    parser.add_argument('-r', '--run_playbook', help='run only one ansible playbook on instance (-i) (for task install only)', required=False)
    parser.add_argument('-d', '--disable_dependencies', help='disable_dependencies', action='append', required=False)
    return parser.parse_args()


def _dispatch_task(goad, args):
    """Preserve the stock goad.py non-interactive task behaviour."""
    if args.instance is not None:
        goad.do_load(args.instance)

    if args.run_playbook is not None or args.ansible_only is not None:
        if args.instance is None:
            Log.error('Instance must be selected (-i) to use --run_playbook (-r) or --ansible_only (-a)')
            return 1

    if args.task == 'install':
        if args.instance is not None:
            if args.run_playbook is not None:
                goad.do_provision(args.run_playbook)
            elif args.ansible_only:
                goad.do_provision_lab()
            else:
                goad.do_install_instance()
        else:
            goad.do_install()
    elif args.task == 'check':
        goad.do_check()
    elif args.task == 'start':
        goad.do_start()
    elif args.task == 'stop':
        goad.do_stop()
    elif args.task == 'restart':
        goad.do_stop()
        goad.do_start()
    elif args.task == 'destroy':
        goad.do_destroy()
    elif args.task == 'status':
        goad.do_status()
    elif args.task == 'snapshot':
        goad.do_snapshot()
    elif args.task == 'reset':
        goad.do_reset()
    elif args.task == 'validate':
        goad.do_validate()
    elif args.task == 'mode':
        goad.do_mode('status')
    elif args.task == 'show':
        pass
    else:
        Log.error(f'Unknown task: {args.task}')
        return 1
    return 0


def main():
    print_logo()
    args = parse_args()
    goad = GoadNomad(args)

    if args is None or args.task is None:
        goad.cmdloop()
        return 0

    return _dispatch_task(goad, args)


if __name__ == '__main__':
    sys.exit(main())