import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock


MODULE = Path(__file__).parents[1] / "tools" / "run_r10a_docking_smokes.py"
SPEC = importlib.util.spec_from_file_location("r10a_docking_runner", MODULE)
runner = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(runner)


class R10ADockingRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.evidence = self.root / "evidence"
        self.godot = self.root / "godot.exe"
        self.godot.write_text("mock engine", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def _execute(self, *, failures=None, duplicate=None, calls=None, omit_logs=None, output_overrides=None):
        failures = failures or {}
        output_overrides = output_overrides or {}

        def execute(case, godot, evidence, user_data):
            if calls is not None:
                calls.append((case, evidence, user_data))
            passed, reason = failures.get(case["filename"], (True, "passed"))
            body = output_overrides.get(case["filename"], case["marker"] + "\n")
            if case["filename"] == duplicate:
                body += case["marker"] + "\n"
            stdout = f"{case['id']}.stdout.log"
            stderr = f"{case['id']}.stderr.log"
            if case["filename"] != omit_logs:
                (evidence / stdout).write_text(body, encoding="utf-8")
                (evidence / stderr).write_text("", encoding="utf-8")
            return {
                "id": case["id"], "passed": passed, "reason": reason,
                "stdout_log": stdout, "stderr_log": stderr,
                "containment_probe": {"passed": True},
                "user_data_dir": str(user_data), "exit_code": 0,
                "diagnostics": [], "cleanup_error": None,
            }
        return execute

    def test_runs_each_mandatory_case_once_with_unique_homes(self):
        calls = []
        result = runner.run(self.godot, self.evidence, execute=self._execute(calls=calls))

        self.assertTrue(result["passed"])
        self.assertEqual(list(runner.CASE_FILENAMES), [case["filename"] for case, _, _ in calls])
        self.assertNotIn("fc_p09_natural_route_smoke.gd", runner.CASE_FILENAMES)
        self.assertEqual(15, len(calls))
        self.assertEqual(len(calls), len({home for _, _, home in calls}))
        self.assertTrue(result["marker"].startswith("R10-A DOCKING PREREQUISITE PASS"))
        summary = json.loads((self.evidence / "summary.json").read_text(encoding="utf-8"))
        hashes = json.loads((self.evidence / "artifact_hashes.json").read_text(encoding="utf-8"))
        self.assertEqual(len(calls), summary["case_count"])
        self.assertIn("summary.json", {entry["path"] for entry in hashes["entries"]})
        self.assertTrue(all((self.evidence / f"{item['id']}.result.json").is_file() for item in summary["results"]))

    def test_missing_planned_case_is_recorded_as_failure_and_never_skipped(self):
        planned = "r10a_dock_endpoint_contract_smoke.gd"
        result = runner.run(self.godot, self.evidence, execute=self._execute(
            failures={planned: (False, "missing script")}))

        self.assertFalse(result["passed"])
        failed = next(item for item in result["results"] if item["filename"] == planned)
        self.assertEqual("missing script", failed["reason"])
        self.assertTrue((self.evidence / f"{failed['id']}.result.json").is_file())

    def test_duplicate_marker_blocks_aggregate_pass(self):
        result = runner.run(self.godot, self.evidence, execute=self._execute(
            duplicate="docking_manager_smoke.gd"))

        self.assertFalse(result["passed"])
        failed = next(item for item in result["results"] if item["filename"] == "docking_manager_smoke.gd")
        self.assertEqual("duplicate marker", failed["reason"])
        self.assertEqual(2, failed["marker_count"])

    def test_exact_complete_markers_are_used_for_formatted_source_smokes(self):
        cases = {case["filename"]: case for case in runner.mandatory_cases()}
        self.assertEqual(
            "DOCKING MANAGER PASS aligned=true relationship=true undock=true "
            "rejects=true self_guard=true resevers=true",
            cases["docking_manager_smoke.gd"]["marker"])
        self.assertEqual(
            "SAVE MIGRATION WORLD PASS unknown_version_passthrough=true "
            "legacy_home_ship_migrated=true current_world_home_ship_migrated=true",
            cases["save_migration_world_smoke.gd"]["marker"])

    def test_static_markers_are_exact_source_lines_and_formatted_markers_are_declared(self):
        for case in runner.mandatory_cases():
            path = Path(runner.ROOT) / case["script"]
            with self.subTest(filename=case["filename"]):
                if not path.is_file():
                    self.assertTrue(case["filename"].startswith("r10a_"))
                    continue
                source = path.read_text(encoding="utf-8")
                if case["filename"] in runner.EXACT_MARKERS:
                    self.assertIn("%", source)
                    self.assertEqual(runner.EXACT_MARKERS[case["filename"]], case["marker"])
                else:
                    self.assertIn(f'print("{case["marker"]}")', source)

    def test_false_truncated_or_prefix_only_marker_output_is_rejected(self):
        expected = runner.EXACT_MARKERS["docking_manager_smoke.gd"]
        for name, output in {
            "false": expected.replace("rejects=true", "rejects=false") + "\n",
            "truncated": expected.rsplit(" resevers=", 1)[0] + "\n",
            "prefix_only": "DOCKING MANAGER PASS\n",
        }.items():
            with self.subTest(name=name):
                evidence = self.root / name
                result = runner.run(self.godot, evidence, execute=self._execute(
                    output_overrides={"docking_manager_smoke.gd": output}))
                failed = next(item for item in result["results"]
                              if item["filename"] == "docking_manager_smoke.gd")
                self.assertFalse(result["passed"])
                self.assertEqual("missing marker", failed["reason"])

    def test_hardened_failure_stays_failed_even_with_a_complete_marker(self):
        filename = "docking_manager_smoke.gd"
        result = runner.run(self.godot, self.evidence, execute=self._execute(
            failures={filename: (False, "missing marker")}))

        failed = next(item for item in result["results"] if item["filename"] == filename)
        self.assertFalse(result["passed"])
        self.assertFalse(failed["passed"])
        self.assertEqual("missing marker", failed["reason"])

    def test_missing_script_reason_is_not_replaced_when_no_raw_logs_exist(self):
        planned = "r10a_dock_endpoint_contract_smoke.gd"
        result = runner.run(self.godot, self.evidence, execute=self._execute(
            failures={planned: (False, "missing script")}, omit_logs=planned))

        failed = next(item for item in result["results"] if item["filename"] == planned)
        self.assertEqual("missing script", failed["reason"])

    def test_success_claim_without_retained_logs_is_rejected(self):
        case = "dock_ports_smoke.gd"
        result = runner.run(self.godot, self.evidence, execute=self._execute(omit_logs=case))

        failed = next(item for item in result["results"] if item["filename"] == case)
        self.assertEqual("missing retained raw output", failed["reason"])

    def test_existing_evidence_root_is_rejected_before_the_engine_seam(self):
        self.evidence.mkdir()
        execute = Mock()

        with self.assertRaisesRegex(runner.RunnerError, "new unique"):
            runner.run(self.godot, self.evidence, execute=execute)

        execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
