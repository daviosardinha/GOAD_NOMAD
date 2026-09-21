"""Source contract for the single-command Kingdoms release acceptance orchestrator."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "validate-kingdoms-release-acceptance.sh"


class ReleaseAcceptanceOrchestratorTests(unittest.TestCase):
    def test_orchestrator_is_fail_fast_without_parent_shell_errexit(self):
        text = SCRIPT.read_text()
        self.assertIn("set -uo pipefail", text)
        self.assertNotIn("set -Eeuo pipefail", text)
        self.assertIn("run_stage()", text)
        self.assertIn("restore_exercise()", text)
        self.assertIn("A validation failure exits this child script, not your interactive shell.", text)

    def test_all_acceptance_stages_are_ordered(self):
        text = SCRIPT.read_text()
        stages = [
            "source_identity",
            "regression_suite",
            "clean_install_source",
            "prepare_runtime_power",
            "rdp_phase01",
            "clean_install_runtime",
            "full_lpe_runtime",
            "phase02_readiness",
            "final_health",
            "final_exercise_state",
            "vmware_running_set",
        ]
        positions = [text.index(f"run_stage {index} ") for index in range(len(stages))]
        self.assertEqual(positions, sorted(positions))
        for stage in stages:
            self.assertIn(stage, text)

    def test_runtime_power_recovery_is_non_provisioning_and_conflict_guarded(self):
        text = SCRIPT.read_text()
        self.assertIn("check-vmware-instance-conflicts.sh", text)
        self.assertIn("vmrun -T ws start", text)
        self.assertIn("nogui", text)
        self.assertIn("ethernet0.startConnected=FALSE", text)
        self.assertNotIn("vagrant up", text)

    def test_phase02_receives_the_requested_instance_via_env(self):
        text = SCRIPT.read_text()
        self.assertIn('env \\\\', text)
        self.assertIn('INSTANCE="${INSTANCE}" \\\\', text)
        self.assertIn('PROVIDER="${PROVIDER}" \\\\', text)
        self.assertIn('EVIDENCE="${EVIDENCE}/phase02" \\\\', text)
        self.assertIn('bash scripts/validate-phase02-readiness.sh', text)

    def test_final_health_temporarily_reopens_management_and_restores_exercise(self):
        text = SCRIPT.read_text()
        start = text.index('final_health()')
        end = text.index('final_exercise_state()', start)
        block = text[start:end]

        self.assertIn('final health proof requires exercise mode', block)
        self.assertIn('lab-mode.sh" provisioning', block)
        self.assertIn('kingdoms-health-final.yml', block)
        self.assertIn('lab-mode.sh" exercise', block)
        self.assertIn('all-six final domain health proof failed', block)

    def test_orchestrator_never_destroys_or_merges(self):
        text = SCRIPT.read_text().lower()
        self.assertNotIn("goad.sh -t destroy", text)
        self.assertNotIn("vagrant destroy", text)
        self.assertNotIn("git merge", text)
        self.assertNotIn("gh pr merge", text)

    def test_final_contract_requires_exercise_and_drop(self):
        text = SCRIPT.read_text()
        self.assertIn("Recorded mode: exercise", text)
        self.assertIn("policy drop;", text)
        self.assertIn("Full 20-scenario LPE reversibility", text)


if __name__ == "__main__":
    unittest.main()
