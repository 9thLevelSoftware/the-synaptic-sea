import copy
import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.check_structural_rebuild_catalog import (
    MAPPING_SOURCE_HASHES,
    RESOURCE_HASHES,
    _assert_mapping_authority,
    _assert_hashes,
    _validate_contract_and_wrapper,
    canonical_rows,
    validate_catalog,
)

ROOT = Path(__file__).parents[1]


def _p09(materials: set[str]) -> dict:
    return {
        "schema": "crafting_economy_report_v1",
        "ok": True,
        "reachable_ids": sorted(materials | {"welder"}),
        "compatible_tool_actions": [
            {"item_id": "welder", "action_id": "rebuild_structure"},
        ],
    }


def _inputs(expected: dict[str, dict]) -> dict:
    materials = {item for row in expected.values() for item in row["requirements"]["materials"]}
    return {
        "expected_rows": expected,
        "item_ids": materials | {"welding_lance", "welder"},
        "action_ids": {"rebuild_structure"},
        "p09_report": _p09(materials),
    }


class StructuralRebuildCatalogTests(unittest.TestCase):
    def test_all_six_mapping_sources_are_checked_from_real_temp_copies(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative_path in MAPPING_SOURCE_HASHES:
                source, destination = ROOT / relative_path, root / relative_path
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
            _assert_mapping_authority(root)
            for relative_path in MAPPING_SOURCE_HASHES:
                mutated = root / relative_path
                mutated.write_bytes(mutated.read_bytes() + b"\nmutation")
                with self.subTest(path=relative_path):
                    with self.assertRaisesRegex(ValueError, "mapping authority drift"):
                        _assert_mapping_authority(root)
                shutil.copyfile(ROOT / relative_path, mutated)

    def test_current_catalog_has_sixty_exact_rows_with_concrete_welder_proof(self):
        expected = canonical_rows(ROOT)
        catalog = json.loads((ROOT / "data/construction/structural_rebuild_catalog.json").read_text())
        report = validate_catalog(catalog, **_inputs(expected))
        self.assertTrue(report["ok"], report)
        self.assertEqual(60, len(expected))

    def test_policy_mutants_have_their_own_exact_blocker(self):
        expected = canonical_rows(ROOT)
        catalog = json.loads((ROOT / "data/construction/structural_rebuild_catalog.json").read_text())
        cases = (
            ("duplicate", lambda value: value["rows"].append(copy.deepcopy(value["rows"][0])), "coverage"),
            ("missing", lambda value: value["rows"].pop(), "coverage"),
            ("fraction", lambda value: value["rows"][0]["requirements"]["materials"].update({"plating": 1.5}), "materials"),
            ("duration", lambda value: value["rows"][0]["requirements"].update({"duration_seconds": 99}), "tuple_mismatches"),
            ("socket", lambda value: value["rows"][0].update({"socket_mapping": []}), "tuple_mismatches"),
            ("extra_root", lambda value: value.update({"unexpected": True}), "catalog_schema"),
            ("extra_row", lambda value: value["rows"][0].update({"unexpected": True}), "row_schema"),
            ("inactive", lambda value: value["rows"][0].update({"active": False}), "row_schema"),
            ("non_object", lambda value: value["rows"].append("no"), "row_schema"),
            ("boolean_skill", lambda value: value["rows"][0]["requirements"].update({"min_skill": False}), "skill"),
            ("boolean_footprint", lambda value: value["rows"][0].update({"footprint_cells": [True, 1]}), "footprint"),
            ("float_footprint", lambda value: value["rows"][0].update({"footprint_cells": [1.0, 1]}), "footprint"),
            ("short_footprint", lambda value: value["rows"][0].update({"footprint_cells": [1]}), "footprint"),
            ("negative_footprint", lambda value: value["rows"][0].update({"footprint_cells": [-1, 1]}), "footprint"),
            ("string_footprint", lambda value: value["rows"][0].update({"footprint_cells": ["1", 1]}), "footprint"),
        )
        for label, mutate, blocker in cases:
            with self.subTest(label=label):
                mutated = copy.deepcopy(catalog); mutate(mutated)
                report = validate_catalog(mutated, **_inputs(expected))
                self.assertIn(blocker, report["blockers"], report)

    def test_p09_requires_strict_reachable_concrete_welder_pair(self):
        expected = canonical_rows(ROOT)
        catalog = json.loads((ROOT / "data/construction/structural_rebuild_catalog.json").read_text())
        inputs = _inputs(expected)
        inputs["p09_report"] = _p09({"plating", "scrap_metal", "wiring_spool", "circuit_board"})
        inputs["p09_report"]["reachable_ids"].append("welding_lance")
        inputs["p09_report"]["compatible_tool_actions"] = [{"item_id": "welding_lance", "action_id": "rebuild_structure"}]
        report = validate_catalog(catalog, **inputs)
        self.assertIn("p09_tool_action_unverified", report["blockers"])
        inputs["p09_report"] = _p09({"plating", "scrap_metal", "wiring_spool", "circuit_board"})
        inputs["p09_report"]["compatible_tool_actions"].append({"item_id": "welder", "action_id": "rebuild_structure", "extra": True})
        report = validate_catalog(catalog, **inputs)
        self.assertIn("p09_report_unverified", report["blockers"])

    def test_contract_and_wrapper_resource_mutations_are_rejected(self):
        first_contract = next(path for path in RESOURCE_HASHES if path.endswith("floor_1x1_contract.tres"))
        first_wrapper = next(path for path in RESOURCE_HASHES if path.endswith("floor_1x1.tscn"))
        for relative_path, needle, replacement in (
            (first_contract, '"kind": "floor_edge"', '"kind": "drifted_kind"'),
            (first_wrapper, 'Anchor_SOCK_floor_edge_north_01', 'Anchor_Removed'),
        ):
            with self.subTest(path=relative_path), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); destination = root / relative_path
                destination.parent.mkdir(parents=True, exist_ok=True)
                content = (ROOT / relative_path).read_text(encoding="utf-8")
                self.assertIn(needle, content)
                destination.write_text(content.replace(needle, replacement, 1), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "structural resource drift"):
                    _assert_hashes(root, {relative_path: RESOURCE_HASHES[relative_path]}, "structural resource")

    def test_pins_are_line_ending_independent(self):
        relative_path = next(iter(MAPPING_SOURCE_HASHES))
        content = (ROOT / relative_path).read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); destination = root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            for newline in ("\n", "\r\n"):
                destination.write_text(content.replace("\n", newline), encoding="utf-8", newline="")
                _assert_hashes(root, {relative_path: MAPPING_SOURCE_HASHES[relative_path]}, "mapping authority")

    def test_semantic_contract_validation_rejects_repin_attempts(self):
        kit = json.loads((ROOT / "data/kits/ship_structural_v0.json").read_text(encoding="utf-8"))
        module = next(row for row in kit["modules"] if row["module_id"] == "floor_1x1")
        contract_relative = module["godot_contract"].removeprefix("res://")
        wrapper_relative = module["godot_wrapper_scene"].removeprefix("res://")
        original_contract = (ROOT / contract_relative).read_text(encoding="utf-8")
        original_wrapper = (ROOT / wrapper_relative).read_text(encoding="utf-8")
        mutations = (
            ("kind", lambda sockets: sockets.__setitem__(0, {**sockets[0], "kind": "drifted_kind"}), "semantic_drift"),
            ("position", lambda sockets: sockets.__setitem__(0, {**sockets[0], "position_m": [99, 0, 0]}), "semantic_drift"),
            ("compatible", lambda sockets: sockets.__setitem__(0, {**sockets[0], "compatible_kinds": ["drifted"]}), "semantic_drift"),
            ("extra", lambda sockets: sockets.append({"id": "extra", "kind": "floor_edge", "position_m": [0, 0, 0], "compatible_kinds": ["floor_edge"]}), "semantic_drift"),
        )
        for label, mutate, reason in mutations:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); contract_path, wrapper_path = root / contract_relative, root / wrapper_relative
                contract_path.parent.mkdir(parents=True, exist_ok=True); wrapper_path.parent.mkdir(parents=True, exist_ok=True)
                lines = original_contract.splitlines(); index = next(index for index, line in enumerate(lines) if line.startswith("sockets = "))
                sockets = json.loads(lines[index].removeprefix("sockets = ")); mutate(sockets); lines[index] = "sockets = " + json.dumps(sockets, separators=(",", ":"))
                mutated = "\n".join(lines) + "\n"; contract_path.write_text(mutated, encoding="utf-8"); wrapper_path.write_text(original_wrapper, encoding="utf-8")
                refreshed = hashlib.sha256(mutated.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")).hexdigest()
                with patch("tools.check_structural_rebuild_catalog.RESOURCE_HASHES", {contract_relative: refreshed}):
                    _assert_hashes(root, {contract_relative: refreshed}, "structural resource")
                with self.assertRaisesRegex(ValueError, reason): _validate_contract_and_wrapper(root, module)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); contract_path, wrapper_path = root / contract_relative, root / wrapper_relative
            contract_path.parent.mkdir(parents=True, exist_ok=True); wrapper_path.parent.mkdir(parents=True, exist_ok=True)
            contract_path.write_text(original_contract, encoding="utf-8"); wrapper_path.write_text(original_wrapper.replace("Anchor_SOCK_floor_edge_north_01", "Anchor_Removed", 1), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "anchors"): _validate_contract_and_wrapper(root, module)

    def test_semantic_contract_validation_rejects_every_duplicate_protected_field_after_repin(self):
        kit = json.loads((ROOT / "data/kits/ship_structural_v0.json").read_text(encoding="utf-8"))
        module = next(row for row in kit["modules"] if row["module_id"] == "floor_1x1")
        contract_relative = module["godot_contract"].removeprefix("res://")
        wrapper_relative = module["godot_wrapper_scene"].removeprefix("res://")
        original_contract = (ROOT / contract_relative).read_text(encoding="utf-8")
        original_wrapper = (ROOT / wrapper_relative).read_text(encoding="utf-8")
        for field in ("asset_id", "footprint_cells", "wrapper_scene", "sockets"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); contract_path, wrapper_path = root / contract_relative, root / wrapper_relative
                contract_path.parent.mkdir(parents=True, exist_ok=True); wrapper_path.parent.mkdir(parents=True, exist_ok=True)
                line = next(line for line in original_contract.splitlines() if line.startswith(field + " = "))
                mutated = original_contract + line + "\n"; contract_path.write_text(mutated, encoding="utf-8"); wrapper_path.write_text(original_wrapper, encoding="utf-8")
                refreshed = hashlib.sha256(mutated.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")).hexdigest()
                with patch("tools.check_structural_rebuild_catalog.RESOURCE_HASHES", {contract_relative: refreshed}):
                    _assert_hashes(root, {contract_relative: refreshed}, "structural resource")
                with self.assertRaisesRegex(ValueError, f"duplicate_top_level_{field}"):
                    _validate_contract_and_wrapper(root, module)

    def test_non_object_root_has_stable_schema_result(self):
        report = validate_catalog([], expected_rows={}, item_ids=set(), action_ids=set(), p09_report=None)
        self.assertEqual(["catalog_schema"], report["blockers"])


if __name__ == "__main__":
    unittest.main()
