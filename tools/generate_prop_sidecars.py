#!/usr/bin/env python3
"""Create and refresh deterministic prop visual sidecars and their index."""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.prop_visual_metadata import read_glb_metadata, write_canonical_json


PROP_GROUPS = ("components", "dressing", "objectives")
DRESSING_SURFACES = {
    "cable_tray": "wall",
    "emergency_wall": "wall",
    "practical_overhead": "ceiling",
    "cargo_pallet": "floor",
    "focused_work_lamp": "floor",
    "generic_crate": "floor",
    "generic_locker": "floor",
    "maintenance_bench": "floor",
    "medical_cabinet": "floor",
    "salvage_cart": "floor",
    "service_rack": "floor",
}
OBJECTIVE_IDS = {
    "medbay_terminal": ["medbay_terminal"],
    "reactor_control_panel": ["reactor_control_panel"],
    "repair_junction": ["maintenance_breaker_panel"],
    "supply_cache": ["cargo_supply_cache", "supply_cache"],
}


def _res_path(project_root: Path, path: Path) -> str:
    return f"res://{path.resolve().relative_to(project_root.resolve()).as_posix()}"


def _binding(prop_kind: str, asset_id: str) -> dict[str, Any]:
    if prop_kind == "component":
        return {"namespace": "component_id", "ids": [asset_id]}
    if prop_kind == "dressing":
        return {"namespace": "visual_prop_id", "ids": [asset_id]}
    return {"namespace": "gameplay_placement_id", "ids": OBJECTIVE_IDS[asset_id]}


def _canonical_sidecar(project_root: Path, glb_path: Path, prop_kind: str) -> dict[str, Any]:
    asset_id = glb_path.stem
    metadata = read_glb_metadata(glb_path)
    placement: dict[str, Any] = {
        "origin": "scene_origin",
        "offset_m": [0.0, 0.0, 0.0],
        "rotation_degrees": [0.0, 0.0, 0.0],
        "allowed_yaw_deg": [0.0, 90.0, 180.0, 270.0],
        "scale": 1.0,
    }
    if prop_kind == "dressing":
        placement["surface"] = DRESSING_SURFACES[asset_id]
    return {
        "schema_version": "1.0.0",
        "document_kind": "prop_visual_binding",
        "asset_id": asset_id,
        "prop_kind": prop_kind,
        "visual_scene_path": _res_path(project_root, glb_path),
        "binding": _binding(prop_kind, asset_id),
        "placement": placement,
        "source": {
            "sha256": metadata["sha256"],
            "byte_size": metadata["byte_size"],
            "mesh_count": metadata["mesh_count"],
            "gltf_version": metadata["gltf_version"],
        },
        "bounds": {
            "local_min_m": metadata["local_min_m"],
            "local_max_m": metadata["local_max_m"],
        },
        "collision_policy": "none_visual_only",
        "provenance": {"license_state": "self-authored", "source_platform": "self-authored"},
        "extensions": {},
    }


def _iter_glbs(project_root: Path) -> list[tuple[str, Path]]:
    prop_root = project_root / "assets/imported/props"
    kind_by_group = {"components": "component", "dressing": "dressing", "objectives": "objective"}
    result: list[tuple[str, Path]] = []
    for prop_kind in PROP_GROUPS:
        group = prop_root / prop_kind
        for glb_path in sorted(group.glob("*.glb"), key=lambda path: path.name):
            result.append((kind_by_group[prop_kind], glb_path))
    return result


def _sidecar_path(glb_path: Path) -> Path:
    return glb_path.with_name(f"{glb_path.stem}.sidecar.json")


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON document must be an object: {path}")
    return value


def _index_record(sidecar: dict[str, Any]) -> dict[str, Any]:
    # Keep the generated record a complete sidecar-derived record. This keeps
    # the runtime catalog independent of sidecar location while retaining all
    # validated visual transform/source evidence.
    return copy.deepcopy(sidecar)


def build_index(project_root: Path) -> dict[str, Any]:
    groups: dict[str, dict[str, Any]] = {"components": {}, "objectives": {}, "dressing": {}}
    for prop_kind, glb_path in _iter_glbs(project_root):
        sidecar_path = _sidecar_path(glb_path)
        if not sidecar_path.is_file():
            raise FileNotFoundError(f"missing sidecar: {sidecar_path.relative_to(project_root).as_posix()}")
        sidecar = _load_json(sidecar_path)
        binding = sidecar.get("binding")
        if not isinstance(binding, dict) or not isinstance(binding.get("ids"), list):
            raise ValueError(f"sidecar has no binding ids: {sidecar_path.relative_to(project_root).as_posix()}")
        index_group = {"component": "components", "dressing": "dressing", "objective": "objectives"}[prop_kind]
        for binding_id in binding["ids"]:
            if not isinstance(binding_id, str) or not binding_id:
                raise ValueError(f"sidecar has invalid binding id: {sidecar_path.relative_to(project_root).as_posix()}")
            if binding_id in groups[index_group]:
                raise ValueError(f"duplicate binding id: {binding_id}")
            groups[index_group][binding_id] = _index_record(sidecar)
    return {
        "schema_version": "1.0.0",
        "document_kind": "prop_visual_binding_index",
        "components": dict(sorted(groups["components"].items())),
        "objectives": dict(sorted(groups["objectives"].items())),
        "dressing": dict(sorted(groups["dressing"].items())),
    }


def _canonical_text(document: dict[str, Any]) -> str:
    return json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n"


def _write_missing(project_root: Path) -> list[str]:
    changes: list[str] = []
    for prop_kind, glb_path in _iter_glbs(project_root):
        sidecar_path = _sidecar_path(glb_path)
        if sidecar_path.exists():
            continue
        sidecar = _canonical_sidecar(project_root, glb_path, prop_kind)
        write_canonical_json(sidecar_path, sidecar)
        changes.append(f"created sidecar: {sidecar_path.relative_to(project_root).as_posix()}")
    return changes


def _refresh_derived(project_root: Path, asset_id: str) -> str:
    matches = [(kind, path) for kind, path in _iter_glbs(project_root) if path.stem == asset_id]
    if len(matches) != 1:
        raise ValueError(f"expected one GLB for asset_id {asset_id}, found {len(matches)}")
    prop_kind, glb_path = matches[0]
    sidecar_path = _sidecar_path(glb_path)
    if not sidecar_path.is_file():
        raise FileNotFoundError(f"missing sidecar: {sidecar_path.relative_to(project_root).as_posix()}")
    existing = _load_json(sidecar_path)
    refreshed = _canonical_sidecar(project_root, glb_path, prop_kind)
    for field in ("binding", "placement", "provenance", "extensions"):
        if field in existing:
            refreshed[field] = copy.deepcopy(existing[field])
    write_canonical_json(sidecar_path, refreshed)
    return f"refreshed derived fields: {sidecar_path.relative_to(project_root).as_posix()}"


def _check_sidecars(project_root: Path) -> list[str]:
    errors: list[str] = []
    for prop_kind, glb_path in _iter_glbs(project_root):
        sidecar_path = _sidecar_path(glb_path)
        relative = sidecar_path.relative_to(project_root).as_posix()
        if not sidecar_path.is_file():
            errors.append(f"missing sidecar: {relative}")
            continue
        try:
            actual = _load_json(sidecar_path)
            expected = _canonical_sidecar(project_root, glb_path, prop_kind)
        except (OSError, ValueError, KeyError) as exc:
            errors.append(f"cannot canonicalize sidecar {relative}: {exc}")
            continue
        for field in ("binding", "placement", "provenance", "extensions"):
            if field in actual:
                expected[field] = copy.deepcopy(actual[field])
        if sidecar_path.read_text(encoding="utf-8") != _canonical_text(expected):
            errors.append(f"sidecar differs from canonical output: {relative}")
    prop_root = project_root / "assets/imported/props"
    for group in PROP_GROUPS:
        group_root = prop_root / group
        glb_names = {path.stem for path in group_root.glob("*.glb")}
        for sidecar_path in sorted(group_root.glob("*.sidecar.json")):
            asset_id = sidecar_path.name.removesuffix(".sidecar.json")
            if asset_id not in glb_names:
                errors.append(f"sidecar has no matching GLB: {sidecar_path.relative_to(project_root).as_posix()}")
    return errors


def _check_index(project_root: Path) -> list[str]:
    path = project_root / "data/props/visual_bindings.generated.json"
    try:
        expected = build_index(project_root)
    except (OSError, ValueError, KeyError) as exc:
        return [str(exc)]
    if not path.is_file():
        return [f"missing generated index: {path.relative_to(project_root).as_posix()}"]
    try:
        _load_json(path)
    except (OSError, ValueError) as exc:
        return [f"invalid generated index: {exc}"]
    if path.read_text(encoding="utf-8") != _canonical_text(expected):
        return ["generated index differs from sidecars"]
    return []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path("."))
    parser.add_argument("--write-missing", action="store_true")
    parser.add_argument("--write-index", action="store_true")
    parser.add_argument("--refresh-derived", action="store_true")
    parser.add_argument("--asset-id")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    project_root = args.project_root.expanduser().resolve()
    if args.refresh_derived and not args.asset_id:
        parser.error("--refresh-derived requires --asset-id")
    if not (args.write_missing or args.write_index or args.refresh_derived or args.check):
        parser.error("one of --write-missing, --write-index, --refresh-derived, or --check is required")

    diagnostics: list[str] = []
    had_error = False
    try:
        if args.write_missing:
            diagnostics.extend(_write_missing(project_root))
        if args.refresh_derived:
            diagnostics.append(_refresh_derived(project_root, args.asset_id))
        if args.write_index:
            index_path = project_root / "data/props/visual_bindings.generated.json"
            write_canonical_json(index_path, build_index(project_root))
            diagnostics.append(f"wrote generated index: {index_path.relative_to(project_root).as_posix()}")
        if args.check:
            diagnostics.extend(_check_sidecars(project_root))
            diagnostics.extend(_check_index(project_root))
    except (OSError, ValueError, KeyError) as exc:
        diagnostics.append(str(exc))
        had_error = True

    for diagnostic in diagnostics:
        print(diagnostic, file=sys.stderr if (args.check and not diagnostic.startswith(("created ", "refreshed ", "wrote "))) else sys.stdout)
    if had_error or (args.check and any(diagnostic for diagnostic in diagnostics)):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
