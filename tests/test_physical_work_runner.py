import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE = Path(__file__).parents[1] / "tools" / "run_physical_work_smokes.py"
SPEC = importlib.util.spec_from_file_location("physical_work_runner", MODULE)
runner = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(runner)


class PhysicalWorkRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.evidence = self.root / "evidence"
        self.godot = self.root / "godot.exe"
        self.godot.write_text("test executable", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def _result(self, case, *, passed=True, reason="passed"):
        return {
            "id": case["id"], "passed": passed, "reason": reason,
            "stdout_log": f"{case['id']}.stdout.log",
            "stderr_log": f"{case['id']}.stderr.log",
            "containment_probe": {"passed": passed},
            "user_data_dir": "owned-home",
        }

    def test_group_uses_every_accepted_card_smoke_once(self):
        calls = []

        def execute(case, godot, evidence, user_data):
            calls.append((case, evidence, user_data))
            (evidence / f"{case['id']}.stdout.log").write_text(case["marker"] + "\n", encoding="utf-8")
            (evidence / f"{case['id']}.stderr.log").write_text("", encoding="utf-8")
            return self._result(case)

        result = runner.run_group("P11", self.godot, self.evidence, execute=execute)

        self.assertTrue(result["passed"])
        self.assertEqual(runner.CARD_SMOKES["P11"], [item["filename"] for item, _, _ in calls])
        self.assertEqual(len(runner.CARD_SMOKES["P11"]), len({item["id"] for item, _, _ in calls}))
        self.assertEqual({self.evidence / "user-data" / item["id"] for item, _, _ in calls}, {home for _, _, home in calls})
        summary = json.loads((self.evidence / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual("P11", summary["group"])
        self.assertEqual(4, summary["case_count"])
        self.assertTrue(all(
            (self.evidence / f"{item['id']}.result.json").is_file()
            for item in summary["results"]
        ))

    def test_reused_evidence_root_is_rejected_without_launching(self):
        self.evidence.mkdir()
        sentinel = self.evidence / "prior.json"
        sentinel.write_text("retain", encoding="utf-8")
        execute = unittest.mock.Mock()

        with self.assertRaisesRegex(runner.RunnerError, "new unique"):
            runner.run_group("P12", self.godot, self.evidence, execute=execute)

        execute.assert_not_called()
        self.assertEqual("retain", sentinel.read_text(encoding="utf-8"))

    def test_existing_empty_evidence_root_is_rejected_before_launching(self):
        self.evidence.mkdir()
        execute = unittest.mock.Mock()

        with self.assertRaisesRegex(runner.RunnerError, "new unique"):
            runner.run_group("P13", self.godot, self.evidence, execute=execute)

        execute.assert_not_called()

    def test_containment_or_body_failures_block_pass_marker_and_are_retained(self):
        def execute(case, godot, evidence, user_data):
            (evidence / f"{case['id']}.stdout.log").write_text("raw stdout\n", encoding="utf-8")
            (evidence / f"{case['id']}.stderr.log").write_text("raw stderr\n", encoding="utf-8")
            if case["filename"] == runner.CARD_SMOKES["P12"][0]:
                return self._result(case, passed=False, reason="containment probe failed")
            return self._result(case, passed=False, reason="missing marker")

        result = runner.run_group("P12", self.godot, self.evidence, execute=execute)

        self.assertFalse(result["passed"])
        self.assertNotIn("R06 P12 FOCUSED PASS", result["marker"])
        self.assertEqual(4, len(result["results"]))
        self.assertTrue(all((self.evidence / item["stdout_log"]).is_file() for item in result["results"]))
        self.assertTrue(all((self.evidence / item["stderr_log"]).is_file() for item in result["results"]))

    def test_adapter_preserves_hardened_failure_reasons(self):
        failures = ("missing marker", "duplicate marker", "unexpected diagnostics", "timeout", "cleanup failure")
        for failure in failures:
            with self.subTest(failure=failure):
                evidence = self.root / failure.replace(" ", "-")

                def execute(case, godot, case_evidence, user_data):
                    (case_evidence / f"{case['id']}.stdout.log").write_text("", encoding="utf-8")
                    (case_evidence / f"{case['id']}.stderr.log").write_text("", encoding="utf-8")
                    return self._result(case, passed=False, reason=failure)

                result = runner.run_group("P11", self.godot, evidence, execute=execute)
                self.assertFalse(result["passed"])
                self.assertEqual([failure] * 4, [item["reason"] for item in result["results"]])


if __name__ == "__main__":
    unittest.main()
