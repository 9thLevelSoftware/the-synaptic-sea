import importlib.util
import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


MODULE = Path(__file__).parents[1] / "tools" / "run_p10_process_smoke.py"
SPEC = importlib.util.spec_from_file_location("p10_process_runner", MODULE)
runner = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(runner)


class P10ProcessRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.original_root = runner.ROOT
        runner.ROOT = self.root
        (self.root / "project.godot").write_text("[application]\nconfig/name=\"test\"\n", encoding="utf-8")
        (self.root / "scripts/validation").mkdir(parents=True)
        (self.root / "scripts/validation/fc_p10_process_smoke.gd").write_text("extends SceneTree\n")
        self.godot = self.root / "godot.exe"; self.godot.write_text("")

    def tearDown(self):
        runner.ROOT = self.original_root
        self.temp.cleanup()

    @staticmethod
    def _probe_result(command):
        values = dict(arg[2:].split("=", 1) for arg in command
                      if arg.startswith("--") and "=" in arg)
        if values.get("mode") != "probe":
            return None
        root = values["user_data"].replace("\\", "/")
        return subprocess.CompletedProcess(
            command, 0,
            f"FC P10 USER DATA PROBE PASS resolved_user={root}/Godot/app_userdata/test os_user={root}/Godot/app_userdata/test root={root}\n",
            "")

    def test_mode_requires_exact_marker_and_no_diagnostics(self):
        evidence = self.root / "evidence"; evidence.mkdir(); user = evidence / "user"; user.mkdir()
        paths = {key: evidence / f"{key}.json" for key in ("baseline", "expected", "post", "post_manifest")}
        def fake(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, "FC P10 PROCESS PRODUCER PASS\n", "")
        self.assertTrue(runner._execute_mode("producer", self.godot, self.root, evidence, user, paths, 1, fake)["passed"])
        def warning(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, "FC P10 PROCESS PRODUCER PASS\n", "WARNING: nope\n")
        self.assertFalse(runner._execute_mode("producer", self.godot, self.root, evidence, user, paths, 1, warning)["passed"])

    def test_timeout_cleans_only_owned_tree(self):
        process = Mock(pid=4242)
        process.communicate.side_effect = [subprocess.TimeoutExpired(["godot"], 1), ("partial", "tail")]
        with patch.object(runner.os, "name", "posix"), patch.object(runner.subprocess, "Popen", return_value=process), patch.object(runner.os, "killpg", create=True) as killpg, patch.object(runner.signal, "SIGKILL", 9, create=True):
            _, _, _, timed_out, cleanup = runner._capture(["godot"], cwd=self.root, env={}, timeout=1)
        self.assertTrue(timed_out); self.assertIsNone(cleanup)
        killpg.assert_called_once_with(4242, 9)

    def test_rejects_reused_evidence_directory(self):
        evidence = self.root / "evidence"; evidence.mkdir(); (evidence / "old").write_text("x")
        with self.assertRaisesRegex(runner.RunnerError, "new empty unique"):
            runner.execute(self.godot, evidence)

    def test_environment_is_run_local(self):
        user = self.root / "run/user-data"
        env = runner._environment(user)
        for key in ("APPDATA", "LOCALAPPDATA", "GODOT_USER_PATH", "XDG_DATA_HOME"):
            self.assertEqual(str(user), env[key])
        evidence = self.root / "evidence"; evidence.mkdir()
        user = evidence / "user"; user.mkdir()
        observed = {}
        def fake(command, **kwargs):
            observed["env"] = kwargs["env"]
            return self._probe_result(command)
        result = runner._execute_containment_probe(
            "producer", self.godot, self.root, evidence, user, 1, fake)
        self.assertTrue(result["passed"])
        for key in ("APPDATA", "LOCALAPPDATA", "GODOT_USER_PATH", "XDG_DATA_HOME"):
            self.assertEqual(str(user), observed["env"][key])

    def test_windows_cleanup_uses_only_child_pid(self):
        process = Mock(pid=99)
        failed = subprocess.CompletedProcess(["taskkill"], 1, "", "denied")
        with patch.object(runner.os, "name", "nt"), patch.object(runner.subprocess, "run", return_value=failed) as taskkill:
            self.assertEqual("taskkill failed: 1", runner._terminate_owned_process(process))
        taskkill.assert_called_once_with(["taskkill", "/PID", "99", "/T", "/F"], text=True, capture_output=True, check=False)

    def test_producer_digest_mismatch_fails_before_consumer_and_retains_logs(self):
        calls = []
        def fake(command, **kwargs):
            calls.append(command)
            probe = self._probe_result(command)
            if probe is not None:
                return probe
            values = dict(arg[2:].split("=", 1) for arg in command if arg.startswith("--") and "=" in arg)
            if values["mode"] == "producer":
                Path(values["baseline"]).write_bytes(b"baseline")
                Path(values["expected"]).write_text(json.dumps({"schema": "p10-process-1", "baseline_sha256": "0" * 64}), encoding="utf-8")
            return subprocess.CompletedProcess(command, 0, f"FC P10 PROCESS {values['mode'].upper()} PASS\n", "")
        evidence = self.root / "evidence"
        with patch.object(runner, "_metadata", return_value={}):
            summary = runner.execute(self.godot, evidence, run=fake)
        self.assertFalse(summary["passed"])
        self.assertEqual("baseline digest mismatch", summary["results"][0]["reason"])
        self.assertEqual(2, len(calls))
        self.assertTrue((evidence / "producer.stdout.log").is_file())

    def test_missing_marker_fails_even_with_zero_exit(self):
        evidence = self.root / "evidence"; evidence.mkdir(); user = evidence / "user"; user.mkdir()
        paths = {key: evidence / f"{key}.json" for key in ("baseline", "expected", "post", "post_manifest")}
        def fake(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, "finished\n", "")
        result = runner._execute_mode("consumer2", self.godot, self.root, evidence, user, paths, 1, fake)
        self.assertFalse(result["passed"])
        self.assertEqual("missing marker", result["reason"])

    def test_json_array_manifest_is_rejected_with_retained_summary(self):
        calls = []
        def fake(command, **kwargs):
            calls.append(command)
            probe = self._probe_result(command)
            if probe is not None:
                return probe
            values = dict(arg[2:].split("=", 1) for arg in command if arg.startswith("--") and "=" in arg)
            Path(values["baseline"]).write_bytes(b"baseline")
            Path(values["expected"]).write_text("[]", encoding="utf-8")
            return subprocess.CompletedProcess(command, 0, "FC P10 PROCESS PRODUCER PASS\n", "")
        evidence = self.root / "evidence"
        with patch.object(runner, "_metadata", return_value={}):
            summary = runner.execute(self.godot, evidence, run=fake)
        self.assertFalse(summary["passed"])
        self.assertIn("malformed expected manifest", summary["results"][0]["reason"])
        self.assertTrue((evidence / "summary.json").is_file())
        self.assertEqual(2, len(calls))

    def test_explicit_root_is_used_as_child_cwd_and_path(self):
        alternate = self.root / "alternate"; (alternate / "scripts/validation").mkdir(parents=True)
        (alternate / "project.godot").write_text("[application]\n", encoding="utf-8")
        (alternate / "scripts/validation/fc_p10_process_smoke.gd").write_text("extends SceneTree\n", encoding="utf-8")
        evidence = self.root / "evidence"; evidence.mkdir(); user = evidence / "user"; user.mkdir()
        paths = {key: evidence / f"{key}.json" for key in ("baseline", "expected", "post", "post_manifest")}
        observed = {}
        def fake(command, **kwargs):
            observed["cwd"] = kwargs["cwd"]
            observed["path"] = command[command.index("--path") + 1]
            return subprocess.CompletedProcess(command, 0, "FC P10 PROCESS PRODUCER PASS\n", "")
        runner._execute_mode("producer", self.godot, alternate, evidence, user, paths, 1, fake)
        self.assertEqual(alternate, observed["cwd"])
        self.assertEqual(str(alternate), observed["path"])

    def test_wrong_or_duplicate_process_marker_fails(self):
        evidence = self.root / "evidence"; evidence.mkdir(); user = evidence / "user"; user.mkdir()
        paths = {key: evidence / f"{key}.json" for key in ("baseline", "expected", "post", "post_manifest")}
        def wrong(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, "FC P10 PROCESS CONSUMER2 PASS\n", "")
        self.assertFalse(runner._execute_mode("producer", self.godot, self.root, evidence, user, paths, 1, wrong)["passed"])
        def duplicate(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, "FC P10 PROCESS PRODUCER PASS\nFC P10 PROCESS PRODUCER PASS\n", "")
        self.assertFalse(runner._execute_mode("producer", self.godot, self.root, evidence, user, paths, 1, duplicate)["passed"])

    def test_reviewed_production_output_prefixes_are_allowed_but_unknown_is_not(self):
        evidence = self.root / "evidence"; evidence.mkdir(); user = evidence / "user"; user.mkdir()
        paths = {key: evidence / f"{key}.json" for key in ("baseline", "expected", "post", "post_manifest")}
        def allowed(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, "CRAFT STARTED id=job\nCRAFT COMPLETED id=job\nFIELD CRAFT STARTED id=field\nFIELD CRAFT COMPLETED id=field\nFC P10 PROCESS PRODUCER PASS\n", "")
        self.assertTrue(runner._execute_mode("producer", self.godot, self.root, evidence, user, paths, 1, allowed)["passed"])
        def unknown(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, "unreviewed output\nFC P10 PROCESS PRODUCER PASS\n", "")
        self.assertFalse(runner._execute_mode("producer", self.godot, self.root, evidence, user, paths, 1, unknown)["passed"])

    def test_nonempty_mode_stderr_fails_even_without_diagnostic(self):
        evidence = self.root / "evidence"; evidence.mkdir(); user = evidence / "user"; user.mkdir()
        paths = {key: evidence / f"{key}.json" for key in ("baseline", "expected", "post", "post_manifest")}
        def fake(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, "FC P10 PROCESS PRODUCER PASS\n", "unclassified stderr\n")
        self.assertFalse(runner._execute_mode("producer", self.godot, self.root, evidence, user, paths, 1, fake)["passed"])

    def test_version_probe_requires_nonempty_clean_engine_evidence(self):
        with patch.object(runner, "_capture", return_value=("", "", 0, False, None)):
            with self.assertRaisesRegex(runner.RunnerError, "version probe failed"):
                runner._metadata(self.godot, self.root)
        with patch.object(runner, "_capture", return_value=("4.7\n", "WARNING: noisy\n", 0, False, None)):
            with self.assertRaisesRegex(runner.RunnerError, "version probe failed"):
                runner._metadata(self.godot, self.root)

    def test_mode_receives_only_its_declared_disk_inputs(self):
        evidence = self.root / "evidence"; evidence.mkdir(); user = evidence / "user"; user.mkdir()
        paths = {key: evidence / f"{key}.json" for key in ("baseline", "expected", "post", "post_manifest")}
        observed = []
        def fake(command, **kwargs):
            observed.extend(command)
            return subprocess.CompletedProcess(command, 0, "FC P10 PROCESS CONSUMER2 PASS\n", "")
        result = runner._execute_mode("consumer2", self.godot, self.root, evidence, user, paths, 1, fake)
        self.assertTrue(result["passed"])
        joined = "\n".join(observed)
        self.assertIn("--post=", joined); self.assertIn("--post_manifest=", joined)
        self.assertNotIn("--baseline=", joined); self.assertNotIn("--expected=", joined)

    def test_bad_post_manifest_stops_before_consumer_two(self):
        calls = []
        def fake(command, **kwargs):
            calls.append(command)
            probe = self._probe_result(command)
            if probe is not None:
                return probe
            values = dict(arg[2:].split("=", 1) for arg in command if arg.startswith("--") and "=" in arg)
            mode = values["mode"]
            if mode == "producer":
                Path(values["baseline"]).write_bytes(b"baseline")
                Path(values["expected"]).write_text(json.dumps({"schema": "p10-process-1", "baseline_sha256": hashlib.sha256(b"baseline").hexdigest()}), encoding="utf-8")
            elif mode == "consumer1":
                Path(values["post"]).write_bytes(b"post")
                Path(values["post_manifest"]).write_text("[]", encoding="utf-8")
            return subprocess.CompletedProcess(command, 0, f"FC P10 PROCESS {mode.upper()} PASS\n", "")
        evidence = self.root / "evidence"
        with patch.object(runner, "_metadata", return_value={"source_sha256": runner._source_hashes(self.root)}):
            summary = runner.execute(self.godot, evidence, run=fake)
        self.assertFalse(summary["passed"])
        self.assertEqual("post digest or manifest mismatch", summary["results"][1]["reason"])
        self.assertEqual(4, len(calls))

    def test_post_run_gameplay_source_drift_fails_completed_modes(self):
        def fake(command, **kwargs):
            probe = self._probe_result(command)
            if probe is not None:
                return probe
            values = dict(arg[2:].split("=", 1) for arg in command if arg.startswith("--") and "=" in arg)
            mode = values["mode"]
            if mode == "producer":
                Path(values["baseline"]).write_bytes(b"baseline")
                Path(values["expected"]).write_text(json.dumps({"schema": "p10-process-1", "baseline_sha256": hashlib.sha256(b"baseline").hexdigest()}), encoding="utf-8")
            elif mode == "consumer1":
                Path(values["post"]).write_bytes(b"post")
                Path(values["post_manifest"]).write_text(json.dumps({"schema": "p10-process-post-1", "post_sha256": hashlib.sha256(b"post").hexdigest()}), encoding="utf-8")
            return subprocess.CompletedProcess(command, 0, f"FC P10 PROCESS {mode.upper()} PASS\n", "")
        evidence = self.root / "evidence"
        with patch.object(runner, "_metadata", return_value={"source_sha256": {"before": "1"}}):
            summary = runner.execute(self.godot, evidence, run=fake)
        self.assertEqual(3, len(summary["results"]))
        self.assertTrue(summary["source_drift_detected"])
        self.assertFalse(summary["passed"])


if __name__ == "__main__":
    unittest.main()
