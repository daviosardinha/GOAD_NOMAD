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

    def test_mitm6_background_launch_never_prompts_for_sudo(self):
        script = (DIAG / "start-mitm6-ws01.sh").read_text()
        self.assertIn("sudo -v", script)
        self.assertIn("sudo -n stdbuf", script)
        self.assertNotIn("sudo stdbuf", script)
        self.assertLess(script.index("sudo -v"), script.index("sudo -n stdbuf"))
        self.assertIn("sudo authentication leaked into the background mitm6 launch", script)

    def test_ws01_renew6_trigger_is_scoped_and_observable(self):
        shell = (DIAG / "trigger-ws01-renew6.sh").read_text()
        playbook = (ROOT / "ansible" / "phase03-trigger-ws01-renew6.yml").read_text()
        self.assertIn("hosts: ws01", playbook)
        self.assertIn("10.4.10.31", playbook)
        self.assertIn("ipconfig.exe /renew6", playbook)
        self.assertIn("Get-DnsClientServerAddress", playbook)
        self.assertIn("kingdoms-mitm6.log", shell)
        self.assertIn("validate-rickon-session.sh", shell)

    def test_wpad_chain_validator_requires_same_capture_sequence(self):
        script = (ROOT / "scripts" / "phase03" / "validate-wpad-chain.sh").read_text()
        self.assertIn("DHCPv6 Solicit", script)
        self.assertIn("DHCPv6 Advertise", script)
        self.assertIn("DHCPv6 Request", script)
        self.assertIn("DHCPv6 Reply", script)
        self.assertIn("attacker-controlled IPv6 DNS", script)
        self.assertIn("GET /wpad.dat", script)
        self.assertIn("reply <= dns <= http", script)
        self.assertIn("WS01_MAC", script)
        self.assertIn("-e eth.src", script)
        self.assertIn('eth.src == $WS01_MAC', script)
        self.assertNotIn("WS01_V6", script)

    def test_wpad_cleanup_is_scoped_and_preserves_evidence(self):
        script = (DIAG / "stop-wpad-runtime.sh").read_text()
        self.assertIn("mitm6", script)
        self.assertIn("http[.]server", script)
        self.assertIn("tcpdump", script)
        self.assertIn("kill -TERM", script)
        self.assertIn("kill -KILL", script)
        self.assertNotIn('rm -f "$PCAP"', script)
        self.assertIn("dnsmasq", script)

    def test_ldap_readonly_relay_profile_is_mutation_disabled(self):
        preflight = (ROOT / "scripts" / "phase03" / "check-ldap-readonly-relay.sh").read_text()
        start = (ROOT / "scripts" / "phase03" / "start-ldap-readonly-relay.sh").read_text()
        stop = (ROOT / "scripts" / "phase03" / "stop-ldap-readonly-relay.sh").read_text()
        for option in ("--no-dump", "--no-da", "--no-acl"):
            self.assertIn(option, preflight)
            self.assertIn(option, start)
        for option in ("--no-http-server", "--no-wcf-server", "--no-raw-server"):
            self.assertIn(option, start)
        self.assertIn("-smb2support", preflight)
        self.assertIn("-smb2support", start)
        self.assertNotIn("--smb2support", preflight)
        self.assertNotIn("--smb2support", start)
        self.assertIn('ldaps://$TARGET', start)
        self.assertIn("TCP/445", preflight)
        self.assertIn("Responder is not running", preflight)
        self.assertIn("kill -TERM", stop)
        self.assertNotIn("--delegate-access", start)
        self.assertNotIn("--shadow-credentials", start)
        self.assertNotIn("--add-computer", start)

    def test_rbcd_preflight_is_read_only_and_scoped_to_ws01(self):
        wrapper = (ROOT / "scripts" / "phase03" / "check-rbcd-prereqs.sh").read_text()
        playbook = (ROOT / "ansible" / "phase03-rbcd-preflight.yml").read_text()
        self.assertIn("hosts: dc02", playbook)
        self.assertIn("Get-ADComputer -Identity 'WS01'", playbook)
        self.assertIn("msDS-AllowedToActOnBehalfOfOtherIdentity", playbook)
        self.assertIn("PHASE03_RBCD_SELF_CAN_WRITE", playbook)
        self.assertIn("PHASE03_RBCD_MAQ", playbook)
        self.assertIn("PHASE03RBCD$", playbook)
        self.assertIn("phase03-rbcd-preflight.yml", wrapper)
        for forbidden in ("Set-AD", "New-ADComputer", "Remove-ADComputer"):
            self.assertNotIn(forbidden, playbook)

    def test_rbcd_baseline_capture_preserves_exact_pre_attack_state(self):
        wrapper = (ROOT / "scripts" / "phase03" / "capture-rbcd-baseline.sh").read_text()
        playbook = (ROOT / "ansible" / "phase03-rbcd-baseline.yml").read_text()
        self.assertIn("msDS-AllowedToActOnBehalfOfOtherIdentity", playbook)
        self.assertIn("RBCDBase64", playbook)
        self.assertIn("GetSecurityDescriptorBinaryForm", playbook)
        self.assertIn("CandidateExisted", playbook)
        self.assertIn("phase03-rbcd-baseline.json", playbook)
        self.assertIn("mode: '0600'", playbook)
        self.assertIn("python3 -m json.tool", wrapper)
        for forbidden in ("Set-AD", "New-ADComputer", "Remove-ADComputer"):
            self.assertNotIn(forbidden, playbook)

    def test_all_phase03_shell_scripts_parse(self):
        phase03 = ROOT / "scripts" / "phase03"
        for script in sorted(phase03.rglob("*.sh")):
            with self.subTest(script=script):
                result = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_rbcd_stage1_creates_only_reserved_candidate(self):
        start = (ROOT / "scripts" / "phase03" / "start-rbcd-stage1-add-computer.sh").read_text()
        verify = (ROOT / "ansible" / "phase03-rbcd-verify-stage1.yml").read_text()
        self.assertIn("--add-computer", start)
        self.assertIn("PHASE03RBCD", start)
        self.assertIn("--no-dump", start)
        self.assertIn("--no-da", start)
        self.assertIn("--no-acl", start)
        self.assertNotIn("--delegate-access", start)
        self.assertNotIn("--shadow-credentials", start)
        self.assertIn("phase03-rbcd-baseline.json", start)
        self.assertIn("phase03-rbcd-password", start)
        self.assertIn("PHASE03_RBCD_STAGE1_CANDIDATE_EXISTS", verify)
        self.assertIn("PHASE03_RBCD_STAGE1_RBCD_PRESENT", verify)
        for forbidden in ("Set-AD", "New-ADComputer", "Remove-ADComputer"):
            self.assertNotIn(forbidden, verify)

    def test_ws01_system_http_trigger_is_temporary_and_system_scoped(self):
        shell = (DIAG / "trigger-ws01-system-http.sh").read_text()
        playbook = (ROOT / "ansible" / "phase03-trigger-ws01-system-http.yml").read_text()
        self.assertIn("hosts: ws01", playbook)
        self.assertIn("New-ScheduledTaskPrincipal -UserId 'SYSTEM'", playbook)
        self.assertIn("Invoke-WebRequest", playbook)
        self.assertIn("-UseDefaultCredentials", playbook)
        self.assertIn("10.4.10.254", playbook)
        self.assertIn("Unregister-ScheduledTask", playbook)
        self.assertIn("ntlmrelayx is not running", shell)
        self.assertIn("TCP/80", shell)

    def test_rbcd_stage2_verifier_is_read_only(self):
        wrapper = (ROOT / "scripts" / "phase03" / "verify-rbcd-stage2.sh").read_text()
        playbook = (ROOT / "ansible" / "phase03-rbcd-verify-stage2.yml").read_text()
        self.assertIn("System.DirectoryServices.ActiveDirectorySecurity", playbook)
        self.assertIn("GetSecurityDescriptorBinaryForm", playbook)
        self.assertIn("[System.Security.AccessControl.RawSecurityDescriptor]::new($binary, 0)", playbook)
        self.assertIn("PHASE03_RBCD_STAGE2_RAW_TYPE", playbook)
        self.assertNotIn("New-Object System.Security.AccessControl.RawSecurityDescriptor", playbook)
        self.assertNotIn("[byte[]]$raw, 0", playbook)
        self.assertIn("PHASE03_RBCD_STAGE2_DELEGATION_PRESENT", playbook)
        self.assertIn("PHASE03RBCD$", playbook)
        self.assertIn("phase03-rbcd-verify-stage2.yml", wrapper)
        for forbidden in ("Set-AD", "New-ADComputer", "Remove-ADComputer"):
            self.assertNotIn(forbidden, playbook)

    def test_rbcd_s4u_proof_uses_ticket_cache_and_read_only_cifs_check(self):
        script = (ROOT / "scripts" / "phase03" / "prove-rbcd-s4u.sh").read_text()
        self.assertIn("impacket-getST", script)
        self.assertIn("-impersonate", script)
        self.assertIn("cifs/$TARGET_FQDN", script)
        self.assertIn("PHASE03RBCD$", script)
        self.assertIn('KRB5CCNAME="$TGT_CACHE"', script)
        self.assertIn('KRB5CCNAME="$ST_CACHE"', script)
        self.assertIn('export KRB5CCNAME="FILE:$TGT_CACHE"', script)
        self.assertIn('printf "%s\n" "$PASSWORD" | "$KINIT"', script)
        self.assertNotIn("sh -c", script)
        self.assertNotIn('KRB5CCNAME="FILE:$TGT_CACHE" \\\n    "$GETST"', script)
        self.assertNotIn('export KRB5CCNAME="FILE:$ST_CACHE"', script)
        self.assertIn("kinit", script)
        self.assertIn("use C$", script)
        self.assertIn("-inputfile", script)
        self.assertNotIn("wmiexec", script)
        self.assertNotIn("psexec", script)

    def test_rbcd_rollback_restores_baseline_and_cleans_only_ephemera(self):
        script = (ROOT / "scripts" / "phase03" / "rollback-rbcd.sh").read_text()
        playbook = (ROOT / "ansible" / "phase03-rbcd-rollback.yml").read_text()
        self.assertIn("phase03-rbcd-baseline.json", script)
        self.assertIn("Phase 03 poisoning/relay runtime is still active", script)
        self.assertIn("Set-ADComputer", playbook)
        self.assertIn("Remove-ADComputer", playbook)
        self.assertIn("PHASE03_RBCD_RESET_RBCD_MATCH", playbook)
        self.assertIn("PHASE03_RBCD_RESET_CANDIDATE_MATCH", playbook)
        self.assertIn("PHASE03_RBCD_RESET_COMPLETE=True", playbook)
        self.assertIn('rm -f -- "$SECRET_FILE"', script)
        self.assertIn('rm -rf -- "$WORK"', script)
        self.assertNotIn('rm -f -- "$BASELINE"', script)
        self.assertNotIn("kdestroy", script)

    def test_phase03_status_docs_are_not_duplicated_or_corrupted(self):
        scope = (ROOT / "docs" / "kingdoms-phase03-north-scope.md").read_text()
        runtime = (ROOT / "docs" / "kingdoms-phase03-runtime-checkpoint.md").read_text()
        self.assertEqual(scope.count("# Kingdoms — Phase 03 NORTH Scope and GOAD Part 4 Parity"), 1)
        self.assertEqual(runtime.count("# Kingdoms — Phase 03 Runtime Checkpoint"), 1)
        self.assertIn("| RBCD rollback |", scope)
        self.assertIn("RBCD is therefore closed end-to-end", runtime)

    def test_interactive_smb_relay_listener_is_scoped_to_castelblack(self):
        script = (ROOT / "scripts" / "phase03" / "start-smb-interactive-relay.sh").read_text()
        self.assertIn("10.4.10.22", script)
        self.assertIn("vmnet10", script)
        self.assertIn("-smb2support", script)
        self.assertTrue(any(line.strip() == "-i" for line in script.splitlines()))
        self.assertTrue(any(line.strip() == "--keep-relaying" for line in script.splitlines()))
        self.assertIn("127.0.0.1:11000+", script)
        self.assertIn("Responder.conf", script)
        self.assertIn("Responder SMB server must be Off", script)
        self.assertIn("Responder HTTP server must be Off", script)
        self.assertIn("SMB=Off HTTP=Off", script)
        self.assertNotIn("-socks", script)

    def test_status_docs_record_interactive_smb_relay_as_proven(self):
        runtime = (ROOT / "docs" / "kingdoms-phase03-runtime-checkpoint.md").read_text()
        scope = (ROOT / "docs" / "kingdoms-phase03-north-scope.md").read_text()
        self.assertIn("Interactive SMB relay to CASTELBLACK is **PROVEN**", runtime)
        self.assertIn("NORTH\\ROBB.STARK", runtime)
        self.assertIn("NORTH\\EDDARD.STARK", runtime)
        self.assertIn("| Interactive SMB relay |", scope)
        self.assertIn("| SOCKS relay |", scope)

    def test_status_docs_record_socks_smb_relay_as_proven(self):
        runtime = (ROOT / "docs" / "kingdoms-phase03-runtime-checkpoint.md").read_text()
        scope = (ROOT / "docs" / "kingdoms-phase03-north-scope.md").read_text()
        self.assertIn("SOCKS SMB relay to CASTELBLACK is **PROVEN**", runtime)
        self.assertIn("127.0.0.1:1080", runtime)
        self.assertIn("AdminStatus FALSE", runtime)
        self.assertIn("AdminStatus TRUE", runtime)
        self.assertIn("STATUS_ACCESS_DENIED", runtime)
        self.assertIn("| SOCKS relay |", scope)
        self.assertIn("| PROVEN |", scope)
        self.assertNotIn("SOCKS relay proof.", runtime)

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
