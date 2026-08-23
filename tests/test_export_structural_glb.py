from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT_ROOT / "tools" / "export_structural_glb.py"


def _load_exporter_module():
    spec = importlib.util.spec_from_file_location("export_structural_glb", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _run_export_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--", *args],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def test_export_cli_requires_blend_path_and_staging_dir() -> None:
    result = _run_export_cli()

    assert result.returncode != 0
    assert "--blend-path" in result.stderr
    assert "--staging-dir" in result.stderr


def test_export_cli_rejects_nonexistent_blend_file(tmp_path: Path) -> None:
    result = _run_export_cli(
        "--blend-path",
        str(tmp_path / "missing.blend"),
        "--staging-dir",
        str(tmp_path / "staging"),
    )

    assert result.returncode != 0
    assert "blend" in result.stderr.lower()
    assert "exist" in result.stderr.lower()


class _FakeCollection(dict):
    def __init__(self, name: str, variant_role: str) -> None:
        super().__init__(variant_role=variant_role)
        self.name = name
        self.objects: list[object] = []


class _FakeCollections(list[_FakeCollection]):
    def get(self, name: str):
        return next((collection for collection in self if collection.name == name), None)


def _fake_bpy(*collections: _FakeCollection):
    return SimpleNamespace(
        context=SimpleNamespace(scene={}),
        data=SimpleNamespace(collections=_FakeCollections(collections), objects=[]),
        ops=SimpleNamespace(
            wm=SimpleNamespace(open_mainfile=lambda filepath: None),
            object=SimpleNamespace(),
            export_scene=SimpleNamespace(),
        ),
    )


def test_export_rejects_duplicate_variant_roles_before_export(tmp_path: Path) -> None:
    exporter = _load_exporter_module()
    args = SimpleNamespace(
        blend_path=tmp_path / "source.blend",
        staging_dir=tmp_path / "staging",
        module="module_a",
    )
    bpy = _fake_bpy(
        _FakeCollection("Export_Damaged_A", "damaged"),
        _FakeCollection("Export_Damaged_B", "damaged"),
    )

    with pytest.raises(ValueError, match="duplicate variant_role 'damaged'"):
        exporter.export_blend(args, bpy)


def test_export_rejects_module_id_that_escapes_staging(tmp_path: Path) -> None:
    exporter = _load_exporter_module()
    args = SimpleNamespace(
        blend_path=tmp_path / "source.blend",
        staging_dir=tmp_path / "staging",
        module="../../evil",
    )

    with pytest.raises(ValueError, match="invalid module id"):
        exporter.export_blend(args, _fake_bpy())
