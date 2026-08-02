#!/usr/bin/env python3
"""Audit the governed structural integrity variants without mutating project data."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


STRUCTURAL_VARIANT_IDS = (
    "floor_1x1",
    "floor_2x1",
    "corridor_floor_1x1",
    "corridor_floor_1x2",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
)

STRUCTURAL_ROOT = Path("assets/imported/structural/ship_structural_v0")
WRAPPER_ROOT = Path("scenes/wrappers/structural/ship_structural_v0")
RESOLVER_PATH = Path("scripts/systems/integrity_visual_resolver.gd")

VARIANT_NODE_NAMES = {
    "intact": "VisualInstance_Intact",
    "damaged": "VisualInstance_Damaged",
    "breached": "VisualInstance_Breached",
}
VARIANT_SUFFIXES = {"intact": "", "damaged": "_damaged", "breached": "_breached"}
REQUIRED_RESOLVER_NODE_NAMES = {
    "Visual",
    "VisualInstance",
    "VisualInstance_Intact",
    "VisualInstance_Damaged",
    "VisualInstance_Breached",
}

EXT_RESOURCE_RE = re.compile(
    r'^\[ext_resource\b[^\n]*?path="(?P<path>[^"]+)"[^\n]*?id="(?P<id>[^"]+)"[^\n]*\]$'
)
NODE_RE = re.compile(
    r'^\[node\s+name="(?P<name>[^"]+)"(?P<rest>[^\]]*)\]$'
)
PARENT_RE = re.compile(r'\bparent="(?P<parent>[^"]+)"')
INSTANCE_RE = re.compile(r'\binstance=ExtResource\("(?P<id>[^"]+)"\)')
RESOLVER_NODE_RE = re.compile(r'get_node_or_null\("(?P<name>[^"]+)"\)')
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _relative(project_root: Path, path: Path) -> str:
    return path.relative_to(project_root).as_posix()


def _load_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def _parse_scene(text: str) -> tuple[dict[str, str], list[dict[str, str]]]:
    resources: dict[str, str] = {}
    nodes: list[dict[str, str]] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        resource_match = EXT_RESOURCE_RE.match(line)
        if resource_match:
            resources[resource_match.group("id")] = resource_match.group("path")
            continue
        node_match = NODE_RE.match(line)
        if not node_match:
            continue
        rest = node_match.group("rest")
        parent_match = PARENT_RE.search(rest)
        instance_match = INSTANCE_RE.search(rest)
        nodes.append(
            {
                "name": node_match.group("name"),
                "parent": parent_match.group("parent") if parent_match else "",
                "resource_id": instance_match.group("id") if instance_match else "",
            }
        )
    return resources, nodes


def _expected_variant_path(asset_id: str, variant: str) -> str:
    suffix = VARIANT_SUFFIXES[variant]
    return f"res://{STRUCTURAL_ROOT.as_posix()}/{asset_id}/{asset_id}{suffix}.glb"


def _resolve_project_path(project_root: Path, resource_path: str) -> Path | None:
    if not resource_path.startswith("res://"):
        return None
    relative = Path(resource_path.removeprefix("res://"))
    candidate = project_root / relative
    try:
        resolved_root = project_root.resolve()
        resolved_candidate = candidate.resolve(strict=False)
    except OSError:
        return None
    if resolved_candidate != resolved_root and resolved_root not in resolved_candidate.parents:
        return None
    return candidate


def _validate_manifest(
    project_root: Path,
    asset_id: str,
    errors: list[str],
) -> tuple[set[str], str | None]:
    manifest_path = project_root / WRAPPER_ROOT / f"{asset_id}.manifest.json"
    manifest = _load_json(manifest_path)
    if manifest is None:
        errors.append(f"cannot read structural manifest: {_relative(project_root, manifest_path)}")
        return set(), None

    asset = manifest.get("asset")
    if not isinstance(asset, dict):
        errors.append(f"structural manifest has no asset object: {asset_id}")
        return set(), None
    if asset.get("id") != asset_id:
        errors.append(f"structural manifest id mismatch: {asset_id}")

    anchors = asset.get("anchors")
    exposed = anchors.get("exposed") if isinstance(anchors, dict) else None
    anchor_names: list[str] = []
    if isinstance(exposed, list):
        for record in exposed:
            if isinstance(record, dict) and isinstance(record.get("name"), str):
                anchor_names.append(record["name"])
    else:
        errors.append(f"structural manifest has no exposed anchors: {asset_id}")

    generated = manifest.get("generated")
    intact_path = generated.get("visual_scene_path") if isinstance(generated, dict) else None
    if intact_path != _expected_variant_path(asset_id, "intact"):
        errors.append(f"manifest intact path does not match intact variant: {asset_id}")

    return set(anchor_names), intact_path if isinstance(intact_path, str) else None


def _validate_input_anchor_currency(
    project_root: Path,
    asset_id: str,
    manifest_anchor_names: set[str],
    errors: list[str],
) -> None:
    input_path = project_root / WRAPPER_ROOT / f"{asset_id}.input.json"
    input_document = _load_json(input_path)
    if input_document is None:
        errors.append(f"cannot read structural input: {_relative(project_root, input_path)}")
        return
    asset = input_document.get("asset")
    anchors = asset.get("anchors") if isinstance(asset, dict) else None
    exposed = anchors.get("exposed") if isinstance(anchors, dict) else None
    input_anchor_names = {
        record["name"]
        for record in exposed or []
        if isinstance(record, dict) and isinstance(record.get("name"), str)
    }
    if input_anchor_names != manifest_anchor_names:
        errors.append(f"manifest/input anchor set differs: {asset_id}")


def _validate_glbs(project_root: Path, asset_id: str, errors: list[str]) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for variant in VARIANT_NODE_NAMES:
        path = _resolve_project_path(project_root, _expected_variant_path(asset_id, variant))
        if path is None or not path.is_file():
            errors.append(f"missing {variant} GLB: {asset_id}")
            continue
        try:
            data = path.read_bytes()
        except OSError as exc:
            errors.append(f"cannot read {variant} GLB {asset_id}: {exc}")
            continue
        if len(data) < 4 or data[:4] != b"glTF":
            errors.append(f"invalid {variant} GLB header: {asset_id}")
            continue
        digest = hashlib.sha256(data).hexdigest()
        if not SHA256_RE.fullmatch(digest):
            errors.append(f"invalid {variant} GLB SHA-256: {asset_id}")
        else:
            hashes[variant] = digest
    return hashes


def _validate_scene(
    project_root: Path,
    asset_id: str,
    manifest_anchor_names: set[str],
    errors: list[str],
) -> None:
    scene_path = project_root / WRAPPER_ROOT / f"{asset_id}.tscn"
    try:
        scene_text = scene_path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"cannot read structural wrapper {_relative(project_root, scene_path)}: {exc}")
        return

    resources, nodes = _parse_scene(scene_text)
    direct_root_names = {node["name"] for node in nodes if node["parent"] in ("", ".")}
    direct_visual_nodes = {
        node["name"]: node
        for node in nodes
        if node["parent"] == "Visual"
    }

    if "Anchor_FloorCenter" not in direct_root_names:
        errors.append(f"missing required anchor Anchor_FloorCenter: {asset_id}")
    for anchor_name in sorted(manifest_anchor_names):
        if anchor_name not in direct_root_names:
            if anchor_name.startswith("Anchor_SOCK_"):
                errors.append(f"missing required socket anchor {anchor_name}: {asset_id}")
            else:
                errors.append(f"missing required anchor {anchor_name}: {asset_id}")
    scene_socket_names = {
        name for name in direct_root_names if name.startswith("Anchor_SOCK_")
    }
    manifest_socket_names = {
        name for name in manifest_anchor_names if name.startswith("Anchor_SOCK_")
    }
    for unexpected in sorted(scene_socket_names - manifest_socket_names):
        errors.append(f"unexpected socket anchor {unexpected}: {asset_id}")

    for variant, node_name in VARIANT_NODE_NAMES.items():
        matching_nodes = [node for node in nodes if node["name"] == node_name]
        direct_node = direct_visual_nodes.get(node_name)
        if direct_node is None:
            if matching_nodes:
                errors.append(f"{node_name} must be a direct child of Visual: {asset_id}")
            else:
                errors.append(f"missing required Visual child {node_name}: {asset_id}")
            continue
        resource_id = direct_node["resource_id"]
        actual_path = resources.get(resource_id)
        expected_path = _expected_variant_path(asset_id, variant)
        if not isinstance(actual_path, str) or actual_path != expected_path:
            errors.append(
                f"{variant} wrapper path does not match {variant} variant: {asset_id}"
            )
            continue
        resolved = _resolve_project_path(project_root, actual_path)
        if resolved is None or not resolved.is_file():
            errors.append(f"missing {variant} wrapper GLB: {asset_id}")


def _validate_resolver(project_root: Path, asset_id: str, errors: list[str]) -> None:
    resolver_path = project_root / RESOLVER_PATH
    try:
        resolver_text = resolver_path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"cannot read IntegrityVisualResolver: {exc}")
        return
    if "class_name IntegrityVisualResolver" not in resolver_text:
        errors.append(f"IntegrityVisualResolver class name missing: {asset_id}")
    resolver_names = set(RESOLVER_NODE_RE.findall(resolver_text))
    for node_name in sorted(REQUIRED_RESOLVER_NODE_NAMES - resolver_names):
        errors.append(f"IntegrityVisualResolver missing node name {node_name}: {asset_id}")


def validate_project(project_root: Path) -> list[str]:
    """Return deterministic diagnostics for the eight governed variant families."""
    errors: list[str] = []
    project_root = project_root.expanduser().resolve()
    for asset_id in STRUCTURAL_VARIANT_IDS:
        manifest_anchor_names, _intact_manifest_path = _validate_manifest(
            project_root, asset_id, errors
        )
        _validate_input_anchor_currency(
            project_root, asset_id, manifest_anchor_names, errors
        )
        _validate_glbs(project_root, asset_id, errors)
        _validate_scene(project_root, asset_id, manifest_anchor_names, errors)
        _validate_resolver(project_root, asset_id, errors)
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path("."))
    args = parser.parse_args(argv)
    project_root = args.project_root.expanduser().resolve()
    errors = validate_project(project_root)
    for error in errors:
        print(f"ERROR: {error}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
