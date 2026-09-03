from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

import pytest

from tools.biomass_catalog_validate import (
    MAX_ATTACHMENTS,
    MAX_DEPTH,
    MAX_NODES,
    MAX_TRIANGLES,
    canonical_recipe_bytes,
    validate_part_catalog,
    validate_recipe,
    validate_recipe_catalog,
)

ROOT = Path(__file__).parents[1]
PARTS_PATH = ROOT / "data/combat/biomass_part_catalog.json"
RECIPES_PATH = ROOT / "data/combat/biomass_recipe_catalog.json"
SCRIPT = ROOT / "tools/biomass_catalog_validate.py"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def parts():
    return load(PARTS_PATH)


def recipes():
    return load(RECIPES_PATH)


def part_map():
    return parts()["parts"]


def recipe(name: str = "biped_puppet_v1"):
    return recipes()["recipes"][name]


def assert_has(errors: list[str], text: str) -> None:
    assert any(text in error for error in errors), errors


def test_valid_catalog_documents() -> None:
    assert validate_part_catalog(parts(), ROOT) == []
    assert validate_recipe_catalog(recipes(), part_map()) == []
    for item in recipes()["recipes"].values():
        assert validate_recipe(item, part_map()) == []


def test_part_catalog_has_exact_ids_values_and_role_counts() -> None:
    document = parts()
    assert set(document) == {"schema_version", "document_kind", "limits", "parts"}
    assert document["schema_version"] == "1.0.0"
    assert document["document_kind"] == "biomass_part_catalog"
    assert document["limits"] == {
        "max_attachments": MAX_ATTACHMENTS,
        "max_depth": MAX_DEPTH,
        "max_triangles": MAX_TRIANGLES,
        "max_nodes": MAX_NODES,
    }
    expected = {
        "biomass_human_arm_v1": ("biomass_limb", ["human"], ["locomotor", "manipulator", "puller"], 2500),
        "biomass_insect_leg_v1": ("biomass_limb", ["insectoid"], ["locomotor"], 2500),
        "biomass_cephalopod_tentacle_v1": ("biomass_limb", ["cephalopodic"], ["locomotor", "puller", "slither"], 2500),
        "biomass_animal_skull_v1": ("biomass_head", ["animal"], ["core", "detail"], 3500),
        "biomass_humanoid_torso_v1": ("biomass_core", ["human"], ["core"], 5000),
        "biomass_gunk_connector_v1": ("biomass_connector", ["biomass"], ["connector"], 500),
        "biomass_claw_v1": ("biomass_appendage", ["alien"], ["detail", "manipulator"], 1500),
        "biomass_maw_v1": ("biomass_appendage", ["alien"], ["detail"], 1500),
    }
    assert set(document["parts"]) == set(expected)
    for part_id, (category, species, roles, budget) in expected.items():
        part = document["parts"][part_id]
        assert part["category"] == category
        assert part["species_tags"] == species
        assert part["assembly_roles"] == roles
        assert part["triangle_budget"] == budget
        assert set(part) == {
            "category", "species_tags", "assembly_roles", "wrapper_scene_path",
            "triangle_budget", "sockets", "collision_shapes", "fallback",
        }
    counts = {}
    for part in document["parts"].values():
        for role in part["assembly_roles"]:
            counts[role] = counts.get(role, 0) + 1
    assert {key: counts[key] for key in ("core", "locomotor", "puller", "slither", "detail", "connector")} == {
        "core": 2, "locomotor": 3, "puller": 2, "slither": 1, "detail": 3, "connector": 1,
    }


def test_recipe_catalog_has_exact_recipes_pools_and_connector_ids() -> None:
    document = recipes()
    assert set(document) == {"schema_version", "document_kind", "recipes", "archetype_pools"}
    assert document["schema_version"] == "1.0.0"
    assert document["document_kind"] == "biomass_recipe_catalog"
    assert set(document["recipes"]) == {
        "biped_puppet_v1", "four_legged_scrambler_v1", "tripod_hound_v1",
        "intestinal_dragger_v1", "tendril_knot_v1",
    }
    assert document["archetype_pools"] == {
        "biomatter_swarm": ["tripod_hound_v1", "intestinal_dragger_v1"],
        "stalker": ["biped_puppet_v1", "four_legged_scrambler_v1"],
        "hull_tendril": ["tendril_knot_v1", "intestinal_dragger_v1"],
        "puppet_corpse": ["biped_puppet_v1", "tripod_hound_v1"],
        "mimic": ["four_legged_scrambler_v1", "tripod_hound_v1"],
        "drone_swarm": ["tendril_knot_v1", "tripod_hound_v1"],
    }
    for item in document["recipes"].values():
        assert set(item) == {"recipe_id", "locomotion_hint", "core", "attachments"}
        assert all(edge["connector_part_id"] == "biomass_gunk_connector_v1" for edge in item["attachments"])


def test_unknown_and_missing_part_fields_are_rejected() -> None:
    document = parts()
    document["unexpected"] = True
    document["parts"]["biomass_claw_v1"]["unexpected"] = True
    errors = validate_part_catalog(document, ROOT)
    assert_has(errors, "unknown field")
    missing = parts()
    del missing["parts"]["biomass_claw_v1"]["fallback"]
    assert_has(validate_part_catalog(missing, ROOT), "missing field")


def test_unknown_and_missing_recipe_fields_are_rejected() -> None:
    document = recipes()
    document["unexpected"] = True
    document["recipes"]["biped_puppet_v1"]["unexpected"] = True
    errors = validate_recipe_catalog(document, part_map())
    assert_has(errors, "unknown field")
    missing = recipes()
    del missing["recipes"]["biped_puppet_v1"]["attachments"]
    assert_has(validate_recipe_catalog(missing, part_map()), "missing field")


def test_duplicate_json_keys_are_rejected_by_cli(tmp_path: Path) -> None:
    part_path = tmp_path / "parts.json"
    recipe_path = tmp_path / "recipes.json"
    part_path.write_text('{"schema_version":"1.0.0","schema_version":"1.0.0"}', encoding="utf-8")
    recipe_path.write_text(json.dumps(recipes()), encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--project-root", str(ROOT), "--parts", str(part_path), "--recipes", str(recipe_path)],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode != 0
    assert "duplicate JSON object key" in result.stdout


def test_non_finite_numbers_are_rejected() -> None:
    document = parts()
    document["parts"]["biomass_claw_v1"]["fallback"]["dimensions_m"][0] = float("nan")
    errors = validate_part_catalog(document, ROOT)
    assert_has(errors, "non-finite")


def test_wrapper_path_rules_allow_empty_and_require_existing_res_path() -> None:
    root = parts()
    assert validate_part_catalog(root, ROOT) == []
    for value, expected in (("/tmp/wrapper.tscn", "absolute"), ("foo/wrapper.tscn", "res://"), ("res://missing.tscn", "does not exist")):
        document = parts()
        document["parts"]["biomass_claw_v1"]["wrapper_scene_path"] = value
        assert_has(validate_part_catalog(document, ROOT), expected)


def test_socket_shape_and_fallback_contract_is_strict() -> None:
    document = parts()
    document["parts"]["biomass_claw_v1"]["sockets"][0]["name"] = "socket_bad_0"
    assert_has(validate_part_catalog(document, ROOT), "socket name")
    document = parts()
    document["parts"]["biomass_claw_v1"]["collision_shapes"][0]["shape"] = "cylinder"
    assert_has(validate_part_catalog(document, ROOT), "unsupported collision shape")
    document = parts()
    document["parts"]["biomass_claw_v1"]["fallback"]["albedo"] = "red"
    assert_has(validate_part_catalog(document, ROOT), "albedo")
    document = parts()
    document["parts"]["biomass_animal_skull_v1"]["sockets"][1]["position_m"][0] = 99
    assert_has(validate_part_catalog(document, ROOT), "outside fallback bounds")


def test_duplicate_roles_and_sockets_are_rejected() -> None:
    document = parts()
    document["parts"]["biomass_claw_v1"]["assembly_roles"].append("detail")
    document["parts"]["biomass_claw_v1"]["sockets"].append(copy.deepcopy(document["parts"]["biomass_claw_v1"]["sockets"][0]))
    errors = validate_part_catalog(document, ROOT)
    assert_has(errors, "duplicate assembly role")
    assert_has(errors, "duplicate socket name")


def test_root_and_non_root_socket_acceptance_rules_are_enforced() -> None:
    document = parts()
    document["parts"]["biomass_claw_v1"]["sockets"][0]["accepts_categories"] = ["biomass_limb"]
    assert_has(validate_part_catalog(document, ROOT), "root socket must have empty")
    document = parts()
    document["parts"]["biomass_human_arm_v1"]["sockets"][1]["accepts_categories"] = []
    assert_has(validate_part_catalog(document, ROOT), "non-root socket must accept")


def test_recipe_rejects_unknown_ids_and_incompatible_categories() -> None:
    document = recipe()
    document["attachments"][0]["part_id"] = "unknown_part"
    assert_has(validate_recipe(document, part_map()), "unknown part_id")
    document = recipe()
    document["attachments"][0]["part_id"] = "biomass_animal_skull_v1"
    assert_has(validate_recipe(document, part_map()), "not accepted")


def test_recipe_rejects_missing_child_root_and_bad_connector() -> None:
    catalog = part_map()
    catalog = copy.deepcopy(catalog)
    del catalog["biomass_claw_v1"]["sockets"][0]
    document = recipe()
    document["attachments"][-1]["part_id"] = "biomass_claw_v1"
    assert_has(validate_recipe(document, catalog), "missing root socket")
    document = recipe()
    document["attachments"][0]["connector_part_id"] = "biomass_claw_v1"
    assert_has(validate_recipe(document, part_map()), "connector")


def test_recipe_rejects_duplicate_instances_socket_occupancy_and_forward_refs() -> None:
    document = recipe()
    document["attachments"][1]["instance_id"] = document["attachments"][0]["instance_id"]
    assert_has(validate_recipe(document, part_map()), "duplicate instance_id")
    document = recipe()
    document["attachments"][1]["parent_socket"] = document["attachments"][0]["parent_socket"]
    assert_has(validate_recipe(document, part_map()), "socket occupancy")
    document = recipe()
    document["attachments"][0]["parent_instance_id"] = "later"
    assert_has(validate_recipe(document, part_map()), "parent-before-child")


def test_recipe_rejects_cycles_depth_and_attachment_limits() -> None:
    document = recipe()
    document["attachments"][0]["parent_instance_id"] = document["attachments"][0]["instance_id"]
    assert_has(validate_recipe(document, part_map()), "cycle")
    document = recipe()
    document["attachments"] = document["attachments"] * 3
    assert_has(validate_recipe(document, part_map()), "max attachments")
    document = recipe()
    parent = "core"
    edges = []
    for index in range(MAX_DEPTH + 1):
        edges.append({
            "instance_id": f"chain_{index}", "part_id": "biomass_human_arm_v1",
            "parent_instance_id": parent, "parent_socket": "distal_0" if index else "appendage_0",
            "child_socket": "root_0", "connector_part_id": "biomass_gunk_connector_v1",
        })
        parent = f"chain_{index}"
    document["attachments"] = edges
    assert_has(validate_recipe(document, part_map()), "max depth")


def test_recipe_rejects_triangle_and_conservative_node_limits() -> None:
    catalog = copy.deepcopy(part_map())
    catalog["biomass_humanoid_torso_v1"]["triangle_budget"] = MAX_TRIANGLES
    assert_has(validate_recipe(recipe(), catalog), "triangle limit")
    catalog = copy.deepcopy(part_map())
    catalog["biomass_humanoid_torso_v1"]["sockets"] *= MAX_NODES
    assert_has(validate_recipe(recipe(), catalog), "node limit")


def test_unsupported_locomotion_and_required_roles_are_rejected() -> None:
    document = recipe()
    document["locomotion_hint"] = "fly"
    assert_has(validate_recipe(document, part_map()), "unsupported locomotion")
    document = recipe()
    document["locomotion_hint"] = "quadruped"
    assert_has(validate_recipe(document, part_map()), "exactly 4 locomotor")
    document = recipe()
    document["locomotion_hint"] = "drag"
    for edge in document["attachments"]:
        edge["part_id"] = "biomass_claw_v1"
    assert_has(validate_recipe(document, part_map()), "puller")
    document = recipe("tendril_knot_v1")
    for edge in document["attachments"]:
        edge["part_id"] = "biomass_human_arm_v1"
    assert_has(validate_recipe(document, part_map()), "slither")


def test_recipe_catalog_rejects_unknown_recipe_pool_and_duplicate_ids() -> None:
    document = recipes()
    document["recipes"]["unknown"] = copy.deepcopy(document["recipes"]["biped_puppet_v1"])
    document["recipes"]["unknown"]["recipe_id"] = "biped_puppet_v1"
    document["archetype_pools"]["unknown"] = ["unknown_recipe"]
    errors = validate_recipe_catalog(document, part_map())
    assert_has(errors, "unknown recipe")
    assert_has(errors, "unknown pool")
    assert_has(errors, "duplicate recipe_id")


def test_canonical_recipe_bytes_are_deterministic_and_newline_terminated() -> None:
    item = recipe()
    reordered = {key: item[key] for key in reversed(list(item))}
    assert canonical_recipe_bytes(item) == canonical_recipe_bytes(reordered)
    assert canonical_recipe_bytes(item).endswith(b"\n")
    assert b" " not in canonical_recipe_bytes(item)
    with pytest.raises(ValueError):
        canonical_recipe_bytes({"bad": float("nan")})


def test_cli_marker_and_repeat_output_are_deterministic(tmp_path: Path) -> None:
    outputs = []
    for name in ("a.txt", "b.txt"):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--project-root", str(ROOT), "--parts", str(PARTS_PATH), "--recipes", str(RECIPES_PATH)],
            capture_output=True, text=True, check=False,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert "BIOMASS CATALOG VALIDATION PASS parts=8 recipes=5 archetypes=6" in result.stdout
        path = tmp_path / name
        path.write_text(result.stdout, encoding="utf-8")
        outputs.append(path.read_bytes())
    assert outputs[0] == outputs[1]


def test_cli_rejects_nonfinite_and_duplicate_json(tmp_path: Path) -> None:
    bad_parts = tmp_path / "bad_parts.json"
    bad_parts.write_text(json.dumps(parts()).replace("2500", "NaN", 1), encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--project-root", str(ROOT), "--parts", str(bad_parts), "--recipes", str(RECIPES_PATH)],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode != 0
    assert "non-finite" in result.stdout
