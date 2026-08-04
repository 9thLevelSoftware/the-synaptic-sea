from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

from tools import focused_nine_evidence as evidence
from tools.prop_visual_metadata import read_glb_metadata


PROJECT_ROOT = Path(__file__).resolve().parents[1]
KNOWN_GLB = PROJECT_ROOT / "assets/imported/props/components/reactor_console.glb"
BLENDER = Path("/opt/homebrew/bin/blender")
MODULE = PROJECT_ROOT / "tools/focused_nine_evidence.py"


def staged_fixture(tmp_path: Path) -> tuple[Path, Path, Path]:
    project = tmp_path / "project"
    stage = project / "assets/_staging/focused_nine/props"
    stage.mkdir(parents=True)
    glb = stage / "fixture.glb"
    shutil.copy2(KNOWN_GLB, glb)
    evidence_dir = project / "assets/_staging/focused_nine/evidence"
    evidence_dir.mkdir()
    return project, glb, evidence_dir / "fixture.json"


def minimal_record(*, triangles: int = 472) -> dict:
    return {
        "triangle_count": triangles,
        "mesh_count": 1,
        "material_names": ["MAT_PaintedAlloyGray"],
        "blender_reimport_passed": True,
    }


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(MODULE), *args],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def test_budget_validator_rejects_triangle_count_above_maximum() -> None:
    record = minimal_record(triangles=1501)

    assert evidence.validate_evidence(record, 350, 1500) == [
        "triangle budget exceeded: 1501 > 1500"
    ]


def test_budget_validator_rejects_triangle_count_below_minimum() -> None:
    errors = evidence.validate_evidence(minimal_record(triangles=299), 300, 1200)

    assert errors == ["triangle budget below minimum: 299 < 300"]


def test_budget_validator_rejects_invalid_ranges_and_malformed_records() -> None:
    errors = evidence.validate_evidence({}, 1200, 300)
    assert errors == sorted(errors)
    assert any("record missing field" in error for error in errors)
    assert any("minimum must not exceed maximum" in error for error in errors)

    nonfinite = minimal_record()
    nonfinite["triangle_count"] = float("nan")
    errors = evidence.validate_evidence(nonfinite, 300, 1200)
    assert any("triangle_count" in error and "finite" in error for error in errors)

    unserializable = minimal_record()
    unserializable["extra"] = object()
    assert "record must be JSON-serializable" in evidence.validate_evidence(
        unserializable, 300, 1200
    )

    assert evidence.validate_evidence(None, 300, 1200) == ["record must be an object"]


def test_budget_validator_checks_material_count_and_reimport_contract() -> None:
    record = minimal_record()
    record["material_count"] = 2
    record["material_names"] = ["zeta", "alpha", "zeta"]
    record["blender_reimport_passed"] = False

    errors = evidence.validate_evidence(record, 300, 1200)

    assert errors == sorted(errors)
    assert any("material_count" in error and "match" in error for error in errors)
    assert any("material_names" in error and "sorted" in error for error in errors)
    assert "blender_reimport_passed must be true" in errors


def test_budget_validator_is_total_for_cyclic_deep_hostile_and_oversized_values() -> None:
    cyclic = minimal_record()
    cyclic["cyclic"] = cyclic
    deep: object = minimal_record()
    for _ in range(2500):
        deep = [deep]

    class HostileMapping(dict):
        def get(self, *_args: object, **_kwargs: object) -> object:
            raise RuntimeError("hostile mapping")

    hostile = HostileMapping(minimal_record())
    oversized = minimal_record()
    oversized["x" * 100_000] = object()

    for record in (cyclic, deep, hostile, oversized):
        first = evidence.validate_evidence(record, 300, 1200)
        second = evidence.validate_evidence(record, 300, 1200)
        assert first == second
        assert first == sorted(first)
        assert all(len(error) < 1000 for error in first)


def test_atomic_json_publish_preserves_previous_evidence_on_validation_failure(
    tmp_path: Path,
) -> None:
    _project, _glb, target = staged_fixture(tmp_path)
    previous = b'{"old":true}\n'
    target.write_bytes(previous)

    with pytest.raises(ValueError):
        evidence.publish_json_atomically(target, {"triangle_count": float("nan")})

    assert target.read_bytes() == previous
    assert not list(target.parent.glob(".*.tmp"))


def test_atomic_json_publish_preserves_previous_evidence_on_serialization_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _project, _glb, target = staged_fixture(tmp_path)
    previous = b'{"old":true}\n'
    target.write_bytes(previous)

    def fail_serialization(*_args: object, **_kwargs: object) -> str:
        raise ValueError("serialization failed")

    monkeypatch.setattr(evidence.json, "dumps", fail_serialization)
    with pytest.raises(ValueError, match="serialization failed"):
        evidence.publish_json_atomically(target, minimal_record())

    assert target.read_bytes() == previous
    assert not list(target.parent.glob(".*.tmp"))


def test_atomic_json_publish_replace_failure_preserves_target_and_cleans_temp(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _project, _glb, target = staged_fixture(tmp_path)
    previous = b'{"old":true}\n'
    target.write_bytes(previous)

    def fail_replace(*_args: object, **_kwargs: object) -> None:
        raise OSError("injected replace failure")

    monkeypatch.setattr(evidence.os, "replace", fail_replace)
    with pytest.raises(OSError, match="injected replace failure"):
        evidence.publish_json_atomically(target, minimal_record())

    assert target.read_bytes() == previous
    assert not list(target.parent.glob(".*.tmp"))


def test_atomic_json_publish_preserves_primary_replace_error_if_cleanup_fails(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _project, _glb, target = staged_fixture(tmp_path)
    previous = b'{"old":true}\n'
    target.write_bytes(previous)

    def fail_replace(*_args: object, **_kwargs: object) -> None:
        raise OSError("primary replace failure")

    def fail_unlink(*_args: object, **_kwargs: object) -> None:
        raise OSError("secondary cleanup failure")

    monkeypatch.setattr(evidence.os, "replace", fail_replace)
    monkeypatch.setattr(evidence.os, "unlink", fail_unlink)
    with pytest.raises(OSError, match="primary replace failure"):
        evidence.publish_json_atomically(target, minimal_record())

    assert target.read_bytes() == previous


def test_atomic_json_publish_writes_canonical_json_bytes_after_success(tmp_path: Path) -> None:
    _project, _glb, target = staged_fixture(tmp_path)
    record = {
        "blender_reimport_passed": True,
        "material_names": ["MAT_PaintedAlloyGray"],
        "mesh_count": 1,
        "triangle_count": 472,
    }

    evidence.publish_json_atomically(target, record)

    assert target.read_bytes() == (
        b'{"blender_reimport_passed":true,"material_names":["MAT_PaintedAlloyGray"],'
        b'"mesh_count":1,"triangle_count":472}\n'
    )


@pytest.mark.skipif(not BLENDER.is_file(), reason="Blender 5.2 is not installed")
def test_inspect_staged_glb_uses_clean_blender_reimport_and_metadata_hash(
    tmp_path: Path,
) -> None:
    project, glb, target = staged_fixture(tmp_path)
    source_hash_before = hashlib.sha256(KNOWN_GLB.read_bytes()).hexdigest()
    before = {
        path.relative_to(project): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in project.rglob("*")
        if path.is_file()
    }
    metadata = read_glb_metadata(glb)

    record = evidence.inspect_staged_glb(glb, BLENDER)

    after = {
        path.relative_to(project): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in project.rglob("*")
        if path.is_file()
    }
    assert after == before
    assert hashlib.sha256(KNOWN_GLB.read_bytes()).hexdigest() == source_hash_before
    assert record["sha256"] == metadata["sha256"]
    assert record["sha256"] == hashlib.sha256(glb.read_bytes()).hexdigest()
    assert record["triangle_count"] > 0
    assert record["material_names"] == sorted(set(record["material_names"]))
    assert record["material_names"]
    assert record["material_count"] == len(record["material_names"])
    assert record["blender_reimport_passed"] is True


def test_inspector_marker_parser_rejects_duplicate_constants_and_shape_attacks() -> None:
    valid = (
        '{"triangle_count":472,"material_names":["MAT_PaintedAlloyGray"],'
        '"blender_reimport_passed":true}'
    )
    assert evidence._parse_inspector_output(
        evidence._INSPECTOR_MARKER + valid + "\n"
    ) == {
        "triangle_count": 472,
        "material_names": ["MAT_PaintedAlloyGray"],
        "blender_reimport_passed": True,
    }

    rejected = (
        '{"triangle_count":472,"triangle_count":473,"material_names":["MAT_PaintedAlloyGray"],'
        '"blender_reimport_passed":true}'
    )
    for payload in (
        rejected,
        '{"triangle_count":NaN,"material_names":["MAT_PaintedAlloyGray"],"blender_reimport_passed":true}',
        '{"triangle_count":472,"material_names":["MAT_PaintedAlloyGray"],"blender_reimport_passed":true,"sha256":"f"}',
        '{"triangle_count":472,"material_names":[],"blender_reimport_passed":true}',
        '{"triangle_count":472,"material_names":["zeta","alpha"],"blender_reimport_passed":true}',
        '{"triangle_count":472,"material_names":["MAT_PaintedAlloyGray"]}',
    ):
        with pytest.raises(ValueError):
            evidence._parse_inspector_output(evidence._INSPECTOR_MARKER + payload + "\n")


def test_inspector_output_is_bounded_and_has_a_finite_timeout(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    real_popen = evidence.subprocess.Popen
    calls: list[dict[str, object]] = []

    def noisy_popen(command: list[str], **kwargs: object) -> object:
        calls.append(kwargs)
        return real_popen(
            [sys.executable, "-c", "import sys; sys.stdout.write('x' * 10000); sys.stdout.flush()"],
            **kwargs,
        )

    monkeypatch.setattr(evidence.subprocess, "Popen", noisy_popen)
    monkeypatch.setattr(evidence, "_BLENDER_INSPECTOR_OUTPUT_LIMIT", 128)
    with pytest.raises(ValueError, match="output exceeded cap"):
        evidence._run_blender_inspector(tmp_path / "fixture.glb", Path("blender"))

    assert calls
    assert calls[0]["stdout"] is evidence.subprocess.PIPE
    assert calls[0]["stderr"] is evidence.subprocess.PIPE
    assert evidence._BLENDER_INSPECTOR_TIMEOUT_SECONDS > 0


def test_inspector_output_timeout_terminates_child_and_is_deterministic(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    real_popen = evidence.subprocess.Popen

    def sleeping_popen(command: list[str], **kwargs: object) -> object:
        return real_popen(
            [sys.executable, "-c", "import time; time.sleep(2)"],
            **kwargs,
        )

    monkeypatch.setattr(evidence.subprocess, "Popen", sleeping_popen)
    monkeypatch.setattr(evidence, "_BLENDER_INSPECTOR_TIMEOUT_SECONDS", 0.05)
    started = time.monotonic()
    with pytest.raises(ValueError, match="timed out"):
        evidence._run_blender_inspector(tmp_path / "fixture.glb", Path("blender"))
    assert time.monotonic() - started < 1.0


@pytest.mark.skipif(os.name != "posix", reason="process groups are POSIX-specific")
def test_inspector_timeout_kills_descendant_process_group_without_leak(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    marker = tmp_path / "descendant.pid"
    child_code = "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)"
    parent_code = (
        "import pathlib,subprocess,sys,time; "
        f"child=subprocess.Popen([{sys.executable!r}, '-c', {child_code!r}]); "
        f"pathlib.Path({str(marker)!r}).write_text(str(child.pid)); "
        "time.sleep(60)"
    )
    real_popen = evidence.subprocess.Popen
    calls: list[dict[str, object]] = []
    processes: list[subprocess.Popen[bytes]] = []

    def process_tree_popen(_command: list[str], **kwargs: object) -> object:
        calls.append(kwargs)
        process = real_popen([sys.executable, "-c", parent_code], **kwargs)
        processes.append(process)
        return process

    monkeypatch.setattr(evidence.subprocess, "Popen", process_tree_popen)
    monkeypatch.setattr(evidence, "_BLENDER_INSPECTOR_TIMEOUT_SECONDS", 0.2)

    with pytest.raises(ValueError, match="timed out"):
        evidence._run_blender_inspector(tmp_path / "fixture.glb", Path("blender"))

    assert calls and calls[0]["start_new_session"] is True
    assert processes and processes[0].returncode is not None
    descendant_pid = int(marker.read_text(encoding="utf-8"))
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        try:
            os.kill(descendant_pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.01)
    else:
        pytest.fail(f"descendant process {descendant_pid} survived process-group cleanup")


@pytest.mark.skipif(os.name != "posix", reason="process groups are POSIX-specific")
def test_inspector_fails_closed_when_process_group_cleanup_is_unavailable(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(evidence.os, "killpg", None)

    with pytest.raises(ValueError, match="process-group"):
        evidence._run_blender_inspector(tmp_path / "fixture.glb", Path("blender"))


def test_inspect_rejects_regular_directory_rebind_after_validation(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _project, glb, _target = staged_fixture(tmp_path)
    original_validate = evidence._validate_staged_glb
    original_directory = glb.parent
    moved_directory = glb.parent.with_name("props-real")

    def replace_with_regular_directory(path: Path) -> tuple[Path, Path, Path]:
        result = original_validate(path)
        original_directory.rename(moved_directory)
        original_directory.mkdir()
        (original_directory / glb.name).write_bytes(KNOWN_GLB.read_bytes())
        return result

    monkeypatch.setattr(evidence, "_validate_staged_glb", replace_with_regular_directory)
    monkeypatch.setattr(
        evidence,
        "_run_blender_inspector",
        lambda *_args: {
            "triangle_count": 472,
            "material_names": ["MAT_PaintedAlloyGray"],
            "blender_reimport_passed": True,
        },
    )
    try:
        with pytest.raises(ValueError, match="identity|rebind"):
            evidence.inspect_staged_glb(glb, BLENDER)
    finally:
        shutil.rmtree(original_directory)
        moved_directory.rename(original_directory)

    assert glb.read_bytes() == KNOWN_GLB.read_bytes()


def test_publisher_rejects_regular_directory_rebind_after_validation(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _project, _glb, target = staged_fixture(tmp_path)
    previous = b'{"old":true}\n'
    target.write_bytes(previous)
    original_validate = evidence._validate_json_target
    original_directory = target.parent
    moved_directory = target.parent.with_name("evidence-real")

    def replace_with_regular_directory(path: Path, expected_stage: Path) -> tuple[Path, Path]:
        result = original_validate(path, expected_stage)
        original_directory.rename(moved_directory)
        original_directory.mkdir()
        (original_directory / target.name).write_bytes(b"attacker\n")
        return result

    monkeypatch.setattr(evidence, "_validate_json_target", replace_with_regular_directory)
    try:
        with pytest.raises(ValueError, match="identity|rebind"):
            evidence.publish_json_atomically(target, minimal_record())
    finally:
        shutil.rmtree(original_directory)
        moved_directory.rename(original_directory)

    assert target.read_bytes() == previous


def test_inspect_merges_only_authenticated_inspector_fields(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    _project, glb, _target = staged_fixture(tmp_path)
    static = read_glb_metadata(glb)
    monkeypatch.setattr(evidence, "_run_blender_inspector", lambda *_args: {
        "triangle_count": 472,
        "material_names": ["MAT_PaintedAlloyGray"],
        "blender_reimport_passed": True,
        "sha256": "f" * 64,
        "mesh_count": 999,
        "local_min_m": [99, 99, 99],
    })

    with pytest.raises(ValueError, match="unexpected inspector field"):
        evidence.inspect_staged_glb(glb, BLENDER)

    monkeypatch.setattr(evidence, "_run_blender_inspector", lambda *_args: {
        "triangle_count": 472,
        "material_names": ["MAT_PaintedAlloyGray"],
        "blender_reimport_passed": True,
    })
    record = evidence.inspect_staged_glb(glb, BLENDER)
    assert record["sha256"] == static["sha256"]
    assert record["mesh_count"] == static["mesh_count"]
    assert record["local_min_m"] == static["local_min_m"]


def test_inspect_pins_input_copy_and_rejects_ancestor_replacement(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _project, glb, _target = staged_fixture(tmp_path)
    original_validate = evidence._validate_staged_glb
    original_directory = glb.parent
    moved_directory = glb.parent.with_name("props-real")
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / glb.name).write_bytes(glb.read_bytes())

    def replace_after_lexical_check(path: Path) -> tuple[Path, Path, Path]:
        result = original_validate(path)
        original_directory.rename(moved_directory)
        try:
            original_directory.symlink_to(outside, target_is_directory=True)
        except OSError as exc:
            moved_directory.rename(original_directory)
            pytest.skip(f"symlink replacement unavailable: {exc}")
        return result

    monkeypatch.setattr(evidence, "_validate_staged_glb", replace_after_lexical_check)
    with pytest.raises(ValueError, match="secure|NOFOLLOW|staging"):
        evidence.inspect_staged_glb(glb, BLENDER)

    original_directory.unlink()
    moved_directory.rename(original_directory)
    assert glb.read_bytes() == KNOWN_GLB.read_bytes()


def test_inspect_uses_immutable_temp_copy_for_all_glb_reads(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _project, glb, _target = staged_fixture(tmp_path)
    paths: list[Path] = []

    def record_magic(path: Path) -> list[str]:
        paths.append(Path(path))
        return []

    def record_metadata(path: Path) -> dict[str, object]:
        paths.append(Path(path))
        return read_glb_metadata(path)

    def record_blender(path: Path, _blender: Path) -> dict[str, object]:
        paths.append(Path(path))
        return {
            "triangle_count": 472,
            "material_names": ["MAT_PaintedAlloyGray"],
            "blender_reimport_passed": True,
        }

    monkeypatch.setattr(evidence, "validate_glb_magic", record_magic)
    monkeypatch.setattr(evidence, "read_glb_metadata", record_metadata)
    monkeypatch.setattr(evidence, "_run_blender_inspector", record_blender)
    record = evidence.inspect_staged_glb(glb, BLENDER)

    assert record["sha256"] == hashlib.sha256(glb.read_bytes()).hexdigest()
    assert len(paths) == 3
    assert all(path != glb and path.name.endswith(".glb") for path in paths)
    assert len({path.parent for path in paths}) == 1


def test_inspect_rejects_imported_input_and_bad_magic_before_blender(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    imported = tmp_path / "project/assets/imported/props/bad.glb"
    imported.parent.mkdir(parents=True)
    imported.write_bytes(b"glTF")
    bad = tmp_path / "project/assets/_staging/focused_nine/props/bad.glb"
    bad.parent.mkdir(parents=True)
    bad.write_bytes(b"not-glb")

    def fail_if_called(*_args: object, **_kwargs: object) -> None:
        raise AssertionError("Blender must not run for static path/magic failures")

    monkeypatch.setattr(evidence.subprocess, "run", fail_if_called)
    with pytest.raises(ValueError, match="focused-nine staging"):
        evidence.inspect_staged_glb(imported, BLENDER)
    with pytest.raises(ValueError, match="invalid GLB magic"):
        evidence.inspect_staged_glb(bad, BLENDER)


def test_publisher_rejects_traversal_and_runtime_imported_outputs(tmp_path: Path) -> None:
    project, _glb, target = staged_fixture(tmp_path)
    with pytest.raises(ValueError, match="focused-nine staging"):
        evidence.publish_json_atomically(project / "assets/imported/evidence.json", minimal_record())
    with pytest.raises(ValueError, match="parent traversal"):
        evidence.publish_json_atomically(
            project / "assets/_staging/focused_nine/props/../escape.json",
            minimal_record(),
        )
    assert not target.exists()


def test_cli_rejects_imported_input_and_output_before_blender(tmp_path: Path) -> None:
    project, staged_glb, target = staged_fixture(tmp_path)
    imported_glb = project / "assets/imported/props/imported.glb"
    imported_glb.parent.mkdir(parents=True)
    shutil.copy2(KNOWN_GLB, imported_glb)
    imported_output = project / "assets/imported/evidence.json"

    input_result = run_cli(
        "--glb",
        str(imported_glb),
        "--kind",
        "prop",
        "--blender",
        str(BLENDER),
        "--json-out",
        str(target),
    )
    output_result = run_cli(
        "--glb",
        str(staged_glb),
        "--kind",
        "prop",
        "--blender",
        str(BLENDER),
        "--json-out",
        str(imported_output),
    )

    assert input_result.returncode == 1
    assert "focused-nine staging" in input_result.stderr
    assert output_result.returncode == 1
    assert "focused-nine staging" in output_result.stderr
    assert not imported_output.exists()


def test_publisher_rejects_symlinked_staging_output(tmp_path: Path) -> None:
    project, _glb, target = staged_fixture(tmp_path)
    outside = tmp_path / "outside.json"
    outside.write_bytes(b"outside\n")
    try:
        target.symlink_to(outside)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")

    with pytest.raises(ValueError, match="symlink"):
        evidence.publish_json_atomically(target, minimal_record())
    assert outside.read_bytes() == b"outside\n"


@pytest.mark.skipif(not BLENDER.is_file(), reason="Blender 5.2 is not installed")
def test_cli_happy_path_writes_evidence_only_under_staging(tmp_path: Path) -> None:
    _project, glb, target = staged_fixture(tmp_path)

    result = run_cli(
        "--glb",
        str(glb),
        "--kind",
        "prop",
        "--blender",
        str(BLENDER),
        "--json-out",
        str(target),
    )

    assert result.returncode == 0, result.stderr
    record = json.loads(target.read_text(encoding="utf-8"))
    assert evidence.validate_evidence(record, 300, 1200) == []
    assert record["sha256"] == read_glb_metadata(glb)["sha256"]


@pytest.mark.skipif(not BLENDER.is_file(), reason="Blender 5.2 is not installed")
def test_cli_budget_error_does_not_publish_output(tmp_path: Path) -> None:
    _project, glb, target = staged_fixture(tmp_path)

    result = run_cli(
        "--glb",
        str(glb),
        "--kind",
        "prop",
        "--min-triangles",
        "500",
        "--max-triangles",
        "600",
        "--blender",
        str(BLENDER),
        "--json-out",
        str(target),
    )

    assert result.returncode == 1
    assert "triangle budget below minimum" in result.stderr
    assert not target.exists()
