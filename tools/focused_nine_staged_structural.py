#!/usr/bin/env python3
"""Build and validate an isolated staged pressure-door Godot overlay.

This module is intentionally separate from the promoted-source and live wrapper
validators.  It copies a checkout to a temporary destination, adds only the
staged pressure-door variants at their canonical imported paths, and promotes
only the staged wrapper resources inside that copy.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Iterable, Sequence
from pathlib import Path

ASSET_ID = "pressure_door_1x1"
_VARIANT_ROLES: tuple[str, ...] = ("intact", "damaged", "breached")
_VARIANT_SUFFIXES = {"intact": "", "damaged": "_damaged", "breached": "_breached"}
_STAGED_ASSET_RELATIVE = Path(
    "assets/_staging/focused_nine/structural/pressure_door_1x1"
)
_CANONICAL_IMPORT_RELATIVE = Path(
    "assets/imported/structural/ship_structural_v0/pressure_door_1x1"
)
_CANONICAL_WRAPPER_RELATIVE = Path(
    "scenes/wrappers/structural/ship_structural_v0"
)
_CONTRACT_RELATIVE = Path(
    "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
)
_SMOKE_RELATIVE = Path("scripts/validation/focused_nine_staged_structural_smoke.gd")
_PACKAGE_FILENAMES = (
    f"{ASSET_ID}.manifest.json",
    f"{ASSET_ID}.input.json",
    f"{ASSET_ID}.tscn",
)
_IGNORED_COPY_NAMES = frozenset(
    {
        ".git",
        ".godot",
        ".hermes",
        ".mypy_cache",
        ".omh",
        ".pytest_cache",
        ".ruff_cache",
        ".serena",
        ".superpowers",
        "__pycache__",
    }
)
_DIAGNOSTIC_MARKERS = ("ERROR:", "WARNING:", "SCRIPT ERROR:")
_PASS_MARKER = "FOCUSED_NINE_PRESSURE_DOOR_PASS variants=3 anchors=4 collision=true"


def _raw_path(value: Path | str, label: str) -> Path:
    path = Path(value).expanduser()
    if ".." in path.parts:
        raise ValueError(f"{label} must not contain traversal: {path}")
    return path if path.is_absolute() else Path.cwd() / path


def _symlink_components(path: Path) -> Iterable[Path]:
    current = Path(path.anchor) if path.is_absolute() else Path.cwd()
    parts = path.parts[1:] if path.is_absolute() else path.parts
    for part in parts:
        current /= part
        try:
            if current.is_symlink() and current not in (Path("/var"), Path("/tmp")):
                # macOS exposes temporary directories through /var -> /private/var;
                # that system alias is not a caller-controlled staging alias.
                yield current
        except OSError as exc:
            raise ValueError(f"cannot inspect {path}") from exc


def _reject_symlink_alias(path: Path, label: str) -> None:
    aliases = tuple(_symlink_components(path))
    if aliases:
        raise ValueError(f"{label} contains symlink alias: {path}")


def _project_root(value: Path | str) -> Path:
    path = _raw_path(value, "project root")
    resolved = path.resolve(strict=False)
    if not resolved.is_dir():
        raise ValueError(f"project root is not a directory: {path}")
    return resolved


def _staging_root(value: Path | str) -> Path:
    path = _raw_path(value, "staging root")
    _reject_symlink_alias(path, "staging root")
    resolved = path.resolve(strict=False)
    if not resolved.is_dir():
        raise ValueError(f"staging root is not a directory: {path}")
    return resolved


def _destination_path(value: Path | str, project_root: Path) -> Path:
    path = _raw_path(value, "destination")
    resolved = path.resolve(strict=False)
    if resolved == project_root or project_root in resolved.parents:
        raise ValueError(f"destination is within project root: {path}")
    _reject_symlink_alias(path, "destination")
    if path.exists() or path.is_symlink():
        raise ValueError(f"destination already exists: {path}")
    return resolved


def _contained(root: Path, candidate: Path, label: str) -> Path:
    resolved_root = root.resolve(strict=False)
    _reject_symlink_alias(candidate, label)
    resolved_candidate = candidate.resolve(strict=False)
    if resolved_candidate == resolved_root or resolved_root not in resolved_candidate.parents:
        raise ValueError(f"{label} escapes root: {candidate}")
    return resolved_candidate


def _regular_file(path: Path, label: str) -> Path:
    try:
        mode = path.lstat().st_mode
    except OSError as exc:
        raise ValueError(f"missing {label}: {path}") from exc
    if not stat.S_ISREG(mode):
        raise ValueError(f"{label} is not a regular file: {path}")
    return path


def _staged_asset_dir(staging_root: Path) -> Path:
    candidates = (
        staging_root / "structural" / ASSET_ID,
        staging_root / "focused_nine" / "structural" / ASSET_ID,
        staging_root / "assets" / "_staging" / "focused_nine" / "structural" / ASSET_ID,
        staging_root / ASSET_ID,
        staging_root if staging_root.name == ASSET_ID else staging_root / "__not_a_candidate__",
    )
    for candidate in candidates:
        candidate = _contained(staging_root, candidate, "staged package")
        if candidate.is_dir():
            return candidate
    raise ValueError(f"missing staged package: {ASSET_ID}")


def _variant_filename(role: str) -> str:
    if role not in _VARIANT_ROLES:
        raise ValueError(f"unsupported pressure-door role: {role}")
    return f"{ASSET_ID}{_VARIANT_SUFFIXES[role]}.glb"


def _staged_variant_paths(staging_root: Path) -> dict[str, Path]:
    package = _staged_asset_dir(staging_root)
    paths: dict[str, Path] = {}
    for role in _VARIANT_ROLES:
        candidate = _contained(
            staging_root, package / _variant_filename(role), "staged variant"
        )
        try:
            path = _regular_file(candidate, f"staged variant {role}")
        except ValueError as exc:
            if not candidate.exists() and not candidate.is_symlink():
                raise ValueError(f"missing staged variant {role}") from exc
            raise
        paths[role] = path
    return paths


def _validate_glb(path: Path, role: str) -> None:
    try:
        header = path.read_bytes()[:12]
        size = path.stat().st_size
    except OSError as exc:
        raise ValueError(f"cannot read staged variant {role}: {path}") from exc
    if len(header) < 12 or header[:4] != b"glTF":
        raise ValueError(f"invalid staged variant {role} GLB header")
    if int.from_bytes(header[4:8], "little") != 2 or int.from_bytes(header[8:12], "little") != size:
        raise ValueError(f"invalid staged variant {role} GLB header")


def _package_sources(project_root: Path, staging_root: Path, staged_package: Path) -> dict[str, Path]:
    project_package = project_root / _STAGED_ASSET_RELATIVE
    sources: dict[str, Path] = {}
    for filename in _PACKAGE_FILENAMES:
        staged_candidate = staged_package / filename
        project_candidate = project_package / filename
        if staged_candidate.exists() or staged_candidate.is_symlink():
            source = _contained(staging_root, staged_candidate, "staged wrapper resource")
        else:
            source = project_candidate
        sources[filename] = _regular_file(source, f"staged wrapper resource {filename}")
    return sources


def _canonical_variant_paths() -> set[str]:
    return {
        f"res://{(_CANONICAL_IMPORT_RELATIVE / _variant_filename(role)).as_posix()}"
        for role in _VARIANT_ROLES
    }


def _parse_ext_resource_paths(scene_text: str) -> list[str]:
    return re.findall(r'^\[ext_resource\b[^\n]*?path="([^"]+)"[^\n]*\]$', scene_text, re.MULTILINE)


def _validate_scene_text(scene_text: str) -> None:
    paths = _parse_ext_resource_paths(scene_text)
    expected_paths = _canonical_variant_paths()
    if len(paths) != 3 or set(paths) != expected_paths:
        raise ValueError("invalid staged wrapper ext_resource paths")
    if any(
        not path.startswith("res://")
        or ".." in Path(path.removeprefix("res://")).parts
        or "_staging" in path
        or "/Volumes/" in path
        for path in paths
    ):
        raise ValueError("invalid staged wrapper ext_resource path")

    lines = [line.strip() for line in scene_text.splitlines()]
    node_records: list[tuple[str, str, str]] = []
    node_re = re.compile(r'^\[node\s+name="([^"]+)"(?:\s+type="([^"]+)")?(?:\s+parent="([^"]+)")?[^\]]*\]$')
    for line in lines:
        match = node_re.match(line)
        if match:
            node_records.append((match.group(1), match.group(2) or "", match.group(3) or ""))
    direct_root = {name: node_type for name, node_type, parent in node_records if parent in ("", ".")}
    direct_visual = {name for name, _node_type, parent in node_records if parent == "Visual"}
    expected_anchors = {
        "Anchor_FloorCenter",
        "Anchor_SOCK_portal_edge_west_01",
        "Anchor_SOCK_portal_edge_east_01",
        "Anchor_SOCK_portal_center_internal_01",
    }
    if direct_root.get("Pressure_Door_1x1") != "Node3D":
        raise ValueError("invalid staged wrapper root")
    if {name for name in direct_root if name.startswith("Anchor_")} != expected_anchors:
        raise ValueError("invalid staged wrapper anchor set")
    if any(direct_root.get(name) != "Marker3D" for name in expected_anchors):
        raise ValueError("invalid staged wrapper anchor types")
    if direct_root.get("CollisionRoot") != "StaticBody3D" or not any(
        name == "CollisionShape3D" and parent == "CollisionRoot" for name, _type, parent in node_records
    ):
        raise ValueError("invalid staged wrapper collision")
    expected_visual = {
        "VisualInstance_Intact",
        "VisualInstance_Damaged",
        "VisualInstance_Breached",
    }
    if direct_root.get("Visual") != "Node3D" or direct_visual != expected_visual:
        raise ValueError("invalid staged wrapper visual variant set")


def _validate_manifest(document: object) -> None:
    if not isinstance(document, dict):
        raise ValueError("invalid staged pressure-door manifest")  # noqa: TRY004
    if document.get("status") != "staged_not_promoted":
        raise ValueError("staged pressure-door manifest is not marked staged_not_promoted")
    promotion = document.get("promotion")
    if not isinstance(promotion, dict) or promotion.get("promoted") is not False:
        raise ValueError("staged pressure-door manifest has invalid promotion status")
    variants = document.get("variants")
    if not isinstance(variants, list) or [entry.get("role") for entry in variants if isinstance(entry, dict)] != list(_VARIANT_ROLES):
        raise ValueError("staged pressure-door manifest must declare intact/damaged/breached roles")
    for entry in variants:
        if not isinstance(entry, dict) or entry.get("sha256") is not None:
            raise ValueError("staged pressure-door manifest hash slots must be unresolved")
    slots = document.get("hash_slots")
    if slots != {role: None for role in _VARIANT_ROLES}:
        raise ValueError("staged pressure-door manifest hash slots are invalid")


def _validate_input(document: object, manifest: object) -> None:
    if not isinstance(document, dict) or document.get("status") != "staged_not_promoted":
        raise ValueError("staged pressure-door input is not marked staged_not_promoted")
    promotion = document.get("promotion")
    if not isinstance(promotion, dict) or promotion.get("promoted") is not False:
        raise ValueError("staged pressure-door input has invalid promotion status")
    asset = document.get("asset")
    if not isinstance(asset, dict) or asset.get("id") != ASSET_ID:
        raise ValueError("staged pressure-door input has invalid asset")
    manifest_asset = manifest.get("asset") if isinstance(manifest, dict) else None
    if not isinstance(manifest_asset, dict) or asset.get("anchors") != manifest_asset.get("anchors"):
        raise ValueError("staged pressure-door manifest/input anchors differ")


def _validate_contract(project_root: Path) -> None:
    path = _regular_file(project_root / _CONTRACT_RELATIVE, "pressure-door contract")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("invalid pressure-door contract") from exc
    if not isinstance(document, dict) or document.get("module_id") != ASSET_ID:
        raise ValueError("pressure-door contract module id mismatch")
    if document.get("kit_id") != "ship_structural_v0" or document.get("module_family") != "portal":
        raise ValueError("pressure-door contract kit/family mismatch")
    sockets = document.get("sockets")
    expected = (
        ("portal_edge_west_01", "portal_edge"),
        ("portal_edge_east_01", "portal_edge"),
        ("portal_center_internal_01", "portal_center"),
    )
    if not isinstance(sockets, list) or not all(isinstance(item, dict) for item in sockets):
        raise ValueError("pressure-door contract socket set mismatch")
    if [(item.get("id"), item.get("kind")) for item in sockets] != list(expected):
        raise ValueError("pressure-door contract socket set mismatch")
    collision = document.get("collision")
    if not isinstance(collision, dict) or collision.get("proxy_shape") != "box" or collision.get("nav_blocker") is not True:
        raise ValueError("pressure-door contract collision mismatch")


def _validate_staged_package(project_root: Path, staging_root: Path, staged_package: Path) -> dict[str, Path]:
    sources = _package_sources(project_root, staging_root, staged_package)
    try:
        scene_text = sources[f"{ASSET_ID}.tscn"].read_text(encoding="utf-8")
        manifest = json.loads(sources[f"{ASSET_ID}.manifest.json"].read_text(encoding="utf-8"))
        input_document = json.loads(sources[f"{ASSET_ID}.input.json"].read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError("invalid staged pressure-door metadata resources") from exc
    _validate_scene_text(scene_text)
    _validate_manifest(manifest)
    _validate_input(input_document, manifest)
    _validate_contract(project_root)
    return sources


def _copy_project_without_symlinks(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for entry in source.iterdir():
        if entry.name in _IGNORED_COPY_NAMES or entry.is_symlink():
            continue
        target = destination / entry.name
        if entry.is_dir():
            _copy_project_without_symlinks(entry, target)
        elif entry.is_file():
            shutil.copy2(entry, target)


def _copy_resources_into_overlay(
    overlay_root: Path,
    package_sources: dict[str, Path],
    staged_variants: dict[str, Path],
) -> None:
    import_root = overlay_root / _CANONICAL_IMPORT_RELATIVE
    import_root.mkdir(parents=True, exist_ok=True)
    for role, source in staged_variants.items():
        shutil.copy2(source, import_root / _variant_filename(role))

    wrapper_root = overlay_root / _CANONICAL_WRAPPER_RELATIVE
    wrapper_root.mkdir(parents=True, exist_ok=True)
    for filename, source in package_sources.items():
        shutil.copy2(source, wrapper_root / filename)


def build_overlay(project_root: Path, staging_root: Path, destination: Path) -> None:
    """Atomically build a project overlay containing the staged pressure door."""

    root = _project_root(project_root)
    stage = _staging_root(staging_root)
    destination_path = _destination_path(destination, root)
    staged_package = _staged_asset_dir(stage)
    staged_variants = _staged_variant_paths(stage)
    for role, path in staged_variants.items():
        _validate_glb(path, role)
    package_sources = _validate_staged_package(root, stage, staged_package)

    destination_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = Path(tempfile.mkdtemp(prefix="focused-nine-overlay-", dir=str(destination_path.parent)))
    try:
        _copy_project_without_symlinks(root, temporary_path)
        _copy_resources_into_overlay(temporary_path, package_sources, staged_variants)
        temporary_path.replace(destination_path)
    except BaseException:
        shutil.rmtree(temporary_path, ignore_errors=True)
        raise


def _diagnostics(output: str) -> list[str]:
    return [
        line.strip()
        for line in output.splitlines()
        if line.strip() and any(marker in line for marker in _DIAGNOSTIC_MARKERS)
    ]


def _run_godot(command: Sequence[str], overlay_root: Path, label: str, require_marker: bool = False) -> list[str]:
    try:
        completed = subprocess.run(
            list(command),
            cwd=str(overlay_root),
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        return [f"cannot invoke Godot for {label}: {exc}"]
    output = f"{getattr(completed, 'stdout', '') or ''}\n{getattr(completed, 'stderr', '') or ''}"
    errors = _diagnostics(output)
    if completed.returncode != 0 and not errors:
        errors.append(f"Godot {label} failed: exit {completed.returncode}")
    if require_marker and _PASS_MARKER not in output and not errors:
        errors.append(f"Godot {label} did not emit {_PASS_MARKER}")
    return errors


def validate_pressure_door_overlay(
    project_root: Path, staging_root: Path, godot: Path
) -> list[str]:
    """Return deterministic diagnostics from an isolated pressure-door validation."""

    try:
        root = _project_root(project_root)
        stage = _staging_root(staging_root)
        staged_package = _staged_asset_dir(stage)
        staged_variants = _staged_variant_paths(stage)
        for role, path in staged_variants.items():
            _validate_glb(path, role)
        _validate_staged_package(root, stage, staged_package)
    except ValueError as exc:
        message = str(exc)
        if message.startswith("missing staged variant "):
            return [message]
        return [message]

    with tempfile.TemporaryDirectory(prefix="focused-nine-pressure-door-") as temporary:
        overlay_root = Path(temporary) / "project"
        try:
            build_overlay(root, stage, overlay_root)
        except (OSError, ValueError) as exc:
            return [f"cannot create pressure-door validation overlay: {exc}"]

        import_command = [str(godot), "--headless", "--import", "--path", str(overlay_root)]
        errors = _run_godot(import_command, overlay_root, "pressure-door import")
        if errors:
            return errors
        smoke_command = [
            str(godot),
            "--headless",
            "--path",
            str(overlay_root),
            "--script",
            f"res://{_SMOKE_RELATIVE.as_posix()}",
        ]
        return _run_godot(smoke_command, overlay_root, "pressure-door smoke", require_marker=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path("."))
    parser.add_argument("--staging-root", type=Path, required=True)
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT", "/opt/homebrew/bin/godot")))
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    errors = validate_pressure_door_overlay(args.project_root, args.staging_root, args.godot)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(_PASS_MARKER)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
