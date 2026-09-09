"""Regression contracts for the Kingdoms MSSQL installation path."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = ROOT / "ansible/roles/mssql/defaults/main.yml"
ROLE = ROOT / "ansible/roles/mssql/tasks/main.yml"

class MssqlInstallRoleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.defaults = DEFAULTS.read_text(encoding="utf-8")
        cls.role = ROLE.read_text(encoding="utf-8")

    def test_sql2019_uses_full_advanced_media(self):
        self.assertIn("SQLEXPRADV_x64_ENU.exe", self.defaults)
        self.assertNotIn("SQL2019-SSEI-Expr.exe", self.defaults)

    def test_stale_ssei_file_cannot_satisfy_sql2019_media_check(self):
        self.assertIn("SQLEXPRADV_x64_ENU.exe", self.role)
        self.assertIn("500000000", self.role)

    def test_download_is_bounded_to_ten_minutes(self):
        self.assertIn("async: 600", self.role)
        self.assertIn("url_timeout: 600", self.role)

    def test_extraction_is_bounded_to_five_minutes(self):
        self.assertIn("WaitForExit(300000)", self.role)
        self.assertIn("exceeded 300 seconds", self.role)

    def test_sql2019_setup_is_bounded_to_twenty_minutes(self):
        self.assertIn("WaitForExit(1200000)", self.role)
        self.assertIn("exceeded 1200 seconds", self.role)

    def test_sql2019_configuration_is_passed_to_real_setup(self):
        self.assertIn(r"SQLEXPRADV_2019\setup.exe", self.role)
        self.assertIn(r"/ConfigurationFile=$configuration", self.role)

if __name__ == "__main__":
    unittest.main()
