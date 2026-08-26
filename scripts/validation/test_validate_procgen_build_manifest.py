import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

SCRIPT = Path(__file__).with_name("validate_procgen_build_manifest.py")
SPEC = importlib.util.spec_from_file_location("manifest_tool", SCRIPT)
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


class ManifestToolTests(unittest.TestCase):
    SOURCE_COMMIT = "a" * 40

    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.content_root = self.root / "content"
        self.content_root.mkdir()
        self.content_file = self.content_root / "catalog.json"
        self.content_file.write_bytes(b"catalog-v1")
        self.explicit_content_file = self.root / "standalone-content.json"
        self.explicit_content_file.write_bytes(b"standalone-v1")

        self.content_manifest = self.root / "data/procgen/manifests/content_manifest.json"
        self.windows_manifest = self.root / "data/procgen/manifests/build/win64.json"
        self.web_manifest = self.root / "data/procgen/manifests/build/web.json"
        self.windows_artifact = self.root / "addons/derelict/bin/win64/derelict_godot.dll"
        self.web_artifact = self.root / "addons/derelict/bin/web/derelict_wasm_bg.wasm"
        self.windows_artifact.parent.mkdir(parents=True)
        self.web_artifact.parent.mkdir(parents=True)
        self.windows_artifact.write_bytes(b"native-dll")
        self.web_artifact.write_bytes(b"web-wasm")

        self.saved_globals = (
            TOOL.ROOT,
            TOOL.CONTENT_MANIFEST,
            TOOL.BUILD_MANIFESTS,
            TOOL.BUILD_MANIFEST,
            TOOL.ARTIFACT,
            TOOL.CONTENT_ROOTS,
            TOOL.subprocess.run,
        )
        TOOL.ROOT = self.root
        TOOL.CONTENT_MANIFEST = self.content_manifest
        TOOL.BUILD_MANIFESTS = {
            "windows": (
                self.windows_manifest,
                "x86_64-pc-windows-msvc",
                "gdextension",
                self.windows_artifact,
                "addons/derelict/bin/win64/derelict_godot.dll",
            ),
            "web": (
                self.web_manifest,
                "wasm32-unknown-unknown",
                "wasm",
                self.web_artifact,
                "addons/derelict/bin/web/derelict_wasm_bg.wasm",
            ),
        }
        TOOL.BUILD_MANIFEST = self.windows_manifest
        TOOL.ARTIFACT = self.windows_artifact
        TOOL.CONTENT_ROOTS = [self.content_root, self.explicit_content_file]
        TOOL.subprocess.run = lambda *args, **kwargs: subprocess.CompletedProcess(args, 0)

    def tearDown(self):
        (
            TOOL.ROOT,
            TOOL.CONTENT_MANIFEST,
            TOOL.BUILD_MANIFESTS,
            TOOL.BUILD_MANIFEST,
            TOOL.ARTIFACT,
            TOOL.CONTENT_ROOTS,
            TOOL.subprocess.run,
        ) = self.saved_globals
        self.temporary_directory.cleanup()

    def run_tool(self, *arguments):
        previous_argv = sys.argv
        stdout = io.StringIO()
        stderr = io.StringIO()
        try:
            sys.argv = [str(SCRIPT), *arguments]
            with redirect_stdout(stdout), redirect_stderr(stderr):
                result = TOOL.main()
        finally:
            sys.argv = previous_argv
        return result, stdout.getvalue(), stderr.getvalue()

    def test_sorted_nul_framing_changes_when_path_or_bytes_change(self):
        first = TOOL.content_hash([self.content_file])
        self.content_file.write_bytes(b"catalog-v2")
        self.assertNotEqual(first, TOOL.content_hash([self.content_file]))

        self.content_file.write_bytes(b"catalog-v1")
        renamed = self.content_file.with_name("renamed.json")
        self.content_file.rename(renamed)
        self.assertNotEqual(first, TOOL.content_hash([renamed]))

    def test_default_windows_and_explicit_web_generate_exact_pairs(self):
        result, _, error = self.run_tool("--source-commit", self.SOURCE_COMMIT)
        self.assertEqual(result, 0, error)
        self.assertTrue(self.windows_manifest.exists())
        self.assertFalse(self.web_manifest.exists())
        windows = json.loads(self.windows_manifest.read_text(encoding="utf-8"))
        self.assertEqual(windows["target"], "x86_64-pc-windows-msvc")
        self.assertEqual(windows["artifact"]["kind"], "gdextension")
        self.assertEqual(windows["generator_version"], 3)
        self.assertEqual(windows["manifest_schema"], "procgen-build-manifest-4")
        self.assertEqual(windows["export_schemas"]["procgen_request"], "procgen-request-2")
        self.assertEqual(windows["export_schemas"]["procgen_bundle"], "procgen-bundle-5")
        self.assertEqual(windows["export_schemas"]["world_ir"], "world-ir-2")
        self.assertEqual(windows["export_schemas"]["site_ir"], "site-ir-2")
        self.assertEqual(windows["export_schemas"]["gameplay_ir"], "gameplay-ir-3")
        self.assertEqual(windows["export_schemas"]["presentation_ir"], "presentation-ir-2")
        self.assertEqual(
            windows["export_schemas"]["generation_trace"], "generation-trace-4"
        )
        self.assertEqual(
            windows["export_schemas"]["adaptive_proposal"], "adaptive-proposal-2"
        )
        self.assertEqual(
            windows["artifact"]["path"],
            "addons/derelict/bin/win64/derelict_godot.dll",
        )

        content_before = self.content_manifest.read_bytes()
        result, _, error = self.run_tool(
            "--source-commit", self.SOURCE_COMMIT, "--target", "web"
        )
        self.assertEqual(result, 0, error)
        self.assertEqual(content_before, self.content_manifest.read_bytes())
        web = json.loads(self.web_manifest.read_text(encoding="utf-8"))
        self.assertEqual(web["target"], "wasm32-unknown-unknown")
        self.assertEqual(web["artifact"]["kind"], "wasm")
        self.assertEqual(web["generator_version"], 3)
        self.assertEqual(web["manifest_schema"], "procgen-build-manifest-4")
        self.assertEqual(web["export_schemas"]["procgen_request"], "procgen-request-2")
        self.assertEqual(web["export_schemas"]["procgen_bundle"], "procgen-bundle-5")
        self.assertEqual(web["export_schemas"]["site_ir"], "site-ir-2")
        self.assertEqual(web["export_schemas"]["gameplay_ir"], "gameplay-ir-3")
        self.assertEqual(web["export_schemas"]["presentation_ir"], "presentation-ir-2")
        self.assertEqual(
            web["artifact"]["path"],
            "addons/derelict/bin/web/derelict_wasm_bg.wasm",
        )

    def test_content_manifest_includes_explicit_files_alongside_directories(self):
        paths = TOOL.files()
        self.assertEqual(paths, sorted(paths, key=TOOL.rel))
        self.assertIn(self.content_file, paths)
        self.assertIn(self.explicit_content_file, paths)

        first = TOOL.content_hash(paths)
        self.explicit_content_file.write_bytes(b"standalone-v2")
        self.assertNotEqual(first, TOOL.content_hash(TOOL.files()))

    def test_web_check_detects_artifact_tamper_without_writing(self):
        result, _, error = self.run_tool(
            "--source-commit", self.SOURCE_COMMIT, "--target", "web"
        )
        self.assertEqual(result, 0, error)
        manifest_before = self.web_manifest.read_bytes()
        content_before = self.content_manifest.read_bytes()

        self.web_artifact.write_bytes(b"tampered-wasm")
        result, _, error = self.run_tool(
            "--check", "--source-commit", self.SOURCE_COMMIT, "--target", "web"
        )
        self.assertEqual(result, 1)
        self.assertIn("web.json is stale or missing", error)
        self.assertEqual(manifest_before, self.web_manifest.read_bytes())
        self.assertEqual(content_before, self.content_manifest.read_bytes())

    def test_check_rejects_stale_content_without_writing(self):
        result, _, error = self.run_tool("--source-commit", self.SOURCE_COMMIT)
        self.assertEqual(result, 0, error)
        content_before = self.content_manifest.read_bytes()
        build_before = self.windows_manifest.read_bytes()
        self.content_file.write_bytes(b"catalog-v2")

        result, _, error = self.run_tool(
            "--check", "--source-commit", self.SOURCE_COMMIT
        )
        self.assertEqual(result, 1)
        self.assertIn("content_manifest.json is stale or missing", error)
        self.assertEqual(content_before, self.content_manifest.read_bytes())
        self.assertEqual(build_before, self.windows_manifest.read_bytes())

    def test_missing_selected_artifact_fails_without_writing(self):
        self.web_artifact.unlink()
        result, _, error = self.run_tool(
            "--source-commit", self.SOURCE_COMMIT, "--target", "web"
        )
        self.assertEqual(result, 1)
        self.assertIn("missing artifact", error)
        self.assertFalse(self.content_manifest.exists())
        self.assertFalse(self.web_manifest.exists())

    def test_source_commit_must_be_lowercase_and_present(self):
        result, _, error = self.run_tool("--check", "--source-commit", "Z" * 40)
        self.assertEqual(result, 1)
        self.assertIn("lowercase hexadecimal", error)

        TOOL.subprocess.run = lambda *args, **kwargs: subprocess.CompletedProcess(args, 1)
        result, _, error = self.run_tool(
            "--check", "--source-commit", "0" * 40
        )
        self.assertEqual(result, 1)
        self.assertIn("source commit is not present", error)

    def test_every_gate3_schema_substitution_is_rejected(self):
        result, _, error = self.run_tool("--source-commit", self.SOURCE_COMMIT)
        self.assertEqual(result, 0, error)
        original = self.windows_manifest.read_text(encoding="utf-8")
        substitutions = {
            "procgen-build-manifest-4": "procgen-build-manifest-3",
            "procgen-bundle-5": "procgen-bundle-4",
            "gameplay-ir-3": "gameplay-ir-2",
            "generation-trace-4": "generation-trace-3",
            "adaptive-proposal-2": "adaptive-proposal-1",
        }
        for current, legacy in substitutions.items():
            self.windows_manifest.write_text(original.replace(current, legacy), encoding="utf-8")
            result, _, error = self.run_tool("--check", "--source-commit", self.SOURCE_COMMIT)
            self.assertEqual(result, 1, f"accepted Gate 3 substitution {current}")
            self.assertIn("win64.json is stale or missing", error)
        self.windows_manifest.write_text(original, encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
