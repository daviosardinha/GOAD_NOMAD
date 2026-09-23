"""Read-only contract checks for the opt-in NORTH RBCD fixture.

These tests cannot substitute for an on-DC PowerShell parser test or a live
apply / second apply / reset / second reset acceptance run.
"""
from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
PLAY = ROOT / "ansible/phase03-rbcd.yml"
SCRIPT = ROOT / "ansible/files/phase03-rbcd-fixture.ps1"
ENTRY = ROOT / "scripts/phase03-rbcd.sh"
DOC = ROOT / "docs/phase03-rbcd-fixture.md"


class Phase03RBCDSourceTests(unittest.TestCase):
    def test_targeted_playbook_does_not_mutate_prior_phases(self):
        play = yaml.safe_load(PLAY.read_text())
        self.assertEqual(len(play), 1)
        self.assertEqual(play[0]["hosts"], "dc02")
        self.assertFalse(play[0]["gather_facts"])
        task_names = [task["name"] for task in play[0]["tasks"]]
        self.assertEqual(
            task_names,
            [
                "Audit, apply or reset the exact Rickon-to-CASTELBLACK attribute ACE",
                "Display read-only audit or safe dry-run preview",
            ],
        )
        win = play[0]["tasks"][0]["ansible.windows.win_powershell"]
        self.assertIn("phase03-rbcd-fixture.ps1", win["script"])
        self.assertEqual(win["parameters"]["Mode"], "{{ phase03_rbcd_action }}")
        assert_block = play[0]["pre_tasks"][0]["ansible.builtin.assert"]
        conditions = " ".join(assert_block["that"])
        self.assertIn("domain_name == 'GOAD'", conditions)
        self.assertIn("ansible_host == '10.4.10.11'", conditions)
        self.assertIn("lab.hosts.srv02", conditions)
        self.assertNotIn("dc01", conditions)
        self.assertNotIn("dc03", conditions)
        self.assertIn("or ansible_check_mode", play[0]["tasks"][1]["when"])
        self.assertIn("not ansible_check_mode", play[0]["tasks"][0]["no_log"])

    def test_attribute_acl_scope_and_guarded_reset(self):
        source = SCRIPT.read_text()
        self.assertIn("ValidateSet('audit', 'apply', 'reset')", source)
        self.assertIn("3f78c3e5-f79a-46bd-a0b8-9d18116ddc79", source)
        self.assertIn("ActiveDirectoryRights]::WriteProperty", source)
        self.assertIn("ActiveDirectorySecurityInheritance]::None", source)
        self.assertNotIn("ActiveDirectoryRights]::GenericAll", source)
        self.assertNotIn("ActiveDirectoryRights]::WriteDacl", source)
        self.assertIn("Get-ADUser -Identity $grantee", source)
        self.assertIn("Get-ADComputer -Identity 'CASTELBLACK'", source)
        self.assertIn("mS-DS-CreatorSID", source)
        self.assertIn("function Convert-RbcdToBytes", source)
        self.assertIn("ActiveDirectorySecurity", source)
        self.assertIn("function Get-RbcdTrusteeSids", source)
        self.assertIn("RbcdParseStatus", source)
        self.assertIn("RbcdTrusteeSids", source)
        self.assertIn("DaclRemovalPreviewStatus", source)
        self.assertIn("DaclRemovalPreviewMatchesInitial", source)
        self.assertIn("$copy.RemoveAccessRuleSpecific($copyMatching[0])", source)
        self.assertIn("$copy.SetSecurityDescriptorBinaryForm($acl.GetSecurityDescriptorBinaryForm())", source)
        self.assertNotIn("$rbcd -isnot [byte[]]", source)
        self.assertIn("RemoveAccessRuleSpecific($rule)", source)
        self.assertIn("state.InitialDacl", source)
        self.assertIn("state.AppliedDacl", source)
        self.assertIn("if ($null -ne $rbcd)", source)
        self.assertIn("throw 'RBCD contains unexpected trustees", source)
        self.assertIn("Remove-ADComputer -Identity $training[0].DistinguishedName", source)
        self.assertNotIn("Set-ADGroupMember", source)
        self.assertIn("State = 'would-add-exact-attribute-ace'", source)
        self.assertIn("State = 'would-restore-original-attribute-and-dacl'", source)
        self.assertEqual(source.count("$Ansible.Changed = $true"), 6)

    def test_operator_requires_instance_and_clean_upstream(self):
        source = ENTRY.read_text()
        self.assertIn("--instance", source)
        self.assertIn(".vagrant/machines/GOAD-DC02/vmware_desktop/id", source)
        self.assertIn("scripts/verify-test-source.sh", source)
        self.assertIn("phase03_rbcd_action=$ACTION", source)
        self.assertIn("--check --diff", source)
        main = (ROOT / "ansible/main.yml").read_text()
        self.assertNotIn("phase03-rbcd.yml", main)
        self.assertIn("second APPLY", DOC.read_text())


if __name__ == "__main__":
    unittest.main()
