import copy
import json
import tempfile
import unittest
from pathlib import Path

from tools.check_runtime_physical_volume_catalog import AUTHORED_PROFILES, CATALOG_PATH, check, validate_catalog

ROOT = Path(__file__).parents[1]


class RuntimePhysicalVolumeCatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = json.loads((ROOT / CATALOG_PATH).read_text(encoding="utf-8"))

    def test_current_catalog_is_the_complete_exact_adr_authority(self) -> None:
        report = validate_catalog(self.catalog)
        self.assertTrue(report["ok"], report)
        self.assertEqual(14, len(AUTHORED_PROFILES))

    def test_schema_and_authority_mutants_fail_closed(self) -> None:
        cases = (
            ("missing_root", lambda value: value.pop("schema"), "catalog_schema"),
            ("missing_profile_field", lambda value: value["profiles"][0].pop("mount_kind"), "profile_schema"),
            ("duplicate_profile", lambda value: value["profiles"].append(copy.deepcopy(value["profiles"][0])), "duplicate_profile_id"),
            ("missing_profile", lambda value: value["profiles"].pop(), "coverage"),
            ("wrong_size", lambda value: value["profiles"][0].update({"dimensions": [9.0, 9.0, 9.0]}), "authored_values"),
            ("wrong_yaw", lambda value: value["profiles"][0].update({"local_yaw_degrees": 90.0}), "authored_values"),
            ("wrong_mount", lambda value: value["profiles"][0].update({"mount_kind": "deck"}), "authored_values"),
            ("wrong_layer", lambda value: value["profiles"][0].update({"collision_layer": 1}), "collision_layer"),
            ("wrong_mask", lambda value: value["profiles"][0].update({"collision_mask": 2}), "collision_mask"),
            ("wrong_purpose", lambda value: value["profiles"][0].update({"blocking_purposes": ["cart_movement"]}), "blocking_purposes"),
            ("nan", lambda value: value["profiles"][0].update({"local_position": [float("nan"), 0.0, 0.0]}), "transform"),
        )
        for label, mutate, blocker in cases:
            with self.subTest(label=label):
                mutated = copy.deepcopy(self.catalog)
                mutate(mutated)
                self.assertIn(blocker, validate_catalog(mutated)["blockers"])

    def test_missing_and_nonfinite_sources_are_not_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertFalse(check(root)["ok"])
            destination = root / CATALOG_PATH
            destination.parent.mkdir(parents=True)
            destination.write_text('{"schema":"runtime_physical_volume_profiles_v1","profiles":[NaN]}', encoding="utf-8")
            report = check(root)
            self.assertFalse(report["ok"], report)
            self.assertEqual(["source_invalid"], report["blockers"])

    def test_godot_json_numeric_normalization_keeps_exact_layer_and_mask(self) -> None:
        normalized = copy.deepcopy(self.catalog)
        normalized["profiles"][0]["collision_layer"] = 2.0
        normalized["profiles"][0]["collision_mask"] = 0.0
        self.assertTrue(validate_catalog(normalized)["ok"])
        normalized["profiles"][0]["collision_layer"] = True
        self.assertIn("collision_layer", validate_catalog(normalized)["blockers"])


if __name__ == "__main__":
    unittest.main()
