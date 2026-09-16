import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TASKS = ROOT / "ansible/roles/phase01/dc/tasks/main.yml"
SID_SCRIPT = ROOT / "ansible/roles/phase01/dc/files/anonymous-sid-translation-gpo.ps1"
RPC_SCRIPT = ROOT / "ansible/roles/phase01/dc/files/anonymous-rpc-gpo.ps1"


class Phase01GpoSourceTests(unittest.TestCase):
    def test_local_security_policy_task_is_removed(self):
        text = TASKS.read_text()
        self.assertNotIn("community.windows.win_security_policy", text)
        self.assertIn("anonymous-sid-translation-gpo.ps1", text)
        self.assertIn("anonymous-rpc-gpo.ps1", text)
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

    def test_dedicated_rpc_gpo_is_scoped_to_named_pipes(self):
        text = RPC_SCRIPT.read_text()
        self.assertIn("Kingdoms - Phase 01 - Anonymous RPC Exposure", text)
        self.assertIn("OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local", text)
        self.assertIn("RestrictNullSessAccess", text)
        self.assertIn("NullSessionPipes", text)
        self.assertIn("[string[]]@('samr', 'lsarpc')", text)
        self.assertIn("-Type DWord -Value 1", text)
        self.assertIn("-Type MultiString -Value ([string[]]$desiredPipes)", text)
        self.assertIn("-Order 2", text)
        self.assertNotIn("NullSessionShares' -Type MultiString", text)

    def test_effective_policy_is_verified_after_refresh(self):
        text = TASKS.read_text()
        refresh = text.index("gpupdate.exe /target:computer /force")
        sid_verify = text.index("Effective policy does not have LSAAnonymousNameLookup=1")
        pipe_verify = text.index("expected only samr and lsarpc")
        share_verify = text.index("Effective NullSessionShares unexpectedly exposes")
        self.assertLess(refresh, sid_verify)
        self.assertLess(refresh, pipe_verify)
        self.assertLess(refresh, share_verify)


if __name__ == "__main__":
    unittest.main()
