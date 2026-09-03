from __future__ import annotations

import json
import shutil
import struct
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

import pytest

from tools import focused_nine_staged_structural as validator

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ASSET_ID = "pressure_door_1x1"
STAGED_PACKAGE = Path("assets/_staging/focused_nine/structural") / ASSET_ID
CANONICAL_IMPORT = Path("assets/imported/structural/ship_structural_v0") / ASSET_ID
CANONICAL_WRAPPER = Path("scenes/wrappers/structural/ship_structural_v0")
CONTRACT_RELATIVE = Path(
    "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
)


def _tiny_glb() -> bytes:
    positions = struct.pack(
        "<9f",
        -0.5,
        0.0,
        0.0,
        0.5,
        0.0,
        0.0,
        0.0,
        0.5,
        0.0,
    )
    indices = struct.pack("<3H", 0, 1, 2) + b"\x00\x00"
    binary = positions + indices
    document = {
        "asset": {"version": "2.0", "generator": "focused-nine-test"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [
            {
                "primitives": [
                    {
                        "attributes": {"POSITION": 0},
                        "indices": 1,
                        "mode": 4,
                    }
                ]
            }
        ],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36, "target": 34962},
            {"buffer": 0, "byteOffset": 36, "byteLength": 6, "target": 34963},
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "max": [0.5, 0.5, 0.0],
                "min": [-0.5, 0.0, 0.0],
            },
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"},
        ],
    }
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    total_length = 12 + 8 + len(json_bytes) + 8 + len(binary)
    return (
        b"glTF"
        + struct.pack("<II", 2, total_length)
        + struct.pack("<I4s", len(json_bytes), b"JSON")
        + json_bytes
        + struct.pack("<I4s", len(binary), b"BIN\x00")
        + binary
    )


def _empty_node_glb() -> bytes:
    document = {
        "asset": {"version": "2.0", "generator": "focused-nine-empty-node-test"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "EmptyNode"}],
    }
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    total_length = 12 + 8 + len(json_bytes)
    return (
        b"glTF"
        + struct.pack("<II", 2, total_length)
        + struct.pack("<I4s", len(json_bytes), b"JSON")
        + json_bytes
    )


def _staging_fixture(tmp_path: Path) -> Path:
    package = tmp_path / "staging" / "structural" / ASSET_ID
    package.mkdir(parents=True)
    payload = _tiny_glb()
    for filename in (
        f"{ASSET_ID}.glb",
        f"{ASSET_ID}_damaged.glb",
        f"{ASSET_ID}_breached.glb",
    ):
        (package / filename).write_bytes(payload)
    source_package = PROJECT_ROOT / STAGED_PACKAGE
    for filename in (
        f"{ASSET_ID}.manifest.json",
        f"{ASSET_ID}.input.json",
        f"{ASSET_ID}.tscn",
    ):
        shutil.copy2(source_package / filename, package / filename)
    return tmp_path / "staging"


def test_build_overlay_copies_only_candidate_glbs_and_promotes_wrapper_into_overlay(
    tmp_path: Path,
) -> None:
    staging_root = _staging_fixture(tmp_path)
    destination = tmp_path / "overlay"

    validator.build_overlay(PROJECT_ROOT, staging_root, destination)

    for role in ("", "_damaged", "_breached"):
        assert (destination / CANONICAL_IMPORT / f"{ASSET_ID}{role}.glb").is_file()
    assert (destination / CANONICAL_WRAPPER / f"{ASSET_ID}.tscn").is_file()
    assert (destination / CANONICAL_WRAPPER / f"{ASSET_ID}.manifest.json").is_file()
    assert (destination / CANONICAL_WRAPPER / f"{ASSET_ID}.input.json").is_file()
    assert not (PROJECT_ROOT / CANONICAL_WRAPPER / f"{ASSET_ID}.tscn").exists()
    assert not (PROJECT_ROOT / CANONICAL_IMPORT).exists()


def test_pressure_door_overlay_validates_with_godot_smoke(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staging_root = _staging_fixture(tmp_path)
    calls: list[list[str]] = []

    def fake_run(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        return type("Completed", (), {"returncode": 0, "stdout": "FOCUSED_NINE_PRESSURE_DOOR_PASS variants=3 anchors=5 collision=true\n", "stderr": ""})()

    monkeypatch.setattr(validator.subprocess, "run", fake_run)
    assert validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot")) == []
    assert len(calls) == 2
    assert "--import" in calls[0]
    assert "focused_nine_staged_structural_smoke.gd" in calls[1][-1]


def test_missing_breached_variant_is_isolated_and_reports_exact_error(tmp_path: Path) -> None:
    staging_root = _staging_fixture(tmp_path)
    (staging_root / "structural" / ASSET_ID / f"{ASSET_ID}_breached.glb").unlink()

    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert errors == ["missing staged variant breached"]
    assert not (PROJECT_ROOT / CANONICAL_WRAPPER / f"{ASSET_ID}.tscn").exists()
    assert not (PROJECT_ROOT / CANONICAL_IMPORT).exists()


def test_incomplete_selected_staged_package_does_not_fallback_to_project_metadata(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    for filename in (
        f"{ASSET_ID}.manifest.json",
        f"{ASSET_ID}.input.json",
        f"{ASSET_ID}.tscn",
    ):
        (package / filename).unlink()

    calls: list[list[str]] = []

    def fail_if_called(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        raise AssertionError("Godot must not run for an incomplete staged package")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert errors == [f"missing staged wrapper resource {ASSET_ID}.manifest.json"]
    assert calls == []
    assert not (PROJECT_ROOT / CANONICAL_WRAPPER / f"{ASSET_ID}.tscn").exists()
    assert not (PROJECT_ROOT / CANONICAL_IMPORT).exists()


def test_staged_manifest_is_explicitly_non_promoted_with_three_unresolved_hash_slots() -> None:
    manifest = json.loads(
        (PROJECT_ROOT / STAGED_PACKAGE / f"{ASSET_ID}.manifest.json").read_text(encoding="utf-8")
    )

    assert manifest["status"] == "staged_not_promoted"
    assert manifest["promotion"]["promoted"] is False
    roles = manifest["variants"]
    assert [entry["role"] for entry in roles] == ["intact", "damaged", "breached"]
    assert [entry["sha256"] for entry in roles] == [None, None, None]


def test_wrapper_uses_only_overlay_canonical_import_paths_and_contract_anchors() -> None:
    scene = (PROJECT_ROOT / STAGED_PACKAGE / f"{ASSET_ID}.tscn").read_text(encoding="utf-8")

    assert "assets/_staging" not in scene
    assert "/Volumes/" not in scene
    assert scene.count("[ext_resource") == 3
    assert '[node name="Pressure_Door_1x1" type="Node3D"]\nvisible = true' in scene
    assert '[node name="Visual" type="Node3D" parent="."]\nvisible = true' in scene
    assert (
        'name="VisualInstance_Intact" parent="Visual" '
        'instance=ExtResource("1_visual_intact")]\nvisible = true'
    ) in scene
    assert (
        'name="VisualInstance_Damaged" parent="Visual" '
        'instance=ExtResource("2_visual_damaged")]\nvisible = false'
    ) in scene
    assert (
        'name="VisualInstance_Breached" parent="Visual" '
        'instance=ExtResource("3_visual_breached")]\nvisible = false'
    ) in scene
    for variant in (ASSET_ID, f"{ASSET_ID}_damaged", f"{ASSET_ID}_breached"):
        assert f"res://assets/imported/structural/ship_structural_v0/{ASSET_ID}/{variant}.glb" in scene
    for anchor in (
        "Anchor_FloorCenter",
        "Anchor_SOCK_portal_edge_west_01",
        "Anchor_SOCK_portal_edge_east_01",
        "Anchor_SOCK_portal_center_internal_01",
        "Anchor_SOCK_wall_base_01",
    ):
        assert f'name="{anchor}"' in scene


def test_wall_base_anchor_is_required_for_pressure_door(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    staged_scene = package / f"{ASSET_ID}.tscn"
    lines = staged_scene.read_text(encoding="utf-8").splitlines()
    lines = [line for line in lines if "Anchor_SOCK_wall_base_01" not in line]
    staged_scene.write_text("\n".join(lines) + "\n", encoding="utf-8")

    calls: list[list[str]] = []

    def fail_if_called(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        raise AssertionError("Godot must not run for a missing wall_base anchor")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert any("anchor" in error for error in errors)
    assert calls == []


def test_landmark_pressure_wrapper_defaults_to_exact_intact_role_visibility() -> None:
    scene = (PROJECT_ROOT / STAGED_PACKAGE / f"{ASSET_ID}.tscn").read_text(
        encoding="utf-8"
    )
    assert 'name="VisualInstance_Intact" parent="Visual" ' in scene
    assert 'name="VisualInstance_Damaged" parent="Visual" ' in scene
    assert 'name="VisualInstance_Breached" parent="Visual" ' in scene
    assert (
        'name="VisualInstance_Intact" parent="Visual" '
        'instance=ExtResource("1_visual_intact")]\nvisible = true'
    ) in scene
    assert (
        'name="VisualInstance_Damaged" parent="Visual" '
        'instance=ExtResource("2_visual_damaged")]\nvisible = false'
    ) in scene
    assert (
        'name="VisualInstance_Breached" parent="Visual" '
        'instance=ExtResource("3_visual_breached")]\nvisible = false'
    ) in scene


def test_bad_ext_resource_is_rejected_without_touching_live_project(
    tmp_path: Path,
) -> None:
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    staged_scene = package / f"{ASSET_ID}.tscn"
    staged_scene.write_text(
        staged_scene.read_text(encoding="utf-8").replace(
            "res://assets/imported/structural/ship_structural_v0/pressure_door_1x1/pressure_door_1x1.glb",
            "res://assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb",
        ),
        encoding="utf-8",
    )

    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert any("ext_resource" in error for error in errors)
    assert not (PROJECT_ROOT / CANONICAL_WRAPPER / f"{ASSET_ID}.tscn").exists()


def test_swapped_visual_ext_resource_bindings_are_rejected_before_godot(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    staged_scene = package / f"{ASSET_ID}.tscn"
    lines = staged_scene.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if 'name="VisualInstance_Intact"' in line:
            lines[index] = line.replace('ExtResource("1_visual_intact")', 'ExtResource("2_visual_damaged")')
        elif 'name="VisualInstance_Damaged"' in line:
            lines[index] = line.replace('ExtResource("2_visual_damaged")', 'ExtResource("1_visual_intact")')
    staged_scene.write_text("\n".join(lines) + "\n", encoding="utf-8")

    calls: list[list[str]] = []

    def fail_if_called(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        raise AssertionError("Godot must not run for a swapped wrapper binding")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert any("binding" in error for error in errors)
    assert calls == []


def test_swapped_visual_visibility_states_are_rejected_before_godot(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    staged_scene = package / f"{ASSET_ID}.tscn"
    scene = staged_scene.read_text(encoding="utf-8")
    scene = scene.replace(
        'name="VisualInstance_Intact" parent="Visual" instance=ExtResource("1_visual_intact")]\nvisible = true',
        'name="VisualInstance_Intact" parent="Visual" instance=ExtResource("1_visual_intact")]\nvisible = false',
    )
    scene = scene.replace(
        'name="VisualInstance_Damaged" parent="Visual" instance=ExtResource("2_visual_damaged")]\nvisible = false',
        'name="VisualInstance_Damaged" parent="Visual" instance=ExtResource("2_visual_damaged")]\nvisible = true',
    )
    staged_scene.write_text(scene, encoding="utf-8")

    calls: list[list[str]] = []

    def fail_if_called(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        raise AssertionError("Godot must not run for swapped wrapper visibility")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert any("visibility" in error for error in errors)
    assert calls == []


@pytest.mark.parametrize(
    ("description", "mutate"),
    [
        (
            "hidden root",
            lambda scene: scene.replace(
                '[node name="Pressure_Door_1x1" type="Node3D"]',
                '[node name="Pressure_Door_1x1" type="Node3D"]\nvisible = false',
            ),
        ),
        (
            "hidden visual root",
            lambda scene: scene.replace(
                '[node name="Visual" type="Node3D" parent="."]',
                '[node name="Visual" type="Node3D" parent="."]\nvisible = false',
            ),
        ),
        (
            "missing intact visibility",
            lambda scene: scene.replace("visible = true\n", "", 1),
        ),
        (
            "hidden intact visual",
            lambda scene: scene.replace(
                'name="VisualInstance_Intact" parent="Visual" instance=ExtResource("1_visual_intact")]\nvisible = true',
                'name="VisualInstance_Intact" parent="Visual" instance=ExtResource("1_visual_intact")]\nvisible = false',
            ),
        ),
        (
            "shown damaged visual",
            lambda scene: scene.replace(
                'name="VisualInstance_Damaged" parent="Visual" instance=ExtResource("2_visual_damaged")]\nvisible = false',
                'name="VisualInstance_Damaged" parent="Visual" instance=ExtResource("2_visual_damaged")]\nvisible = true',
            ),
        ),
        (
            "shown breached visual",
            lambda scene: scene.replace(
                'name="VisualInstance_Breached" parent="Visual" instance=ExtResource("3_visual_breached")]\nvisible = false',
                'name="VisualInstance_Breached" parent="Visual" instance=ExtResource("3_visual_breached")]\nvisible = true',
            ),
        ),
    ],
)
def test_required_wrapper_visibility_contract_is_rejected_before_godot(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    description: str,
    mutate: Callable[[str], str],
) -> None:
    del description
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    staged_scene = package / f"{ASSET_ID}.tscn"
    staged_scene.write_text(mutate(staged_scene.read_text(encoding="utf-8")), encoding="utf-8")

    calls: list[list[str]] = []

    def fail_if_called(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        raise AssertionError("Godot must not run for an invalid wrapper visibility contract")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert any("visibility" in error for error in errors)
    assert calls == []


@pytest.mark.parametrize(
    ("name", "mutate"),
    [
        (
            "root nested under Visual",
            lambda scene: scene.replace(
                '[node name="Pressure_Door_1x1" type="Node3D"]',
                '[node name="Pressure_Door_1x1" type="Node3D" parent="Visual"]',
            ),
        ),
        (
            "visual nested under an unrelated node",
            lambda scene: scene.replace(
                '[node name="Visual" type="Node3D" parent="."]',
                '[node name="Visual" type="Node3D" parent="CollisionRoot"]',
            ),
        ),
    ],
)
def test_malformed_wrapper_visibility_nesting_is_rejected_before_godot(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    name: str,
    mutate: Callable[[str], str],
) -> None:
    del name
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    staged_scene = package / f"{ASSET_ID}.tscn"
    staged_scene.write_text(mutate(staged_scene.read_text(encoding="utf-8")), encoding="utf-8")

    calls: list[list[str]] = []

    def fail_if_called(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        raise AssertionError("Godot must not run for malformed wrapper nesting")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert any("root" in error or "visual" in error for error in errors)
    assert calls == []


@pytest.mark.parametrize(
    ("resource", "mutate", "message"),
    [
        (
            f"{ASSET_ID}.manifest.json",
            lambda document: document["asset"].update({"id": "wrong_asset"}),
            "asset",
        ),
        (
            f"{ASSET_ID}.manifest.json",
            lambda document: document["asset"].update({"wrapper_scene": "/Volumes/elsewhere/door.tscn"}),
            "wrapper",
        ),
        (
            f"{ASSET_ID}.manifest.json",
            lambda document: document["asset"].update({"source_asset_path": "assets/_staging/escape.glb"}),
            "source",
        ),
        (
            f"{ASSET_ID}.manifest.json",
            lambda document: document.update(
                {"variants": [document["variants"][0], document["variants"][2], document["variants"][1]]}
            ),
            "roles",
        ),
        (
            f"{ASSET_ID}.manifest.json",
            lambda document: document["asset"]["anchors"]["exposed"].append(
                {"name": "Anchor_unexpected", "kind": "attachment", "surface": "custom"}
            ),
            "anchors",
        ),
    ],
)
def test_staged_metadata_tampering_is_rejected_deterministically(
    tmp_path: Path,
    resource: str,
    mutate: Callable[[dict[str, object]], None],
    message: str,
) -> None:
    staging_root = _staging_fixture(tmp_path)
    path = staging_root / "structural" / ASSET_ID / resource
    document = json.loads(path.read_text(encoding="utf-8"))
    mutate(document)
    path.write_text(json.dumps(document), encoding="utf-8")

    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert errors
    assert message in errors[0]


def test_header_only_glb_is_rejected_before_godot(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    header_only = b"glTF" + struct.pack("<II", 2, 12)
    for path in package.glob("*.glb"):
        path.write_bytes(header_only)
    calls: list[list[str]] = []

    def fail_if_called(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        raise AssertionError("Godot must not run for a malformed GLB")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert any("chunk" in error for error in errors)
    assert calls == []


def test_semantically_empty_node_only_glb_is_rejected_before_godot(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staging_root = _staging_fixture(tmp_path)
    package = staging_root / "structural" / ASSET_ID
    for path in package.glob("*.glb"):
        path.write_bytes(_empty_node_glb())
    calls: list[list[str]] = []

    def fail_if_called(command: list[str], **kwargs: object) -> object:
        calls.append(command)
        raise AssertionError("Godot must not run for a semantically empty GLB")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, staging_root, Path("godot"))

    assert errors == ["invalid staged variant intact GLB no meshes"]
    assert calls == []


def test_staging_traversal_and_symlink_aliases_are_rejected(tmp_path: Path) -> None:
    staging_root = _staging_fixture(tmp_path)
    with pytest.raises(ValueError, match="staging root.*traversal"):
        validator.build_overlay(PROJECT_ROOT, Path(str(staging_root / ".." / "staging" / "..")), tmp_path / "overlay")

    alias = tmp_path / "staging-alias"
    alias.symlink_to(staging_root, target_is_directory=True)
    errors = validator.validate_pressure_door_overlay(PROJECT_ROOT, alias, Path("godot"))
    assert any("symlink" in error for error in errors)


@pytest.mark.parametrize("root_kind", ["project", "staging"])
def test_self_loop_project_or_staging_root_is_total_and_deterministic(
    tmp_path: Path, root_kind: str
) -> None:
    staging_root = _staging_fixture(tmp_path)
    loop = tmp_path / f"{root_kind}-loop"
    loop.symlink_to(loop)
    project_root = loop if root_kind == "project" else PROJECT_ROOT
    selected_staging = loop if root_kind == "staging" else staging_root

    errors = validator.validate_pressure_door_overlay(project_root, selected_staging, Path("godot"))

    assert len(errors) == 1
    assert "resolve" in errors[0] or "symlink" in errors[0]


def test_self_loop_destination_is_rejected_without_runtime_error(tmp_path: Path) -> None:
    destination = tmp_path / "destination-loop"
    destination.symlink_to(destination)

    with pytest.raises(ValueError, match="resolve|symlink"):
        validator.build_overlay(PROJECT_ROOT, _staging_fixture(tmp_path), destination)


def test_destination_alias_into_live_project_is_rejected(tmp_path: Path) -> None:
    destination = tmp_path / "project-alias"
    destination.symlink_to(PROJECT_ROOT, target_is_directory=True)

    with pytest.raises(ValueError, match="destination.*project root"):
        validator.build_overlay(PROJECT_ROOT, _staging_fixture(tmp_path), destination)


def test_cli_self_loop_project_returns_nonzero_without_traceback(tmp_path: Path) -> None:
    project_loop = tmp_path / "project-loop"
    project_loop.symlink_to(project_loop)
    staging_root = _staging_fixture(tmp_path)

    completed = subprocess.run(
        [
            sys.executable,
            str(PROJECT_ROOT / "tools/focused_nine_staged_structural.py"),
            "--project-root",
            str(project_loop),
            "--staging-root",
            str(staging_root),
            "--godot",
            "godot",
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert completed.returncode != 0
    assert "Traceback" not in completed.stderr
    assert "ERROR:" in completed.stderr


def test_smoke_source_has_exact_marker_and_runtime_contract_assertions() -> None:
    smoke = (
        PROJECT_ROOT / "scripts/validation/focused_nine_staged_structural_smoke.gd"
    ).read_text(encoding="utf-8")

    assert 'FOCUSED_NINE_PRESSURE_DOOR_PASS variants=3 anchors=5 collision=true' in smoke
    assert "VisualInstance_Intact" in smoke
    assert "VisualInstance_Damaged" in smoke
    assert "VisualInstance_Breached" in smoke
    assert "intact.visible" in smoke
    assert "damaged.visible" in smoke
    assert "breached.visible" in smoke
    assert "Anchor_FloorCenter" in smoke
    assert "CollisionShape3D" in smoke
