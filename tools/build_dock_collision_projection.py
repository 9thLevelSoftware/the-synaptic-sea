#!/usr/bin/env python3
"""Build the strict docking collision projection from selected Godot wrappers."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "dock-collision-projection-v1"
DEFAULT_KIT = Path("data/kits/ship_structural_v0.json")
IDENTITY_BASIS = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
ZERO = (0.0, 0.0, 0.0)
HEADER_RE = re.compile(r"^\[(?P<kind>[a-z_]+)(?P<attrs>.*)\]$")
ATTR_RE = re.compile(r'(?P<key>[a-z_]+)=(?:"(?P<quoted>[^"]*)"|(?P<bare>[^\s\]]+))')
VECTOR_RE = re.compile(r"^Vector3\(([^)]*)\)$")
TRANSFORM_RE = re.compile(r"^Transform3D\(([^)]*)\)$")
SUBRESOURCE_RE = re.compile(r'^SubResource\("([^"]+)"\)$')
CONTRACT_WRAPPER_RE = re.compile(r'^wrapper_scene = "([^"]+)"$', re.MULTILINE)


class ProjectionError(ValueError):
    pass


class Transform:
    def __init__(
            self,
            basis: tuple[float, ...] = IDENTITY_BASIS,
            origin: tuple[float, float, float] = ZERO) -> None:
        self.basis = basis
        self.origin = origin


class NodeRecord:
    def __init__(
            self,
            path: str,
            type_name: str,
            parent_path: str | None,
            properties: dict[str, str]) -> None:
        self.path = path
        self.type_name = type_name
        self.parent_path = parent_path
        self.properties = properties


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _f32(value: float) -> float:
    try:
        return struct.unpack("<f", struct.pack("<f", value))[0]
    except (OverflowError, struct.error) as error:
        raise ProjectionError("number is outside finite binary32 range") from error


def _f32_hex(value: float) -> str:
    return f"{struct.unpack('<I', struct.pack('<f', value))[0]:08x}"


def _f32_product(left: float, right: float) -> float:
    return _f32(_f32(left) * _f32(right))


def _f32_sum(left: float, right: float) -> float:
    return _f32(_f32(left) + _f32(right))


def _numbers(raw: str, count: int, context: str) -> tuple[float, ...]:
    parts = [part.strip() for part in raw.split(",")]
    if len(parts) != count:
        raise ProjectionError(f"malformed {context}: expected {count} numbers")
    try:
        parsed = tuple(float(part) for part in parts)
    except ValueError as error:
        raise ProjectionError(f"malformed {context}: non-numeric value") from error
    values = tuple(_f32(value) for value in parsed)
    if not all(math.isfinite(value) for value in values):
        raise ProjectionError(f"malformed {context}: non-finite value")
    return values


def _vector(value: str, context: str) -> tuple[float, float, float]:
    match = VECTOR_RE.fullmatch(value.strip())
    if match is None:
        raise ProjectionError(f"malformed {context}: expected Vector3")
    result = _numbers(match.group(1), 3, context)
    return result[0], result[1], result[2]


def _basis_vector(basis: tuple[float, ...], vector: tuple[float, ...]) -> tuple[float, float, float]:
    return (
        _f32_sum(_f32_sum(_f32_product(basis[0], vector[0]),
                          _f32_product(basis[3], vector[1])),
                 _f32_product(basis[6], vector[2])),
        _f32_sum(_f32_sum(_f32_product(basis[1], vector[0]),
                          _f32_product(basis[4], vector[1])),
                 _f32_product(basis[7], vector[2])),
        _f32_sum(_f32_sum(_f32_product(basis[2], vector[0]),
                          _f32_product(basis[5], vector[1])),
                 _f32_product(basis[8], vector[2])),
    )


def _basis_product(parent: tuple[float, ...], child: tuple[float, ...]) -> tuple[float, ...]:
    columns: list[float] = []
    for offset in (0, 3, 6):
        columns.extend(_basis_vector(parent, child[offset:offset + 3]))
    return tuple(columns)


def _compose(parent: Transform, child: Transform) -> Transform:
    translated = _basis_vector(parent.basis, child.origin)
    return Transform(
        _basis_product(parent.basis, child.basis),
        tuple(_f32_sum(parent.origin[index], translated[index]) for index in range(3)),
    )


def _bits(values: tuple[float, ...]) -> list[str]:
    return [_f32_hex(value) for value in values]


def _collision_content_bytes(boxes: list[dict[str, Any]]) -> bytes:
    lines = ["dock-collision-content-v1"]
    for box in boxes:
        path = str(box["shape_path"])
        if "\n" in path or "\r" in path or "=" in path:
            raise ProjectionError(f"unsupported shape path characters: {path}")
        lines.extend([
            f"path={path}",
            "basis=" + ",".join(box["basis_f32_bits"]),
            "origin=" + ",".join(box["origin_f32_bits"]),
            "dimensions=" + ",".join(box["dimensions_f32_bits"]),
        ])
    return ("\n".join(lines) + "\n").encode("utf-8")


def _local_transform(node: NodeRecord) -> Transform:
    transform_keys = set(node.properties) & {"transform", "position", "rotation", "rotation_degrees", "scale"}
    unsupported = transform_keys & {"rotation", "rotation_degrees", "scale"}
    if unsupported:
        raise ProjectionError(
            f"unsupported transform property on {node.path}: {sorted(unsupported)[0]}")
    if "transform" in transform_keys and "position" in transform_keys:
        raise ProjectionError(f"ambiguous transform properties on {node.path}")
    if "transform" in transform_keys:
        match = TRANSFORM_RE.fullmatch(node.properties["transform"].strip())
        if match is None:
            raise ProjectionError(f"malformed Transform3D on {node.path}")
        values = _numbers(match.group(1), 12, f"Transform3D on {node.path}")
        # Godot text resources serialize the 3x3 basis in row order, while the
        # Basis scalar/vector APIs expose its three columns.
        basis = (
            values[0], values[3], values[6],
            values[1], values[4], values[7],
            values[2], values[5], values[8],
        )
        determinant = (
            basis[0] * (basis[4] * basis[8] - basis[7] * basis[5])
            - basis[3] * (basis[1] * basis[8] - basis[7] * basis[2])
            + basis[6] * (basis[1] * basis[5] - basis[4] * basis[2])
        )
        if determinant == 0.0:
            raise ProjectionError(f"singular Transform3D on {node.path}")
        return Transform(basis, (values[9], values[10], values[11]))
    if "position" in transform_keys:
        return Transform(IDENTITY_BASIS, _vector(node.properties["position"], f"position on {node.path}"))
    return Transform()


def _parse_attrs(raw: str, context: str) -> dict[str, str]:
    attrs: dict[str, str] = {}
    consumed: list[tuple[int, int]] = []
    for match in ATTR_RE.finditer(raw):
        key = match.group("key")
        if key in attrs:
            raise ProjectionError(f"duplicate {context} attribute: {key}")
        attrs[key] = match.group("quoted") if match.group("quoted") is not None else match.group("bare")
        consumed.append(match.span())
    residue = raw
    for start, end in reversed(consumed):
        residue = residue[:start] + residue[end:]
    if residue.strip():
        raise ProjectionError(f"malformed {context} attributes: {residue.strip()}")
    return attrs


def _resource_path(root: Path, value: str, context: str) -> Path:
    if not value.startswith("res://"):
        raise ProjectionError(f"{context} must be a res:// path")
    root = root.resolve()
    path = (root / value.removeprefix("res://")).resolve()
    try:
        path.relative_to(root)
    except ValueError as error:
        raise ProjectionError(f"{context} escapes project root") from error
    if not path.is_file():
        raise ProjectionError(f"missing {context}: {value}")
    return path


def _parse_wrapper(path: Path) -> list[dict[str, Any]]:
    resources: dict[str, dict[str, str]] = {}
    nodes: dict[str, NodeRecord] = {}
    root_name: str | None = None
    current_kind = ""
    current: dict[str, Any] | None = None

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        header = HEADER_RE.fullmatch(line)
        if header is not None:
            current_kind = header.group("kind")
            attrs = _parse_attrs(header.group("attrs"), f"{current_kind} at {path}:{line_number}")
            current = None
            if current_kind == "sub_resource":
                resource_id = attrs.get("id", "")
                if not resource_id or resource_id in resources:
                    raise ProjectionError(f"missing or duplicate subresource id in {path}")
                current = {"type": attrs.get("type", ""), "properties": {}}
                resources[resource_id] = current
            elif current_kind == "node":
                name = attrs.get("name", "")
                if not name:
                    raise ProjectionError(f"node missing name in {path}:{line_number}")
                parent = attrs.get("parent")
                if parent is None:
                    if root_name is not None:
                        raise ProjectionError(f"multiple wrapper roots in {path}")
                    root_name = name
                    node_path = ""
                    parent_path = None
                else:
                    if root_name is None:
                        raise ProjectionError(f"child before wrapper root in {path}:{line_number}")
                    parent_path = "" if parent == "." else parent
                    node_path = f"{parent_path}/{name}" if parent_path else name
                if node_path in nodes:
                    raise ProjectionError(f"duplicate collision shape path or node path: {node_path}")
                record = NodeRecord(node_path, attrs.get("type", ""), parent_path, {})
                nodes[node_path] = record
                current = {"record": record}
            continue
        if " = " not in line or current is None:
            continue
        key, value = line.split(" = ", 1)
        if current_kind == "sub_resource":
            current["properties"][key] = value
        elif current_kind == "node":
            current["record"].properties[key] = value

    if root_name is None:
        raise ProjectionError(f"wrapper has no root node: {path}")

    world_transforms: dict[str, Transform] = {"": Transform()}

    def world_transform(node_path: str, visiting: set[str] | None = None) -> Transform:
        if node_path in world_transforms:
            return world_transforms[node_path]
        node = nodes.get(node_path)
        if node is None or node.parent_path is None:
            raise ProjectionError(f"unresolved node path in {path}: {node_path}")
        visiting = set() if visiting is None else visiting
        if node_path in visiting:
            raise ProjectionError(f"node parent cycle in {path}: {node_path}")
        visiting.add(node_path)
        parent = world_transform(node.parent_path, visiting)
        visiting.remove(node_path)
        result = _compose(parent, _local_transform(node))
        world_transforms[node_path] = result
        return result

    boxes: list[dict[str, Any]] = []
    for node_path, node in sorted(nodes.items()):
        if node.type_name != "CollisionShape3D":
            continue
        if node.properties.get("disabled", "false") == "true":
            continue
        reference = SUBRESOURCE_RE.fullmatch(node.properties.get("shape", ""))
        if reference is None:
            raise ProjectionError(f"collision shape missing strict SubResource on {node_path}")
        resource = resources.get(reference.group(1))
        if resource is None:
            raise ProjectionError(f"collision shape references missing subresource on {node_path}")
        if resource["type"] != "BoxShape3D":
            raise ProjectionError(f"unsupported shape {resource['type']} on {node_path}")
        dimensions = _vector(resource["properties"].get("size", ""), f"box size on {node_path}")
        if any(value <= 0.0 for value in dimensions):
            raise ProjectionError(f"box size must be positive on {node_path}")
        transform = world_transform(node_path)
        boxes.append({
            "shape_path": node_path,
            "basis": list(transform.basis),
            "basis_f32_bits": _bits(transform.basis),
            "origin": list(transform.origin),
            "origin_f32_bits": _bits(transform.origin),
            "dimensions": list(dimensions),
            "dimensions_f32_bits": _bits(dimensions),
        })
    if not boxes:
        raise ProjectionError(f"wrapper has no enabled box collision shapes: {path}")
    return boxes


def _contract_wrapper(root: Path, contract_value: str) -> tuple[str, str]:
    path = _resource_path(root, contract_value, "contract")
    matches = CONTRACT_WRAPPER_RE.findall(path.read_text(encoding="utf-8"))
    if len(matches) != 1:
        raise ProjectionError(f"contract must declare exactly one top-level wrapper_scene: {contract_value}")
    return matches[0], _sha256(path.read_bytes())


def build_projection(root: Path, kit_path: Path) -> dict[str, Any]:
    root = root.resolve()
    kit_path = kit_path.resolve()
    kit = json.loads(kit_path.read_text(encoding="utf-8"))
    if not isinstance(kit, dict) or not isinstance(kit.get("modules"), list):
        raise ProjectionError("kit modules must be an array")
    modules: dict[str, Any] = {}
    for item in kit["modules"]:
        if not isinstance(item, dict):
            raise ProjectionError("kit module must be an object")
        module_id = item.get("module_id")
        wrapper_value = item.get("godot_wrapper_scene")
        contract_value = item.get("godot_contract")
        if not isinstance(module_id, str) or not module_id or module_id in modules:
            raise ProjectionError(f"missing or duplicate module_id: {module_id}")
        if not isinstance(wrapper_value, str) or not isinstance(contract_value, str):
            raise ProjectionError(f"module {module_id} lacks wrapper/contract identity")
        selected_wrapper, contract_sha = _contract_wrapper(root, contract_value)
        if selected_wrapper != wrapper_value:
            raise ProjectionError(f"contract-selected wrapper mismatch for {module_id}")
        wrapper_path = _resource_path(root, wrapper_value, "wrapper")
        boxes = _parse_wrapper(wrapper_path)
        collision_content = _collision_content_bytes(boxes)
        modules[module_id] = {
            "module_id": module_id,
            "contract_path": contract_value,
            "contract_sha256": contract_sha,
            "wrapper_scene": wrapper_value,
            "wrapper_sha256": _sha256(wrapper_path.read_bytes()),
            "content_sha256": _sha256(collision_content),
            "boxes": boxes,
        }
    return {
        "schema_version": SCHEMA_VERSION,
        "numeric_encoding": "ieee754-binary32-bits-v1",
        "content_encoding": "dock-collision-content-v1",
        "modules": dict(sorted(modules.items())),
    }


def check_projection(root: Path, kit_path: Path) -> None:
    root = root.resolve()
    kit_path = kit_path.resolve()
    kit = json.loads(kit_path.read_text(encoding="utf-8"))
    stored = kit.get("dock_collision_projection_v1") if isinstance(kit, dict) else None
    if not isinstance(stored, dict):
        raise ProjectionError("kit is missing dock_collision_projection_v1")
    modules = stored.get("modules")
    if not isinstance(modules, dict):
        raise ProjectionError("stored collision projection modules must be an object")
    for module_id, record in modules.items():
        if not isinstance(record, dict) or not isinstance(record.get("wrapper_scene"), str):
            raise ProjectionError(f"malformed stored projection for {module_id}")
        wrapper_path = _resource_path(root, record["wrapper_scene"], "wrapper")
        if record.get("wrapper_sha256") != _sha256(wrapper_path.read_bytes()):
            raise ProjectionError(f"stale wrapper hash for {module_id}")
    expected = build_projection(root, kit_path)
    if stored != expected:
        raise ProjectionError("stored collision projection is stale or malformed")


def write_projection(root: Path, kit_path: Path) -> None:
    root = root.resolve()
    kit_path = kit_path.resolve()
    kit = json.loads(kit_path.read_text(encoding="utf-8"))
    kit["dock_collision_projection_v1"] = build_projection(root, kit_path)
    kit_path.write_text(json.dumps(kit, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--kit", type=Path, default=DEFAULT_KIT)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    kit_path = args.kit if args.kit.is_absolute() else root / args.kit
    try:
        if args.write:
            write_projection(root, kit_path)
        check_projection(root, kit_path)
    except (OSError, json.JSONDecodeError, ProjectionError) as error:
        print(f"DOCK COLLISION PROJECTION FAIL: {error}")
        return 1
    projection = json.loads(kit_path.read_text(encoding="utf-8"))["dock_collision_projection_v1"]
    shape_count = sum(len(module["boxes"]) for module in projection["modules"].values())
    print(f"DOCK COLLISION PROJECTION PASS modules={len(projection['modules'])} boxes={shape_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
