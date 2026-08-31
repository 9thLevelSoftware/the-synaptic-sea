#!/usr/bin/env python3
"""Stage credit-bounded Meshy candidates without promoting runtime assets.

The adapter deliberately has a small injectable client boundary.  Tests and
local callers can provide a client implementing ``get_balance``,
``create_task``, ``poll_task``, and ``download`` without making network calls.
All provider URLs and credentials stay outside staged evidence.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import time
import uuid
from datetime import date as _date, datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Mapping, Optional, Tuple, Union

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.meshy_asset_contract import (  # noqa: E402
    AssetContract,
    canonical_json_bytes,
    load_contract,
    render_prompt_packet,
)
from tools import meshy_governance as governance  # noqa: E402


ENDPOINTS = {
    "image_to_3d": "/openapi/v1/image-to-3d",
    "multi_image_to_3d": "/openapi/v1/multi-image-to-3d",
}

DEFAULT_PRICING_PATH = (
    Path(__file__).resolve().parents[1] / "data/asset_generation/meshy_pricing_v1.json"
)
_PRICING_MAX_BYTES = 1024 * 1024
_REFERENCE_FILE_MAX_BYTES = 16 * 1024 * 1024
_REFERENCE_TOTAL_MAX_BYTES = 48 * 1024 * 1024
_PNG_SIGNATURE = bytes((137, 80, 78, 71, 13, 10, 26, 10))
_JPEG_SIGNATURE = bytes((255, 216, 255))
_REFERENCE_EXTENSIONS = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}

# These are the provider's fixed pilot estimates used by the credit gate.  A
# response's consumed_credits is still recorded as the source of truth for the
# completed task.
ESTIMATED_COST_PER_CANDIDATE = {
    "image_to_3d": 10,
    "multi_image_to_3d": 20,
}

STAGING_RELATIVE = Path("assets/_staging/meshy")
PROTECTED_RELATIVE = (
    Path("assets/imported"),
    Path("data/combat"),
    Path("data/props"),
    Path("scenes/wrappers"),
)
_TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_MAX_POLL_ATTEMPTS = 120
_POLL_DELAYS = (0.0, 0.25, 0.5, 1.0, 2.0)


class MeshyClient:
    """Minimal requests-backed Meshy client used by the optional CLI path.

    The client is never constructed by plan mode.  Network behavior is kept
    here rather than in the staging functions so injected fakes remain fully
    in-process and deterministic.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        session: Any = None,
    ) -> None:
        if api_key is None:
            api_key = os.environ.get("MESHY_API_KEY")
        if not api_key:
            raise ValueError("MESHY_API_KEY is required for generation")
        try:
            import requests
        except ImportError as exc:  # pragma: no cover - requests is project-installed
            raise ValueError("requests is required for generation") from exc

        self.api_key = api_key
        self.base_url = (base_url or os.environ.get("MESHY_BASE_URL", "https://api.meshy.ai")).rstrip("/")
        self.session = session or requests.Session()
        self.session.trust_env = False
        self._requests = requests

    def _request(self, method: str, endpoint: str, **kwargs: Any) -> Any:
        headers = dict(kwargs.pop("headers", {}))
        headers["Authorization"] = "Bearer " + self.api_key
        headers["Accept"] = "application/json"
        last_response = None
        for attempt in range(3):
            response = self.session.request(
                method,
                self.base_url + endpoint,
                headers=headers,
                timeout=(10, 60),
                **kwargs,
            )
            last_response = response
            if response.status_code not in (429, 500, 502, 503, 504):
                break
            if attempt < 2:
                time.sleep(0.5 * (2 ** attempt))
        if last_response is None or not 200 <= last_response.status_code < 300:
            status = getattr(last_response, "status_code", "unknown")
            raise RuntimeError("Meshy request failed with status {0}".format(status))
        try:
            return last_response.json()
        except ValueError as exc:
            raise RuntimeError("Meshy returned invalid JSON") from exc

    def get_balance(self) -> int:
        payload = self._request("GET", "/openapi/v1/user/balance")
        if isinstance(payload, dict):
            for key in ("balance", "credits", "credit_balance"):
                value = payload.get(key)
                if isinstance(value, int) and not isinstance(value, bool):
                    return value
        raise RuntimeError("Meshy balance response did not contain credits")

    def create_task(self, endpoint: str, payload: Dict[str, Any]) -> str:
        response = self._request("POST", endpoint, json=payload)
        if isinstance(response, dict):
            for key in ("result", "task_id", "id"):
                value = response.get(key)
                if isinstance(value, str) and value:
                    return value
        raise RuntimeError("Meshy create response did not contain a task id")

    def poll_task(self, endpoint: str, task_id: str) -> Dict[str, Any]:
        response = self._request("GET", endpoint.rstrip("/") + "/" + task_id)
        if not isinstance(response, dict):
            raise RuntimeError("Meshy task response was not an object")
        return response

    def download(self, url: str, destination: Path) -> None:
        # The signed URL is used only for this request and is never serialized
        # or included in an error message.
        response = self.session.get(url, stream=True, timeout=(10, 120))
        if not 200 <= response.status_code < 300:
            raise RuntimeError("Meshy download failed with status {0}".format(response.status_code))
        destination.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix="." + destination.name + ".", suffix=".tmp", dir=str(destination.parent)
        )
        os.close(descriptor)
        temporary = Path(temporary_name)
        try:
            with temporary.open("wb") as handle:
                for chunk in response.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        handle.write(chunk)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(str(temporary), str(destination))
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _copy_mapping(value: Mapping[str, Any]) -> Dict[str, Any]:
    # JSON round-tripping keeps request/evidence objects detached from the
    # contract object while rejecting non-JSON values early.
    return json.loads(canonical_json_bytes(dict(value)).decode("utf-8"))


class _SealedCapsule:
    """Base for transient records that must not be serialized or mutated."""

    __slots__ = ()

    def __setattr__(self, name: str, value: object) -> None:
        raise AttributeError("capsule records are immutable")

    def __delattr__(self, name: str) -> None:
        raise AttributeError("capsule records are immutable")

    def __reduce_ex__(self, protocol: Any) -> Any:
        raise TypeError("capsule records cannot be pickled")


class ReferenceInput(_SealedCapsule):
    """One validated reference with transient bytes hidden from evidence."""

    __slots__ = ("_view", "_basename", "_media_type", "_byte_size", "_sha256", "_bytes")

    def __init__(
        self,
        view: str,
        basename: str,
        media_type: str,
        byte_size: int,
        sha256: str,
        _bytes: bytes,
    ) -> None:
        object.__setattr__(self, "_view", view)
        object.__setattr__(self, "_basename", basename)
        object.__setattr__(self, "_media_type", media_type)
        object.__setattr__(self, "_byte_size", byte_size)
        object.__setattr__(self, "_sha256", sha256)
        object.__setattr__(self, "_bytes", _bytes)

    @property
    def view(self) -> str:
        return self._view

    @property
    def basename(self) -> str:
        return self._basename

    @property
    def media_type(self) -> str:
        return self._media_type

    @property
    def byte_size(self) -> int:
        return self._byte_size

    @property
    def sha256(self) -> str:
        return self._sha256

    @property
    def metadata(self) -> Dict[str, Any]:
        return {
            "view": self.view,
            "basename": self.basename,
            "media_type": self.media_type,
            "byte_size": self.byte_size,
            "sha256": self.sha256,
        }

    def __repr__(self) -> str:
        return (
            "ReferenceInput(view={0!r}, basename={1!r}, media_type={2!r}, "
            "byte_size={3!r}, sha256={4!r})"
        ).format(self.view, self.basename, self.media_type, self.byte_size, self.sha256)


class ReferenceInputs(_SealedCapsule):
    """Immutable, contract-ordered reference snapshot."""

    __slots__ = ("_references",)

    def __init__(self, references: Iterable[ReferenceInput]) -> None:
        object.__setattr__(self, "_references", tuple(references))

    @property
    def references(self) -> Tuple[ReferenceInput, ...]:
        return self._references

    def __iter__(self):
        return iter(self.references)

    def __len__(self) -> int:
        return len(self.references)

    def __getitem__(self, index: int) -> ReferenceInput:
        return self.references[index]

    @property
    def metadata(self) -> Tuple[Dict[str, Any], ...]:
        return tuple(reference.metadata for reference in self.references)

    def __repr__(self) -> str:
        return "ReferenceInputs(count={0})".format(len(self.references))


class PricingRecord(_SealedCapsule):
    """Immutable pricing document and the hash of its original source bytes."""

    __slots__ = (
        "_pricing_id",
        "_checked_at",
        "_expires_at",
        "_source_url",
        "_sha256",
        "_snapshot",
    )

    def __init__(
        self,
        pricing_id: str,
        checked_at: str,
        expires_at: str,
        source_url: str,
        sha256: str,
        _snapshot: bytes,
    ) -> None:
        object.__setattr__(self, "_pricing_id", pricing_id)
        object.__setattr__(self, "_checked_at", checked_at)
        object.__setattr__(self, "_expires_at", expires_at)
        object.__setattr__(self, "_source_url", source_url)
        object.__setattr__(self, "_sha256", sha256)
        object.__setattr__(self, "_snapshot", _snapshot)

    @property
    def pricing_id(self) -> str:
        return self._pricing_id

    @property
    def checked_at(self) -> str:
        return self._checked_at

    @property
    def expires_at(self) -> str:
        return self._expires_at

    @property
    def source_url(self) -> str:
        return self._source_url

    @property
    def sha256(self) -> str:
        return self._sha256

    @property
    def document(self) -> Dict[str, Any]:
        return self.document_copy()

    def snapshot_bytes(self) -> bytes:
        return bytes(self._snapshot)

    def document_copy(self) -> Dict[str, Any]:
        value = json.loads(self._snapshot.decode("utf-8"))
        if not isinstance(value, dict):  # pragma: no cover - strict loader validates this
            raise ValueError("pricing snapshot must be an object")
        return value

    def cost_for(self, contract: AssetContract) -> int:
        if not isinstance(contract, AssetContract):
            raise TypeError("cost_for requires an AssetContract")
        generation = contract._snapshot_document().get("generation")
        if not isinstance(generation, dict):
            raise ValueError("contract generation must be an object")
        return self._cost_for_values(
            generation.get("mode"),
            generation.get("model_type"),
            generation.get("ai_model"),
            generation.get("should_texture"),
        )

    def _cost_for_values(
        self,
        mode: object,
        model_type: object,
        ai_model: object,
        should_texture: object,
    ) -> int:
        if (
            not isinstance(mode, str)
            or not isinstance(model_type, str)
            or not isinstance(ai_model, str)
            or should_texture is not False
        ):
            raise ValueError("unknown Meshy pricing combination")
        texture_state = "untextured"
        costs = self.document_copy()["costs"]
        try:
            value = costs[mode][model_type][ai_model][texture_state]
        except (KeyError, TypeError):
            raise ValueError(
                "unknown Meshy pricing combination: {0}/{1}/{2}/{3}".format(
                    mode, model_type, ai_model, texture_state
                )
            )
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise ValueError("unknown Meshy pricing combination")
        return value

    def __repr__(self) -> str:
        return (
            "PricingRecord(pricing_id={0!r}, checked_at={1!r}, expires_at={2!r}, "
            "source_url={3!r}, sha256={4!r})"
        ).format(
            self.pricing_id,
            self.checked_at,
            self.expires_at,
            self.source_url,
            self.sha256,
        )


class TransientProviderRequest(_SealedCapsule):
    """Request payload held as private canonical bytes and redacted evidence."""

    __slots__ = ("_provider_payload_sha256", "_payload_snapshot", "_redacted_snapshot")

    def __init__(
        self,
        provider_payload_sha256: str,
        _payload_snapshot: bytes,
        _redacted_snapshot: bytes,
    ) -> None:
        object.__setattr__(self, "_provider_payload_sha256", provider_payload_sha256)
        object.__setattr__(self, "_payload_snapshot", _payload_snapshot)
        object.__setattr__(self, "_redacted_snapshot", _redacted_snapshot)

    @property
    def provider_payload_sha256(self) -> str:
        return self._provider_payload_sha256

    @property
    def payload(self) -> Dict[str, Any]:
        value = json.loads(self._payload_snapshot.decode("utf-8"))
        if not isinstance(value, dict):  # pragma: no cover - built internally
            raise ValueError("provider request snapshot must be an object")
        return value

    @property
    def redacted_request(self) -> Dict[str, Any]:
        value = json.loads(self._redacted_snapshot.decode("utf-8"))
        if not isinstance(value, dict):  # pragma: no cover - built internally
            raise ValueError("redacted request snapshot must be an object")
        return value

    def __repr__(self) -> str:
        return "TransientProviderRequest(provider_payload_sha256={0!r})".format(
            self.provider_payload_sha256
        )


def _coerce_iso_date(value: object, label: str) -> _date:
    if isinstance(value, _date) and not isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            parsed = _date.fromisoformat(value)
        except ValueError as exc:
            raise ValueError(f"{label} must be an ISO date") from exc
        if parsed.isoformat() != value:
            raise ValueError(f"{label} must be an ISO date")
        return parsed
    raise ValueError(f"{label} must be an ISO date")


def _validate_pricing_cost_leaves(value: object, label: str = "pricing costs") -> None:
    if not isinstance(value, Mapping):
        raise ValueError("{0} must contain exact positive integer leaves".format(label))
    for key, child in value.items():
        child_label = "{0}.{1}".format(label, key)
        if isinstance(child, Mapping):
            _validate_pricing_cost_leaves(child, child_label)
            continue
        if not isinstance(child, int) or isinstance(child, bool) or child <= 0:
            raise ValueError("{0} must be an exact positive integer".format(child_label))


def _pricing_document_is_exact(document: Mapping[str, Any]) -> None:
    expected_top = {
        "schema_version",
        "document_kind",
        "pricing_id",
        "checked_at",
        "expires_at",
        "source_url",
        "costs",
    }
    if set(document) != expected_top:
        raise ValueError("pricing document fields are not exact")
    if document["schema_version"] != "1.0.0":
        raise ValueError("pricing schema_version must be 1.0.0")
    if document["document_kind"] != "meshy_pricing":
        raise ValueError("pricing document_kind must be meshy_pricing")
    pricing_id = document["pricing_id"]
    if pricing_id != "meshy_api_2026_08_31":
        raise ValueError("pricing_id must be meshy_api_2026_08_31")
    if not isinstance(pricing_id, str) or _TASK_ID_RE.fullmatch(pricing_id) is None:
        raise ValueError("pricing_id must be a safe identifier")
    checked_text = document["checked_at"]
    expires_text = document["expires_at"]
    if checked_text != "2026-08-31" or expires_text != "2026-09-30":
        raise ValueError("pricing checked_at/expires_at do not match the versioned record")
    checked = _coerce_iso_date(checked_text, "pricing checked_at")
    expires = _coerce_iso_date(expires_text, "pricing expires_at")
    if checked >= expires:
        raise ValueError("pricing checked_at must precede expires_at")
    if document["source_url"] != "https://docs.meshy.ai/api/pricing.md":
        raise ValueError("pricing source_url is not the official Meshy pricing URL")
    expected_costs = {
        "image_to_3d": {
            "smart-topology": {"meshy-t2": {"untextured": 5}},
        },
        "multi_image_to_3d": {
            "standard": {
                "meshy-7": {"untextured": 20},
                "latest": {"untextured": 20},
            },
        },
    }
    _validate_pricing_cost_leaves(document["costs"])
    if document["costs"] != expected_costs:
        raise ValueError("pricing costs contain an unknown or unsupported combination")


def load_pricing(
    path: Optional[Path] = None,
    today: object = None,
    date: object = None,
) -> PricingRecord:
    """Load the exact official pricing record, failing closed after expiry."""

    source = Path(path) if path is not None else DEFAULT_PRICING_PATH
    try:
        document, raw = governance.strict_load_json_bytes(
            source, "Meshy pricing", _PRICING_MAX_BYTES
        )
    except (OSError, TypeError, ValueError) as exc:
        raise ValueError(f"Meshy pricing could not be read: {exc}") from exc
    _pricing_document_is_exact(document)
    if today is not None and date is not None:
        raise ValueError("pass only one of today or date")
    as_of = _coerce_iso_date(
        today if today is not None else date if date is not None else _date.today(),
        "pricing today",
    )
    expires = _coerce_iso_date(document["expires_at"], "pricing expires_at")
    if as_of >= expires:
        raise ValueError("Meshy pricing is expired")
    return PricingRecord(
        pricing_id=document["pricing_id"],
        checked_at=document["checked_at"],
        expires_at=document["expires_at"],
        source_url=document["source_url"],
        sha256=hashlib.sha256(raw).hexdigest(),
        _snapshot=canonical_json_bytes(document),
    )


def _resolve_reference_root(reference_root: Union[str, os.PathLike]) -> Path:
    candidate = Path(reference_root).expanduser()
    try:
        resolved = candidate.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise ValueError(f"reference root could not be resolved: {exc}") from exc
    if not resolved.is_dir():
        raise ValueError("reference root must be a directory")
    return resolved


def _parse_reference_specs(
    reference_specs: Union[Mapping[str, str], Iterable[Union[str, Tuple[str, str]]]]
) -> Dict[str, str]:
    if isinstance(reference_specs, Mapping):
        entries = list(reference_specs.items())
    elif isinstance(reference_specs, str):
        entries = [reference_specs]
    else:
        try:
            entries = list(reference_specs)
        except TypeError as exc:
            raise ValueError("reference specs must be a mapping or repeated view=filename") from exc
    parsed: Dict[str, str] = {}
    for entry in entries:
        if isinstance(entry, str):
            if entry.count("=") != 1:
                raise ValueError("reference spec must be view=filename")
            view, filename = entry.split("=", 1)
        elif isinstance(entry, (tuple, list)) and len(entry) == 2:
            view, filename = entry
        else:
            raise ValueError("reference spec must be view=filename")
        if not isinstance(view, str) or not isinstance(filename, str) or not view or not filename:
            raise ValueError("reference spec view and filename must be strings")
        if view in parsed:
            raise ValueError(f"duplicate reference view: {view}")
        parsed[view] = filename
    return parsed


def _validate_reference_filename(filename: str) -> str:
    if (
        not filename
        or any(ord(character) == 0 for character in filename)
        or "/" in filename
        or chr(92) in filename
        or filename in {".", ".."}
    ):
        raise ValueError("reference filename must be basename-only without slash or dot traversal")
    candidate = Path(filename)
    if candidate.is_absolute() or candidate.name != filename:
        raise ValueError("reference filename must be basename-only")
    suffix = candidate.suffix.lower()
    if suffix not in _REFERENCE_EXTENSIONS:
        raise ValueError("reference filename extension must be .png, .jpg, or .jpeg")
    return suffix


def _reference_magic_matches(suffix: str, payload: bytes) -> bool:
    if suffix == ".png":
        return payload.startswith(_PNG_SIGNATURE)
    return payload.startswith(_JPEG_SIGNATURE) and payload.endswith(bytes((255, 217)))


def _provider_required_views(contract: AssetContract) -> list[str]:
    document = contract._snapshot_document()
    references = document.get("references")
    required_views = references.get("required_views") if isinstance(references, dict) else None
    if (
        not isinstance(required_views, list)
        or not required_views
        or not all(isinstance(view, str) for view in required_views)
        or len(required_views) != len(set(required_views))
    ):
        raise ValueError("contract references.required_views must be a non-empty unique list")
    generation = document.get("generation")
    mode = generation.get("mode") if isinstance(generation, dict) else None
    if mode == "multi_image_to_3d" and required_views[0] != "front":
        raise ValueError("multi-image provider requires front as the first reference view")
    return required_views


def resolve_reference_inputs(
    contract: AssetContract,
    reference_root: Union[str, os.PathLike],
    reference_specs: Union[Mapping[str, str], Iterable[Union[str, Tuple[str, str]]]],
) -> ReferenceInputs:
    """Read and hash exactly the contract's ordered reference views."""

    required_views = _provider_required_views(contract)
    parsed = _parse_reference_specs(reference_specs)
    required_set = set(required_views)
    if set(parsed) != required_set:
        missing = sorted(required_set - set(parsed))
        extra = sorted(set(parsed) - required_set)
        detail = []
        if missing:
            detail.append("missing " + ", ".join(missing))
        if extra:
            detail.append("unknown " + ", ".join(extra))
        raise ValueError("reference views must match contract exactly" + (": " + "; ".join(detail) if detail else ""))

    root = _resolve_reference_root(reference_root)
    result = []
    aggregate_size = 0
    seen_basenames = set()
    seen_hashes = set()
    for view in required_views:
        filename = parsed[view]
        basename_key = filename.casefold()
        if basename_key in seen_basenames:
            raise ValueError("duplicate reference basename across views")
        seen_basenames.add(basename_key)
        suffix = _validate_reference_filename(filename)
        path = root / filename
        try:
            governance._reject_symlink_components_below(root, path, f"reference {view}")
            payload = governance._read_bounded_regular_file(
                path, f"reference {view}", _REFERENCE_FILE_MAX_BYTES
            )
        except (OSError, TypeError, ValueError) as exc:
            raise ValueError(f"reference {view} could not be read: {exc}") from exc
        aggregate_size += len(payload)
        if aggregate_size > _REFERENCE_TOTAL_MAX_BYTES:
            raise ValueError("references exceed maximum aggregate size")
        if not _reference_magic_matches(suffix, payload):
            raise ValueError(f"reference {view} has an invalid {suffix} signature")
        digest = hashlib.sha256(payload).hexdigest()
        if digest in seen_hashes:
            raise ValueError("duplicate reference content SHA-256 across views")
        seen_hashes.add(digest)
        result.append(
            ReferenceInput(
                view=view,
                basename=filename,
                media_type=_REFERENCE_EXTENSIONS[suffix],
                byte_size=len(payload),
                sha256=digest,
                _bytes=bytes(payload),
            )
        )
    return ReferenceInputs(tuple(result))


def _base_provider_request(contract: AssetContract) -> Dict[str, Any]:
    _provider_required_views(contract)
    generation = contract._snapshot_document().get("generation")
    if not isinstance(generation, dict):
        raise ValueError("contract generation must be an object")
    mode = generation.get("mode")
    if mode not in ENDPOINTS:
        raise ValueError("unsupported Meshy generation mode")
    request_fields = (
        "model_type",
        "ai_model",
        "target_polycount",
        "should_texture",
        "target_formats",
    )
    if any(field_name not in generation for field_name in request_fields):
        raise ValueError("contract generation is missing a request field")
    return _copy_mapping({field_name: generation[field_name] for field_name in request_fields})


def _validate_resolved_reference_inputs(
    contract: AssetContract, reference_inputs: ReferenceInputs
) -> list[ReferenceInput]:
    if type(reference_inputs) is not ReferenceInputs:
        raise ValueError("reference inputs must be resolved reference records")
    required_views = _provider_required_views(contract)
    records = reference_inputs.references
    if not records:
        raise ValueError("at least one reference input is required")
    if len(records) != len(required_views):
        raise ValueError("reference inputs must match contract views exactly")

    aggregate_size = 0
    seen_basenames = set()
    seen_hashes = set()
    for reference, expected_view in zip(records, required_views):
        if type(reference) is not ReferenceInput:
            raise ValueError("reference inputs must contain exact resolver records")
        try:
            view = reference.view
            basename = reference.basename
            media_type = reference.media_type
            byte_size = reference.byte_size
            digest = reference.sha256
            payload = reference._bytes
        except AttributeError as exc:
            raise ValueError("reference input record is incomplete") from exc
        if type(view) is not str or view != expected_view:
            raise ValueError("reference inputs must match contract order exactly")
        if type(basename) is not str:
            raise ValueError("reference basename must be a string")
        basename_key = basename.casefold()
        if basename_key in seen_basenames:
            raise ValueError("duplicate reference basename across views")
        seen_basenames.add(basename_key)
        try:
            suffix = _validate_reference_filename(basename)
        except ValueError as exc:
            raise ValueError("reference input has an invalid basename") from exc
        if type(media_type) is not str or media_type != _REFERENCE_EXTENSIONS[suffix]:
            raise ValueError("reference media type does not match its extension")
        if type(payload) is not bytes:
            raise ValueError("reference input bytes must be immutable bytes")
        if not isinstance(byte_size, int) or isinstance(byte_size, bool):
            raise ValueError("reference byte size must be an integer")
        if byte_size <= 0 or byte_size > _REFERENCE_FILE_MAX_BYTES or byte_size != len(payload):
            raise ValueError("reference byte size does not match its bytes")
        aggregate_size += byte_size
        if aggregate_size > _REFERENCE_TOTAL_MAX_BYTES:
            raise ValueError("references exceed maximum aggregate size")
        if not _reference_magic_matches(suffix, payload):
            raise ValueError("reference input has an invalid signature")
        computed_digest = hashlib.sha256(payload).hexdigest()
        if type(digest) is not str or digest != computed_digest:
            raise ValueError("reference sha256 does not match its bytes")
        if digest in seen_hashes:
            raise ValueError("duplicate reference content SHA-256 across views")
        seen_hashes.add(digest)
    return list(records)


def _reference_record_for_evidence(reference: ReferenceInput) -> Dict[str, Any]:
    return reference.metadata


def build_transient_provider_request(
    contract: AssetContract, reference_inputs: ReferenceInputs
) -> TransientProviderRequest:
    """Build a provider payload while retaining data URIs only in private bytes."""

    records = _validate_resolved_reference_inputs(contract, reference_inputs)
    payload = _base_provider_request(contract)
    evidence = [_reference_record_for_evidence(reference) for reference in records]
    data_uris = [
        "data:{0};base64,{1}".format(
            reference.media_type, base64.b64encode(reference._bytes).decode("ascii")
        )
        for reference in records
    ]
    generation = contract._snapshot_document()["generation"]
    if generation["mode"] == "image_to_3d":
        payload["image_url"] = data_uris[0]
        redacted = _copy_mapping(payload)
        redacted["image_url"] = evidence[0]
    else:
        payload["image_urls"] = data_uris
        redacted = _copy_mapping(payload)
        redacted["image_urls"] = evidence
    payload_snapshot = canonical_json_bytes(payload)
    return TransientProviderRequest(
        provider_payload_sha256=hashlib.sha256(payload_snapshot).hexdigest(),
        _payload_snapshot=payload_snapshot,
        _redacted_snapshot=canonical_json_bytes(redacted),
    )


def _generation_details(contract: AssetContract) -> Tuple[int, str, Dict[str, Any], int, str]:
    _provider_required_views(contract)
    generation = contract.document.get("generation")
    if not isinstance(generation, dict):
        raise ValueError("contract generation must be an object")
    mode = generation.get("mode")
    if mode not in ENDPOINTS:
        raise ValueError("unsupported Meshy generation mode")
    candidate_count = generation.get("candidate_count")
    if not isinstance(candidate_count, int) or isinstance(candidate_count, bool) or candidate_count <= 0:
        raise ValueError("candidate_count must be a positive integer")
    request_fields = (
        "model_type",
        "ai_model",
        "target_polycount",
        "should_texture",
        "target_formats",
    )
    request = {field: generation[field] for field in request_fields if field in generation}
    if tuple(request) != request_fields:
        raise ValueError("contract generation is missing a request field")
    request = _copy_mapping(request)
    cost_per_candidate = ESTIMATED_COST_PER_CANDIDATE[mode]
    prompt_hash = hashlib.sha256(
        canonical_json_bytes(render_prompt_packet(contract))
    ).hexdigest()
    return candidate_count, ENDPOINTS[mode], request, candidate_count * cost_per_candidate, prompt_hash


def _root_and_stage(project_root: Path, asset_id: str) -> Tuple[Path, Path, Path]:
    root = Path(project_root).expanduser().resolve(strict=False)
    if not asset_id or _TASK_ID_RE.fullmatch(asset_id) is None:
        raise ValueError("contract asset_id is not a safe staging identifier")
    stage = root / STAGING_RELATIVE
    asset_root = stage / asset_id
    stage_resolved = stage.resolve(strict=False)
    asset_resolved = asset_root.resolve(strict=False)
    if not _contained(root, stage_resolved) or not _contained(stage_resolved, asset_resolved):
        raise ValueError("Meshy staging path escapes the project root")
    for relative in PROTECTED_RELATIVE:
        protected = (root / relative).resolve(strict=False)
        if _contained(protected, stage_resolved) or _contained(protected, asset_resolved):
            raise ValueError("Meshy staging path overlaps a protected runtime surface")
    _reject_static_symlink_components(stage, "Meshy staging path")
    return root, stage, asset_root


def _contained(root: Path, candidate: Path) -> bool:
    return candidate == root or root in candidate.parents


def _reject_static_symlink_components(path: Path, label: str) -> None:
    absolute = Path(os.path.abspath(os.fspath(path)))
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            break
        except OSError as exc:
            raise ValueError("cannot inspect {0}".format(label)) from exc
        if stat.S_ISLNK(mode) and current not in (Path("/tmp"), Path("/var")):
            raise ValueError("{0} contains symlink component".format(label))


def plan_generation(
    contract: AssetContract,
    project_root: Path,
    client: Any = None,
    pricing_file: Optional[Path] = None,
    reference_root: Optional[Path] = None,
    reference_specs: object = None,
    today: object = None,
    date: object = None,
) -> Dict[str, Any]:
    """Return a deterministic, read-only generation plan.

    ``client`` and ``project_root`` remain accepted for caller compatibility,
    but planning never consults the client or writes through the project root.
    """

    del project_root, client
    document = contract._snapshot_document()
    generation = document.get("generation")
    if not isinstance(generation, dict):
        raise ValueError("contract generation must be an object")
    mode = generation.get("mode")
    if mode not in ENDPOINTS:
        raise ValueError("unsupported Meshy generation mode")
    candidate_count = generation.get("candidate_count")
    if not isinstance(candidate_count, int) or isinstance(candidate_count, bool) or candidate_count <= 0:
        raise ValueError("candidate_count must be a positive integer")
    base_request = _base_provider_request(contract)
    endpoint = ENDPOINTS[mode]
    prompt_packet = render_prompt_packet(contract)
    prompt_hash = hashlib.sha256(canonical_json_bytes(prompt_packet)).hexdigest()
    pricing = load_pricing(pricing_file, today=today, date=date)
    cost_per_candidate = pricing.cost_for(contract)
    required_views = document["references"]["required_views"]
    has_root = reference_root is not None
    has_specs = reference_specs is not None
    if has_root != has_specs:
        raise ValueError("reference-root and reference specs must be supplied together")

    result: Dict[str, Any] = {
        "asset_id": contract.asset_id,
        "required_views": list(required_views),
        "references_resolved": False,
        "candidate_count": candidate_count,
        "endpoint": endpoint,
        "cost_per_candidate": cost_per_candidate,
        "maximum_credits": candidate_count * cost_per_candidate,
        "pricing_id": pricing.pricing_id,
        "pricing_sha256": pricing.sha256,
        "pricing_source_url": pricing.source_url,
        "pricing_checked_at": pricing.checked_at,
        "pricing_expires_at": pricing.expires_at,
        "contract_sha256": contract.sha256,
        "prompt_profile_id": prompt_packet["prompt_profile_id"],
        "prompt_profile_sha256": prompt_packet["prompt_profile_sha256"],
        "prompt_packet_sha256": prompt_hash,
        "request": base_request,
    }
    if has_root and has_specs:
        resolved = resolve_reference_inputs(contract, reference_root, reference_specs)
        transient = build_transient_provider_request(contract, resolved)
        result["references_resolved"] = True
        result["resolved_references"] = [
            reference.metadata for reference in resolved.references
        ]
        result["request"] = transient.redacted_request
        result["provider_payload_sha256"] = transient.provider_payload_sha256
    return result


def _safe_task_id(task_id: object) -> str:
    if not isinstance(task_id, str) or _TASK_ID_RE.fullmatch(task_id) is None:
        raise ValueError("Meshy returned an unsafe task id")
    return task_id


def _poll_until_succeeded(client: Any, endpoint: str, task_id: str) -> Dict[str, Any]:
    for attempt in range(_MAX_POLL_ATTEMPTS):
        response = client.poll_task(endpoint, task_id)
        if not isinstance(response, dict):
            raise ValueError("Meshy task response must be an object")
        status = response.get("status")
        if isinstance(status, str):
            normalized_status = status.upper()
        else:
            normalized_status = ""
        if normalized_status == "SUCCEEDED":
            return response
        if normalized_status in ("FAILED", "CANCELED", "CANCELLED", "EXPIRED"):
            raise RuntimeError("Meshy task {0} ended with status {1}".format(task_id, normalized_status))
        if attempt + 1 >= _MAX_POLL_ATTEMPTS:
            break
        delay = _POLL_DELAYS[min(attempt, len(_POLL_DELAYS) - 1)]
        if delay:
            time.sleep(delay)
    raise RuntimeError("Meshy task {0} did not reach SUCCEEDED".format(task_id))


def _require_downloaded_file(path: Path, label: str) -> None:
    try:
        mode = path.lstat().st_mode
    except OSError as exc:
        raise RuntimeError("Meshy did not produce {0}".format(label)) from exc
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode) or path.stat().st_size <= 0:
        raise RuntimeError("Meshy did not produce a regular {0}".format(label))


def _file_evidence(path: Path) -> Dict[str, Any]:
    return {
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "byte_size": path.stat().st_size,
    }


def _license_state(contract: AssetContract) -> str:
    rights_state = contract.document.get("references", {}).get("rights_state")
    if rights_state == "free-cc-by-4.0":
        return "free-cc-by-4.0"
    return "paid-private"


def _generation_record(
    contract: AssetContract,
    request: Dict[str, Any],
    endpoint: str,
    task_id: str,
    prompt_hash: str,
    response: Mapping[str, Any],
    created_at: str,
    completed_at: str,
    raw_glb: Path,
    thumbnail: Path,
) -> Dict[str, Any]:
    consumed = response.get("consumed_credits")
    if not isinstance(consumed, int) or isinstance(consumed, bool) or consumed < 0:
        raise ValueError("Meshy success response did not contain consumed_credits")
    generation = contract.document["generation"]
    model = generation["ai_model"]
    return {
        "completed_at": completed_at,
        "consumed_credits": consumed,
        "contract_sha256": contract.sha256,
        "created_at": created_at,
        "endpoint": endpoint,
        "input_image_hashes": {},
        "outputs": {
            "raw.glb": _file_evidence(raw_glb),
            "thumbnail.png": _file_evidence(thumbnail),
        },
        "prompt_packet_sha256": prompt_hash,
        "provenance": {
            "license_state": _license_state(contract),
            "model": model,
            "provider": "meshy",
        },
        "request": request,
        "status": "SUCCEEDED",
        "task_id": task_id,
    }


def _write_canonical(path: Path, value: object) -> None:
    path.write_bytes(canonical_json_bytes(value))


def _publish_task_directory(temp_dir: Path, final_dir: Path) -> None:
    """Publish a completed task directory under its exact task id.

    A resume replaces the old task directory only after all new downloads and
    metadata are complete.  The short backup window gives a failed replace a
    rollback path without exposing a partial task directory.
    """
    _reject_static_symlink_components(final_dir, "Meshy task path")
    final_exists = os.path.lexists(str(final_dir))
    if not final_exists:
        os.replace(str(temp_dir), str(final_dir))
        return
    if final_dir.is_symlink() or not final_dir.is_dir():
        raise ValueError("Meshy task path is not a directory")
    backup = final_dir.with_name("." + final_dir.name + ".previous-" + uuid.uuid4().hex)
    os.replace(str(final_dir), str(backup))
    try:
        os.replace(str(temp_dir), str(final_dir))
    except BaseException:
        if not os.path.lexists(str(final_dir)) and os.path.lexists(str(backup)):
            os.replace(str(backup), str(final_dir))
        raise
    try:
        shutil.rmtree(str(backup))
    except FileNotFoundError:
        pass


def _copy_resume_metadata(final_dir: Path, temp_dir: Path) -> None:
    for name in ("contract.json", "prompt-packet.json", "review.json"):
        source = final_dir / name
        if not source.exists():
            continue
        if source.is_symlink() or not source.is_file():
            raise ValueError("existing Meshy metadata is not a regular file")
        shutil.copy2(str(source), str(temp_dir / name))


def _stage_task(
    contract: AssetContract,
    project_root: Path,
    client: Any,
    endpoint: str,
    request: Dict[str, Any],
    prompt_hash: str,
    task_id: str,
    created_at: str,
    existing_dir: Optional[Path] = None,
) -> Dict[str, Any]:
    root, _stage, asset_root = _root_and_stage(project_root, contract.asset_id)
    del root
    asset_root.mkdir(parents=True, exist_ok=True)
    _reject_static_symlink_components(asset_root, "Meshy asset staging path")
    final_dir = asset_root / task_id
    _reject_static_symlink_components(final_dir, "Meshy task path")
    temp_dir = Path(tempfile.mkdtemp(prefix="." + task_id + ".", dir=str(asset_root)))
    try:
        if existing_dir is not None:
            _copy_resume_metadata(existing_dir, temp_dir)
        else:
            _write_canonical(temp_dir / "contract.json", contract.document)
            _write_canonical(temp_dir / "prompt-packet.json", render_prompt_packet(contract))

        response = _poll_until_succeeded(client, endpoint, task_id)
        model_urls = response.get("model_urls")
        if not isinstance(model_urls, dict) or not isinstance(model_urls.get("glb"), str):
            raise ValueError("Meshy success response did not contain a GLB URL")
        thumbnail_url = response.get("thumbnail_url")
        if not isinstance(thumbnail_url, str):
            raise ValueError("Meshy success response did not contain a thumbnail URL")

        raw_glb = temp_dir / "raw.glb"
        thumbnail = temp_dir / "thumbnail.png"
        # The final task directory does not exist during either download: only
        # the private sibling temp directory is handed to the client.
        client.download(model_urls["glb"], raw_glb)
        client.download(thumbnail_url, thumbnail)
        _require_downloaded_file(raw_glb, "raw.glb")
        _require_downloaded_file(thumbnail, "thumbnail.png")

        record = _generation_record(
            contract,
            request,
            endpoint,
            task_id,
            prompt_hash,
            response,
            created_at,
            _utc_timestamp(),
            raw_glb,
            thumbnail,
        )
        _write_canonical(temp_dir / "generation.json", record)
        _publish_task_directory(temp_dir, final_dir)
        return record
    except BaseException:
        shutil.rmtree(str(temp_dir), ignore_errors=True)
        raise


def generate_batch(
    contract: AssetContract,
    project_root: Path,
    client: Any,
    approved_credits: int,
) -> Dict[str, Any]:
    """Create, poll, download, and atomically publish a bounded candidate batch."""
    candidate_count, endpoint, request, estimated_cost, prompt_hash = _generation_details(contract)
    if (
        not isinstance(approved_credits, int)
        or isinstance(approved_credits, bool)
        or approved_credits < estimated_cost
    ):
        raise ValueError(
            "approved credit ceiling is below the estimated Meshy batch cost "
            "({0} required)".format(estimated_cost)
        )
    if client is None or not hasattr(client, "get_balance"):
        raise ValueError("a Meshy client is required for generation")
    balance = client.get_balance()
    if not isinstance(balance, int) or isinstance(balance, bool) or balance < estimated_cost:
        raise ValueError(
            "insufficient Meshy balance for the estimated batch cost ({0} required)".format(
                estimated_cost
            )
        )

    task_ids = []
    consumed_total = 0
    for _index in range(candidate_count):
        created_at = _utc_timestamp()
        task_id = _safe_task_id(client.create_task(endpoint, request))
        task_ids.append(task_id)
        record = _stage_task(
            contract,
            project_root,
            client,
            endpoint,
            request,
            prompt_hash,
            task_id,
            created_at,
        )
        consumed_total += record["consumed_credits"]
    return {
        "asset_id": contract.asset_id,
        "candidate_count": candidate_count,
        "estimated_cost": estimated_cost,
        "consumed_credits": consumed_total,
        "task_ids": task_ids,
    }


def resume_batch(
    contract: AssetContract, project_root: Path, client: Any
) -> Dict[str, Any]:
    """Resume pending staged tasks without creating duplicate provider tasks."""
    _candidate_count, _endpoint, _request, _estimated_cost, prompt_hash = _generation_details(contract)
    _root, _stage, asset_root = _root_and_stage(project_root, contract.asset_id)
    if not asset_root.is_dir():
        return {"asset_id": contract.asset_id, "resumed": [], "skipped": []}

    resumed = []
    skipped = []
    for generation_path in sorted(asset_root.glob("*/generation.json")):
        task_dir = generation_path.parent
        if not task_dir.is_dir() or task_dir.name.startswith("."):
            continue
        try:
            generation = json.loads(generation_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError("invalid staged generation record: {0}".format(task_dir.name)) from exc
        if not isinstance(generation, dict):
            raise ValueError("staged generation record must be an object")
        task_id = _safe_task_id(generation.get("task_id"))
        if task_id != task_dir.name:
            raise ValueError("staged generation task id does not match its directory")
        status = generation.get("status")
        if status == "SUCCEEDED":
            skipped.append(task_id)
            continue
        if status != "PENDING":
            raise ValueError("unsupported staged generation status for {0}".format(task_id))
        endpoint = generation.get("endpoint")
        request = generation.get("request")
        if not isinstance(endpoint, str) or endpoint not in ENDPOINTS.values() or not isinstance(request, dict):
            raise ValueError("pending staged generation has invalid request metadata")
        created_at = generation.get("created_at")
        if not isinstance(created_at, str) or not created_at:
            created_at = _utc_timestamp()
        _stage_task(
            contract,
            project_root,
            client,
            endpoint,
            _copy_mapping(request),
            prompt_hash,
            task_id,
            created_at,
            existing_dir=task_dir,
        )
        resumed.append(task_id)
    return {"asset_id": contract.asset_id, "resumed": resumed, "skipped": skipped}


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    plan = subparsers.add_parser("plan")
    plan.add_argument("--project-root", type=Path, required=True)
    plan.add_argument("--contract", type=Path, required=True)
    plan.add_argument("--pricing-file", type=Path, default=None)
    plan.add_argument("--reference-root", type=Path, default=None)
    plan.add_argument("--reference", action="append", default=None, metavar="VIEW=FILENAME")
    generate = subparsers.add_parser("generate")
    generate.add_argument("--project-root", type=Path, required=True)
    generate.add_argument("--contract", type=Path, required=True)
    generate.add_argument("--approved-credits", type=int, required=True)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        contract = load_contract(args.contract)
        if args.command == "plan":
            result = plan_generation(
                contract,
                args.project_root,
                pricing_file=args.pricing_file,
                reference_root=args.reference_root,
                reference_specs=args.reference,
            )
        elif args.command == "generate":
            # Reject a zero/negative ceiling before constructing a client.  This
            # makes the safety gate useful even when no API key is configured.
            if args.approved_credits <= 0:
                raise ValueError("approved credit ceiling must be positive")
            result = generate_batch(
                contract,
                args.project_root,
                MeshyClient(),
                args.approved_credits,
            )
        else:  # pragma: no cover - argparse owns the command choices
            return 2
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        print("error: {0}".format(exc), file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "DEFAULT_PRICING_PATH",
    "ENDPOINTS",
    "MeshyClient",
    "PricingRecord",
    "ReferenceInput",
    "ReferenceInputs",
    "TransientProviderRequest",
    "build_transient_provider_request",
    "generate_batch",
    "load_pricing",
    "plan_generation",
    "resolve_reference_inputs",
    "resume_batch",
]
