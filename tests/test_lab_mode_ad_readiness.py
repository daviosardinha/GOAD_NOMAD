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

    def test_exercise_restart_proves_authenticated_readiness_before_final_disconnect(self):
        text = self.text

        for token in (
            "prove_isolated_guest_ready()",
            'temporarily connecting runtime NAT for authenticated readiness',
            'vmrun -T ws connectNamedDevice',
            'vmrun -T ws disconnectNamedDevice',
            'authenticated post-reboot readiness proven; runtime NAT disconnected',
            'prove_isolated_guest_ready "${vm}" member',
            'prove_isolated_guest_ready "${vm}" dc',
        ):
            self.assertIn(token, text)

        fn = text[text.index("prove_isolated_guest_ready()"):
                  text.index("configure_windows_nat_exercise()")]
        self.assertIn(
            '[[ "${persistent}" == "FALSE" ]]',
            fn,
        )
        self.assertIn("trap cleanup_runtime_nat EXIT", fn)

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

    def test_member_readiness_emits_exact_failure_class(self):
        text = self.text
        fn = text[text.index("wait_domain_member_ready()"):
                  text.index("preflight_domain_health()")]

        for marker in (
            "KINGDOMS_MEMBER_NOT_READY|reason=dns",
            "KINGDOMS_MEMBER_NOT_READY|reason=secure_channel",
            "KINGDOMS_MEMBER_NOT_READY|reason=account_translation",
            "KINGDOMS_MEMBER_NOT_READY|reason=time|source=",
            "reason=transport",
        ):
            self.assertIn(marker, fn)

        self.assertIn(
            'did not regain domain identity readiness for ${domain} within 300s; ${last_state}',
            fn,
        )

    def test_member_lifecycle_uses_one_bounded_time_only_repair(self):
        text = self.text
        fn = text[text.index("wait_domain_member_ready()"):
                  text.index("preflight_domain_health()")]

        for token in (
            "consecutive_time_failures >= 6",
            "time_repair_attempted == 0",
            "w32tm.exe /config /syncfromflags:domhier /update",
            "nltest.exe '/dsgetdc:${domain}' /timeserv /force",
            "Restart-Service W32Time -Force",
            "w32tm.exe /resync /rediscover /nowait",
            "KINGDOMS_MEMBER_TIME_REPAIRED",
            "KINGDOMS_MEMBER_TIME_REPAIR_FAILED",
        ):
            self.assertIn(token, fn)

        # Normal lifecycle may recover W32Time only. Directory trust repair
        # remains an explicit maintenance/provisioning operation.
        for forbidden in (
            "Reset-ComputerMachinePassword",
            "/sc_reset:",
            "netdom resetpwd",
        ):
            self.assertNotIn(forbidden, fn)

    def test_time_repair_requires_identity_probe_to_reach_time_stage(self):
        text = self.text
        fn = text[text.index("wait_domain_member_ready()"):
                  text.index("preflight_domain_health()")]

        self.assertLess(
            fn.index("Resolve-DnsName '${dc}'"),
            fn.index("Test-ComputerSecureChannel -Server '${dc}'"),
        )
        self.assertLess(
            fn.index("Test-ComputerSecureChannel -Server '${dc}'"),
            fn.index("System.Security.Principal.NTAccount"),
        )
        self.assertLess(
            fn.index("System.Security.Principal.NTAccount"),
            fn.index("w32tm.exe /query /source"),
        )
        self.assertIn(
            'if [[ "${last_state}" == reason=time\\|* ]]; then',
            fn,
        )


if __name__ == "__main__":
    unittest.main()