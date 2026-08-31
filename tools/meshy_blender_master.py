#!/usr/bin/env python3
"""Create the external Blender master for a selected Meshy candidate.

The host-Python path in this module only validates inputs and launches Blender.
The Blender-only implementation imports ``bpy`` lazily, so contract and command
construction tests do not require Blender's Python modules.
"""

from __future__ import annotations

import argparse
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional, Sequence, Union

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.meshy_asset_contract import AssetContract, load_contract  # noqa: E402


BLENDER_PATH = "/opt/homebrew/bin/blender"
MASTER_SOURCE_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source")
MASTER_ROOT = MASTER_SOURCE_ROOT
PROTECTED_RELATIVE = (
    Path("assets/imported"),
    Path("data/combat"),
    Path("data/props"),
    Path("scenes/wrappers"),
)
PROTECTED_RUNTIME_PATHS = PROTECTED_RELATIVE
_IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")


PathLike = Union[str, os.PathLike]


class BlenderMasterError(ValueError):
    """Raised when a Blender master request is unsafe or invalid."""


def _as_path(value: PathLike) -> Path:
    return Path(value).expanduser()


def _project_path(project_root: Path, value: Path) -> Path:
    path = _as_path(value)
    if not path.is_absolute():
        path = _as_path(project_root) / path
    return path


def _safe_asset_id(asset_id: object) -> str:
    if not isinstance(asset_id, str) or _IDENTIFIER_RE.fullmatch(asset_id) is None:
        raise BlenderMasterError("asset_id must be a lowercase identifier")
    return asset_id


def derive_master_path(asset_id: Union[str, AssetContract], optional_asset_id: Optional[str] = None) -> Path:
    """Return the exact external editable-source path for ``asset_id``.

    ``optional_asset_id`` is accepted for compatibility with callers that pass
    a project root as the first positional argument; the master is always on
    the fixed external source volume.
    """

    if optional_asset_id is not None:
        candidate = optional_asset_id
    elif isinstance(asset_id, AssetContract):
        candidate = asset_id.asset_id
    else:
        candidate = asset_id
    safe_asset_id = _safe_asset_id(candidate)
    return MASTER_ROOT / safe_asset_id / (safe_asset_id + "_master.blend")


def _contained(root: Path, candidate: Path) -> bool:
    return candidate == root or root in candidate.parents


def _reject_symlink_components(path: Path, label: str) -> None:
    absolute = Path(os.path.abspath(os.fspath(path)))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            break
        except OSError as exc:
            raise BlenderMasterError("cannot inspect " + label) from exc
        if stat.S_ISLNK(mode):
            raise BlenderMasterError(label + " contains symlink component")


def reject_protected_output_path(
    master_path: PathLike, project_root: Optional[PathLike] = None
) -> Path:
    """Reject a master output inside a live runtime surface.

    ``project_root`` is optional to make the policy helper useful to callers
    that already have an absolute path.  The normal CLI always supplies it.
    """

    target = _as_path(master_path).resolve(strict=False)
    _reject_symlink_components(target, "master output path")
    roots = []  # type: List[Path]
    if project_root is not None:
        root = _as_path(project_root).resolve(strict=False)
        roots.extend((root / relative).resolve(strict=False) for relative in PROTECTED_RELATIVE)
    # Also inspect path components so a caller cannot bypass the policy by
    # passing a path rooted elsewhere with the same protected suffix.
    parts = target.parts
    protected_pairs = {
        ("assets", "imported"),
        ("data", "combat"),
        ("data", "props"),
        ("scenes", "wrappers"),
    }
    for index in range(len(parts) - 1):
        if (parts[index], parts[index + 1]) in protected_pairs:
            raise BlenderMasterError("master output path is protected")
    if any(_contained(protected, target) for protected in roots):
        raise BlenderMasterError("master output path is protected")
    return target


def build_blender_command(
    project_root: PathLike,
    contract: PathLike,
    task_dir: PathLike,
    reviewer: str,
    blender: str = BLENDER_PATH,
) -> List[str]:
    """Build the canonical host-to-Blender invocation without running it."""

    if not isinstance(reviewer, str) or not reviewer.strip():
        raise BlenderMasterError("reviewer must be non-empty text")
    return [
        blender,
        "--background",
        "--factory-startup",
        "--python",
        str(Path(__file__).resolve()),
        "--",
        "--project-root",
        str(_as_path(project_root)),
        "--contract",
        str(_as_path(contract)),
        "--task-dir",
        str(_as_path(task_dir)),
        "--reviewer",
        reviewer,
    ]


def _regular_file(path: Path, label: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise BlenderMasterError(label + " must be a regular file")
    return path


def _request_inputs(
    project_root: Path, contract_path: Path, task_dir: Path, reviewer: str
) -> tuple[AssetContract, Path, Path]:
    if not reviewer.strip():
        raise BlenderMasterError("reviewer must be non-empty text")
    root = _as_path(project_root).resolve(strict=False)
    contract = load_contract(_project_path(root, contract_path))
    resolved_task_dir = _project_path(root, task_dir).resolve(strict=False)
    raw_path = _regular_file(resolved_task_dir / "raw.glb", "raw.glb")
    master_path = reject_protected_output_path(
        derive_master_path(contract.asset_id), project_root=project_root
    )
    return contract, raw_path, master_path


def _is_blender_runtime() -> bool:
    executable = Path(sys.executable).name.lower()
    return executable.startswith("blender") or "--background" in sys.argv


def _runtime_argv(argv: Optional[Sequence[str]]) -> Optional[List[str]]:
    if argv is not None:
        return list(argv)
    if "--" not in sys.argv:
        return None
    return list(sys.argv[sys.argv.index("--") + 1 :])


def _ensure_collection(bpy: object, scene: object, name: str) -> object:
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    if scene.collection.children.get(name) is None:
        scene.collection.children.link(collection)
    return collection


def _link_only(obj: object, collection: object) -> None:
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    collection.objects.link(obj)


def _save_blend_atomically(bpy: object, master_path: Path) -> None:
    master_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix="." + master_path.name + ".", suffix=".tmp", dir=str(master_path.parent)
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        result = bpy.ops.wm.save_as_mainfile(filepath=str(temporary))
        if getattr(result, "__contains__", lambda _value: False)("CANCELLED"):
            raise BlenderMasterError("Blender could not save the master")
        os.replace(str(temporary), str(master_path))
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def run_blender_master(
    raw_path: Path, master_path: Path, contract: AssetContract, reviewer: str
) -> None:
    """Run the Blender-only import, organization, marker, and save steps."""

    # Deliberately local: importing bpy at module import time would make host
    # tests depend on Blender's Python environment.
    import bpy  # type: ignore

    scene = bpy.context.scene
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection, do_unlink=True)

    source_raw = _ensure_collection(bpy, scene, "SOURCE_RAW")
    working = _ensure_collection(bpy, scene, "WORKING")
    sockets_markers = _ensure_collection(bpy, scene, "SOCKETS_MARKERS")
    _ensure_collection(bpy, scene, "EXPORT")
    source_raw.hide_viewport = True
    source_raw.hide_render = True

    before = set(bpy.data.objects)
    result = bpy.ops.import_scene.gltf(filepath=str(raw_path))
    if "FINISHED" not in result:
        raise BlenderMasterError("Blender could not import raw.glb")
    imported = [obj for obj in bpy.data.objects if obj not in before]
    source_meshes = [obj for obj in imported if obj.type == "MESH"]
    if not source_meshes:
        raise BlenderMasterError("raw.glb contains no mesh geometry")

    for obj in imported:
        _link_only(obj, source_raw)
        obj.hide_viewport = True
        obj.hide_render = True
        obj.hide_select = True
        obj["meshy_source_raw"] = True

    for source_obj in source_meshes:
        duplicate = source_obj.copy()
        duplicate.data = source_obj.data.copy()
        duplicate.name = source_obj.name + "_WORKING"
        working.objects.link(duplicate)
        duplicate.hide_viewport = False
        duplicate.hide_render = False
        duplicate.hide_select = False
        duplicate["meshy_working_copy"] = True

    dimensions = contract.document["dimensions_m"]
    marker_height = max(float(dimensions[2]), 0.001)
    origin = bpy.data.objects.new("ORIGIN_MARKER", None)
    origin.empty_display_type = "PLAIN_AXES"
    origin.empty_display_size = max(max(float(value) for value in dimensions) * 0.1, 0.05)
    origin["pivot_policy"] = contract.document["pivot"]
    origin["asset_id"] = contract.asset_id
    sockets_markers.objects.link(origin)

    forward = bpy.data.objects.new("FORWARD_Z_MARKER", None)
    forward.empty_display_type = "ARROWS"
    forward.empty_display_size = max(marker_height * 0.5, 0.05)
    forward.location = (0.0, 0.0, marker_height)
    forward["forward_axis"] = "+Z"
    forward["asset_id"] = contract.asset_id
    sockets_markers.objects.link(forward)

    scene["meshy_asset_id"] = contract.asset_id
    scene["meshy_contract_sha256"] = contract.sha256
    scene["meshy_reviewer"] = reviewer
    scene["meshy_master_source"] = str(master_path)
    _save_blend_atomically(bpy, master_path)
    print(
        "MESHY BLENDER MASTER READY asset={0} master={1}".format(
            contract.asset_id, master_path
        )
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--task-dir", type=Path, required=True)
    parser.add_argument("--reviewer", required=True)
    return parser


# Kept as discoverable aliases for callers that use the naming conventions of
# the other repository tools.
_build_parser = build_parser


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    """Parse host or Blender arguments without importing ``bpy``."""

    return build_parser().parse_args(_runtime_argv(argv) if argv is None and _is_blender_runtime() else argv)


master_path_for_asset = derive_master_path
validate_master_output_path = reject_protected_output_path
reject_protected_path = reject_protected_output_path
build_master_command = build_blender_command


def main(argv: Optional[Sequence[str]] = None) -> int:
    runtime = _is_blender_runtime() if argv is None else False
    parse_argv = _runtime_argv(argv) if runtime else argv
    try:
        args = build_parser().parse_args(parse_argv)
        contract, raw_path, master_path = _request_inputs(
            args.project_root, args.contract, args.task_dir, args.reviewer
        )
        if runtime:
            run_blender_master(raw_path, master_path, contract, args.reviewer)
            return 0

        command = build_blender_command(
            project_root=args.project_root,
            contract=args.contract,
            task_dir=args.task_dir,
            reviewer=args.reviewer,
        )
        completed = subprocess.run(command, cwd=str(args.project_root), check=False)
        if completed.returncode != 0:
            return completed.returncode
        print(
            "MESHY BLENDER MASTER COMMAND PASS asset={0} master={1}".format(
                contract.asset_id, master_path
            )
        )
        return 0
    except (BlenderMasterError, OSError, ValueError) as exc:
        print("meshy_blender_master: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
