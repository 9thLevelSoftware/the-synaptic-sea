from __future__ import annotations

import builtins
import importlib
from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _load_recovery_cli():
    return importlib.import_module("tools.recover_modules")


def test_recovery_cli_requires_explicit_project_and_source_roots() -> None:
    recovery_cli = _load_recovery_cli()

    with pytest.raises(SystemExit):
        recovery_cli.parse_args(["--module", "floor_1x1"])


def test_recovery_cli_rejects_unapproved_module_before_blender_import(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    recovery_cli = _load_recovery_cli()
    real_import = builtins.__import__

    def reject_blender_import(name: str, *args: object, **kwargs: object):
        if name == "bpy":
            raise AssertionError("CLI imported Blender before validating module id")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", reject_blender_import)

    with pytest.raises(SystemExit):
        recovery_cli.main(
            [
                "--project-root",
                str(PROJECT_ROOT),
                "--source-root",
                str(tmp_path),
                "--module",
                "not_a_structural_module",
            ]
        )
