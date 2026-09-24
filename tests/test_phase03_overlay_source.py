"""Offline source contract for Kingdoms Phase 03 overlay scaffolding."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLAYBOOK = ROOT / "ansible" / "phase03.yml"
APPLY = ROOT / "scripts" / "apply-phase03.sh"
VALIDATE = ROOT / "scripts" / "validate-phase03-runtime.sh"
RESET = ROOT / "scripts" / "reset-phase03.sh"
DIAG = ROOT / "scripts" / "phase03" / "diagnostics"


class Phase03OverlaySourceTests(unittest.TestCase):
    def test_required_files_exist(self):
        for path in (PLAYBOOK, APPLY, VALIDATE, RESET):
            with self.subTest(path=path):
                self.assertTrue(path.is_file(), path)

    def test_shell_entrypoints_parse(self):
        scripts = [APPLY, VALIDATE, RESET, *sorted(DIAG.glob("*.sh"))]
        for script in scripts:
            with self.subTest(script=script):
                result = subprocess.run(
                    ["bash", "-n", str(script)],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_playbook_is_scoped_to_north_hosts(self):
        text = PLAYBOOK.read_text()
        self.assertIn("hosts: dc02:srv02:ws01", text)
        self.assertIn("north.sevenkingdoms.local", text)
        self.assertIn("phase03_apply", text)
        self.assertIn("any_errors_fatal: true", text)
        for forbidden in ("dc01", "dc03", "srv03", "all:"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(f"hosts: {forbidden}", text)

    def test_apply_fails_closed_and_runs_readiness_first(self):
        text = APPLY.read_text()
        self.assertIn("--confirm", text)
        self.assertIn("working tree must be clean", text)
        self.assertIn("kingdoms/phase03-overlay", text)
        self.assertIn("validate-phase03-readiness.sh", text)
        self.assertIn("-e phase03_apply=true", text)
        self.assertIn("ad/GOAD/data/inventory", text)
        self.assertIn("ad/GOAD/providers/vmware/inventory", text)
        self.assertIn("--list-hosts", text)
        self.assertIn("required Phase 03 host missing", text)
        self.assertNotIn('"$PROVIDER/inventory"', text)
        self.assertLess(
            text.index("validate-phase03-readiness.sh"),
            text.index("ansible-playbook"),
        )

    def test_reset_is_non_destructive_at_checkpoint(self):
        text = RESET.read_text().lower()
        self.assertIn("no permanent phase 03 state-changing fixture", text)
        for forbidden in (
            "remove-ad",
            "delete-ad",
            "vagrant destroy",
            "goad.sh -t destroy",
            "rm -rf",
            "git reset --hard",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, text)

    def test_no_embedded_phase03_secrets(self):
        corpus = "\n".join(
            p.read_text(errors="replace")
            for p in [PLAYBOOK, APPLY, VALIDATE, RESET, *sorted(DIAG.glob("*.sh"))]
        ).lower()
        for forbidden in (
            "winter2022",
            "sexywolfy",
            "fightp3aceandhonor!",
            "youwillnotkerboroast1ngmeeeeee",
            "/p:rickon",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, corpus)

    def test_wpad_observer_handles_privileged_capture_file(self):
        script = (DIAG / "start-wpad-observers.sh").read_text()
        self.assertIn('sudo rm -f "$PCAP"', script)
        self.assertIn('-Z "$USER"', script)
        self.assertIn("kingdoms-wpad-tcpdump.log", script)

    def test_checkpoint_does_not_modify_lab_yet(self):
        text = PLAYBOOK.read_text().lower()
        self.assertNotIn("win_regedit", text)
        self.assertNotIn("win_feature", text)
        self.assertNotIn("win_service", text)
        self.assertNotIn("win_file", text)
        self.assertNotIn("win_copy", text)
        self.assertNotIn("set-acl", text)
        self.assertNotIn("set-ad", text)


if __name__ == "__main__":
    unittest.main()
