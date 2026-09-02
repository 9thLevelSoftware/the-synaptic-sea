from __future__ import annotations

import contextlib
import inspect
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Iterator

from tools import generate_prop_sidecars, validate_prop_visual_bindings


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROPS_ROOT = Path("assets/imported/props")

GOVERNED_PROP_FILES = (
    "assets/imported/props/components/air_recycler_unit.glb",
    "assets/imported/props/components/air_recycler_unit.sidecar.json",
    "assets/imported/props/components/conduit_run.glb",
    "assets/imported/props/components/conduit_run.sidecar.json",
    "assets/imported/props/components/console_generic.glb",
    "assets/imported/props/components/console_generic.sidecar.json",
    "assets/imported/props/components/hull_plating.glb",
    "assets/imported/props/components/hull_plating.sidecar.json",
    "assets/imported/props/components/locker_wall.glb",
    "assets/imported/props/components/locker_wall.sidecar.json",
    "assets/imported/props/components/machinery_block.glb",
    "assets/imported/props/components/machinery_block.sidecar.json",
    "assets/imported/props/components/nav_console.glb",
    "assets/imported/props/components/nav_console.sidecar.json",
    "assets/imported/props/components/pump_assembly.glb",
    "assets/imported/props/components/pump_assembly.sidecar.json",
    "assets/imported/props/components/reactor_console.glb",
    "assets/imported/props/components/reactor_console.sidecar.json",
    "assets/imported/props/components/sensor_rack.glb",
    "assets/imported/props/components/sensor_rack.sidecar.json",
    "assets/imported/props/components/thruster_control.glb",
    "assets/imported/props/components/thruster_control.sidecar.json",
    "assets/imported/props/dressing/cable_tray.glb",
    "assets/imported/props/dressing/cable_tray.sidecar.json",
    "assets/imported/props/dressing/cargo_pallet.glb",
    "assets/imported/props/dressing/cargo_pallet.sidecar.json",
    "assets/imported/props/dressing/emergency_wall.glb",
    "assets/imported/props/dressing/emergency_wall.sidecar.json",
    "assets/imported/props/dressing/focused_work_lamp.glb",
    "assets/imported/props/dressing/focused_work_lamp.sidecar.json",
    "assets/imported/props/dressing/generic_crate.glb",
    "assets/imported/props/dressing/generic_crate.sidecar.json",
    "assets/imported/props/dressing/generic_locker.glb",
    "assets/imported/props/dressing/generic_locker.sidecar.json",
    "assets/imported/props/dressing/maintenance_bench.glb",
    "assets/imported/props/dressing/maintenance_bench.sidecar.json",
    "assets/imported/props/dressing/medical_cabinet.glb",
    "assets/imported/props/dressing/medical_cabinet.sidecar.json",
    "assets/imported/props/dressing/practical_overhead.glb",
    "assets/imported/props/dressing/practical_overhead.sidecar.json",
    "assets/imported/props/dressing/salvage_cart.glb",
    "assets/imported/props/dressing/salvage_cart.sidecar.json",
    "assets/imported/props/dressing/service_rack.glb",
    "assets/imported/props/dressing/service_rack.sidecar.json",
    "assets/imported/props/objectives/medbay_terminal.glb",
    "assets/imported/props/objectives/medbay_terminal.sidecar.json",
    "assets/imported/props/objectives/reactor_control_panel.glb",
    "assets/imported/props/objectives/reactor_control_panel.sidecar.json",
    "assets/imported/props/objectives/repair_junction.glb",
    "assets/imported/props/objectives/repair_junction.sidecar.json",
    "assets/imported/props/objectives/supply_cache.glb",
    "assets/imported/props/objectives/supply_cache.sidecar.json",
)
MAX_CURATED_PROP_BYTES = 2_000_000
CURATED_PROP_FILES = GOVERNED_PROP_FILES
CURATED_TOOL_FILES = (
    "tools/generate_prop_sidecars.py",
    "tools/prop_visual_metadata.py",
    "tools/validate_prop_visual_bindings.py",
)
COMPONENT_CATALOG_FILE = "data/components/component_catalog.json"
GAMEPLAY_SLICE_FILE = "data/procgen/fixture/gameplay_slice.json"
AUTHORITATIVE_COMPONENT_IDS = (
    "air_recycler_unit",
    "conduit_run",
    "console_generic",
    "hull_plating",
    "locker_wall",
    "machinery_block",
    "nav_console",
    "pump_assembly",
    "reactor_console",
    "sensor_rack",
    "thruster_control",
)
OBJECTIVE_PLACEMENT_IDS = (
    "medbay_terminal",
    "reactor_control_panel",
    "maintenance_breaker_panel",
    "cargo_supply_cache",
    "supply_cache",
)


def _copy_file(source_root: Path, destination_root: Path, relative: str) -> None:
    source = source_root / relative
    if not source.is_file():
        raise AssertionError(f"fixture source must be a regular file: {relative}")
    destination = destination_root / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def _write_fixture_json(root: Path, relative: str, value: object) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    _write_json(path, value)


@contextlib.contextmanager
def copied_project() -> Iterator[Path]:
    with tempfile.TemporaryDirectory(prefix="prop-binding-test-") as temporary:
        root = Path(temporary) / "project"
        root.mkdir()
        for relative in (*CURATED_PROP_FILES, *CURATED_TOOL_FILES, COMPONENT_CATALOG_FILE):
            _copy_file(PROJECT_ROOT, root, relative)
        _copy_file(PROJECT_ROOT, root, "data/props/visual_bindings.generated.json")
        _write_fixture_json(
            root,
            GAMEPLAY_SLICE_FILE,
            {
                "schema_version": "1.1.0",
                "document_kind": "ship_gameplay_slice",
                "objectives": [{"placement_id": placement_id} for placement_id in OBJECTIVE_PLACEMENT_IDS],
            },
        )
        yield root


@contextlib.contextmanager
def copied_project_without(relative: str) -> Iterator[Path]:
    with copied_project() as root:
        (root / relative).unlink()
        yield root


def _load_sidecar(root: Path, asset_id: str) -> tuple[Path, dict]:
    matches = sorted((root / PROPS_ROOT).glob(f"*/{asset_id}.sidecar.json"))
    if len(matches) != 1:
        raise AssertionError(f"expected one sidecar for {asset_id}, found {matches}")
    path = matches[0]
    return path, json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")


@contextlib.contextmanager
def copied_project_with_sidecar_value(asset_id: str, path: list[str], value: object) -> Iterator[Path]:
    with copied_project() as root:
        sidecar_path, sidecar = _load_sidecar(root, asset_id)
        cursor = sidecar
        for key in path[:-1]:
            cursor = cursor[key]
        cursor[path[-1]] = value
        _write_json(sidecar_path, sidecar)
        yield root


@contextlib.contextmanager
def copied_project_without_asset(group: str, asset_id: str) -> Iterator[Path]:
    with copied_project() as root:
        (root / PROPS_ROOT / group / f"{asset_id}.glb").unlink()
        (root / PROPS_ROOT / group / f"{asset_id}.sidecar.json").unlink()
        yield root


@contextlib.contextmanager
def copied_project_with_objective_alias(asset_id: str, alias: str) -> Iterator[Path]:
    with copied_project() as root:
        sidecar_path, sidecar = _load_sidecar(root, asset_id)
        sidecar["binding"]["ids"] = [*sidecar["binding"]["ids"], alias]
        _write_json(sidecar_path, sidecar)
        yield root


@contextlib.contextmanager
def copied_project_with_stale_index(group: str, asset_id: str) -> Iterator[Path]:
    with copied_project() as root:
        index_path = root / "data/props/visual_bindings.generated.json"
        index = json.loads(index_path.read_text(encoding="utf-8"))
        index[group][asset_id]["visual_scene_path"] = "res://assets/imported/props/stale.glb"
        _write_json(index_path, index)
        yield root


@contextlib.contextmanager
def copied_project_with_extension(asset_id: str, extensions: dict) -> Iterator[Path]:
    with copied_project() as root:
        sidecar_path, sidecar = _load_sidecar(root, asset_id)
        sidecar["extensions"] = extensions
        _write_json(sidecar_path, sidecar)
        yield root


def run_validator(project_root: Path) -> str:
    result = subprocess.run(
        [
            sys.executable,
            str(project_root / "tools/validate_prop_visual_bindings.py"),
            "--project-root",
            str(project_root),
            "--check-index",
        ],
        cwd=project_root,
        capture_output=True,
        text=True,
        check=False,
    )
    return "\n".join(part for part in (result.stdout, result.stderr) if part)


def refresh_derived(project_root: Path, asset_id: str) -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(project_root / "tools/generate_prop_sidecars.py"),
            "--project-root",
            str(project_root),
            "--refresh-derived",
            "--asset-id",
            asset_id,
            "--write-index",
        ],
        cwd=project_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"refresh failed ({result.returncode}): {result.stdout}\n{result.stderr}")


def run_generator(project_root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(project_root / "tools/generate_prop_sidecars.py"),
            "--project-root",
            str(project_root),
            *arguments,
        ],
        cwd=project_root,
        capture_output=True,
        text=True,
        check=False,
    )


class ValidatePropVisualBindingsTests(unittest.TestCase):
    def test_fixture_plan_is_explicitly_curated_and_bounded(self) -> None:
        helper_source = inspect.getsource(copied_project)
        self.assertNotIn("_copy_path(", helper_source)
        self.assertNotIn("copytree(", helper_source)
        self.assertNotIn("assets/imported/props", helper_source)

        manifest = globals().get("CURATED_PROP_FILES")
        if manifest is None:
            self.fail("copied_project must declare CURATED_PROP_FILES")
        self.assertEqual(tuple(manifest), GOVERNED_PROP_FILES)
        self.assertEqual(len(manifest), 52)
        self.assertEqual(len(set(manifest)), 52)
        self.assertTrue(all("/ithappy/" not in f"/{relative}" for relative in manifest))
        self.assertTrue(all(not relative.endswith(".glb.import") for relative in manifest))
        missing = [relative for relative in manifest if not (PROJECT_ROOT / relative).is_file()]
        self.assertEqual(missing, [])
        total_bytes = sum((PROJECT_ROOT / relative).stat().st_size for relative in manifest)
        self.assertLessEqual(total_bytes, MAX_CURATED_PROP_BYTES)

    def test_validator_rejects_missing_sidecar(self) -> None:
        with copied_project_without("assets/imported/props/components/reactor_console.sidecar.json") as project_root:
            self.assertIn("missing sidecar", run_validator(project_root))

    def test_validator_rejects_stale_hash(self) -> None:
        with copied_project_with_sidecar_value("reactor_console", ["source", "sha256"], "0" * 64) as project_root:
            self.assertIn("sha256 mismatch", run_validator(project_root))

    def test_validator_rejects_unknown_component_id(self) -> None:
        with copied_project_with_sidecar_value("reactor_console", ["binding", "ids"], ["unknown_component"]) as project_root:
            self.assertIn("unknown component_id: unknown_component", run_validator(project_root))

    def test_validator_rejects_duplicate_objective_placement_binding(self) -> None:
        with copied_project_with_objective_alias("medbay_terminal", "reactor_control_panel") as project_root:
            self.assertIn("duplicate gameplay_placement_id: reactor_control_panel", run_validator(project_root))

    def test_validator_rejects_stale_generated_index(self) -> None:
        with copied_project_with_stale_index("components", "reactor_console") as project_root:
            self.assertIn("generated index differs from sidecars", run_validator(project_root))

    def test_generator_rejects_invalid_sidecar_before_writing_index(self) -> None:
        with copied_project_with_sidecar_value("reactor_console", ["source", "sha256"], "0" * 64) as project_root:
            index_path = project_root / "data/props/visual_bindings.generated.json"
            original_index = index_path.read_bytes()
            result = run_generator(project_root, "--write-index")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("reactor_console.sidecar.json", result.stderr)
            self.assertEqual(index_path.read_bytes(), original_index)

    def test_generator_rejects_unknown_authoritative_mapping_before_writing_index(self) -> None:
        with copied_project_with_sidecar_value("reactor_console", ["binding", "ids"], ["unknown_component"]) as project_root:
            index_path = project_root / "data/props/visual_bindings.generated.json"
            original_index = index_path.read_bytes()
            result = run_generator(project_root, "--write-index")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown component_id: unknown_component", result.stderr)
            self.assertEqual(index_path.read_bytes(), original_index)

    def test_generator_rejects_missing_governed_asset_before_writing_index(self) -> None:
        with copied_project_without_asset("dressing", "cable_tray") as project_root:
            index_path = project_root / "data/props/visual_bindings.generated.json"
            original_index = index_path.read_bytes()
            result = run_generator(project_root, "--write-index")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing dressing asset: cable_tray", result.stderr)
            self.assertEqual(index_path.read_bytes(), original_index)

    def test_validator_rejects_noncanonical_generated_index_bytes(self) -> None:
        with copied_project() as project_root:
            index_path = project_root / "data/props/visual_bindings.generated.json"
            document = json.loads(index_path.read_text(encoding="utf-8"))
            pretty = json.dumps(document, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
            index_path.write_text(pretty, encoding="utf-8")
            self.assertIn("generated index differs from sidecars", run_validator(project_root))

    def test_validator_rejects_trailing_whitespace_in_generated_index(self) -> None:
        with copied_project() as project_root:
            index_path = project_root / "data/props/visual_bindings.generated.json"
            index_path.write_bytes(index_path.read_bytes() + b"\n")
            self.assertIn("generated index differs from sidecars", run_validator(project_root))

    def test_validator_rejects_duplicate_keys_in_generated_index(self) -> None:
        with copied_project() as project_root:
            index_path = project_root / "data/props/visual_bindings.generated.json"
            canonical = index_path.read_text(encoding="utf-8")
            duplicate = canonical.replace(
                '"schema_version":"1.0.0",',
                '"schema_version":"1.0.0","schema_version":"1.0.0",',
                1,
            )
            index_path.write_text(duplicate, encoding="utf-8")
            self.assertIn("invalid generated index", run_validator(project_root))

    def test_validator_rejects_sidecar_symlink_escape_without_traceback(self) -> None:
        with copied_project() as project_root:
            sidecar_path, _sidecar = _load_sidecar(project_root, "reactor_console")
            outside_path = project_root.parent / "outside-reactor-console.sidecar.json"
            outside_path.write_bytes(sidecar_path.read_bytes())
            sidecar_path.unlink()
            sidecar_path.symlink_to(outside_path)
            output = run_validator(project_root)
            self.assertIn("path escapes project root via symlink", output)
            self.assertNotIn("Traceback", output)

    def test_generator_rejects_index_symlink_escape_without_writing_outside(self) -> None:
        with copied_project() as project_root:
            index_path = project_root / "data/props/visual_bindings.generated.json"
            outside_path = project_root.parent / "outside-visual-bindings.generated.json"
            outside_path.write_bytes(index_path.read_bytes())
            original_outside = outside_path.read_bytes()
            index_path.unlink()
            index_path.symlink_to(outside_path)
            result = run_generator(project_root, "--write-index")
            output = "\n".join(part for part in (result.stdout, result.stderr) if part)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("path escapes project root via symlink", output)
            self.assertNotIn("Traceback", output)
            self.assertEqual(outside_path.read_bytes(), original_outside)

    def test_refresh_preserves_extensions_and_hand_authored_fields(self) -> None:
        with copied_project_with_extension("reactor_console", {"studio": {"review_state": "approved"}}) as project_root:
            refresh_derived(project_root, "reactor_console")
            _sidecar_path, sidecar = _load_sidecar(project_root, "reactor_console")
            self.assertEqual(sidecar["extensions"], {"studio": {"review_state": "approved"}})
            self.assertEqual(sidecar["binding"]["ids"], ["reactor_console"])
            self.assertEqual(sidecar["placement"]["origin"], "scene_origin")

    def test_refresh_preserves_ai_provenance_fixture(self) -> None:
        ai_generation = {
            "provider": "meshy",
            "task_id": "018-test-promotion",
            "model": "meshy-t2",
            "input_sha256": ["a" * 64],
            "raw_output_sha256": "b" * 64,
            "cleaned_output_sha256": "c" * 64,
            "contract_sha256": "d" * 64,
            "human_cleanup": True,
            "reviewer": "operator",
        }
        with copied_project() as project_root:
            sidecar_path, sidecar = _load_sidecar(project_root, "reactor_console")
            sidecar["provenance"] = {
                "license_state": "paid-private",
                "source_platform": "meshy",
            }
            sidecar["extensions"] = {"ai_generation": ai_generation}
            _write_json(sidecar_path, sidecar)
            refresh_derived(project_root, "reactor_console")
            _sidecar_path, refreshed = _load_sidecar(project_root, "reactor_console")
            self.assertEqual(refreshed["provenance"], {
                "license_state": "paid-private",
                "source_platform": "meshy",
            })
            self.assertEqual(refreshed["extensions"]["ai_generation"], ai_generation)


if __name__ == "__main__":
    unittest.main()
