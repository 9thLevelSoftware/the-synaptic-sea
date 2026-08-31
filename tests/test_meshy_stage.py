from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

import pytest

from tools.meshy_asset_contract import (
    AssetContract,
    canonical_json_bytes,
    load_contract,
    render_prompt_packet,
)
from tools.meshy_stage import generate_batch, plan_generation, resume_batch


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
        response["model_urls"]["glb"] = (
            "https://assets.meshy.example/{0}.glb?token={1}".format(
                task_id, SIGNED_DOWNLOAD_TOKEN
            )
        )
        response["thumbnail_url"] = (
            "https://assets.meshy.example/{0}.png?token={1}".format(
                task_id, SIGNED_DOWNLOAD_TOKEN
            )
        )
        return response

    def download(self, url: str, destination: Path) -> None:
        self.calls.append(("download", url, str(destination)))
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(b"fake-glb-data")


class AtomicityFakeMeshyClient(FakeMeshyClient):
    def __init__(self, project_root: Path, asset_id: str) -> None:
        super().__init__()
        self.project_root = project_root
        self.asset_id = asset_id
        self.current_task_dir_visible_during_download: List[bool] = []

    def download(self, url: str, destination: Path) -> None:
        task_id = next(task_id for task_id in self.created_tasks if task_id in url)
        final_task_dir = (
            self.project_root
            / STAGING_RELATIVE
            / self.asset_id
            / task_id
        )
        self.current_task_dir_visible_during_download.append(final_task_dir.exists())
        super().download(url, destination)


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
        )

    assert fake_client.created_tasks == []


def test_successful_generation_records_immutable_evidence(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(
        valid_contract,
        project_root=tmp_path,
        client=fake_client,
        approved_credits=10000,
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
        assert generation["input_image_hashes"] == {}
        assert generation["task_id"] == task_dir.name
        assert generation["endpoint"] == IMAGE_ENDPOINT
        assert generation["status"] == "SUCCEEDED"
        assert generation["created_at"]
        assert generation["completed_at"]
        assert generation["consumed_credits"] == 10

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
    )

    assert client.current_task_dir_visible_during_download
    assert not any(client.current_task_dir_visible_during_download)
    task_dirs = sorted(path for path in _stage_asset_root(tmp_path, valid_contract.asset_id).iterdir())
    assert [path.name for path in task_dirs] == client.created_tasks
    assert all(path.is_dir() for path in task_dirs)
    assert all(not path.name.startswith(".") for path in task_dirs)
    assert _stage_asset_root(tmp_path, valid_contract.asset_id).is_dir()


def test_resume_skips_already_completed_tasks(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(
        valid_contract,
        project_root=tmp_path,
        client=fake_client,
        approved_credits=10000,
    )
    generation_paths = _generation_paths(tmp_path, valid_contract.asset_id)
    assert len(generation_paths) == 4

    pending_paths = generation_paths[2:]
    pending_ids = [path.parent.name for path in pending_paths]
    for generation_path in pending_paths:
        generation = json.loads(generation_path.read_text(encoding="utf-8"))
        generation["status"] = "PENDING"
        generation_path.write_bytes(canonical_json_bytes(generation))
        (generation_path.parent / "raw.glb").unlink()
        (generation_path.parent / "thumbnail.png").unlink()

    original_created_tasks = list(fake_client.created_tasks)
    fake_client.calls.clear()
    fake_client.poll_task_ids.clear()

    resume_batch(
        valid_contract,
        project_root=tmp_path,
        client=fake_client,
    )

    assert fake_client.created_tasks == original_created_tasks
    assert fake_client.poll_task_ids == pending_ids
    assert all(
        generation_path.parent.joinpath("raw.glb").is_file()
        for generation_path in pending_paths
    )
    assert all(
        json.loads(path.read_text(encoding="utf-8"))["status"] == "SUCCEEDED"
        for path in _generation_paths(tmp_path, valid_contract.asset_id)
    )


def test_contract_hash_and_prompt_packet_hash_are_recorded(
    tmp_path: Path, fake_client: FakeMeshyClient, valid_contract: AssetContract
) -> None:
    generate_batch(
        valid_contract,
        project_root=tmp_path,
        client=fake_client,
        approved_credits=10000,
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
