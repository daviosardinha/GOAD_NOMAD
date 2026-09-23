"""Offline tests for the opt-in headless NORTH RDP bot. No lab connections."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/rdp-bot-headless.sh"
UNIT = ROOT / "ops/systemd/kingdoms-rdp-bot.service"


class RdpBotRunnerTests(unittest.TestCase):
    def test_runner_bash_syntax(self):
        result = subprocess.run(["bash", "-n", str(RUNNER)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_runner_scope_and_secret_handling(self):
        source = RUNNER.read_text()
        for expected in (
            "TARGET_IP='10.4.10.22'",
            "EXPECTED_INTERFACE='vmnet10'",
            "EXPECTED_SOURCE='10.4.10.254'",
            "/args-from:stdin",
            "RDP_CERT_SHA256='df04438dc21da0b7fdf61f3694df1b9d658fc4bc965d082c06516aeec8453dfe'",
            'id -u',
            'stat -c',
            'exec xvfb-run',
            'cat -- "$CREDENTIAL_FILE"',
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, source)
        for forbidden in (
            "/cert:ignore",
            "/p:sexywolfy",
            "Disable-ScheduledTask",
            "Stop-Process",
            "Start-ScheduledTask",
            "systemctl start",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)

    def test_unit_not_enabled_by_source_and_limits_retries(self):
        text = UNIT.read_text()
        self.assertIn('WantedBy=default.target', text)
        self.assertIn('RestartSec=120', text)
        self.assertIn('StartLimitBurst=3', text)
        self.assertIn('rdp-bot-headless.sh', text)
        self.assertNotIn('/p:', text)
        self.assertNotIn('ExecStartPre=systemctl', text)

    @staticmethod
    def write_executable(path, contents):
        path.write_text(contents)
        path.chmod(0o700)

    def invoke_mock(self, secret_mode=0o600, ip_source='10.4.10.254'):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            secret = root / 'robb-rdp.password'
            secret.write_text('DUMMY_CREDENTIAL_DO_NOT_USE\n')
            secret.chmod(secret_mode)
            argv = root / 'argv'
            stdin = root / 'stdin'

            # All network, GUI and FreeRDP commands are inert local test doubles.
            self.write_executable(bin_dir / 'id', '#!/bin/sh\necho 1000\n')
            self.write_executable(
                bin_dir / 'ip',
                '#!/bin/sh\necho "10.4.10.22 via 10.4.10.1 dev vmnet10 src ' +
                ip_source + ' uid 1000"\n',
            )
            self.write_executable(
                bin_dir / 'stat',
                '#!/bin/sh\nif [ "$2" = "%u" ]; then echo 1000; '
                'else /usr/bin/stat "$@"; fi\n',
            )
            self.write_executable(
                bin_dir / 'xvfb-run',
                '#!/bin/sh\n[ "$1" = "-a" ] && shift\n'
                '[ "$1" = "-s" ] && shift 2\nexec "$@"\n',
            )
            self.write_executable(
                bin_dir / 'xfreerdp3',
                '#!/bin/sh\nprintf "%s\\n" "$@" > "$RDP_TEST_ARGV"\n'
                'cat > "$RDP_TEST_STDIN"\n',
            )
            env = dict(os.environ)
            env.update(
                PATH=str(bin_dir) + os.pathsep + env.get('PATH', ''),
                KINGDOMS_RDP_BOT_SECRET_FILE=str(secret),
                RDP_TEST_ARGV=str(argv),
                RDP_TEST_STDIN=str(stdin),
            )
            result = subprocess.run(
                ['/usr/bin/bash', str(RUNNER)],
                capture_output=True, text=True, timeout=10, env=env,
            )
            args = argv.read_text() if argv.exists() else ''
            received = stdin.read_text() if stdin.exists() else ''
            return result, args, received

    def test_dummy_credential_only_reaches_stdin(self):
        result, args, received = self.invoke_mock()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('/args-from:stdin', args)
        self.assertNotIn('/v:10.4.10.22', args)
        self.assertNotIn('DUMMY_CREDENTIAL_DO_NOT_USE', args)
        self.assertNotIn('DUMMY_CREDENTIAL_DO_NOT_USE', result.stdout + result.stderr)
        self.assertIn('/v:10.4.10.22', received)
        self.assertIn('/p:DUMMY_CREDENTIAL_DO_NOT_USE', received)
        self.assertIn('/cert:fingerprint:sha256:df04438dc21da0b7fdf61f3694df1b9d658fc4bc965d082c06516aeec8453dfe', received)

    def test_world_readable_secret_fails_closed(self):
        result, args, _ = self.invoke_mock(secret_mode=0o644)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('group/other access', result.stderr)
        self.assertEqual(args, '')

    def test_unexpected_network_route_fails_closed(self):
        result, args, _ = self.invoke_mock(ip_source='10.4.10.123')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('NORTH route changed', result.stderr)
        self.assertEqual(args, '')


if __name__ == '__main__':
    unittest.main()
