from __future__ import annotations

import hashlib
import json
import os
import signal
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

from tools import focused_nine_ownership_inventory as inventory


ASSET_IDS = (
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


def test_canonical_json_bytes_are_closed_and_repeatable() -> None:
    document = {"z": [2, 1], "a": {"b": True, "a": "x"}}

    first = inventory.canonical_json_bytes(document)
    second = inventory.canonical_json_bytes(document)

    assert first == second
    assert first == b'{"a":{"a":"x","b":true},"z":[2,1]}'
    assert b"\n" not in first


def test_probe_output_requires_exactly_one_canonical_record() -> None:
    record = {"kind": "blend", "objects": []}
    output = "noise\nFOCUSED_NINE_PROBE " + json.dumps(record) + "\n"

    assert inventory.parse_probe_output(output) == record


@pytest.mark.parametrize(
    "output, message",
    [
        ("", "missing probe record"),
        ("FOCUSED_NINE_PROBE {not-json}\n", "malformed probe record"),
        (
            "FOCUSED_NINE_PROBE {}\nFOCUSED_NINE_PROBE {}\n",
            "duplicate probe records",
        ),
    ],
)
def test_probe_output_rejects_malformed_missing_and_duplicate_records(
    output: str, message: str
) -> None:
    with pytest.raises(inventory.InventoryError, match=message):
        inventory.parse_probe_output(output)


def test_live_path_allowlist_rejects_traversal_and_unexpected_asset(tmp_path: Path) -> None:
    source_root = tmp_path / "source"
    expected = source_root / "ship_structural_v0" / "floor_1x1" / "floor_1x1.blend"
    expected.parent.mkdir(parents=True)
    expected.write_bytes(b"blend")

    assert inventory.expected_live_path(source_root, "floor_1x1") == expected
    with pytest.raises(inventory.InventoryError, match="allowlisted"):
        inventory.validate_live_path(
            source_root,
            "floor_1x1",
            source_root / "ship_structural_v0" / "floor_1x1" / "../wall.blend",
        )
    with pytest.raises(inventory.InventoryError, match="unknown asset"):
        inventory.expected_live_path(source_root, "not_an_asset")


def test_regular_source_rejects_symlink_and_hardlink(tmp_path: Path) -> None:
    real = tmp_path / "real.blend"
    real.write_bytes(b"blend")
    symlink = tmp_path / "link.blend"
    try:
        symlink.symlink_to(real)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")

    with pytest.raises(inventory.InventoryError, match="symlink"):
        inventory.snapshot_file(symlink)

    hardlink = tmp_path / "hardlink.blend"
    try:
        os.link(real, hardlink)
    except OSError as exc:
        pytest.skip(f"hardlinks unavailable: {exc}")
    with pytest.raises(inventory.InventoryError, match="hardlink"):
        inventory.snapshot_file(hardlink)


def test_probe_timeout_kills_fresh_process_group(monkeypatch: pytest.MonkeyPatch) -> None:
    killed: list[tuple[int, int]] = []

    class FakeProcess:
        pid = 4242

        def communicate(self, timeout: float):
            raise subprocess.TimeoutExpired(["blender"], timeout)

        def wait(self, timeout: float | None = None):
            return -signal.SIGTERM

    def fake_popen(command, **kwargs):
        assert command[0] == "blender"
        assert kwargs["start_new_session"] is True
        return FakeProcess()

    monkeypatch.setattr(inventory.subprocess, "Popen", fake_popen)
    monkeypatch.setattr(
        inventory.os,
        "killpg",
        lambda pgid, sig: killed.append((pgid, sig)),
    )

    with pytest.raises(inventory.InventoryError, match="timed out"):
        inventory.run_blender_probe("blender", Path("asset.blend"), timeout=0.01)
    assert killed == [(4242, signal.SIGTERM)]


def test_fake_blender_success_is_read_only_and_parsed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    commands: list[list[str]] = []

    class FakeProcess:
        pid = 31337
        returncode = 0

        def communicate(self, timeout: float):
            return 'FOCUSED_NINE_PROBE {"kind":"blend","objects":[]}\n', ""

    def fake_popen(command, **kwargs):
        commands.append(command)
        assert kwargs["start_new_session"] is True
        return FakeProcess()

    monkeypatch.setattr(inventory.subprocess, "Popen", fake_popen)

    result = inventory.run_blender_probe(
        "blender", Path("asset.blend"), asset_id="floor_1x1", timeout=1.0
    )

    assert result["kind"] == "blend"
    assert "--background" in commands[0]
    assert "save_as_mainfile" not in commands[0][-1]


def test_geometry_signature_change_is_mismatch_even_when_name_is_same() -> None:
    canonical = {"name": "FocusedNine_floor_1x1", "geometry_signature": "geo-a"}
    alternate = {"name": "FocusedNine_floor_1x1", "geometry_signature": "geo-b"}

    comparison = inventory.compare_object_signatures(canonical, alternate)

    assert comparison["status"] == "mismatch"
    assert "geometry signature" in comparison["reason"]


def test_ownership_and_material_mismatch_is_not_approved_by_name() -> None:
    canonical = {
        "name": "FocusedNine_pressure_door_1x1",
        "geometry_signature": "same",
        "ownership_ids": {"focused_nine_asset_id": "pressure_door_1x1"},
        "material_signature": "material-a",
    }
    alternate = {
        "name": "FocusedNine_pressure_door_1x1",
        "geometry_signature": "same",
        "ownership_ids": {"focused_nine_asset_id": "different"},
        "material_signature": "material-b",
    }

    comparison = inventory.compare_object_signatures(canonical, alternate)

    assert comparison["status"] == "mismatch"
    assert "ownership" in comparison["reason"]
    assert "material" in comparison["reason"]


def test_before_after_snapshot_detects_mutation(tmp_path: Path) -> None:
    source = tmp_path / "asset.blend"
    source.write_bytes(b"before")
    before = inventory.snapshot_file(source)
    source.write_bytes(b"after")

    with pytest.raises(inventory.InventoryError, match="changed"):
        inventory.assert_snapshot_unchanged({str(source): before})


def test_deterministic_manifest_repeat_has_no_runtime_timestamp() -> None:
    manifest = inventory.build_closed_manifest(
        repository_head="head",
        tool_snapshot={"sha256": "a" * 64, "byte_size": 1, "mtime_ns": 2, "inode": 3},
        blender_info={"version": "Blender 5.2.0", "path": "/opt/blender"},
        material_library={"path": "/materials.blend", "sha256": "b" * 64},
        quarantine={"manifest": None, "archive": None, "entries": []},
        assets=[{"asset_id": asset_id} for asset_id in ASSET_IDS],
    )

    assert inventory.canonical_json_bytes(manifest) == inventory.canonical_json_bytes(manifest)
    assert "generated_at" not in manifest
    assert manifest["status"] == "needs_review"
    assert manifest["summary"]["unowned_count"] == 6
    assert manifest["summary"]["potentially_tainted_count"] == 3


def test_hash_snapshot_contains_canonical_file_identity(tmp_path: Path) -> None:
    source = tmp_path / "asset.blend"
    raw = b"blend"
    source.write_bytes(raw)

    snapshot = inventory.snapshot_file(source)

    assert snapshot["sha256"] == hashlib.sha256(raw).hexdigest()
    assert snapshot["byte_size"] == len(raw)
    assert snapshot["mtime_ns"] == source.stat().st_mtime_ns
    assert snapshot["inode"] == source.stat().st_ino
