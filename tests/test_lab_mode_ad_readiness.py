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
            'vmrun_named_device_action "${vm}" connect 15 2',
            'vmrun_named_device_action "${vm}" disconnect 15 2 || true',
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

        connect = fn.index('vmrun_named_device_action "${vm}" connect 15 2')
        readiness = fn.index('case "${kind}" in')
        final_cleanup = fn.index('\n    cleanup_runtime_nat\n    trap - EXIT')
        final_proof = fn.index(
            'authenticated post-reboot readiness proven; runtime NAT disconnected'
        )

        self.assertLess(connect, readiness)
        self.assertLess(readiness, final_cleanup)
        self.assertLess(final_cleanup, final_proof)

    def test_provisioning_powers_on_cleanly_stopped_guests_before_readiness(self):
        text = self.text
        ensure = text[text.index("ensure_vm_nat_state()"):
                      text.index("vagrant_powershell_ready()")]

        self.assertIn(
            '[[ "${desired}" == "TRUE" && "${action}" == "connect" ]]',
            ensure,
        )
        self.assertIn("VM is powered off; starting it for provisioning readiness", ensure)
        self.assertIn('vmrun -T ws start "${vmx}" nogui', ensure)
        self.assertIn('wait_started "${vmx}"', ensure)
        self.assertIn("did not start for provisioning readiness", ensure)
        self.assertIn("runtime connect requested while VM is powered off", ensure)

        provisioning = text[text.index("configure_windows_nat_provisioning()"):
                            text.index("prove_isolated_guest_ready()")]
        self.assertLess(
            provisioning.index('ensure_vm_nat_state "${vm}" TRUE connect'),
            provisioning.index('wait_domain_controller_ready "${vm}"'),
        )
        self.assertLess(
            provisioning.rindex('ensure_vm_nat_state "${vm}" TRUE connect'),
            provisioning.index('wait_domain_member_ready "${vm}"'),
        )

    def test_isolated_readiness_fails_fast_if_guest_is_powered_off(self):
        text = self.text
        fn = text[text.index("prove_isolated_guest_ready()"):
                  text.index("configure_windows_nat_exercise()")]

        self.assertIn(
            'authenticated exercise-readiness probe requires the VM to be powered on',
            fn,
        )
        self.assertLess(
            fn.index('is_running "${vmx}"'),
            fn.index('vmrun_named_device_action "${vm}" connect 15 2'),
        )

    def test_vmware_named_device_actions_are_retried_and_not_silently_ignored(self):
        text = self.text
        helper = text[text.index("vmrun_named_device_action()"):
                      text.index("ensure_vm_nat_state()")]
        self.assertIn("connectNamedDevice", helper)
        self.assertIn("disconnectNamedDevice", helper)
        self.assertIn("attempt<=attempts", helper)
        self.assertIn('if output="$(vmrun -T ws', helper)
        self.assertIn("rc=$?", helper)
        self.assertIn("already.*connected", helper)
        self.assertIn("already.*disconnected", helper)

        ensure = text[text.index("ensure_vm_nat_state()"):
                      text.index("vagrant_powershell_ready()")]
        self.assertIn('vmrun_named_device_action "${vm}" "${action}" 15 2', ensure)
        self.assertNotIn("connectNamedDevice", ensure)
        self.assertNotIn("disconnectNamedDevice", ensure)
        self.assertNotIn("|| true", ensure)

        isolated = text[text.index("prove_isolated_guest_ready()"):
                        text.index("configure_windows_nat_exercise()")]
        self.assertIn('vmrun_named_device_action "${vm}" connect 15 2', isolated)
        self.assertIn('vmrun_named_device_action "${vm}" disconnect 15 2 || true', isolated)

    def test_dc_readiness_surfaces_probe_output_and_retries_runtime_nat(self):
        text = self.text
        dc = text[text.index("wait_domain_controller_ready()"):
                  text.index("wait_domain_member_ready()")]

        self.assertIn('local last_state="reason=transport"', dc)
        self.assertIn('vagrant_powershell_capture "${vm}" "${script}" "${probe_timeout}"', dc)
        self.assertIn("reason=guest_probe_failure", dc)
        self.assertIn("reason=guest_probe_no_ready_marker", dc)
        self.assertIn("bounded VMware transport self-heal", dc)
        self.assertIn('vmrun_named_device_action "${vm}" connect 3 2 || true', dc)
        self.assertIn("last Vagrant/PowerShell readiness output follows", dc)
        self.assertIn('tail -80', dc)

    def test_failed_lifecycle_has_fail_closed_network_isolation_path(self):
        text = self.text
        fn = text[text.index("enter_exercise_failsafe()"):
                  text.index("enter_provisioning_mode()")]

        self.assertIn("set_state recovery-required", fn)
        self.assertIn('bash "${ROUTES}" disable', fn)
        self.assertIn('ensure_vm_nat_state "${vm}" FALSE disconnect', fn)
        self.assertIn("verify_persistent_state FALSE", fn)
        self.assertIn("apply_router_policy exercise", fn)
        self.assertIn("policy drop;", fn)
        self.assertIn("mode remains recovery-required", fn)
        self.assertIn("set_state exercise", fn)
        self.assertIn("does not claim AD/domain readiness", fn)

        self.assertLess(fn.index('bash "${ROUTES}" disable'), fn.index("apply_router_policy exercise"))
        self.assertLess(
            fn.index('ensure_vm_nat_state "${vm}" FALSE disconnect'),
            fn.index("apply_router_policy exercise"),
        )
        self.assertLess(fn.index("set_state recovery-required"), fn.index("set_state exercise"))

        main = text[text.index("main()"):]
        self.assertIn("exercise-failsafe)", main)

    def test_status_reports_local_vm_state_even_when_router_query_fails(self):
        text = self.text
        fn = text[text.index("show_status()"):
                  text.index("enter_exercise_mode()")]

        self.assertIn("[UNAVAILABLE] router management/policy query failed", fn)
        self.assertIn("router_status=1", fn)
        self.assertIn("=== WINDOWS VM NETWORK STATE ===", fn)
        self.assertIn('return "${router_status}"', fn)

    def test_winrm_helpers_use_explicit_nested_timeout(self):
        text = self.text
        helpers = text[text.index("vagrant_powershell_ready()"):
                       text.index("ensure_child_dc_time_ready()")]

        self.assertIn('local timeout_seconds="$3"', helpers)
        self.assertEqual(helpers.count('timeout "${timeout_seconds}" vagrant winrm'), 2)
        self.assertNotIn("timeout 90 vagrant winrm", helpers)

    def test_readiness_deadlines_cap_nested_winrm_to_remaining_budget(self):
        text = self.text

        for token in (
            "readonly AD_READINESS_TIMEOUT_SECONDS=300",
            "readonly AD_READINESS_PROBE_TIMEOUT_SECONDS=15",
            "readonly AD_READINESS_RETRY_DELAY_SECONDS=5",
            "readonly AD_REPAIR_TIMEOUT_SECONDS=90",
        ):
            self.assertIn(token, text)

        child = text[text.index("ensure_child_dc_time_ready()"):
                     text.index("wait_domain_controller_ready()")]
        dc = text[text.index("wait_domain_controller_ready()"):
                  text.index("wait_domain_member_ready()")]
        member = text[text.index("wait_domain_member_ready()"):
                      text.index("preflight_domain_health()")]

        for fn in (child, dc, member):
            self.assertIn('local started="${SECONDS}"', fn)
            self.assertIn(
                "while (( SECONDS - started < AD_READINESS_TIMEOUT_SECONDS )); do",
                fn,
            )
            self.assertIn("remaining=$((AD_READINESS_TIMEOUT_SECONDS - elapsed))", fn)
            self.assertIn(
                '(( remaining < probe_timeout )) && probe_timeout="${remaining}"',
                fn,
            )
            self.assertNotIn("for attempt in {1..60}", fn)

        self.assertIn(
            'vagrant_powershell_capture "${vm}" "${probe_script}" "${probe_timeout}"',
            child,
        )
        self.assertIn(
            'vagrant_powershell_capture "${vm}" "${script}" "${probe_timeout}"',
            dc,
        )
        self.assertIn(
            'vagrant_powershell_capture "${vm}" "${script}" "${probe_timeout}"',
            member,
        )

        # A repair is allowed a larger inner timeout, but never more than the
        # parent readiness window still has left.
        for fn in (child, member):
            self.assertIn('repair_timeout="${AD_REPAIR_TIMEOUT_SECONDS}"', fn)
            self.assertIn(
                '(( remaining < repair_timeout )) && repair_timeout="${remaining}"',
                fn,
            )
            self.assertIn('"${repair_script}" "${repair_timeout}"', fn)

    def test_declared_300s_readiness_budget_is_not_attempt_math(self):
        text = self.text
        relevant = text[text.index("ensure_child_dc_time_ready()"):
                        text.index("preflight_domain_health()")]

        self.assertNotIn("$((attempt * 5))", relevant)
        self.assertNotIn("for attempt in {1..60}", relevant)
        self.assertGreaterEqual(
            relevant.count("AD_READINESS_TIMEOUT_SECONDS - elapsed"),
            3,
        )

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

    def test_child_dc_time_hierarchy_is_explicit_and_repaired_before_members(self):
        text = self.text

        for token in (
            'DC_TIME_PARENT_DOMAIN',
            '[GOAD-DC02]="sevenkingdoms.local"',
            'DC_TIME_PARENT_SERVER',
            '[GOAD-DC02]="kingslanding.sevenkingdoms.local"',
            'ensure_child_dc_time_ready()',
            "nltest.exe '/dsgetdc:${parent_domain}' /timeserv /force",
            "w32tm.exe /stripchart /computer:${parent_server}",
            "w32tm.exe /config /syncfromflags:domhier /update",
            "w32tm.exe /resync /rediscover /nowait",
            "KINGDOMS_DC_TIME_REPAIRED",
            "KINGDOMS_DC_TIME_REPAIR_DEFERRED",
            "KINGDOMS_DC_TIME_REPAIR_FAILED",
        ):
            self.assertIn(token, text)

        fn = text[text.index("wait_domain_controller_ready()"):
                  text.index("wait_domain_member_ready()")]
        self.assertIn('ensure_child_dc_time_ready "${vm}"', fn)

    def test_recorded_exercise_preflights_child_time_before_member_isolation(self):
        text = self.text
        fn = text[text.index("enter_exercise_mode()"):
                  text.index("enter_provisioning_mode()")]

        self.assertIn("preflight_exercise_time_dependencies", fn)
        self.assertLess(
            fn.index("preflight_exercise_time_dependencies"),
            fn.index("configure_windows_nat_exercise"),
        )

        dep = text[text.index("preflight_exercise_time_dependencies()"):
                   text.index("configure_windows_nat_provisioning()")]
        self.assertIn('prove_isolated_guest_ready "${vm}" dc', dep)
        self.assertIn('DC_TIME_PARENT_DOMAIN', dep)

    def test_child_dc_time_repair_defers_until_parent_timeserv_is_ready(self):
        text = self.text
        fn = text[text.index("ensure_child_dc_time_ready()"):
                  text.index("wait_domain_controller_ready()")]

        self.assertIn("KINGDOMS_DC_TIME_REPAIR_DEFERRED|stage=parent_domain_locator", fn)
        self.assertIn("KINGDOMS_DC_TIME_REPAIR_DEFERRED|stage=parent_timeserv_locator", fn)
        self.assertIn("KINGDOMS_DC_TIME_REPAIR_DEFERRED|stage=parent_ntp_path", fn)
        self.assertIn("REPAIRED|REPAIR_DEFERRED|REPAIR_FAILED", fn)
        self.assertIn("repair_deferred=$((repair_deferred + 1))", fn)
        self.assertIn("repair_invocations=$((repair_invocations + 1))", fn)
        self.assertIn("parent prerequisite is not ready yet", fn)
        self.assertIn("recovery failed after prerequisites were proven", fn)

    def test_child_dc_time_repair_is_bounded_and_never_rewrites_trust(self):
        text = self.text
        fn = text[text.index("ensure_child_dc_time_ready()"):
                  text.index("wait_domain_controller_ready()")]

        self.assertIn("repair_attempted == 0", fn)
        self.assertIn("consecutive_source_failures >= 6", fn)
        self.assertIn("syncAttempt -le 12", fn)

        for forbidden in (
            "Reset-ComputerMachinePassword",
            "/sc_reset:",
            "netdom resetpwd",
        ):
            self.assertNotIn(forbidden, fn)

    def test_member_readiness_proves_trust_account_lookup_and_domain_time(self):
        text = self.text

        for token in (
            "Test-ComputerSecureChannel -Server",
            "System.Security.Principal.NTAccount",
            "Translate([System.Security.Principal.SecurityIdentifier])",
            "w32tm.exe /query /source",
            "expected=${dc}",
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
            "KINGDOMS_MEMBER_NOT_READY|reason=netlogon_session",
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
            "w32tm.exe /stripchart /computer:${dc}",
            "nltest.exe '/sc_query:${domain}'",
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
            fn.index("nltest.exe '/sc_query:${domain}'"),
        )
        self.assertLess(
            fn.index("nltest.exe '/sc_query:${domain}'"),
            fn.index("w32tm.exe /query /source"),
        )
        self.assertIn(
            'if [[ "${last_state}" == reason=time\\|* ]]; then',
            fn,
        )

    def test_member_time_recovery_requires_live_netlogon_session(self):
        text = self.text
        fn = text[text.index("wait_domain_member_ready()"):
                  text.index("preflight_domain_health()")]

        for token in (
            "KINGDOMS_MEMBER_NOT_READY|reason=netlogon_session",
            "KINGDOMS_MEMBER_TIME_REPAIR_FAILED|stage=netlogon_session",
            "KINGDOMS_MEMBER_TIME_REPAIR_FAILED|stage=netlogon_session_lost",
            "netlogon_session=ready",
        ):
            self.assertIn(token, fn)

    def test_time_repair_failure_marker_is_not_hidden(self):
        text = self.text
        fn = text[text.index("wait_domain_member_ready()"):
                  text.index("preflight_domain_health()")]

        self.assertIn(
            "KINGDOMS_MEMBER_TIME_(REPAIRED|REPAIR_FAILED)",
            fn,
        )
        self.assertIn(
            'elif [[ "${marker}" == KINGDOMS_MEMBER_TIME_REPAIR_FAILED\\|* ]]; then',
            fn,
        )
        self.assertIn(
            'bounded domain-time recovery failed: ${marker}',
            fn,
        )
        self.assertNotIn(
            "time-recovery command returned without a success marker",
            fn,
        )


if __name__ == "__main__":
    unittest.main()