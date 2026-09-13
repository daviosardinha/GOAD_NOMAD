import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TASKS = ROOT / "ansible/roles/phase01/dc/tasks/main.yml"
SCRIPT = ROOT / "ansible/roles/phase01/dc/files/anonymous-sid-translation-gpo.ps1"


class Phase01GpoSourceTests(unittest.TestCase):
    def test_local_security_policy_task_is_removed(self):
        text = TASKS.read_text()
        self.assertNotIn("community.windows.win_security_policy", text)
        self.assertIn("anonymous-sid-translation-gpo.ps1", text)
        self.assertIn("gpupdate.exe /target:computer /force", text)
        self.assertIn("LSAAnonymousNameLookup=1", text)

    def test_dedicated_gpo_contains_security_policy_extension(self):
        text = SCRIPT.read_text()
        self.assertIn("Kingdoms - Phase 01 - Anonymous SID Translation", text)
        self.assertIn("OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local", text)
        self.assertIn("LSAAnonymousNameLookup = 1", text)
        self.assertIn("{827D319E-6EAC-11D2-A4EA-00C04F79F83A}", text)
        self.assertIn("{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}", text)
        self.assertIn("-Order 1", text)

    def test_effective_policy_is_verified_after_refresh(self):
        text = TASKS.read_text()
        refresh = text.index("gpupdate.exe /target:computer /force")
        verify = text.index("Effective policy does not have LSAAnonymousNameLookup=1")
        self.assertLess(refresh, verify)


if __name__ == "__main__":
    unittest.main()
