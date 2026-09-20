"""Regression contract for AD-aware Kingdoms mode transitions."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAB_MODE = ROOT / "scripts" / "lab-mode.sh"


class LabModeAdReadinessTests(unittest.TestCase):
    def setUp(self):
        self.text = LAB_MODE.read_text(encoding="utf-8")

    def test_provisioning_restarts_dcs_before_members_and_waits_for_identity(self):
        text = self.text

        self.assertIn("configure_windows_nat_provisioning()", text)
        self.assertIn('for vm in "${DOMAIN_CONTROLLERS[@]}"', text)
        self.assertIn('wait_domain_controller_ready "${vm}"', text)
        self.assertIn('for vm in "${DOMAIN_MEMBERS[@]}"', text)
        self.assertIn('wait_domain_member_ready "${vm}"', text)

        fn = text[text.index("configure_windows_nat_provisioning()"):
                  text.index("configure_windows_nat_exercise()")]
        self.assertLess(
            fn.index('for vm in "${DOMAIN_CONTROLLERS[@]}"'),
            fn.index('for vm in "${DOMAIN_MEMBERS[@]}"'),
        )

    def test_exercise_restarts_members_before_domain_controllers(self):
        text = self.text
        fn = text[text.index("configure_windows_nat_exercise()"):
                  text.index("verify_persistent_state()")]

        self.assertLess(
            fn.index('for vm in "${DOMAIN_MEMBERS[@]}"'),
            fn.index('for vm in "${EXERCISE_DOMAIN_CONTROLLERS[@]}"'),
        )
        self.assertIn("preflight_domain_health", text)

    def test_dc_readiness_is_ad_aware_not_merely_winrm(self):
        text = self.text

        for token in (
            "ADPS_LoadDefaultDrive",
            "Get-ADRootDSE",
            "SYSVOL",
            "NETLOGON",
            "nltest.exe '/dsgetdc:",
            "KINGDOMS_DC_RUNTIME_READY",
        ):
            self.assertIn(token, text)

    def test_member_readiness_proves_trust_account_lookup_and_domain_time(self):
        text = self.text

        for token in (
            "Test-ComputerSecureChannel -Server",
            "System.Security.Principal.NTAccount",
            "Translate([System.Security.Principal.SecurityIdentifier])",
            "w32tm.exe /query /source",
            "Local CMOS Clock",
            "KINGDOMS_MEMBER_RUNTIME_READY",
        ):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
