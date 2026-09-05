import importlib.util
import os
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

    def test_near_match_and_stderr_only_marker_fail(self):
        self.assertFalse(self._run(stdout="NOT FC P03 PASSING\n")["passed"])
        self.assertFalse(self._run(stdout="", stderr="FC P03 PASS\n")["passed"])

    def test_pass_with_script_error_fails(self):
        self.assertFalse(self._run(stdout="FC P03 PASS\n\x1b[31mSCRIPT ERROR: Invalid call\x1b[0m\n")["passed"])

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
            stdout, stderr, code, timed_out, cleanup_error = runner._capture(["godot"], cwd=self.root, env={}, timeout=1)
        self.assertTrue(timed_out); self.assertIsNone(code)
        self.assertEqual("partial", stdout); self.assertEqual("tail", stderr)
        self.assertIsNone(cleanup_error)
        killpg.assert_called_once_with(4242, 9)

    def test_windows_cleanup_targets_only_owned_pid_and_reports_failure(self):
        process = Mock(pid=4242)
        failed = subprocess.CompletedProcess(["taskkill"], 1, "", "no access")
        with patch.object(runner.os, "name", "nt"), patch.object(runner.subprocess, "run", return_value=failed) as taskkill:
            error = runner._terminate_owned_process(process)
        taskkill.assert_called_once_with(["taskkill", "/PID", "4242", "/T", "/F"], text=True, capture_output=True, check=False)
        self.assertEqual("taskkill failed: 1", error)

    def test_windows_process_group_is_created(self):
        process = Mock(pid=9); process.communicate.return_value = ("", ""); process.returncode = 0
        with patch.object(runner.os, "name", "nt"), patch.object(runner.subprocess, "Popen", return_value=process) as popen:
            runner._capture(["godot"], cwd=self.root, env={}, timeout=1)
        self.assertEqual(runner.subprocess.CREATE_NEW_PROCESS_GROUP, popen.call_args.kwargs["creationflags"])

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

    def test_headless_manifest_rejects_player_scope_and_invalid_status(self):
        manifest = self.root / "cases.json"
        manifest.write_text('{"cases":[{"id":"P03","script":"a","marker":"FC P03 PASS","scope":"player","status":"done"}]}')
        with self.assertRaisesRegex(runner.RunnerError, "invalid"):
            runner.load_cases(manifest)

    def test_manifest_rejects_unknown_profile(self):
        manifest = self.root / "cases.json"
        manifest.write_text('{"cases":[{"id":"P03","script":"a","marker":"FC P03 PASS","scope":"model","status":"active","profile":"craftng"}]}')
        with self.assertRaisesRegex(runner.RunnerError, "invalid"):
            runner.load_cases(manifest)

    def test_manifest_rejects_missing_profile(self):
        manifest = self.root / "cases.json"
        manifest.write_text('{"cases":[{"id":"P03","script":"a","marker":"FC P03 PASS","scope":"model","status":"active"}]}')
        with self.assertRaisesRegex(runner.RunnerError, "invalid"):
            runner.load_cases(manifest)

    def test_manifest_accepts_only_named_profiles(self):
        manifest = self.root / "cases.json"
        manifest.write_text('{"cases":[{"id":"P03","script":"a","marker":"FC P03 PASS","scope":"model","status":"active","profile":"crafting"},{"id":"P04","script":"b","marker":"FC P04 PASS","scope":"scene","status":"planned","profile":"restoration"}]}')
        cases = runner.load_cases(manifest)
        self.assertEqual({"crafting", "restoration"}, {case["profile"] for case in cases})

    def test_canonical_extraction_requires_expected_boundary_and_marker(self):
        plan = self.root / "plan.md"
        plan.write_text("## Regression bundle\n\n```bash\nrun_clean 'a' 'a' true\n```\n")
        with self.assertRaisesRegex(runner.RunnerError, "marker"):
            runner.extract_regression_bundle(plan)

    def _bundle(self, stdout, stderr="", code=0):
        body = "run_clean() { :; }\nrun_clean 'one' 'one' true\necho 'SYNAPTIC_SEA REGRESSION PASS commands=999 clean_output=true'\n"
        def fake(command, **kwargs):
            if command[-1] == "--version":
                return subprocess.CompletedProcess(command, 0, "GNU bash", "")
            return subprocess.CompletedProcess(command, code, stdout, stderr)
        with patch.object(runner, "extract_regression_bundle", return_value=(body, 1)), patch.object(runner, "_verified_bash", return_value="C:\\Program Files\\Git\\bin\\bash.exe"):
            return runner.execute_bundle(Path("C:\\Godot\\godot.exe"), self.evidence, self.user_data, run=fake, timeout=1)

    def test_bundle_rejects_mismatch_duplicate_stderr_and_trailing_marker_forms(self):
        self.assertFalse(self._bundle("SYNAPTIC_SEA REGRESSION PASS commands=999 clean_output=true\n")["passed"])
        self.assertFalse(self._bundle("SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true\nSYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true\n")["passed"])
        self.assertFalse(self._bundle("", "SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true\n")["passed"])
        self.assertFalse(self._bundle("SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true\nafter\n")["passed"])

    def test_bundle_allows_canonical_allowlisted_output_but_requires_bundle_exit_for_other_diagnostics(self):
        allowed = "WARNING: SaveLoadService: cannot save null world snapshot\nSYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true\n"
        self.assertTrue(self._bundle(allowed)["passed"])
        self.assertFalse(self._bundle("WARNING: unexpected\nSYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true\n", code=1)["passed"])

    def test_windows_rejects_wsl_bash_and_accepts_git_bash_with_windows_paths(self):
        def fake(command, **kwargs):
            return subprocess.CompletedProcess(command, 0, "GNU bash", "")
        with patch.object(runner.os, "name", "nt"), patch.object(runner.shutil, "which", return_value=r"C:\Windows\System32\bash.exe"), patch.object(runner.Path, "is_file", return_value=False):
            with self.assertRaisesRegex(runner.RunnerError, "Windows-compatible"):
                runner._verified_bash(fake)
        with patch.object(runner.os, "name", "nt"), patch.object(runner.shutil, "which", return_value=r"C:\Program Files\Git\bin\bash.exe"):
            self.assertEqual(r"C:\Program Files\Git\bin\bash.exe", runner._verified_bash(fake))

    def test_prepared_bundle_derives_count_at_runtime(self):
        source = "run_clean() {\n  :\n}\nrun_clean 'one' 'one' true\necho 'SYNAPTIC_SEA REGRESSION PASS commands=633 clean_output=true'\n"
        prepared = runner._prepared_bundle(source)
        self.assertIn("RUN_CLEAN_COUNT=$((RUN_CLEAN_COUNT + 1))", prepared)
        self.assertIn("commands=${RUN_CLEAN_COUNT}", prepared)

    def test_post_kill_drain_timeout_is_reported(self):
        process = Mock(pid=17)
        process.communicate.side_effect = [subprocess.TimeoutExpired(["godot"], 1), subprocess.TimeoutExpired(["godot"], 5)]
        with patch.object(runner.os, "name", "posix"), patch.object(runner.subprocess, "Popen", return_value=process), patch.object(runner.os, "killpg", create=True), patch.object(runner.signal, "SIGKILL", 9, create=True):
            _, _, _, timed_out, cleanup_error = runner._capture(["godot"], cwd=self.root, env={}, timeout=1)
        self.assertTrue(timed_out)
        self.assertEqual("post-kill output drain timed out", cleanup_error)

    def test_canonical_run_clean_prints_a_failing_child_before_exiting(self):
        bash = Path(r"C:\Program Files\Git\bin\bash.exe")
        if not bash.is_file():
            self.skipTest("Git Bash is required for this Windows shell regression")
        script = self.root / "failing-child-regression.sh"
        body, _ = runner.extract_regression_bundle()
        # Exercise the authoritative shell policy rather than a copied function.
        policy = body.split("\nrun_clean ", 1)[0]
        environment = {**os.environ, "ROOT": str(self.root), "GODOT": "unused"}
        for output, expected_code, failure_marker in (
            ("retained failure", 7, "COMMAND_FAILED exit=7"),
            ("ERROR: retained failure", 1, "UNEXPECTED_ERROR_OR_WARNING"),
        ):
            with self.subTest(output=output):
                script.write_text(
                    policy + "\nrun_clean 'fake child' 'FAKE PASS' /bin/sh -c "
                    + "'printf \"FAKE PASS\\n" + output + "\\n\"; exit 7'\n",
                    encoding="utf-8", newline="\n")
                result = subprocess.run([str(bash), str(script)], env=environment,
                                        text=True, capture_output=True, check=False, timeout=10)
                self.assertEqual(expected_code, result.returncode, result.stderr)
                self.assertIn(output, result.stdout)
                self.assertIn(failure_marker, result.stdout)


if __name__ == "__main__":
    unittest.main()
