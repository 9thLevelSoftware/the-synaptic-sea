#!/usr/bin/env python3
"""Preflight, journal, and securely stage bounded Meshy candidates.

Generation is deliberately a no-promotion workflow.  All provider calls are
made through an injectable client in tests; the real client has a fixed
production origin and never writes secrets or signed URLs to evidence.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import inspect
import json
import math
import os
import re
import stat
import sys
import tempfile
import time
import uuid
from datetime import date as _date, datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Mapping, NamedTuple, Optional, Tuple, Union
from urllib.parse import urlsplit

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools import meshy_governance as governance  # noqa: E402
from tools.meshy_asset_contract import (  # noqa: E402
    AssetContract,
    canonical_json_bytes,
    load_contract,
    render_prompt_packet,
)


ENDPOINTS = {
    "image_to_3d": "/openapi/v1/image-to-3d",
    "multi_image_to_3d": "/openapi/v1/multi-image-to-3d",
}
DEFAULT_PRICING_PATH = Path(__file__).resolve().parents[1] / "data/asset_generation/meshy_pricing_v1.json"
STAGING_RELATIVE = Path("assets/_staging/meshy")
PROTECTED_RELATIVE = governance.PROTECTED_RUNTIME_RELATIVE_PATHS
_TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
_BATCH_ID_RE = re.compile(r"^[0-9a-f]{32}$")
_HASH_RE = re.compile(r"^[0-9a-f]{64}$")
_REFERENCE_EXTENSIONS = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
_PNG_SIGNATURE = bytes((137, 80, 78, 71, 13, 10, 26, 10))
_JPEG_SIGNATURE = bytes((255, 216, 255))
_PRICING_MAX_BYTES = 1024 * 1024
_REFERENCE_FILE_MAX_BYTES = 16 * 1024 * 1024
_REFERENCE_TOTAL_MAX_BYTES = 48 * 1024 * 1024
_GLB_MAX_BYTES = 64 * 1024 * 1024
_THUMBNAIL_MAX_BYTES = 16 * 1024 * 1024
_DOWNLOAD_TOTAL_MAX_BYTES = 80 * 1024 * 1024
_MAX_POLL_ATTEMPTS = 120
_POLL_DELAYS = (0.0, 0.25, 0.5, 1.0, 2.0)
_ALLOWED_LICENSES = ("paid-private", "free-cc-by-4.0")


class MeshyClient:
    """Small requests-backed client with a fixed, production API origin."""

    PRODUCTION_ORIGIN = "https://api.meshy.ai"
    DOWNLOAD_HOST = "assets.meshy.ai"

    def __init__(self, api_key: Optional[str] = None, base_url: Optional[str] = None, session: Any = None) -> None:
        # MESHY_BASE_URL is intentionally ignored: an environment value must
        # never redirect an API key.  A supplied origin is accepted only when it
        # is the exact production origin, including for injected sessions.
        origin = (base_url or self.PRODUCTION_ORIGIN).rstrip("/")
        if origin != self.PRODUCTION_ORIGIN:
            raise ValueError("Meshy base URL must be https://api.meshy.ai")
        if api_key is None:
            api_key = os.environ.get("MESHY_API_KEY")
        if session is None:
            if not api_key:
                raise ValueError("MESHY_API_KEY is required for generation")
            try:
                import requests
            except ImportError as exc:  # pragma: no cover
                raise ValueError("requests is required for generation") from exc
            session = requests.Session()
            try:
                session.trust_env = False
            except AttributeError:
                pass
        self.api_key = api_key or ""
        self.base_url = origin
        self.session = session

    @staticmethod
    def _safe_transport_error() -> RuntimeError:
        return RuntimeError("Meshy transport failed")

    def _request(self, method: str, endpoint: str, **kwargs: Any) -> Any:
        headers = dict(kwargs.pop("headers", {}))
        if self.api_key:
            headers["Authorization"] = "Bearer " + self.api_key
        headers["Accept"] = "application/json"
        response = None
        try:
            for attempt in range(3):
                try:
                    response = self.session.request(
                        method,
                        self.base_url + endpoint,
                        headers=headers,
                        timeout=(10, 60),
                        **kwargs,
                    )
                except Exception as exc:
                    raise self._safe_transport_error() from exc
                status = getattr(response, "status_code", None)
                if not isinstance(status, int) or isinstance(status, bool):
                    raise RuntimeError("Meshy response had an invalid status")
                if status not in (429, 500, 502, 503, 504):
                    break
                if attempt < 2:
                    time.sleep(0.5 * (2 ** attempt))
            status = getattr(response, "status_code", None)
            if not isinstance(status, int) or not 200 <= status < 300:
                raise RuntimeError("Meshy request failed with status {0}".format(status if isinstance(status, int) else "unknown"))
            try:
                return response.json()
            except Exception as exc:
                raise RuntimeError("Meshy returned invalid JSON") from exc
        except RuntimeError:
            raise
        except Exception as exc:
            raise self._safe_transport_error() from exc

    def get_balance(self) -> int:
        payload = self._request("GET", "/openapi/v1/balance")
        if isinstance(payload, dict):
            for key in ("balance", "credits", "credit_balance"):
                value = payload.get(key)
                if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
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

    @classmethod
    def _validate_download_url(cls, value: object) -> str:
        if not isinstance(value, str) or len(value) > 4096:
            raise RuntimeError("Meshy download URL is invalid")
        try:
            parsed = urlsplit(value)
            port = parsed.port
        except ValueError as exc:
            raise RuntimeError("Meshy download URL is invalid") from exc
        host = (parsed.hostname or "").lower()
        if parsed.scheme != "https" or port not in (None, 443) or not host or parsed.username or parsed.password or parsed.fragment:
            raise RuntimeError("Meshy download URL is not approved")
        if not (host == cls.DOWNLOAD_HOST or (host.endswith(".meshy.ai") and host != "meshy.ai")):
            raise RuntimeError("Meshy download host is not approved")
        return value

    def download(
        self,
        url: str,
        destination: Path,
        max_bytes: int = _GLB_MAX_BYTES,
        deadline: Optional[float] = None,
        clock: Optional[Callable[[], float]] = None,
    ) -> None:
        self._validate_download_url(url)
        if not isinstance(max_bytes, int) or isinstance(max_bytes, bool) or max_bytes <= 0:
            raise RuntimeError("Meshy download size limit is invalid")
        now = clock or time.monotonic
        started = now()
        parent = Path(destination).parent
        try:
            info = parent.lstat()
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
                raise RuntimeError("Meshy download directory is not private")
            current = Path(os.path.abspath(os.fspath(parent.anchor or os.sep)))
            for component in Path(os.path.abspath(os.fspath(parent))).parts[1:]:
                current /= component
                if current in (Path("/tmp"), Path("/var")):
                    continue
                if current.is_symlink():
                    raise RuntimeError("Meshy download directory contains a symlink")
        except OSError as exc:
            raise RuntimeError("Meshy download directory is unavailable") from exc
        temporary: Optional[Path] = None
        response = None
        try:
            try:
                response = self.session.get(url, stream=True, timeout=(10, 120))
            except Exception as exc:
                raise self._safe_transport_error() from exc
            status = getattr(response, "status_code", None)
            if not isinstance(status, int) or isinstance(status, bool):
                raise RuntimeError("Meshy download returned an invalid status")
            if not 200 <= status < 300:
                raise RuntimeError("Meshy download failed with status {0}".format(status))
            if deadline is not None and now() - started >= deadline:
                raise RuntimeError("Meshy download deadline exceeded")
            descriptor, name = tempfile.mkstemp(prefix="." + Path(destination).name + ".", suffix=".tmp", dir=str(parent))
            os.close(descriptor)
            temporary = parent / name
            total = 0
            with temporary.open("wb") as handle:
                for chunk in response.iter_content(chunk_size=1024 * 1024):
                    if deadline is not None and now() - started >= deadline:
                        raise RuntimeError("Meshy download deadline exceeded")
                    if chunk:
                        if not isinstance(chunk, bytes):
                            raise RuntimeError("Meshy download returned invalid bytes")
                        total += len(chunk)
                        if total > max_bytes:
                            raise RuntimeError("Meshy download exceeds maximum size")
                        handle.write(chunk)
                handle.flush()
                os.fsync(handle.fileno())
            if deadline is not None and now() - started >= deadline:
                raise RuntimeError("Meshy download deadline exceeded")
            os.replace(str(temporary), str(destination))
            temporary = None
        except RuntimeError:
            raise
        except Exception as exc:
            raise self._safe_transport_error() from exc
        finally:
            if temporary is not None:
                try:
                    temporary.unlink()
                except OSError:
                    pass


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _copy_mapping(value: Mapping[str, Any]) -> Dict[str, Any]:
    return json.loads(canonical_json_bytes(dict(value)).decode("utf-8"))


class _SealedCapsule:
    __slots__ = ()

    def __setattr__(self, name: str, value: object) -> None:
        raise AttributeError("capsule records are immutable")

    def __delattr__(self, name: str) -> None:
        raise AttributeError("capsule records are immutable")

    def __reduce_ex__(self, protocol: Any) -> Any:
        raise TypeError("capsule records cannot be pickled")


class ReferenceInput(_SealedCapsule):
    __slots__ = ("_view", "_basename", "_media_type", "_byte_size", "_sha256", "_bytes")

    def __init__(self, view: str, basename: str, media_type: str, byte_size: int, sha256: str, _bytes: bytes) -> None:
        object.__setattr__(self, "_view", view)
        object.__setattr__(self, "_basename", basename)
        object.__setattr__(self, "_media_type", media_type)
        object.__setattr__(self, "_byte_size", byte_size)
        object.__setattr__(self, "_sha256", sha256)
        object.__setattr__(self, "_bytes", _bytes)

    view = property(lambda self: self._view)
    basename = property(lambda self: self._basename)
    media_type = property(lambda self: self._media_type)
    byte_size = property(lambda self: self._byte_size)
    sha256 = property(lambda self: self._sha256)

    @property
    def metadata(self) -> Dict[str, Any]:
        return {"view": self.view, "basename": self.basename, "media_type": self.media_type, "byte_size": self.byte_size, "sha256": self.sha256}

    def __repr__(self) -> str:
        return "ReferenceInput(view={0!r}, basename={1!r}, media_type={2!r}, byte_size={3!r}, sha256={4!r})".format(self.view, self.basename, self.media_type, self.byte_size, self.sha256)


class ReferenceInputs(_SealedCapsule):
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
        return tuple(item.metadata for item in self.references)

    def __repr__(self) -> str:
        return "ReferenceInputs(count={0})".format(len(self.references))


class PricingRecord(_SealedCapsule):
    __slots__ = ("_pricing_id", "_checked_at", "_expires_at", "_source_url", "_sha256", "_snapshot")

    def __init__(self, pricing_id: str, checked_at: str, expires_at: str, source_url: str, sha256: str, _snapshot: bytes) -> None:
        object.__setattr__(self, "_pricing_id", pricing_id)
        object.__setattr__(self, "_checked_at", checked_at)
        object.__setattr__(self, "_expires_at", expires_at)
        object.__setattr__(self, "_source_url", source_url)
        object.__setattr__(self, "_sha256", sha256)
        object.__setattr__(self, "_snapshot", _snapshot)

    pricing_id = property(lambda self: self._pricing_id)
    checked_at = property(lambda self: self._checked_at)
    expires_at = property(lambda self: self._expires_at)
    source_url = property(lambda self: self._source_url)
    sha256 = property(lambda self: self._sha256)

    @property
    def document(self) -> Dict[str, Any]:
        return json.loads(self._snapshot.decode("utf-8"))

    def snapshot_bytes(self) -> bytes:
        return bytes(self._snapshot)

    def cost_for(self, contract: AssetContract) -> int:
        if not isinstance(contract, AssetContract):
            raise TypeError("cost_for requires an AssetContract")
        generation = contract._snapshot_document().get("generation")
        if not isinstance(generation, dict):
            raise ValueError("contract generation must be an object")
        values = (generation.get("mode"), generation.get("model_type"), generation.get("ai_model"), generation.get("should_texture"))
        if not isinstance(values[0], str) or not isinstance(values[1], str) or not isinstance(values[2], str) or values[3] is not False:
            raise ValueError("unknown Meshy pricing combination")
        try:
            value = self.document["costs"][values[0]][values[1]][values[2]]["untextured"]
        except (KeyError, TypeError):
            raise ValueError("unknown Meshy pricing combination")
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise ValueError("unknown Meshy pricing combination")
        return value

    def __repr__(self) -> str:
        return "PricingRecord(pricing_id={0!r}, checked_at={1!r}, expires_at={2!r}, source_url={3!r}, sha256={4!r})".format(self.pricing_id, self.checked_at, self.expires_at, self.source_url, self.sha256)


class TransientProviderRequest(_SealedCapsule):
    __slots__ = ("_provider_payload_sha256", "_payload_snapshot", "_redacted_snapshot")

    def __init__(self, provider_payload_sha256: str, _payload_snapshot: bytes, _redacted_snapshot: bytes) -> None:
        object.__setattr__(self, "_provider_payload_sha256", provider_payload_sha256)
        object.__setattr__(self, "_payload_snapshot", _payload_snapshot)
        object.__setattr__(self, "_redacted_snapshot", _redacted_snapshot)

    provider_payload_sha256 = property(lambda self: self._provider_payload_sha256)

    @property
    def payload(self) -> Dict[str, Any]:
        return json.loads(self._payload_snapshot.decode("utf-8"))

    @property
    def redacted_request(self) -> Dict[str, Any]:
        return json.loads(self._redacted_snapshot.decode("utf-8"))

    def __repr__(self) -> str:
        return "TransientProviderRequest(provider_payload_sha256={0!r})".format(self.provider_payload_sha256)


def _coerce_iso_date(value: object, label: str) -> _date:
    if isinstance(value, _date) and not isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            parsed = _date.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("{0} must be an ISO date".format(label)) from exc
        if parsed.isoformat() != value:
            raise ValueError("{0} must be an ISO date".format(label))
        return parsed
    raise ValueError("{0} must be an ISO date".format(label))


def _validate_pricing_document(document: Mapping[str, Any]) -> None:
    expected = {"schema_version", "document_kind", "pricing_id", "checked_at", "expires_at", "source_url", "costs"}
    if set(document) != expected or document.get("schema_version") != "1.0.0" or document.get("document_kind") != "meshy_pricing":
        raise ValueError("pricing document fields are not exact")
    if document.get("pricing_id") != "meshy_api_2026_08_31" or not isinstance(document.get("pricing_id"), str):
        raise ValueError("pricing_id is not the approved pricing record")
    checked = _coerce_iso_date(document.get("checked_at"), "pricing checked_at")
    expires = _coerce_iso_date(document.get("expires_at"), "pricing expires_at")
    if checked >= expires:
        raise ValueError("pricing checked_at must precede pricing expires_at")
    if document.get("source_url") != "https://docs.meshy.ai/api/pricing.md":
        raise ValueError("pricing source_url is not official")
    expected_costs = {
        "image_to_3d": {"smart-topology": {"meshy-t2": {"untextured": 5}}},
        "multi_image_to_3d": {"standard": {"meshy-7": {"untextured": 20}, "latest": {"untextured": 20}}},
    }
    def exact_equal(left: object, right: object) -> bool:
        if type(left) is not type(right):
            return False
        if isinstance(left, dict) and isinstance(right, dict):
            return set(left) == set(right) and all(exact_equal(left[key], right[key]) for key in left)
        if isinstance(left, list) and isinstance(right, list):
            return len(left) == len(right) and all(exact_equal(a, b) for a, b in zip(left, right))
        return left == right

    if not exact_equal(document.get("costs"), expected_costs):
        raise ValueError("pricing costs contain an unknown combination or non-positive integer")


def load_pricing(path: Optional[Path] = None, today: object = None, date: object = None) -> PricingRecord:
    if today is not None and date is not None:
        raise ValueError("pass only one of today or date")
    source = Path(path) if path is not None else DEFAULT_PRICING_PATH
    try:
        document, raw = governance.strict_load_json_bytes(source, "Meshy pricing", _PRICING_MAX_BYTES)
        _validate_pricing_document(document)
        as_of = _coerce_iso_date(today if today is not None else date if date is not None else _date.today(), "pricing today")
        if as_of >= _coerce_iso_date(document["expires_at"], "pricing expires_at"):
            raise ValueError("Meshy pricing is expired")
    except (OSError, TypeError, ValueError) as exc:
        if isinstance(exc, ValueError) and str(exc) == "Meshy pricing is expired":
            raise
        raise ValueError("Meshy pricing could not be read: {0}".format(exc)) from exc
    return PricingRecord(document["pricing_id"], document["checked_at"], document["expires_at"], document["source_url"], hashlib.sha256(raw).hexdigest(), canonical_json_bytes(document))


def _resolve_reference_root(reference_root: Union[str, os.PathLike]) -> Path:
    candidate = Path(reference_root).expanduser()
    try:
        if candidate.is_symlink():
            raise ValueError("reference root must not be a symlink")
        resolved = candidate.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise ValueError("reference root could not be resolved") from exc
    if not resolved.is_dir():
        raise ValueError("reference root must be a directory")
    return resolved


def _parse_reference_specs(specs: Union[Mapping[str, str], Iterable[Union[str, Tuple[str, str]]]]) -> Dict[str, str]:
    if isinstance(specs, Mapping):
        entries = list(specs.items())
    elif isinstance(specs, str):
        entries = [specs]
    else:
        try:
            entries = list(specs)
        except TypeError as exc:
            raise ValueError("reference specs must be a mapping or view=filename") from exc
    result: Dict[str, str] = {}
    for entry in entries:
        if isinstance(entry, str) and entry.count("=") == 1:
            view, filename = entry.split("=", 1)
        elif isinstance(entry, (tuple, list)) and len(entry) == 2:
            view, filename = entry
        else:
            raise ValueError("reference spec must be view=filename")
        if not isinstance(view, str) or not isinstance(filename, str) or not view or not filename or view in result:
            raise ValueError("reference spec view and filename must be unique strings")
        result[view] = filename
    return result


def _validate_reference_filename(filename: str) -> str:
    if not filename or "/" in filename or chr(92) in filename or filename in (".", "..") or any(ord(c) == 0 for c in filename):
        raise ValueError("reference filename must be basename-only")
    candidate = Path(filename)
    suffix = candidate.suffix.lower()
    if candidate.is_absolute() or candidate.name != filename or suffix not in _REFERENCE_EXTENSIONS:
        raise ValueError("reference filename must be basename-only with a supported extension")
    return suffix


def _reference_magic_matches(suffix: str, payload: bytes) -> bool:
    return payload.startswith(_PNG_SIGNATURE) if suffix == ".png" else payload.startswith(_JPEG_SIGNATURE) and payload.endswith(bytes((255, 217)))


def _provider_required_views(contract: AssetContract) -> List[str]:
    document = contract._snapshot_document()
    refs = document.get("references")
    views = refs.get("required_views") if isinstance(refs, dict) else None
    if not isinstance(views, list) or not views or any(not isinstance(v, str) for v in views) or len(views) != len(set(views)):
        raise ValueError("contract references.required_views must be a non-empty unique list")
    if document.get("generation", {}).get("mode") == "multi_image_to_3d" and views[0] != "front":
        raise ValueError("multi-image provider requires front as the first reference view")
    return views


def resolve_reference_inputs(contract: AssetContract, reference_root: Union[str, os.PathLike], reference_specs: Union[Mapping[str, str], Iterable[Union[str, Tuple[str, str]]]]) -> ReferenceInputs:
    views = _provider_required_views(contract)
    parsed = _parse_reference_specs(reference_specs)
    if set(parsed) != set(views):
        raise ValueError("reference views must match contract exactly")
    root = _resolve_reference_root(reference_root)
    result: List[ReferenceInput] = []
    names = set()
    identities = set()
    hashes = set()
    total = 0
    for view in views:
        filename = parsed[view]
        suffix = _validate_reference_filename(filename)
        if filename.casefold() in names:
            raise ValueError("duplicate reference basename across views")
        names.add(filename.casefold())
        path = root / filename
        try:
            governance._reject_symlink_components_below(root, path, "reference {0}".format(view))
            payload = governance._read_bounded_regular_file(path, "reference {0}".format(view), _REFERENCE_FILE_MAX_BYTES)
            info = path.stat()
        except (OSError, ValueError) as exc:
            raise ValueError("reference {0} could not be read: {1}".format(view, exc)) from exc
        identity = (info.st_dev, info.st_ino)
        if identity in identities:
            raise ValueError("duplicate reference file identity across views")
        identities.add(identity)
        total += len(payload)
        if total > _REFERENCE_TOTAL_MAX_BYTES:
            raise ValueError("references exceed maximum aggregate size")
        if not _reference_magic_matches(suffix, payload):
            raise ValueError("reference {0} has an invalid signature".format(view))
        digest = hashlib.sha256(payload).hexdigest()
        if digest in hashes:
            raise ValueError("duplicate reference content SHA-256 across views")
        hashes.add(digest)
        result.append(ReferenceInput(view, filename, _REFERENCE_EXTENSIONS[suffix], len(payload), digest, bytes(payload)))
    return ReferenceInputs(result)


def _base_provider_request(contract: AssetContract) -> Dict[str, Any]:
    generation = contract._snapshot_document().get("generation")
    if not isinstance(generation, dict) or generation.get("mode") not in ENDPOINTS:
        raise ValueError("unsupported Meshy generation mode")
    fields = ("model_type", "ai_model", "target_polycount", "should_texture", "target_formats")
    if any(name not in generation for name in fields):
        raise ValueError("contract generation is missing a request field")
    return _copy_mapping({name: generation[name] for name in fields})


def _validate_resolved_reference_inputs(contract: AssetContract, references: ReferenceInputs) -> List[ReferenceInput]:
    if type(references) is not ReferenceInputs or len(references) != len(_provider_required_views(contract)):
        raise ValueError("reference inputs must match contract views exactly")
    seen_names, seen_hashes = set(), set()
    total = 0
    for item, expected_view in zip(references.references, _provider_required_views(contract)):
        if type(item) is not ReferenceInput or item.view != expected_view or not isinstance(item._bytes, bytes):
            raise ValueError("reference inputs are not immutable resolver records")
        suffix = _validate_reference_filename(item.basename)
        if item.basename.casefold() in seen_names:
            raise ValueError("duplicate reference basename across views")
        seen_names.add(item.basename.casefold())
        if item.media_type != _REFERENCE_EXTENSIONS[suffix] or item.byte_size != len(item._bytes) or item.byte_size <= 0:
            raise ValueError("reference metadata does not match bytes")
        total += item.byte_size
        if total > _REFERENCE_TOTAL_MAX_BYTES or not _reference_magic_matches(suffix, item._bytes):
            raise ValueError("reference bytes are invalid")
        digest = hashlib.sha256(item._bytes).hexdigest()
        if item.sha256 != digest or digest in seen_hashes:
            raise ValueError("reference sha256 does not match immutable bytes")
        seen_hashes.add(digest)
    return list(references.references)


def build_transient_provider_request(contract: AssetContract, reference_inputs: ReferenceInputs) -> TransientProviderRequest:
    records = _validate_resolved_reference_inputs(contract, reference_inputs)
    payload = _base_provider_request(contract)
    evidence = [item.metadata for item in records]
    data_uris = ["data:{0};base64,{1}".format(item.media_type, base64.b64encode(item._bytes).decode("ascii")) for item in records]
    mode = contract._snapshot_document()["generation"]["mode"]
    if mode == "image_to_3d":
        payload["image_url"] = data_uris[0]
        redacted = _copy_mapping(payload)
        redacted["image_url"] = evidence[0]
    else:
        payload["image_urls"] = data_uris
        redacted = _copy_mapping(payload)
        redacted["image_urls"] = evidence
    payload_bytes = canonical_json_bytes(payload)
    return TransientProviderRequest(hashlib.sha256(payload_bytes).hexdigest(), payload_bytes, canonical_json_bytes(redacted))


def plan_generation(contract: AssetContract, project_root: Path, client: Any = None, pricing_file: Optional[Path] = None, reference_root: Optional[Path] = None, reference_specs: object = None, today: object = None, date: object = None) -> Dict[str, Any]:
    del project_root, client
    document = contract._snapshot_document()
    generation = document.get("generation")
    if not isinstance(generation, dict) or generation.get("mode") not in ENDPOINTS:
        raise ValueError("unsupported Meshy generation mode")
    count = generation.get("candidate_count")
    if not isinstance(count, int) or isinstance(count, bool) or count <= 0:
        raise ValueError("candidate_count must be a positive integer")
    packet = render_prompt_packet(contract)
    pricing = load_pricing(pricing_file, today=today, date=date)
    transient: Optional[TransientProviderRequest] = None
    if (reference_root is None) != (reference_specs is None):
        raise ValueError("reference-root and reference specs must be supplied together")
    result: Dict[str, Any] = {
        "asset_id": contract.asset_id, "required_views": list(_provider_required_views(contract)), "references_resolved": False,
        "candidate_count": count, "endpoint": ENDPOINTS[generation["mode"]], "cost_per_candidate": pricing.cost_for(contract),
        "maximum_credits": count * pricing.cost_for(contract), "pricing_id": pricing.pricing_id, "pricing_sha256": pricing.sha256,
        "pricing_source_url": pricing.source_url, "pricing_checked_at": pricing.checked_at, "pricing_expires_at": pricing.expires_at,
        "contract_sha256": contract.sha256, "prompt_profile_id": packet["prompt_profile_id"], "prompt_profile_sha256": packet["prompt_profile_sha256"],
        "prompt_packet_sha256": hashlib.sha256(canonical_json_bytes(packet)).hexdigest(), "request": _base_provider_request(contract),
    }
    if reference_root is not None and reference_specs is not None:
        resolved = resolve_reference_inputs(contract, reference_root, reference_specs)
        transient = build_transient_provider_request(contract, resolved)
        result.update({"references_resolved": True, "resolved_references": list(resolved.metadata), "request": transient.redacted_request, "provider_payload_sha256": transient.provider_payload_sha256})
    return result


def _safe_task_id(value: object) -> str:
    if not isinstance(value, str) or _TASK_ID_RE.fullmatch(value) is None:
        raise ValueError("Meshy returned an unsafe task id")
    return value


def _validate_staging_paths(project_root: Union[str, os.PathLike], asset_id: str) -> Tuple[Path, Path, Path]:
    root = governance.physical_project_root(project_root)
    if not isinstance(asset_id, str) or _TASK_ID_RE.fullmatch(asset_id) is None:
        raise ValueError("contract asset_id is not a safe staging identifier")
    stage = root / STAGING_RELATIVE
    asset_root = stage / asset_id
    governance._reject_symlink_components_below(root, stage, "Meshy staging path")
    governance._reject_symlink_components_below(root, asset_root, "Meshy asset staging path")
    for relative in PROTECTED_RELATIVE:
        protected = root / relative
        governance._reject_symlink_components_below(root, protected, "protected surface")
        if governance._contained(protected, stage) or governance._contained(protected, asset_root) or governance._contained(stage, protected):
            raise ValueError("Meshy staging path overlaps a protected runtime surface")
    return root, stage, asset_root


def _safe_error(exc: BaseException) -> str:
    message = str(exc) or exc.__class__.__name__
    message = re.sub(r"https?://[^\s]+", "provider URL", message)
    message = re.sub(r"(?i)(authorization|bearer|api[_-]?key|token|signature)\s*[:=]?\s*[^\s,;]+", r"\1 redacted", message)
    message = re.sub(r"(?i)signed-download(?:-[A-Za-z0-9_-]+)*|sk-[A-Za-z0-9_-]+", "secret redacted", message)
    return message[:240]


class _Preflight(NamedTuple):
    root: Path
    stage: Path
    asset_root: Path
    batch_root: Path
    contract: AssetContract
    pricing: PricingRecord
    pricing_path: Optional[Path]
    prompt_packet: Dict[str, Any]
    prompt_hash: str
    references: ReferenceInputs
    reference_root: Path
    reference_specs: Tuple[Tuple[str, str], ...]
    transient: TransientProviderRequest
    endpoint: str
    candidate_count: int
    cost_per_candidate: int
    maximum_credits: int
    approved_credits: int
    output_license: str
    protected_snapshot: Tuple[governance.ProtectedSurfaceRecord, ...]
    today: object
    date: object
    clock: Callable[[], float]
    operation_deadline: Optional[float]


def _validate_positive_int(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ValueError("{0} must be a positive integer".format(label))
    return value


def _new_deadline(clock: Callable[[], float], deadline: object) -> Optional[float]:
    if deadline is None:
        return None
    if not isinstance(deadline, (int, float)) or isinstance(deadline, bool) or not math.isfinite(float(deadline)) or float(deadline) < 0:
        raise ValueError("deadline must be a non-negative finite number")
    return clock() + float(deadline)


def _check_deadline(preflight: _Preflight) -> None:
    if preflight.operation_deadline is not None and preflight.clock() >= preflight.operation_deadline:
        raise RuntimeError("Meshy generation deadline exceeded")


def _approval(preflight: _Preflight, created_at: str) -> Dict[str, Any]:
    return {
        "contract_sha256": preflight.contract.sha256,
        "prompt_profile_id": preflight.prompt_packet["prompt_profile_id"],
        "prompt_profile_sha256": preflight.prompt_packet["prompt_profile_sha256"],
        "prompt_packet_sha256": preflight.prompt_hash,
        "pricing_id": preflight.pricing.pricing_id,
        "pricing_sha256": preflight.pricing.sha256,
        "provider_payload_sha256": preflight.transient.provider_payload_sha256,
        "request": preflight.transient.redacted_request,
        "references": list(preflight.references.metadata),
        "endpoint": preflight.endpoint,
        "candidate_count": preflight.candidate_count,
        "cost_per_candidate": preflight.cost_per_candidate,
        "maximum_credits": preflight.maximum_credits,
        "approved_credits": preflight.approved_credits,
        "output_license": preflight.output_license,
        "protected_snapshot": [{"type": item.type, "path": item.path, "sha256": item.sha256, "size": item.size} for item in preflight.protected_snapshot],
        "created_at": created_at,
    }


def _journal_document(preflight: _Preflight, batch_id: str, state: str, tasks: List[Dict[str, Any]], cumulative: int, created_at: str) -> Dict[str, Any]:
    return {"schema_version": "1.0.0", "document_kind": "meshy_batch_journal", "batch_id": batch_id, "asset_id": preflight.contract.asset_id, "approval": _approval(preflight, created_at), "state": state, "tasks": tasks, "cumulative_consumed_credits": cumulative}


def _write_journal(preflight: _Preflight, batch_id: str, document: Dict[str, Any]) -> None:
    path = preflight.batch_root / (batch_id + ".json")
    governance.atomic_write_json(path, document, project_root=preflight.root, allowed_root=preflight.batch_root)


def _load_open_journals(preflight: _Preflight, contract_sha256: str, profile_sha256: str, pricing_sha256: str, provider_hash: str) -> None:
    if not preflight.batch_root.exists():
        return
    if preflight.batch_root.is_symlink() or not preflight.batch_root.is_dir():
        raise ValueError("Meshy batch journal root is not a directory")
    for path in sorted(preflight.batch_root.glob("*.json")):
        if path.is_symlink() or not path.is_file():
            raise ValueError("Meshy batch journal entry is not a regular file")
        document = governance.strict_load_json(path, "Meshy batch journal", 4 * 1024 * 1024)
        errors = validate_batch_journal(document)
        if errors:
            raise ValueError("invalid Meshy batch journal: " + "; ".join(errors))
        if path.stem != document["batch_id"]:
            raise ValueError("Meshy batch journal filename does not match batch_id")
        if document["state"] in ("APPROVED", "SUBMITTING"):
            approval = document["approval"]
            if (approval["contract_sha256"], approval["prompt_profile_sha256"], approval["pricing_sha256"], approval["provider_payload_sha256"]) == (contract_sha256, profile_sha256, pricing_sha256, provider_hash):
                raise ValueError("an open duplicate Meshy batch already exists")


def _preflight(contract: AssetContract, project_root: Path, client: Any, approved_credits: int, *, pricing_file: Optional[Path], reference_root: Path, reference_specs: object, output_license: str, today: object, date: object, clock: Optional[Callable[[], float]], deadline: object) -> _Preflight:
    del client
    approved = _validate_positive_int(approved_credits, "approved_credits")
    if output_license not in _ALLOWED_LICENSES:
        raise ValueError("output_license must be paid-private or free-cc-by-4.0")
    if reference_root is None or reference_specs is None:
        raise ValueError("reference-root, reference specs, and output-license are required")
    if not isinstance(contract, AssetContract):
        raise TypeError("contract must be an AssetContract")
    source_contract = load_contract(contract.path)
    if source_contract.sha256 != contract.sha256 or source_contract.snapshot_bytes() != contract.snapshot_bytes():
        raise ValueError("asset contract changed since it was loaded")
    packet = render_prompt_packet(source_contract)
    prompt_hash = hashlib.sha256(canonical_json_bytes(packet)).hexdigest()
    pricing = load_pricing(pricing_file, today=today, date=date)
    reference_root_physical = _resolve_reference_root(reference_root)
    parsed_reference_specs = _parse_reference_specs(reference_specs)
    references = resolve_reference_inputs(source_contract, reference_root_physical, parsed_reference_specs)
    transient = build_transient_provider_request(source_contract, references)
    root, stage, asset_root = _validate_staging_paths(project_root, source_contract.asset_id)
    protected = governance.snapshot_protected_surfaces(root)
    cost = pricing.cost_for(source_contract)
    count = _validate_positive_int(source_contract._snapshot_document()["generation"].get("candidate_count"), "candidate_count")
    maximum = count * cost
    if approved < maximum:
        raise ValueError("approved credit ceiling is below the maximum Meshy batch cost ({0} required)".format(maximum))
    batch_root = asset_root / "_batches"
    governance._reject_symlink_components_below(root, batch_root, "Meshy batch journal root")
    result = _Preflight(root, stage, asset_root, batch_root, source_contract, pricing, Path(pricing_file) if pricing_file is not None else None, packet, prompt_hash, references, reference_root_physical, tuple(parsed_reference_specs.items()), transient, ENDPOINTS[source_contract._snapshot_document()["generation"]["mode"]], count, cost, maximum, approved, output_license, protected, today, date, clock or time.monotonic, _new_deadline(clock or time.monotonic, deadline))
    _load_open_journals(result, source_contract.sha256, packet["prompt_profile_sha256"], pricing.sha256, transient.provider_payload_sha256)
    return result


def _refresh_before_provider(preflight: _Preflight) -> None:
    _check_deadline(preflight)
    current_contract = load_contract(preflight.contract.path)
    if current_contract.sha256 != preflight.contract.sha256 or current_contract.snapshot_bytes() != preflight.contract.snapshot_bytes():
        raise ValueError("asset contract changed during Meshy preflight")
    packet = render_prompt_packet(current_contract)
    if packet["prompt_profile_id"] != preflight.prompt_packet["prompt_profile_id"] or packet["prompt_profile_sha256"] != preflight.prompt_packet["prompt_profile_sha256"] or hashlib.sha256(canonical_json_bytes(packet)).hexdigest() != preflight.prompt_hash:
        raise ValueError("prompt profile changed during Meshy preflight")
    pricing = load_pricing(preflight.pricing_path, today=preflight.today, date=preflight.date)
    if pricing.sha256 != preflight.pricing.sha256:
        raise ValueError("Meshy pricing changed during preflight")
    current_references = resolve_reference_inputs(current_contract, preflight.reference_root, dict(preflight.reference_specs))
    if current_references.metadata != preflight.references.metadata:
        raise ValueError("reference inputs changed during preflight")
    transient = build_transient_provider_request(current_contract, current_references)
    if transient.provider_payload_sha256 != preflight.transient.provider_payload_sha256:
        raise ValueError("Meshy provider payload changed during preflight")
    current_snapshot = governance.snapshot_protected_surfaces(preflight.root)
    if current_snapshot != preflight.protected_snapshot:
        raise ValueError("protected runtime surfaces changed during preflight")


class _TaskFailure(RuntimeError):
    def __init__(self, message: str, consumed: Optional[int] = None) -> None:
        super().__init__(message)
        self.consumed = consumed


def _base_generation(preflight: _Preflight, task_id: str, created_at: str) -> Dict[str, Any]:
    generation = preflight.contract._snapshot_document()["generation"]
    return {
        "schema_version": "1.0.0", "document_kind": "meshy_generation_record", "asset_id": preflight.contract.asset_id, "task_id": task_id,
        "status": "PENDING", "endpoint": preflight.endpoint, "contract_sha256": preflight.contract.sha256,
        "prompt_profile_id": preflight.prompt_packet["prompt_profile_id"], "prompt_profile_sha256": preflight.prompt_packet["prompt_profile_sha256"],
        "prompt_packet_sha256": preflight.prompt_hash, "pricing_id": preflight.pricing.pricing_id, "pricing_sha256": preflight.pricing.sha256,
        "provider_payload_sha256": preflight.transient.provider_payload_sha256, "request": preflight.transient.redacted_request,
        "references": list(preflight.references.metadata), "input_image_hashes": {item.view: item.sha256 for item in preflight.references},
        "output_license": preflight.output_license, "created_at": created_at, "completed_at": None, "consumed_credits": None,
        "outputs": {}, "provenance": {"provider": "meshy", "model": generation["ai_model"], "license_state": preflight.output_license}, "error": None,
    }


def _artifact_path(preflight: _Preflight, task_id: str, name: str) -> Path:
    path = preflight.asset_root / task_id / name
    governance.governed_task_path(preflight.root, path, "Meshy task artifact")
    return path


def _write_artifact_json(preflight: _Preflight, task_id: str, name: str, value: object) -> None:
    governance.atomic_write_json(_artifact_path(preflight, task_id, name), value, project_root=preflight.root, allowed_root=preflight.asset_root)


def _read_download(path: Path, label: str, maximum: int, preflight: _Preflight) -> bytes:
    _check_deadline(preflight)
    return governance._read_bounded_regular_file(path, label, maximum)


def _download_with_limit(client: Any, url: str, destination: Path, maximum: int, preflight: _Preflight) -> None:
    """Use the bounded real-client seam while retaining tiny fake compatibility."""

    remaining = None
    if preflight.operation_deadline is not None:
        remaining = max(0.0, preflight.operation_deadline - preflight.clock())
    try:
        parameters = inspect.signature(client.download).parameters
    except (TypeError, ValueError):
        parameters = {}
    accepts_limits = "max_bytes" in parameters or any(
        parameter.kind == inspect.Parameter.VAR_KEYWORD for parameter in parameters.values()
    )
    if accepts_limits:
        options: Dict[str, Any] = {"max_bytes": maximum}
        if "deadline" in parameters or any(parameter.kind == inspect.Parameter.VAR_KEYWORD for parameter in parameters.values()):
            options["deadline"] = remaining
        if "clock" in parameters or any(parameter.kind == inspect.Parameter.VAR_KEYWORD for parameter in parameters.values()):
            options["clock"] = preflight.clock
        client.download(url, destination, **options)
    else:
        client.download(url, destination)


def _poll_until_succeeded(client: Any, preflight: _Preflight, task_id: str, on_consumed: Callable[[int], None]) -> Dict[str, Any]:
    last: Optional[Dict[str, Any]] = None
    for attempt in range(_MAX_POLL_ATTEMPTS):
        _check_deadline(preflight)
        try:
            response = client.poll_task(preflight.endpoint, task_id)
        except Exception as exc:
            raise _TaskFailure(_safe_error(exc))
        if not isinstance(response, dict):
            raise _TaskFailure("Meshy task response must be an object")
        if response.get("task_id") != task_id:
            raise _TaskFailure("Meshy task response identity mismatch")
        consumed = response.get("consumed_credits")
        if consumed is not None:
            if not isinstance(consumed, int) or isinstance(consumed, bool) or consumed < 0:
                raise _TaskFailure("Meshy consumed_credits must be a non-negative integer")
            on_consumed(consumed)
        last = response
        status = response.get("status")
        if status == "SUCCEEDED":
            return response
        if status in ("FAILED", "CANCELED", "CANCELLED", "EXPIRED"):
            raise _TaskFailure("Meshy task ended with status {0}".format(status), consumed)
        if status not in ("PENDING", "IN_PROGRESS", "QUEUED"):
            raise _TaskFailure("Meshy task returned an unsupported status", consumed)
        if attempt + 1 >= _MAX_POLL_ATTEMPTS:
            break
        delay = _POLL_DELAYS[min(attempt, len(_POLL_DELAYS) - 1)]
        if delay:
            _check_deadline(preflight)
            remaining = preflight.operation_deadline - preflight.clock() if preflight.operation_deadline is not None else delay
            if remaining <= 0:
                raise _TaskFailure("Meshy generation deadline exceeded", consumed)
            time.sleep(min(delay, remaining))
    raise _TaskFailure("Meshy task did not reach SUCCEEDED", last.get("consumed_credits") if last else None)


def _stage_task(client: Any, preflight: _Preflight, task_id: str, created_at: str, prior_consumed: int) -> Dict[str, Any]:
    task_dir = preflight.asset_root / task_id
    if os.path.lexists(str(task_dir)):
        raise _TaskFailure("Meshy task directory already exists")
    generation_record = _base_generation(preflight, task_id, created_at)
    generation_written = False
    last_consumed: Optional[int] = None
    try:
        _write_artifact_json(preflight, task_id, "contract.json", json.loads(preflight.contract.snapshot_bytes().decode("utf-8")))
        _write_artifact_json(preflight, task_id, "prompt-packet.json", preflight.prompt_packet)
        _write_artifact_json(preflight, task_id, "pricing.json", preflight.pricing.document)
        for item in preflight.references:
            _write_artifact_bytes = lambda name, payload: governance.atomic_write_bytes(_artifact_path(preflight, task_id, name), payload, project_root=preflight.root, allowed_root=preflight.asset_root)
            _write_artifact_bytes("source_{0}{1}".format(item.view, Path(item.basename).suffix.lower()), item._bytes)
        review = {"schema_version": "1.0.0", "document_kind": "meshy_candidate_review", "asset_id": preflight.contract.asset_id, "task_id": task_id, "state": "pending", "decision": "pending", "checks": {"silhouette_readable": False, "proportions_match_contract": False, "functional_volume_present": False, "movable_parts_separable": False, "cleanup_bounded": False, "camera_readability": False}, "rejection_reasons": [], "reviewer": "unassigned"}
        _write_artifact_json(preflight, task_id, "review.json", review)
        _write_artifact_json(preflight, task_id, "generation.json", generation_record)
        generation_written = True

        def note_consumed(value: int) -> None:
            nonlocal last_consumed
            last_consumed = value
            if value > preflight.cost_per_candidate or prior_consumed + value > preflight.approved_credits:
                raise _TaskFailure("Meshy actual credit consumption exceeded the approved bound", value)

        response = _poll_until_succeeded(client, preflight, task_id, note_consumed)
        if response.get("task_id") != task_id or response.get("status") != "SUCCEEDED":
            raise _TaskFailure("Meshy success response identity/status mismatch", last_consumed)
        consumed = response.get("consumed_credits")
        if not isinstance(consumed, int) or isinstance(consumed, bool) or consumed < 0:
            raise _TaskFailure("Meshy success response did not contain consumed_credits", last_consumed)
        if consumed > preflight.cost_per_candidate or prior_consumed + consumed > preflight.approved_credits:
            raise _TaskFailure("Meshy actual credit consumption exceeded the approved bound", consumed)
        model_urls = response.get("model_urls")
        glb_url = model_urls.get("glb") if isinstance(model_urls, dict) else None
        thumbnail_url = response.get("thumbnail_url")
        if not isinstance(glb_url, str) or not isinstance(thumbnail_url, str):
            raise _TaskFailure("Meshy success response did not contain required output URLs", consumed)
        try:
            MeshyClient._validate_download_url(glb_url)
            MeshyClient._validate_download_url(thumbnail_url)
        except RuntimeError as exc:
            raise _TaskFailure(_safe_error(exc), consumed)
        _check_deadline(preflight)
        temp_dir = Path(tempfile.mkdtemp(prefix=".download-", dir=str(task_dir)))
        try:
            _download_with_limit(client, glb_url, temp_dir / "raw.glb", _GLB_MAX_BYTES, preflight)
            _check_deadline(preflight)
            _download_with_limit(client, thumbnail_url, temp_dir / "thumbnail.png", _THUMBNAIL_MAX_BYTES, preflight)
            glb = _read_download(temp_dir / "raw.glb", "raw.glb", _GLB_MAX_BYTES, preflight)
            thumbnail = _read_download(temp_dir / "thumbnail.png", "thumbnail.png", _THUMBNAIL_MAX_BYTES, preflight)
            if len(glb) <= 4 or not glb.startswith(b"glTF"):
                raise _TaskFailure("raw.glb has an invalid GLB signature", consumed)
            if not thumbnail.startswith(_PNG_SIGNATURE):
                raise _TaskFailure("thumbnail.png has an invalid PNG signature", consumed)
            if len(glb) + len(thumbnail) > _DOWNLOAD_TOTAL_MAX_BYTES:
                raise _TaskFailure("Meshy downloads exceed aggregate size", consumed)
            governance.atomic_write_bytes(_artifact_path(preflight, task_id, "raw.glb"), glb, project_root=preflight.root, allowed_root=preflight.asset_root)
            governance.atomic_write_bytes(_artifact_path(preflight, task_id, "thumbnail.png"), thumbnail, project_root=preflight.root, allowed_root=preflight.asset_root)
        finally:
            for child in sorted(temp_dir.iterdir()) if temp_dir.exists() else []:
                try:
                    child.unlink()
                except OSError:
                    pass
            try:
                temp_dir.rmdir()
            except OSError:
                pass
        generation_record.update({"status": "SUCCEEDED", "completed_at": _utc_timestamp(), "consumed_credits": consumed, "outputs": {"raw.glb": {"sha256": hashlib.sha256(glb).hexdigest(), "byte_size": len(glb)}, "thumbnail.png": {"sha256": hashlib.sha256(thumbnail).hexdigest(), "byte_size": len(thumbnail)}}})
        _write_artifact_json(preflight, task_id, "generation.json", generation_record)
        return generation_record
    except BaseException as exc:
        if generation_written:
            failed = dict(generation_record)
            failed["status"] = "FAILED"
            failed["consumed_credits"] = last_consumed
            failed["error"] = _safe_error(exc)
            try:
                _write_artifact_json(preflight, task_id, "generation.json", failed)
            except BaseException:
                pass
        if isinstance(exc, _TaskFailure):
            raise
        raise _TaskFailure(_safe_error(exc), last_consumed)


def _task_entry(index: int, task_id: Optional[str], state: str, consumed: Optional[int], error: Optional[str]) -> Dict[str, Any]:
    return {"index": index, "task_id": task_id, "state": state, "consumed_credits": consumed, "error": error}


def generate_batch(contract: AssetContract, project_root: Path, client: Any, approved_credits: int, *, pricing_file: Optional[Path], reference_root: Path, reference_specs: object, output_license: str, today: object = None, date: object = None, clock: Optional[Callable[[], float]] = None, deadline: object = None) -> Dict[str, Any]:
    if client is None or not all(hasattr(client, name) for name in ("get_balance", "create_task", "poll_task", "download")):
        raise ValueError("a Meshy client is required for generation")
    preflight = _preflight(contract, project_root, client, approved_credits, pricing_file=pricing_file, reference_root=reference_root, reference_specs=reference_specs, output_license=output_license, today=today, date=date, clock=clock, deadline=deadline)
    batch_id = uuid.uuid4().hex
    created_at = _utc_timestamp()
    tasks = [_task_entry(index, None, "PENDING", None, None) for index in range(preflight.candidate_count)]
    journal = _journal_document(preflight, batch_id, "APPROVED", tasks, 0, created_at)
    # This is the first filesystem mutation, and it occurs after every
    # contract/profile/pricing/reference/path/protected/credit preflight.
    _write_journal(preflight, batch_id, journal)
    task_ids: List[str] = []
    cumulative = 0
    for index in range(preflight.candidate_count):
        try:
            _refresh_before_provider(preflight)
        except Exception as exc:
            error = _safe_error(exc)
            tasks[index] = _task_entry(index, None, "FAILED", None, error)
            _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, "FAILED", tasks, cumulative, created_at))
            raise
        tasks[index] = _task_entry(index, None, "SUBMITTING", None, None)
        journal = _journal_document(preflight, batch_id, "SUBMITTING", tasks, cumulative, created_at)
        _write_journal(preflight, batch_id, journal)
        try:
            balance = client.get_balance()
        except Exception as exc:
            error = _safe_error(exc)
            tasks[index] = _task_entry(index, None, "FAILED", None, error)
            _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, "FAILED", tasks, cumulative, created_at))
            raise RuntimeError(error)
        if not isinstance(balance, int) or isinstance(balance, bool) or balance < (preflight.candidate_count - index) * preflight.cost_per_candidate:
            error = "insufficient Meshy balance for remaining reserved maximum"
            tasks[index] = _task_entry(index, None, "FAILED", None, error)
            _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, "FAILED", tasks, cumulative, created_at))
            raise ValueError(error)
        # The balance call is an injectable boundary: a fake can expose a
        # protected-surface change there.  Recheck immediately before POST so
        # no task is created after that change.
        try:
            _refresh_before_provider(preflight)
        except Exception as exc:
            error = _safe_error(exc)
            tasks[index] = _task_entry(index, None, "FAILED", None, error)
            _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, "FAILED", tasks, cumulative, created_at))
            raise
        try:
            task_id = _safe_task_id(client.create_task(preflight.endpoint, preflight.transient.payload))
        except Exception as exc:
            # Keep SUBMITTING: a crash/transport failure after POST may have
            # created an unknown provider task, and R2B2 must reconcile it.
            error = _safe_error(exc)
            tasks[index] = _task_entry(index, None, "SUBMITTING", None, error)
            _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, "SUBMITTING", tasks, cumulative, created_at))
            raise RuntimeError(error)
        if task_id in task_ids:
            error = "Meshy returned a duplicate task id"
            tasks[index] = _task_entry(index, task_id, "FAILED", None, error)
            _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, "FAILED", tasks, cumulative, created_at))
            raise ValueError(error)
        task_ids.append(task_id)
        tasks[index] = _task_entry(index, task_id, "PENDING", None, None)
        _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, "SUBMITTING", tasks, cumulative, created_at))
        try:
            record = _stage_task(client, preflight, task_id, _utc_timestamp(), cumulative)
        except Exception as exc:
            consumed = exc.consumed if isinstance(exc, _TaskFailure) else None
            if consumed is not None:
                cumulative += consumed
            tasks[index] = _task_entry(index, task_id, "FAILED", consumed, _safe_error(exc))
            _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, "FAILED", tasks, cumulative, created_at))
            raise
        consumed = record["consumed_credits"]
        cumulative += consumed
        tasks[index] = _task_entry(index, task_id, "SUCCEEDED", consumed, None)
        state = "COMPLETED" if index + 1 == preflight.candidate_count else "APPROVED"
        _write_journal(preflight, batch_id, _journal_document(preflight, batch_id, state, tasks, cumulative, created_at))
    return {"asset_id": preflight.contract.asset_id, "batch_id": batch_id, "candidate_count": preflight.candidate_count, "maximum_credits": preflight.maximum_credits, "approved_credits": preflight.approved_credits, "consumed_credits": cumulative, "task_ids": task_ids}


def validate_generation_record(document: object) -> List[str]:
    errors: List[str] = []
    if not isinstance(document, dict):
        return ["generation record must be an object"]
    required = {"schema_version", "document_kind", "asset_id", "task_id", "status", "endpoint", "contract_sha256", "prompt_profile_id", "prompt_profile_sha256", "prompt_packet_sha256", "pricing_id", "pricing_sha256", "provider_payload_sha256", "request", "references", "input_image_hashes", "output_license", "created_at", "completed_at", "consumed_credits", "outputs", "provenance", "error"}
    if set(document) - required or set(document) != required:
        errors.append("generation record fields are not exact")
    if document.get("schema_version") != "1.0.0" or document.get("document_kind") != "meshy_generation_record":
        errors.append("generation record kind/version is invalid")
    if not isinstance(document.get("asset_id"), str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", document.get("asset_id", "")):
        errors.append("generation asset_id is invalid")
    if not isinstance(document.get("task_id"), str) or _TASK_ID_RE.fullmatch(document.get("task_id", "")) is None:
        errors.append("generation task_id is invalid")
    if document.get("status") not in ("PENDING", "SUCCEEDED", "FAILED"):
        errors.append("generation status is invalid")
    if document.get("endpoint") not in ENDPOINTS.values():
        errors.append("generation endpoint is invalid")
    for name in ("contract_sha256", "prompt_profile_sha256", "prompt_packet_sha256", "pricing_sha256", "provider_payload_sha256"):
        if not isinstance(document.get(name), str) or _HASH_RE.fullmatch(document.get(name, "")) is None:
            errors.append("generation {0} is invalid".format(name))
    request = document.get("request")
    if isinstance(request, dict):
        expected_request_fields = {"model_type", "ai_model", "target_polycount", "should_texture", "target_formats", "image_url" if document.get("endpoint") == ENDPOINTS["image_to_3d"] else "image_urls"}
        if set(request) != expected_request_fields:
            errors.append("generation request fields are not exact")
        else:
            reference_values = request.get("image_url") if "image_url" in request else request.get("image_urls")
            values = reference_values if isinstance(reference_values, list) else [reference_values]
            for value in values:
                if not isinstance(value, dict) or set(value) != {"view", "basename", "media_type", "byte_size", "sha256"}:
                    errors.append("generation request reference evidence is invalid")
            expected_values = document["references"] if "image_urls" in request else document["references"][:1] if isinstance(document.get("references"), list) else []
            if isinstance(document.get("references"), list) and values != expected_values:
                errors.append("generation request references do not match evidence")
    if document.get("output_license") not in _ALLOWED_LICENSES or not isinstance(request, dict) or not isinstance(document.get("references"), list) or not isinstance(document.get("input_image_hashes"), dict) or not isinstance(document.get("outputs"), dict) or not isinstance(document.get("provenance"), dict):
        errors.append("generation typed fields are invalid")
    provenance = document.get("provenance")
    if isinstance(provenance, dict) and (set(provenance) != {"provider", "model", "license_state"} or provenance.get("provider") != "meshy" or provenance.get("license_state") != document.get("output_license") or not isinstance(provenance.get("model"), str) or not provenance.get("model")):
        errors.append("generation provenance is invalid")
    references = document.get("references")
    if isinstance(references, list):
        reference_views = set()
        for reference in references:
            if not isinstance(reference, dict) or set(reference) != {"view", "basename", "media_type", "byte_size", "sha256"}:
                errors.append("generation reference metadata is invalid")
                continue
            if reference.get("view") in reference_views:
                errors.append("generation references contain duplicate views")
            reference_views.add(reference.get("view"))
            if not isinstance(reference.get("sha256"), str) or _HASH_RE.fullmatch(reference.get("sha256", "")) is None or not isinstance(reference.get("byte_size"), int) or isinstance(reference.get("byte_size"), bool) or reference.get("byte_size") <= 0:
                errors.append("generation reference hash/size is invalid")
    image_hashes = document.get("input_image_hashes")
    if isinstance(image_hashes, dict) and (any(not isinstance(key, str) or not isinstance(value, str) or _HASH_RE.fullmatch(value) is None for key, value in image_hashes.items()) or isinstance(document.get("references"), list) and set(image_hashes) != {item.get("view") for item in document["references"] if isinstance(item, dict)}):
        errors.append("generation input image hashes are invalid")
    outputs = document.get("outputs")
    if isinstance(outputs, dict):
        if set(outputs) - {"raw.glb", "thumbnail.png"}:
            errors.append("generation output names are invalid")
        for output in outputs.values():
            if not isinstance(output, dict) or set(output) != {"sha256", "byte_size"} or not isinstance(output.get("sha256"), str) or _HASH_RE.fullmatch(output.get("sha256", "")) is None or not isinstance(output.get("byte_size"), int) or isinstance(output.get("byte_size"), bool) or output.get("byte_size") <= 0:
                errors.append("generation output evidence is invalid")
    consumed = document.get("consumed_credits")
    if consumed is not None and (not isinstance(consumed, int) or isinstance(consumed, bool) or consumed < 0):
        errors.append("generation consumed_credits is invalid")
    if document.get("status") == "PENDING" and consumed is not None:
        errors.append("pending generation cannot report consumed credits")
    if document.get("status") == "FAILED" and not isinstance(document.get("error"), str):
        errors.append("failed generation must contain an error")
    if document.get("status") == "SUCCEEDED" and document.get("error") is not None:
        errors.append("succeeded generation cannot contain an error")
    if document.get("status") == "SUCCEEDED" and (not isinstance(consumed, int) or document.get("completed_at") is None or set(document.get("outputs", {})) != {"raw.glb", "thumbnail.png"}):
        errors.append("succeeded generation is incomplete")
    if document.get("status") == "PENDING" and document.get("completed_at") is not None:
        errors.append("pending generation cannot be completed")
    def inspect_evidence(value: object) -> None:
        if isinstance(value, float) and not math.isfinite(value):
            errors.append("generation record contains a non-finite number")
        elif isinstance(value, dict):
            for child in value.values():
                inspect_evidence(child)
        elif isinstance(value, list):
            for child in value:
                inspect_evidence(child)
        elif isinstance(value, str) and ("data:" in value or "Authorization" in value or "Bearer " in value or "api_key" in value or "signed-download" in value or "?token=" in value or "?Signature=" in value or "https://" in value or value.startswith("sk-") or (value.startswith("/") and value not in ENDPOINTS.values()) or re.match(r"^[A-Za-z]:[\\/]", value) is not None):
            errors.append("generation record contains forbidden secret or path material")
    inspect_evidence(document)
    if re.search(r"(?:^|[\" ])/(?:Users|private|tmp|var)/", json.dumps(document, ensure_ascii=False, sort_keys=True)):
        errors.append("generation record contains forbidden secret or path material")
    return sorted(set(errors))


def validate_batch_journal(document: object) -> List[str]:
    errors: List[str] = []
    if not isinstance(document, dict):
        return ["batch journal must be an object"]
    required = {"schema_version", "document_kind", "batch_id", "asset_id", "approval", "state", "tasks", "cumulative_consumed_credits"}
    if set(document) != required:
        errors.append("batch journal fields are not exact")
    if document.get("schema_version") != "1.0.0" or document.get("document_kind") != "meshy_batch_journal":
        errors.append("batch journal kind/version is invalid")
    if not isinstance(document.get("batch_id"), str) or _BATCH_ID_RE.fullmatch(document.get("batch_id", "")) is None:
        errors.append("batch_id is invalid")
    if document.get("state") not in ("APPROVED", "SUBMITTING", "COMPLETED", "FAILED"):
        errors.append("batch journal state is invalid")
    approval = document.get("approval")
    if not isinstance(approval, dict):
        errors.append("batch journal approval is invalid")
    else:
        fields = {"contract_sha256", "prompt_profile_id", "prompt_profile_sha256", "prompt_packet_sha256", "pricing_id", "pricing_sha256", "provider_payload_sha256", "request", "references", "endpoint", "candidate_count", "cost_per_candidate", "maximum_credits", "approved_credits", "output_license", "protected_snapshot", "created_at"}
        if set(approval) != fields:
            errors.append("batch journal approval fields are not exact")
        for name in ("contract_sha256", "prompt_profile_sha256", "prompt_packet_sha256", "pricing_sha256", "provider_payload_sha256"):
            if not isinstance(approval.get(name), str) or _HASH_RE.fullmatch(approval.get(name, "")) is None:
                errors.append("batch journal approval hash is invalid")
        for name in ("candidate_count", "cost_per_candidate", "maximum_credits", "approved_credits"):
            if not isinstance(approval.get(name), int) or isinstance(approval.get(name), bool) or approval.get(name) <= 0:
                errors.append("batch journal approval credit field is invalid")
        if all(isinstance(approval.get(name), int) and not isinstance(approval.get(name), bool) for name in ("candidate_count", "cost_per_candidate", "maximum_credits", "approved_credits")):
            if approval["maximum_credits"] != approval["candidate_count"] * approval["cost_per_candidate"] or approval["approved_credits"] < approval["maximum_credits"]:
                errors.append("batch journal approval credit bound is invalid")
        approval_request = approval.get("request")
        expected_request_fields = {"model_type", "ai_model", "target_polycount", "should_texture", "target_formats", "image_url" if approval.get("endpoint") == ENDPOINTS["image_to_3d"] else "image_urls"}
        if not isinstance(approval_request, dict) or set(approval_request) != expected_request_fields:
            errors.append("batch journal approval request fields are not exact")
        elif isinstance(approval.get("references"), list):
            request_value = approval_request.get("image_url") if "image_url" in approval_request else approval_request.get("image_urls")
            request_values = request_value if isinstance(request_value, list) else [request_value]
            expected_values = approval["references"] if "image_urls" in approval_request else approval["references"][:1]
            if request_values != expected_values:
                errors.append("batch journal request references do not match evidence")
        if approval.get("output_license") not in _ALLOWED_LICENSES or approval.get("endpoint") not in ENDPOINTS.values() or not isinstance(approval_request, dict) or not isinstance(approval.get("references"), list) or not isinstance(approval.get("protected_snapshot"), list):
            errors.append("batch journal approval typed field is invalid")
    tasks = document.get("tasks")
    if not isinstance(tasks, list):
        errors.append("batch journal tasks must be a list")
    else:
        indexes = []
        task_ids = set()
        for item in tasks:
            if not isinstance(item, dict) or set(item) != {"index", "task_id", "state", "consumed_credits", "error"}:
                errors.append("batch journal task fields are not exact")
                continue
            if not isinstance(item["index"], int) or isinstance(item["index"], bool) or item["index"] < 0 or item["state"] not in ("PENDING", "SUBMITTING", "SUCCEEDED", "FAILED"):
                errors.append("batch journal task identity/state is invalid")
            indexes.append(item["index"])
            if item["task_id"] is not None and (not isinstance(item["task_id"], str) or _TASK_ID_RE.fullmatch(item["task_id"]) is None):
                errors.append("batch journal task id is invalid")
            if item["task_id"] is not None and item["task_id"] in task_ids:
                errors.append("batch journal contains duplicate task ids")
            if item["task_id"] is not None:
                task_ids.add(item["task_id"])
            if item["consumed_credits"] is not None and (not isinstance(item["consumed_credits"], int) or isinstance(item["consumed_credits"], bool) or item["consumed_credits"] < 0):
                errors.append("batch journal task credits are invalid")
            if item["state"] in ("PENDING", "SUBMITTING") and item["consumed_credits"] is not None:
                errors.append("pending batch task cannot report consumed credits")
            if item["state"] == "FAILED" and not isinstance(item["error"], str):
                errors.append("failed batch task must contain an error")
            if item["state"] != "FAILED" and item["error"] is not None:
                errors.append("non-failed batch task cannot contain an error")
        if indexes != list(range(len(indexes))):
            errors.append("batch journal task indexes are not exact")
        if isinstance(approval, dict) and isinstance(approval.get("candidate_count"), int) and len(tasks) != approval["candidate_count"]:
            errors.append("batch journal task count does not match approval")
    cumulative = document.get("cumulative_consumed_credits")
    if not isinstance(cumulative, int) or isinstance(cumulative, bool) or cumulative < 0:
        errors.append("batch journal cumulative credits are invalid")
    def inspect_journal(value: object) -> None:
        if isinstance(value, float) and not math.isfinite(value):
            errors.append("batch journal contains a non-finite number")
        elif isinstance(value, dict):
            for child in value.values():
                inspect_journal(child)
        elif isinstance(value, list):
            for child in value:
                inspect_journal(child)
        elif isinstance(value, str) and ("data:" in value or "Authorization" in value or "Bearer " in value or "api_key" in value or "signed-download" in value or "?token=" in value or "?Signature=" in value or "https://" in value or value.startswith("sk-") or (value.startswith("/") and value not in ENDPOINTS.values()) or re.match(r"^[A-Za-z]:[\\/]", value) is not None):
            errors.append("batch journal contains forbidden secret material")
    inspect_journal(document)
    return sorted(set(errors))


def load_generation_record(path: Union[str, os.PathLike]) -> Dict[str, Any]:
    """Strictly parse and validate one generated record from disk."""

    document = governance.strict_load_json(path, "Meshy generation record", 4 * 1024 * 1024)
    errors = validate_generation_record(document)
    if errors:
        raise ValueError("invalid Meshy generation record: " + "; ".join(errors))
    if Path(path).name == "generation.json" and Path(path).parent.name != document["task_id"]:
        raise ValueError("Meshy generation filename does not match task_id")
    if document["status"] == "SUCCEEDED":
        task_dir = Path(path).parent
        for name, maximum in (("raw.glb", _GLB_MAX_BYTES), ("thumbnail.png", _THUMBNAIL_MAX_BYTES)):
            artifact = task_dir / name
            try:
                payload = governance._read_bounded_regular_file(artifact, "Meshy " + name, maximum)
            except (OSError, ValueError) as exc:
                raise ValueError("Meshy succeeded artifact is unavailable: " + name) from exc
            if (name == "raw.glb" and (len(payload) <= 4 or not payload.startswith(b"glTF"))) or (name == "thumbnail.png" and not payload.startswith(_PNG_SIGNATURE)):
                raise ValueError("Meshy succeeded artifact signature is invalid: " + name)
            evidence = document["outputs"][name]
            if evidence["byte_size"] != len(payload) or evidence["sha256"] != hashlib.sha256(payload).hexdigest():
                raise ValueError("Meshy succeeded artifact hash/size does not match: " + name)
    return document


def load_batch_journal(path: Union[str, os.PathLike]) -> Dict[str, Any]:
    """Strictly parse and validate one batch journal from disk."""

    document = governance.strict_load_json(path, "Meshy batch journal", 4 * 1024 * 1024)
    errors = validate_batch_journal(document)
    if errors:
        raise ValueError("invalid Meshy batch journal: " + "; ".join(errors))
    if Path(path).suffix == ".json" and Path(path).stem != document["batch_id"]:
        raise ValueError("Meshy batch journal filename does not match batch_id")
    return document


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
    generate.add_argument("--pricing-file", type=Path, default=None, required=False)
    generate.add_argument("--reference-root", type=Path, required=True)
    generate.add_argument("--reference", action="append", required=True, metavar="VIEW=FILENAME")
    generate.add_argument("--output-license", choices=_ALLOWED_LICENSES, required=True)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        contract = load_contract(args.contract)
        if args.command == "plan":
            result = plan_generation(contract, args.project_root, pricing_file=args.pricing_file, reference_root=args.reference_root, reference_specs=args.reference)
        else:
            if args.approved_credits <= 0:
                raise ValueError("approved credit ceiling must be positive")
            result = generate_batch(contract, args.project_root, MeshyClient(), args.approved_credits, pricing_file=args.pricing_file, reference_root=args.reference_root, reference_specs=args.reference, output_license=args.output_license)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        print("error: {0}".format(_safe_error(exc)), file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "DEFAULT_PRICING_PATH", "ENDPOINTS", "MeshyClient", "PricingRecord", "ReferenceInput", "ReferenceInputs", "TransientProviderRequest",
    "build_transient_provider_request", "generate_batch", "load_batch_journal", "load_generation_record", "load_pricing", "plan_generation", "resolve_reference_inputs", "validate_batch_journal", "validate_generation_record",
]
