#!/usr/bin/env python3
"""Read-only provenance inventory for the Focused Nine Blender masters.

The host process is intentionally pure Python: ``bpy`` only appears inside the
bounded expression sent to a fresh Blender process.  The expression opens a
blend file and reads datablocks; it never invokes a save operator.  All source
paths are constructed from fixed allowlisted layouts and every inspected file
is checked for symlinks, hardlinks, and mutation around each Blender process.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import signal
import stat
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import Any, Mapping, Sequence


SCHEMA = "focused_nine_ownership_inventory_v1"
STATUS = "needs_review"
ASSET_IDS: tuple[str, ...] = (
    "floor_1x1",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
    "ceiling_cap_1x1",
    "pressure_door_1x1",
    "hull_breach_seal_point",
    "fire_suppression_station",
)
STRUCTURAL_IDS = ASSET_IDS[:7]
PROP_IDS = ASSET_IDS[7:]
UNOWNED_IDS = ASSET_IDS[:6]
POTENTIALLY_TAINTED_IDS = ASSET_IDS[6:]
HEX64 = re.compile(r"^[0-9a-f]{64}$")
PROBE_PREFIX = "FOCUSED_NINE_PROBE "
DEFAULT_SOURCE_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshes/source")
DEFAULT_ALTERNATE_ROOT = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0_focused_nine"
)
DEFAULT_CANDIDATE_ROOT = Path("/private/tmp/focused_nine_migration_v2")
DEFAULT_QUARANTINE_ROOT = Path(
    "/Volumes/Untitled/SynapticSeaAssets/quarantine/focused-nine-ownership-2026-09-03"
)
DEFAULT_MATERIAL_LIBRARY = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/salvage_industrial.blend"
)
DEFAULT_BLENDER = Path(
    "/opt/homebrew/Caskroom/blender/5.2.0/.homebrew-command-wrappers/blender"
)
DEFAULT_OUTPUT = Path("artifacts/validation-previews/focused-nine-ownership-inventory.json")
DEFAULT_PROOF = Path("docs/superpowers/proofs/focused-nine-ownership-baseline.md")


class InventoryError(RuntimeError):
    """Raised for an unsafe input, failed probe, or non-deterministic result."""


class ExternalMutationError(InventoryError):
    """Raised when an external source changes during the read-only audit."""


def canonical_json_bytes(value: Any) -> bytes:
    """Serialize JSON-like data with the one canonical encoding used by the tool."""

    try:
        return json.dumps(
            value,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise InventoryError(f"value is not canonical JSON: {exc}") from exc


def _absolute(path: Path | str) -> Path:
    return Path(os.path.abspath(os.fspath(path)))


def _lexical_is_beneath(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def _check_no_symlink_ancestors(path: Path, stop: Path | None = None) -> None:
    """Reject a symlink anywhere in an existing lexical path chain."""

    current = path
    stop_abs = _absolute(stop) if stop is not None else None
    while True:
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            current = current.parent
            if current == current.parent:
                break
            continue
        except OSError as exc:
            raise InventoryError(f"cannot inspect path {current}: {exc}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise InventoryError(f"path contains symlink: {path}")
        if stop_abs is not None and current == stop_abs:
            break
        if current == current.parent:
            break
        current = current.parent


def _validate_root(root: Path | str, label: str) -> Path:
    root_abs = _absolute(root)
    _check_no_symlink_ancestors(root_abs)
    try:
        info = os.lstat(root_abs)
    except OSError as exc:
        raise InventoryError(f"{label} is not accessible: {root_abs}: {exc}") from exc
    if not stat.S_ISDIR(info.st_mode):
        raise InventoryError(f"{label} is not a directory: {root_abs}")
    if root_abs.resolve(strict=True) != root_abs:
        raise InventoryError(f"{label} resolves through a symlink: {root_abs}")
    return root_abs


def _validate_contained_path(path: Path | str, root: Path, label: str) -> Path:
    path_abs = _absolute(path)
    root_abs = _absolute(root)
    if not _lexical_is_beneath(path_abs, root_abs):
        raise InventoryError(f"{label} escapes allowlisted root: {path_abs}")
    _check_no_symlink_ancestors(path_abs, root_abs)
    return path_abs


def expected_live_path(source_root: Path | str, asset_id: str) -> Path:
    """Return the only live path allowed for an exact registered asset id."""

    if asset_id not in ASSET_IDS:
        raise InventoryError(f"unknown asset: {asset_id}")
    root = _absolute(source_root)
    if asset_id in STRUCTURAL_IDS:
        return root / "ship_structural_v0" / asset_id / f"{asset_id}.blend"
    return root / "props" / f"{asset_id}.blend"


def validate_live_path(source_root: Path | str, asset_id: str, path: Path | str) -> Path:
    """Require an exact lexical allowlisted live path, not merely containment."""

    root = _absolute(source_root)
    expected = expected_live_path(root, asset_id)
    candidate = _absolute(path)
    if candidate != expected:
        raise InventoryError(f"live source is not allowlisted for {asset_id}: {candidate}")
    _validate_contained_path(candidate, root, "live source")
    return candidate


def _stable_stat(info: os.stat_result) -> tuple[int, int, int, int, int]:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns)


def snapshot_file(path: Path | str) -> dict[str, Any]:
    """Hash one regular, non-symlink, non-hardlinked file with TOCTOU readback."""

    file_path = _absolute(path)
    _check_no_symlink_ancestors(file_path)
    try:
        before = os.lstat(file_path)
    except OSError as exc:
        raise InventoryError(f"cannot inspect source {file_path}: {exc}") from exc
    if stat.S_ISLNK(before.st_mode):
        raise InventoryError(f"source is a symlink: {file_path}")
    if not stat.S_ISREG(before.st_mode):
        raise InventoryError(f"source is not a regular file: {file_path}")
    if before.st_nlink != 1:
        raise InventoryError(f"source is a hardlink (link count {before.st_nlink}): {file_path}")

    digest = hashlib.sha256()
    try:
        with file_path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise InventoryError(f"cannot read source {file_path}: {exc}") from exc
    try:
        after = os.lstat(file_path)
    except OSError as exc:
        raise ExternalMutationError(f"source disappeared while hashing: {file_path}") from exc
    if _stable_stat(before) != _stable_stat(after):
        raise ExternalMutationError(f"source changed while hashing: {file_path}")

    return {
        "path": str(file_path),
        "sha256": digest.hexdigest(),
        "byte_size": before.st_size,
        "mtime_ns": before.st_mtime_ns,
        "inode": before.st_ino,
    }


def snapshot_paths(paths: Sequence[Path | str]) -> dict[str, dict[str, Any] | None]:
    """Snapshot present paths and preserve an explicit absent state for optionals."""

    result: dict[str, dict[str, Any] | None] = {}
    for raw_path in sorted({_absolute(path) for path in paths}, key=str):
        try:
            os.lstat(raw_path)
        except FileNotFoundError:
            result[str(raw_path)] = None
            continue
        result[str(raw_path)] = snapshot_file(raw_path)
    return result


def assert_snapshot_unchanged(expected: Mapping[str, Mapping[str, Any]]) -> None:
    """Re-read exact file identities and raise if a file changed."""

    for path_string, expected_snapshot in sorted(expected.items()):
        actual = snapshot_file(Path(path_string))
        if actual != dict(expected_snapshot):
            raise ExternalMutationError(f"external source changed: {path_string}")


def assert_state_unchanged(
    expected: Mapping[str, Mapping[str, Any] | None],
) -> None:
    """Recheck present and absent external paths without mutating them."""

    for path_string, expected_snapshot in sorted(expected.items()):
        path = Path(path_string)
        try:
            os.lstat(path)
        except FileNotFoundError:
            actual_snapshot = None
        else:
            actual_snapshot = snapshot_file(path)
        if actual_snapshot != expected_snapshot:
            raise ExternalMutationError(f"external source changed: {path}")


def _probe_expression(source: Path, kind: str, asset_id: str | None) -> str:
    source_literal = repr(str(source))
    kind_literal = repr(kind)
    asset_literal = repr(asset_id)
    return r'''import bpy, hashlib, json, math

def _json_value(value):
    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, float):
        return round(value, 8) if math.isfinite(value) else None
    if isinstance(value, dict):
        return {str(k): _json_value(value[k]) for k in sorted(value, key=lambda item: str(item))}
    if hasattr(value, "to_list"):
        return [_json_value(item) for item in value.to_list()]
    try:
        if not isinstance(value, (str, bytes)):
            return [_json_value(item) for item in value]
    except TypeError:
        pass
    return str(value)

def _canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")

def _digest(value):
    return hashlib.sha256(_canonical(value)).hexdigest()

def _props(owner):
    result = {}
    try:
        keys = sorted(str(key) for key in owner.keys())
        for key in keys:
            result[key] = _json_value(owner[key])
    except (AttributeError, KeyError, TypeError):
        pass
    return result

def _ownership(props):
    return {key: props[key] for key in sorted(props) if (
        "focused_nine" in key or "ownership" in key or "owner" in key or key == "asset_id"
    )}

def _q(value):
    return round(float(value), 6)

def _matrix(matrix):
    return [[_q(matrix[row][column]) for column in range(4)] for row in range(4)]

def _mesh_signatures(obj):
    mesh = getattr(obj, "data", None) if getattr(obj, "type", None) == "MESH" else None
    if mesh is None:
        return {"vertex_count": 0, "edge_count": 0, "polygon_count": 0,
                "quantized_local_geometry_signature": _digest([]),
                "face_signature": _digest([]), "geometry_signature": _digest([])}
    vertices = [[_q(vertex.co[index]) for index in range(3)] for vertex in mesh.vertices]
    faces = [{"vertices": [int(index) for index in polygon.vertices],
              "material_index": int(polygon.material_index),
              "use_smooth": bool(polygon.use_smooth)} for polygon in mesh.polygons]
    geometry_payload = {"vertices": vertices, "faces": faces}
    return {
        "vertex_count": len(mesh.vertices),
        "edge_count": len(mesh.edges),
        "polygon_count": len(mesh.polygons),
        "quantized_local_geometry_signature": _digest(vertices),
        "face_signature": _digest(faces),
        "geometry_signature": _digest(geometry_payload),
    }

def _world_aabb(obj):
    try:
        corners = [obj.matrix_world @ corner for corner in obj.bound_box]
    except (AttributeError, TypeError, ValueError):
        return None
    if not corners:
        return None
    return {
        "min": [_q(min(corner[index] for corner in corners)) for index in range(3)],
        "max": [_q(max(corner[index] for corner in corners)) for index in range(3)],
    }

def _node_tree_signature(material):
    tree = getattr(material, "node_tree", None)
    if tree is None:
        return {"nodes": [], "links": []}
    nodes = []
    for node in sorted(tree.nodes, key=lambda item: item.name):
        inputs = []
        for index, socket in enumerate(node.inputs):
            inputs.append({"index": index, "name": socket.name,
                           "default_value": _json_value(getattr(socket, "default_value", None))})
        nodes.append({
            "name": node.name, "type": node.bl_idname, "label": node.label,
            "mute": bool(node.mute), "hide": bool(node.hide),
            "location": [_q(node.location[0]), _q(node.location[1])],
            "inputs": inputs,
        })
    links = []
    for link in tree.links:
        links.append({"from_node": link.from_node.name, "from_socket": link.from_socket.name,
                      "to_node": link.to_node.name, "to_socket": link.to_socket.name})
    links.sort(key=lambda item: tuple(item.values()))
    return {"nodes": nodes, "links": links}

def _material_record(material):
    props = _props(material)
    node_tree = _node_tree_signature(material)
    return {
        "name": material.name,
        "ownership_ids": _ownership(props),
        "source_library": (
            getattr(getattr(material, "library", None), "filepath", None)
            or props.get("focused_nine_source_library")
            or None
        ),
        "node_tree_signature": node_tree,
        "value_signature": _digest(node_tree),
        "properties": props,
    }

def _object_record(obj, expected_asset_id):
    props = _props(obj)
    mesh_info = _mesh_signatures(obj)
    slots = []
    for index, slot in enumerate(getattr(obj, "material_slots", [])):
        material = getattr(slot, "material", None)
        slots.append({"index": index, "name": material.name if material else None,
                      "signature": _digest(_material_record(material)) if material else None})
    matrix = _matrix(obj.matrix_basis)
    identity = all(matrix[row][column] == (1.0 if row == column else 0.0)
                   for row in range(4) for column in range(4))
    ownership = _ownership(props)
    return {
        "name": obj.name,
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "collections": sorted(collection.name for collection in obj.users_collection),
        "ownership_ids": ownership,
        "properties": props,
        "vertex_count": mesh_info["vertex_count"],
        "edge_count": mesh_info["edge_count"],
        "polygon_count": mesh_info["polygon_count"],
        "applied_transform": {"is_identity_basis": identity, "matrix_basis": matrix},
        "quantized_local_geometry_signature": mesh_info["quantized_local_geometry_signature"],
        "face_signature": mesh_info["face_signature"],
        "geometry_signature": mesh_info["geometry_signature"],
        "world_aabb": _world_aabb(obj),
        "used_material_slots": slots,
        "material_signature": _digest(slots),
        "expected_asset_id_match": ownership.get("focused_nine_asset_id") == expected_asset_id,
    }

def _collection_record(collection):
    props = _props(collection)
    return {"name": collection.name, "ownership_ids": _ownership(props), "properties": props}

def _run():
    source = __SOURCE__
    expected_asset_id = __ASSET__
    objects = sorted(bpy.data.objects, key=lambda item: item.name)
    object_records = [_object_record(obj, expected_asset_id) for obj in objects if obj.name.startswith("FocusedNine_")]
    collections = sorted((_collection_record(collection) for collection in bpy.data.collections), key=lambda item: item["name"])
    materials = sorted((_material_record(material) for material in bpy.data.materials), key=lambda item: item["name"])
    expected_prefix = "FocusedNine_" + expected_asset_id if expected_asset_id else None
    unexpected_names = sorted(
        obj.name for obj in objects if obj.name.startswith("FocusedNine_") and
        (expected_prefix is None or not obj.name.startswith(expected_prefix))
    )
    record = {
        "kind": __KIND__,
        "source_path": source,
        "expected_asset_id": expected_asset_id,
        "collections": collections,
        "objects": object_records,
        "materials": materials,
        "unexpected_names": unexpected_names,
    }
    print("FOCUSED_NINE_PROBE " + json.dumps(record, ensure_ascii=True, sort_keys=True, separators=(",", ":")))

try:
    bpy.ops.wm.open_mainfile(filepath=__SOURCE__)
    _run()
except Exception as exc:
    print("FOCUSED_NINE_PROBE_ERROR " + json.dumps({"error": type(exc).__name__ + ": " + str(exc)}, ensure_ascii=True, sort_keys=True))
''' \
        .replace("__SOURCE__", source_literal) \
        .replace("__KIND__", kind_literal) \
        .replace("__ASSET__", asset_literal)


def parse_probe_output(output: str) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    for line in output.splitlines():
        if not line.startswith(PROBE_PREFIX):
            continue
        payload = line[len(PROBE_PREFIX) :]
        try:
            value = json.loads(payload)
        except json.JSONDecodeError as exc:
            raise InventoryError(f"malformed probe record: {exc.msg}") from exc
        if not isinstance(value, dict):
            raise InventoryError("malformed probe record: expected object")
        records.append(value)
    if not records:
        error_lines = [line for line in output.splitlines() if line.startswith("FOCUSED_NINE_PROBE_ERROR ")]
        if error_lines:
            raise InventoryError(error_lines[0])
        raise InventoryError("missing probe record")
    if len(records) != 1:
        raise InventoryError("duplicate probe records")
    validate_probe_record(records[0])
    return records[0]


def validate_probe_record(record: Mapping[str, Any]) -> None:
    """Reject structurally malformed probe records before using their evidence."""

    if not isinstance(record, dict):
        raise InventoryError("malformed probe record: expected object")
    if not isinstance(record.get("kind"), str) or not record["kind"]:
        raise InventoryError("malformed probe record: missing kind")
    objects = record.get("objects")
    if not isinstance(objects, list):
        raise InventoryError("malformed probe record: objects must be a list")
    names: list[str] = []
    for obj in objects:
        if not isinstance(obj, dict) or not isinstance(obj.get("name"), str):
            raise InventoryError("malformed probe record: object is missing name")
        names.append(obj["name"])
    if len(names) != len(set(names)):
        raise InventoryError("duplicate probe object names")


def run_blender_probe(
    blender: Path | str,
    source: Path | str,
    *,
    kind: str = "blend",
    asset_id: str | None = None,
    timeout: float = 120.0,
) -> dict[str, Any]:
    """Run one read-only Blender probe in a fresh process group."""

    blender_path = os.fspath(blender)
    source_path = _absolute(source)
    expression = _probe_expression(source_path, kind, asset_id)
    command = [
        blender_path,
        "--background",
        "--factory-startup",
        "--python-expr",
        expression,
    ]
    process: subprocess.Popen[str] | None = None
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5.0)
        raise InventoryError(f"Blender probe timed out after {timeout:.3f}s: {source_path}") from exc
    except OSError as exc:
        raise InventoryError(f"could not launch Blender: {exc}") from exc

    if process.returncode != 0:
        detail = (stderr or stdout or "no process output").strip().splitlines()
        raise InventoryError(
            f"Blender probe failed for {source_path}: " + (detail[-1] if detail else "unknown error")
        )
    record = parse_probe_output(stdout)
    if record.get("kind") != kind:
        raise InventoryError(f"probe kind mismatch for {source_path}")
    return record


def _object_geometry_keys(record: Mapping[str, Any]) -> list[tuple[Any, ...]]:
    objects = record.get("objects", [])
    if not isinstance(objects, list):
        return []
    keys: list[tuple[Any, ...]] = []
    for obj in objects:
        if isinstance(obj, dict):
            keys.append((
                obj.get("geometry_signature"),
                obj.get("face_signature"),
                obj.get("quantized_local_geometry_signature"),
            ))
    return sorted(keys, key=lambda item: canonical_json_bytes(item))


def _object_ownership_keys(record: Mapping[str, Any]) -> list[Any]:
    objects = record.get("objects", [])
    values = [obj.get("ownership_ids", {}) for obj in objects if isinstance(obj, dict)]
    return sorted(values, key=canonical_json_bytes)


def _object_material_keys(record: Mapping[str, Any]) -> list[Any]:
    objects = record.get("objects", [])
    values = [obj.get("material_signature") for obj in objects if isinstance(obj, dict)]
    return sorted(values, key=canonical_json_bytes)


def compare_object_signatures(
    canonical: Mapping[str, Any], candidate: Mapping[str, Any]
) -> dict[str, str]:
    """Compare one object without treating its name as proof of identity."""

    reasons: list[str] = []
    if canonical.get("geometry_signature") != candidate.get("geometry_signature"):
        reasons.append("geometry signature differs")
    if canonical.get("face_signature") != candidate.get("face_signature"):
        reasons.append("face signature differs")
    if canonical.get("ownership_ids") != candidate.get("ownership_ids"):
        reasons.append("ownership IDs differ")
    if canonical.get("material_signature") != candidate.get("material_signature"):
        reasons.append("material signature differs")
    return {
        "status": "exact_geometry_match" if not reasons else "mismatch",
        "reason": "signatures match" if not reasons else "; ".join(reasons),
    }


def compare_probe_signatures(
    canonical: Mapping[str, Any], candidate: Mapping[str, Any] | None, *, absent_reason: str
) -> dict[str, str]:
    if candidate is None:
        return {"status": "absent", "reason": absent_reason}
    reasons: list[str] = []
    if _object_geometry_keys(canonical) != _object_geometry_keys(candidate):
        reasons.append("geometry or face signatures differ")
    if _object_ownership_keys(canonical) != _object_ownership_keys(candidate):
        reasons.append("ownership IDs differ")
    if _object_material_keys(canonical) != _object_material_keys(candidate):
        reasons.append("material signatures differ")
    if canonical.get("collections") != candidate.get("collections"):
        reasons.append("collection ownership properties differ")
    return {
        "status": "exact_geometry_match" if not reasons else "mismatch",
        "reason": "signatures match" if not reasons else "; ".join(reasons),
    }


def _safe_archive_member(name: str) -> None:
    path = Path(name)
    if path.is_absolute() or ".." in path.parts:
        raise InventoryError(f"quarantine archive contains unsafe member path: {name}")


def inspect_quarantine(root: Path | str) -> dict[str, Any]:
    """Read the forensic manifest/archive without extracting or executing members."""

    quarantine_root = _validate_root(root, "quarantine root")
    manifest_path = quarantine_root / "manifest.json"
    archive_path = quarantine_root / "untrusted-leftovers.tar.gz"
    manifest_snapshot = snapshot_file(manifest_path)
    archive_snapshot = snapshot_file(archive_path)
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InventoryError(f"invalid quarantine manifest: {exc}") from exc
    if not isinstance(manifest, dict) or manifest.get("document_kind") != "focused_nine_ownership_forensic_quarantine":
        raise InventoryError("quarantine manifest has unexpected document kind")
    entries = manifest.get("entries")
    if not isinstance(entries, list):
        raise InventoryError("quarantine manifest entries must be a list")
    normalized_entries: list[dict[str, Any]] = []
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise InventoryError("quarantine manifest contains malformed entry")
        archive_member = entry.get("archive_path")
        digest = entry.get("sha256")
        size = entry.get("byte_size")
        if not isinstance(archive_member, str) or archive_member in seen:
            raise InventoryError("quarantine manifest contains duplicate or invalid archive path")
        if not isinstance(digest, str) or HEX64.fullmatch(digest) is None:
            raise InventoryError("quarantine manifest contains invalid SHA-256")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise InventoryError("quarantine manifest contains invalid byte size")
        _safe_archive_member(archive_member)
        seen.add(archive_member)
        normalized_entries.append({"archive_path": archive_member, "byte_size": size, "sha256": digest})

    members: list[dict[str, Any]] = []
    try:
        with tarfile.open(archive_path, mode="r:gz") as archive:
            for member in sorted(archive.getmembers(), key=lambda item: item.name):
                _safe_archive_member(member.name)
                if member.issym() or member.islnk():
                    raise InventoryError(f"quarantine archive contains link member: {member.name}")
                if member.isfile():
                    handle = archive.extractfile(member)
                    if handle is None:
                        raise InventoryError(f"cannot read quarantine member: {member.name}")
                    digest = hashlib.sha256()
                    size = 0
                    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                        digest.update(chunk)
                        size += len(chunk)
                    members.append({"archive_path": member.name, "byte_size": size, "sha256": digest.hexdigest()})
    except (OSError, tarfile.TarError) as exc:
        raise InventoryError(f"invalid quarantine archive: {exc}") from exc

    manifest_by_path = {entry["archive_path"]: entry for entry in normalized_entries}
    archive_by_path = {member["archive_path"]: member for member in members}
    if set(manifest_by_path) != set(archive_by_path):
        raise InventoryError("quarantine manifest and archive member sets differ")
    for archive_member, expected in sorted(manifest_by_path.items()):
        actual = archive_by_path[archive_member]
        if (
            actual["byte_size"] != expected["byte_size"]
            or actual["sha256"] != expected["sha256"]
        ):
            raise InventoryError(f"quarantine archive evidence hash mismatch: {archive_member}")

    return {
        "manifest": manifest_snapshot,
        "archive": archive_snapshot,
        "entries": sorted(normalized_entries, key=lambda item: item["archive_path"]),
        "archive_members": members,
        "warning": manifest.get("warning", ""),
    }


def _candidate_path(root: Path, asset_id: str) -> Path:
    return root / f"{asset_id}_migrated.blend"


def _alternate_path(root: Path, asset_id: str) -> Path:
    if asset_id in STRUCTURAL_IDS:
        if root.name == "ship_structural_v0_focused_nine":
            return root / asset_id / f"{asset_id}.blend"
        return root / "ship_structural_v0_focused_nine" / asset_id / f"{asset_id}.blend"
    if root.name == "props":
        return root / f"{asset_id}.blend"
    return root / "props" / f"{asset_id}.blend"


def _optional_root(root: Path | None, label: str) -> Path | None:
    if root is None or not os.path.lexists(root):
        return None
    return _validate_root(root, label)


def _git_head(project_root: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(project_root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10.0,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise InventoryError(f"could not read repository HEAD: {exc}") from exc
    head = result.stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise InventoryError("repository HEAD is not a full hexadecimal commit")
    return head


def _blender_info(blender: Path) -> dict[str, Any]:
    binary = snapshot_file(blender)
    try:
        result = subprocess.run(
            [str(blender), "--version"], check=True, capture_output=True, text=True, timeout=30.0
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise InventoryError(f"could not query Blender version: {exc}") from exc
    version = next((line.strip() for line in result.stdout.splitlines() if line.strip()), "")
    if not version:
        raise InventoryError("Blender did not report a version")
    return {"path": str(blender), "version": version, "sha256": binary["sha256"]}


def _output_path(project_root: Path, path: Path | str, expected_relative: Path) -> Path:
    raw_path = Path(path)
    output = _absolute(project_root / raw_path) if not raw_path.is_absolute() else _absolute(raw_path)
    expected = _absolute(project_root / expected_relative)
    if output != expected:
        raise InventoryError(f"output path must be exactly {expected}: {output}")
    _validate_contained_path(output, project_root, "output")
    if output.exists():
        snapshot_file(output)
    return output


def _write_repo_file(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        info = os.lstat(path)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise InventoryError(f"refusing unsafe repository output: {path}")
    path.write_bytes(content)


def _asset_kind(asset_id: str) -> str:
    return "structural" if asset_id in STRUCTURAL_IDS else "props"


def build_closed_manifest(
    *,
    repository_head: str,
    tool_snapshot: Mapping[str, Any],
    blender_info: Mapping[str, Any],
    material_library: Mapping[str, Any],
    quarantine: Mapping[str, Any],
    assets: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Build the closed, timestamp-free manifest document."""

    if any(not isinstance(asset, Mapping) for asset in assets):
        raise InventoryError("manifest asset records must be objects")
    by_id = {asset.get("asset_id"): dict(asset) for asset in assets}
    if set(by_id) != set(ASSET_IDS) or len(by_id) != len(ASSET_IDS):
        raise InventoryError("manifest must contain exactly one record for each Focused Nine asset")
    ordered_assets = [by_id[asset_id] for asset_id in ASSET_IDS]
    for index, asset in enumerate(ordered_assets):
        asset.setdefault("kind", _asset_kind(ASSET_IDS[index]))
        asset.setdefault("ownership_status", "unowned" if ASSET_IDS[index] in UNOWNED_IDS else "potentially_tainted")
    return {
        "schema": SCHEMA,
        "status": STATUS,
        "repository_head": repository_head,
        "tool": dict(tool_snapshot),
        "blender": dict(blender_info),
        "material_library": dict(material_library),
        "quarantine": dict(quarantine),
        "assets": ordered_assets,
        "summary": {
            "asset_count": len(ASSET_IDS),
            "unowned_count": len(UNOWNED_IDS),
            "potentially_tainted_count": len(POTENTIALLY_TAINTED_IDS),
            "unowned_assets": list(UNOWNED_IDS),
            "potentially_tainted_assets": list(POTENTIALLY_TAINTED_IDS),
        },
    }


def _asset_snapshot_paths(
    source_root: Path,
    alternate_root: Path | None,
    candidate_root: Path | None,
    material_library: Path,
    quarantine_root: Path | None,
) -> tuple[list[Path], dict[str, list[Path]]]:
    live_paths = [validate_live_path(source_root, asset_id, expected_live_path(source_root, asset_id)) for asset_id in ASSET_IDS]
    optional: dict[str, list[Path]] = {"alternate": [], "candidate": [], "quarantine": []}
    if alternate_root is not None:
        optional["alternate"] = [_alternate_path(alternate_root, asset_id) for asset_id in ASSET_IDS]
    if candidate_root is not None:
        optional["candidate"] = [_candidate_path(candidate_root, asset_id) for asset_id in ASSET_IDS]
    if quarantine_root is not None:
        optional["quarantine"] = [quarantine_root / "manifest.json", quarantine_root / "untrusted-leftovers.tar.gz"]
    paths = live_paths + [material_library]
    root_for_group = {
        "alternate": alternate_root,
        "candidate": candidate_root,
        "quarantine": quarantine_root,
    }
    for group_name, group in optional.items():
        group_root = root_for_group[group_name]
        for path in group:
            if group_root is None:
                continue
            _validate_contained_path(path, group_root, f"{group_name} source")
            if os.path.lexists(path):
                paths.append(path)
    return paths, {"live": live_paths, **optional}


def run_inventory(args: argparse.Namespace) -> tuple[dict[str, Any], dict[str, Any]]:
    project_root = _validate_root(args.project_root, "project root")
    source_root = _validate_root(args.source_root, "live source root")
    material_library = _absolute(args.material_library)
    _check_no_symlink_ancestors(material_library)
    alternate_root = _optional_root(args.alternate_root, "alternate source root")
    candidate_root = _optional_root(args.candidate_root, "candidate source root")
    quarantine_root = _optional_root(args.quarantine_root, "quarantine root")
    blender = _absolute(args.blender)
    _check_no_symlink_ancestors(blender)
    tool_snapshot = snapshot_file(Path(__file__))
    blender_info = _blender_info(blender)
    repository_head = _git_head(project_root)

    paths, groups = _asset_snapshot_paths(
        source_root, alternate_root, candidate_root, material_library, quarantine_root
    )
    initial_state = snapshot_paths(paths)
    for path in groups["live"]:
        if initial_state[str(path)] is None:
            raise InventoryError(f"required live source is missing: {path}")
    if initial_state[str(material_library)] is None:
        raise InventoryError(f"canonical material library is missing: {material_library}")

    quarantine = inspect_quarantine(quarantine_root) if quarantine_root else {
        "manifest": None, "archive": None, "entries": [], "archive_members": [], "warning": "not provided"
    }
    assert_state_unchanged(initial_state)

    def probe(path: Path, *, kind: str, asset_id: str | None) -> dict[str, Any]:
        assert_state_unchanged(initial_state)
        record = run_blender_probe(
            blender, path, kind=kind, asset_id=asset_id, timeout=float(args.timeout)
        )
        assert_state_unchanged(initial_state)
        return record

    material_probe = probe(material_library, kind="material_library", asset_id=None)
    material_record = dict(initial_state[str(material_library)] or {})
    material_record["materials"] = material_probe.get("materials", [])
    material_record["probe_kind"] = material_probe.get("kind")

    assets: list[dict[str, Any]] = []
    external_before_after: list[dict[str, Any]] = []
    for asset_id in ASSET_IDS:
        live_path = expected_live_path(source_root, asset_id)
        live_snapshot = initial_state[str(live_path)]
        if live_snapshot is None:
            raise InventoryError(f"required live source is missing: {live_path}")
        canonical_probe = probe(live_path, kind="blend", asset_id=asset_id)
        alternate_probe: dict[str, Any] | None = None
        candidate_probe: dict[str, Any] | None = None
        alternate_path: Path | None = None
        candidate_path: Path | None = None
        if alternate_root is not None:
            alternate_path = _alternate_path(alternate_root, asset_id)
            if initial_state.get(str(alternate_path)) is not None:
                alternate_probe = probe(alternate_path, kind="blend", asset_id=asset_id)
        if candidate_root is not None:
            candidate_path = _candidate_path(candidate_root, asset_id)
            if initial_state.get(str(candidate_path)) is not None:
                candidate_probe = probe(candidate_path, kind="blend", asset_id=asset_id)
        object_records = canonical_probe.get("objects", [])
        has_explicit_ownership = any(
            isinstance(obj, dict) and bool(obj.get("ownership_ids")) for obj in object_records
        )
        ownership_status = "potentially_tainted" if asset_id in POTENTIALLY_TAINTED_IDS or has_explicit_ownership else "unowned"
        comparisons = [
            {
                "source": "alternate",
                "path": str(alternate_path) if alternate_path else None,
                **compare_probe_signatures(
                    canonical_probe,
                    alternate_probe,
                    absent_reason="alternate source absent",
                ),
            },
            {
                "source": "quarantined_candidate",
                "path": str(candidate_path) if candidate_path else None,
                **compare_probe_signatures(
                    canonical_probe,
                    candidate_probe,
                    absent_reason="quarantined candidate absent",
                ),
            },
        ]
        assets.append({
            "asset_id": asset_id,
            "kind": _asset_kind(asset_id),
            "ownership_status": ownership_status,
            "unexpected_names": canonical_probe.get("unexpected_names", []),
            "canonical": {**dict(live_snapshot), "probe": canonical_probe},
            "comparisons": comparisons,
        })
        external_before_after.append({
            "asset_id": asset_id,
            "path": str(live_path),
            "sha256": live_snapshot["sha256"],
            "byte_size": live_snapshot["byte_size"],
            "mtime_ns": live_snapshot["mtime_ns"],
            "inode": live_snapshot["inode"],
        })

    assert_state_unchanged(initial_state)
    manifest = build_closed_manifest(
        repository_head=repository_head,
        tool_snapshot=tool_snapshot,
        blender_info=blender_info,
        material_library=material_record,
        quarantine=quarantine,
        assets=assets,
    )
    return manifest, {"external_before_after": external_before_after}


def write_outputs(
    project_root: Path,
    manifest: Mapping[str, Any],
    evidence: Mapping[str, Any],
    output: Path,
    proof: Path,
) -> tuple[Path, Path, str]:
    output_bytes = canonical_json_bytes(manifest)
    output_path = _output_path(project_root, output, DEFAULT_OUTPUT)
    proof_path = _output_path(project_root, proof, DEFAULT_PROOF)
    _write_repo_file(output_path, output_bytes)
    manifest_hash = hashlib.sha256(output_bytes).hexdigest()
    lines = [
        "# Focused Nine Ownership Baseline",
        "",
        f"Manifest path: `{output_path.relative_to(project_root).as_posix()}`",
        f"Manifest SHA-256: `{manifest_hash}`",
        f"Manifest schema: `{manifest['schema']}`",
        f"Status: `{manifest['status']}`",
        "",
        "This is a read-only provenance inventory. No migration, promotion, replacement, quarantine execution, or Blender save occurred.",
        "External source before/after observations are identical for every Focused Nine live master.",
        "",
        "| Asset | Source SHA-256 | Bytes | mtime_ns | inode |",
        "|---|---|---:|---:|---:|",
    ]
    for row in evidence["external_before_after"]:
        lines.append(
            f"| `{row['asset_id']}` | `{row['sha256']}` | {row['byte_size']} | {row['mtime_ns']} | {row['inode']} |"
        )
    lines.extend([
        "",
        f"Summary: six unowned, three potentially tainted; review status remains `{STATUS}`.",
    ])
    _write_repo_file(proof_path, "\n".join(lines).encode("utf-8"))
    return output_path, proof_path, manifest_hash


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE_ROOT)
    parser.add_argument("--alternate-root", type=Path, default=DEFAULT_ALTERNATE_ROOT)
    parser.add_argument("--candidate-root", type=Path, default=DEFAULT_CANDIDATE_ROOT)
    parser.add_argument("--quarantine-root", type=Path, default=DEFAULT_QUARANTINE_ROOT)
    parser.add_argument("--material-library", type=Path, default=DEFAULT_MATERIAL_LIBRARY)
    parser.add_argument("--blender", type=Path, default=DEFAULT_BLENDER)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--proof", type=Path, default=DEFAULT_PROOF)
    parser.add_argument("--timeout", type=float, default=120.0)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        manifest, evidence = run_inventory(args)
        output_path, proof_path, manifest_hash = write_outputs(
            _validate_root(args.project_root, "project root"),
            manifest,
            evidence,
            args.output,
            args.proof,
        )
    except InventoryError as exc:
        print(f"FOCUSED_NINE_INVENTORY ERROR {exc}", file=sys.stderr)
        return 1
    print(
        "FOCUSED_NINE_OWNERSHIP_INVENTORY PASS "
        f"schema={SCHEMA} status={STATUS} assets={len(ASSET_IDS)} "
        f"manifest={output_path} proof={proof_path} sha256={manifest_hash}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
