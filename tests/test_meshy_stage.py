from __future__ import annotations

import base64
import binascii
import dataclasses
import hashlib
import inspect
import json
import os
import pickle
import shutil
import struct
import subprocess
import sys
import threading
import zlib
from pathlib import Path
from typing import Any, Dict, List, Tuple

import pytest

from tools.meshy_asset_contract import (
    AssetContract,
    canonical_json_bytes,
    load_contract,
    render_prompt_packet,
)
from tools import meshy_stage as stage_module
from tools.meshy_stage import (
    PricingRecord,
    ReferenceInput,
    ReferenceInputs,
    TransientProviderRequest,
    build_transient_provider_request,
    generate_batch,
    load_pricing,
    plan_generation,
    resolve_reference_inputs,
)


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "data/asset_generation/contracts/loot_container_derelict_v1.json"
API_FIXTURES = Path(__file__).parent / "fixtures/meshy_api"
IMAGE_ENDPOINT = "/openapi/v1/image-to-3d"
MULTI_IMAGE_ENDPOINT = "/openapi/v1/multi-image-to-3d"
STAGING_RELATIVE = Path("assets/_staging/meshy")
PROTECTED_SURFACES = (
    Path("assets/imported"),
    Path("data/combat"),
    Path("data/props"),
    Path("scenes/wrappers"),
)
TEST_API_KEY = "sk-test-meshy-secret"
SIGNED_DOWNLOAD_TOKEN = "signed-download-token"


def _valid_glb() -> bytes:
    json_chunk = b'{"asset":{"version":"2.0"}}'
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    total = 12 + 8 + len(json_chunk)
    return b"glTF" + struct.pack("<II", 2, total) + struct.pack("<II", len(json_chunk), int.from_bytes(b"JSON", "little")) + json_chunk


class FakeMeshyClient:
    """In-process client double; no network or provider credits are used."""

    def __init__(self) -> None:
        self.calls: List[Tuple[Any, ...]] = []
        self.created_tasks: List[str] = []
        self.balance = 10000
        self._task_counter = 0
        self.task_statuses: Dict[str, str] = {}
        self.poll_task_ids: List[str] = []
        self.api_key = TEST_API_KEY
        self.account_lock_id = "a" * 64

    def get_balance(self) -> int:
        self.calls.append(("get_balance",))
        return self.balance

    def create_task(self, endpoint: str, payload: dict) -> str:
        self.calls.append(("create_task", endpoint, payload))
        self._task_counter += 1
        task_id = "fake-task-{0:04d}".format(self._task_counter)
        self.created_tasks.append(task_id)
        return task_id

    def poll_task(self, endpoint: str, task_id: str) -> dict:
        self.calls.append(("poll_task", endpoint, task_id))
        self.poll_task_ids.append(task_id)
        status = self.task_statuses.get(task_id, "SUCCEEDED")
        if status != "SUCCEEDED":
            return {"status": status, "task_id": task_id}

        fixture_name = (
            "multi_image_to_3d_succeeded.json"
            if endpoint == MULTI_IMAGE_ENDPOINT
            else "image_to_3d_succeeded.json"
        )
        response = json.loads((API_FIXTURES / fixture_name).read_text(encoding="utf-8"))
        response["task_id"] = task_id
        response["consumed_credits"] = 5
        response["model_urls"]["glb"] = (
            "https://assets.meshy.ai/{0}.glb?token={1}".format(
                task_id, SIGNED_DOWNLOAD_TOKEN
            )
        )
        response["thumbnail_url"] = (
            "https://assets.meshy.ai/{0}.png?token={1}".format(
                task_id, SIGNED_DOWNLOAD_TOKEN
            )
        )
        return response

    def download_bytes(self, url: str, max_bytes: int, deadline: float, clock: Any) -> bytes:
        self.calls.append(("download_bytes", url, max_bytes, deadline))
        payload = _valid_glb() if url.endswith(".glb?token=" + SIGNED_DOWNLOAD_TOKEN) else b"\x89PNG\r\n\x1a\nthumbnail"
        assert len(payload) <= max_bytes
        return payload


class AtomicityFakeMeshyClient(FakeMeshyClient):
    def __init__(self, project_root: Path, asset_id: str) -> None:
        super().__init__()
        self.project_root = project_root
        self.asset_id = asset_id
        self.current_task_dir_visible_during_download: List[bool] = []

    def download_bytes(self, url: str, max_bytes: int, deadline: float, clock: Any) -> bytes:
        task_id = next(task_id for task_id in self.created_tasks if task_id in url)
        final_task_dir = self.project_root / STAGING_RELATIVE / self.asset_id / task_id
        self.current_task_dir_visible_during_download.append(final_task_dir.exists())
        return super().download_bytes(url, max_bytes, deadline, clock)


@pytest.fixture
def valid_contract() -> AssetContract:
    return load_contract(CONTRACT_PATH)


@pytest.fixture
def fake_client() -> FakeMeshyClient:
    return FakeMeshyClient()


def _stage_asset_root(project_root: Path, asset_id: str) -> Path:
    return project_root / STAGING_RELATIVE / asset_id


def _generation_paths(project_root: Path, asset_id: str) -> List[Path]:
    return sorted(_stage_asset_root(project_root, asset_id).glob("*/generation.json"))


def _generation_kwargs(tmp_path: Path) -> Dict[str, Any]:
    reference_root = tmp_path / "references"
    reference_root.mkdir()
    return {
        "pricing_file": None,
        "reference_root": reference_root,
        "reference_specs": _write_reference_set(reference_root),
        "output_license": "paid-private",
        "today": "2026-09-01",
    }


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _assert_protected_surfaces_are_file_free(project_root: Path) -> None:
    for relative in PROTECTED_SURFACES:
        surface = project_root / relative
        if surface.exists():
            assert not any(path.is_file() for path in surface.rglob("*")), relative


def test_plan_mode_writes_nothing_and_calls_no_api(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    result = plan_generation(valid_contract, project_root=tmp_path, client=fake_client)

    assert result["candidate_count"] == 4
    assert fake_client.calls == []
    assert list(tmp_path.rglob("*")) == []


def test_meshy_client_download_bytes_is_sealed_and_closes_response() -> None:
    class Response:
        status_code = 200

        def __init__(self) -> None:
            self.closed = False

        def iter_content(self, chunk_size: int):
            assert chunk_size > 0
            return [b"one", b"", b"two"]

        def close(self) -> None:
            self.closed = True

    class Session:
        def __init__(self) -> None:
            self.response = Response()

        def get(self, url: str, **kwargs: Any) -> Response:
            assert url == "https://assets.meshy.ai/model.glb"
            assert kwargs["stream"] is True
            assert kwargs["timeout"][1] <= 120
            return self.response

    session = Session()
    client = stage_module.MeshyClient(api_key="test", session=session)
    assert not hasattr(client, "download")
    assert client.download_bytes(
        "https://assets.meshy.ai/model.glb", 10, 10.0, lambda: 0.0
    ) == b"onetwo"
    assert session.response.closed


def test_meshy_client_download_bytes_rejects_deadline_and_bounds_chunks() -> None:
    class Session:
        def get(self, *_args: Any, **_kwargs: Any) -> Any:
            raise AssertionError("deadline should be checked before request")

    client = stage_module.MeshyClient(api_key="test", session=Session())
    clock_values = iter((1.0, 3.0))
    with pytest.raises(RuntimeError, match="deadline"):
        client.download_bytes(
            "https://assets.meshy.ai/model.glb", 10, 1.0, lambda: next(clock_values)
        )


@pytest.mark.parametrize(
    "payload",
    [
        b"glTFX",
        b"glTF\x02\x00\x00\x00",
        b"glTF" + struct.pack("<II", 1, 12),
        b"glTF" + struct.pack("<II", 2, 16),
        b"glTF" + struct.pack("<II", 2, 20) + b"\x04\x00\x00\x00JSON{}",
    ],
)
def test_glb_validation_rejects_truncated_invalid_or_misaligned_containers(payload: bytes) -> None:
    with pytest.raises(ValueError, match="GLB|glTF|chunk|length|JSON|version"):
        stage_module._validate_glb(payload)


def test_glb_validation_accepts_tiny_valid_padded_container() -> None:
    stage_module._validate_glb(_valid_glb())


def test_preflight_uses_repository_snapshot_caps(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    calls: List[Dict[str, int]] = []
    real_snapshot = stage_module.governance.snapshot_protected_surfaces

    def capture_snapshot(root: Path, **kwargs: int):
        calls.append(kwargs)
        return real_snapshot(root, **kwargs)

    monkeypatch.setattr(stage_module.governance, "snapshot_protected_surfaces", capture_snapshot)
    generate_batch(valid_contract, tmp_path, fake_client, 100, **_generation_kwargs(tmp_path))
    assert calls
    assert all(call["max_file_bytes"] >= 1024**3 for call in calls)
    assert all(call["max_total_bytes"] >= 4 * 1024**3 for call in calls)
    assert all(call["max_entries"] >= 20_000 for call in calls)
    assert all(call["max_depth"] >= 128 for call in calls)


def test_generate_deadline_is_positive_default_and_cli_exposes_it() -> None:
    assert inspect.signature(generate_batch).parameters["deadline"].default == 1200
    parser = stage_module._build_parser()
    args = parser.parse_args(
        [
            "generate", "--project-root", "/tmp/project", "--contract", "/tmp/contract.json",
            "--approved-credits", "1", "--reference-root", "/tmp/references",
            "--reference", "front=front.png", "--output-license", "paid-private",
        ]
    )
    assert args.deadline_seconds == 1200


def test_polling_is_bounded_at_120_attempts_and_publishes_deadline_failure(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    class Pending(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            self.calls.append(("poll_task", endpoint, task_id))
            self.poll_task_ids.append(task_id)
            return {"task_id": task_id, "status": "PENDING"}

    monkeypatch.setattr(stage_module.time, "sleep", lambda _seconds: None)
    client = Pending()
    with pytest.raises(RuntimeError, match="did not reach SUCCEEDED"):
        generate_batch(valid_contract, tmp_path, client, 100, deadline=1200, **_generation_kwargs(tmp_path))
    assert len(client.poll_task_ids) == 120
    task_dir = _stage_asset_root(tmp_path, valid_contract.asset_id) / client.created_tasks[0]
    assert json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))["status"] == "FAILED"


def test_generate_refuses_when_estimate_exceeds_approved_credits(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    fake_client.balance = 1000

    with pytest.raises(ValueError, match="approved credit ceiling"):
        generate_batch(
            valid_contract,
            project_root=tmp_path,
            client=fake_client,
            approved_credits=1,
            **_generation_kwargs(tmp_path),
        )

    assert fake_client.created_tasks == []


def test_generate_refuses_when_balance_insufficient(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    fake_client.balance = 0

    with pytest.raises(ValueError, match="insufficient"):
        generate_batch(
            valid_contract,
            project_root=tmp_path,
            client=fake_client,
            approved_credits=10000,
            **_generation_kwargs(tmp_path),
        )

    assert fake_client.created_tasks == []


def test_successful_generation_records_immutable_evidence(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generation_kwargs = _generation_kwargs(tmp_path)
    expected_front_hash = _sha256(generation_kwargs["reference_root"] / "front.png")
    expected_front_size = (generation_kwargs["reference_root"] / "front.png").stat().st_size
    generate_batch(
        valid_contract,
        project_root=tmp_path,
        client=fake_client,
        approved_credits=10000,
        **generation_kwargs,
    )

    contract = valid_contract
    records = _generation_paths(tmp_path, contract.asset_id)
    assert len(records) == contract.document["generation"]["candidate_count"]
    expected_request = {
        "model_type": "smart-topology",
        "ai_model": "meshy-t2",
        "target_polycount": 3000,
        "should_texture": False,
        "target_formats": ["glb"],
        "image_url": {
            "view": "front",
            "basename": "front.png",
            "media_type": "image/png",
            "byte_size": expected_front_size,
            "sha256": expected_front_hash,
        },
    }

    for generation_path in records:
        task_dir = generation_path.parent
        generation_bytes = generation_path.read_bytes()
        generation = json.loads(generation_bytes.decode("utf-8"))
        assert generation_bytes == canonical_json_bytes(generation)
        assert generation["request"] == expected_request
        assert generation["contract_sha256"] == contract.sha256
        assert isinstance(generation["prompt_packet_sha256"], str)
        assert len(generation["prompt_packet_sha256"]) == 64
        assert set(generation["input_image_hashes"]) == set(
            valid_contract.document["references"]["required_views"]
        )
        assert all(len(value) == 64 for value in generation["input_image_hashes"].values())
        assert generation["task_id"] == task_dir.name
        assert generation["endpoint"] == IMAGE_ENDPOINT
        assert generation["status"] == "SUCCEEDED"
        assert generation["created_at"]
        assert generation["completed_at"]
        assert generation["consumed_credits"] == 5

        provenance = generation["provenance"]
        assert provenance["provider"] == "meshy"
        assert provenance["model"] == "meshy-t2"
        assert provenance["license_state"] == "paid-private"

        raw_glb = task_dir / "raw.glb"
        thumbnail = task_dir / "thumbnail.png"
        assert raw_glb.is_file()
        assert thumbnail.is_file()
        assert generation["outputs"]["raw.glb"] == {
            "sha256": _sha256(raw_glb),
            "byte_size": raw_glb.stat().st_size,
        }
        assert generation["outputs"]["thumbnail.png"] == {
            "sha256": _sha256(thumbnail),
            "byte_size": thumbnail.stat().st_size,
        }

        for forbidden in (
            TEST_API_KEY,
            "Authorization",
            SIGNED_DOWNLOAD_TOKEN,
            str(Path.home()),
        ):
            assert forbidden.encode("utf-8") not in generation_bytes

    _assert_protected_surfaces_are_file_free(tmp_path)


def test_staging_uses_atomic_temp_directory_rename(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    client = AtomicityFakeMeshyClient(tmp_path, valid_contract.asset_id)

    generate_batch(
        valid_contract,
        project_root=tmp_path,
        client=client,
        approved_credits=10000,
        **_generation_kwargs(tmp_path),
    )

    assert client.current_task_dir_visible_during_download
    assert all(not visible for visible in client.current_task_dir_visible_during_download)
    task_dirs = sorted(path for path in _stage_asset_root(tmp_path, valid_contract.asset_id).iterdir() if path.name != "_batches")
    assert [path.name for path in task_dirs] == client.created_tasks
    assert all(path.is_dir() for path in task_dirs)
    assert all(not path.name.startswith(".") for path in task_dirs)
    assert _stage_asset_root(tmp_path, valid_contract.asset_id).is_dir()


def test_failed_download_publishes_only_failed_complete_record_and_cleans_temp(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class FailingDownload(FakeMeshyClient):
        def download_bytes(self, url: str, max_bytes: int, deadline: float, clock: Any) -> bytes:
            if ".glb?token=" in url:
                raise RuntimeError("download failed")
            return super().download_bytes(url, max_bytes, deadline, clock)

    client = FailingDownload()
    with pytest.raises(RuntimeError, match="download failed"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))

    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    task_dir = asset_root / client.created_tasks[0]
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    assert generation["status"] == "FAILED"
    assert not (task_dir / "raw.glb").exists()
    assert not any(path.name.startswith(".task-") for path in asset_root.iterdir())


def test_resume_is_exposed_for_r2b2(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    result = subprocess.run(
        [sys.executable, "tools/meshy_stage.py", "resume", "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert "existing Meshy task ids" in result.stdout


def test_contract_hash_and_prompt_packet_hash_are_recorded(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(
        valid_contract,
        project_root=tmp_path,
        client=fake_client,
        approved_credits=10000,
        **_generation_kwargs(tmp_path),
    )

    expected_prompt_hash = hashlib.sha256(
        canonical_json_bytes(render_prompt_packet(valid_contract))
    ).hexdigest()
    for generation_path in _generation_paths(tmp_path, valid_contract.asset_id):
        generation = json.loads(generation_path.read_text(encoding="utf-8"))
        assert generation["contract_sha256"] == valid_contract.sha256
        assert generation["prompt_packet_sha256"] == expected_prompt_hash


def test_protected_surfaces_are_never_written(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(
        valid_contract,
        project_root=tmp_path,
        client=fake_client,
        approved_credits=10000,
        **_generation_kwargs(tmp_path),
    )

    _assert_protected_surfaces_are_file_free(tmp_path)


def test_cli_plan_subcommand_prints_plan_without_side_effects(tmp_path: Path) -> None:
    result = subprocess.run(
        [
            sys.executable,
            "tools/meshy_stage.py",
            "plan",
            "--project-root",
            str(tmp_path),
            "--contract",
            str(CONTRACT_PATH),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "candidate_count" in result.stdout
    assert IMAGE_ENDPOINT in result.stdout
    assert "model_type" in result.stdout
    assert "target_polycount" in result.stdout
    assert not (tmp_path / STAGING_RELATIVE).exists()


def test_cli_generate_subcommand_requires_approved_credits(tmp_path: Path) -> None:
    command = [
        sys.executable,
        "tools/meshy_stage.py",
        "generate",
        "--project-root",
        str(tmp_path),
        "--contract",
        str(CONTRACT_PATH),
    ]
    missing = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    zero = subprocess.run(
        command + ["--approved-credits", "0"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert missing.returncode != 0
    assert zero.returncode != 0
    assert not (tmp_path / STAGING_RELATIVE).exists()


def test_cli_generate_accepts_pricing_and_reference_flags(tmp_path: Path) -> None:
    reference_root = tmp_path / "references"
    reference_root.mkdir()
    names = _write_reference_set(reference_root)
    command = [
        sys.executable,
        "tools/meshy_stage.py",
        "generate",
        "--project-root",
        str(tmp_path),
        "--contract",
        str(CONTRACT_PATH),
        "--approved-credits",
        "20",
        "--reference-root",
        str(reference_root),
        "--output-license",
        "paid-private",
    ]
    for view, name in names.items():
        command.extend(["--reference", view + "=" + name])
    result = subprocess.run(command + ["--pricing-file", "/does/not/exist"], cwd=ROOT, capture_output=True, text=True, check=False)
    assert result.returncode != 0
    assert "unrecognized arguments" not in result.stderr
    assert not (tmp_path / STAGING_RELATIVE).exists()

def _valid_png_bytes(tag: int = 0) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)
        )

    raw = bytes((0, tag & 0xFF, (tag >> 8) & 0xFF, (tag >> 16) & 0xFF, 255))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def _valid_jpeg_bytes(tag: int = 0) -> bytes:
    body = bytes.fromhex(
        "ffd8ffe000104a46494600010100000100010000"
        "ffdb004300080606070605080707070909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c"
        "20242e2720222c231c1c2837292c30313434341f27393d38323c2e333432"
        "ffc0000b080001000101011100"
        "ffc40014100100000000000000000000000000000000"
        "ffda0008010100003f00fb"
        "ffd9"
    )
    comment = struct.pack(">H", tag & 0xFFFF)
    return b"\xff\xd8" + b"\xff\xfe" + struct.pack(">H", 4) + comment + body[2:]


def _write_reference_set(root: Path, suffix: str = ".png") -> dict[str, str]:
    names = {
        "front": "front" + suffix,
        "side": "side" + suffix,
        "back": "back" + suffix,
        "three_quarter": "three-quarter" + suffix,
    }
    writer = _valid_jpeg_bytes if suffix.lower() in (".jpg", ".jpeg") else _valid_png_bytes
    for index, name in enumerate(names.values()):
        (root / name).write_bytes(writer(index + 1))
    return names


def test_reference_inputs_are_ordered_hashed_and_basename_only(tmp_path: Path, valid_contract: AssetContract) -> None:
    names = _write_reference_set(tmp_path)
    resolved = resolve_reference_inputs(valid_contract, tmp_path, names)

    assert [item.view for item in resolved.references] == ["front", "side", "back", "three_quarter"]
    assert [item.basename for item in resolved.references] == list(names.values())
    assert all(item.media_type == "image/png" for item in resolved.references)
    assert all(len(item.sha256) == 64 for item in resolved.references)
    with pytest.raises(ValueError, match="basename|slash"):
        resolve_reference_inputs(valid_contract, tmp_path, {**names, "front": "nested/front.png"})


def test_reference_inputs_reject_duplicate_basenames(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = {view: "same.png" for view in valid_contract.document["references"]["required_views"]}
    (tmp_path / "same.png").write_bytes(_valid_png_bytes(1))

    with pytest.raises(ValueError, match="duplicate.*basename"):
        resolve_reference_inputs(valid_contract, tmp_path, names)


def test_reference_inputs_reject_duplicate_content_and_file_identity(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = _write_reference_set(tmp_path)
    shared = _valid_png_bytes(99)
    (tmp_path / names["front"]).write_bytes(shared)
    (tmp_path / names["side"]).write_bytes(shared)
    with pytest.raises(ValueError, match="duplicate.*(content|sha|file)"):
        resolve_reference_inputs(valid_contract, tmp_path, names)

    names = _write_reference_set(tmp_path)
    (tmp_path / names["side"]).unlink()
    os.link(str(tmp_path / names["front"]), str(tmp_path / names["side"]))
    with pytest.raises(ValueError, match="duplicate.*(content|sha|file)"):
        resolve_reference_inputs(valid_contract, tmp_path, names)


def test_transient_builder_rejects_fabricated_reference_hash(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = _write_reference_set(tmp_path)
    resolved = resolve_reference_inputs(valid_contract, tmp_path, names)
    first = resolved[0]
    forged = ReferenceInput(
        view=first.view,
        basename=first.basename,
        media_type=first.media_type,
        byte_size=first.byte_size,
        sha256="0" * 64,
        _bytes=first._bytes,
    )
    fabricated = ReferenceInputs((forged,) + tuple(resolved.references[1:]))

    with pytest.raises(ValueError, match="sha256|hash"):
        build_transient_provider_request(valid_contract, fabricated)


def test_multi_image_provider_requires_front_as_first_view(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    document = _multi_image_contract(tmp_path, valid_contract).document
    document["references"]["required_views"] = ["side", "front", "back", "three_quarter"]
    path = tmp_path / "side-first-contract.json"
    path.write_bytes(canonical_json_bytes(document))
    contract = load_contract(path)

    with pytest.raises(ValueError, match="front"):
        plan_generation(contract, tmp_path, today="2026-09-01")


def test_jpeg_requires_minimal_end_marker(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = _write_reference_set(tmp_path, suffix=".jpg")
    for name in names.values():
        (tmp_path / name).write_bytes(b"\xff\xd8\xff\xe0not-terminated")

    with pytest.raises(ValueError, match="signature"):
        resolve_reference_inputs(valid_contract, tmp_path, names)


def test_reference_inputs_reject_truncated_or_wrapper_only_images(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = _write_reference_set(tmp_path)
    (tmp_path / names["front"]).write_bytes(b"\x89PNG\r\n\x1a\n")
    with pytest.raises(ValueError, match="signature"):
        resolve_reference_inputs(valid_contract, tmp_path, names)

    names = _write_reference_set(tmp_path, suffix=".jpg")
    (tmp_path / names["front"]).write_bytes(bytes((255, 216, 255, 224)) + b"jpeg" + bytes((255, 217)))
    with pytest.raises(ValueError, match="signature"):
        resolve_reference_inputs(valid_contract, tmp_path, names)


def test_pricing_cost_for_has_only_strict_contract_argument(
    valid_contract: AssetContract,
) -> None:
    pricing = load_pricing(today="2026-09-01")

    assert list(inspect.signature(PricingRecord.cost_for).parameters) == ["self", "contract"]
    assert pricing.cost_for(valid_contract) == 5
    with pytest.raises(TypeError):
        pricing.cost_for(valid_contract, texture_state="textured")
    with pytest.raises(TypeError):
        pricing.cost_for("image_to_3d")


def test_pricing_loader_rejects_float_cost_leaf(tmp_path: Path) -> None:
    pricing_document = json.loads(
        (ROOT / "data/asset_generation/meshy_pricing_v1.json").read_text(encoding="utf-8")
    )
    pricing_document["costs"]["image_to_3d"]["smart-topology"]["meshy-t2"]["untextured"] = 5.0
    pricing_path = tmp_path / "float-pricing.json"
    pricing_path.write_bytes(canonical_json_bytes(pricing_document))

    with pytest.raises(ValueError, match="positive integer|exact integer"):
        load_pricing(pricing_path, today="2026-09-01")


def test_secret_bearing_capsules_are_not_serializable_or_path_leaking(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = _write_reference_set(tmp_path)
    resolved = resolve_reference_inputs(valid_contract, tmp_path, names)
    transient = build_transient_provider_request(valid_contract, resolved)
    pricing = load_pricing(today="2026-09-01")

    assert not dataclasses.is_dataclass(ReferenceInput)
    assert not dataclasses.is_dataclass(ReferenceInputs)
    assert not dataclasses.is_dataclass(TransientProviderRequest)
    assert not dataclasses.is_dataclass(PricingRecord)
    assert not hasattr(transient, "provider_payload")
    assert not hasattr(transient, "request")
    assert not hasattr(stage_module, "ResolvedReference")
    assert not hasattr(stage_module, "load_meshy_pricing")
    assert not hasattr(stage_module, "load_pricing_record")
    assert not hasattr(pricing, "path")

    for capsule in (resolved[0], resolved, transient, pricing):
        assert str(tmp_path) not in repr(capsule)
        with pytest.raises(TypeError):
            json.dumps(capsule)
        with pytest.raises(TypeError):
            dataclasses.asdict(capsule)
        with pytest.raises(TypeError):
            pickle.dumps(capsule)


def test_transient_request_hashes_payload_but_redacts_data_uris(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = _write_reference_set(tmp_path)
    resolved = resolve_reference_inputs(valid_contract, tmp_path, names)
    transient = build_transient_provider_request(valid_contract, resolved)

    assert transient.payload["image_url"].startswith("data:image/png;base64,")
    assert transient.provider_payload_sha256 == hashlib.sha256(
        canonical_json_bytes(transient.payload)
    ).hexdigest()
    assert transient.redacted_request["image_url"]["view"] == "front"
    assert "data:image" not in json.dumps(transient.redacted_request)
    assert str(tmp_path) not in json.dumps(transient.redacted_request)


def test_pricing_is_strict_expiring_and_fails_unknown_combinations(
    valid_contract: AssetContract,
) -> None:
    pricing_path = ROOT / "data/asset_generation/meshy_pricing_v1.json"
    pricing = load_pricing(pricing_path, today="2026-09-01")

    assert pricing.cost_for(valid_contract) == 5
    assert pricing.pricing_id == "meshy_api_2026_08_31"
    assert pricing.expires_at == "2026-09-30"
    with pytest.raises(ValueError, match="expired"):
        load_pricing(pricing_path, today="2026-10-01")
    with pytest.raises(TypeError):
        pricing.cost_for("multi_image_to_3d", "standard", "not-a-model", False)


def test_plan_binds_pricing_and_reference_metadata_without_paths_or_data_uris(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = _write_reference_set(tmp_path)
    result = plan_generation(
        valid_contract,
        project_root=tmp_path / "unused-project-root",
        reference_root=tmp_path,
        reference_specs=names,
        today="2026-09-01",
    )

    encoded = json.dumps(result, sort_keys=True)
    assert result["required_views"] == ["front", "side", "back", "three_quarter"]
    assert result["references_resolved"] is True
    assert result["cost_per_candidate"] == 5
    assert result["maximum_credits"] == 20
    assert "estimated_cost_per_candidate" not in result
    assert "estimated_cost" not in result
    assert result["provider_payload_sha256"]
    assert result["resolved_references"][0]["view"] == "front"
    assert "data:image" not in encoded
    assert str(tmp_path) not in encoded


def test_plan_without_references_is_pure_and_reports_redacted_base_request(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    result = plan_generation(valid_contract, tmp_path, client=fake_client, today="2026-09-01")

    assert result["references_resolved"] is False
    assert result["request"]["should_texture"] is False
    assert result["cost_per_candidate"] == 5
    assert result["maximum_credits"] == 20
    assert fake_client.calls == []
    assert list(tmp_path.rglob("*")) == []


def _multi_image_contract(tmp_path: Path, valid_contract: AssetContract) -> AssetContract:
    document = valid_contract.document
    document["generation"].update(
        mode="multi_image_to_3d", model_type="standard", ai_model="meshy-7"
    )
    path = tmp_path / "multi-contract.json"
    path.write_bytes(canonical_json_bytes(document))
    return load_contract(path)


def test_multi_image_request_preserves_contract_order_and_uses_official_cost(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    contract = _multi_image_contract(tmp_path, valid_contract)
    names = _write_reference_set(tmp_path / "refs") if (tmp_path / "refs").mkdir() is None else {}
    resolved = resolve_reference_inputs(contract, tmp_path / "refs", names)
    transient = build_transient_provider_request(contract, resolved)
    pricing = load_pricing(today="2026-09-01")

    assert transient.payload["image_urls"] == [
        "data:image/png;base64," + base64.b64encode(
            (tmp_path / "refs" / name).read_bytes()
        ).decode("ascii")
        for name in names.values()
    ]
    assert [record["view"] for record in transient.redacted_request["image_urls"]] == [
        "front", "side", "back", "three_quarter"
    ]
    assert pricing.cost_for(contract) == 20
    assert transient.provider_payload_sha256 == hashlib.sha256(
        canonical_json_bytes(transient.payload)
    ).hexdigest()


def test_reference_jpeg_magic_extension_and_symlink_fail_closed(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    names = _write_reference_set(tmp_path, suffix=".jpg")
    jpeg_names = dict(names)
    resolved = resolve_reference_inputs(valid_contract, tmp_path, jpeg_names)
    assert all(item.media_type == "image/jpeg" for item in resolved.references)

    (tmp_path / jpeg_names["front"]).write_bytes(b"not-jpeg")
    with pytest.raises(ValueError, match="signature"):
        resolve_reference_inputs(valid_contract, tmp_path, jpeg_names)

    outside = tmp_path / "outside.png"
    outside.write_bytes(bytes((137, 80, 78, 71, 13, 10, 26, 10)) + b"outside")
    link_names = dict(jpeg_names)
    link_names["front"] = "link.png"
    (tmp_path / "link.png").symlink_to(outside)
    with pytest.raises(ValueError, match="symlink"):
        resolve_reference_inputs(valid_contract, tmp_path, link_names)


def test_reference_file_and_aggregate_limits_are_enforced(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    names = _write_reference_set(tmp_path)
    monkeypatch.setattr(stage_module, "_REFERENCE_FILE_MAX_BYTES", 8)
    with pytest.raises(ValueError, match="size|large"):
        resolve_reference_inputs(valid_contract, tmp_path, names)

    names = _write_reference_set(tmp_path)
    monkeypatch.setattr(stage_module, "_REFERENCE_FILE_MAX_BYTES", 100)
    monkeypatch.setattr(stage_module, "_REFERENCE_TOTAL_MAX_BYTES", 16)
    with pytest.raises(ValueError, match="aggregate|maximum"):
        resolve_reference_inputs(valid_contract, tmp_path, names)


def test_staging_paths_use_contract_identifier_regex(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="safe staging identifier"):
        stage_module._validate_staging_paths(tmp_path, "Foo.Bar")
    with pytest.raises(ValueError, match="safe staging identifier"):
        stage_module._validate_staging_paths(tmp_path, "Not_Valid.ID")
    _root, _stage, asset_root = stage_module._validate_staging_paths(tmp_path, "fixture_triangle")
    assert asset_root.name == "fixture_triangle"
    assert asset_root.parent.name == "meshy"


def test_pricing_id_accepts_dated_snapshot_and_rejects_undated(tmp_path: Path) -> None:
    source = json.loads((ROOT / "data/asset_generation/meshy_pricing_v1.json").read_text(encoding="utf-8"))
    source["pricing_id"] = "meshy_api_2026_09_02"
    path = tmp_path / "priced.json"
    path.write_bytes(canonical_json_bytes(source))
    pricing = load_pricing(path, today="2026-09-01")
    assert pricing.pricing_id == "meshy_api_2026_09_02"

    source["pricing_id"] = "meshy_api"
    path.write_bytes(canonical_json_bytes(source))
    with pytest.raises(ValueError, match="pricing"):
        load_pricing(path, today="2026-09-01")


def test_pricing_document_has_exact_closed_fields_and_original_hash() -> None:
    pricing_path = ROOT / "data/asset_generation/meshy_pricing_v1.json"
    raw = pricing_path.read_bytes()
    pricing = load_pricing(pricing_path, today="2026-09-01")
    assert pricing.sha256 == hashlib.sha256(raw).hexdigest()
    assert set(pricing.document) == {
        "schema_version", "document_kind", "pricing_id", "checked_at",
        "expires_at", "source_url", "costs",
    }
    schema = json.loads(
        (ROOT / "data/asset_generation/schemas/meshy_pricing_v1.schema.json").read_text()
    )
    assert schema["additionalProperties"] is False
    assert set(schema["properties"]) == set(pricing.document)


def test_r2b1_journal_exists_before_first_provider_create(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    generation_kwargs = _generation_kwargs(tmp_path)

    class JournalProbe(FakeMeshyClient):
        def create_task(self, endpoint: str, payload: dict) -> str:
            journal_root = _stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches"
            assert list(journal_root.glob("*.json"))
            return super().create_task(endpoint, payload)

    client = JournalProbe()
    result = generate_batch(
        valid_contract,
        tmp_path,
        client,
        100,
        **generation_kwargs,
    )
    assert result["batch_id"]
    journal_path = next((_stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches").glob("*.json"))
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    assert journal["state"] == "COMPLETED"
    assert journal["approval"]["output_license"] == "paid-private"
    assert stage_module.validate_batch_journal(journal) == []


def test_r2b1_publishes_sources_review_and_strict_generation_record(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(valid_contract, tmp_path, fake_client, 100, **_generation_kwargs(tmp_path))
    task_dir = next(path for path in _stage_asset_root(tmp_path, valid_contract.asset_id).iterdir() if path.name != "_batches")
    assert (task_dir / "source_front.png").is_file()
    assert (task_dir / "source_three_quarter.png").is_file()
    review = json.loads((task_dir / "review.json").read_text(encoding="utf-8"))
    assert review == {
        "schema_version": "1.0.0",
        "document_kind": "meshy_candidate_review",
        "asset_id": valid_contract.asset_id,
        "task_id": task_dir.name,
        "state": "pending",
        "decision": "pending",
        "checks": {
            "silhouette_readable": False,
            "proportions_match_contract": False,
            "functional_volume_present": False,
            "movable_parts_separable": False,
            "cleanup_bounded": False,
            "camera_readability": False,
        },
        "rejection_reasons": [],
        "reviewer": "unassigned",
    }
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    assert generation["output_license"] == "paid-private"
    assert stage_module.validate_generation_record(generation) == []


def test_r2b1_failure_keeps_task_identity_and_failed_evidence(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class FailingPoll(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            self.calls.append(("poll_task", endpoint, task_id))
            return {"task_id": task_id, "status": "FAILED"}

    client = FailingPoll()
    with pytest.raises(RuntimeError, match="ended with status FAILED"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    task_id = client.created_tasks[0]
    task_dir = _stage_asset_root(tmp_path, valid_contract.asset_id) / task_id
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    assert generation["status"] == "FAILED"
    assert generation["task_id"] == task_id
    journal = json.loads(next((_stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert journal["tasks"][0]["task_id"] == task_id
    assert journal["tasks"][0]["state"] == "FAILED"


def test_r2b1_stops_after_actual_credit_overrun(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class Overrun(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            return {"task_id": task_id, "status": "SUCCEEDED", "consumed_credits": 6}

    client = Overrun()
    with pytest.raises(RuntimeError, match="credit consumption"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    assert len(client.created_tasks) == 1
    journal = json.loads(next((_stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert journal["state"] == "BUDGET_OVERRUN"
    assert journal["cumulative_consumed_credits"] == 6
    assert journal["tasks"][0]["consumed_credits"] == 6


def test_r2b1_rejects_duplicate_provider_task_ids(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class Duplicate(FakeMeshyClient):
        def create_task(self, endpoint: str, payload: dict) -> str:
            self.calls.append(("create_task", endpoint, payload))
            self.created_tasks.append("same-task")
            return "same-task"

    client = Duplicate()
    with pytest.raises(ValueError, match="duplicate task id"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    assert len(client.created_tasks) == 2
    journal = json.loads(next((_stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert journal["tasks"][1]["task_id"] is None
    assert journal["tasks"][1]["collision_task_id"] == "same-task"
    assert journal["tasks"][1]["state"] == "COLLISION"
    assert stage_module.validate_batch_journal(journal) == []


def test_r2b1_global_credit_lock_serializes_shared_account(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    account = {"balance": 20, "lock": threading.Lock()}
    barrier = threading.Barrier(2)

    class SharedAccount(FakeMeshyClient):
        def get_balance(self) -> int:
            with account["lock"]:
                return account["balance"]

        def create_task(self, endpoint: str, payload: dict) -> str:
            with account["lock"]:
                if account["balance"] < 5:
                    raise RuntimeError("shared balance exhausted")
                account["balance"] -= 5
            return super().create_task(endpoint, payload)

    results = []

    def run() -> None:
        client = SharedAccount()
        barrier.wait(timeout=5)
        try:
            result = generate_batch(
                valid_contract, tmp_path, client, 20, **_generation_kwargs(tmp_path)
            )
            results.append(("ok", result))
        except Exception as exc:
            results.append(("error", exc))

    threads = [threading.Thread(target=run) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=20)
    assert all(not thread.is_alive() for thread in threads)
    assert [result[0] for result in results].count("ok") == 1
    assert [result[0] for result in results].count("error") == 1
    assert account["balance"] == 0


def test_r2b1_generation_loader_binds_all_adjacent_artifacts_and_journal(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(valid_contract, tmp_path, fake_client, 100, **_generation_kwargs(tmp_path))
    task_dir = next(
        path
        for path in _stage_asset_root(tmp_path, valid_contract.asset_id).iterdir()
        if path.name != "_batches"
    )
    generation_path = task_dir / "generation.json"
    journal_path = next((_stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches").glob("*.json"))
    generation = stage_module.load_generation_record(generation_path)
    assert generation["batch_id"] == journal_path.stem
    assert generation["task_index"] == 0
    assert generation["approved_credits"] == 100
    assert generation["contract_artifact_sha256"] == _sha256(task_dir / "contract.json")
    assert generation["pricing_artifact_sha256"] == _sha256(task_dir / "pricing.json")

    for name, payload in (
        ("contract.json", {"asset_id": "tampered"}),
        ("prompt-packet.json", {"prompt_profile_id": "tampered"}),
        ("pricing.json", {"pricing_id": "tampered"}),
        ("source_front.png", b"tampered"),
        ("review.json", {"asset_id": "tampered", "task_id": task_dir.name}),
    ):
        original = (task_dir / name).read_bytes()
        try:
            if isinstance(payload, bytes):
                (task_dir / name).write_bytes(payload)
            else:
                (task_dir / name).write_bytes(canonical_json_bytes(payload))
            with pytest.raises(ValueError, match="bind|match|hash|artifact|review|contract|prompt|pricing|source"):
                stage_module.load_generation_record(generation_path, journal_path=journal_path)
        finally:
            (task_dir / name).write_bytes(original)

    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    journal["tasks"][0]["index"] = 1
    assert stage_module.validate_batch_journal(journal)


def test_r2b1_journal_validator_rejects_forged_state_credit_and_collision_fields(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(valid_contract, tmp_path, fake_client, 100, **_generation_kwargs(tmp_path))
    journal_path = next((_stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches").glob("*.json"))
    journal = json.loads(journal_path.read_text(encoding="utf-8"))

    forged = json.loads(json.dumps(journal))
    forged["tasks"][0]["state"] = "PENDING"
    assert stage_module.validate_batch_journal(forged)

    forged = json.loads(json.dumps(journal))
    forged["cumulative_consumed_credits"] = 999999
    assert stage_module.validate_batch_journal(forged)

    forged = json.loads(json.dumps(journal))
    forged["state"] = "FAILED"
    assert stage_module.validate_batch_journal(forged)

    forged = json.loads(json.dumps(journal))
    forged["tasks"][0]["task_id"] = None
    forged["tasks"][0]["collision_task_id"] = "unknown-provider-task"
    forged["tasks"][0]["state"] = "FAILED"
    forged["tasks"][0]["error"] = "collision"
    assert stage_module.validate_batch_journal(forged)

    leftover = json.loads(json.dumps(journal))
    leftover["tasks"][0]["state"] = "PENDING"
    leftover["tasks"][0]["consumed_credits"] = None
    leftover["tasks"][0]["error"] = None
    leftover["tasks"][0]["budget_violation"] = False
    errors = stage_module.validate_batch_journal(leftover)
    assert any("pending state is inconsistent" in item for item in errors)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("target_polycount", "not-an-int"),
        ("should_texture", True),
        ("target_formats", ["obj"]),
        ("image_url", {"view": "front", "basename": "front.png", "media_type": "image/png", "byte_size": 1, "sha256": "0" * 64, "extra": True}),
    ],
)
def test_r2b1_generation_validator_rejects_forged_request_fields(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract, field: str, value: object
) -> None:
    generate_batch(valid_contract, tmp_path, fake_client, 100, **_generation_kwargs(tmp_path))
    task_dir = next(path for path in _stage_asset_root(tmp_path, valid_contract.asset_id).iterdir() if path.name != "_batches")
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    generation["request"][field] = value
    assert stage_module.validate_generation_record(generation)


def test_r2b1_error_evidence_is_fully_redacted_and_still_valid(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    secret_error = "/Users/christopherwilloughby/private/ref.png data:image/png;base64,QUJD https://provider.invalid/?q=secret Bearer secret"

    class FailingPoll(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            raise RuntimeError(secret_error)

    client = FailingPoll()
    with pytest.raises(RuntimeError):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    task_dir = _stage_asset_root(tmp_path, valid_contract.asset_id) / client.created_tasks[0]
    generation_path = task_dir / "generation.json"
    journal_path = next((_stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches").glob("*.json"))
    generation_bytes = generation_path.read_bytes()
    journal_bytes = journal_path.read_bytes()
    for forbidden in ("/Users/christopherwilloughby", "data:image", "base64,QUJD", "https://", "Bearer secret", "provider.invalid"):
        assert forbidden.encode("utf-8") not in generation_bytes
        assert forbidden.encode("utf-8") not in journal_bytes
    assert stage_module.validate_generation_record(json.loads(generation_bytes)) == []
    assert stage_module.validate_batch_journal(json.loads(journal_bytes)) == []


def test_r2b1_invalid_physical_root_makes_no_provider_or_stage_write(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    project = tmp_path / "project"
    project.mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    (project / "assets").symlink_to(outside, target_is_directory=True)
    client = FakeMeshyClient()
    with pytest.raises(ValueError, match="symlink|staging|root"):
        generate_batch(valid_contract, project, client, 100, **_generation_kwargs(tmp_path))
    assert client.calls == []
    assert not (outside / "_staging").exists()


def test_plan_rejects_partial_reference_group_and_cli_output_is_repeatable(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    with pytest.raises(ValueError, match="supplied together"):
        plan_generation(valid_contract, tmp_path, reference_root=tmp_path, today="2026-09-01")
    command = [
        sys.executable, "tools/meshy_stage.py", "plan", "--project-root", str(tmp_path),
        "--contract", str(CONTRACT_PATH),
    ]
    first = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    second = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    assert first.returncode == second.returncode == 0
    assert first.stdout == second.stdout
    assert "data:" not in first.stdout
    assert str(tmp_path) not in first.stdout
    assert not (tmp_path / STAGING_RELATIVE).exists()


def test_r2b1_budget_overrun_is_truthful_and_explicit(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class Overrun(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            return {"task_id": task_id, "status": "SUCCEEDED", "consumed_credits": 6}

    client = Overrun()
    with pytest.raises(RuntimeError, match="credit consumption"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))

    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    task_dir = asset_root / client.created_tasks[0]
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    journal = json.loads(next((asset_root / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert generation["status"] == "FAILED"
    assert generation["consumed_credits"] == 6
    assert generation["budget_violation"] is True
    assert journal["state"] == "BUDGET_OVERRUN"
    assert journal["tasks"][0]["state"] == "OVERRUN"
    assert journal["tasks"][0]["consumed_credits"] == 6
    assert journal["tasks"][0]["budget_violation"] is True
    assert stage_module.validate_generation_record(generation) == []
    assert stage_module.validate_batch_journal(journal) == []
    assert stage_module.load_generation_record(task_dir / "generation.json") == generation
    assert stage_module.load_batch_journal(next((asset_root / "_batches").glob("*.json"))) == journal


def test_r2b1_failed_poll_preserves_last_observed_consumption(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class FailedAfterObserved(FakeMeshyClient):
        def __init__(self) -> None:
            super().__init__()
            self.poll_count = 0

        def poll_task(self, endpoint: str, task_id: str) -> dict:
            self.poll_count += 1
            if self.poll_count == 1:
                return {"task_id": task_id, "status": "PENDING", "consumed_credits": 5}
            return {"task_id": task_id, "status": "FAILED"}

    client = FailedAfterObserved()
    with pytest.raises(RuntimeError, match="ended with status FAILED"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    task_dir = asset_root / client.created_tasks[0]
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    journal = json.loads(next((asset_root / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert generation["consumed_credits"] == journal["tasks"][0]["consumed_credits"] == 5


@pytest.mark.parametrize("json_document", [{}, {"asset": {"version": "1.0"}}, {"asset": []}])
def test_r2b1_glb_requires_gltf_asset_version_2(json_document: dict) -> None:
    json_chunk = json.dumps(json_document, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    total = 12 + 8 + len(json_chunk)
    payload = b"glTF" + struct.pack("<II", 2, total) + struct.pack("<II", len(json_chunk), int.from_bytes(b"JSON", "little")) + json_chunk
    with pytest.raises(ValueError, match="asset|version"):
        stage_module._validate_glb(payload)


def test_r2b1_publication_uncertainty_preserves_succeeded_generation(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    real_publish = stage_module.governance.atomic_publish_directory

    def publish_then_report_uncertain(*args: Any, **kwargs: Any) -> None:
        real_publish(*args, **kwargs)
        if Path(args[1]).name.startswith("fake-task-"):
            raise stage_module.governance.PublicationUncertainError()

    monkeypatch.setattr(stage_module.governance, "atomic_publish_directory", publish_then_report_uncertain)
    client = FakeMeshyClient()
    with pytest.raises(RuntimeError, match="durability"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    task_dir = asset_root / client.created_tasks[0]
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    journal = json.loads(next((asset_root / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert generation["status"] == "SUCCEEDED"
    assert journal["state"] == "UNCERTAIN"
    assert journal["tasks"][0]["state"] == "UNCERTAIN"
    assert stage_module.load_generation_record(task_dir / "generation.json") == generation


def test_r2b1_static_failure_publishes_journal_only(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    real_write = stage_module._write_artifact_bytes

    def fail_side_source(preflight: Any, task_dir: Path, name: str, payload: bytes) -> None:
        if name == "source_side.png":
            raise RuntimeError("source write failed")
        real_write(preflight, task_dir, name, payload)

    monkeypatch.setattr(stage_module, "_write_artifact_bytes", fail_side_source)
    client = FakeMeshyClient()
    with pytest.raises(RuntimeError):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    assert not (asset_root / client.created_tasks[0]).exists()
    journal = json.loads(next((asset_root / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert journal["tasks"][0]["state"] == "FAILED"
    assert not any(path.name.startswith(".task-") for path in asset_root.iterdir())


def test_r2b1_existing_final_directory_is_a_collision(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class Existing(FakeMeshyClient):
        def create_task(self, endpoint: str, payload: dict) -> str:
            task_id = "existing-task"
            self.created_tasks.append(task_id)
            return task_id

    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    (asset_root / "existing-task").mkdir(parents=True)
    client = Existing()
    with pytest.raises(ValueError, match="collision"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    journal = json.loads(next((asset_root / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert journal["state"] == "FAILED"
    assert journal["tasks"][0]["task_id"] is None
    assert journal["tasks"][0]["collision_task_id"] == "existing-task"
    assert journal["tasks"][0]["state"] == "COLLISION"


def test_r2b1_loader_accepts_valid_mutable_review_state(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(valid_contract, tmp_path, fake_client, 100, **_generation_kwargs(tmp_path))
    task_dir = _stage_asset_root(tmp_path, valid_contract.asset_id) / fake_client.created_tasks[0]
    review = json.loads((task_dir / "review.json").read_text(encoding="utf-8"))
    review.update(
        state="selected",
        decision="accept_for_cleanup",
        checks={field: True for field in review["checks"]},
        reviewer="reviewer",
    )
    (task_dir / "review.json").write_bytes(canonical_json_bytes(review))
    stage_module.load_generation_record(task_dir / "generation.json")


def test_r2b1_decreasing_consumption_is_rejected_as_ambiguous(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class Decreasing(FakeMeshyClient):
        def __init__(self) -> None:
            super().__init__()
            self.poll_count = 0

        def poll_task(self, endpoint: str, task_id: str) -> dict:
            self.poll_count += 1
            return {"task_id": task_id, "status": "PENDING", "consumed_credits": 5 if self.poll_count == 1 else 4}

    client = Decreasing()
    with pytest.raises(RuntimeError, match="ambiguous"):
        generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    task_dir = asset_root / client.created_tasks[0]
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    journal = json.loads(next((asset_root / "_batches").glob("*.json")).read_text(encoding="utf-8"))
    assert generation["consumed_credits"] == journal["tasks"][0]["consumed_credits"] == 5


def test_r2b1_validators_enforce_success_cost_and_overrun_bindings(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(valid_contract, tmp_path, fake_client, 100, **_generation_kwargs(tmp_path))
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    task_dir = asset_root / fake_client.created_tasks[0]
    generation_path = task_dir / "generation.json"
    generation = json.loads(generation_path.read_text(encoding="utf-8"))
    generation["consumed_credits"] = 100
    assert stage_module.validate_generation_record(generation)
    journal_path = next((asset_root / "_batches").glob("*.json"))
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    journal["tasks"][0]["consumed_credits"] = 85
    journal["cumulative_consumed_credits"] = 85
    assert stage_module.validate_batch_journal(journal)

    overrun = dict(generation)
    overrun["status"] = "FAILED"
    overrun["consumed_credits"] = 100
    overrun["completed_at"] = None
    overrun["outputs"] = {}
    overrun["error"] = "Meshy actual credit consumption exceeded the approved bound"
    overrun["budget_violation"] = True
    assert stage_module.validate_generation_record(overrun) == []


def test_r2b2_resume_pending_reuses_existing_task_ids_without_create(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    original = FakeMeshyClient()
    generation_kwargs = _generation_kwargs(tmp_path)
    generated = generate_batch(valid_contract, tmp_path, original, 100, **generation_kwargs)
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    journal_path = asset_root / "_batches" / (generated["batch_id"] + ".json")
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    for task_id in generated["task_ids"]:
        shutil.rmtree(asset_root / task_id)
    for task in journal["tasks"]:
        task.update(state="PENDING", consumed_credits=None, error=None, budget_violation=False)
    journal["state"] = "SUBMITTING"
    journal["cumulative_consumed_credits"] = 0
    journal_path.write_bytes(canonical_json_bytes(journal))

    class NoCreate(FakeMeshyClient):
        def create_task(self, endpoint: str, payload: dict) -> str:
            raise AssertionError("resume must never create a provider task")

    client = NoCreate()
    client.balance = 0
    resumed = stage_module.resume_batch(
        valid_contract,
        tmp_path,
        client,
        journal_path,
        100,
        **generation_kwargs,
    )

    assert resumed["state"] == "COMPLETED"
    assert resumed["resumed"] == generated["task_ids"]
    assert resumed["unresolved"] == []
    assert json.loads(journal_path.read_text(encoding="utf-8"))["state"] == "COMPLETED"


def test_r2b2_verify_batch_is_offline_and_reports_completed_without_client(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    generation_kwargs = _generation_kwargs(tmp_path)
    generated = generate_batch(
        valid_contract, tmp_path, FakeMeshyClient(), 100, **generation_kwargs
    )
    journal_path = _stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches" / (generated["batch_id"] + ".json")

    report = stage_module.verify_batch(tmp_path, valid_contract, journal_path)

    assert report["pass"] is True
    assert report["terminal_state"] == "COMPLETED"
    assert report["unresolved"] == []
    assert report["errors"] == []
    assert set(report["verified_ids"]) == set(generated["task_ids"])


def test_r2b2_cli_exposes_resume_and_offline_verify_help() -> None:
    parser = stage_module._build_parser()
    resume = parser.parse_args([
        "resume", "--project-root", "/tmp/project", "--contract", "/tmp/contract.json",
        "--batch-journal", "/tmp/batch.json", "--approved-credits", "20",
        "--reference-root", "/tmp/references", "--reference", "front=front.png",
        "--output-license", "paid-private",
    ])
    verify = parser.parse_args([
        "verify", "--project-root", "/tmp/project", "--contract", "/tmp/contract.json",
        "--batch-journal", "/tmp/batch.json",
    ])
    assert resume.command == "resume"
    assert verify.command == "verify"


def test_r2b2_resume_completed_batch_skips_without_poll_or_create(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    generation_kwargs = _generation_kwargs(tmp_path)
    generated = generate_batch(
        valid_contract, tmp_path, FakeMeshyClient(), 100, **generation_kwargs
    )
    client = FakeMeshyClient()

    result = stage_module.resume_batch(
        valid_contract,
        tmp_path,
        client,
        _stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches" / (generated["batch_id"] + ".json"),
        100,
        **generation_kwargs,
    )

    assert result["pass"] is True
    assert result["resumed"] == []
    assert result["skipped"] == generated["task_ids"]
    assert client.poll_task_ids == []
    assert client.created_tasks == []


def test_r2b2_resume_reports_null_submitting_as_unresolved_submission(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class CrashAfterPost(FakeMeshyClient):
        def create_task(self, endpoint: str, payload: dict) -> str:
            self.calls.append(("create_task", endpoint, payload))
            raise RuntimeError("transport crashed after POST")

    generation_kwargs = _generation_kwargs(tmp_path)
    with pytest.raises(RuntimeError):
        generate_batch(valid_contract, tmp_path, CrashAfterPost(), 100, **generation_kwargs)
    journal_path = next((_stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches").glob("*.json"))

    client = FakeMeshyClient()
    result = stage_module.resume_batch(
        valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
    )

    assert result["pass"] is False
    assert result["unresolved_submission"]
    assert result["unresolved_submission"][0]["reason"] == "unresolved_submission"
    assert client.poll_task_ids == []
    assert client.created_tasks == []


def test_r2b2_resume_reconciles_uncertain_succeeded_generation(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    generation_kwargs = _generation_kwargs(tmp_path)
    generated = generate_batch(
        valid_contract, tmp_path, FakeMeshyClient(), 100, **generation_kwargs
    )
    journal_path = _stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches" / (generated["batch_id"] + ".json")
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    journal["state"] = "UNCERTAIN"
    journal["tasks"][0].update(state="UNCERTAIN", error="Meshy task publication durability is uncertain")
    journal_path.write_bytes(canonical_json_bytes(journal))

    result = stage_module.resume_batch(
        valid_contract, tmp_path, FakeMeshyClient(), journal_path, 100, **generation_kwargs
    )

    assert result["pass"] is True
    assert result["reconciled"] == [generated["task_ids"][0]]
    assert json.loads(journal_path.read_text(encoding="utf-8"))["state"] == "COMPLETED"


def test_r2b2_offline_verify_rejects_orphan_task_directory(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    generation_kwargs = _generation_kwargs(tmp_path)
    generated = generate_batch(
        valid_contract, tmp_path, FakeMeshyClient(), 100, **generation_kwargs
    )
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    (asset_root / "orphan-provider-task").mkdir()
    journal_path = asset_root / "_batches" / (generated["batch_id"] + ".json")

    report = stage_module.verify_batch(tmp_path, valid_contract, journal_path)

    assert report["pass"] is False
    assert report["unresolved"] == []
    assert any("not named" in error for error in report["errors"])


def test_r2b2_cli_verify_is_offline_and_emits_pass_marker(
    tmp_path: Path, valid_contract: AssetContract, capsys: pytest.CaptureFixture[str]
) -> None:
    generation_kwargs = _generation_kwargs(tmp_path)
    generated = generate_batch(
        valid_contract, tmp_path, FakeMeshyClient(), 100, **generation_kwargs
    )
    journal_path = _stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches" / (generated["batch_id"] + ".json")

    result = stage_module.main([
        "verify", "--project-root", str(tmp_path), "--contract", str(valid_contract.path),
        "--batch-journal", str(journal_path),
    ])

    captured = capsys.readouterr()
    assert result == 0
    assert "MESHY VERIFY PASS" in captured.out


def test_meshy_client_retries_only_safe_gets(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(stage_module.time, "sleep", lambda _seconds: None)

    class Response:
        def __init__(self, status: int, payload: dict) -> None:
            self.status_code = status
            self.payload = payload

        def json(self) -> dict:
            return self.payload

    class Session:
        def __init__(self, responses: List[Any]) -> None:
            self.responses = list(responses)
            self.methods: List[str] = []

        def request(self, method: str, *_args: Any, **_kwargs: Any) -> Any:
            self.methods.append(method)
            response = self.responses.pop(0)
            if isinstance(response, BaseException):
                raise response
            return response

    for failure in (OSError("transport"), Response(429, {}), Response(500, {})):
        session = Session([failure, Response(200, {"result": "unexpected-second-attempt"})])
        client = stage_module.MeshyClient(api_key="test", session=session)
        with pytest.raises(RuntimeError):
            client.create_task(IMAGE_ENDPOINT, {})
        assert session.methods == ["POST"]

    session = Session([Response(500, {}), Response(200, {"balance": 17})])
    client = stage_module.MeshyClient(api_key="test", session=session)
    assert client.get_balance() == 17
    assert session.methods == ["GET", "GET"]


def test_r2b2_resume_reconciles_published_task_after_journal_write_failure(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    real_write = stage_module._write_journal
    armed = True

    def fail_after_publication(preflight: Any, batch_id: str, document: dict) -> None:
        nonlocal armed
        if armed and document["tasks"][0]["state"] == "SUCCEEDED":
            armed = False
            raise OSError("injected journal write failure")
        real_write(preflight, batch_id, document)

    monkeypatch.setattr(stage_module, "_write_journal", fail_after_publication)
    generation_kwargs = _generation_kwargs(tmp_path)
    original = FakeMeshyClient()
    with pytest.raises(OSError, match="journal write"):
        generate_batch(valid_contract, tmp_path, original, 100, **generation_kwargs)

    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    journal_path = next((asset_root / "_batches").glob("*.json"))
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    task_id = original.created_tasks[0]
    assert journal["tasks"][0]["state"] == "PENDING"
    assert journal["tasks"][0]["task_id"] == task_id
    assert (asset_root / task_id / "generation.json").is_file()

    class NoProviderCalls(FakeMeshyClient):
        def get_balance(self) -> int:
            raise AssertionError("bound terminal evidence must not call the provider")

        def poll_task(self, endpoint: str, task_id: str) -> dict:
            raise AssertionError("bound terminal evidence must not poll")

        def download_bytes(self, url: str, max_bytes: int, deadline: float, clock: Any) -> bytes:
            raise AssertionError("bound terminal evidence must not download")

    client = NoProviderCalls()
    resumed = stage_module.resume_batch(
        valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
    )

    assert resumed["reconciled"] == [task_id]
    assert resumed["state"] == "SUBMITTING"
    assert resumed["errors"] == []
    assert client.calls == []
    reconciled = json.loads(journal_path.read_text(encoding="utf-8"))["tasks"][0]
    assert reconciled["state"] == "SUCCEEDED"
    assert reconciled["consumed_credits"] == 5


@pytest.mark.parametrize("terminal_state", ["FAILED", "OVERRUN"])
def test_r2b2_resume_reconciles_bound_terminal_failure_semantics(
    tmp_path: Path, valid_contract: AssetContract, terminal_state: str
) -> None:
    class Terminal(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            if terminal_state == "FAILED":
                return {"task_id": task_id, "status": "FAILED"}
            return {"task_id": task_id, "status": "SUCCEEDED", "consumed_credits": 6}

    generation_kwargs = _generation_kwargs(tmp_path)
    client = Terminal()
    with pytest.raises(RuntimeError):
        generate_batch(valid_contract, tmp_path, client, 100, **generation_kwargs)

    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    journal_path = next((asset_root / "_batches").glob("*.json"))
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    task_id = client.created_tasks[0]
    journal["tasks"][0].update(
        state="PENDING", consumed_credits=None, error=None, budget_violation=False
    )
    journal["state"] = "SUBMITTING"
    journal["cumulative_consumed_credits"] = 0
    journal_path.write_bytes(canonical_json_bytes(journal))

    class NoProviderCalls(FakeMeshyClient):
        def get_balance(self) -> int:
            raise AssertionError("bound terminal evidence must not call the provider")

        def poll_task(self, endpoint: str, task_id: str) -> dict:
            raise AssertionError("bound terminal evidence must not poll")

        def download_bytes(self, url: str, max_bytes: int, deadline: float, clock: Any) -> bytes:
            raise AssertionError("bound terminal evidence must not download")

    resumed = stage_module.resume_batch(
        valid_contract,
        tmp_path,
        NoProviderCalls(),
        journal_path,
        100,
        **generation_kwargs,
    )
    final_journal = json.loads(journal_path.read_text(encoding="utf-8"))
    final_task = final_journal["tasks"][0]
    assert resumed["reconciled"] == [task_id]
    assert resumed["errors"] == []
    assert final_task["state"] == terminal_state
    assert final_task["budget_violation"] is (terminal_state == "OVERRUN")
    assert final_journal["state"] == ("BUDGET_OVERRUN" if terminal_state == "OVERRUN" else "FAILED")


def test_r2b2_resume_maps_explicit_macos_alias_journal_path(
    tmp_path: Path, valid_contract: AssetContract, fake_client: FakeMeshyClient
) -> None:
    physical = tmp_path.resolve()
    if len(physical.parts) < 3 or physical.parts[1] != "private" or physical.parts[2] not in {"tmp", "var"}:
        pytest.skip("the macOS /private alias is unavailable")
    alias_root = Path("/") / physical.parts[2] / Path(*physical.parts[3:])
    generated = generate_batch(valid_contract, tmp_path, fake_client, 100, **_generation_kwargs(tmp_path))
    journal_path = _stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches" / (generated["batch_id"] + ".json")
    alias_journal = alias_root / STAGING_RELATIVE / valid_contract.asset_id / "_batches" / journal_path.name

    resolved = stage_module._resume_journal_path(alias_root, valid_contract.asset_id, alias_journal)

    assert resolved[0] == physical
    assert resolved[3] == journal_path


def test_r2b2_offline_verify_rejects_all_hidden_and_symlink_direct_entries(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    generated = generate_batch(
        valid_contract, tmp_path, FakeMeshyClient(), 100, **_generation_kwargs(tmp_path)
    )
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    (asset_root / ".task-orphan.tmp").mkdir()
    (asset_root / ".hidden-file").write_text("orphan", encoding="utf-8")
    (asset_root / "symlink-task").symlink_to(asset_root / generated["task_ids"][0], target_is_directory=True)
    journal_path = asset_root / "_batches" / (generated["batch_id"] + ".json")

    report = stage_module.verify_batch(tmp_path, valid_contract, journal_path)

    assert report["pass"] is False
    assert any("hidden" in error for error in report["errors"])
    assert any("symlink" in error for error in report["errors"])


def test_r2b2_offline_verify_requires_the_approved_pricing_source(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    pricing_document = json.loads(
        (ROOT / "data/asset_generation/meshy_pricing_v1.json").read_text(encoding="utf-8")
    )
    custom_pricing = tmp_path / "custom-pricing.json"
    custom_pricing.write_text(json.dumps(pricing_document, indent=2), encoding="utf-8")
    generation_kwargs = _generation_kwargs(tmp_path)
    generation_kwargs["pricing_file"] = custom_pricing
    generated = generate_batch(valid_contract, tmp_path, FakeMeshyClient(), 100, **generation_kwargs)
    journal_path = _stage_asset_root(tmp_path, valid_contract.asset_id) / "_batches" / (generated["batch_id"] + ".json")

    default_report = stage_module.verify_batch(tmp_path, valid_contract, journal_path)
    correct_report = stage_module.verify_batch(
        tmp_path, valid_contract, journal_path, pricing_file=custom_pricing
    )
    wrong_report = stage_module.verify_batch(
        tmp_path, valid_contract, journal_path, pricing_file=stage_module.DEFAULT_PRICING_PATH
    )

    assert default_report["pass"] is False
    assert any("non-default pricing" in error for error in default_report["errors"])
    assert correct_report["pass"] is True
    assert correct_report["errors"] == []
    assert wrong_report["pass"] is False
    assert any("pricing hash" in error for error in wrong_report["errors"])


def test_r2b2_cli_verify_accepts_pricing_file() -> None:
    parser = stage_module._build_parser()
    verify = parser.parse_args([
        "verify", "--project-root", "/tmp/project", "--contract", "/tmp/contract.json",
        "--batch-journal", "/tmp/batch.json", "--pricing-file", "/tmp/custom-pricing.json",
    ])
    assert verify.pricing_file == Path("/tmp/custom-pricing.json")


def _historical_failed_batch(tmp_path: Path, valid_contract: AssetContract) -> Tuple[dict, Path, Path, Dict[str, Any]]:
    generation_kwargs = _generation_kwargs(tmp_path)
    original = FakeMeshyClient()
    generated = generate_batch(valid_contract, tmp_path, original, 100, **generation_kwargs)
    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    journal_path = asset_root / "_batches" / (generated["batch_id"] + ".json")
    task_id = generated["task_ids"][0]
    task_dir = asset_root / task_id
    generation_path = task_dir / "generation.json"
    generation = json.loads(generation_path.read_text(encoding="utf-8"))
    generation.update(
        status="FAILED",
        completed_at=None,
        consumed_credits=5,
        outputs={},
        error="Meshy operation failed",
        budget_violation=False,
    )
    generation_path.write_bytes(canonical_json_bytes(generation))
    for output_name in ("raw.glb", "thumbnail.png"):
        (task_dir / output_name).unlink()
    for suffix_task_id in generated["task_ids"][1:]:
        shutil.rmtree(asset_root / suffix_task_id)
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    journal["state"] = "FAILED"
    journal["cumulative_consumed_credits"] = 5
    journal["tasks"] = [
        {
            "index": 0,
            "task_id": task_id,
            "collision_task_id": None,
            "state": "FAILED",
            "consumed_credits": 5,
            "error": "Meshy operation failed",
            "budget_violation": False,
        }
    ] + [
        {
            "index": index,
            "task_id": None,
            "collision_task_id": None,
            "state": "PENDING",
            "consumed_credits": None,
            "error": None,
            "budget_violation": False,
        }
        for index in range(1, 4)
    ]
    journal_path.write_bytes(canonical_json_bytes(journal))
    return generated, journal_path, task_dir, generation_kwargs


def test_r9_crash_after_outputs_before_cas_is_retryable(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    generated, journal_path, task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    original = stage_module._cas_replace_generation

    def crash(*args: Any, **kwargs: Any) -> None:
        raise RuntimeError("injected after outputs")

    monkeypatch.setattr(stage_module, "_cas_replace_generation", crash)
    with pytest.raises(RuntimeError, match="injected after outputs"):
        stage_module.continue_batch(
            valid_contract, tmp_path, FakeMeshyClient(), journal_path, 100, **generation_kwargs
        )

    assert (task_dir / "raw.glb").is_file()
    assert (task_dir / "thumbnail.png").is_file()
    assert json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))["status"] == "FAILED"
    monkeypatch.setattr(stage_module, "_cas_replace_generation", original)
    retry_client = FakeMeshyClient()
    retry_client._task_counter = 100
    retry = stage_module.continue_batch(
        valid_contract, tmp_path, retry_client, journal_path, 100, **generation_kwargs
    )
    assert retry["state"] == "COMPLETED"
    assert retry["pass"] is True
    assert generated["task_ids"][0] in retry["recovered"]


def test_r9_crash_after_cas_before_journal_update_is_retryable(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    _generated, journal_path, task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    failed_task_id = task_dir.name
    original = stage_module._resume_journal_update
    calls = {"count": 0}

    def crash(preflight: Any, journal: dict, tasks: List[dict], cumulative: int) -> None:
        calls["count"] += 1
        if calls["count"] == 1:
            raise RuntimeError("injected after cas")
        original(preflight, journal, tasks, cumulative)

    monkeypatch.setattr(stage_module, "_resume_journal_update", crash)
    with pytest.raises(RuntimeError, match="injected after cas"):
        stage_module.continue_batch(
            valid_contract, tmp_path, FakeMeshyClient(), journal_path, 100, **generation_kwargs
        )

    assert json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))["status"] == "SUCCEEDED"
    assert json.loads(journal_path.read_text(encoding="utf-8"))["tasks"][0]["state"] == "FAILED"
    generation_after_cas = (task_dir / "generation.json").read_bytes()
    archive_after_cas = (task_dir / "generation.failed.json").read_bytes()

    monkeypatch.setattr(stage_module, "_resume_journal_update", original)
    retry_client = FakeMeshyClient()
    retry_client._task_counter = 100
    retry = stage_module.continue_batch(
        valid_contract, tmp_path, retry_client, journal_path, 100, **generation_kwargs
    )
    assert retry["state"] == "COMPLETED"
    assert retry["pass"] is True
    assert len(retry_client.created_tasks) == 3
    assert failed_task_id not in retry_client.poll_task_ids
    assert not any(
        failed_task_id in repr(call)
        for call in retry_client.calls
        if call[0] in {"poll_task", "download_bytes", "create_task"}
    )
    assert (task_dir / "generation.json").read_bytes() == generation_after_cas
    assert (task_dir / "generation.failed.json").read_bytes() == archive_after_cas


def test_r9_archive_before_outputs_crash_is_retryable(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    _generated, journal_path, task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    original = stage_module._create_artifact_bytes
    armed = {"value": True}

    def crash(preflight: Any, directory: Path, name: str, payload: bytes) -> None:
        if armed["value"] and name == "raw.glb":
            armed["value"] = False
            raise RuntimeError("injected after archive")
        original(preflight, directory, name, payload)

    monkeypatch.setattr(stage_module, "_create_artifact_bytes", crash)
    with pytest.raises(RuntimeError, match="injected after archive"):
        stage_module.continue_batch(
            valid_contract, tmp_path, FakeMeshyClient(), journal_path, 100, **generation_kwargs
        )

    archive = task_dir / "generation.failed.json"
    assert archive.is_file()
    assert archive.stat().st_mode & 0o777 == 0o600
    assert not (task_dir / "raw.glb").exists()
    assert not (task_dir / "thumbnail.png").exists()
    assert json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))["status"] == "FAILED"

    monkeypatch.setattr(stage_module, "_create_artifact_bytes", original)
    retry_client = FakeMeshyClient()
    retry_client._task_counter = 100
    retry = stage_module.continue_batch(
        valid_contract, tmp_path, retry_client, journal_path, 100, **generation_kwargs
    )
    assert retry["state"] == "COMPLETED"
    assert retry["pass"] is True


def test_r9_one_preexisting_matching_output_is_reused(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    _generated, journal_path, task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    raw = _valid_glb()
    (task_dir / "raw.glb").write_bytes(raw)
    os.chmod(task_dir / "raw.glb", 0o600)

    client = FakeMeshyClient()
    client._task_counter = 100
    result = stage_module.continue_batch(
        valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
    )

    assert result["state"] == "COMPLETED"
    assert result["pass"] is True
    assert (task_dir / "raw.glb").read_bytes() == raw
    assert (task_dir / "thumbnail.png").is_file()


def test_r9_recovery_rejects_raw_leaf_appearing_before_exclusive_publish(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    _generated, journal_path, task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    generation_before = (task_dir / "generation.json").read_bytes()
    journal_before = journal_path.read_bytes()
    attacker = b"attacker-owned-raw"
    real_create = stage_module.governance.atomic_create_bytes

    def create_after_raw_appearance(path: Path, payload: bytes, *args: Any, **kwargs: Any) -> None:
        if Path(path).name == "raw.glb":
            Path(path).write_bytes(attacker)
            os.chmod(path, 0o600)
        return real_create(path, payload, *args, **kwargs)

    monkeypatch.setattr(stage_module.governance, "atomic_create_bytes", create_after_raw_appearance)
    with pytest.raises(ValueError, match="appeared|exists|recovery output|output"):
        stage_module.continue_batch(
            valid_contract, tmp_path, FakeMeshyClient(), journal_path, 100, **generation_kwargs
        )

    assert (task_dir / "raw.glb").read_bytes() == attacker
    assert (task_dir / "raw.glb").stat().st_mode & 0o777 == 0o600
    assert (task_dir / "generation.json").read_bytes() == generation_before
    assert journal_path.read_bytes() == journal_before
    assert not (task_dir / "thumbnail.png").exists()


def test_r9_recovery_rejects_failed_archive_appearing_before_exclusive_publish(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    _generated, journal_path, task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    generation_before = (task_dir / "generation.json").read_bytes()
    journal_before = journal_path.read_bytes()
    attacker = b"attacker-owned-archive"
    real_create = stage_module.governance.atomic_create_bytes

    def create_after_archive_appearance(path: Path, payload: bytes, *args: Any, **kwargs: Any) -> None:
        if Path(path).name == "generation.failed.json":
            Path(path).write_bytes(attacker)
            os.chmod(path, 0o600)
        return real_create(path, payload, *args, **kwargs)

    monkeypatch.setattr(stage_module.governance, "atomic_create_bytes", create_after_archive_appearance)
    with pytest.raises(ValueError, match="appeared|exists|generation.failed"):
        stage_module.continue_batch(
            valid_contract, tmp_path, FakeMeshyClient(), journal_path, 100, **generation_kwargs
        )

    archive = task_dir / "generation.failed.json"
    assert archive.read_bytes() == attacker
    assert archive.stat().st_mode & 0o777 == 0o600
    assert (task_dir / "generation.json").read_bytes() == generation_before
    assert journal_path.read_bytes() == journal_before
    assert not (task_dir / "raw.glb").exists()
    assert not (task_dir / "thumbnail.png").exists()


def test_r9_suffix_published_before_journal_update_is_reconciled(
    tmp_path: Path, valid_contract: AssetContract, monkeypatch: pytest.MonkeyPatch
) -> None:
    _generated, journal_path, _failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    original = stage_module._resume_journal_update
    calls = {"count": 0}

    def crash(preflight: Any, journal: dict, tasks: List[dict], cumulative: int) -> None:
        if (
            calls["count"] == 0
            and tasks[1]["state"] == "SUCCEEDED"
            and isinstance(tasks[1].get("task_id"), str)
        ):
            calls["count"] += 1
            raise RuntimeError("injected suffix journal crash")
        original(preflight, journal, tasks, cumulative)

    monkeypatch.setattr(stage_module, "_resume_journal_update", crash)
    first_client = FakeMeshyClient()
    first_client._task_counter = 100
    with pytest.raises(RuntimeError, match="injected suffix journal crash"):
        stage_module.continue_batch(
            valid_contract, tmp_path, first_client, journal_path, 100, **generation_kwargs
        )

    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    suffix_id = journal["tasks"][1]["task_id"]
    assert journal["tasks"][1]["state"] == "PENDING"
    assert isinstance(suffix_id, str)
    assert (task_dir := _stage_asset_root(tmp_path, valid_contract.asset_id) / suffix_id / "generation.json").is_file()
    assert json.loads(task_dir.read_text(encoding="utf-8"))["status"] == "SUCCEEDED"

    monkeypatch.setattr(stage_module, "_resume_journal_update", original)
    retry_client = FakeMeshyClient()
    retry_client._task_counter = 500
    result = stage_module.continue_batch(
        valid_contract, tmp_path, retry_client, journal_path, 100, **generation_kwargs
    )

    assert result["state"] == "COMPLETED"
    assert result["pass"] is True
    assert suffix_id not in retry_client.created_tasks
    assert len(retry_client.created_tasks) == 2
    assert suffix_id not in retry_client.poll_task_ids


def test_r9_pending_persisted_id_without_task_dir_is_staged_without_create(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    _generated, journal_path, _failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    persisted_id = "persisted-task-0001"
    journal["tasks"][1]["task_id"] = persisted_id
    journal_path.write_bytes(canonical_json_bytes(journal))

    class Tracking(FakeMeshyClient):
        def __init__(self) -> None:
            super().__init__()
            self._task_counter = 100

    client = Tracking()
    result = stage_module.continue_batch(
        valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
    )

    assert result["state"] == "COMPLETED"
    assert result["pass"] is True
    assert persisted_id not in client.created_tasks
    assert len(client.created_tasks) == 2
    assert not any(call[0] == "create_task" and persisted_id in call for call in client.calls)
    assert client.poll_task_ids.count(persisted_id) == 1
    final_journal = json.loads(journal_path.read_text(encoding="utf-8"))
    assert final_journal["tasks"][1]["state"] == "SUCCEEDED"
    assert final_journal["tasks"][1]["consumed_credits"] == 5
    assert final_journal["cumulative_consumed_credits"] == 20
    assert (_stage_asset_root(tmp_path, valid_contract.asset_id) / persisted_id / "generation.json").is_file()


@pytest.mark.parametrize("output_case", ["different", "wrong_mode", "symlink", "directory"])
def test_r9_preexisting_output_integrity_failure_is_non_mutating(
    tmp_path: Path, valid_contract: AssetContract, output_case: str
) -> None:
    _generated, journal_path, task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    output = task_dir / "raw.glb"
    if output_case == "different":
        output.write_bytes(b"different-output")
    elif output_case == "wrong_mode":
        output.write_bytes(_valid_glb())
        os.chmod(output, 0o644)
    elif output_case == "symlink":
        target = tmp_path / "raw-target"
        target.write_bytes(_valid_glb())
        output.symlink_to(target)
    else:
        output.mkdir()
    generation_before = (task_dir / "generation.json").read_bytes()
    journal_before = journal_path.read_bytes()
    client = FakeMeshyClient()

    with pytest.raises(ValueError, match="recovery output|output|symlink component|task artifact"):
        stage_module.continue_batch(
            valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
        )

    assert (task_dir / "generation.json").read_bytes() == generation_before
    assert journal_path.read_bytes() == journal_before
    assert not (task_dir / "generation.failed.json").exists()
    if output_case == "directory":
        assert output.is_dir()
    elif output_case == "symlink":
        assert output.is_symlink()
    else:
        assert output.read_bytes() == (_valid_glb() if output_case == "wrong_mode" else b"different-output")
    assert client.created_tasks == []


def test_r9_repeated_completed_continue_is_idempotent(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    _generated, journal_path, _failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    first_client = FakeMeshyClient()
    first_client._task_counter = 100
    first = stage_module.continue_batch(
        valid_contract, tmp_path, first_client, journal_path, 100, **generation_kwargs
    )
    assert first["state"] == "COMPLETED"

    asset_root = _stage_asset_root(tmp_path, valid_contract.asset_id)
    before = tuple(
        (
            path.relative_to(asset_root).as_posix(),
            path.lstat().st_mode & 0o7777,
            path.read_bytes() if path.is_file() and not path.is_symlink() else None,
        )
        for path in sorted(asset_root.rglob("*"))
    )

    class NoProvider(FakeMeshyClient):
        def get_balance(self) -> int:
            raise AssertionError("completed continue must not check balance")

        def poll_task(self, endpoint: str, task_id: str) -> dict:
            raise AssertionError("completed continue must not poll")

        def download_bytes(self, url: str, max_bytes: int, deadline: float, clock: Any) -> bytes:
            raise AssertionError("completed continue must not download")

        def create_task(self, endpoint: str, payload: dict) -> str:
            raise AssertionError("completed continue must not create")

    second_client = NoProvider()
    second = stage_module.continue_batch(
        valid_contract, tmp_path, second_client, journal_path, 100, **generation_kwargs
    )
    after = tuple(
        (
            path.relative_to(asset_root).as_posix(),
            path.lstat().st_mode & 0o7777,
            path.read_bytes() if path.is_file() and not path.is_symlink() else None,
        )
        for path in sorted(asset_root.rglob("*"))
    )
    assert second["state"] == "COMPLETED"
    assert second["pass"] is True
    assert second_client.calls == []
    assert after == before



def _top_level_id_response(response: dict, task_id: str) -> dict:
    normalized = dict(response)
    normalized.pop("task_id", None)
    normalized["id"] = task_id
    return normalized


def test_provider_top_level_id_is_normalized_to_task_id(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    class TopLevelId(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            return _top_level_id_response(super().poll_task(endpoint, task_id), task_id)

    client = TopLevelId()
    result = generate_batch(valid_contract, tmp_path, client, 100, **_generation_kwargs(tmp_path))
    assert result["task_ids"] == client.created_tasks
    assert result["consumed_credits"] == 20


@pytest.mark.parametrize("identity_shape", ["missing", "wrong", "conflicting"])
def test_provider_task_identity_aliases_fail_closed(
    tmp_path: Path, valid_contract: AssetContract, identity_shape: str
) -> None:
    class BadIdentity(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            response = super().poll_task(endpoint, task_id)
            if identity_shape == "missing":
                response.pop("task_id", None)
            elif identity_shape == "wrong":
                response.pop("task_id", None)
                response["id"] = "different-task"
            else:
                response["id"] = "different-task"
            return response

    with pytest.raises(RuntimeError, match="identity"):
        generate_batch(valid_contract, tmp_path, BadIdentity(), 100, **_generation_kwargs(tmp_path))


def test_continue_recovers_failed_task_and_creates_only_contiguous_suffix(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    generated, journal_path, failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)

    class ContinueClient(FakeMeshyClient):
        def __init__(self) -> None:
            super().__init__()
            self._task_counter = 100

        def poll_task(self, endpoint: str, task_id: str) -> dict:
            return _top_level_id_response(super().poll_task(endpoint, task_id), task_id)

    client = ContinueClient()
    result = stage_module.continue_batch(
        valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
    )

    assert result["state"] == "COMPLETED"
    assert result["recovered"] == [generated["task_ids"][0]]
    assert len(client.created_tasks) == 3
    assert generated["task_ids"][0] not in client.created_tasks
    archive = failed_task_dir / "generation.failed.json"
    assert archive.is_file()
    assert archive.stat().st_mode & 0o777 == 0o600
    assert len(list(path for path in _stage_asset_root(tmp_path, valid_contract.asset_id).iterdir() if path.name != "_batches")) == 4
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    assert journal["state"] == "COMPLETED"
    assert [task["state"] for task in journal["tasks"]] == ["SUCCEEDED"] * 4
    assert len({task["task_id"] for task in journal["tasks"]}) == 4
    assert journal["tasks"][0]["consumed_credits"] == 5
    for task in journal["tasks"]:
        task_dir = _stage_asset_root(tmp_path, valid_contract.asset_id) / task["task_id"]
        assert (task_dir / "raw.glb").is_file()
        assert (task_dir / "thumbnail.png").is_file()
        assert stage_module.load_generation_record(task_dir / "generation.json", journal_path=journal_path)["status"] == "SUCCEEDED"


def test_continue_ambiguous_post_is_unresolved_and_never_retried(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    _generated, journal_path, _failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)

    class AmbiguousPost(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            return _top_level_id_response(super().poll_task(endpoint, task_id), task_id)

        def create_task(self, endpoint: str, payload: dict) -> str:
            self.calls.append(("create_task", endpoint, payload))
            raise RuntimeError("transport crashed after POST")

    first_client = AmbiguousPost()
    first = stage_module.continue_batch(
        valid_contract, tmp_path, first_client, journal_path, 100, **generation_kwargs
    )
    assert first["pass"] is False
    assert first["unresolved_submission"][0]["reason"] == "unresolved_submission"
    assert len([call for call in first_client.calls if call[0] == "create_task"]) == 1
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    assert journal["tasks"][1]["state"] == "SUBMITTING"
    assert journal["tasks"][1]["task_id"] is None

    class NoCreate(FakeMeshyClient):
        def create_task(self, endpoint: str, payload: dict) -> str:
            raise AssertionError("ambiguous POST must never be retried")

    second_client = NoCreate()
    second = stage_module.continue_batch(
        valid_contract, tmp_path, second_client, journal_path, 100, **generation_kwargs
    )
    assert second["pass"] is False
    assert second["unresolved_submission"][0]["reason"] == "unresolved_submission"
    assert second_client.created_tasks == []


def test_continue_provider_terminal_failure_stays_manual_without_suffix_creates(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    _generated, journal_path, _failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)

    class TerminalFailure(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            return {"id": task_id, "status": "FAILED"}

        def create_task(self, endpoint: str, payload: dict) -> str:
            raise AssertionError("terminal recovery must not create suffix tasks")

    client = TerminalFailure()
    result = stage_module.continue_batch(
        valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
    )
    assert result["pass"] is False
    assert result["unresolved"][0]["reason"] == "terminal_manual"
    assert client.created_tasks == []
    assert json.loads(journal_path.read_text(encoding="utf-8"))["state"] == "FAILED"


@pytest.mark.parametrize("mutation", ["pending_id", "missing_failed_id"])
def test_continue_rejects_noncontiguous_or_untrusted_missing_ids(
    tmp_path: Path, valid_contract: AssetContract, mutation: str
) -> None:
    _generated, journal_path, _failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    if mutation == "pending_id":
        journal["tasks"][2]["task_id"] = "untrusted-provider-task"
    else:
        journal["tasks"][0]["task_id"] = None
    journal_path.write_bytes(canonical_json_bytes(journal))
    client = FakeMeshyClient()
    with pytest.raises(ValueError, match="suffix|task id|identity"):
        stage_module.continue_batch(
            valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
        )
    assert client.created_tasks == []


@pytest.mark.parametrize("archive_case", ["symlink", "different", "canonical_mismatch", "malformed", "wrong_mode"])
def test_continue_rejects_invalid_failed_archive_without_mutation(
    tmp_path: Path, valid_contract: AssetContract, archive_case: str
) -> None:
    _generated, journal_path, failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    failed_bytes = (failed_task_dir / "generation.json").read_bytes()
    archive = failed_task_dir / "generation.failed.json"
    if archive_case == "symlink":
        target = tmp_path / "archive-target"
        target.write_bytes(failed_bytes)
        archive.symlink_to(target)
    elif archive_case == "different":
        archive.write_bytes(b"different")
    elif archive_case == "canonical_mismatch":
        mismatched = json.loads(failed_bytes.decode("utf-8"))
        mismatched["error"] = "different failed identity"
        archive.write_bytes(canonical_json_bytes(mismatched))
    elif archive_case == "malformed":
        archive.write_bytes(b"not-json")
    else:
        archive.write_bytes(failed_bytes)
        os.chmod(archive, 0o644)
    before_generation = failed_bytes
    client = FakeMeshyClient()
    with pytest.raises(ValueError, match="generation.failed"):
        stage_module.continue_batch(
            valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
        )
    assert (failed_task_dir / "generation.json").read_bytes() == before_generation
    assert not (failed_task_dir / "raw.glb").exists()
    assert not (failed_task_dir / "thumbnail.png").exists()
    assert client.created_tasks == []


def test_continue_cas_rejects_old_record_drift_without_replacing_it(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    _generated, journal_path, failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)

    class Drift(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            response = _top_level_id_response(super().poll_task(endpoint, task_id), task_id)
            path = failed_task_dir / "generation.json"
            drifted = json.loads(path.read_text(encoding="utf-8"))
            drifted["error"] = "operator drift"
            path.write_bytes(canonical_json_bytes(drifted))
            return response

    client = Drift()
    with pytest.raises(ValueError, match="compare|changed|CAS|generation"):
        stage_module.continue_batch(
            valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
        )
    assert not (failed_task_dir / "generation.failed.json").exists()
    assert not (failed_task_dir / "raw.glb").exists()


def test_continue_cas_rejects_ancestor_rebind_without_publishing(
    tmp_path: Path, valid_contract: AssetContract
) -> None:
    _generated, journal_path, failed_task_dir, generation_kwargs = _historical_failed_batch(tmp_path, valid_contract)
    asset_root = failed_task_dir.parent

    class Rebind(FakeMeshyClient):
        def poll_task(self, endpoint: str, task_id: str) -> dict:
            response = _top_level_id_response(super().poll_task(endpoint, task_id), task_id)
            failed_task_dir.rename(asset_root / "moved-task")
            return response

    client = Rebind()
    with pytest.raises(ValueError, match="identity|changed|generation"):
        stage_module.continue_batch(
            valid_contract, tmp_path, client, journal_path, 100, **generation_kwargs
        )
    assert not (failed_task_dir / "generation.failed.json").exists()
    assert not (asset_root / "moved-task" / "raw.glb").exists()


def test_continue_cli_parser_has_resume_identity_flags() -> None:
    parser = stage_module._build_parser()
    args = parser.parse_args([
        "continue", "--project-root", "/tmp/project", "--contract", "/tmp/contract.json",
        "--batch-journal", "/tmp/batch.json", "--approved-credits", "20",
        "--reference-root", "/tmp/references", "--reference", "front=front.png",
        "--output-license", "paid-private", "--deadline-seconds", "10",
    ])
    assert args.command == "continue"
    assert args.batch_journal == Path("/tmp/batch.json")
    assert args.deadline_seconds == 10
