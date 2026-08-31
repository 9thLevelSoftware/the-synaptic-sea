#!/usr/bin/env python3
"""Build a credit-gated, proposal-only Meshy texture request.

Meshy texturing is downstream of candidate selection and Blender validation.  A
request is written beside the selected candidate as ``texture_request.json``;
this tool never changes ``cleaned.glb`` or any runtime asset surface.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import struct
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, Mapping, Optional, Tuple, Union

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.meshy_asset_contract import (  # noqa: E402
    AssetContract,
    canonical_json_bytes,
    load_contract,
    render_prompt_packet,
)


MATERIAL_VOCABULARY_PATH = (
    Path(__file__).resolve().parents[1] / "data/asset_generation/material_vocabulary.json"
)
TEXTURE_REQUEST_NAME = "texture_request.json"
TEXTURE_MODEL = "meshy-7"
ESTIMATED_TEXTURE_CREDITS = 10

PathLike = Union[str, os.PathLike]


class TexturePacketError(ValueError):
    """Raised when a Meshy texture request fails a governance gate."""


def _reject_duplicate_keys(pairs: list[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError("non-finite JSON constant: " + value)


def _load_json(path: Path, label: str) -> object:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise TexturePacketError("{0} could not be read: {1}".format(label, exc)) from exc
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise TexturePacketError("{0} is not valid UTF-8".format(label)) from exc
    try:
        return json.loads(
            text,
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_constant,
        )
    except (json.JSONDecodeError, RecursionError, ValueError) as exc:
        raise TexturePacketError("invalid JSON in {0}: {1}".format(label, exc)) from exc


def _finite_unit_range(value: object, field_name: str) -> Tuple[float, float]:
    if not isinstance(value, list) or len(value) != 2:
        raise TexturePacketError("{0} must contain exactly two numbers".format(field_name))
    try:
        minimum, maximum = float(value[0]), float(value[1])
    except (TypeError, ValueError) as exc:
        raise TexturePacketError("{0} must contain exactly two numbers".format(field_name)) from exc
    if not all(0.0 <= item <= 1.0 for item in (minimum, maximum)):
        raise TexturePacketError("{0} must be bounded between 0 and 1".format(field_name))
    if minimum > maximum:
        raise TexturePacketError("{0} minimum must not exceed maximum".format(field_name))
    return minimum, maximum


def _validate_family(family_id: str, family: object) -> Dict[str, Any]:
    if not isinstance(family, dict):
        raise TexturePacketError("material family {0!r} must be an object".format(family_id))
    required = (
        "canonical_name",
        "base_traits",
        "allowed_accent_colors",
        "roughness_range",
        "metallic_range",
        "manual_emission_required",
    )
    missing = [field for field in required if field not in family]
    if missing:
        raise TexturePacketError(
            "material family {0!r} missing field(s): {1}".format(family_id, ", ".join(missing))
        )
    if family.get("canonical_name") != family_id:
        raise TexturePacketError("material family canonical_name must match its identifier")
    for field in ("canonical_name", "base_traits"):
        if not isinstance(family.get(field), str) or not family[field].strip():
            raise TexturePacketError("material family {0} has invalid {1}".format(family_id, field))
    accents = family.get("allowed_accent_colors")
    if not isinstance(accents, list) or not all(
        isinstance(color, str) and color.strip() for color in accents
    ):
        raise TexturePacketError("material family {0} has invalid accent colors".format(family_id))
    _finite_unit_range(family.get("roughness_range"), "roughness_range")
    _finite_unit_range(family.get("metallic_range"), "metallic_range")
    if not isinstance(family.get("manual_emission_required"), bool):
        raise TexturePacketError(
            "material family {0} has invalid manual_emission_required".format(family_id)
        )
    return dict(family)


def load_material_vocabulary(path: Optional[PathLike] = None) -> Dict[str, Dict[str, Any]]:
    """Load and validate the shared material vocabulary."""
    vocabulary_path = Path(path or MATERIAL_VOCABULARY_PATH).expanduser()
    document = _load_json(vocabulary_path, "material vocabulary")
    if not isinstance(document, dict):
        raise TexturePacketError("material vocabulary must be an object")
    if "schema_version" in document and document["schema_version"] != "1.0.0":
        raise TexturePacketError("material vocabulary schema_version must be 1.0.0")

    families_value = document.get("families", document)
    if not isinstance(families_value, dict):
        raise TexturePacketError("material vocabulary families must be an object")
    families: Dict[str, Dict[str, Any]] = {}
    for family_id, family in families_value.items():
        if not isinstance(family_id, str) or not family_id:
            raise TexturePacketError("material vocabulary family identifiers must be strings")
        families[family_id] = _validate_family(family_id, family)
    return families


def _coerce_contract(contract: Union[AssetContract, PathLike]) -> AssetContract:
    if isinstance(contract, AssetContract):
        return contract
    try:
        return load_contract(Path(contract))
    except (OSError, ValueError) as exc:
        raise TexturePacketError("contract is invalid: {0}".format(exc)) from exc


def _regular_task_directory(task_dir: PathLike) -> Path:
    path = Path(task_dir).expanduser()
    try:
        mode = path.lstat().st_mode
    except OSError as exc:
        raise TexturePacketError("task directory does not exist: {0}".format(path)) from exc
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        raise TexturePacketError("task directory must be a regular directory: {0}".format(path))
    return path


def _validation_status(report: Mapping[str, Any]) -> bool:
    for field in ("status", "validation_status", "result", "outcome", "validation"):
        value = report.get(field)
        if isinstance(value, str):
            return value.upper() == "PASS"
    return report.get("passed") is True


def _report_uv_state(report: Mapping[str, Any]) -> Optional[bool]:
    for field in ("uvs_present", "uv_present", "has_uvs", "has_uv"):
        if field in report:
            return report[field] if isinstance(report[field], bool) else False
    for field in ("uvs", "uv", "uv_maps"):
        value = report.get(field)
        if isinstance(value, bool):
            return value
        if isinstance(value, dict):
            for nested in ("present", "available", "has_uvs", "has_uv"):
                if nested in value:
                    return value[nested] if isinstance(value[nested], bool) else False
    attributes = report.get("attributes")
    if isinstance(attributes, dict) and "TEXCOORD_0" in attributes:
        return bool(attributes["TEXCOORD_0"])
    return None


def _cleaned_glb_has_uv(task_dir: Path) -> bool:
    """Use the normalized GLB as a fallback when the report omits UV metadata."""
    cleaned = task_dir / "cleaned.glb"
    try:
        if cleaned.is_symlink() or not cleaned.is_file():
            return False
        raw = cleaned.read_bytes()
    except OSError:
        return False
    try:
        # The parser is host-Python-only and does not import bpy.
        from tools.meshy_blender_validate import _parse_glb

        document = _parse_glb(raw).document
    except (ImportError, OSError, ValueError, TypeError, struct.error):  # type: ignore[name-defined]
        return False
    meshes = document.get("meshes")
    if not isinstance(meshes, list):
        return False
    for mesh in meshes:
        if not isinstance(mesh, dict):
            continue
        primitives = mesh.get("primitives")
        if not isinstance(primitives, list):
            continue
        for primitive in primitives:
            if not isinstance(primitive, dict):
                continue
            attributes = primitive.get("attributes")
            if isinstance(attributes, dict) and isinstance(attributes.get("TEXCOORD_0"), int):
                return True
    return False


def _load_blender_validation(task_dir: Path) -> Dict[str, Any]:
    report_path = task_dir / "blender-validation.json"
    try:
        mode = report_path.lstat().st_mode
    except OSError as exc:
        raise TexturePacketError(
            "Blender validation report blender-validation.json is required"
        ) from exc
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise TexturePacketError("blender-validation.json must be a regular file")
    report = _load_json(report_path, "blender-validation.json")
    if not isinstance(report, dict):
        raise TexturePacketError("blender-validation.json must be an object")
    if not _validation_status(report):
        raise TexturePacketError("Blender validation did not PASS")
    uv_state = _report_uv_state(report)
    if uv_state is False or (uv_state is None and not _cleaned_glb_has_uv(task_dir)):
        raise TexturePacketError("Blender validation does not confirm UVs are present")
    return report


def _generation_claims_emission(task_dir: Path) -> bool:
    """Reject staged metadata that attributes an emission map to Meshy 7."""
    generation_path = task_dir / "generation.json"
    if not generation_path.exists():
        return False
    try:
        mode = generation_path.lstat().st_mode
    except OSError as exc:
        raise TexturePacketError("generation.json could not be inspected") from exc
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise TexturePacketError("generation.json must be a regular file")
    generation = _load_json(generation_path, "generation.json")
    if not isinstance(generation, dict):
        raise TexturePacketError("generation.json must be an object")

    for field in ("emission", "has_emission", "emission_map", "claims_emission", "meshy_emission"):
        if field not in generation:
            continue
        value = generation[field]
        if value is True or (field == "emission_map" and value not in (None, False, {}, [])):
            return True
    outputs = generation.get("outputs")
    if isinstance(outputs, dict) and "emission" in outputs and outputs["emission"] not in (None, False, {}, []):
        return True
    return False


def _require_credit_gate(approved_credits: Optional[int], client: Any) -> None:
    if (
        not isinstance(approved_credits, int)
        or isinstance(approved_credits, bool)
        or approved_credits < ESTIMATED_TEXTURE_CREDITS
    ):
        raise TexturePacketError(
            "approved credit ceiling is below the estimated Meshy texture cost "
            "({0} required)".format(ESTIMATED_TEXTURE_CREDITS)
        )
    if client is None:
        return
    if not hasattr(client, "get_balance"):
        raise TexturePacketError("Meshy client must provide get_balance")
    balance = client.get_balance()
    if not isinstance(balance, int) or isinstance(balance, bool) or balance < ESTIMATED_TEXTURE_CREDITS:
        raise TexturePacketError(
            "insufficient Meshy balance for the estimated texture cost ({0} required)".format(
                ESTIMATED_TEXTURE_CREDITS
            )
        )


def _texture_prompt(profile_prompt: str, family_id: str, family: Mapping[str, Any]) -> str:
    roughness = family["roughness_range"]
    metallic = family["metallic_range"]
    accents = family["allowed_accent_colors"]
    emission = (
        "Manual emission is required after Meshy texturing."
        if family["manual_emission_required"]
        else "Do not add emission; Meshy 7 is not an emission source."
    )
    return (
        "{0} Material family {1}: {2}. Allowed accent colors: {3}. "
        "Roughness range {4}-{5}; metallic range {6}-{7}. {8}"
    ).format(
        profile_prompt,
        family_id,
        family["base_traits"],
        ", ".join(accents) if accents else "none",
        roughness[0],
        roughness[1],
        metallic[0],
        metallic[1],
        emission,
    )


def validate_texture_inputs(
    contract: Union[AssetContract, PathLike],
    task_dir: PathLike,
    material_family: str,
    resolution: int,
    reviewer: str,
    *,
    remove_lighting: bool = True,
    pbr_enabled: bool = True,
    meshy_emission: bool = False,
    approved_credits: Optional[int] = None,
    client: Any = None,
    vocabulary_path: Optional[PathLike] = None,
) -> Tuple[AssetContract, Path, Dict[str, Any]]:
    """Validate all non-network gates and return normalized request inputs."""
    asset_contract = _coerce_contract(contract)
    task_path = _regular_task_directory(task_dir)
    _load_blender_validation(task_path)

    vocabulary = load_material_vocabulary(vocabulary_path)
    if not isinstance(material_family, str) or material_family not in vocabulary:
        raise TexturePacketError("unknown material family: {0}".format(material_family))
    family = vocabulary[material_family]

    if _generation_claims_emission(task_path):
        raise TexturePacketError("Meshy 7 emission claims are forbidden")
    if not isinstance(remove_lighting, bool) or not remove_lighting:
        raise TexturePacketError("remove_lighting must be true")
    if not isinstance(pbr_enabled, bool) or not pbr_enabled:
        raise TexturePacketError("PBR must be enabled")
    if not isinstance(meshy_emission, bool) or meshy_emission:
        raise TexturePacketError("Meshy 7 emission claims are forbidden")
    if not isinstance(resolution, int) or isinstance(resolution, bool) or resolution <= 0:
        raise TexturePacketError("texture resolution must be a positive integer")

    budget = asset_contract.document.get("budget")
    budget_resolution = budget.get("texture_resolution") if isinstance(budget, dict) else None
    if not isinstance(budget_resolution, int) or isinstance(budget_resolution, bool):
        raise TexturePacketError("contract texture resolution budget is invalid")
    if resolution > budget_resolution:
        raise TexturePacketError(
            "texture resolution {0} exceeds contract budget {1}".format(
                resolution, budget_resolution
            )
        )
    if not isinstance(reviewer, str) or not reviewer.strip():
        raise TexturePacketError("reviewer must be non-empty text")

    _require_credit_gate(approved_credits, client)
    return asset_contract, task_path, family


def build_texture_request(
    contract: Union[AssetContract, PathLike],
    task_dir: PathLike,
    material_family: str,
    resolution: int,
    reviewer: str,
    *,
    remove_lighting: bool = True,
    pbr_enabled: bool = True,
    meshy_emission: bool = False,
    approved_credits: Optional[int] = None,
    client: Any = None,
    vocabulary_path: Optional[PathLike] = None,
) -> Dict[str, Any]:
    """Build a proposal-only canonical texture request."""
    asset_contract, _task_path, family = validate_texture_inputs(
        contract,
        task_dir,
        material_family,
        resolution,
        reviewer,
        remove_lighting=remove_lighting,
        pbr_enabled=pbr_enabled,
        meshy_emission=meshy_emission,
        approved_credits=approved_credits,
        client=client,
        vocabulary_path=vocabulary_path,
    )
    profile_packet = render_prompt_packet(asset_contract)
    prompt = _texture_prompt(profile_packet["texture_prompt"], material_family, family)
    return {
        "asset_id": asset_contract.asset_id,
        "contract": {
            "asset_id": asset_contract.asset_id,
            "sha256": asset_contract.sha256,
        },
        "contract_sha256": asset_contract.sha256,
        "material_family": material_family,
        "pbr": {
            "enabled": True,
            "emission": False,
            "model": TEXTURE_MODEL,
        },
        "prompt": prompt,
        "proposal_only": True,
        "remove_lighting": True,
        "resolution": resolution,
        "reviewer": reviewer.strip(),
    }


def write_texture_request(
    contract: Union[AssetContract, PathLike],
    task_dir: PathLike,
    material_family: str,
    resolution: int,
    reviewer: str,
    **kwargs: Any,
) -> Dict[str, Any]:
    """Validate and atomically write ``texture_request.json`` in ``task_dir``."""
    request = build_texture_request(
        contract,
        task_dir,
        material_family,
        resolution,
        reviewer,
        **kwargs,
    )
    destination = Path(task_dir).expanduser() / TEXTURE_REQUEST_NAME
    try:
        mode = destination.lstat().st_mode
        if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
            raise TexturePacketError("texture_request.json must be a regular file")
    except FileNotFoundError:
        pass
    descriptor, temporary_name = tempfile.mkstemp(
        prefix="." + TEXTURE_REQUEST_NAME + ".",
        suffix=".tmp",
        dir=str(Path(task_dir).expanduser()),
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(canonical_json_bytes(request))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(destination))
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
    return request


# Keep the packet terminology available to callers that use the plan's name.
build_texture_packet = build_texture_request
write_texture_packet = write_texture_request
create_texture_request = build_texture_request


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--task-dir", type=Path, required=True)
    parser.add_argument("--material-family", required=True)
    parser.add_argument("--resolution", type=int, required=True)
    parser.add_argument("--reviewer", required=True)
    parser.add_argument("--approved-credits", type=int, required=True)
    parser.add_argument(
        "--keep-lighting",
        action="store_true",
        help="test/diagnostic override; governance rejects this request",
    )
    parser.add_argument(
        "--disable-pbr",
        action="store_true",
        help="test/diagnostic override; governance rejects this request",
    )
    parser.add_argument(
        "--meshy-emission",
        action="store_true",
        help="test/diagnostic override; Meshy 7 cannot claim emission",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        request = write_texture_request(
            args.contract,
            args.task_dir,
            args.material_family,
            args.resolution,
            args.reviewer,
            remove_lighting=not args.keep_lighting,
            pbr_enabled=not args.disable_pbr,
            meshy_emission=args.meshy_emission,
            approved_credits=args.approved_credits,
        )
    except (OSError, TexturePacketError, RuntimeError, TypeError, ValueError) as exc:
        print("error: {0}".format(exc), file=sys.stderr)
        return 1
    print(
        "MESHY TEXTURE PACKET PASS asset={0} family={1} resolution={2}".format(
            request["asset_id"], request["material_family"], request["resolution"]
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "ESTIMATED_TEXTURE_CREDITS",
    "MATERIAL_VOCABULARY_PATH",
    "TEXTURE_MODEL",
    "TexturePacketError",
    "build_texture_packet",
    "build_texture_request",
    "create_texture_request",
    "load_material_vocabulary",
    "validate_texture_inputs",
    "write_texture_packet",
    "write_texture_request",
]
