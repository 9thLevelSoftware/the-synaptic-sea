from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
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
    assert target.parent.exists()


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
