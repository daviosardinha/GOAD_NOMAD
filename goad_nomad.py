"""GOAD_NOMAD console entry point.

This module deliberately subclasses the upstream-style ``goad.py`` console
rather than duplicating the project controller.  ``./goad.sh`` remains the
canonical entry point while GOAD_NOMAD can add segmented-network operations
without making future upstream merges unnecessarily invasive.
"""

from pathlib import Path
import runpy
import sys

from goad.log import Log
from goad.menu import print_menu_entry, print_menu_title
from goad.utils import READY


_upstream = runpy.run_path(
    str(Path(__file__).with_name('goad.py')),
    run_name='goad_upstream_console',
)

BaseGoad = _upstream['Goad']
parse_args = _upstream['parse_args']
print_logo = _upstream['print_logo']


class GoadNomad(BaseGoad):
    """GOAD console plus GOAD_NOMAD segmented-network lifecycle commands."""

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
