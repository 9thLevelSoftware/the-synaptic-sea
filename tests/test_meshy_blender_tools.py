from __future__ import annotations

import hashlib
import json
import os
import shutil
import struct
import subprocess
import time
from pathlib import Path

import pytest

from tools.meshy_asset_contract import load_contract
from tools.meshy_blender_master import (
    BLENDER_PATH,
    build_blender_command,
    derive_master_path,
    reject_protected_output_path,
)
from tools import meshy_blender_master as master_module
from tools import meshy_blender_validate as validate_module
from tools.meshy_blender_validate import (
    BlenderValidationError,
    _parse_glb,
    _resolve_task_inputs,
    build_parser as build_validate_parser,
    check_dimensions,
    check_triangle_budget,
    validate_cleaned_glb,
    write_validation_report,
)
from tools.meshy_blender_master import build_parser as build_master_parser

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/meshy_blender"
CONTRACT_PATH = FIXTURES / "fixture_contract.json"
GLB_PATH = FIXTURES / "fixture_triangle.glb"
MASTER_SCRIPT = ROOT / "tools/meshy_blender_master.py"
ASSET_ID = "fixture_triangle"


@pytest.fixture()
def contract():
    return load_contract(CONTRACT_PATH)


def test_master_derives_correct_blend_path() -> None:
    assert derive_master_path(ASSET_ID) == Path(
        "/Volumes/Untitled/SynapticSeaAssets/meshy/source/"
        "fixture_triangle/fixture_triangle_master.blend"
    )


def test_master_rejects_protected_output_path(tmp_path: Path) -> None:
    protected = tmp_path / "assets/imported" / "fixture_triangle_master.blend"

    with pytest.raises(ValueError, match="protected"):
        reject_protected_output_path(protected, project_root=tmp_path)


def test_master_constructs_blender_command(tmp_path: Path) -> None:
    contract_path = tmp_path / "contract.json"
    task_dir = tmp_path / "task"
    command = build_blender_command(
        project_root=tmp_path,
        contract=contract_path,
        task_dir=task_dir,
        reviewer="operator",
    )

    assert command == [
        BLENDER_PATH,
        "--background",
        "--factory-startup",
        "--python",
        str(MASTER_SCRIPT),
        "--",
        "--project-root",
        str(tmp_path),
        "--contract",
        str(contract_path),
        "--task-dir",
        str(task_dir),
        "--reviewer",
        "operator",
    ]


def test_validate_rejects_missing_glb(contract, tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="does not exist"):
        validate_cleaned_glb(tmp_path / "missing.glb", contract)


def test_validate_rejects_non_glb_file(contract, tmp_path: Path) -> None:
    path = tmp_path / "not-a-glb.glb"
    path.write_bytes(b"not a glb")

    with pytest.raises(ValueError, match="GLB"):
        validate_cleaned_glb(path, contract)


def test_validate_report_has_required_fields(contract, tmp_path: Path) -> None:
    report = validate_cleaned_glb(GLB_PATH, contract)
    persisted = report
    assert {
        "sha256",
        "byte_size",
        "mesh_count",
        "material_names",
        "triangle_count",
        "bounds",
    } <= set(persisted)
    assert persisted["sha256"] == hashlib.sha256(GLB_PATH.read_bytes()).hexdigest()
    assert persisted["byte_size"] == GLB_PATH.stat().st_size
    assert persisted["mesh_count"] == 1
    assert persisted["triangle_count"] == 1
    assert persisted["material_names"] == []
    assert persisted["bounds"]["min"] == [0.0, 0.0, 0.0]
    assert persisted["bounds"]["max"] == [1.0, 1.0, 0.0]
    assert persisted["status"] == "PASS"
    assert persisted["uvs_present"] is True
    assert persisted["blender_reimport_passed"] is False
    with pytest.raises(ValueError, match="task_id|re-import"):
        write_validation_report(tmp_path, tmp_path / "task", persisted)


def test_validate_dimensions_within_tolerance() -> None:
    assert check_dimensions([1.0, 2.0, 3.0], [1.01, 2.0, 3.0], 0.01)
    assert not check_dimensions([1.0, 2.02, 3.0], [1.01, 2.0, 3.0], 0.01)


def test_validate_triangle_budget() -> None:
    assert check_triangle_budget(3, 3)
    assert check_triangle_budget(3, {"min": 1, "max": 3, "scope": "whole_asset"})
    assert not check_triangle_budget(4, 3)


def test_cli_master_requires_all_args() -> None:
    with pytest.raises(SystemExit):
        build_master_parser().parse_args([])


def test_cli_validate_requires_all_args() -> None:
    with pytest.raises(SystemExit):
        build_validate_parser().parse_args([])


def test_r4_fixture_is_padded_and_report_has_canonical_pass_evidence(contract) -> None:
    assert GLB_PATH.stat().st_size % 4 == 0
    report = validate_cleaned_glb(GLB_PATH, contract)
    assert report["schema_version"] == "1.0.0"
    assert report["document_kind"] == "meshy_blender_validation"
    assert report["status"] == "PASS"
    assert report["uvs_present"] is True
    assert report["uv_evidence"]
    assert report["blender_reimport_passed"] is False


def test_master_requires_governed_direct_task(tmp_path: Path) -> None:
    from tools.meshy_blender_master import _request_inputs

    task_dir = tmp_path / "outside-task"
    task_dir.mkdir()
    (task_dir / "raw.glb").write_bytes(GLB_PATH.read_bytes())
    with pytest.raises(ValueError, match="staging|review|generation|task"):
        _request_inputs(tmp_path, CONTRACT_PATH, task_dir, "operator")


def test_validation_report_writer_requires_task_root_and_fixed_leaf(contract, tmp_path: Path) -> None:
    report = validate_cleaned_glb(GLB_PATH, contract)
    with pytest.raises((TypeError, ValueError)):
        write_validation_report(tmp_path, tmp_path / "task", report)


def _fixture_document_and_binary() -> tuple[dict, bytes]:
    parsed = _parse_glb(GLB_PATH.read_bytes())
    return json.loads(json.dumps(parsed.document)), parsed.binary


def _pack_glb(document: dict, binary: bytes = b"") -> bytes:
    json_chunk = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    binary += b"\0" * ((-len(binary)) % 4)
    total = 12 + 8 + len(json_chunk) + (8 + len(binary) if binary else 0)
    result = bytearray(b"glTF" + struct.pack("<II", 2, total))
    result.extend(struct.pack("<II", len(json_chunk), int.from_bytes(b"JSON", "little")))
    result.extend(json_chunk)
    if binary:
        result.extend(struct.pack("<II", len(binary), int.from_bytes(b"BIN\0", "little")))
        result.extend(binary)
    return bytes(result)


def _bound_fixture_task(tmp_path: Path):
    from tests.test_meshy_candidate_review import (
        _ReviewFakeMeshyClient,
        _true_checks,
        _write_review_references,
    )
    from tools.meshy_candidate_review import select_candidate
    from tools.meshy_stage import generate_batch

    project_root = tmp_path / "project"
    project_root.mkdir()
    references = project_root / "references"
    references.mkdir()
    contract = load_contract(CONTRACT_PATH)
    specs = _write_review_references(references)
    generate_batch(
        contract,
        project_root,
        _ReviewFakeMeshyClient(),
        100,
        pricing_file=None,
        reference_root=references,
        reference_specs={"front": specs["front"]},
        output_license="paid-private",
        today="2026-09-01",
    )
    task_dir = next(
        path for path in (project_root / "assets/_staging/meshy" / contract.asset_id).iterdir()
        if path.name != "_batches"
    )
    select_candidate(project_root, task_dir, "operator", _true_checks())
    shutil.copy2(GLB_PATH, task_dir / "cleaned.glb")
    return project_root, task_dir, contract


def test_parse_glb_rejects_duplicate_json_duplicate_bin_unknown_and_illegal_chunk_order() -> None:
    document, binary = _fixture_document_and_binary()
    json_chunk = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    bin_chunk = binary + b"\0" * ((-len(binary)) % 4)

    def chunks(items: list[tuple[bytes, bytes]]) -> bytes:
        total = 12 + sum(8 + len(payload) for _kind, payload in items)
        output = bytearray(b"glTF" + struct.pack("<II", 2, total))
        for kind, payload in items:
            output.extend(struct.pack("<II", len(payload), int.from_bytes(kind, "little")))
            output.extend(payload)
        return bytes(output)

    cases = (
        chunks([(b"JSON", json_chunk), (b"JSON", json_chunk)]),
        chunks([(b"JSON", json_chunk), (b"BIN\0", bin_chunk), (b"BIN\0", bin_chunk)]),
        chunks([(b"ABCD", json_chunk)]),
        chunks([(b"BIN\0", bin_chunk), (b"JSON", json_chunk)]),
    )
    for raw in cases:
        with pytest.raises(ValueError):
            _parse_glb(raw)


def test_parse_glb_rejects_duplicate_json_keys_nonfinite_values_and_illegal_padding() -> None:
    document, binary = _fixture_document_and_binary()
    duplicate = b'{"asset":{"version":"2.0"},"asset":{"version":"2.0"}}'
    duplicate += b" " * ((-len(duplicate)) % 4)
    nonfinite = json.dumps(document, separators=(",", ":")).replace("\"version\":\"2.0\"", "\"version\":NaN", 1).encode()
    nonfinite += b" " * ((-len(nonfinite)) % 4)
    valid = json.dumps(document, separators=(",", ":")).encode()
    valid += b"\n" * (4 - (len(valid) % 4) or 4)
    for label, json_chunk in (("duplicate", duplicate), ("nonfinite", nonfinite), ("padding", valid)):
        total = 12 + 8 + len(json_chunk) + 8 + len(binary)
        raw = b"glTF" + struct.pack("<II", 2, total)
        raw += struct.pack("<II", len(json_chunk), int.from_bytes(b"JSON", "little")) + json_chunk
        raw += struct.pack("<II", len(binary), int.from_bytes(b"BIN\0", "little")) + binary
        with pytest.raises(ValueError):
            _parse_glb(raw)


@pytest.mark.parametrize(
    "change",
    [
        lambda d, b: d["bufferViews"][0].update(buffer=99),
        lambda d, b: d["accessors"][0].update(bufferView=99),
        lambda d, b: d.setdefault("images", []).append({"bufferView": 99}),
    ],
)
def test_validate_rejects_invalid_buffers_views_accessors_and_image_references(
    contract, tmp_path: Path, change
) -> None:
    document, binary = _fixture_document_and_binary()
    change(document, binary)
    path = tmp_path / "invalid.glb"
    path.write_bytes(_pack_glb(document, binary))
    with pytest.raises(ValueError):
        validate_cleaned_glb(path, contract)


def test_validate_rejects_index_values_outside_position_accessor(contract, tmp_path: Path) -> None:
    document, binary = _fixture_document_and_binary()
    mutated = bytearray(binary)
    struct.pack_into("<H", mutated, 36, 99)
    path = tmp_path / "bad-index.glb"
    path.write_bytes(_pack_glb(document, bytes(mutated)))
    with pytest.raises(ValueError, match="index"):
        validate_cleaned_glb(path, contract)


def test_validate_requires_uvs_on_every_materialized_primitive(contract, tmp_path: Path) -> None:
    document, binary = _fixture_document_and_binary()
    del document["meshes"][0]["primitives"][0]["attributes"]["TEXCOORD_0"]
    path = tmp_path / "missing-uv.glb"
    path.write_bytes(_pack_glb(document, binary))
    with pytest.raises(ValueError, match="TEXCOORD_0"):
        validate_cleaned_glb(path, contract)


def test_validate_derives_required_states_and_pivot_policy_from_contract(contract, tmp_path: Path) -> None:
    document, binary = _fixture_document_and_binary()
    document["pivot"] = "bottom_center"
    document["required_states"] = ["open", "closed"]
    path = tmp_path / "contract-authority.glb"
    path.write_bytes(_pack_glb(document, binary))
    report = validate_cleaned_glb(path, contract)
    assert report["asset_id"] == contract.asset_id


def test_validate_rejects_neutral_non_mesh_nodes_cameras_lights_and_helpers(contract, tmp_path: Path) -> None:
    document, binary = _fixture_document_and_binary()
    document["nodes"].append({"name": "AuxLocator"})
    document["scenes"][0]["nodes"].append(1)
    path = tmp_path / "neutral-helper.glb"
    path.write_bytes(_pack_glb(document, binary))
    with pytest.raises(ValueError, match="non-mesh|helper"):
        validate_cleaned_glb(path, contract)


def test_validate_report_contains_typed_bound_fields_and_reimport_evidence(contract) -> None:
    report = validate_cleaned_glb(GLB_PATH, contract, task_id="task-1")
    assert set(report) == set(validate_module._CANONICAL_FIELDS)
    assert report["uv_evidence"][0]["vertex_count"] == 3
    assert report["blender_reimport_passed"] is False
    report["blender_reimport_passed"] = True
    validate_module._validate_report_record(report)


def test_master_runner_uses_isolated_process_group_timeout_term_kill_and_reap(monkeypatch) -> None:
    calls = []

    class FakeProcess:
        pid = 1234

        def __init__(self):
            self.communicates = 0

        def communicate(self, timeout=None):
            calls.append(("communicate", timeout))
            self.communicates += 1
            if self.communicates < 3:
                raise subprocess.TimeoutExpired(["blender"], timeout, output="", stderr="")
            return "", ""

        def wait(self, timeout=None):
            calls.append(("wait", timeout))
            return -9

    monkeypatch.setattr(master_module.subprocess, "Popen", lambda *a, **kw: (calls.append(kw) or FakeProcess()))
    monkeypatch.setattr(master_module.os, "killpg", lambda pid, sig: calls.append(("killpg", pid, sig)))
    monkeypatch.setattr(master_module, "_PROCESS_GRACE", 0.01)
    completed = master_module._run_bounded_process(["blender"], cwd=Path.cwd(), timeout=0.01)
    assert completed.returncode == -9
    assert calls[0]["start_new_session"] is True
    assert [item[2] for item in calls if isinstance(item, tuple) and item[0] == "killpg"] == [15, 9]
    assert any(item[0] == "wait" for item in calls if isinstance(item, tuple))


def test_master_publication_requires_trusted_external_root_and_private_atomic_write(tmp_path: Path, monkeypatch) -> None:
    root = tmp_path / "masters"
    root.mkdir(mode=0o700)
    monkeypatch.setattr(master_module, "TRUSTED_MASTER_ROOT", root)
    target = master_module.derive_master_path(ASSET_ID)

    class Wm:
        def save_as_mainfile(self, filepath):
            Path(filepath).write_bytes(b"blend")
            return {"FINISHED"}

    class Bpy:
        ops = type("Ops", (), {"wm": Wm()})()

    master_module._save_blend_atomically(Bpy(), target)
    assert target.read_bytes() == b"blend"
    assert (target.stat().st_mode & 0o777) == 0o600


def test_master_uses_only_task_raw_glb_and_exact_master_path(tmp_path: Path, monkeypatch) -> None:
    project_root, task_dir, contract = _bound_fixture_task(tmp_path)
    master_root = tmp_path / "trusted-master-root"
    master_root.mkdir(mode=0o700)
    monkeypatch.setattr(master_module, "TRUSTED_MASTER_ROOT", master_root)
    loaded_contract, raw_path, master_path = master_module._request_inputs(
        project_root, CONTRACT_PATH, task_dir, "operator"
    )
    assert loaded_contract.asset_id == contract.asset_id
    assert raw_path == task_dir / "raw.glb"
    assert master_path == master_root / contract.asset_id / (contract.asset_id + "_master.blend")
    (task_dir / "raw.glb").write_bytes(b"tampered")
    with pytest.raises(ValueError, match="hash|governed|container"):
        master_module._request_inputs(project_root, CONTRACT_PATH, task_dir, "operator")


def test_master_rejects_nested_or_symlinked_task_directory(tmp_path: Path, monkeypatch) -> None:
    project_root, task_dir, _contract = _bound_fixture_task(tmp_path)
    master_root = tmp_path / "trusted-master-root"
    master_root.mkdir(mode=0o700)
    monkeypatch.setattr(master_module, "TRUSTED_MASTER_ROOT", master_root)
    nested = task_dir.parent / "nested" / task_dir.name
    nested.parent.mkdir()
    shutil.copytree(task_dir, nested)
    with pytest.raises(ValueError, match="direct|task"):
        master_module._request_inputs(project_root, CONTRACT_PATH, nested, "operator")
    link = task_dir.parent / "link-task"
    link.symlink_to(task_dir, target_is_directory=True)
    with pytest.raises(ValueError, match="symlink|task"):
        master_module._request_inputs(project_root, CONTRACT_PATH, link, "operator")


def test_validation_schema_is_canonical_and_runtime_parity() -> None:
    schema_path = ROOT / "data/asset_generation/schemas/meshy_blender_validation_v1.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    assert schema["additionalProperties"] is False
    assert set(schema["properties"]) == set(validate_module._CANONICAL_FIELDS)


def test_validate_rejects_glb_and_report_aliases_outside_exact_task_leaves(tmp_path: Path) -> None:
    project_root, task_dir, contract = _bound_fixture_task(tmp_path)
    with pytest.raises(ValueError, match="exact task leaf"):
        _resolve_task_inputs(project_root, CONTRACT_PATH, task_dir, tmp_path / "alias.glb")
    with pytest.raises(ValueError, match="exact task leaf"):
        _resolve_task_inputs(project_root, CONTRACT_PATH, task_dir, None, tmp_path / "alias.json")


def test_validate_report_writer_uses_mode_0600_and_preserves_outside_sentinel(tmp_path: Path) -> None:
    project_root, task_dir, contract = _bound_fixture_task(tmp_path)
    report = validate_cleaned_glb(task_dir / "cleaned.glb", contract, task_id=task_dir.name)
    report["blender_reimport_passed"] = True
    authority = validate_module._BlenderReimportEvidence(
        validate_module._REIMPORT_AUTHORITY,
        report["sha256"],
        report["byte_size"],
        report["triangle_count"],
    )
    sentinel = tmp_path / "outside-sentinel"
    sentinel.write_bytes(b"untouched")
    write_validation_report(project_root, task_dir, report, authority)
    assert (task_dir / "blender-validation.json").stat().st_mode & 0o777 == 0o600
    assert sentinel.read_bytes() == b"untouched"
    assert json.loads((task_dir / "blender-validation.json").read_text()) == report


def test_validate_report_writer_rejects_fixed_leaf_symlink_without_touching_target(tmp_path: Path) -> None:
    project_root, task_dir, contract = _bound_fixture_task(tmp_path)
    report = validate_cleaned_glb(task_dir / "cleaned.glb", contract, task_id=task_dir.name)
    report["blender_reimport_passed"] = True
    sentinel = tmp_path / "outside-sentinel"
    sentinel.write_bytes(b"untouched")
    (task_dir / "blender-validation.json").symlink_to(sentinel)
    with pytest.raises(ValueError):
        write_validation_report(project_root, task_dir, report)
    assert sentinel.read_bytes() == b"untouched"


def test_transition_review_keeps_blender_cleanup_pass_blocked_without_report_binder(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _bound_fixture_task(tmp_path)
    review_path = task_dir / "review.json"
    review = json.loads(review_path.read_text())
    review.update({"state": "blender_cleanup_pass", "decision": "cleanup_validated"})
    review_path.write_bytes(json.dumps(review, sort_keys=True, separators=(",", ":")).encode() + b"\n")
    with pytest.raises(ValueError, match="selected"):
        _resolve_task_inputs(project_root, CONTRACT_PATH, task_dir)


def test_real_blender_reimports_fixture_and_publishes_report(tmp_path: Path) -> None:
    blender = Path(os.environ.get("BLENDER", "/opt/homebrew/bin/blender"))
    assert blender.is_file() and os.access(blender, os.X_OK)
    project_root, task_dir, _contract = _bound_fixture_task(tmp_path)
    command = [
        str(blender), "--background", "--factory-startup", "--python",
        str(MASTER_SCRIPT.parent / "meshy_blender_validate.py"), "--",
        "--project-root", str(project_root), "--contract", str(CONTRACT_PATH),
        "--task-dir", str(task_dir),
    ]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    assert "MESHY BLENDER VALIDATION PASS" in result.stdout
    persisted = json.loads((task_dir / "blender-validation.json").read_text())
    assert persisted["blender_reimport_passed"] is True
    assert (task_dir / "blender-validation.json").stat().st_mode & 0o777 == 0o600


def test_real_blender_rejects_non_affine_matrix_with_failure_marker(tmp_path: Path) -> None:
    blender = Path(os.environ.get("BLENDER", os.environ.get("BLENDER_PATH", "/Applications/Blender.app/Contents/MacOS/Blender")))
    assert blender.is_file() and os.access(blender, os.X_OK)
    project_root, task_dir, _contract = _bound_fixture_task(tmp_path)
    document, binary = _fixture_document_and_binary()
    document["nodes"][0]["matrix"] = [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 2.0,
    ]
    (task_dir / "cleaned.glb").write_bytes(_pack_glb(document, binary))
    command = [
        str(blender), "--background", "--factory-startup", "--python",
        str(MASTER_SCRIPT.parent / "meshy_blender_validate.py"), "--",
        "--project-root", str(project_root), "--contract", str(CONTRACT_PATH),
        "--task-dir", str(task_dir),
    ]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    assert result.returncode != 0
    assert "MESHY BLENDER VALIDATION PASS" not in result.stdout
    assert "affine" in result.stderr.lower() or "matrix" in result.stderr.lower()
    assert not (task_dir / "blender-validation.json").exists()


def test_report_writer_recomputes_all_semantics_and_rejects_host_boolean(tmp_path: Path) -> None:
    project_root, task_dir, contract = _bound_fixture_task(tmp_path)
    report = validate_cleaned_glb(task_dir / "cleaned.glb", contract, task_id=task_dir.name)
    report["blender_reimport_passed"] = True
    report["triangle_count"] = 99
    with pytest.raises(ValueError, match="semantic|re-import|evidence|match"):
        write_validation_report(project_root, task_dir, report)

    honest = validate_cleaned_glb(task_dir / "cleaned.glb", contract, task_id=task_dir.name)
    honest["blender_reimport_passed"] = True
    with pytest.raises(ValueError, match="authority|re-import|evidence"):
        write_validation_report(project_root, task_dir, honest)


def test_report_writer_rejects_forged_bounds_materials_and_uv_evidence(tmp_path: Path) -> None:
    project_root, task_dir, contract = _bound_fixture_task(tmp_path)
    report = validate_cleaned_glb(task_dir / "cleaned.glb", contract, task_id=task_dir.name)
    report["blender_reimport_passed"] = True
    expected = validate_cleaned_glb(task_dir / "cleaned.glb", contract, task_id=task_dir.name)
    authority = validate_module._BlenderReimportEvidence(
        validate_module._REIMPORT_AUTHORITY,
        expected["sha256"],
        expected["byte_size"],
        expected["triangle_count"],
    )
    report["bounds"]["max"][0] = 999.0
    report["bounds"]["dimensions"][0] = 999.0
    report["material_names"] = ["ForgedMaterial"]
    report["uv_evidence"][0]["accessor"] = 999
    with pytest.raises(ValueError, match="semantic|re-import|evidence|match|bounds"):
        write_validation_report(project_root, task_dir, report, authority)


def _run_python_process(script: str) -> list[str]:
    return ["/usr/bin/python3", "-c", script]


def _kill_pid_if_alive(pid_file: Path) -> None:
    try:
        pid = int(pid_file.read_text())
    except (OSError, ValueError):
        return
    try:
        os.kill(pid, 0)
    except OSError:
        return
    try:
        os.kill(pid, 9)
    except OSError:
        pass


def test_master_timeout_is_failure_when_leader_exits_zero_but_descendant_holds_pipes(tmp_path: Path, monkeypatch) -> None:
    child_pid = tmp_path / "child.pid"
    script = (
        "import pathlib, subprocess, sys, time; "
        "p=subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
        "pathlib.Path(" + repr(str(child_pid)) + ").write_text(str(p.pid)); "
        "sys.exit(0)"
    )
    try:
        monkeypatch.setattr(master_module, "_PROCESS_GRACE", 0.05)
        completed = master_module._run_bounded_process(
            _run_python_process(script), cwd=tmp_path, timeout=0.05
        )
        assert completed.returncode != 0
    finally:
        _kill_pid_if_alive(child_pid)


def test_master_output_cap_is_failure_even_when_leader_exits_zero(tmp_path: Path, monkeypatch) -> None:
    try:
        monkeypatch.setattr(master_module, "_MAX_PROCESS_OUTPUT", 64)
        completed = master_module._run_bounded_process(
            _run_python_process("import sys; sys.stdout.write('x' * 128); sys.stdout.flush()"),
            cwd=tmp_path,
            timeout=1.0,
        )
        assert completed.returncode != 0
    finally:
        pass


def test_master_post_launch_setup_failure_cleans_up_and_reaps_process(tmp_path: Path, monkeypatch) -> None:
    leader_pid = tmp_path / "leader.pid"
    script = (
        "import os, pathlib, time; "
        "pathlib.Path(" + repr(str(leader_pid)) + ").write_text(str(os.getpid())); "
        "time.sleep(30)"
    )
    original_group_check = master_module._isolated_process_group_id

    def fail_after_process_starts(process):
        deadline = time.monotonic() + 1.0
        while time.monotonic() < deadline and not leader_pid.exists():
            time.sleep(0.01)
        raise master_module.BlenderMasterError("inspection boom")

    monkeypatch.setattr(master_module, "_isolated_process_group_id", fail_after_process_starts)
    monkeypatch.setattr(master_module, "_PROCESS_GRACE", 0.05)
    try:
        with pytest.raises(ValueError, match="inspection boom"):
            master_module._run_bounded_process(_run_python_process(script), cwd=tmp_path, timeout=1.0)
        assert leader_pid.exists()
        deadline = time.monotonic() + 1.0
        while time.monotonic() < deadline:
            try:
                os.kill(int(leader_pid.read_text()), 0)
            except OSError:
                break
            time.sleep(0.01)
        else:
            pytest.fail("post-launch setup failure leaked the leader")
    finally:
        monkeypatch.setattr(master_module, "_isolated_process_group_id", original_group_check)
        _kill_pid_if_alive(leader_pid)


def test_parse_glb_rejects_newline_before_space_padding() -> None:
    document, binary = _fixture_document_and_binary()
    json_chunk = json.dumps(document, separators=(",", ":")).encode("utf-8") + b"\n"
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    binary_chunk = binary + b"\0" * ((-len(binary)) % 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(binary_chunk)
    raw = b"glTF" + struct.pack("<II", 2, total)
    raw += struct.pack("<II", len(json_chunk), int.from_bytes(b"JSON", "little")) + json_chunk
    raw += struct.pack("<II", len(binary_chunk), int.from_bytes(b"BIN\0", "little")) + binary_chunk
    with pytest.raises(ValueError, match="padding"):
        _parse_glb(raw)


@pytest.mark.parametrize(
    "mutate",
    [
        lambda d: d.update(materials=[{"name": "Paint", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}], textures=[]),
        lambda d: d.update(materials=[{"name": "Paint", "extensions": {"KHR_materials_clearcoat": {"clearcoatNormalTexture": {"index": 0}}}}], textures=[]),
        lambda d: d.update(materials=[{"name": "Paint", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}], textures=[{"source": 9}], images=[{"uri": "paint.png"}]),
        lambda d: d.update(materials=[{"name": "Paint", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}], textures=[{"sampler": 9}], samplers=[{}]),
    ],
)
def test_validate_rejects_invalid_material_texture_graph_references(contract, tmp_path: Path, mutate) -> None:
    document, binary = _fixture_document_and_binary()
    mutate(document)
    path = tmp_path / "invalid-texture-graph.glb"
    path.write_bytes(_pack_glb(document, binary))
    with pytest.raises(ValueError, match="Texture|texture|image|sampler"):
        validate_cleaned_glb(path, contract)


def test_validate_checks_secondary_scene_references_and_uses_default_scene_bounds(contract, tmp_path: Path) -> None:
    document, binary = _fixture_document_and_binary()
    document["nodes"].append({"mesh": 0, "name": "TriangleSecondary"})
    document["scenes"].append({"nodes": [1]})
    path = tmp_path / "secondary-scene.glb"
    path.write_bytes(_pack_glb(document, binary))
    report = validate_cleaned_glb(path, contract)
    assert report["mesh_count"] == 1
    assert report["triangle_count"] == 1
    assert report["bounds"]["max"] == [1.0, 1.0, 0.0]


def test_validate_rejects_invalid_secondary_scene_root(contract, tmp_path: Path) -> None:
    document, binary = _fixture_document_and_binary()
    document["scenes"].append({"nodes": [99]})
    path = tmp_path / "invalid-secondary-scene.glb"
    path.write_bytes(_pack_glb(document, binary))
    with pytest.raises(ValueError, match="scene node|scene"):
        validate_cleaned_glb(path, contract)


def test_validate_report_uv_evidence_requires_positive_counts(contract) -> None:
    report = validate_cleaned_glb(GLB_PATH, contract, task_id="task-1")
    report["blender_reimport_passed"] = True
    report["uv_evidence"][0]["vertex_count"] = 0
    report["uv_evidence"][0]["uv_count"] = 0
    with pytest.raises(ValueError, match="UV evidence"):
        validate_module._validate_report_record(report)


def test_validate_rejects_non_affine_glb_matrix(contract, tmp_path: Path) -> None:
    document, binary = _fixture_document_and_binary()
    document["nodes"][0]["matrix"] = [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 2.0,
    ]
    path = tmp_path / "non-affine.glb"
    path.write_bytes(_pack_glb(document, binary))
    with pytest.raises(ValueError, match="affine|matrix"):
        validate_cleaned_glb(path, contract)
