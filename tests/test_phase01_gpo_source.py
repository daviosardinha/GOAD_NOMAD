import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TASKS = ROOT / "ansible/roles/phase01/dc/tasks/main.yml"
SID_SCRIPT = ROOT / "ansible/roles/phase01/dc/files/anonymous-sid-translation-gpo.ps1"
RPC_SCRIPT = ROOT / "ansible/roles/phase01/dc/files/anonymous-rpc-exposure-gpo.ps1"


class Phase01GpoSourceTests(unittest.TestCase):
    def test_local_security_policy_task_is_removed(self):
        text = TASKS.read_text()
        self.assertNotIn("community.windows.win_security_policy", text)
        self.assertIn("anonymous-sid-translation-gpo.ps1", text)
        self.assertIn("anonymous-rpc-exposure-gpo.ps1", text)
        self.assertIn("gpupdate.exe /target:computer /force", text)
        self.assertIn("LSAAnonymousNameLookup=1", text)

    def test_dedicated_sid_gpo_contains_security_policy_extension(self):
        text = SID_SCRIPT.read_text()
        self.assertIn("Kingdoms - Phase 01 - Anonymous SID Translation", text)
        self.assertIn("OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local", text)
        self.assertIn("LSAAnonymousNameLookup = 1", text)
        self.assertIn("{827D319E-6EAC-11D2-A4EA-00C04F79F83A}", text)
        self.assertIn("{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}", text)
        self.assertIn("-Order 1", text)

    def test_dedicated_rpc_gpo_is_scoped_to_required_null_rpc_surface(self):
        text = RPC_SCRIPT.read_text()
        self.assertIn("Kingdoms - Phase 01 - Anonymous RPC Exposure", text)
        self.assertIn("OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local", text)
        self.assertIn("RestrictAnonymous", text)
        self.assertIn("RestrictAnonymousSAM", text)
        self.assertIn("EveryoneIncludesAnonymous", text)
        self.assertIn("RestrictNullSessAccess", text)
        self.assertIn("NullSessionPipes", text)
        self.assertIn("@('samr', 'lsarpc')", text)
        self.assertIn("Value = 1", text)
        self.assertIn("Value = 0", text)
        self.assertIn("-Order 2", text)
        self.assertNotIn("NullSessionShares", text)

    def test_effective_policies_are_verified_after_refresh(self):
        text = TASKS.read_text()
        refresh = text.index("gpupdate.exe /target:computer /force")
        sid_verify = text.index("Effective policy does not have LSAAnonymousNameLookup=1")
        rpc_verify = text.index("Effective NullSessionPipes must contain only samr and lsarpc")
        self.assertLess(refresh, sid_verify)
        self.assertLess(refresh, rpc_verify)


if __name__ == "__main__":
    unittest.main()
