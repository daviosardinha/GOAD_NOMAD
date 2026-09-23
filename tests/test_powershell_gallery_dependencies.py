"""Regression contracts for external PowerShell Gallery dependencies."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
ROLE_FILES = (
    ROOT / "ansible/roles/domain_controller/tasks/main.yml",
    ROOT / "ansible/roles/child_domain/tasks/main.yml",
)


class PowerShellGalleryDependencyTests(unittest.TestCase):
    def test_active_directory_dsc_is_pinned_and_locally_retried(self):
        for path in ROLE_FILES:
            text = path.read_text(encoding="utf-8")
            with self.subTest(path=path):
                self.assertIn("name: ActiveDirectoryDSC", text)
                self.assertIn("repository: PSGallery", text)
                self.assertIn('required_version: "6.7.1"', text)
                self.assertIn("register: active_directory_dsc_install", text)
                self.assertIn("retries: 5", text)
                self.assertIn("delay: 30", text)
                self.assertIn(
                    "until: active_directory_dsc_install is succeeded",
                    text,
                )

    def test_active_directory_dsc_is_not_left_unversioned(self):
        for path in ROLE_FILES:
            text = path.read_text(encoding="utf-8")
            block = text.split("name: ActiveDirectoryDSC", 1)[1].split(
                "\n- name:", 1
            )[0]
            with self.subTest(path=path):
                self.assertIn('required_version: "6.7.1"', block)


if __name__ == "__main__":
    unittest.main()
