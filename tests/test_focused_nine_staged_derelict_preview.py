from __future__ import annotations

import json
import shutil
import sys
import time
from pathlib import Path

import pytest

from tools import focused_nine_staged_derelict_preview as preview

PROJECT_ROOT = Path(__file__).resolve().parents[1]
STAGING_RELATIVE = Path("assets/_staging/focused_nine")
PREVIEW_RELATIVE = Path("artifacts/validation-previews/focused-nine")
PROOF_RELATIVE = Path("docs/superpowers/proofs/focused-nine-staged-derelict.md")
IMAGE_NAME = "focused-nine-staged-derelict.png"


def _args(project: Path, *, dry_run: bool = False) -> list[str]:
    values = [
        "--project-root",
        str(project),
        "--staging-root",
        str(project / STAGING_RELATIVE),
        "--preview-dir",
        str(project / PREVIEW_RELATIVE),
        "--proof",
        str(project / PROOF_RELATIVE),
    ]
    if dry_run:
        values.append("--dry-run")
    return values


def _project_fixture(tmp_path: Path) -> Path:
    project = tmp_path / "project"
    project.mkdir()
    shutil.copytree(
        PROJECT_ROOT / STAGING_RELATIVE,
        project / STAGING_RELATIVE,
        copy_function=shutil.copy2,
    )
    contract_path = project / "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
    contract_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        PROJECT_ROOT / "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json",
        contract_path,
    )
    wrapper = project / "scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn"
    wrapper.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        PROJECT_ROOT / "scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn",
        wrapper,
    )
    return project


def _namespace_args(project: Path, *, dry_run: bool = False):
    return preview.parse_args(_args(project, dry_run=dry_run))


def test_parse_args_rejects_runtime_staging_alias_and_traversal(tmp_path: Path) -> None:
    project = tmp_path / "project"
    project.mkdir()
    with pytest.raises(SystemExit):
        preview.parse_args(
            [
                "--project-root",
                str(project),
                "--staging-root",
                str(project / "assets/imported"),
                "--preview-dir",
                str(project / PREVIEW_RELATIVE),
                "--proof",
                str(project / PROOF_RELATIVE),
            ]
        )
    with pytest.raises(SystemExit):
        preview.parse_args(_args(project / ".." / "project"))


def test_preflight_requires_all_staged_focused_nine_inputs(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    (project / STAGING_RELATIVE / "structural/pressure_door_1x1/pressure_door_1x1_breached.glb").unlink()
    with pytest.raises(ValueError, match="pressure-door|staged input"):
        preview.validate_inputs(_namespace_args(project))


def test_overlay_uses_regular_staged_glbs_at_canonical_import_paths(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    inputs = preview.validate_inputs(_namespace_args(project))
    overlay = tmp_path / "overlay"
    preview._build_overlay(project, inputs, overlay)
    try:
        imported_floor = overlay / "assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb"
        staged_floor = project / STAGING_RELATIVE / "structural/floor_1x1/floor_1x1.glb"
        assert imported_floor.is_file()
        assert not imported_floor.is_symlink()
        assert imported_floor.read_bytes() == staged_floor.read_bytes()
        wrapper = overlay / "scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn"
        assert "res://assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb" in wrapper.read_text()
        assert "assets/_staging/focused_nine" not in wrapper.read_text()
    finally:
        shutil.rmtree(overlay)


def test_capture_output_rejects_diagnostics_even_with_pass_marker(tmp_path: Path) -> None:
    wrapper = tmp_path / "capture.py"
    wrapper.write_text(
        "print('FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS seed=17 rooms=5 placements=5 walls=4 portals=1 staged_wrapper_count=5 staged=17 debug=res://artifacts/validation-previews/focused-nine/edge_map.json output=res://artifacts/validation-previews/focused-nine/focused-nine-staged-derelict.png')\n"
        "print('WARNING: injected')\n",
        encoding="utf-8",
    )
    ok, detail, metadata = preview._run_capture_process(
        [sys.executable, str(wrapper)], cwd=tmp_path, timeout=3
    )
    assert not ok
    assert "WARNING:" in detail
    assert metadata is None


def test_bounded_process_timeout_kills_process_group(tmp_path: Path) -> None:
    wrapper = tmp_path / "sleep.py"
    wrapper.write_text("import time\ntime.sleep(30)\n", encoding="utf-8")
    started = time.monotonic()
    with pytest.raises(preview.CaptureTimeout):
        preview._run_bounded_process([sys.executable, str(wrapper)], timeout=0.1, label="test")
    assert time.monotonic() - started < 3


def test_proof_contains_seed_room_and_staged_wrapper_evidence(tmp_path: Path) -> None:
    proof = preview.build_proof(
        output_path=tmp_path / IMAGE_NAME,
        dimensions=(1600, 900),
        seed=17,
        room_count=5,
        staged_wrapper_count=12,
        staged_input_count=17,
        marker="FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS seed=17 rooms=5 wrappers=12 staged=17",
    )
    assert "seed=17" in proof
    assert "room_count=5" in proof
    assert "staged_wrapper_count=12" in proof
    assert "staged_input_count=17" in proof
    assert "No runtime promotion occurred" in proof


def test_capture_scene_source_uses_direct_viewport_texture_and_staged_generator_contract() -> None:
    script = PROJECT_ROOT / "scripts/validation/focused_nine_staged_derelict_capture.gd"
    scene = PROJECT_ROOT / "scenes/validation/focused_nine_staged_derelict_harness.tscn"
    assert script.is_file()
    assert scene.is_file()
    text = script.read_text(encoding="utf-8")
    assert "get_viewport().get_root()" not in text
    assert "get_viewport()" in text
    assert "get_texture()" in text
    assert "ShipGenerator" in text
    assert "StagedFocusedNine" in text
    assert "FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS" in text


def test_capture_uses_one_production_generator_path_and_never_decorates_floors() -> None:
    source = (PROJECT_ROOT / "scripts/validation/focused_nine_staged_derelict_capture.gd").read_text(
        encoding="utf-8"
    )
    assert "ShipGeneratorScript.new()" in source
    assert "generator.generate(blueprint, derelict_archetype)" in source
    assert source.count("generator.generate(blueprint, derelict_archetype)") == 1
    assert "RoomGraphGeneratorScript" not in source
    assert "StructuralPlacerScript" not in source
    assert "_decorate_from_generated_rooms" not in source
    assert "_add_generated_labels" not in source


def test_preview_runner_requires_edge_debug_bundle_before_publish() -> None:
    source = (PROJECT_ROOT / "tools/focused_nine_staged_derelict_preview.py").read_text(encoding="utf-8")
    assert "edge_map.json" in source
    assert "duplicate edge key" in source
    assert "portal endpoint" in source
    assert "_validate_debug_bundle" in source


def test_capture_scene_keeps_only_production_root_and_camera_inputs() -> None:
    scene = (PROJECT_ROOT / "scenes/validation/focused_nine_staged_derelict_harness.tscn").read_text(
        encoding="utf-8"
    )
    assert 'node name="GeneratedShipRoot" type="Node3D" parent="."' in scene
    assert 'node name="DerelictCamera" type="Camera3D" parent="."' in scene
    assert "RoomGraphGenerator" not in scene
    assert "StructuralPlacer" not in scene


def test_debug_bundle_rejects_duplicate_edge_keys(tmp_path: Path) -> None:
    bundle = tmp_path / "edge_map.json"
    edge = {"edge_key": "0|h|0|0", "kind": "SOLID", "room_ids": ["room_a", ""]}
    bundle.write_text(
        json.dumps(
            {
                "schema": "focused_nine_canonical_edge_map_v1",
                "capture_id": "StagedFocusedNine",
                "seed": 17,
                "rooms": 5,
                "occupancy": [],
                "edges": [
                    {**edge, "placement_required": False, "wrapper_required": False},
                    {**edge, "placement_required": False, "wrapper_required": False},
                ],
                "placements": [],
                "wrapper_metadata": [],
                "validation": {
                    "edge_keys_unique": True,
                    "portal_endpoints_valid": True,
                    "no_portal_wall_overlap": True,
                    "canonical_validator": True,
                },
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="duplicate edge key"):
        preview._validate_debug_bundle(bundle)


def test_debug_bundle_rejects_nonreciprocal_portal_endpoint(tmp_path: Path) -> None:
    bundle = tmp_path / "edge_map.json"
    bundle.write_text(
        json.dumps(
            {
                "schema": "focused_nine_canonical_edge_map_v1",
                "capture_id": "StagedFocusedNine",
                "seed": 17,
                "rooms": 5,
                "occupancy": [],
                "edges": [
                    {
                        "edge_key": "0|h|0|0",
                        "kind": "DOOR",
                        "room_ids": ["room_a", ""],
                        "placement_required": True,
                        "wrapper_required": True,
                    }
                ],
                "placements": [],
                "wrapper_metadata": [],
                "validation": {
                    "edge_keys_unique": True,
                    "portal_endpoints_valid": True,
                    "no_portal_wall_overlap": True,
                    "canonical_validator": True,
                },
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="portal endpoint"):
        preview._validate_debug_bundle(bundle)


def test_dry_run_does_not_build_overlay_or_write_outputs(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = _project_fixture(tmp_path)
    args = _namespace_args(project, dry_run=True)
    monkeypatch.setattr(
        preview,
        "_build_overlay",
        lambda *_args: (_ for _ in ()).throw(AssertionError("dry-run built overlay")),
    )
    result = preview.run(args)
    assert result.exit_code == 0
    assert result.dry_run
    assert not (project / PREVIEW_RELATIVE).exists()
    assert not (project / PROOF_RELATIVE).exists()


def test_runtime_snapshot_mismatch_blocks_publication(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = _project_fixture(tmp_path)
    args = _namespace_args(project)
    monkeypatch.setattr(preview, "validate_inputs", lambda _args: preview.ValidatedInputs(()))
    monkeypatch.setattr(preview, "_run_capture_process", lambda *_args, **_kwargs: (False, "synthetic stop", None))
    snapshots = iter([("before",), ("after",)])
    monkeypatch.setattr(preview, "snapshot_runtime_surfaces", lambda _root: next(snapshots))
    result = preview.run(args)
    assert result.exit_code == 1
    assert "runtime surface mismatch" in result.reason


def test_png_dimension_validation_requires_real_1600x900_png(tmp_path: Path) -> None:
    image = tmp_path / IMAGE_NAME
    image.write_bytes(b"\x89PNG\r\n\x1a\ninvalid")
    with pytest.raises(ValueError, match="PNG|1600x900"):
        preview._validate_capture_image(image)


def test_png_validation_rejects_forged_dimensions_without_complete_chunks(tmp_path: Path) -> None:
    image = tmp_path / IMAGE_NAME
    # This has enough bytes to forge the IHDR dimensions, but no complete
    # IDAT/IEND chunk stream. Header-only validation would accept it.
    image.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + (13).to_bytes(4, "big")
        + b"IHDR"
        + (1600).to_bytes(4, "big")
        + (900).to_bytes(4, "big")
        + b"\x08\x06\x00\x00\x00"
        + b"\x00\x00\x00\x00"
    )
    with pytest.raises(ValueError, match="PNG|chunk|IEND|IDAT"):
        preview._validate_capture_image(image)


def test_publication_outputs_use_private_directory_and_file_modes(tmp_path: Path) -> None:
    preview_path = tmp_path / "new" / "nested" / "preview.png"
    proof_path = tmp_path / "other" / "nested" / "proof.md"

    preview.publish_artifacts(preview_path, b"png", proof_path, "proof")

    for directory in (preview_path.parent, preview_path.parent.parent, proof_path.parent, proof_path.parent.parent):
        assert directory.stat().st_mode & 0o777 == 0o700
    assert preview_path.stat().st_mode & 0o777 == 0o600
    assert proof_path.stat().st_mode & 0o777 == 0o600


def _debug_bundle(*, schema: bool = True, capture_id: bool = True, wrapper_metadata: bool = True) -> dict:
    edge_key = "0|h|0|0"
    placement_id = f"placement:{edge_key}"
    document = {
        "schema": "focused_nine_canonical_edge_map_v1",
        "capture_id": "StagedFocusedNine",
        "seed": 17,
        "rooms": 5,
        "occupancy": [],
        "edges": [
            {
                "edge_key": edge_key,
                "kind": "SOLID",
                "room_ids": ["room_a", ""],
                "placement_required": True,
                "wrapper_required": True,
            }
        ],
        "placements": [{"edge_key": edge_key, "placement_id": placement_id, "kind": "SOLID"}],
        "wrapper_metadata": [{"edge_key": edge_key, "placement_id": placement_id}],
        "validation": {
            "edge_keys_unique": True,
            "portal_endpoints_valid": True,
            "no_portal_wall_overlap": True,
            "canonical_validator": True,
        },
    }
    if not schema:
        document.pop("schema")
    if not capture_id:
        document.pop("capture_id")
    if not wrapper_metadata:
        document.pop("wrapper_metadata")
    return document


def test_debug_bundle_requires_schema_capture_id_and_wrapper_metadata(tmp_path: Path) -> None:
    bundle = tmp_path / "edge_map.json"
    document = _debug_bundle(schema=False, capture_id=False, wrapper_metadata=False)
    bundle.write_text(json.dumps(document), encoding="utf-8")

    with pytest.raises(ValueError, match="schema|capture_id|wrapper_metadata"):
        preview._validate_debug_bundle(bundle)


def test_debug_bundle_rejects_placement_redirect_to_open_unrequired_edge(tmp_path: Path) -> None:
    bundle = tmp_path / "edge_map.json"
    document = _debug_bundle()
    required_key = "0|h|0|0"
    open_key = "0|h|0|1"
    document["edges"] = [
        document["edges"][0],
        {
            "edge_key": open_key,
            "kind": "OPEN",
            "room_ids": ["room_a", "room_b"],
            "placement_required": False,
            "wrapper_required": False,
        },
    ]
    document["placements"] = [{"edge_key": open_key, "placement_id": f"placement:{open_key}", "kind": "OPEN"}]
    document["wrapper_metadata"] = [{"edge_key": open_key, "placement_id": f"placement:{open_key}"}]
    assert required_key not in {entry["edge_key"] for entry in document["placements"]}
    bundle.write_text(json.dumps(document), encoding="utf-8")

    with pytest.raises(ValueError, match="required|OPEN|unrequired|placement"):
        preview._validate_debug_bundle(bundle)
