"""Regression tests for runtime inventory accounting."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / "tools"))
import build_system_inventory as inventory


def _source(root, relative):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("extends RefCounted\n", encoding="utf-8")


def _classification(*entries):
    return {"files": list(entries)}


def _entry(path, classification="active", **extra):
    return {"path": path, "classification": classification,
            "reason": "test reason", "evidence": "test evidence", **extra}


class RuntimeInventoryCoverageTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)

    def tearDown(self):
        self.tempdir.cleanup()

    def test_new_runtime_file_requires_classification(self):
        _source(self.root, "scripts/world/new_runtime.gd")
        self.assertEqual(
            inventory.coverage({"systems": [], "loops": []}, self.root, ["scripts"],
                               _classification()),
            ["unclassified runtime file: scripts/world/new_runtime.gd"])

    def test_active_runtime_file_requires_inventory_entry(self):
        path = "scripts/world/new_runtime.gd"
        _source(self.root, path)
        self.assertEqual(
            inventory.coverage({"systems": [], "loops": []}, self.root, ["scripts"],
                               _classification(_entry(path))),
            [f"active runtime file not in inventory: {path}"])

    def test_tools_gameplay_file_cannot_be_silently_excluded(self):
        path = "scripts/tools/crafting_station.gd"
        _source(self.root, path)
        # A tools directory name does not exempt runtime code from inventory.
        self.assertEqual(
            inventory.coverage({"systems": [], "loops": []}, self.root, ["scripts"],
                               _classification(_entry(path))),
            [f"active runtime file not in inventory: {path}"])
        errors = inventory.validate_runtime_classification(
            _classification(_entry(path, "tooling")), self.root)
        self.assertTrue(any("tooling_reference" in error for error in errors))

    def test_non_gameplay_exclusion_needs_evidence(self):
        path = "scripts/world/secret_exclusion.gd"
        _source(self.root, path)
        errors = inventory.validate_runtime_classification(
            _classification(_entry(path, "legacy")), self.root)
        self.assertTrue(any("legacy_reference" in error for error in errors))

        bad_validation = "scripts/validation/check.gd"
        _source(self.root, bad_validation)
        errors = inventory.validate_runtime_classification(
            _classification(_entry(bad_validation, "tooling", tooling_reference="test")), self.root)
        self.assertTrue(any("must be 'validation'" in error for error in errors))

    def test_duplicate_classification_path_is_rejected(self):
        path = "scripts/world/runtime.gd"
        _source(self.root, path)
        errors = inventory.validate_runtime_classification(
            _classification(_entry(path), _entry(path)), self.root)
        self.assertTrue(any("duplicate" in error for error in errors))
