from __future__ import annotations

import hashlib
import json
import os
import stat
import struct
import subprocess
import sys
from pathlib import Path

import pytest

from tools import biomass_composite_review as review

ROOT = Path(__file__).resolve().parents[1]


def _png_bytes(width: int = 96, height: int = 64) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        import binascii

        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)
        )

    rows = b"".join(b"\x00" + b"\x18\x28\x48\xff" * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", __import__("zlib").compress(rows))
        + chunk(b"IEND", b"")
    )


def _case_payload(case: dict, output: Path) -> dict:
    return {
        "case_id": case["case_id"],
        "recipe_id": case["recipe_id"],
        "seed": case["seed"],
        "lighting": case["lighting"],
        "visual_stage": case["visual_stage"],
        "archetype_id": case["archetype_id"],
        "pool_membership": True,
        "main_scene_path": "res://scenes/main.tscn",
        "playable_ready_seen": True,
        "playable_started": True,
        "loader_loaded": True,
        "camera_script_path": "res://scripts/camera/iso_camera_rig.gd",
        "camera_current": True,
        "standalone_nodes_created": False,
        "recipe_sha256": "a" * 64,
        "runtime": {
            "nodes": 58,
            "triangles": 17000,
            "aabb_extents_m": [2.0, 2.0, 2.0],
            "collision_count": 9,
            "enabled_collision_count": 5,
            "disabled_connector_collision_count": 4,
            "direct_body_collision_children": 9,
            "body_collision_layer": 1,
            "body_collision_mask": 1,
            "ray_hit": True,
            "ray_miss_after_free": True,
            "gait_frames": 120,
            "gait_delta_seconds": 1.0 / 60.0,
            "wrapper_paths_empty": True,
            "primitive_mesh_parts": True,
            "lighting": {
                "applied": True,
                "key_light_applied": True,
                "is_away": True,
                "ambient_color": [0.12, 0.20, 0.40],
                "ambient_energy": 0.72,
                "key_light_color": [0.72, 0.84, 1.0],
                "key_light_energy": 1.5,
                "fog_enabled": True,
                "fog_density": 0.032,
                "emergency_accent_present": False,
                "emergency_accent_applied": False,
                "emergency_accent_energy": None,
            },
            "paired_visibility": {
                "rgb_delta": 1.0,
                "changed_pixels": 128,
                "changed_bbox_width": 16,
                "changed_bbox_height": 16,
            },
        },
        "output": {
            "path": output.relative_to(ROOT).as_posix() if output.is_relative_to(ROOT) else output.name,
            "sha256": hashlib.sha256(_png_bytes()).hexdigest(),
            "byte_size": len(_png_bytes()),
            "width": 96,
            "height": 64,
        },
    }


def test_matrix_is_exact_stage_qualified_sorted_and_covers_all_pools() -> None:
    cases = review.build_case_matrix("placeholder")

    assert len(cases) == 30
    assert cases == sorted(cases, key=lambda item: item["case_id"])
    assert len({item["case_id"] for item in cases}) == 30
    assert all(item["case_id"].startswith("placeholder/") for item in cases)
    assert {(item["recipe_id"], item["seed"]) for item in cases} == {
        (recipe, seed) for recipe in review.RECIPE_IDS for seed in review.SEEDS
    }
    assert {item["lighting"] for item in cases} == set(review.LIGHTING_MODES)
    assert {item["archetype_id"] for item in cases} == set(review.ARCHETYPE_IDS)
    assert review.validate_case_matrix(cases, "placeholder") == []


def test_mapping_is_closed_and_rejects_altered_or_incomplete_values() -> None:
    assert review.validate_archetype_mapping(review.RECIPE_SEED_ARCHETYPES) == []

    altered = dict(review.RECIPE_SEED_ARCHETYPES)
    altered[("biped_puppet_v1", 42)] = "mimic"
    assert any("mapping" in error for error in review.validate_archetype_mapping(altered))

    incomplete = dict(review.RECIPE_SEED_ARCHETYPES)
    incomplete.pop(("tendril_knot_v1", 777))
    assert any("mapping" in error for error in review.validate_archetype_mapping(incomplete))


def test_command_requires_archetype_and_uses_exact_renderer_recipe() -> None:
    case = review.build_case_matrix("placeholder")[0]
    command = review.build_godot_command(
        Path("/tmp/project"), Path("/tmp/capture.png"), Path("/opt/homebrew/bin/godot"), case
    )

    separator = command.index("--")
    assert command[:separator] == [
        "/opt/homebrew/bin/godot",
        "--headless",
        "--path",
        "/tmp/project",
        "--script",
        "res://scripts/validation/biomass_visual_review.gd",
        "--",
    ][:separator]
    user_args = command[separator + 1 :]
    assert user_args == [
        "--recipe-id",
        case["recipe_id"],
        "--seed",
        str(case["seed"]),
        "--archetype-id",
        case["archetype_id"],
        "--lighting",
        case["lighting"],
        "--visual-stage",
        "placeholder",
        "--output",
        "/tmp/capture.png",
    ]


def test_capture_retries_without_dummy_headless_renderer(monkeypatch: pytest.MonkeyPatch) -> None:
    command = ["godot", "--headless", "--script", review.CAPTURE_SCRIPT]
    calls: list[list[str]] = []

    def fake_run(argv: list[str], **_: object) -> subprocess.CompletedProcess[str]:
        calls.append(argv)
        if "--headless" in argv:
            return subprocess.CompletedProcess(
                argv,
                1,
                'ERROR: Parameter "t" is null.\nBIOMASS COMPOSITE CASE FAIL: production viewport did not produce a visible image',
                "",
            )
        return subprocess.CompletedProcess(argv, 0, "BIOMASS COMPOSITE CASE PASS {}", "")

    monkeypatch.setattr(subprocess, "run", fake_run)

    result, executed = review.run_capture_command(command)

    assert result.returncode == 0
    assert executed == ["godot", "--script", review.CAPTURE_SCRIPT]
    assert calls == [command, executed]


def test_case_output_parser_rejects_diagnostics_and_wrong_identity() -> None:
    case = review.build_case_matrix("placeholder")[0]
    output = Path("/tmp/capture.png")
    payload = _case_payload(case, output)
    marker = review.case_marker(payload)

    assert review.parse_case_marker(marker, case)["case_id"] == case["case_id"]
    with pytest.raises(review.ReviewError, match="diagnostic"):
        review.parse_case_output(marker + "\nWARNING: forged", "", case)
    with pytest.raises(review.ReviewError, match="case_id"):
        forged = dict(payload)
        forged["case_id"] = "placeholder/forged"
        review.parse_case_marker(review.case_marker(forged), case)
    with pytest.raises(review.ReviewError, match="pass marker"):
        review.parse_case_output("", "", case)


def test_manifest_is_closed_and_canonical() -> None:
    cases = review.build_case_matrix("placeholder")
    document = review.build_manifest(
        project_root=ROOT,
        visual_stage="placeholder",
        cases=[_case_payload(case, ROOT / "capture.png") for case in cases],
        protected_before={"data/combat/biomass_part_catalog.json": "a" * 64},
        protected_after={"data/combat/biomass_part_catalog.json": "a" * 64},
        commit="b" * 40,
        godot_version="4.7.1",
    )

    assert document["document_kind"] == "biomass_composite_review_v1"
    assert set(document) == review.TOP_LEVEL_FIELDS
    assert len(document["recipes"]) == 5
    assert len(document["cases"]) == 30
    assert review.canonical_json_bytes(document).endswith(b"\n")
    assert b" " not in review.canonical_json_bytes(document)

    forged = json.loads(json.dumps(document))
    forged["unexpected"] = True
    assert any("unknown field" in error for error in review.validate_manifest(forged, ROOT))


def test_plan_does_not_spawn_or_write(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    def forbidden(*args, **kwargs):
        raise AssertionError("plan spawned a subprocess")

    monkeypatch.setattr(subprocess, "run", forbidden)
    plan = review.plan_document(ROOT, "placeholder", "4.7.1", "a" * 40)
    assert plan["visual_stage"] == "placeholder"
    assert len(plan["cases"]) == 30
    assert not list(tmp_path.iterdir())


def test_png_and_inventory_validation_rejects_extra_stale_escape_and_symlink(tmp_path: Path) -> None:
    root = tmp_path / "artifacts/validation-previews/biomass-assembly-placeholder"
    root.mkdir(parents=True)
    png = root / "placeholder__biped_puppet_v1__seed-42__normal.png"
    png.write_bytes(_png_bytes())
    assert review.inspect_png(png) == {"width": 96, "height": 64, "byte_size": len(_png_bytes())}

    with pytest.raises(review.ReviewError, match="PNG"):
        (root / "bad.png").write_bytes(b"not png")
        review.inspect_png(root / "bad.png")

    outside = tmp_path / "outside.png"
    outside.write_bytes(_png_bytes())
    link = root / "link.png"
    link.symlink_to(outside)
    with pytest.raises(review.ReviewError, match="symlink"):
        review.inspect_png(link)


def test_lighting_profile_is_explicitly_validation_owned() -> None:
    for profile in review.LIGHTING_PROFILES.values():
        assert profile["away_fog_density_mult"] == 1.6
        assert profile["fog_density"] == 0.032
        assert profile["is_away"] is True
    assert review.LIGHTING_PROFILES["normal"]["emergency_accent"] is None
    assert review.LIGHTING_PROFILES["emergency"]["emergency_accent"] == "#ff6a3d"
    assert review.LIGHTING_PROFILES["dark"]["emergency_accent"] is None


def test_runtime_accepts_measured_finite_aabb_within_review_bounds(tmp_path: Path) -> None:
    case = next(case for case in review.build_case_matrix("placeholder") if case["lighting"] == "normal")
    payload = _case_payload(case, tmp_path / "capture.png")
    runtime = payload["runtime"]
    runtime["attachments"] = 4
    runtime["occurrences"] = 9
    runtime["max_nodes"] = 160
    runtime["max_triangles"] = 24000
    runtime["aabb_extents_m"] = [1.25, 0.8, 3.0]
    errors: list[str] = []

    review._validate_runtime(runtime, case, errors)

    assert errors == []


def test_verify_recomputes_png_hash_and_rejects_hash_drift(tmp_path: Path) -> None:
    report = tmp_path / "review.json"
    root = tmp_path / "artifacts/validation-previews/biomass-assembly-placeholder"
    root.mkdir(parents=True)
    png = root / "placeholder__biped_puppet_v1__seed-42__normal.png"
    png.write_bytes(_png_bytes())

    with pytest.raises(review.ReviewError, match="JSON|manifest|case"):
        review.verify_report(tmp_path, report)

    assert stat.S_ISREG(png.stat().st_mode)
