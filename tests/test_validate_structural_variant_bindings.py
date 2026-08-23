from __future__ import annotations

import contextlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from typing import Iterator

from tools import validate_structural_variant_bindings


PROJECT_ROOT = Path(__file__).resolve().parents[1]
STRUCTURAL_ROOT = Path("assets/imported/structural/ship_structural_v0")
WRAPPER_ROOT = Path("scenes/wrappers/structural/ship_structural_v0")
RESOLVER_PATH = Path("scripts/systems/integrity_visual_resolver.gd")
VARIANT_IDS = (
    "floor_1x1",
    "floor_2x1",
    "corridor_floor_1x1",
    "corridor_floor_1x2",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
)


def _copy_path(source_root: Path, destination_root: Path, relative: Path) -> None:
    source = source_root / relative
    destination = destination_root / relative
    if source.is_dir():
        shutil.copytree(source, destination)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def _populate_structural_families(root: Path) -> None:
    for asset_id in VARIANT_IDS:
        for relative in (
            STRUCTURAL_ROOT / asset_id,
            WRAPPER_ROOT / f"{asset_id}.tscn",
            WRAPPER_ROOT / f"{asset_id}.manifest.json",
            WRAPPER_ROOT / f"{asset_id}.input.json",
        ):
            _copy_path(PROJECT_ROOT, root, relative)
    _copy_path(PROJECT_ROOT, root, RESOLVER_PATH)


@contextlib.contextmanager
def copied_structural_fixture() -> Iterator[Path]:
    with tempfile.TemporaryDirectory(prefix="structural-variant-test-") as temporary:
        root = Path(temporary) / "project"
        root.mkdir()
        _populate_structural_families(root)
        yield root


@contextlib.contextmanager
def copied_structural_fixture_without(filename: str) -> Iterator[Path]:
    with copied_structural_fixture() as root:
        candidate = root / STRUCTURAL_ROOT / "floor_1x1" / filename
        candidate.unlink()
        yield root


@contextlib.contextmanager
def copied_structural_fixture_with_wrapper_ref(
    asset_id: str, node_name: str, ref_name: str
) -> Iterator[Path]:
    with copied_structural_fixture() as root:
        scene_path = root / WRAPPER_ROOT / f"{asset_id}.tscn"
        scene = scene_path.read_text(encoding="utf-8")
        damaged_path = (
            f"res://{STRUCTURAL_ROOT.as_posix()}/{asset_id}/{asset_id}_damaged.glb"
        )
        replacement_path = (
            f"res://{STRUCTURAL_ROOT.as_posix()}/{asset_id}/{ref_name}"
        )
        marker = f'parent="Visual" instance=ExtResource("2_visual_damaged")'
        if node_name != "VisualInstance_Damaged":
            raise AssertionError(f"unsupported fixture node: {node_name}")
        if damaged_path not in scene or marker not in scene:
            raise AssertionError("canonical damaged wrapper reference not found")
        scene_path.write_text(scene.replace(damaged_path, replacement_path, 1), encoding="utf-8")
        yield root


@contextlib.contextmanager
def copied_structural_fixture_without_node(asset_id: str, node_name: str) -> Iterator[Path]:
    with copied_structural_fixture() as root:
        scene_path = root / WRAPPER_ROOT / f"{asset_id}.tscn"
        scene = scene_path.read_text(encoding="utf-8")
        manifest_path = root / WRAPPER_ROOT / f"{asset_id}.manifest.json"
        input_path = root / WRAPPER_ROOT / f"{asset_id}.input.json"
        canonical_name = "Anchor_SOCK_floor_edge_north_01"
        if node_name != "Anchor_SOCK_N":
            raise AssertionError(f"unsupported fixture node: {node_name}")
        scene = "\n".join(
            line for line in scene.splitlines() if f'name="{canonical_name}"' not in line
        ) + "\n"
        scene_path.write_text(scene, encoding="utf-8")
        for path in (manifest_path, input_path):
            document = json.loads(path.read_text(encoding="utf-8"))
            anchors = document["asset"]["anchors"]["exposed"]
            for anchor in anchors:
                if anchor["name"] == canonical_name:
                    anchor["name"] = node_name
            path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        yield root


@contextlib.contextmanager
def copied_non_variant_structural_fixture(asset_id: str) -> Iterator[Path]:
    with tempfile.TemporaryDirectory(prefix="structural-nonvariant-test-") as temporary:
        root = Path(temporary) / "project"
        root.mkdir()
        _populate_structural_families(root)
        for relative in (
            STRUCTURAL_ROOT / asset_id,
            WRAPPER_ROOT / f"{asset_id}.tscn",
            WRAPPER_ROOT / f"{asset_id}.manifest.json",
            WRAPPER_ROOT / f"{asset_id}.input.json",
        ):
            _copy_path(PROJECT_ROOT, root, relative)
        yield root


def run_structural_audit(project_root: Path) -> list[str]:
    return validate_structural_variant_bindings.validate_project(project_root)


class ValidateStructuralVariantBindingsTests(unittest.TestCase):
    def test_baseline_structural_fixture_is_accepted(self) -> None:
        with copied_structural_fixture() as project_root:
            self.assertEqual([], run_structural_audit(project_root))

    def test_missing_breached_variant_is_rejected(self) -> None:
        with copied_structural_fixture_without("floor_1x1_breached.glb") as project_root:
            self.assertIn("missing breached GLB: floor_1x1", run_structural_audit(project_root))

    def test_wrapper_path_that_differs_from_variant_path_is_rejected(self) -> None:
        with copied_structural_fixture_with_wrapper_ref(
            "floor_1x1", "VisualInstance_Damaged", "floor_1x1.glb"
        ) as project_root:
            self.assertIn(
                "damaged wrapper path does not match damaged variant: floor_1x1",
                run_structural_audit(project_root),
            )

    def test_missing_wrapper_socket_anchor_is_rejected(self) -> None:
        with copied_structural_fixture_without_node("floor_1x1", "Anchor_SOCK_N") as project_root:
            self.assertIn(
                "missing required socket anchor Anchor_SOCK_N: floor_1x1",
                run_structural_audit(project_root),
            )

    def test_non_variant_wrapper_is_ignored_when_it_has_no_integrity_triplet(self) -> None:
        with copied_non_variant_structural_fixture("wall_end_cap") as project_root:
            self.assertEqual([], run_structural_audit(project_root))

    def test_nested_variant_node_is_rejected(self) -> None:
        with copied_structural_fixture() as project_root:
            scene_path = root_scene = project_root / WRAPPER_ROOT / "floor_1x1.tscn"
            scene = scene_path.read_text(encoding="utf-8")
            scene = scene.replace(
                '[node name="VisualInstance_Damaged" parent="Visual" instance=ExtResource("2_visual_damaged")]',
                '[node name="VisualInstance_Damaged" parent="Visual/Nested" instance=ExtResource("2_visual_damaged")]',
            )
            root_scene.write_text(scene, encoding="utf-8")
            self.assertIn(
                "VisualInstance_Damaged must be a direct child of Visual: floor_1x1",
                run_structural_audit(project_root),
            )

    def test_missing_resolver_variant_name_is_rejected(self) -> None:
        with copied_structural_fixture() as project_root:
            resolver_path = project_root / RESOLVER_PATH
            resolver = resolver_path.read_text(encoding="utf-8")
            resolver_path.write_text(resolver.replace('"VisualInstance_Breached"', '"VisualInstance_Breached_Old"'), encoding="utf-8")
            self.assertIn(
                "IntegrityVisualResolver missing node name VisualInstance_Breached: floor_1x1",
                run_structural_audit(project_root),
            )


if __name__ == "__main__":
    unittest.main()
