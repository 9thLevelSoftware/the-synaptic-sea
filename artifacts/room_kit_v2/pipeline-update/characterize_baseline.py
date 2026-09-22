"""Reproduce the pre-update regression cohort without reverting checkout files.

Only this disposable process uses the pinned old promoter, exporter and recipe
suite. Their normal temporary-fixture isolation remains in force.
"""
import hashlib
import json
import os
import subprocess
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BASELINE = "51f7cf2e9263abd8f9ddfeb9337d34d108c72d37"
HERE = Path(__file__).parent
os.chdir(ROOT)
sys.path.insert(0, str(ROOT))
run = subprocess.run
provenance = {"baseline": BASELINE, "overrides": {}}


def original(path):
    text = run(["git", "show", BASELINE + ":" + path], cwd=ROOT,
               check=True, capture_output=True, text=True).stdout
    provenance["overrides"][path] = hashlib.sha256(text.encode()).hexdigest()
    return text


exporter = HERE / "baseline-export_structural_glb.py"
exporter.write_text(original("tools/export_structural_glb.py"))
name = "tools.promote_structural_sources"
module = types.ModuleType(name)
module.__file__ = str(ROOT / "tools/promote_structural_sources.py")
module.__package__ = "tools"
sys.modules[name] = module
exec(compile(original("tools/promote_structural_sources.py"), module.__file__, "exec"), module.__dict__)


def baseline_run(command, *args, **kwargs):
    if isinstance(command, (list, tuple)):
        command = [str(exporter) if str(token) == str(ROOT / "tools/export_structural_glb.py") else token
                   for token in command]
    return run(command, *args, **kwargs)


subprocess.run = baseline_run
# The current pressure-door test now expects HOLD; characterize the old version.
test_relative = "tests/test_focused_nine_blender_recipes.py"
test_source = original(test_relative)
test_snapshot = HERE / "baseline_test_focused_nine_blender_recipes.py"
test_snapshot.write_text(test_source)
test_module = types.ModuleType("test_focused_nine_blender_recipes")
test_module.__file__ = str(ROOT / test_relative)
sys.modules[test_module.__name__] = test_module
exec(compile(test_source, str(test_snapshot), "exec"), test_module.__dict__)
(HERE / "baseline-characterization-provenance.json").write_text(json.dumps(provenance, indent=2))
import pytest
raise SystemExit(pytest.main(["-q",
    "tests/test_structural_source_contract.py", "tests/test_validate_structural_sources.py",
    "tests/test_validate_structural_variant_bindings.py", "tests/test_backup_structural_sources.py",
    "tests/test_focused_nine_blender_recipes.py",
]))
