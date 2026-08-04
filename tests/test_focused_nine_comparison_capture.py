from __future__ import annotations

import re
from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CAPTURE_SCRIPT = PROJECT_ROOT / "scripts/validation/focused_nine_comparison_capture.gd"
HARNESS_SCENE = PROJECT_ROOT / "scenes/validation/focused_nine_comparison_harness.tscn"


def _source(path: Path) -> str:
    if not path.is_file():
        pytest.fail(f"expected Task 7 file is missing: {path}")
    return path.read_text(encoding="utf-8")


def test_task_7_files_exist() -> None:
    assert CAPTURE_SCRIPT.is_file(), CAPTURE_SCRIPT
    assert HARNESS_SCENE.is_file(), HARNESS_SCENE


def test_capture_script_uses_locked_iso_camera_and_direct_staged_glb_loading() -> None:
    source = _source(CAPTURE_SCRIPT)

    assert "CAMERA_SIZE := 18.0" in source
    assert "GLTFDocument" in source
    assert "append_from_file" in source
    assert "generate_scene" in source
    assert 'STAGED_ROOT := "res://assets/_staging/focused_nine/"' in source
    assert "missing staged GLB" in source
    assert "RuntimePropVisualBinder" not in source


def test_capture_script_has_exact_cli_and_capture_contract() -> None:
    source = _source(CAPTURE_SCRIPT)

    for option in ("--output-dir", "--baseline-label", "--improved-label"):
        assert option in source
    assert 'FOCUSED_NINE_COMPARISON_CAPTURE PASS output=' in source
    assert "get_root().get_texture().get_image()" in source
    assert "get_tree().process_frame" in source
    assert re.search(r"for\s+[^\n]+\s+in\s+10", source)
    assert "1600" in source and "900" in source
    assert "image.get_width()" in source
    assert "image.get_height()" in source
    assert "image.is_empty()" in source
    assert "get_file_as_bytes" in source
    assert "focused-nine-comparison00000000.png" in source
    assert "focused-nine-comparison.png" in source
    assert "copy_absolute" in source
    assert "--write-movie" not in source


def test_capture_rejects_headless_and_out_of_project_output_dirs() -> None:
    source = _source(CAPTURE_SCRIPT)

    assert 'DisplayServer.get_name() == "headless"' in source
    assert "ProjectSettings.globalize_path" in source
    assert "is_absolute_path" in source
    assert "begins_with(project_root" in source
    assert "output directory must be inside project root" in source


def test_harness_has_fixed_camera_and_baseline_improved_roots() -> None:
    scene = _source(HARNESS_SCENE)

    assert 'name="Baseline" type="Node3D" parent="."' in scene
    assert 'name="Improved" type="Node3D" parent="."' in scene
    assert "size = 18.0" in scene
    assert "projection = 1" in scene
    assert (
        "Transform3D(0.707107, -0.408248, 0.57735, 0, 0.816497, 0.57735, "
        "-0.707107, -0.408248, 0.57735, 16, 14, 16)"
    ) in scene
    assert "position = Vector3(-5, 0, 0)" in scene
    assert "position = Vector3(5, 0, 0)" in scene
    assert 'type="DirectionalLight3D"' in scene
    assert 'type="Label"' not in scene
    assert 'type="Label3D"' not in scene


def test_capture_disables_local_lights_on_every_baseline_stand_in_recursively() -> None:
    source = _source(CAPTURE_SCRIPT)
    helper = re.search(
        r"func _disable_local_lights\(node: Node\) -> void:(?P<body>.*?)(?=\n\nfunc |\Z)",
        source,
        flags=re.DOTALL,
    )

    assert helper is not None
    helper_body = helper.group("body")
    assert re.search(r"for\s+child(?::\s*Node)?\s+in\s+node\.get_children\(\)", helper_body)
    assert "if child is Light3D" in helper_body
    assert "child.visible = false" in helper_body
    assert "_disable_local_lights(child)" in helper_body

    for stand_in_name in ("stand_in_supply", "stand_in_breaker", "stand_in_blocked"):
        stand_in_start = source.index(f"var {stand_in_name}: Node3D")
        add_child = source.index(f"baseline.add_child({stand_in_name})", stand_in_start)
        assert source.index(f"_disable_local_lights({stand_in_name})", stand_in_start) < add_child
