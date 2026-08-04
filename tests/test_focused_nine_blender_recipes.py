from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from types import SimpleNamespace
from pathlib import Path

import pytest

from tools import focused_nine_contract

PROJECT_ROOT = Path(__file__).resolve().parents[1]
BLENDER = Path("/opt/homebrew/bin/blender")
SOURCE_FIXTURE = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/floor_1x1/floor_1x1.blend"
)
PRESSURE_SOURCE_FIXTURE = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/doorway_frame_open_1x1/doorway_frame_open_1x1.blend"
)
PRESSURE_CONTRACT_FIXTURE = PROJECT_ROOT / (
    "data/placement/contracts/structural/ship_structural_v0/doorway_frame_open_1x1_contract.json"
)
PRESSURE_GLB_FIXTURE = PROJECT_ROOT / (
    "assets/imported/structural/ship_structural_v0/doorway_frame_open_1x1/doorway_frame_open_1x1.glb"
)
PROP_SOURCE_FIXTURE = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/props/emergency_wall.blend"
)
MATERIAL_FIXTURE = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/salvage_industrial.blend"
)
CONTRACT_FIXTURE = PROJECT_ROOT / (
    "data/placement/contracts/structural/ship_structural_v0/floor_1x1_contract.json"
)
SOURCE_GLB_FIXTURE = PROJECT_ROOT / (
    "assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb"
)


def test_registry_is_reused_without_a_second_asset_allowlist() -> None:
    from tools.focused_nine_blender_recipes import (
        PROP_ASSET_IDS,
        STRUCTURAL_ASSET_IDS,
    )

    assert STRUCTURAL_ASSET_IDS == focused_nine_contract.STRUCTURAL_IDS
    assert PROP_ASSET_IDS == focused_nine_contract.PROP_IDS


def test_unknown_asset_is_rejected_before_blender_import() -> None:
    sys.modules.pop("bpy", None)
    from tools.focused_nine_blender_recipes import parse_args, select_asset

    with pytest.raises(ValueError, match="unknown focused-nine asset"):
        select_asset("not_a_focused_nine_asset")
    with pytest.raises(SystemExit):
        parse_args(
            [
                "--project-root",
                ".",
                "--structural-source-root",
                "/tmp/structural",
                "--props-source-root",
                "/tmp/props",
                "--asset-id",
                "unknown",
            ]
        )
    assert "bpy" not in sys.modules


def test_source_paths_are_exact_and_kind_specific(tmp_path: Path) -> None:
    from tools.focused_nine_blender_recipes import source_blend_path, source_path

    structural_root = tmp_path / "structural"
    props_root = tmp_path / "props"
    assert source_blend_path(structural_root, props_root, "floor_1x1") == (
        structural_root / "floor_1x1/floor_1x1.blend"
    )
    assert source_path(structural_root, props_root, "wall_straight_1x1") == (
        structural_root / "wall_straight_1x1/wall_straight_1x1.blend"
    )
    assert source_blend_path(structural_root, props_root, "hull_breach_seal_point") == (
        props_root / "hull_breach_seal_point.blend"
    )
    with pytest.raises(ValueError, match="unknown focused-nine asset"):
        source_blend_path(structural_root, props_root, "../escape")


def test_source_candidates_reject_runtime_surfaces_and_symlink_aliases(tmp_path: Path) -> None:
    from tools.focused_nine_blender_recipes import resolve_source_path

    project_root = tmp_path / "project"
    imported_root = project_root / "assets/imported"
    staging_root = project_root / "assets/_staging"
    imported_root.mkdir(parents=True)
    staging_root.mkdir(parents=True)

    with pytest.raises(ValueError, match="runtime"):
        resolve_source_path(project_root, imported_root / "structural", tmp_path / "props", "floor_1x1")
    with pytest.raises(ValueError, match="runtime"):
        resolve_source_path(project_root, staging_root / "focused_nine", tmp_path / "props", "floor_1x1")

    alias = tmp_path / "imported-alias"
    alias.symlink_to(imported_root, target_is_directory=True)
    with pytest.raises(ValueError, match="runtime"):
        resolve_source_path(project_root, alias / "structural", tmp_path / "props", "floor_1x1")

    external_root = tmp_path / "external-source"
    external_root.mkdir()
    resolved = resolve_source_path(project_root, external_root, tmp_path / "props", "floor_1x1")
    assert resolved == (external_root / "floor_1x1/floor_1x1.blend").resolve()


def test_run_rejects_runtime_source_before_blender_or_save(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    import tools.focused_nine_blender_recipes as recipes

    project_root = tmp_path / "project"
    runtime_root = project_root / "assets/imported"
    runtime_root.mkdir(parents=True)
    monkeypatch.setattr(recipes, "_BPY", None)
    args = argparse.Namespace(
        project_root=project_root,
        structural_source_root=runtime_root,
        props_source_root=tmp_path / "props",
        asset_id="floor_1x1",
    )

    with pytest.raises(ValueError, match="runtime surface"):
        recipes._run(args)
    assert recipes._BPY is None


class _FakeCollection:
    def __init__(self, name: str, objects: list[object] | None = None) -> None:
        self.name = name
        self.objects = objects or []
        self.children: list[_FakeCollection] = []
        self._props: dict[str, object] = {}

    def __contains__(self, key: str) -> bool:
        return key in self._props

    def __getitem__(self, key: str) -> object:
        return self._props[key]

    def __setitem__(self, key: str, value: object) -> None:
        self._props[key] = value

    def get(self, key: str, default: object = None) -> object:
        return self._props.get(key, default)


class _FakeCollections(list[_FakeCollection]):
    def get(self, name: str) -> _FakeCollection | None:
        return next((collection for collection in self if collection.name == name), None)

    def new(self, name: str) -> _FakeCollection:
        collection = _FakeCollection(name)
        self.append(collection)
        return collection


def test_replace_generated_visuals_is_limited_to_the_passed_collection(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import tools.focused_nine_blender_recipes as recipes

    target_generated = SimpleNamespace(name="FocusedNine_floor_1x1_target")
    target_authored = SimpleNamespace(name="Authored_floor_1x1_panel")
    unrelated_generated = SimpleNamespace(name="FocusedNine_floor_1x1_same_name")
    target = _FakeCollection("Geometry", [target_generated, target_authored])
    unrelated = _FakeCollection("Export_intact", [unrelated_generated])

    class FakeObjects:
        def remove(self, obj: object, *, do_unlink: bool) -> None:
            assert do_unlink is True
            for collection in (target, unrelated):
                if obj in collection.objects:
                    collection.objects.remove(obj)

    fake_bpy = SimpleNamespace(
        data=SimpleNamespace(collections=_FakeCollections([target, unrelated]), objects=FakeObjects())
    )
    monkeypatch.setattr(recipes, "_BPY", fake_bpy)

    recipes.replace_generated_visuals(SimpleNamespace(name="ModuleRoot_floor_1x1"), target, "floor_1x1")

    assert target.objects == [target_authored]
    assert unrelated.objects == [unrelated_generated]


def test_existing_helper_metadata_is_untouched_and_incompatible_metadata_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import tools.focused_nine_blender_recipes as recipes

    existing = _FakeCollection("Export_intact")
    existing["variant_role"] = "intact"
    existing["authored_metadata"] = "preserve-byte-for-byte"
    helpers = _FakeCollection("AuthoringHelpers")
    helpers.children.append(existing)
    collections = _FakeCollections([helpers, existing])
    monkeypatch.setattr(recipes, "_BPY", SimpleNamespace(data=SimpleNamespace(collections=collections)))
    before = dict(existing._props)

    recipes.ensure_structural_helpers(
        SimpleNamespace(module_id="floor_1x1"),
        SimpleNamespace(name="ModuleRoot_floor_1x1"),
        helpers,
    )
    assert existing._props == before

    existing["variant_role"] = "breached"
    with pytest.raises(RuntimeError, match="incompatible metadata"):
        recipes.ensure_structural_helpers(
            SimpleNamespace(module_id="floor_1x1"),
            SimpleNamespace(name="ModuleRoot_floor_1x1"),
            helpers,
        )


def test_report_only_lists_target_asset_helpers(monkeypatch: pytest.MonkeyPatch) -> None:
    import tools.focused_nine_blender_recipes as recipes

    generated = SimpleNamespace(name="FocusedNine_floor_1x1_panel", type="EMPTY", modifiers=())
    target = _FakeCollection("Export_intact")
    unrelated = _FakeCollection("Export_intact_other_asset")
    fake_bpy = SimpleNamespace(data=SimpleNamespace(collections=_FakeCollections([target, unrelated])))
    monkeypatch.setattr(recipes, "_BPY", fake_bpy)

    report = recipes._report(
        "floor_1x1",
        "structural",
        Path("/tmp/floor_1x1.blend"),
        [generated],
        {"intact": target},
        {"material_names": list(recipes.REQUIRED_MATERIAL_NAMES)},
    )

    assert report["helper_names"] == ["Export_intact"]


def test_cli_parser_exposes_the_required_blender_interface() -> None:
    from tools.focused_nine_blender_recipes import parse_args

    args = parse_args(
        [
            "--project-root",
            "/project",
            "--structural-source-root",
            "/structural",
            "--props-source-root",
            "/props",
            "--asset-id",
            "floor_1x1",
            "--overwrite-generated-only",
        ]
    )
    assert args.project_root == Path("/project")
    assert args.structural_source_root == Path("/structural")
    assert args.props_source_root == Path("/props")
    assert args.asset_id == "floor_1x1"
    assert args.overwrite_generated_only is True


def test_compatibility_wrapper_delegates_without_scene_wide_or_boolean_operations() -> None:
    wrapper = (PROJECT_ROOT / "tools/improve_floor_geometry.py").read_text(encoding="utf-8")
    assert "focused_nine_blender_recipes" in wrapper
    assert "select_all" not in wrapper
    assert "BOOLEAN" not in wrapper
    assert "bpy.ops.object.delete" not in wrapper


def test_compatibility_parser_preserves_python_args_and_rejects_missing_separator(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from tools.improve_floor_geometry import parse_args

    explicit = parse_args(
        [
            "--project-root",
            "/project",
            "--source-root",
            "/structural",
            "--module",
            "floor_1x1",
            "--overwrite",
        ]
    )
    assert explicit.project_root == Path("/project")
    assert explicit.source_root == Path("/structural")

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "improve_floor_geometry.py",
            "--project-root",
            "/project",
            "--source-root",
            "/structural",
            "--module",
            "floor_1x1",
            "--overwrite",
        ],
    )
    with pytest.raises(SystemExit):
        parse_args()


def _report_from_stdout(stdout: str) -> tuple[dict, str]:
    reports = []
    for line in stdout.splitlines():
        if line.startswith("FOCUSED_NINE_REPORT "):
            reports.append(json.loads(line.removeprefix("FOCUSED_NINE_REPORT ")))
    assert len(reports) == 1, stdout
    report_line = next(
        line for line in stdout.splitlines() if line.startswith("FOCUSED_NINE_REPORT ")
    )
    return reports[0], report_line


def _recipe_command(
    *, project_root: Path, structural_root: Path, props_root: Path, asset_id: str
) -> list[str]:
    return [
        str(BLENDER),
        "--background",
        "--factory-startup",
        "--python",
        str(PROJECT_ROOT / "tools/focused_nine_blender_recipes.py"),
        "--",
        "--project-root",
        str(project_root),
        "--structural-source-root",
        str(structural_root),
        "--props-source-root",
        str(props_root),
        "--asset-id",
        asset_id,
        "--overwrite-generated-only",
    ]


def test_blender_pressure_door_roles_are_distinct_and_idempotent(tmp_path: Path) -> None:
    for fixture in (
        BLENDER,
        PRESSURE_SOURCE_FIXTURE,
        PRESSURE_CONTRACT_FIXTURE,
        PRESSURE_GLB_FIXTURE,
        MATERIAL_FIXTURE,
    ):
        if not fixture.is_file():
            pytest.fail(f"fixture missing: {fixture}")
    pressure_fixture_bytes = PRESSURE_SOURCE_FIXTURE.read_bytes()
    pressure_contract_bytes = PRESSURE_CONTRACT_FIXTURE.read_bytes()
    pressure_glb_bytes = PRESSURE_GLB_FIXTURE.read_bytes()
    material_fixture_bytes = MATERIAL_FIXTURE.read_bytes()

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "pressure_door_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "pressure_door_1x1.blend"
    shutil.copy2(PRESSURE_SOURCE_FIXTURE, source_blend)
    props_root = tmp_path / "props"
    props_root.mkdir()
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

    command = _recipe_command(
        project_root=PROJECT_ROOT,
        structural_root=structural_root,
        props_root=props_root,
        asset_id="pressure_door_1x1",
    )
    first = subprocess.run(command, capture_output=True, text=True, check=False)
    assert first.returncode == 0, first.stdout + first.stderr
    first_report, first_line = _report_from_stdout(first.stdout)
    second = subprocess.run(command, capture_output=True, text=True, check=False)
    assert second.returncode == 0, second.stdout + second.stderr
    second_report, second_line = _report_from_stdout(second.stdout)

    assert first_report == second_report
    assert first_line == second_line
    prefix = "FocusedNine_pressure_door_1x1_"
    names = first_report["generated_object_names"]
    assert names
    assert all(name.startswith(prefix) for name in names)
    assert first_report["generated_count"] == len(names)
    assert first_report["helper_names"] == [
        "Export_breached",
        "Export_damaged",
        "Export_intact",
    ]
    damaged = {name for name in names if name.startswith(prefix + "damaged_")}
    breached = {name for name in names if name.startswith(prefix + "breached_")}
    assert damaged and breached and damaged != breached
    assert not any(name.endswith("_damaged_cyan_indicator_right") for name in names)
    assert not any(name.endswith("_breached_split_leaf_left") for name in names)
    assert any(name.endswith("_cyan_indicator_right") for name in names)
    assert any(name.endswith("_split_leaf_left") for name in names)
    assert first_report["boolean_modifiers"] == []
    assert "BOOLEAN" not in first_report["modifier_types"]
    assert first_report["triangle_count"] > 0
    assert PRESSURE_SOURCE_FIXTURE.read_bytes() == pressure_fixture_bytes
    assert PRESSURE_CONTRACT_FIXTURE.read_bytes() == pressure_contract_bytes
    assert PRESSURE_GLB_FIXTURE.read_bytes() == pressure_glb_bytes
    assert MATERIAL_FIXTURE.read_bytes() == material_fixture_bytes


def test_blender_prop_recipe_is_idempotent_and_uses_library_material_on_collision(
    tmp_path: Path,
) -> None:
    for fixture in (BLENDER, PROP_SOURCE_FIXTURE, MATERIAL_FIXTURE):
        if not fixture.is_file():
            pytest.fail(f"fixture missing: {fixture}")
    prop_fixture_bytes = PROP_SOURCE_FIXTURE.read_bytes()
    material_fixture_bytes = MATERIAL_FIXTURE.read_bytes()

    structural_root = tmp_path / "structural"
    structural_root.mkdir()
    props_root = tmp_path / "props"
    props_root.mkdir()
    source_blend = props_root / "fire_suppression_station.blend"
    shutil.copy2(PROP_SOURCE_FIXTURE, source_blend)
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

    stale_expr = (
        "import bpy; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "stale=bpy.data.materials.get('MAT_PaintedAlloyGray') or "
        "bpy.data.materials.new('MAT_PaintedAlloyGray'); "
        "stale['authored_marker']='stale-authored-material'; stale.use_fake_user=True; "
        f"bpy.ops.wm.save_as_mainfile(filepath={str(source_blend)!r})"
    )
    prepared = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", stale_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert prepared.returncode == 0, prepared.stdout + prepared.stderr

    command = _recipe_command(
        project_root=PROJECT_ROOT,
        structural_root=structural_root,
        props_root=props_root,
        asset_id="fire_suppression_station",
    )
    first = subprocess.run(command, capture_output=True, text=True, check=False)
    assert first.returncode == 0, first.stdout + first.stderr
    first_report, first_line = _report_from_stdout(first.stdout)
    second = subprocess.run(command, capture_output=True, text=True, check=False)
    assert second.returncode == 0, second.stdout + second.stderr
    second_report, second_line = _report_from_stdout(second.stdout)

    assert first_report == second_report
    assert first_line == second_line
    prefix = "FocusedNine_fire_suppression_station_"
    assert first_report["generated_object_names"]
    assert all(name.startswith(prefix) for name in first_report["generated_object_names"])
    assert first_report["helper_names"] == []
    assert first_report["boolean_modifiers"] == []
    assert "BOOLEAN" not in first_report["modifier_types"]

    proof_expr = (
        "import bpy,json; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "obj=bpy.data.objects['FocusedNine_fire_suppression_station_labeled_shape_panel']; "
        "mat=obj.data.materials[0]; stale=bpy.data.materials['MAT_PaintedAlloyGray']; "
        "print('MATERIAL_PROOF '+json.dumps({'generated':mat.name,'library':mat.get('focused_nine_source_library'),'source':mat.get('focused_nine_source_name'),'stale':stale.get('authored_marker')}))"
    )
    proof = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", proof_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proof.returncode == 0, proof.stdout + proof.stderr
    proof_line = next(line for line in proof.stdout.splitlines() if line.startswith("MATERIAL_PROOF "))
    material_proof = json.loads(proof_line.removeprefix("MATERIAL_PROOF "))
    assert material_proof["generated"] != "MAT_PaintedAlloyGray"
    assert material_proof["library"].endswith("salvage_industrial.blend")
    assert material_proof["source"] == "focused-nine:MAT_PaintedAlloyGray"
    assert material_proof["stale"] == "stale-authored-material"
    assert PROP_SOURCE_FIXTURE.read_bytes() == prop_fixture_bytes
    assert MATERIAL_FIXTURE.read_bytes() == material_fixture_bytes


def test_blender_floor_recipe_is_idempotent_and_source_scoped(tmp_path: Path) -> None:
    if not BLENDER.is_file():
        pytest.fail(f"Blender 5.2 executable missing: {BLENDER}")
    if not SOURCE_FIXTURE.is_file():
        pytest.fail(f"source fixture missing: {SOURCE_FIXTURE}")
    if not MATERIAL_FIXTURE.is_file():
        pytest.fail(f"material fixture missing: {MATERIAL_FIXTURE}")
    source_fixture_bytes = SOURCE_FIXTURE.read_bytes()

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "floor_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "floor_1x1.blend"
    shutil.copy2(SOURCE_FIXTURE, source_blend)
    material_dir = structural_root.parent / "materials"
    material_dir.mkdir(parents=True)
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")
    props_root = tmp_path / "props"
    props_root.mkdir()

    command = [
        str(BLENDER),
        "--background",
        "--factory-startup",
        "--python",
        str(PROJECT_ROOT / "tools/focused_nine_blender_recipes.py"),
        "--",
        "--project-root",
        str(PROJECT_ROOT),
        "--structural-source-root",
        str(structural_root),
        "--props-source-root",
        str(props_root),
        "--asset-id",
        "floor_1x1",
        "--overwrite-generated-only",
    ]
    first = subprocess.run(command, capture_output=True, text=True, check=False)
    assert first.returncode == 0, first.stdout + first.stderr
    first_report, first_report_line = _report_from_stdout(first.stdout)

    second = subprocess.run(command, capture_output=True, text=True, check=False)
    assert second.returncode == 0, second.stdout + second.stderr
    second_report, second_report_line = _report_from_stdout(second.stdout)

    assert first_report == second_report
    assert first_report_line == second_report_line

    assert first_report["asset_id"] == "floor_1x1"
    assert first_report["helper_names"] == [
        "Export_intact",
    ]
    assert first_report["generated_object_names"]
    assert all(
        name.startswith("FocusedNine_floor_1x1_")
        for name in first_report["generated_object_names"]
    )
    assert first_report["generated_count"] == len(first_report["generated_object_names"])
    assert first_report["triangle_count"] > 0
    assert first_report["boolean_modifiers"] == []
    assert "BOOLEAN" not in first_report["modifier_types"]
    assert SOURCE_FIXTURE.read_bytes() == source_fixture_bytes


def test_blender_compatibility_wrapper_normalizes_blender_arguments(tmp_path: Path) -> None:
    if not BLENDER.is_file():
        pytest.fail(f"Blender 5.2 executable missing: {BLENDER}")
    if not SOURCE_FIXTURE.is_file():
        pytest.fail(f"source fixture missing: {SOURCE_FIXTURE}")
    if not MATERIAL_FIXTURE.is_file():
        pytest.fail(f"material fixture missing: {MATERIAL_FIXTURE}")
    if not CONTRACT_FIXTURE.is_file():
        pytest.fail(f"contract fixture missing: {CONTRACT_FIXTURE}")
    if not SOURCE_GLB_FIXTURE.is_file():
        pytest.fail(f"source GLB fixture missing: {SOURCE_GLB_FIXTURE}")

    project_root = tmp_path / "project"
    contract_copy = project_root / (
        "data/placement/contracts/structural/ship_structural_v0/floor_1x1_contract.json"
    )
    glb_copy = project_root / (
        "assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb"
    )
    contract_copy.parent.mkdir(parents=True)
    glb_copy.parent.mkdir(parents=True)
    shutil.copy2(CONTRACT_FIXTURE, contract_copy)
    shutil.copy2(SOURCE_GLB_FIXTURE, glb_copy)
    contract_fixture_bytes = CONTRACT_FIXTURE.read_bytes()
    source_glb_fixture_bytes = SOURCE_GLB_FIXTURE.read_bytes()

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "floor_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "floor_1x1.blend"
    shutil.copy2(SOURCE_FIXTURE, source_blend)
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    material_copy = material_dir / "salvage_industrial.blend"
    shutil.copy2(MATERIAL_FIXTURE, material_copy)

    source_fixture_bytes = SOURCE_FIXTURE.read_bytes()
    material_fixture_bytes = MATERIAL_FIXTURE.read_bytes()
    command = [
        str(BLENDER),
        "--background",
        "--factory-startup",
        "--python",
        str(PROJECT_ROOT / "tools/improve_floor_geometry.py"),
        "--",
        "--project-root",
        str(project_root),
        "--source-root",
        str(structural_root),
        "--module",
        "floor_1x1",
        "--overwrite",
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)

    assert result.returncode == 0, result.stdout + result.stderr
    report, report_line = _report_from_stdout(result.stdout)
    assert report_line.startswith("FOCUSED_NINE_REPORT ")
    assert report["asset_id"] == "floor_1x1"
    assert report["generated_object_names"]
    assert all(
        name.startswith("FocusedNine_floor_1x1_")
        for name in report["generated_object_names"]
    )
    assert report["generated_count"] == len(report["generated_object_names"])
    assert report["triangle_count"] > 0
    assert report["boolean_modifiers"] == []
    assert "BOOLEAN" not in report["modifier_types"]
    assert SOURCE_FIXTURE.read_bytes() == source_fixture_bytes
    assert MATERIAL_FIXTURE.read_bytes() == material_fixture_bytes
    assert CONTRACT_FIXTURE.read_bytes() == contract_fixture_bytes
    assert SOURCE_GLB_FIXTURE.read_bytes() == source_glb_fixture_bytes
    assert source_blend.is_file()
    assert material_copy.read_bytes() == material_fixture_bytes
