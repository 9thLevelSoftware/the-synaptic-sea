import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


MODULE = Path(__file__).parents[1] / "tools" / "run_feature_completion.py"
SPEC = importlib.util.spec_from_file_location("feature_runner", MODULE)
runner = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(runner)


class FeatureCompletionRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.evidence = self.root / "evidence"; self.evidence.mkdir()
        self.user_data = self.evidence / "user-data"; self.user_data.mkdir()
        self.original_root = runner.ROOT
        runner.ROOT = self.root
        (self.root / "scripts/validation").mkdir(parents=True)
        self.script = self.root / "scripts/validation/fc_p03_smoke.gd"
        self.script.write_text("extends SceneTree\n", encoding="utf-8")
        self.case = {"id": "P03", "scope": "model", "script": "scripts/validation/fc_p03_smoke.gd", "marker": "FC P03 PASS"}

    def tearDown(self):
        runner.ROOT = self.original_root
        self.temp.cleanup()

    def _run(self, stdout="FC P03 PASS\n", stderr="", code=0):
        def fake(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], code, stdout, stderr)
        return runner.execute_case(self.case, Path("godot"), self.evidence, self.user_data, run=fake)

    def test_exit_zero_without_marker_fails(self):
        self.assertEqual("missing marker", self._run(stdout="done\n")["reason"])

    def test_pass_with_error_fails(self):
        result = self._run(stderr="ERROR: bad thing\n")
        self.assertFalse(result["passed"]); self.assertEqual("unexpected diagnostics", result["reason"])

    def test_pass_with_warning_fails(self):
        self.assertFalse(self._run(stderr="WARNING: bad thing\n")["passed"])

    def test_expected_negative_diagnostic_still_fails(self):
        self.assertFalse(self._run(stdout="FC P03 PASS\nERROR: expected negative assertion\n")["passed"])

    def test_nonzero_exit_with_pass_fails(self):
        result = self._run(code=7)
        self.assertFalse(result["passed"]); self.assertEqual("nonzero exit", result["reason"])

    def test_timeout_fails_and_captures_logs(self):
        def timeout(*args, **kwargs):
            raise subprocess.TimeoutExpired(args[0], kwargs["timeout"], output="partial", stderr="still running")
        result = runner.execute_case(self.case, Path("godot"), self.evidence, self.user_data, run=timeout)
        self.assertFalse(result["passed"]); self.assertEqual("timeout", result["reason"])
        self.assertEqual("partial", (self.evidence / result["stdout_log"]).read_text())
        self.assertEqual("still running", (self.evidence / result["stderr_log"]).read_text())

    def test_timeout_cleans_up_only_owned_process_group(self):
        process = Mock(pid=4242)
        process.communicate.side_effect = [subprocess.TimeoutExpired(["godot"], 1), (b"partial", b"tail")]
        with patch.object(runner.os, "name", "posix"), patch.object(runner.subprocess, "Popen", return_value=process), patch.object(runner.os, "killpg", create=True) as killpg, patch.object(runner.signal, "SIGKILL", 9, create=True):
            stdout, stderr, code, timed_out = runner._capture(["godot"], cwd=self.root, env={}, timeout=1)
        self.assertTrue(timed_out); self.assertIsNone(code)
        self.assertEqual("partial", stdout); self.assertEqual("tail", stderr)
        killpg.assert_called_once_with(4242, 9)

    def test_missing_script_fails_explicitly(self):
        self.script.unlink()
        result = self._run()
        self.assertFalse(result["passed"]); self.assertEqual("missing script", result["reason"])

    def test_stdout_and_stderr_are_captured_separately(self):
        result = self._run(stdout="FC P03 PASS\nstdout", stderr="stderr")
        self.assertEqual("FC P03 PASS\nstdout", (self.evidence / result["stdout_log"]).read_text())
        self.assertEqual("stderr", (self.evidence / result["stderr_log"]).read_text())

    def test_duplicate_case_ids_are_rejected(self):
        manifest = self.root / "cases.json"
        manifest.write_text('{"cases":[{"id":"P03","script":"a","marker":"x"},{"id":"P03","script":"b","marker":"y"}]}')
        with self.assertRaisesRegex(runner.RunnerError, "duplicate"):
            runner.load_cases(manifest)

    def test_canonical_extraction_requires_expected_boundary_and_marker(self):
        plan = self.root / "plan.md"
        plan.write_text("## Regression bundle\n\n```bash\nrun_clean 'a' 'a' true\n```\n")
        with self.assertRaisesRegex(runner.RunnerError, "marker"):
            runner.extract_regression_bundle(plan)


if __name__ == "__main__":
    unittest.main()
