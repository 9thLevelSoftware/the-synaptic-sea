import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path

SCRIPT = Path(__file__).with_name("validate_procgen_build_manifest.py")
SPEC = importlib.util.spec_from_file_location("manifest_tool", SCRIPT)
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)

class ManifestToolTests(unittest.TestCase):
    def test_sorted_nul_framing_changes_when_path_or_bytes_change(self):
        with tempfile.TemporaryDirectory() as root:
            base = Path(root); a = base / "a.txt"; b = base / "b.txt"
            a.write_bytes(b"a"); b.write_bytes(b"b")
            old_root = TOOL.ROOT; TOOL.ROOT = base
            try:
                first = TOOL.content_hash([a, b]); b.write_bytes(b"changed")
                self.assertNotEqual(first, TOOL.content_hash([a, b]))
            finally: TOOL.ROOT = old_root

    def test_check_rejects_stale_content_without_writing(self):
        with tempfile.TemporaryDirectory() as root:
            base = Path(root); (base / "data/procgen/manifests/build").mkdir(parents=True)
            (base / "data/procgen/manifests/content_manifest.json").write_text("stale", encoding="utf-8")
            (base / "addons/derelict/bin/win64").mkdir(parents=True)
            artifact = base / "addons/derelict/bin/win64/derelict_godot.dll"; artifact.write_bytes(b"dll")
            old = (TOOL.ROOT, TOOL.CONTENT_MANIFEST, TOOL.BUILD_MANIFEST, TOOL.ARTIFACT, TOOL.CONTENT_ROOTS)
            TOOL.ROOT = base; TOOL.CONTENT_MANIFEST = base / "data/procgen/manifests/content_manifest.json"; TOOL.BUILD_MANIFEST = base / "data/procgen/manifests/build/win64.json"; TOOL.ARTIFACT = artifact; TOOL.CONTENT_ROOTS = []
            try:
                old_run = TOOL.subprocess.run; TOOL.subprocess.run = lambda *args, **kwargs: type("R", (), {"returncode": 0})()
                old_argv = sys.argv; sys.argv = [str(SCRIPT), "--check"]
                try:
                    with redirect_stderr(io.StringIO()): self.assertEqual(TOOL.main(), 1)
                finally: sys.argv = old_argv; TOOL.subprocess.run = old_run
            finally:
                TOOL.ROOT, TOOL.CONTENT_MANIFEST, TOOL.BUILD_MANIFEST, TOOL.ARTIFACT, TOOL.CONTENT_ROOTS = old

if __name__ == "__main__": unittest.main()
