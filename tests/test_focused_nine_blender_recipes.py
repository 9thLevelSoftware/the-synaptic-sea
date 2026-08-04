from __future__ import annotations

import argparse
import json
import os
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
PRESSURE_CANDIDATE_CONTRACT_FIXTURE = PROJECT_ROOT / (
    "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
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
UNDER_BUDGET_FIXTURES: dict[str, tuple[str, Path, int]] = {
    "wall_straight_1x1": (
        "structural",
        Path(
            "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/"
            "wall_straight_1x1/wall_straight_1x1.blend"
        ),
        350,
    ),
    "doorway_frame_open_1x1": (
        "structural",
        Path(
            "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/"
            "doorway_frame_open_1x1/doorway_frame_open_1x1.blend"
        ),
        350,
    ),
    "pillar_support_1x1": (
        "structural",
        Path(
            "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/"
            "pillar_support_1x1/pillar_support_1x1.blend"
        ),
        350,
    ),
    "ceiling_cap_1x1": (
        "structural",
        Path(
            "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/"
            "ceiling_cap_1x1/ceiling_cap_1x1.blend"
        ),
        350,
    ),
    "fire_suppression_station": (
        "prop",
        Path("/Volumes/Untitled/SynapticSeaAssets/meshes/source/props/fire_suppression_station.blend"),
        300,
    ),
}
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


def test_source_candidates_reject_external_hardlinks_to_runtime_files(tmp_path: Path) -> None:
    from tools.focused_nine_blender_recipes import resolve_source_path

    project_root = tmp_path / "project"
    runtime_file = project_root / "assets/imported/shared.blend"
    runtime_file.parent.mkdir(parents=True)
    runtime_file.write_bytes(b"shared inode")
    props_root = tmp_path / "props"
    props_root.mkdir()
    source = props_root / "fire_suppression_station.blend"
    try:
        os.link(runtime_file, source)
    except OSError as exc:
        pytest.skip(f"hardlinks unavailable: {exc}")

    with pytest.raises(ValueError, match="hardlink"):
        resolve_source_path(project_root, tmp_path / "structural", props_root, "fire_suppression_station")


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


class _FakeObject:
    def __init__(self, name: str, **properties: object) -> None:
        self.name = name
        self.users_collection: list[object] = []
        self._props = properties

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

    target_generated = _FakeObject(
        "FocusedNine_floor_1x1_target",
        focused_nine_generated=True,
        focused_nine_asset_id="floor_1x1",
    )
    target_authored = _FakeObject("FocusedNine_floor_1x1_authored_panel")
    wrong_asset = _FakeObject(
        "FocusedNine_floor_1x1_wrong_asset",
        focused_nine_generated=True,
        focused_nine_asset_id="wall_straight_1x1",
    )
    unrelated_generated = _FakeObject(
        "FocusedNine_floor_1x1_same_name",
        focused_nine_generated=True,
        focused_nine_asset_id="floor_1x1",
    )
    target = _FakeCollection("Geometry", [target_generated, target_authored, wrong_asset])
    unrelated = _FakeCollection("Export_intact", [unrelated_generated])

    class FakeObjects:
        def remove(self, obj: object, *, do_unlink: bool) -> None:
            assert do_unlink is False
            for collection in (target, unrelated):
                if obj in collection.objects:
                    collection.objects.remove(obj)

    fake_bpy = SimpleNamespace(
        data=SimpleNamespace(collections=_FakeCollections([target, unrelated]), objects=FakeObjects())
    )
    monkeypatch.setattr(recipes, "_BPY", fake_bpy)

    recipes.replace_generated_visuals(SimpleNamespace(name="ModuleRoot_floor_1x1"), target, "floor_1x1")

    assert target.objects == [target_authored, wrong_asset]
    assert unrelated.objects == [unrelated_generated]


def test_generated_replacement_unlinks_target_without_destroying_external_collection(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import tools.focused_nine_blender_recipes as recipes

    target = _FakeCollection("Geometry")
    external = _FakeCollection("AuthoredCollection")
    shared_generated = _FakeObject(
        "FocusedNine_floor_1x1_shared_generated",
        focused_nine_generated=True,
        focused_nine_asset_id="floor_1x1",
    )
    shared_generated.users_collection = [target, external]
    target.objects.append(shared_generated)
    external.objects.append(shared_generated)
    removed: list[object] = []

    class FakeObjects:
        def remove(self, obj: object, *, do_unlink: bool) -> None:
            assert do_unlink is False
            removed.append(obj)

    monkeypatch.setattr(
        recipes,
        "_BPY",
        SimpleNamespace(data=SimpleNamespace(objects=FakeObjects())),
    )

    recipes._replace_generated_collection(target, "floor_1x1")

    assert target.objects == []
    assert external.objects == [shared_generated]
    assert shared_generated.users_collection == [external]
    assert removed == []


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

    generated = SimpleNamespace(
        name="FocusedNine_floor_1x1_panel",
        type="MESH",
        data=SimpleNamespace(calc_loop_triangles=lambda: None, loop_triangles=()),
        material_slots=(SimpleNamespace(material=SimpleNamespace(name="MAT_Conduit")),),
        modifiers=(),
    )
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


def _prepare_material_free_source(source: Path) -> None:
    """Keep real source geometry while making a collision-free temp input."""

    expression = (
        "import bpy; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source)!r}); "
        "[obj.data.materials.clear() for obj in bpy.data.objects if obj.type == 'MESH']; "
        "[bpy.data.materials.remove(material) for material in list(bpy.data.materials)]; "
        f"result=bpy.ops.wm.save_as_mainfile(filepath={str(source)!r}); "
        "assert 'FINISHED' in result"
    )
    result = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", expression],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def _recipe_with_external_material_library(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "FOCUSED_NINE_MATERIAL_LIBRARY": str(MATERIAL_FIXTURE)},
    )


def test_blender_authored_material_collision_fails_before_mutation(tmp_path: Path) -> None:
    for fixture in (BLENDER, SOURCE_FIXTURE, MATERIAL_FIXTURE):
        if not fixture.is_file():
            pytest.fail(f"fixture missing: {fixture}")

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "floor_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "floor_1x1.blend"
    shutil.copy2(SOURCE_FIXTURE, source_blend)
    props_root = tmp_path / "props"
    props_root.mkdir()
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

    before = source_blend.read_bytes()

    result = _recipe_with_external_material_library(
        _recipe_command(
            project_root=PROJECT_ROOT,
            structural_root=structural_root,
            props_root=props_root,
            asset_id="floor_1x1",
        )
    )
    assert result.returncode == 1
    assert "refusing to rename, delete, or use" in result.stdout + result.stderr
    assert "one-time manual migration required" in result.stdout + result.stderr
    assert source_blend.read_bytes() == before

    proof_expr = (
        "import bpy,json; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "material=bpy.data.materials['MAT_PaintedAlloyGray']; "
        "print('COLLISION_PROOF '+json.dumps({'name':material.name,'marker':material.get('authored_marker'),'objects':len(bpy.data.objects)}))"
    )
    proof = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", proof_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proof.returncode == 0, proof.stdout + proof.stderr
    collision_line = next(line for line in proof.stdout.splitlines() if line.startswith("COLLISION_PROOF "))
    collision = json.loads(collision_line.removeprefix("COLLISION_PROOF "))
    assert collision["name"] == "MAT_PaintedAlloyGray"
    assert collision["marker"] is None


def test_blender_owned_suffixed_library_remnant_is_repaired_canonically(
    tmp_path: Path,
) -> None:
    for fixture in (BLENDER, SOURCE_FIXTURE, MATERIAL_FIXTURE):
        if not fixture.is_file():
            pytest.fail(f"fixture missing: {fixture}")

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "floor_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "floor_1x1.blend"
    shutil.copy2(SOURCE_FIXTURE, source_blend)
    props_root = tmp_path / "props"
    props_root.mkdir()
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

    seed_expr = (
        "import bpy; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "canonical=bpy.data.materials['MAT_PaintedAlloyGray']; "
        "[setattr(slot, 'material', None) for obj in bpy.data.objects for slot in obj.material_slots if slot.material is canonical]; "
        "bpy.data.materials.remove(canonical); "
        f"bpy.ops.wm.save_as_mainfile(filepath={str(source_blend)!r})"
    )
    seeded = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", seed_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert seeded.returncode == 0, seeded.stdout + seeded.stderr

    command = _recipe_command(
        project_root=PROJECT_ROOT,
        structural_root=structural_root,
        props_root=props_root,
        asset_id="floor_1x1",
    )
    first = _recipe_with_external_material_library(command)
    assert first.returncode == 0, first.stdout + first.stderr
    first_report, first_line = _report_from_stdout(first.stdout)
    second = _recipe_with_external_material_library(command)
    assert second.returncode == 0, second.stdout + second.stderr
    second_report, second_line = _report_from_stdout(second.stdout)
    assert first_report == second_report
    assert first_line == second_line
    assert first_report["material_names"] == [
        "MAT_Conduit",
        "MAT_PaintedAlloyGray",
        "MAT_WarningStripe",
    ]

    proof_expr = (
        "import bpy,json; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "print('REMNANT_PROOF '+json.dumps({'canonical':bpy.data.materials.get('MAT_PaintedAlloyGray') is not None,'suffixed':bpy.data.materials.get('MAT_PaintedAlloyGray.001') is not None,'source':bpy.data.materials['MAT_PaintedAlloyGray'].get('focused_nine_source_name'),'library':bpy.data.materials['MAT_PaintedAlloyGray'].get('focused_nine_source_library')}))"
    )
    proof = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", proof_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proof.returncode == 0, proof.stdout + proof.stderr
    proof_line = next(line for line in proof.stdout.splitlines() if line.startswith("REMNANT_PROOF "))
    remnant = json.loads(proof_line.removeprefix("REMNANT_PROOF "))
    assert remnant == {
        "canonical": True,
        "suffixed": False,
        "source": "focused-nine:MAT_PaintedAlloyGray",
        "library": str(MATERIAL_FIXTURE),
    }

    destination = tmp_path / "assets/_staging/focused_nine/structural/floor_1x1"
    glb = _export_recipe_result_for_evidence(
        source=source_blend,
        asset_id="floor_1x1",
        kind="structural",
        destination=destination,
    )
    from tools import focused_nine_evidence

    evidence = focused_nine_evidence.inspect_staged_glb(glb, BLENDER)
    assert evidence["material_names"] == [
        "MAT_Conduit",
        "MAT_PaintedAlloyGray",
        "MAT_WarningStripe",
    ]


def test_blender_verified_remnant_with_wrong_module_context_is_rejected(
    tmp_path: Path,
) -> None:
    for fixture in (BLENDER, SOURCE_FIXTURE, MATERIAL_FIXTURE):
        if not fixture.is_file():
            pytest.fail(f"fixture missing: {fixture}")

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "floor_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "floor_1x1.blend"
    shutil.copy2(SOURCE_FIXTURE, source_blend)
    props_root = tmp_path / "props"
    props_root.mkdir()
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

    seed_expr = (
        "import bpy; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "canonical=bpy.data.materials['MAT_PaintedAlloyGray']; "
        "[setattr(slot, 'material', None) for obj in bpy.data.objects for slot in obj.material_slots if slot.material is canonical]; "
        "bpy.data.materials.remove(canonical); "
        "wrong_root=bpy.data.objects.new('ModuleRoot_wall_straight_1x1', None); "
        "bpy.context.scene.collection.objects.link(wrong_root); "
        "generated=bpy.data.objects['FocusedNine_floor_1x1_floor_panel']; generated.parent=wrong_root; "
        f"bpy.ops.wm.save_as_mainfile(filepath={str(source_blend)!r})"
    )
    seeded = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", seed_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert seeded.returncode == 0, seeded.stdout + seeded.stderr
    before = source_blend.read_bytes()

    result = _recipe_with_external_material_library(
        _recipe_command(
            project_root=PROJECT_ROOT,
            structural_root=structural_root,
            props_root=props_root,
            asset_id="floor_1x1",
        )
    )
    assert result.returncode == 1, result.stdout + result.stderr
    assert "has an authored user" in result.stdout + result.stderr
    assert source_blend.read_bytes() == before


def test_blender_owned_canonical_legacy_material_is_repaired_from_library(
    tmp_path: Path,
) -> None:
    for fixture in (BLENDER, SOURCE_FIXTURE, MATERIAL_FIXTURE):
        if not fixture.is_file():
            pytest.fail(f"fixture missing: {fixture}")

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "floor_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "floor_1x1.blend"
    shutil.copy2(SOURCE_FIXTURE, source_blend)
    props_root = tmp_path / "props"
    props_root.mkdir()
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

    seed_expr = (
        "import bpy; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "canonical=bpy.data.materials['MAT_PaintedAlloyGray']; "
        "[setattr(slot, 'material', None) for obj in bpy.data.objects for slot in obj.material_slots if slot.material is canonical]; "
        "bpy.data.materials.remove(canonical); "
        "legacy=bpy.data.materials['MAT_PaintedAlloyGray.001']; legacy.name='MAT_PaintedAlloyGray'; "
        "[legacy.__delitem__(key) for key in ('focused_nine_source_library', 'focused_nine_source_name') if key in legacy]; "
        f"bpy.ops.wm.save_as_mainfile(filepath={str(source_blend)!r})"
    )
    seeded = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", seed_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert seeded.returncode == 0, seeded.stdout + seeded.stderr

    result = _recipe_with_external_material_library(
        _recipe_command(
            project_root=PROJECT_ROOT,
            structural_root=structural_root,
            props_root=props_root,
            asset_id="floor_1x1",
        )
    )
    assert result.returncode == 0, result.stdout + result.stderr
    report, _report_line = _report_from_stdout(result.stdout)
    assert report["material_names"] == [
        "MAT_Conduit",
        "MAT_PaintedAlloyGray",
        "MAT_WarningStripe",
    ]

    proof_expr = (
        "import bpy,json; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "generated=bpy.data.objects['FocusedNine_floor_1x1_floor_panel']; mat=generated.data.materials[0]; "
        "legacy=bpy.data.materials.get('MAT_PaintedAlloyGray.legacy'); "
        "print('CANONICAL_LEGACY_PROOF '+json.dumps({'generated':mat.name,'library':mat.get('focused_nine_source_library'),'source':mat.get('focused_nine_source_name'),'legacy_preserved':legacy is not None,'legacy_fake_user':legacy.use_fake_user if legacy else None,'legacy_users':legacy.users if legacy else None,'legacy_mesh_users':sum(1 for obj in bpy.data.objects if obj.type == 'MESH' for slot in obj.material_slots if slot.material is legacy)}))"
    )
    proof = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", proof_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proof.returncode == 0, proof.stdout + proof.stderr
    proof_line = next(line for line in proof.stdout.splitlines() if line.startswith("CANONICAL_LEGACY_PROOF "))
    canonical_legacy = json.loads(proof_line.removeprefix("CANONICAL_LEGACY_PROOF "))
    assert canonical_legacy == {
        "generated": "MAT_PaintedAlloyGray",
        "library": str(MATERIAL_FIXTURE),
        "source": "focused-nine:MAT_PaintedAlloyGray",
        "legacy_preserved": True,
        "legacy_fake_user": True,
        "legacy_users": 1,
        "legacy_mesh_users": 0,
    }


def test_blender_floor_recipe_emits_exact_material_names_and_exports(tmp_path: Path) -> None:
    for fixture in (BLENDER, SOURCE_FIXTURE, MATERIAL_FIXTURE, CONTRACT_FIXTURE):
        if not fixture.is_file():
            pytest.fail(f"fixture missing: {fixture}")

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "floor_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "floor_1x1.blend"
    shutil.copy2(SOURCE_FIXTURE, source_blend)
    _prepare_material_free_source(source_blend)
    props_root = tmp_path / "props"
    props_root.mkdir()
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

    command = _recipe_command(
        project_root=PROJECT_ROOT,
        structural_root=structural_root,
        props_root=props_root,
        asset_id="floor_1x1",
    )
    first = subprocess.run(command, capture_output=True, text=True, check=False)
    assert first.returncode == 0, first.stdout + first.stderr
    first_report, first_line = _report_from_stdout(first.stdout)
    second = subprocess.run(command, capture_output=True, text=True, check=False)
    assert second.returncode == 0, second.stdout + second.stderr
    second_report, second_line = _report_from_stdout(second.stdout)
    assert first_report == second_report
    assert first_line == second_line
    assert first_report["material_names"]
    assert set(first_report["material_names"]).issubset(
        {"MAT_PaintedAlloyGray", "MAT_WarningStripe", "MAT_ReactorGlow", "MAT_Conduit"}
    )
    assert all("." not in name for name in first_report["material_names"])

    destination = tmp_path / "assets/_staging/focused_nine/structural/floor_1x1"
    glb = _export_recipe_result_for_evidence(
        source=source_blend,
        asset_id="floor_1x1",
        kind="structural",
        destination=destination,
    )
    from tools import focused_nine_evidence

    evidence = focused_nine_evidence.inspect_staged_glb(glb, BLENDER)
    assert evidence["material_names"] == first_report["material_names"]
    assert set(evidence["material_names"]).issubset(
        {"MAT_PaintedAlloyGray", "MAT_WarningStripe", "MAT_ReactorGlow", "MAT_Conduit"}
    )
    assert all("." not in name for name in evidence["material_names"])


def test_blender_pressure_door_roles_are_distinct_and_idempotent(tmp_path: Path) -> None:
    for fixture in (
        BLENDER,
        PRESSURE_SOURCE_FIXTURE,
        PRESSURE_CONTRACT_FIXTURE,
        PRESSURE_CANDIDATE_CONTRACT_FIXTURE,
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
    _prepare_material_free_source(source_blend)
    props_root = tmp_path / "props"
    props_root.mkdir()
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

    pressure_project = tmp_path / "pressure-project"
    pressure_contract = pressure_project / (
        "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
    )
    pressure_glb = pressure_project / (
        "assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb"
    )
    pressure_contract.parent.mkdir(parents=True)
    pressure_glb.parent.mkdir(parents=True)
    shutil.copy2(PRESSURE_CANDIDATE_CONTRACT_FIXTURE, pressure_contract)
    shutil.copy2(PRESSURE_GLB_FIXTURE, pressure_glb)
    prepare_pressure_source_expr = (
        "import bpy; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "root=bpy.data.objects.get('ModuleRoot_doorway_frame_open_1x1'); "
        "assert root is not None; root.name='ModuleRoot_pressure_door_1x1'; "
        "intact=bpy.data.collections.get('Export_intact'); "
        "assert intact is not None; intact['module_id']='pressure_door_1x1'; "
        f"bpy.ops.wm.save_as_mainfile(filepath={str(source_blend)!r})"
    )
    prepared = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", prepare_pressure_source_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert prepared.returncode == 0, prepared.stdout + prepared.stderr

    command = _recipe_command(
        project_root=pressure_project,
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


def test_blender_prop_recipe_is_idempotent_with_exact_library_material_names(
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
    _prepare_material_free_source(source_blend)
    material_dir = tmp_path / "materials"
    material_dir.mkdir()
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")

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
    from tools.focused_nine_blender_recipes import REQUIRED_MATERIAL_NAMES

    assert first_report["generated_object_names"]
    assert all(
        name.startswith("FocusedNine_fire_suppression_station_")
        for name in first_report["generated_object_names"]
    )
    assert set(first_report["material_names"]).issubset(set(REQUIRED_MATERIAL_NAMES))
    assert all("." not in name for name in first_report["material_names"])

    proof_expr = (
        "import bpy,json; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "obj=bpy.data.objects['FocusedNine_fire_suppression_station_labeled_shape_panel']; "
        "mat=obj.data.materials[0]; "
        "print('MATERIAL_PROOF '+json.dumps({'generated':mat.name,'library':mat.get('focused_nine_source_library'),'source':mat.get('focused_nine_source_name'),'generated_marker':obj.get('focused_nine_generated'),'generated_asset':obj.get('focused_nine_asset_id')}))"
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
    assert material_proof["generated"] in REQUIRED_MATERIAL_NAMES
    assert "." not in material_proof["generated"]
    assert material_proof["library"].endswith("salvage_industrial.blend")
    assert material_proof["source"] == f"focused-nine:{material_proof['generated']}"
    assert material_proof["generated_marker"] is True
    assert material_proof["generated_asset"] == "fire_suppression_station"
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
    _prepare_material_free_source(source_blend)
    material_dir = structural_root.parent / "materials"
    material_dir.mkdir(parents=True)
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")
    props_root = tmp_path / "props"
    props_root.mkdir()

    seed_expr = (
        "import bpy; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "geometry=bpy.data.collections.get('Geometry') or bpy.data.collections.new('Geometry'); "
        "bpy.context.scene.collection.children.link(geometry) if geometry.name not in {child.name for child in bpy.context.scene.collection.children} else None; "
        "authored=bpy.data.objects.new('FocusedNine_floor_1x1_authored_panel', None); geometry.objects.link(authored); "
        "authored['authored_marker']='preserve'; "
        "stale=bpy.data.objects.new('FocusedNine_floor_1x1_stale_generated', None); geometry.objects.link(stale); "
        "stale['focused_nine_generated']=True; stale['focused_nine_asset_id']='floor_1x1'; "
        f"bpy.ops.wm.save_as_mainfile(filepath={str(source_blend)!r})"
    )
    prepared = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", seed_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert prepared.returncode == 0, prepared.stdout + prepared.stderr

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

    proof_expr = (
        "import bpy,json; "
        f"bpy.ops.wm.open_mainfile(filepath={str(source_blend)!r}); "
        "authored=bpy.data.objects.get('FocusedNine_floor_1x1_authored_panel'); "
        "stale=bpy.data.objects.get('FocusedNine_floor_1x1_stale_generated'); "
        "generated=bpy.data.objects['FocusedNine_floor_1x1_floor_panel']; "
        "print('OWNERSHIP_PROOF '+json.dumps({'authored':authored.get('authored_marker') if authored else None,'stale':stale is not None,'generated':generated.get('focused_nine_generated'),'asset':generated.get('focused_nine_asset_id')}))"
    )
    proof = subprocess.run(
        [str(BLENDER), "--background", "--factory-startup", "--python-expr", proof_expr],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proof.returncode == 0, proof.stdout + proof.stderr
    proof_line = next(line for line in proof.stdout.splitlines() if line.startswith("OWNERSHIP_PROOF "))
    ownership_proof = json.loads(proof_line.removeprefix("OWNERSHIP_PROOF "))
    assert ownership_proof == {
        "authored": "preserve",
        "stale": False,
        "generated": True,
        "asset": "floor_1x1",
    }
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
    _prepare_material_free_source(source_blend)
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


def _export_recipe_result_for_evidence(
    *, source: Path, asset_id: str, kind: str, destination: Path
) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    if kind == "structural":
        command = [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python",
            str(PROJECT_ROOT / "tools/export_structural_glb.py"),
            "--",
            "--blend-path",
            str(source),
            "--staging-dir",
            str(destination),
            "--module",
            asset_id,
        ]
    else:
        output = destination / f"{asset_id}.glb"
        expression = (
            "import bpy; "
            f"result=bpy.ops.wm.open_mainfile(filepath={str(source)!r}); "
            "assert 'FINISHED' in result, 'prop source open failed'; "
            f"collection=bpy.data.collections.get({f'FocusedNine_{asset_id}_Generated'!r}); "
            "assert collection is not None, 'generated prop collection missing'; "
            "bpy.ops.object.select_all(action='DESELECT'); "
            "objects=[obj for obj in collection.objects if obj.type == 'MESH']; "
            "assert objects, 'generated prop collection has no mesh'; "
            "[obj.select_set(True) for obj in objects]; "
            "bpy.context.view_layer.objects.active=objects[0]; "
            f"result=bpy.ops.export_scene.gltf(filepath={str(output)!r}, export_format='GLB', export_apply=True, use_selection=True); "
            "assert 'CANCELLED' not in result, 'prop GLB export cancelled'"
        )
        command = [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python-expr",
            expression,
        ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stdout + result.stderr
    output = destination / f"{asset_id}.glb"
    assert output.is_file() and output.stat().st_size > 0
    return output


def test_blender_under_budget_recipes_meet_gameplay_evidence_minima(tmp_path: Path) -> None:
    from tools import focused_nine_evidence

    for fixture in (BLENDER, MATERIAL_FIXTURE, *(item[1] for item in UNDER_BUDGET_FIXTURES.values())):
        if not fixture.is_file():
            pytest.fail(f"fixture missing: {fixture}")

    structural_root = tmp_path / "structural"
    props_root = tmp_path / "props"
    material_dir = tmp_path / "materials"
    props_root.mkdir(parents=True)
    material_dir.mkdir(parents=True)
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")
    fixture_bytes = {asset_id: fixture.read_bytes() for asset_id, (_, fixture, _) in UNDER_BUDGET_FIXTURES.items()}

    measured: dict[str, int] = {}
    for asset_id, (kind, fixture, minimum) in UNDER_BUDGET_FIXTURES.items():
        if kind == "structural":
            source_dir = structural_root / asset_id
            source_dir.mkdir(parents=True)
            source = source_dir / f"{asset_id}.blend"
        else:
            props_root.mkdir(parents=True, exist_ok=True)
            source = props_root / f"{asset_id}.blend"
        shutil.copy2(fixture, source)
        _prepare_material_free_source(source)

        command = _recipe_command(
            project_root=PROJECT_ROOT,
            structural_root=structural_root,
            props_root=props_root,
            asset_id=asset_id,
        )
        recipe = subprocess.run(command, capture_output=True, text=True, check=False)
        assert recipe.returncode == 0, recipe.stdout + recipe.stderr
        report, _report_line = _report_from_stdout(recipe.stdout)
        assert report["boolean_modifiers"] == []
        assert "BOOLEAN" not in report["modifier_types"]
        assert all(name.startswith(f"FocusedNine_{asset_id}_") for name in report["generated_object_names"])

        stage = tmp_path / "assets/_staging/focused_nine" / kind / asset_id
        glb = _export_recipe_result_for_evidence(
            source=source,
            asset_id=asset_id,
            kind=kind,
            destination=stage,
        )
        record = focused_nine_evidence.inspect_staged_glb(glb, BLENDER)
        maximum = 1500 if kind == "structural" else 1200
        assert focused_nine_evidence.validate_evidence(record, minimum, maximum) == []
        measured[asset_id] = record["triangle_count"]

    assert set(measured) == set(UNDER_BUDGET_FIXTURES)
    for asset_id, (_, fixture, _) in UNDER_BUDGET_FIXTURES.items():
        assert fixture.read_bytes() == fixture_bytes[asset_id]
