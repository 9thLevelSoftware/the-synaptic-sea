from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CAPTURE_SCRIPT = PROJECT_ROOT / "scripts/validation/focused_nine_comparison_capture.gd"
HARNESS_SCENE = PROJECT_ROOT / "scenes/validation/focused_nine_comparison_harness.tscn"
GODOT = shutil.which("godot") or "/opt/homebrew/bin/godot"


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
    assert 'APPROVED_OUTPUT_ROOT := "res://artifacts/validation-previews/focused-nine"' in source
    assert 'const REALPATH_COMMAND := "/bin/realpath"' in source
    assert "OS.execute" in source
    assert "canonical" in source.lower()
    assert "output directory must be inside approved focused-nine subtree" in source


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


def test_capture_checks_stable_copy_bytes_and_defers_visual_acceptance_to_task_8() -> None:
    source = _source(CAPTURE_SCRIPT)

    assert "_copy_stable_frame" in source
    assert re.search(r"stable_bytes\s*!=\s*frame_bytes|frame_bytes\s*!=\s*stable_bytes", source)
    assert "full real GLTF render/copy/PASS marker acceptance is intentionally deferred to Task 8" in source
    assert "after all nine GLBs are staged" in source


def _write_behavioral_probe(project: Path, probe: Path) -> None:
    (project / "scripts/validation").mkdir(parents=True)
    (project / "scripts/procgen").mkdir(parents=True)
    shutil.copy2(CAPTURE_SCRIPT, project / "scripts/validation/focused_nine_comparison_capture.gd")
    shutil.copy2(
        PROJECT_ROOT / "scripts/procgen/readability_prop_factory.gd",
        project / "scripts/procgen/readability_prop_factory.gd",
    )
    (project / "project.godot").write_text(
        "\n".join(
            (
                "; Task 7 behavioral probe project",
                "config_version=5",
                "",
                "[application]",
                'config/name="Task 7 Capture Probe"',
                'config/features=PackedStringArray("4.6", "GL Compatibility")',
                "",
                "[rendering]",
                'renderer/rendering_method="gl_compatibility"',
                "",
            )
        ),
        encoding="utf-8",
    )
    probe.write_text(
        """extends SceneTree

const CaptureScript: GDScript = preload("res://scripts/validation/focused_nine_comparison_capture.gd")
const PASS_MARKER := "TASK7_CAPTURE_BEHAVIORAL_PROBE PASS"


func _expect(condition: bool, reason: String) -> void:
    if condition:
        return
    printerr("TASK7_CAPTURE_BEHAVIORAL_PROBE FAIL reason=%s" % reason)
    quit(1)


func _init() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    _expect(args.size() == 7, "probe arguments")
    var capture = CaptureScript.new()

    var valid: Dictionary = capture.call(
        "_parse_user_args",
        PackedStringArray(["--output-dir", "res://artifacts/validation-previews/focused-nine/probe", "--baseline-label", "B", "--improved-label", "I"]),
    )
    _expect(not valid.has("error"), "valid parser args")
    _expect(str(valid["output_dir"]).ends_with("focused-nine/probe"), "valid output option")
    _expect(str(valid["baseline_label"]) == "B" and str(valid["improved_label"]) == "I", "valid labels")

    var missing: Dictionary = capture.call("_parse_user_args", PackedStringArray(["--baseline-label"]))
    _expect(missing.has("error") and str(missing["error"]).contains("missing value"), "missing option value")
    var duplicate: Dictionary = capture.call(
        "_parse_user_args",
        PackedStringArray(["--output-dir", "res://artifacts/validation-previews/focused-nine/a", "--output-dir", "res://artifacts/validation-previews/focused-nine/b"]),
    )
    _expect(duplicate.has("error") and str(duplicate["error"]).contains("duplicate"), "duplicate option")
    var unknown: Dictionary = capture.call("_parse_user_args", PackedStringArray(["--unknown", "value"]))
    _expect(unknown.has("error") and str(unknown["error"]).contains("unknown argument"), "unknown option")

    var valid_path: String = str(args[0])
    var outside_path: String = str(args[1])
    var traversal_path: String = str(args[2])
    var symlink_path: String = str(args[3])
    var outside_escape_path: String = str(args[4])
    var copy_source: String = str(args[5])
    var copy_target: String = str(args[6])

    var resolved_valid: String = str(capture.call("_resolve_output_dir", "res://artifacts/validation-previews/focused-nine/probe"))
    _expect(resolved_valid == valid_path, "valid intended output path")
    _expect(str(capture.call("_resolve_output_dir", outside_path)).is_empty(), "outside-root output")
    _expect(str(capture.call("_resolve_output_dir", traversal_path)).is_empty(), "traversal output")
    var prepared_escape: String = str(capture.call("_prepare_output_dir", symlink_path))
    _expect(prepared_escape.is_empty(), "symlink escape output")
    _expect(not DirAccess.dir_exists_absolute(outside_escape_path), "symlink escape wrote outside root")

    var prepared_valid: String = str(capture.call("_prepare_output_dir", valid_path))
    _expect(not prepared_valid.is_empty(), "valid output preparation")
    _expect(DirAccess.dir_exists_absolute(valid_path), "valid output directory created")
    var copied_ok: bool = capture.call("_copy_stable_frame", copy_source, copy_target)
    _expect(copied_ok, "stable copy")
    _expect(FileAccess.get_file_as_bytes(copy_source) == FileAccess.get_file_as_bytes(copy_target), "stable copy bytes")
    capture.free()

    print(PASS_MARKER)
    quit(0)
""",
        encoding="utf-8",
    )


def test_capture_behavioral_probe_exercises_parser_containment_and_stable_copy() -> None:
    with tempfile.TemporaryDirectory(prefix="task7-capture-probe-") as temporary:
        root = Path(temporary).resolve()
        project = root / "project"
        project.mkdir()
        probe = root / "task7_capture_behavioral_probe.gd"
        _write_behavioral_probe(project, probe)

        approved = project / "artifacts/validation-previews/focused-nine"
        nonempty_parent = approved / "nonempty"
        nonempty_parent.mkdir(parents=True)
        outside_root = root / "outside-root"
        outside_root.mkdir()
        escape = nonempty_parent / "escape"
        escape.symlink_to(outside_root, target_is_directory=True)

        valid_path = (approved / "probe").resolve()
        outside_path = root / "outside-root-request"
        traversal_path = approved / ".." / "traversal-escape"
        symlink_path = escape / "new-output"
        outside_escape_path = outside_root / "new-output"
        copy_source = root / "first-frame.bin"
        copy_target = root / "stable-frame.bin"
        copy_source.write_bytes(b"stable-frame-probe")

        result = subprocess.run(
            [
                GODOT,
                "--headless",
                "--path",
                str(project),
                "--script",
                str(probe),
                "--",
                str(valid_path),
                str(outside_path),
                str(traversal_path),
                str(symlink_path),
                str(outside_escape_path),
                str(copy_source),
                str(copy_target),
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        output = result.stdout + result.stderr

        assert result.returncode == 0, output
        assert "TASK7_CAPTURE_BEHAVIORAL_PROBE PASS" in output
        assert not re.search(r"\b(?:SCRIPT ERROR|ERROR|WARNING)\b", output), output
        assert not outside_escape_path.exists()
