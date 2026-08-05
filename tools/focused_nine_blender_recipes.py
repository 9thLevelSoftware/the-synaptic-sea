#!/usr/bin/env python3
"""Idempotent, generated-only visual recipes for the focused nine assets.

The contract and selection helpers in this module are importable with ordinary
Python.  Blender is imported lazily, after the asset id and source paths have
been validated, so a typo cannot start a Blender mutation.

The two source roots are intentionally distinct:

* ``--structural-source-root`` contains ``<asset>/<asset>.blend`` under the
  ``ship_structural_v0`` kit source directory.
* ``--props-source-root`` contains ``<asset>.blend`` files directly.

Only objects in the generated namespace ``FocusedNine_<asset_id>_`` with the
explicit generated marker and matching asset id are removed.  Authored objects,
helpers, collections, and runtime assets are never cleared or replaced by this
driver.

Trusted-workspace boundary: after the initial path and inode observations, the
caller must approve a same-user trusted workspace for Blender's path-based
open/save. Blender cannot be given an FD-pinned ``.blend`` path here, so these
checks do not solve a same-user rebind race after the observations; that race is
outside this boundary rather than being silently claimed safe.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any, Iterable, Sequence

try:
    from tools import focused_nine_contract
    from tools.structural_source_contract import load_source_spec
except ModuleNotFoundError:  # Blender executes a script with tools as sys.path[0].
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools import focused_nine_contract
    from tools.structural_source_contract import load_source_spec


STRUCTURAL_ASSET_IDS: tuple[str, ...] = focused_nine_contract.STRUCTURAL_IDS
PROP_ASSET_IDS: tuple[str, ...] = focused_nine_contract.PROP_IDS
ALL_ASSET_IDS: tuple[str, ...] = STRUCTURAL_ASSET_IDS + PROP_ASSET_IDS
REQUIRED_MATERIAL_NAMES: tuple[str, ...] = (
    "MAT_PaintedAlloyGray",
    "MAT_WarningStripe",
    "MAT_ReactorGlow",
    "MAT_Conduit",
)
LANDMARK_ROLE_TOKENS: Mapping[str, tuple[str, ...]] = {
    "doorway_frame_open_1x1": (
        "frame_inner_left",
        "frame_inner_right",
        "mechanical_rail_left",
        "mechanical_rail_right",
        "seal_left",
        "seal_right",
        "threshold_rail",
        "threshold_seal",
    ),
    "pressure_door_1x1": (
        "shared_frame_left",
        "shared_frame_right",
        "shared_rail_left",
        "shared_rail_right",
        "seal_left",
        "seal_right",
        "intact_lock_bar",
        "damaged_reinforcement",
        "breached_void_marker",
    ),
    "hull_breach_seal_point": ("mounting_plate", "hose", "cable", "status"),
    "fire_suppression_station": (
        "mounting_plate",
        "handle",
        "hose",
        "cable",
        "indicator",
    ),
}
_GENERATED_PREFIX = "FocusedNine_"
_MATERIAL_LIBRARY_NAME = "salvage_industrial.blend"
TRUST_BOUNDARY_DOCUMENTATION = (
    "Trusted-workspace boundary: after the initial path and inode observations, "
    "the caller must approve a same-user trusted workspace for Blender's "
    "path-based open/save. Blender cannot FD-pin a .blend path here, so these "
    "checks do not solve same-user rebind races after those observations."
)
# Export collections intentionally remain source-visible. The Godot wrapper is
# the runtime visibility authority and selects one imported GLB at a time.
PRESSURE_VARIANT_VISIBILITY_POLICY = "source_visible_wrapper_authority"
_PRESSURE_LEGACY_VISUAL_RULES: Mapping[str, str] = {
    "intact": "all pressure-door panels",
    "damaged": "one cosmetic indicator panel omitted",
    "breached": "central leaf omitted",
}

# Blender is deliberately not imported at module import time.
_BPY: Any | None = None
_VERIFIED_MATERIALS: Mapping[str, Any] | None = None


def _require_bpy() -> Any:
    """Import bpy only after pure-Python validation has completed."""

    global _BPY
    if _BPY is None:
        _BPY = __import__("bpy")
    return _BPY


def select_asset(asset_id: str) -> str:
    """Return ``structural`` or ``prop`` for a registered focused-nine id."""

    if asset_id in STRUCTURAL_ASSET_IDS:
        return "structural"
    if asset_id in PROP_ASSET_IDS:
        return "prop"
    raise ValueError(f"unknown focused-nine asset id: {asset_id!r}")


def source_blend_path(
    structural_source_root: Path, props_source_root: Path, asset_id: str
) -> Path:
    """Return the exact source `.blend` path for one registered asset.

    Structural roots are rooted at ``ship_structural_v0``; props roots are
    rooted at the flat prop source directory.  No path normalization or
    existence check is performed here, which keeps this helper deterministic
    and useful to Python-only callers.
    """

    kind = select_asset(asset_id)
    if kind == "structural":
        return Path(structural_source_root) / asset_id / f"{asset_id}.blend"
    return Path(props_source_root) / f"{asset_id}.blend"


def source_path(
    structural_source_root: Path, props_source_root: Path, asset_id: str
) -> Path:
    """Compatibility alias for the plan's pure-Python source-path interface."""

    return source_blend_path(structural_source_root, props_source_root, asset_id)


def structural_source_path(structural_source_root: Path, asset_id: str) -> Path:
    """Return the exact structural source path after allowlist validation."""

    if select_asset(asset_id) != "structural":
        raise ValueError(f"asset is not structural: {asset_id!r}")
    return Path(structural_source_root) / asset_id / f"{asset_id}.blend"


def prop_source_path(props_source_root: Path, asset_id: str) -> Path:
    """Return the exact flat prop source path after allowlist validation."""

    if select_asset(asset_id) != "prop":
        raise ValueError(f"asset is not a prop: {asset_id!r}")
    return Path(props_source_root) / f"{asset_id}.blend"


def _absolute_without_resolving_symlinks(path: Path) -> Path:
    """Normalize ``..`` without erasing symlink aliases used for safety checks."""

    return Path(os.path.abspath(os.fspath(Path(path).expanduser())))


def _is_same_or_descendant(candidate: Path, parent: Path) -> bool:
    try:
        candidate.relative_to(parent)
    except ValueError:
        return False
    return True


def _iter_real_regular_files(root: Path) -> Iterable[Path]:
    """Yield regular files under *root* without following symlink entries."""

    try:
        root_stat = os.stat(root, follow_symlinks=False)
    except FileNotFoundError:
        return
    except OSError as exc:
        raise ValueError(f"could not scan runtime mutation surface: {root}") from exc

    if stat.S_ISREG(root_stat.st_mode):
        yield root
        return
    if not stat.S_ISDIR(root_stat.st_mode):
        return

    try:
        with os.scandir(root) as iterator:
            entries = sorted(iterator, key=lambda entry: entry.name)
    except OSError as exc:
        raise ValueError(f"could not scan runtime mutation surface: {root}") from exc
    for entry in entries:
        try:
            entry_stat = entry.stat(follow_symlinks=False)
        except OSError as exc:
            raise ValueError(
                f"could not scan runtime mutation surface: {entry.path}"
            ) from exc
        if stat.S_ISREG(entry_stat.st_mode):
            yield Path(entry.path)
        elif stat.S_ISDIR(entry_stat.st_mode):
            yield from _iter_real_regular_files(Path(entry.path))


def _reject_hardlinked_runtime_source(
    source: Path, runtime_surfaces: Iterable[Path]
) -> None:
    """Reject an external source sharing an inode with a live runtime file."""

    try:
        source_stat = source.stat()
    except FileNotFoundError:
        return
    except OSError as exc:
        raise ValueError(f"could not stat focused-nine source candidate: {source}") from exc
    if not stat.S_ISREG(source_stat.st_mode):
        return

    source_inode = (source_stat.st_dev, source_stat.st_ino)
    seen_surfaces: set[str] = set()
    for surface in sorted(runtime_surfaces, key=os.fspath):
        surface_key = os.fspath(surface)
        if surface_key in seen_surfaces:
            continue
        seen_surfaces.add(surface_key)
        for runtime_file in _iter_real_regular_files(surface):
            try:
                runtime_stat = os.stat(runtime_file, follow_symlinks=False)
            except OSError as exc:
                raise ValueError(
                    f"could not stat runtime mutation file: {runtime_file}"
                ) from exc
            if (runtime_stat.st_dev, runtime_stat.st_ino) == source_inode:
                raise ValueError(
                    "focused-nine source candidate is an external hardlink to "
                    f"runtime mutation file: {source} -> {runtime_file}"
                )


def resolve_source_path(
    project_root: Path,
    structural_source_root: Path,
    props_source_root: Path,
    asset_id: str,
) -> Path:
    """Resolve one source blend while rejecting every live project surface.

    The lexical and resolved forms are both checked.  The first catches a
    source root named through a project-local symlink, while the second catches
    an external alias that resolves back into the project runtime tree.
    """

    source = source_blend_path(structural_source_root, props_source_root, asset_id)
    project_lexical = _absolute_without_resolving_symlinks(Path(project_root))
    try:
        project_resolved = project_lexical.resolve(strict=False)
        source_lexical = _absolute_without_resolving_symlinks(source)
        source_resolved = source_lexical.resolve(strict=False)
        runtime_lexical = [
            project_lexical / "assets/imported",
            project_lexical / "assets/_staging",
            *(_absolute_without_resolving_symlinks(path) for path in focused_nine_contract.runtime_mutation_paths(project_lexical)),
        ]
        runtime_resolved = [
            project_resolved / "assets/imported",
            project_resolved / "assets/_staging",
            *(Path(path).resolve(strict=False) for path in focused_nine_contract.runtime_mutation_paths(project_resolved)),
        ]
    except (OSError, RuntimeError, ValueError) as exc:
        raise ValueError(f"could not resolve focused-nine source path: {source}") from exc

    for runtime_surface in (*runtime_lexical, *runtime_resolved):
        if _is_same_or_descendant(source_lexical, runtime_surface) or _is_same_or_descendant(
            source_resolved, runtime_surface
        ):
            raise ValueError(
                f"focused-nine source candidate is on a runtime surface: {source}"
            )
    _reject_hardlinked_runtime_source(
        source_resolved,
        (*runtime_lexical, *runtime_resolved),
    )
    return source_resolved


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, epilog=TRUST_BOUNDARY_DOCUMENTATION
    )
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--structural-source-root", type=Path, required=True)
    parser.add_argument("--props-source-root", type=Path, required=True)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument("--overwrite-generated-only", action="store_true")
    return parser


def _argv_from_blender(argv: Sequence[str] | None) -> list[str]:
    if argv is not None:
        return list(argv)
    raw = list(sys.argv[1:])
    return raw[raw.index("--") + 1 :] if "--" in raw else raw


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse the CLI and reject unknown ids without importing Blender."""

    parser = build_parser()
    args = parser.parse_args(_argv_from_blender(argv))
    try:
        select_asset(args.asset_id)
    except ValueError as exc:
        parser.error(str(exc))
    return args


def _generated_name(asset_id: str, token: str) -> str:
    return f"{_GENERATED_PREFIX}{asset_id}_{token}"


def _material_library_candidates(
    project_root: Path, structural_root: Path, props_root: Path
) -> tuple[Path, ...]:
    configured = os.environ.get("FOCUSED_NINE_MATERIAL_LIBRARY")
    candidates: list[Path] = []
    if configured:
        candidates.append(Path(configured).expanduser())
    candidates.extend(
        (
            Path(project_root) / "meshes/source/materials" / _MATERIAL_LIBRARY_NAME,
            Path(structural_root).parent / "materials" / _MATERIAL_LIBRARY_NAME,
            Path(structural_root) / "materials" / _MATERIAL_LIBRARY_NAME,
            Path(props_root).parent / "materials" / _MATERIAL_LIBRARY_NAME,
            Path(project_root).parent / "meshes/source/materials" / _MATERIAL_LIBRARY_NAME,
        )
    )
    unique: list[Path] = []
    seen: set[Path] = set()
    for candidate in candidates:
        candidate = candidate.resolve(strict=False)
        if candidate not in seen:
            seen.add(candidate)
            unique.append(candidate)
    return tuple(unique)


def _material_source_name(material: Any) -> str | None:
    source_name = material.get("focused_nine_source_name")
    if isinstance(source_name, str) and source_name.startswith("focused-nine:"):
        return source_name.removeprefix("focused-nine:")
    return None


def _material_is_verified_library(
    material: Any, library_key: str, canonical_name: str
) -> bool:
    return (
        material.get("focused_nine_source_library") == library_key
        and _material_source_name(material) == canonical_name
    )


def _material_users(material: Any) -> Iterable[Any]:
    """Yield mesh objects that actually use *material* in a material slot."""

    bpy = _require_bpy()
    for obj in getattr(bpy.data, "objects", ()):
        if getattr(obj, "type", None) != "MESH":
            continue
        for slot in getattr(obj, "material_slots", ()):
            if getattr(slot, "material", None) is material:
                yield obj
                break


def _object_parent_chain(obj: Any) -> Iterable[Any]:
    current = getattr(obj, "parent", None)
    seen: set[int] = set()
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        yield current
        current = getattr(current, "parent", None)


def _collection_property(collection: Any, key: str, default: Any = None) -> Any:
    getter = getattr(collection, "get", None)
    if callable(getter):
        return getter(key, default)
    return default


def _object_matches_focused_asset(obj: Any, asset_id: str) -> bool:
    """Prove that a generated material user belongs to *asset_id*.

    The generated marker and asset id are necessary but not sufficient: an
    authored object can carry copied ID properties. Structural objects must
    also descend from the exact module root (with matching ``module_id``) and
    live in the known geometry/export namespace. Props must live in their
    exact generated collection. This keeps a same-id object in another module
    or collection on the authored/non-owned failure path.
    """

    if getattr(obj, "type", None) != "MESH":
        return False
    getter = getattr(obj, "get", None)
    if not callable(getter):
        return False
    if getter("focused_nine_generated") is not True:
        return False
    if getter("focused_nine_asset_id") != asset_id:
        return False

    collections = tuple(getattr(obj, "users_collection", ()))
    if asset_id in STRUCTURAL_ASSET_IDS:
        expected_root_name = f"ModuleRoot_{asset_id}"
        matching_roots = tuple(
            parent
            for parent in _object_parent_chain(obj)
            if getattr(parent, "name", None) == expected_root_name
        )
        if not matching_roots:
            return False
        allowed_collections = {
            "Geometry",
            "Export_intact",
            "Export_damaged",
            "Export_breached",
        }
        return any(
            getattr(collection, "name", None) in allowed_collections
            and (
                _collection_property(collection, "module_id") == asset_id
                or (
                    getattr(collection, "name", None) == "Geometry"
                    and any(
                        _collection_property(parent, "module_id") == asset_id
                        for parent in matching_roots
                    )
                )
            )
            for collection in collections
        )

    expected_collection_name = f"FocusedNine_{asset_id}_Generated"
    return any(
        getattr(collection, "name", None) == expected_collection_name
        and _collection_property(collection, "module_id", asset_id) == asset_id
        for collection in collections
    )


def _is_focused_generated_material_user(obj: Any) -> bool:
    getter = getattr(obj, "get", None)
    if not callable(getter):
        return False
    asset_id = getter("focused_nine_asset_id")
    return (
        isinstance(asset_id, str)
        and asset_id in ALL_ASSET_IDS
        and _object_matches_focused_asset(obj, asset_id)
    )


def _material_has_authored_marker(material: Any) -> bool:
    getter = getattr(material, "get", None)
    if not callable(getter):
        return False
    return getter("authored_marker") is not None or getter("focused_nine_authored") is True


def _material_has_authored_user(material: Any) -> bool:
    return _material_has_authored_marker(material) or any(
        not _is_focused_generated_material_user(obj) for obj in _material_users(material)
    )


def _verified_material_remnants(materials: Iterable[Any], library_key: str, name: str) -> list[Any]:
    return [
        material
        for material in materials
        if material.name != name
        and _material_is_verified_library(material, library_key, name)
    ]


def _preserved_material_name(material: Any, canonical_name: str) -> str:
    """Return a deterministic unused name for an owned legacy material."""

    bpy = _require_bpy()
    base = f"{canonical_name}.legacy"
    candidate = base
    index = 1
    while True:
        existing = bpy.data.materials.get(candidate)
        if existing is None or existing is material:
            return candidate
        candidate = f"{base}.{index:03d}"
        index += 1


def ensure_material_library(
    project_root: Path, structural_root: Path, props_root: Path
) -> dict[str, Any]:
    """Load or safely repair exact canonical materials from salvage library.

    A non-owned/authored user is a hard stop before any source mutation. An
    unproven canonical datablock is repairable only when every actual mesh user
    is an owned focused-nine object in the exact module/collection namespace.
    Repair appends the real material from the configured salvage library,
    relinks only those generated users, and preserves the old datablock under a
    fake-user legacy name rather than marking it as verified.
    """

    global _VERIFIED_MATERIALS
    _VERIFIED_MATERIALS = None
    bpy = _require_bpy()
    library_path = next(
        (
            candidate
            for candidate in _material_library_candidates(
                project_root, structural_root, props_root
            )
            if candidate.is_file()
        ),
        None,
    )
    if library_path is None:
        searched = ", ".join(
            str(path)
            for path in _material_library_candidates(
                project_root, structural_root, props_root
            )
        )
        raise RuntimeError(
            f"missing required material library {_MATERIAL_LIBRARY_NAME}; searched: {searched}"
        )

    library_key = str(library_path)
    with bpy.data.libraries.load(str(library_path), link=False) as (data_from, _data_to):
        available = set(data_from.materials)
    missing_from_library = sorted(set(REQUIRED_MATERIAL_NAMES) - available)
    if missing_from_library:
        raise RuntimeError(
            f"material library {library_path} is missing required materials: "
            + ", ".join(missing_from_library)
        )

    # Preflight every canonical slot before renaming, relinking, or appending.
    # This makes authored collisions a loud, source-safe failure and ensures a
    # later missing-library failure cannot leave an earlier material renamed.
    plans: dict[str, tuple[str, Any | None]] = {}
    for canonical_name in REQUIRED_MATERIAL_NAMES:
        remnants = _verified_material_remnants(
            bpy.data.materials, library_key, canonical_name
        )
        if len(remnants) > 1:
            raise RuntimeError(
                f"multiple verified focused-nine remnants compete for canonical material "
                f"{canonical_name!r}; refusing to guess"
            )
        remnant = remnants[0] if remnants else None
        if remnant is not None and _material_has_authored_user(remnant):
            raise RuntimeError(
                f"verified remnant {remnant.name!r} for canonical material "
                f"{canonical_name!r} has an authored user; refusing to rename it; "
                "one-time manual migration required"
            )

        existing = bpy.data.materials.get(canonical_name)
        if existing is not None:
            if _material_is_verified_library(existing, library_key, canonical_name):
                if _material_has_authored_user(existing):
                    raise RuntimeError(
                        f"canonical material {canonical_name!r} has an authored user; "
                        "refusing to use or remediate it; one-time manual migration "
                        "required"
                    )
                plans[canonical_name] = ("existing", existing)
                continue

            if _material_has_authored_user(existing):
                raise RuntimeError(
                    f"canonical material {canonical_name!r} is occupied by a non-owned "
                    "material; refusing to rename, delete, or use it; one-time manual "
                    "migration required"
                )
            plans[canonical_name] = ("remediate", existing)
            continue

        if remnant is not None:
            plans[canonical_name] = ("rename", remnant)
        else:
            plans[canonical_name] = ("load", None)

    materials: dict[str, Any] = {}
    for canonical_name, (action, material) in plans.items():
        if action == "rename":
            assert material is not None
            material.name = canonical_name
            if material.name != canonical_name:
                raise RuntimeError(
                    f"verified material remnant could not take canonical name {canonical_name!r}"
                )
            materials[canonical_name] = material
        elif action == "existing":
            assert material is not None
            materials[canonical_name] = material

    requested_materials = tuple(
        name
        for name, (action, _material) in plans.items()
        if action in {"load", "remediate"}
    )
    if requested_materials:
        with bpy.data.libraries.load(str(library_path), link=False) as (_data_from, data_to):
            data_to.materials = list(requested_materials)
        loaded_materials: list[Any] = list(data_to.materials)
        if len(loaded_materials) != len(requested_materials) or any(
            material is None for material in loaded_materials
        ):
            raise RuntimeError(
                "required materials were not loaded from the configured library: "
                + ", ".join(requested_materials)
            )
        for source_name, loaded in zip(requested_materials, loaded_materials, strict=True):
            action, legacy = plans[source_name]
            if action == "load" and loaded.name != source_name:
                raise RuntimeError(
                    f"material library load produced non-canonical name {loaded.name!r} "
                    f"for {source_name!r}"
                )
            loaded["focused_nine_source_library"] = library_key
            # Blender treats an IDProperty string equal to a datablock name as
            # an ID pointer. Prefixing it keeps provenance a stable string.
            loaded["focused_nine_source_name"] = f"focused-nine:{source_name}"
            if action == "remediate":
                assert legacy is not None
                for obj in bpy.data.objects:
                    for slot in getattr(obj, "material_slots", ()):
                        if getattr(slot, "material", None) is legacy:
                            slot.material = loaded
                legacy.name = _preserved_material_name(legacy, source_name)
                legacy.use_fake_user = True
                loaded.name = source_name
            materials[source_name] = loaded

    if set(materials) != set(REQUIRED_MATERIAL_NAMES) or any(
        material.name != name
        or not _material_is_verified_library(material, library_key, name)
        for name, material in materials.items()
    ):
        raise RuntimeError(
            "required materials were not verified under exact canonical names from the "
            f"configured library {library_path}"
        )
    _VERIFIED_MATERIALS = materials
    return {
        "library_path": library_key,
        "material_names": list(REQUIRED_MATERIAL_NAMES),
        "materials": materials,
    }


def _link_object(obj: Any, collection: Any) -> None:
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    collection.objects.link(obj)


def _mark_generated(obj: Any, asset_id: str) -> None:
    obj["focused_nine_generated"] = True
    obj["focused_nine_asset_id"] = asset_id


def _mark_landmark_role(obj: Any, role: str) -> Any:
    """Attach a stable semantic role to a generated landmark object."""

    obj["focused_nine_role"] = role
    obj["landmark_role"] = role
    return obj


def _activate_only(obj: Any) -> None:
    """Select only a newly created object without touching scene contents."""

    bpy = _require_bpy()
    for selected in list(bpy.context.selected_objects):
        selected.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _apply_transform(obj: Any, *, rotation: bool = True) -> None:
    bpy = _require_bpy()
    _activate_only(obj)
    bpy.ops.object.transform_apply(location=False, rotation=rotation, scale=True)


def _assign_material(obj: Any, material_name: str) -> None:
    if _VERIFIED_MATERIALS is None:
        raise RuntimeError("verified material mapping is not initialized")
    material = _VERIFIED_MATERIALS.get(material_name)
    if material is None:
        raise RuntimeError(f"required verified material is unavailable: {material_name}")
    if obj.type == "MESH":
        if len(obj.data.materials) == 0:
            obj.data.materials.append(material)
        else:
            obj.data.materials[0] = material


def _claim_generated_name(asset_id: str, token: str) -> str:
    """Reserve one canonical generated object name before creating geometry."""

    bpy = _require_bpy()
    expected_name = _generated_name(asset_id, token)
    if bpy.data.objects.get(expected_name) is not None:
        raise RuntimeError(
            f"generated object name {expected_name!r} is occupied; refusing to "
            "co-own an authored or stale object"
        )
    return expected_name


def _set_exact_generated_name(obj: Any, expected_name: str) -> None:
    """Fail closed if Blender ever suffixes a canonical generated name."""

    bpy = _require_bpy()
    obj.name = expected_name
    if obj.name == expected_name:
        return
    actual_name = obj.name
    bpy.data.objects.remove(obj, do_unlink=True)
    raise RuntimeError(
        f"Blender could not assign exact generated object name {expected_name!r}; "
        f"received {actual_name!r}"
    )


def _bevel(obj: Any, width: float) -> Any:
    """Apply a small non-destructive-looking bevel to a generated box."""

    bpy = _require_bpy()
    modifier = obj.modifiers.new(name="FocusedNineBevel", type="BEVEL")
    modifier.width = max(0.001, float(width))
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    _activate_only(obj)
    result = bpy.ops.object.modifier_apply(modifier=modifier.name)
    if "FINISHED" not in result:
        raise RuntimeError(f"could not apply bevel to generated object {obj.name}")
    return obj


def _box(
    asset_id: str,
    token: str,
    collection: Any,
    size: Sequence[float],
    location: Sequence[float],
    material_name: str,
    *,
    bevel_width: float = 0.0,
) -> Any:
    bpy = _require_bpy()
    expected_name = _claim_generated_name(asset_id, token)
    dimensions = tuple(max(0.001, float(value)) for value in size)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=tuple(float(value) for value in location))
    obj = bpy.context.active_object
    _set_exact_generated_name(obj, expected_name)
    _mark_generated(obj, asset_id)
    _link_object(obj, collection)
    obj.dimensions = dimensions
    _apply_transform(obj)
    if bevel_width:
        _bevel(obj, bevel_width)
    _assign_material(obj, material_name)
    return obj


def _cylinder(
    asset_id: str,
    token: str,
    collection: Any,
    radius: float,
    depth: float,
    location: Sequence[float],
    material_name: str,
    *,
    rotation: Sequence[float] = (0.0, 0.0, 0.0),
    vertices: int = 12,
) -> Any:
    bpy = _require_bpy()
    expected_name = _claim_generated_name(asset_id, token)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=max(0.001, float(radius)),
        depth=max(0.001, float(depth)),
        location=tuple(float(value) for value in location),
        rotation=tuple(float(value) for value in rotation),
    )
    obj = bpy.context.active_object
    _set_exact_generated_name(obj, expected_name)
    _mark_generated(obj, asset_id)
    _link_object(obj, collection)
    _apply_transform(obj)
    _assign_material(obj, material_name)
    return obj


def _dimensions_from_spec(spec: Any) -> tuple[float, float, float]:
    try:
        minimum = tuple(float(value) for value in spec.bounds_min_y_up)
        maximum = tuple(float(value) for value in spec.bounds_max_y_up)
        return (
            max(0.5, maximum[0] - minimum[0]),
            max(0.5, maximum[2] - minimum[2]),
            max(0.25, maximum[1] - minimum[1]),
        )
    except (AttributeError, TypeError, ValueError):
        return (4.0, 4.0, 0.25)


def _base_z(spec: Any) -> float:
    try:
        return float(spec.bounds_min_y_up[1])
    except (AttributeError, IndexError, TypeError, ValueError):
        return 0.0


def _add_floor_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, depth, thickness = _dimensions_from_spec(spec)
    z = _base_z(spec)
    objects: list[Any] = []
    objects.append(_box(asset_id, "floor_panel", collection, (width - 0.12, depth - 0.12, max(0.12, thickness)), (0, 0, z + thickness / 2), "MAT_PaintedAlloyGray", bevel_width=0.025))
    objects.append(_box(asset_id, "panel_seam_ns", collection, (0.025, depth - 0.22, 0.018), (0, 0, z + thickness + 0.012), "MAT_Conduit"))
    objects.append(_box(asset_id, "panel_seam_ew", collection, (width - 0.22, 0.025, 0.018), (0, 0, z + thickness + 0.013), "MAT_Conduit"))
    objects.append(_box(asset_id, "access_plate", collection, (0.72, 0.72, 0.045), (0.55, -0.55, z + thickness + 0.025), "MAT_PaintedAlloyGray", bevel_width=0.02))
    for index, (x, y) in enumerate(((0.26, -0.84), (0.84, -0.84), (0.26, -0.26), (0.84, -0.26))):
        objects.append(_cylinder(asset_id, f"access_bolt_{index:02d}", collection, 0.045, 0.035, (x, y, z + thickness + 0.065), "MAT_WarningStripe", vertices=12))
    for side, x in (("west", -width / 2 + 0.18), ("east", width / 2 - 0.18)):
        objects.append(_box(asset_id, f"conduit_channel_{side}", collection, (0.12, depth - 0.45, 0.07), (x, 0, z + thickness + 0.035), "MAT_Conduit", bevel_width=0.015))
    objects.append(_cylinder(asset_id, "drain_grate", collection, 0.18, 0.035, (0, 0.95, z + thickness + 0.02), "MAT_Conduit", vertices=16))
    for index, x in enumerate((-0.09, 0.09)):
        objects.append(_box(asset_id, f"drain_bar_{index:02d}", collection, (0.025, 0.26, 0.025), (x, 0.95, z + thickness + 0.045), "MAT_WarningStripe"))
    track_span = max(1.0, depth - 0.8)
    track_z = z + thickness + 0.055
    for side, x in (("west", -0.72), ("east", 0.72)):
        objects.append(
            _box(
                asset_id,
                f"service_track_{side}",
                collection,
                (0.16, track_span, 0.045),
                (x, 0, track_z),
                "MAT_Conduit",
                bevel_width=0.01,
            )
        )
    for index, y in enumerate((-depth / 2 + 0.38, -depth / 2 + 0.56, -depth / 2 + 0.74)):
        objects.append(
            _box(
                asset_id,
                f"threshold_rib_{index:02d}",
                collection,
                (width * 0.66, 0.06, 0.045),
                (0, y, track_z + 0.012),
                "MAT_WarningStripe",
                bevel_width=0.008,
            )
        )
    return objects


def _add_wall_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, _depth, height = _dimensions_from_spec(spec)
    height = max(3.5, height)
    thickness = 0.28
    frame_width = width * 0.81
    frame_height = height * 0.78
    frame_depth = 0.045
    frame_rail_width = 0.12
    frame_rail_height = 0.10
    frame_center_z = height * 0.47
    frame_side_x = (frame_width - frame_rail_width) / 2
    frame_top_bottom_z = (frame_height - frame_rail_height) / 2
    objects = [
        _box(asset_id, "perimeter_left", collection, (0.22, thickness, height), (-width / 2 + 0.12, 0, height / 2), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "perimeter_right", collection, (0.22, thickness, height), (width / 2 - 0.12, 0, height / 2), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "perimeter_top", collection, (width, thickness, 0.22), (0, 0, height - 0.11), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "panel_frame_outer_left", collection, (frame_rail_width, frame_depth, frame_height), (-frame_side_x, -0.21, frame_center_z), "MAT_PaintedAlloyGray", bevel_width=0.018),
        _box(asset_id, "panel_frame_outer_right", collection, (frame_rail_width, frame_depth, frame_height), (frame_side_x, -0.21, frame_center_z), "MAT_PaintedAlloyGray", bevel_width=0.018),
        _box(asset_id, "panel_frame_outer_bottom", collection, (frame_width, frame_depth, frame_rail_height), (0, -0.21, frame_center_z - frame_top_bottom_z), "MAT_PaintedAlloyGray", bevel_width=0.018),
        _box(asset_id, "panel_frame_outer_top", collection, (frame_width, frame_depth, frame_rail_height), (0, -0.21, frame_center_z + frame_top_bottom_z), "MAT_PaintedAlloyGray", bevel_width=0.018),
        _box(asset_id, "panel_inset_upper", collection, (width * 0.24, 0.06, height * 0.22), (-width * 0.22, -0.245, height * 0.69), "MAT_PaintedAlloyGray", bevel_width=0.018),
        _box(asset_id, "panel_inset_lower", collection, (width * 0.24, 0.06, height * 0.22), (width * 0.22, -0.245, height * 0.25), "MAT_PaintedAlloyGray", bevel_width=0.018),
    ]
    for index, x in enumerate((-width * 0.22, width * 0.22)):
        objects.append(_box(asset_id, f"inset_panel_{index:02d}", collection, (width * 0.28, 0.06, height * 0.52), (x, -0.17, height * 0.49), "MAT_PaintedAlloyGray", bevel_width=0.025))
    objects.extend(
        (
            _box(asset_id, "conduit_vertical", collection, (0.09, 0.09, height * 0.72), (-width / 2 + 0.42, -0.22, height * 0.46), "MAT_Conduit", bevel_width=0.015),
            _box(asset_id, "conduit_run_horizontal", collection, (width * 0.52, 0.09, 0.09), (-width * 0.08, -0.25, height * 0.18), "MAT_Conduit", bevel_width=0.015),
            _box(asset_id, "service_cover", collection, (0.46, 0.08, 0.38), (width / 2 - 0.42, -0.22, height * 0.3), "MAT_WarningStripe", bevel_width=0.015),
        )
    )
    for panel_index, x in enumerate((-width * 0.22, width * 0.22)):
        for seam_index, z in enumerate((height * 0.3, height * 0.68)):
            objects.append(
                _box(
                    asset_id,
                    f"panel_seam_{panel_index:02d}_{seam_index:02d}",
                    collection,
                    (width * 0.23, 0.028, 0.026),
                    (x, -0.207, z),
                    "MAT_Conduit",
                )
            )
    return objects


def _add_doorway_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, _depth, height = _dimensions_from_spec(spec)
    opening_width = min(width * 0.62, 2.5)
    jamb_height = max(3.4, height)
    objects = [
        _box(asset_id, "jamb_left", collection, (0.32, 0.42, jamb_height), (-opening_width / 2 - 0.2, 0, jamb_height / 2), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "jamb_right", collection, (0.32, 0.42, jamb_height), (opening_width / 2 + 0.2, 0, jamb_height / 2), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "lintel", collection, (opening_width + 0.72, 0.42, 0.34), (0, 0, jamb_height - 0.17), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "indicator_bay_left", collection, (0.12, 0.48, 0.26), (-opening_width / 2 - 0.2, -0.26, jamb_height - 0.5), "MAT_ReactorGlow", bevel_width=0.015),
        _box(asset_id, "indicator_bay_right", collection, (0.12, 0.48, 0.26), (opening_width / 2 + 0.2, -0.26, jamb_height - 0.5), "MAT_ReactorGlow", bevel_width=0.015),
        _box(asset_id, "threshold", collection, (opening_width + 0.72, 0.65, 0.12), (0, 0, 0.06), "MAT_WarningStripe", bevel_width=0.02),
    ]
    inner_frame_x = opening_width / 2 - 0.06
    objects.extend(
        (
            _mark_landmark_role(
                _box(
                    asset_id,
                    "frame_inner_left",
                    collection,
                    (0.16, 0.12, jamb_height * 0.76),
                    (-inner_frame_x, -0.18, jamb_height * 0.42),
                    "MAT_PaintedAlloyGray",
                    bevel_width=0.018,
                ),
                "frame",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "frame_inner_right",
                    collection,
                    (0.16, 0.12, jamb_height * 0.76),
                    (inner_frame_x, -0.18, jamb_height * 0.42),
                    "MAT_PaintedAlloyGray",
                    bevel_width=0.018,
                ),
                "frame",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "mechanical_rail_left",
                    collection,
                    (0.09, 0.09, jamb_height * 0.7),
                    (-opening_width / 2 - 0.1, -0.29, jamb_height * 0.4),
                    "MAT_Conduit",
                    bevel_width=0.012,
                ),
                "rail",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "mechanical_rail_right",
                    collection,
                    (0.09, 0.09, jamb_height * 0.7),
                    (opening_width / 2 + 0.1, -0.29, jamb_height * 0.4),
                    "MAT_Conduit",
                    bevel_width=0.012,
                ),
                "rail",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "seal_left",
                    collection,
                    (0.06, 0.07, jamb_height * 0.66),
                    (-opening_width / 2 + 0.02, -0.34, jamb_height * 0.4),
                    "MAT_WarningStripe",
                ),
                "seal",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "seal_right",
                    collection,
                    (0.06, 0.07, jamb_height * 0.66),
                    (opening_width / 2 - 0.02, -0.34, jamb_height * 0.4),
                    "MAT_WarningStripe",
                ),
                "seal",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "threshold_rail",
                    collection,
                    (opening_width + 0.22, 0.1, 0.07),
                    (0, 0.27, 0.17),
                    "MAT_Conduit",
                    bevel_width=0.012,
                ),
                "threshold",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "threshold_seal",
                    collection,
                    (opening_width, 0.06, 0.05),
                    (0, -0.25, 0.17),
                    "MAT_WarningStripe",
                    bevel_width=0.008,
                ),
                "threshold",
            ),
        )
    )
    for side, x in (("left", -opening_width / 2 - 0.2), ("right", opening_width / 2 + 0.2)):
        for segment_index, z in enumerate((jamb_height * 0.28, jamb_height * 0.5, jamb_height * 0.72)):
            objects.append(
                _box(
                    asset_id,
                    f"jamb_segment_{side}_{segment_index:02d}",
                    collection,
                    (0.38, 0.045, 0.075),
                    (x, -0.238, z),
                    "MAT_Conduit",
                )
            )
    for index, x in enumerate((-opening_width * 0.28, opening_width * 0.28)):
        objects.append(
            _box(
                asset_id,
                f"lintel_seam_{index:02d}",
                collection,
                (0.34, 0.045, 0.08),
                (x, -0.238, jamb_height - 0.17),
                "MAT_Conduit",
            )
        )
    return objects


def _add_pillar_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, depth, height = _dimensions_from_spec(spec)
    body = min(width, depth) * 0.34
    objects = [
        _box(asset_id, "pillar_body", collection, (body, body, max(2.8, height - 0.45)), (0, 0, max(2.8, height - 0.45) / 2 + 0.22), "MAT_PaintedAlloyGray", bevel_width=0.04),
        _box(asset_id, "base", collection, (body * 1.45, body * 1.45, 0.22), (0, 0, 0.11), "MAT_PaintedAlloyGray", bevel_width=0.03),
        _box(asset_id, "cap", collection, (body * 1.35, body * 1.35, 0.2), (0, 0, max(2.8, height) - 0.1), "MAT_PaintedAlloyGray", bevel_width=0.03),
        _cylinder(asset_id, "collar", collection, body * 0.55, 0.18, (0, 0, max(2.8, height) * 0.55), "MAT_WarningStripe", vertices=12),
    ]
    for index, x in enumerate((-body * 0.58, body * 0.58)):
        objects.append(_box(asset_id, f"rib_{index:02d}", collection, (0.1, body * 0.98, max(1.8, height * 0.72)), (x, 0, max(1.8, height * 0.72) / 2 + 0.35), "MAT_Conduit", bevel_width=0.015))
    structural_rib_depth = 0.1
    structural_rib_offset = body / 2 + structural_rib_depth / 2 - 0.01
    for index, y in enumerate((-structural_rib_offset, structural_rib_offset)):
        objects.append(
            _box(
                asset_id,
                f"structural_rib_{index:02d}",
                collection,
                (body * 0.72, structural_rib_depth, max(1.8, height * 0.68)),
                (0, y, max(1.8, height * 0.68) / 2 + 0.35),
                "MAT_Conduit",
                bevel_width=0.015,
            )
        )
    for index, z in enumerate((max(0.8, height * 0.38), max(1.4, height * 0.7))):
        objects.append(
            _box(
                asset_id,
                f"repair_bracket_{index:02d}",
                collection,
                (body * 0.8, 0.14, 0.12),
                (0, -(body / 2 + 0.14 / 2 - 0.01), z),
                "MAT_WarningStripe",
                bevel_width=0.012,
            )
        )
    bolt_positions = (
        (-body * 0.45, -body * 0.45),
        (body * 0.45, -body * 0.45),
        (-body * 0.45, body * 0.45),
        (body * 0.45, body * 0.45),
    )
    cap_z = max(2.8, height) - 0.18
    for level, z in (("base", 0.255), ("cap", cap_z)):
        for index, (x, y) in enumerate(bolt_positions):
            objects.append(
                _box(
                    asset_id,
                    f"{level}_bolt_{index:02d}",
                    collection,
                    (0.09, 0.09, 0.06),
                    (x, y, z),
                    "MAT_WarningStripe",
                )
            )
    return objects


def _add_ramp_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, depth, _height = _dimensions_from_spec(spec)
    width = max(width, 3.6)
    depth = max(depth, 7.0)
    tread_count = 6
    objects: list[Any] = []
    for index in range(tread_count):
        y = -depth / 2 + (index + 0.5) * depth / tread_count
        z = 0.09 + index * 0.14
        objects.append(_box(asset_id, f"tread_{index:02d}", collection, (width - 0.4, depth / tread_count - 0.04, 0.16), (0, y, z), "MAT_PaintedAlloyGray", bevel_width=0.018))
        objects.append(
            _box(
                asset_id,
                f"anti_slip_rib_{index:02d}",
                collection,
                (width - 0.62, 0.06, 0.045),
                (0, y, z + 0.105),
                "MAT_WarningStripe",
                bevel_width=0.008,
            )
        )
    for side, x in (("left", -width / 2 + 0.12), ("right", width / 2 - 0.12)):
        objects.append(_box(asset_id, f"curb_{side}", collection, (0.18, depth, 0.42), (x, 0, 0.22), "MAT_WarningStripe", bevel_width=0.02))
    objects.append(_box(asset_id, "raceway", collection, (0.13, depth * 0.78, 0.11), (width / 2 - 0.42, 0, 0.58), "MAT_Conduit", bevel_width=0.015))
    return objects


def _add_ceiling_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, depth, _height = _dimensions_from_spec(spec)
    objects = [
        _box(asset_id, "ceiling_cap", collection, (width - 0.12, depth - 0.12, 0.2), (0, 0, 3.9), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "light_trough", collection, (width * 0.58, 0.3, 0.08), (0, 0, 3.76), "MAT_ReactorGlow", bevel_width=0.015),
        _box(asset_id, "service_tray_frame", collection, (width * 0.36, depth * 0.46, 0.045), (width * 0.28, 0, 3.71), "MAT_Conduit", bevel_width=0.01),
        _box(asset_id, "service_tray", collection, (width * 0.3, depth * 0.4, 0.08), (width * 0.28, 0, 3.76), "MAT_Conduit", bevel_width=0.015),
        _box(asset_id, "emissive_recess", collection, (0.36, 0.24, 0.045), (-width * 0.28, -depth * 0.22, 3.73), "MAT_ReactorGlow", bevel_width=0.012),
    ]
    for index, x in enumerate((-width * 0.25, -width * 0.08, width * 0.09, width * 0.26)):
        objects.append(_box(asset_id, f"vent_bar_{index:02d}", collection, (0.06, depth * 0.48, 0.08), (x, 0, 3.76), "MAT_WarningStripe"))
    for index, x in enumerate((-width * 0.34, -width * 0.17, 0, width * 0.17, width * 0.34)):
        objects.append(_box(asset_id, f"vent_grille_{index:02d}", collection, (0.045, depth * 0.24, 0.045), (x, -depth * 0.2, 3.72), "MAT_WarningStripe"))
    for index, x in enumerate((-width * 0.36, -width * 0.12, width * 0.12, width * 0.36)):
        objects.append(
            _box(
                asset_id,
                f"panel_seam_ns_{index:02d}",
                collection,
                (0.025, depth * 0.68, 0.026),
                (x, 0, 3.80),
                "MAT_Conduit",
            )
        )
    for index, y in enumerate((-depth * 0.34, -depth * 0.11, depth * 0.11, depth * 0.34)):
        objects.append(
            _box(
                asset_id,
                f"panel_seam_ew_{index:02d}",
                collection,
                (width * 0.68, 0.025, 0.026),
                (0, y, 3.80),
                "MAT_Conduit",
            )
        )
    for index, (x, y) in enumerate(
        (
            (-width * 0.39, -depth * 0.39),
            (0, -depth * 0.39),
            (width * 0.39, -depth * 0.39),
            (-width * 0.39, 0),
            (width * 0.39, 0),
            (-width * 0.39, depth * 0.39),
            (0, depth * 0.39),
            (width * 0.39, depth * 0.39),
        )
    ):
        objects.append(
            _box(
                asset_id,
                f"service_bolt_{index:02d}",
                collection,
                (0.09, 0.09, 0.06),
                (x, y, 3.80),
                "MAT_WarningStripe",
            )
        )
    return objects


def _add_pressure_door_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, _depth, height = _dimensions_from_spec(spec)
    portal_width = min(width * 0.68, 2.7)
    height = max(height, 3.4)
    objects = [
        _box(asset_id, "outer_portal_left", collection, (0.35, 0.48, height), (-portal_width / 2 - 0.28, 0, height / 2), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "outer_portal_right", collection, (0.35, 0.48, height), (portal_width / 2 + 0.28, 0, height / 2), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "outer_portal_lintel", collection, (portal_width + 0.91, 0.48, 0.36), (0, 0, height - 0.18), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "split_leaf_left", collection, (portal_width * 0.47, 0.18, height * 0.78), (-portal_width * 0.235, -0.06, height * 0.43), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "split_leaf_right", collection, (portal_width * 0.47, 0.18, height * 0.78), (portal_width * 0.235, -0.06, height * 0.43), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "motor_housing", collection, (0.82, 0.52, 0.34), (0, 0, height - 0.56), "MAT_Conduit", bevel_width=0.025),
        _box(asset_id, "warning_threshold", collection, (portal_width + 0.7, 0.72, 0.13), (0, 0, 0.065), "MAT_WarningStripe", bevel_width=0.02),
        _box(asset_id, "cyan_indicator_left", collection, (0.09, 0.12, 0.3), (-portal_width / 2 - 0.28, -0.31, height - 0.62), "MAT_ReactorGlow", bevel_width=0.01),
        _box(asset_id, "cyan_indicator_right", collection, (0.09, 0.12, 0.3), (portal_width / 2 + 0.28, -0.31, height - 0.62), "MAT_ReactorGlow", bevel_width=0.01),
    ]
    frame_x = portal_width / 2 + 0.28
    inner_x = portal_width / 2 - 0.08
    objects.extend(
        (
            _mark_landmark_role(
                _box(
                    asset_id,
                    "shared_frame_left",
                    collection,
                    (0.16, 0.1, height * 0.8),
                    (-frame_x, -0.28, height * 0.45),
                    "MAT_PaintedAlloyGray",
                    bevel_width=0.014,
                ),
                "shared_frame",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "shared_frame_right",
                    collection,
                    (0.16, 0.1, height * 0.8),
                    (frame_x, -0.28, height * 0.45),
                    "MAT_PaintedAlloyGray",
                    bevel_width=0.014,
                ),
                "shared_frame",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "shared_rail_left",
                    collection,
                    (0.09, 0.1, height * 0.7),
                    (-inner_x, -0.2, height * 0.43),
                    "MAT_Conduit",
                    bevel_width=0.012,
                ),
                "shared_rail",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "shared_rail_right",
                    collection,
                    (0.09, 0.1, height * 0.7),
                    (inner_x, -0.2, height * 0.43),
                    "MAT_Conduit",
                    bevel_width=0.012,
                ),
                "shared_rail",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "seal_left",
                    collection,
                    (0.06, 0.08, height * 0.68),
                    (-inner_x, -0.27, height * 0.43),
                    "MAT_WarningStripe",
                ),
                "seal",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "seal_right",
                    collection,
                    (0.06, 0.08, height * 0.68),
                    (inner_x, -0.27, height * 0.43),
                    "MAT_WarningStripe",
                ),
                "seal",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "intact_lock_bar",
                    collection,
                    (portal_width * 0.62, 0.08, 0.1),
                    (0, -0.2, height * 0.44),
                    "MAT_ReactorGlow",
                    bevel_width=0.012,
                ),
                "Intact",
            ),
        )
    )
    return objects


def build_structural_recipe(asset_id: str, spec: Any, geometry: Any) -> list[Any]:
    """Build one structural visual recipe using additive primitives only."""

    if select_asset(asset_id) != "structural":
        raise ValueError(f"asset is not structural: {asset_id!r}")
    recipes = {
        "floor_1x1": _add_floor_recipe,
        "wall_straight_1x1": _add_wall_recipe,
        "doorway_frame_open_1x1": _add_doorway_recipe,
        "pillar_support_1x1": _add_pillar_recipe,
        "ramp_up_1x2": _add_ramp_recipe,
        "ceiling_cap_1x1": _add_ceiling_recipe,
        "pressure_door_1x1": _add_pressure_door_recipe,
    }
    return recipes[asset_id](asset_id, spec, geometry)


def _add_hull_breach_prop(asset_id: str, collection: Any) -> list[Any]:
    objects: list[Any] = [
        _box(asset_id, "clamp_frame_top", collection, (2.0, 0.18, 0.18), (0, 0, 1.0), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "clamp_frame_bottom", collection, (2.0, 0.18, 0.18), (0, 0, -1.0), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "clamp_frame_left", collection, (0.18, 0.18, 2.0), (-1.0, 0, 0), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "clamp_frame_right", collection, (0.18, 0.18, 2.0), (1.0, 0, 0), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "orange_face", collection, (1.45, 0.14, 0.72), (0, -0.08, 0), "MAT_WarningStripe", bevel_width=0.025),
        _box(asset_id, "conduit", collection, (0.13, 0.35, 1.65), (0.72, -0.16, 0), "MAT_Conduit", bevel_width=0.015),
    ]
    objects.extend(
        (
            _mark_landmark_role(
                _box(
                    asset_id,
                    "mounting_plate",
                    collection,
                    (1.72, 0.18, 1.76),
                    (0, 0.08, 0),
                    "MAT_PaintedAlloyGray",
                    bevel_width=0.018,
                ),
                "mounting_plate",
            ),
            _mark_landmark_role(
                _cylinder(
                    asset_id,
                    "hose_vertical",
                    collection,
                    0.07,
                    1.18,
                    (-0.62, -0.22, 0),
                    "MAT_Conduit",
                    vertices=12,
                ),
                "hose",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "cable_run",
                    collection,
                    (0.07, 0.08, 1.48),
                    (0.84, -0.22, 0),
                    "MAT_Conduit",
                    bevel_width=0.012,
                ),
                "cable",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "status_indicator",
                    collection,
                    (0.22, 0.08, 0.16),
                    (-0.62, -0.24, 0.78),
                    "MAT_ReactorGlow",
                    bevel_width=0.012,
                ),
                "status",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "status_warning",
                    collection,
                    (0.22, 0.08, 0.12),
                    (-0.62, -0.24, -0.78),
                    "MAT_WarningStripe",
                    bevel_width=0.01,
                ),
                "status",
            ),
        )
    )
    for index, (x, z) in enumerate(((-0.72, -0.72), (0.72, -0.72), (-0.72, 0.72), (0.72, 0.72))):
        objects.append(_box(asset_id, f"clamp_arm_{index:02d}", collection, (0.14, 0.32, 0.72), (x, 0, z), "MAT_Conduit", bevel_width=0.015))
    return objects


def _add_fire_station_prop(asset_id: str, collection: Any) -> list[Any]:
    objects = [
        _box(asset_id, "red_cabinet", collection, (1.1, 0.42, 1.8), (0, 0, 0.9), "MAT_WarningStripe", bevel_width=0.04),
        _cylinder(asset_id, "hose_reel", collection, 0.38, 0.16, (0, -0.28, 0.9), "MAT_Conduit", rotation=(1.570796, 0.0, 0.0), vertices=16),
        _box(asset_id, "emergency_light", collection, (0.22, 0.16, 0.22), (0, -0.28, 1.68), "MAT_ReactorGlow", bevel_width=0.02),
        _box(asset_id, "labeled_shape_panel", collection, (0.6, 0.06, 0.34), (0, -0.25, 0.38), "MAT_PaintedAlloyGray", bevel_width=0.015),
    ]
    objects[-1]["label_shape"] = "emergency_service_panel"
    objects[-1]["text_mesh"] = False
    objects.extend(
        (
            _mark_landmark_role(
                _box(
                    asset_id,
                    "mounting_plate",
                    collection,
                    (0.96, 0.06, 1.58),
                    (0, -0.24, 0.9),
                    "MAT_PaintedAlloyGray",
                    bevel_width=0.015,
                ),
                "mounting_plate",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "handle_bar",
                    collection,
                    (0.34, 0.05, 0.06),
                    (0, -0.35, 1.18),
                    "MAT_PaintedAlloyGray",
                    bevel_width=0.012,
                ),
                "handle",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "handle_mount_left",
                    collection,
                    (0.06, 0.06, 0.12),
                    (-0.17, -0.34, 1.18),
                    "MAT_Conduit",
                ),
                "handle",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "handle_mount_right",
                    collection,
                    (0.06, 0.06, 0.12),
                    (0.17, -0.34, 1.18),
                    "MAT_Conduit",
                ),
                "handle",
            ),
            _mark_landmark_role(
                _cylinder(
                    asset_id,
                    "hose_drop",
                    collection,
                    0.05,
                    0.72,
                    (0.34, -0.35, 0.62),
                    "MAT_Conduit",
                    vertices=12,
                ),
                "hose",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "cable_run",
                    collection,
                    (0.06, 0.05, 0.78),
                    (-0.42, -0.34, 0.9),
                    "MAT_Conduit",
                ),
                "cable",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "status_indicator_amber",
                    collection,
                    (0.18, 0.05, 0.14),
                    (0, -0.35, 1.56),
                    "MAT_ReactorGlow",
                    bevel_width=0.012,
                ),
                "indicator",
            ),
            _mark_landmark_role(
                _box(
                    asset_id,
                    "status_indicator_fault",
                    collection,
                    (0.12, 0.05, 0.08),
                    (0.31, -0.35, 1.56),
                    "MAT_WarningStripe",
                    bevel_width=0.008,
                ),
                "indicator",
            ),
        )
    )
    objects.extend(
        (
            _box(asset_id, "cabinet_seam_left", collection, (0.025, 0.045, 1.42), (-0.34, -0.235, 0.9), "MAT_Conduit"),
            _box(asset_id, "cabinet_seam_right", collection, (0.025, 0.045, 1.42), (0.34, -0.235, 0.9), "MAT_Conduit"),
            _box(asset_id, "cabinet_seam_upper", collection, (0.68, 0.045, 0.025), (0, -0.235, 1.35), "MAT_Conduit"),
            _box(asset_id, "cabinet_seam_lower", collection, (0.68, 0.045, 0.025), (0, -0.235, 0.66), "MAT_Conduit"),
            _box(asset_id, "vent_slot_upper", collection, (0.12, 0.045, 0.035), (-0.18, -0.235, 1.48), "MAT_WarningStripe"),
            _box(asset_id, "vent_slot_lower", collection, (0.12, 0.045, 0.035), (0.18, -0.235, 1.48), "MAT_WarningStripe"),
        )
    )
    for index, (x, z) in enumerate(((-0.43, 0.28), (0.43, 0.28), (-0.43, 1.52), (0.43, 1.52))):
        objects.append(
            _box(
                asset_id,
                f"cabinet_bolt_{index:02d}",
                collection,
                (0.075, 0.06, 0.075),
                (x, -0.25, z),
                "MAT_WarningStripe",
            )
        )
    return objects


def build_prop_recipe(asset_id: str, collection: Any) -> list[Any]:
    """Build one prop visual recipe without touching authored prop objects."""

    if select_asset(asset_id) != "prop":
        raise ValueError(f"asset is not a prop: {asset_id!r}")
    if asset_id == "hull_breach_seal_point":
        return _add_hull_breach_prop(asset_id, collection)
    return _add_fire_station_prop(asset_id, collection)


def _ensure_collection(name: str) -> Any:
    bpy = _require_bpy()
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    scene_root = bpy.context.scene.collection
    if collection.name not in {child.name for child in scene_root.children}:
        scene_root.children.link(collection)
    return collection


def _ensure_empty(name: str, root: Any, helpers: Any, role: str) -> Any:
    bpy = _require_bpy()
    existing = bpy.data.objects.get(name)
    if existing is not None:
        return existing
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.35
    helpers.objects.link(empty)
    empty.parent = root
    empty["export_role"] = role
    empty["focused_nine_anchor"] = True
    return empty


def _is_owned_pressure_helper_collection(collection: Any) -> bool:
    return (
        _collection_property(collection, "focused_nine_generated") is True
        and _collection_property(collection, "focused_nine_asset_id")
        == "pressure_door_1x1"
    )


def ensure_structural_helpers(spec: Any, root: Any, helpers: Any) -> dict[str, Any]:
    """Return helper collections, migrating only owned Task 1 pressure rules.

    The Task 1 pressure-door rules were descriptive metadata, not authored
    geometry.  They are migrated only when the collection carries both
    generated ownership markers.  An authored or foreign collection with the
    same stale rule remains a hard failure rather than being silently claimed.
    """

    module_id = getattr(spec, "module_id", "")
    if getattr(root, "name", "") == "ModuleRoot_pressure_door_1x1":
        module_id = "pressure_door_1x1"
    roles = (
        ("intact", "damaged", "breached")
        if module_id == "pressure_door_1x1"
        else ("intact",)
    )
    visual_rules = {
        "intact": "shared frame rails seals and intact lock bar",
        "damaged": "shared frame rails seals plus reinforcement and hinge damage",
        "breached": "shared frame rails seals plus omitted leaf and exposed conduit",
    }
    bpy = _require_bpy()
    helper_collections: dict[str, Any] = {}
    for role in roles:
        name = f"Export_{role}"
        collection = next(
            (child for child in helpers.children if child.name == name), None
        )
        created = False
        if collection is None:
            existing_global = bpy.data.collections.get(name)
            if existing_global is not None:
                raise RuntimeError(
                    f"helper collection {name} exists outside target AuthoringHelpers"
                )
            collection = bpy.data.collections.new(name)
            if hasattr(helpers.children, "link"):
                helpers.children.link(collection)
            else:
                helpers.children.append(collection)
            created = True

        expected = {
            "variant_role": role,
            "module_id": module_id,
        }
        if module_id == "pressure_door_1x1":
            expected["variant_visual_rule"] = visual_rules[role]
        if created:
            for key, value in expected.items():
                collection[key] = value
            if module_id == "pressure_door_1x1":
                collection["variant_visibility_policy"] = PRESSURE_VARIANT_VISIBILITY_POLICY
        else:
            owned_pressure = module_id == "pressure_door_1x1" and _is_owned_pressure_helper_collection(collection)
            for key, value in expected.items():
                existing = _collection_property(collection, key)
                if existing is None:
                    if key == "variant_visual_rule" and owned_pressure:
                        collection[key] = value
                    continue
                if existing == value:
                    continue
                if (
                    key == "variant_visual_rule"
                    and owned_pressure
                    and existing == _PRESSURE_LEGACY_VISUAL_RULES[role]
                ):
                    collection[key] = value
                    continue
                if key in collection:
                    raise RuntimeError(
                        f"incompatible metadata on existing helper collection {name}: "
                        f"{key}={existing!r}, expected {value!r}"
                    )
            if owned_pressure:
                collection["variant_visibility_policy"] = PRESSURE_VARIANT_VISIBILITY_POLICY
        if module_id == "pressure_door_1x1" and (
            bool(getattr(collection, "hide_viewport", False))
            or bool(getattr(collection, "hide_render", False))
        ):
            raise RuntimeError(
                f"pressure-door helper collection {name} must remain source-visible "
                f"under {PRESSURE_VARIANT_VISIBILITY_POLICY}; runtime wrapper owns visibility"
            )
        helper_collections[role] = collection
    return helper_collections


def replace_generated_visuals(root: Any, geometry: Any, asset_id: str) -> None:
    """Remove only owned objects from the exact target collection.

    Structural calls must provide their exact module root; prop calls must use
    ``None`` because their generated collection is their ownership boundary.
    """

    kind = select_asset(asset_id)
    expected_root = f"ModuleRoot_{asset_id}"
    if kind == "structural":
        if root is None or getattr(root, "name", None) != expected_root:
            raise ValueError(
                f"focused-nine replacement requires root {expected_root!r}"
            )
    elif root is not None:
        raise ValueError("focused-nine prop replacement root must be None")
    _replace_owned_objects(geometry, asset_id)


def _object_property(obj: Any, key: str, default: Any = None) -> Any:
    getter = getattr(obj, "get", None)
    if callable(getter):
        return getter(key, default)
    return getattr(obj, key, default)


def _is_owned_generated_object(obj: Any, asset_id: str) -> bool:
    return (
        _object_property(obj, "focused_nine_generated") is True
        and _object_property(obj, "focused_nine_asset_id") == asset_id
    )


def _unlink_from_collection(collection: Any, obj: Any) -> None:
    links = collection.objects
    unlink = getattr(links, "unlink", None)
    if callable(unlink):
        unlink(obj)
        return
    try:
        links.remove(obj)
    except ValueError:
        pass
    users_collection = getattr(obj, "users_collection", None)
    if isinstance(users_collection, list) and collection in users_collection:
        users_collection.remove(collection)


def _remove_owned_object_if_unlinked(obj: Any) -> None:
    bpy = _require_bpy()
    users_collection = getattr(obj, "users_collection", None)
    if users_collection is not None and len(users_collection) > 0:
        return
    bpy.data.objects.remove(obj, do_unlink=False)


def _replace_owned_objects(collection: Any, asset_id: str) -> None:
    for obj in list(collection.objects):
        if not _is_owned_generated_object(obj, asset_id):
            continue
        _unlink_from_collection(collection, obj)
        _remove_owned_object_if_unlinked(obj)


def _replace_generated_collection(collection: Any, asset_id: str) -> None:
    """Clear owned objects from one explicitly selected export collection."""

    _replace_owned_objects(collection, asset_id)


def _remove_owned_pressure_foreign_details(
    root: Any, collections: Iterable[Any]
) -> None:
    """Remove doorway recipe remnants only after proving generated ownership.

    Pressure Task 2 sources were initially copied from the doorway recipe.  A
    doorway object is removable here only when its canonical generated marker,
    foreign asset id, namespace, and parent root all agree.  Authored objects,
    differently marked objects, and foreign links outside the selected export
    namespace are not touched.
    """

    target_collections = tuple(collections)
    target_ids = {id(collection) for collection in target_collections}
    seen: set[int] = set()
    for collection in target_collections:
        for obj in list(collection.objects):
            if id(obj) in seen:
                continue
            if not (
                _object_property(obj, "focused_nine_generated") is True
                and _object_property(obj, "focused_nine_asset_id")
                == "doorway_frame_open_1x1"
                and getattr(obj, "name", "").startswith(
                    _generated_name("doorway_frame_open_1x1", "")
                )
                and any(parent is root for parent in _object_parent_chain(obj))
            ):
                continue
            seen.add(id(obj))
            for target in target_collections:
                if id(target) not in target_ids:
                    continue
                if obj in list(target.objects):
                    _unlink_from_collection(target, obj)
            _remove_owned_object_if_unlinked(obj)


def _parent_generated(
    root: Any, objects: Iterable[Any], asset_id: str | None = None
) -> None:
    for obj in objects:
        obj.parent = root
        if asset_id is not None:
            _mark_generated(obj, asset_id)


def _link_existing_object(obj: Any, collection: Any) -> None:
    if obj.name not in {item.name for item in collection.objects}:
        collection.objects.link(obj)


def _build_export_variants(
    asset_id: str,
    root: Any,
    generated: Sequence[Any],
    export_collections: dict[str, Any],
) -> list[Any]:
    """Build deterministic export inventories with one shared pressure base."""

    if asset_id != "pressure_door_1x1":
        for obj in generated:
            _link_existing_object(obj, export_collections["intact"])
        return list(generated)

    portal_width = 2.7
    height = 3.4
    for obj in generated:
        if obj.name.endswith("_split_leaf_left"):
            dimensions = getattr(obj, "dimensions", None)
            dimension_x = getattr(dimensions, "x", None)
            dimension_z = getattr(dimensions, "z", None)
            if dimension_x is not None and dimension_z is not None:
                portal_width = max(0.5, float(dimension_x) / 0.47)
                height = max(3.4, float(dimension_z) / 0.78)
            break
    variant_objects: list[Any] = list(generated)

    # These are the only state-specific members of the source recipe.  Every
    # other generated object is linked (not copied) into every variant export
    # collection, making the common portal/base silhouette exact by identity
    # and inventory.  Collection metadata remains the export-role authority.
    state_specific_tokens = {
        "split_leaf_left",
        "cyan_indicator_right",
        "intact_lock_bar",
    }
    shared_base = [
        obj
        for obj in generated
        if not any(obj.name.endswith(f"_{token}") for token in state_specific_tokens)
    ]
    for obj in shared_base:
        for role in ("intact", "damaged", "breached"):
            _link_existing_object(obj, export_collections[role])
        obj["variant_role"] = "shared_base"
        obj["visibility_role"] = "Shared"

    # Intact owns the pristine state-specific objects.  Damaged retains the
    # left leaf, while breached retains the right indicator; the omitted pieces
    # are the intended state deltas and never contaminate the shared base.
    for obj in generated:
        if obj in shared_base:
            continue
        if obj.name.endswith(("_split_leaf_left", "_cyan_indicator_right", "_intact_lock_bar")):
            _link_existing_object(obj, export_collections["intact"])
            obj["variant_role"] = "intact"
            obj["visibility_role"] = "Intact"
    for role in ("damaged", "breached"):
        destination = export_collections[role]
        for obj in generated:
            if obj in shared_base:
                continue
            if role == "damaged" and obj.name.endswith(
                ("_cyan_indicator_right", "_intact_lock_bar")
            ):
                continue
            if role == "breached" and obj.name.endswith(
                ("_split_leaf_left", "_intact_lock_bar")
            ):
                continue
            copy = obj.copy()
            copy.data = obj.data.copy()
            token = obj.name.removeprefix(_generated_name(asset_id, ""))
            expected_name = _claim_generated_name(asset_id, f"{role}_{token}")
            _set_exact_generated_name(copy, expected_name)
            destination.objects.link(copy)
            copy.parent = root
            _mark_generated(copy, asset_id)
            copy["variant_role"] = role
            copy["visibility_role"] = role.capitalize()
            variant_objects.append(copy)

        variant_specs: dict[str, tuple[tuple[str, Sequence[float], Sequence[float], str], ...]] = {
            "damaged": (
                (
                    "damaged_reinforcement",
                    (0.42, 0.1, 0.18),
                    (-portal_width * 0.18, -0.31, 0.84),
                    "MAT_WarningStripe",
                ),
                (
                    "damaged_hinge_block",
                    (0.16, 0.14, 0.42),
                    (portal_width * 0.25, -0.3, height * 0.42),
                    "MAT_Conduit",
                ),
            ),
            "breached": (
                (
                    "breached_void_marker",
                    (portal_width * 0.44, 0.08, height * 0.42),
                    (0, -0.32, height * 0.43),
                    "MAT_WarningStripe",
                ),
                (
                    "breached_exposed_conduit",
                    (0.08, 0.12, height * 0.58),
                    (portal_width * 0.25, -0.34, height * 0.38),
                    "MAT_Conduit",
                ),
            ),
        }
        for token, size, location, material_name in variant_specs[role]:
            overlay = _box(
                asset_id,
                token,
                destination,
                size,
                location,
                material_name,
                bevel_width=0.012,
            )
            _mark_landmark_role(overlay, role.capitalize())
            overlay.parent = root
            overlay["variant_role"] = role
            overlay["visibility_role"] = role.capitalize()
            variant_objects.append(overlay)
    return variant_objects


def _structural_spec(project_root: Path, asset_id: str) -> Any:
    if asset_id != "pressure_door_1x1":
        return load_source_spec(Path(project_root), asset_id)
    candidate_path = focused_nine_contract.asset_stage_glb(project_root, asset_id)
    if candidate_path.is_file():
        from tools.structural_source_contract import load_candidate_source_spec

        return load_candidate_source_spec(project_root, asset_id, candidate_path)
    # The pressure-door source can be authored before its staged candidate GLB
    # is promoted.  Its contract intentionally mirrors the open doorway family.
    return load_source_spec(Path(project_root), "doorway_frame_open_1x1")


def _triangle_count(objects: Iterable[Any]) -> int:
    count = 0
    for obj in objects:
        if obj.type != "MESH":
            continue
        obj.data.calc_loop_triangles()
        count += len(obj.data.loop_triangles)
    return count


def _report(
    asset_id: str,
    kind: str,
    source_path: Path,
    generated: Sequence[Any],
    helpers: Mapping[str, Any] | None,
    material_info: dict[str, Any],
) -> dict[str, Any]:
    names = sorted(obj.name for obj in generated)
    if any(not name.startswith(_generated_name(asset_id, "")) for name in names):
        raise RuntimeError(f"generated object escaped namespace for {asset_id}")
    helper_names = []
    if helpers is not None:
        helper_names = sorted(collection.name for collection in helpers.values())
    modifier_types = sorted(
        {
            modifier.type
            for obj in generated
            for modifier in getattr(obj, "modifiers", ())
        }
    )
    material_names = sorted(
        {
            slot.material.name
            for obj in generated
            if getattr(obj, "type", None) == "MESH"
            for slot in getattr(obj, "material_slots", ())
            if getattr(slot, "material", None) is not None
        }
    )
    if not material_names:
        raise RuntimeError(f"generated recipe has no mesh materials for {asset_id}")
    if not set(material_names).issubset(REQUIRED_MATERIAL_NAMES):
        raise RuntimeError(
            f"generated recipe emitted non-canonical materials for {asset_id}: "
            + ", ".join(material_names)
        )
    export_visibility = {
        role: {
            "hide_viewport": bool(getattr(collection, "hide_viewport", False)),
            "hide_render": bool(getattr(collection, "hide_render", False)),
        }
        for role, collection in (helpers or {}).items()
    }
    pressure_helpers = any(
        _collection_property(collection, "module_id") == "pressure_door_1x1"
        for collection in (helpers or {}).values()
    )
    return {
        "asset_id": asset_id,
        "kind": kind,
        "source_path": str(source_path),
        "generated_object_names": names,
        "generated_count": len(names),
        "triangle_count": _triangle_count(generated),
        "helper_names": helper_names,
        "export_collection_visibility": export_visibility,
        "variant_visibility_policy": (
            PRESSURE_VARIANT_VISIBILITY_POLICY if pressure_helpers else None
        ),
        "material_names": material_names,
        "modifier_types": modifier_types,
        "boolean_modifiers": [
            obj.name
            for obj in generated
            for modifier in getattr(obj, "modifiers", ())
            if modifier.type.casefold() == "boolean"
        ],
    }


def _run(args: argparse.Namespace) -> dict[str, Any]:
    """Open, mutate, report, and save one requested source blend."""

    # This path selection is deliberately before _require_bpy().
    kind = select_asset(args.asset_id)
    source_path = resolve_source_path(
        args.project_root,
        args.structural_source_root,
        args.props_source_root,
        args.asset_id,
    )
    if not source_path.is_file():
        raise FileNotFoundError(f"requested focused-nine source blend does not exist: {source_path}")
    spec = _structural_spec(args.project_root, args.asset_id) if kind == "structural" else None
    bpy = _require_bpy()
    result = bpy.ops.wm.open_mainfile(filepath=str(source_path))
    if "FINISHED" not in result:
        raise RuntimeError(f"Blender could not open source blend: {source_path}")
    material_info = ensure_material_library(args.project_root, args.structural_source_root, args.props_source_root)

    if kind == "structural":
        helper_collections: Mapping[str, Any] | None = None
        root = bpy.data.objects.get(f"ModuleRoot_{args.asset_id}")
        if root is None:
            root = bpy.data.objects.new(f"ModuleRoot_{args.asset_id}", None)
            bpy.context.scene.collection.objects.link(root)
        geometry = _ensure_collection("Geometry")
        helpers = _ensure_collection("AuthoringHelpers")
        replace_generated_visuals(root, geometry, args.asset_id)
        export_collections = ensure_structural_helpers(spec, root, helpers)
        helper_collections = export_collections
        if "intact" not in export_collections:
            raise RuntimeError(f"missing Export_intact collection for {args.asset_id}")
        if args.asset_id == "pressure_door_1x1":
            _remove_owned_pressure_foreign_details(
                root,
                (geometry, *export_collections.values()),
            )
        for collection in export_collections.values():
            _replace_generated_collection(collection, args.asset_id)
        generated = build_structural_recipe(args.asset_id, spec, geometry)
        _parent_generated(root, generated, args.asset_id)
        generated = _build_export_variants(args.asset_id, root, generated, export_collections)
    else:
        root = None
        helpers = None
        helper_collections = None
        geometry = _ensure_collection(f"FocusedNine_{args.asset_id}_Generated")
        replace_generated_visuals(root, geometry, args.asset_id)
        generated = build_prop_recipe(args.asset_id, geometry)

    report = _report(
        args.asset_id,
        kind,
        source_path,
        generated,
        helper_collections,
        material_info,
    )
    save_result = bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
    if "FINISHED" not in save_result:
        raise RuntimeError(f"Blender could not save source blend: {source_path}")
    return report


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entrypoint; validation errors are reported without Blender import."""

    args = parse_args(argv)
    if not args.overwrite_generated_only:
        print("ERROR: --overwrite-generated-only is required for the safe generated-only driver", file=sys.stderr)
        return 2
    try:
        report = _run(args)
    except (FileNotFoundError, RuntimeError, ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print("FOCUSED_NINE_REPORT " + json.dumps(report, sort_keys=True, separators=(",", ":"), allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
