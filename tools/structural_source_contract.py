"""Pure-Python contract API for recovered structural Blender sources."""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


STRUCTURAL_SOURCE_MODULE_IDS: tuple[str, ...] = (
    "floor_1x1",
    "floor_2x1",
    "corridor_floor_1x1",
    "corridor_floor_1x2",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
)

_CONTRACT_ROOT = Path("data/placement/contracts/structural/ship_structural_v0")
_SOURCE_GLB_ROOT = Path("assets/imported/structural/ship_structural_v0")
_DEFAULT_COLLISION_PROXY_SHAPE = "box"
_DEFAULT_NAV_BLOCKER = False
_ORIENTATION_SOURCE = "socket-id-cardinal-convention"


@dataclass(frozen=True)
class SocketSpec:
    """One contract socket normalized for Blender source authoring."""

    socket_id: str
    kind: str
    compatible_kinds: tuple[str, ...]
    position_y_up: tuple[float, float, float]

    @property
    def anchor_name(self) -> str:
        return f"Anchor_SOCK_{self.socket_id}"

    @property
    def position_z_up(self) -> tuple[float, float, float]:
        return y_up_to_z_up(self.position_y_up)


@dataclass(frozen=True)
class StructuralSourceSpec:
    """Immutable, validated input required to recover one structural source."""

    module_id: str
    kit_id: str
    module_family: str
    grid_step_m: float
    footprint_cells: tuple[int, int]
    placement_origin: str
    bounds_min_y_up: tuple[float, float, float]
    bounds_max_y_up: tuple[float, float, float]
    collision_proxy_shape: str
    nav_blocker: bool
    sockets: tuple[SocketSpec, ...]
    contract_path: Path
    contract_sha256: str
    source_glb_path: Path
    source_glb_sha256: str


def y_up_to_z_up(value: tuple[float, float, float]) -> tuple[float, float, float]:
    """Convert a contract Y-up point to Blender's Z-up coordinate order."""

    return (float(value[0]), float(value[2]), float(value[1]))


def _unsupported_module(module_id: object) -> ValueError:
    return ValueError(f"unsupported structural source module: {module_id!r}")


def _validate_module_id(module_id: str) -> None:
    if module_id not in STRUCTURAL_SOURCE_MODULE_IDS:
        raise _unsupported_module(module_id)


def _nonempty_string(value: object, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"invalid structural contract {field_name}")
    return value


def _finite_float(value: object, field_name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"invalid structural contract {field_name}")
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"invalid structural contract {field_name}")
    return result


def _coordinate_tuple(value: object, field_name: str) -> tuple[float, float, float]:
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        raise ValueError(f"invalid structural contract {field_name}")
    return (
        _finite_float(value[0], field_name),
        _finite_float(value[1], field_name),
        _finite_float(value[2], field_name),
    )


def _footprint_tuple(value: object) -> tuple[int, int]:
    if (
        not isinstance(value, (list, tuple))
        or len(value) != 2
        or any(isinstance(item, bool) or not isinstance(item, int) for item in value)
    ):
        raise ValueError("invalid structural contract footprint_cells")
    return (value[0], value[1])  # type: ignore[index,return-value]


def _parse_socket(document: object, index: int) -> SocketSpec:
    field_prefix = f"sockets[{index}]"
    if not isinstance(document, dict):
        raise ValueError(f"invalid structural contract {field_prefix}")

    socket_id = _nonempty_string(document.get("id"), f"{field_prefix}.id")
    kind = _nonempty_string(document.get("kind"), f"{field_prefix}.kind")
    compatible = document.get("compatible_kinds")
    if not isinstance(compatible, (list, tuple)) or not compatible:
        raise ValueError(f"invalid structural contract {field_prefix}.compatible_kinds")
    compatible_kinds = tuple(
        _nonempty_string(item, f"{field_prefix}.compatible_kinds") for item in compatible
    )
    position_y_up = _coordinate_tuple(document.get("position_m"), f"{field_prefix}.position_m")
    return SocketSpec(
        socket_id=socket_id,
        kind=kind,
        compatible_kinds=compatible_kinds,
        position_y_up=position_y_up,
    )


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_source_spec(project_root: Path, module_id: str) -> StructuralSourceSpec:
    """Load and strictly validate one allowlisted structural source contract."""

    _validate_module_id(module_id)
    root = Path(project_root).expanduser().resolve()
    contract_path = root / _CONTRACT_ROOT / f"{module_id}_contract.json"
    source_glb_path = root / _SOURCE_GLB_ROOT / module_id / f"{module_id}.glb"

    try:
        contract_bytes = contract_path.read_bytes()
    except OSError as exc:
        raise ValueError(f"cannot read structural contract: {module_id}") from exc
    try:
        document = json.loads(contract_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid structural contract JSON: {module_id}") from exc
    if not isinstance(document, dict):
        raise ValueError(f"invalid structural contract document: {module_id}")

    if document.get("document_kind") != "modular_asset_spec":
        raise ValueError(f"invalid structural contract kind: {module_id}")
    if document.get("module_id") != module_id:
        raise ValueError(f"contract module_id mismatch: {module_id}")

    kit_id = _nonempty_string(document.get("kit_id"), "kit_id")
    module_family = _nonempty_string(document.get("module_family"), "module_family")
    grid_step_m = _finite_float(document.get("grid_step_m"), "grid_step_m")
    if grid_step_m <= 0.0:
        raise ValueError("invalid structural contract grid_step_m")

    bounds = document.get("bounds")
    if not isinstance(bounds, dict):
        raise ValueError(f"invalid structural contract bounds: {module_id}")
    bounds_min_y_up = _coordinate_tuple(bounds.get("local_min_m"), "bounds.local_min_m")
    bounds_max_y_up = _coordinate_tuple(bounds.get("local_max_m"), "bounds.local_max_m")
    placement_origin = _nonempty_string(bounds.get("placement_origin"), "bounds.placement_origin")

    footprint_cells = _footprint_tuple(document.get("footprint_cells"))

    raw_sockets = document.get("sockets")
    if not isinstance(raw_sockets, list):
        raise ValueError(f"invalid structural contract sockets: {module_id}")
    sockets = tuple(_parse_socket(socket, index) for index, socket in enumerate(raw_sockets))
    socket_ids = [socket.socket_id for socket in sockets]
    if len(socket_ids) != len(set(socket_ids)):
        raise ValueError(f"duplicate structural contract socket id: {module_id}")

    collision = document.get("collision", {})
    if collision is None:
        collision = {}
    if not isinstance(collision, dict):
        raise ValueError(f"invalid structural contract collision: {module_id}")
    collision_proxy_shape = collision.get("proxy_shape", _DEFAULT_COLLISION_PROXY_SHAPE)
    collision_proxy_shape = _nonempty_string(collision_proxy_shape, "collision.proxy_shape")
    nav_blocker = collision.get("nav_blocker", _DEFAULT_NAV_BLOCKER)
    if not isinstance(nav_blocker, bool):
        raise ValueError(f"invalid structural contract collision.nav_blocker: {module_id}")

    if not source_glb_path.is_file():
        raise ValueError(f"missing source GLB: {module_id}")

    return StructuralSourceSpec(
        module_id=module_id,
        kit_id=kit_id,
        module_family=module_family,
        grid_step_m=grid_step_m,
        footprint_cells=footprint_cells,
        placement_origin=placement_origin,
        bounds_min_y_up=bounds_min_y_up,
        bounds_max_y_up=bounds_max_y_up,
        collision_proxy_shape=collision_proxy_shape,
        nav_blocker=nav_blocker,
        sockets=sockets,
        contract_path=contract_path,
        contract_sha256=hashlib.sha256(contract_bytes).hexdigest(),
        source_glb_path=source_glb_path,
        source_glb_sha256=_sha256(source_glb_path),
    )


def source_output_paths(source_root: Path, module_id: str) -> tuple[Path, Path]:
    """Return safe `.blend` and canonical `.source.json` paths for a module."""

    _validate_module_id(module_id)
    root = Path(source_root).expanduser()
    resolved_root = root.resolve()
    module_root = root / module_id
    resolved_module_root = module_root.resolve(strict=False)
    if resolved_module_root == resolved_root or resolved_root not in resolved_module_root.parents:
        raise ValueError(f"source output path escapes source root: {module_id}")

    return (
        module_root / f"{module_id}.blend",
        module_root / f"{module_id}.source.json",
    )


def build_source_record(spec: StructuralSourceSpec, blend_path: Path) -> dict[str, Any]:
    """Build deterministic, timestamp-free provenance for a Blender source."""

    return {
        "document_kind": "structural_blender_source",
        "schema_version": "1.0.0",
        "module_id": spec.module_id,
        "kit_id": spec.kit_id,
        "contract": {
            "path": str(spec.contract_path),
            "sha256": spec.contract_sha256,
        },
        "source_glb": {
            "path": str(spec.source_glb_path),
            "sha256": spec.source_glb_sha256,
        },
        "blend_path": str(Path(blend_path)),
        "coordinate_conversion": "contract[x,y,z]->blender[x,z,y]",
        "placement_origin": spec.placement_origin,
        "sockets": [
            {
                "id": socket.socket_id,
                "anchor_name": socket.anchor_name,
                "kind": socket.kind,
                "compatible_kinds": list(socket.compatible_kinds),
                "position_contract_y_up": list(socket.position_y_up),
                "position_blender_z_up": list(socket.position_z_up),
                "orientation_source": _ORIENTATION_SOURCE,
            }
            for socket in spec.sockets
        ],
    }


def canonical_json(document: dict[str, Any]) -> bytes:
    """Serialize a document as sorted compact UTF-8 JSON with one newline."""

    return (
        json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
    ).encode("utf-8")
