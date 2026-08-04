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


def test_capture_publishes_fixed_leaves_via_verified_atomic_temporary_files() -> None:
    source = _source(CAPTURE_SCRIPT)

    assert 'const TEST_COMMAND := "/bin/test"' in source
    assert '_native_test_flag("-L", path)' in source
    assert '_native_test_flag("-e", path)' in source
    assert "PackedStringArray([flag, path])" in source
    assert "rename_absolute" in source
    assert "_validate_publication_leaf" in source
    assert "_temporary" in source
    assert "save_png(first_frame_path)" not in source
    assert "copy_absolute(first_frame_path, stable_path)" not in source


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


func _expect_no_temporary_files(directory: String, reason: String) -> void:
    for name: String in DirAccess.get_files_at(directory):
        _expect(not name.begins_with(".focused-nine-comparison"), reason)


func _init() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    _expect(args.size() == 10, "probe arguments")
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
    var end_marker: Dictionary = capture.call(
        "_parse_user_args",
        PackedStringArray(["--output-dir", "res://artifacts/validation-previews/focused-nine/probe", "--"]),
    )
    _expect(end_marker.has("error") and str(end_marker["error"]).contains("unexpected argument --"), "unexpected end marker")
    var option_after_end_marker: Dictionary = capture.call(
        "_parse_user_args",
        PackedStringArray(["--", "--output-dir", "res://artifacts/validation-previews/focused-nine/probe"]),
    )
    _expect(
        option_after_end_marker.has("error") and str(option_after_end_marker["error"]).contains("unexpected argument --"),
        "option after unexpected end marker",
    )

    var valid_path: String = str(args[0])
    var outside_path: String = str(args[1])
    var traversal_path: String = str(args[2])
    var symlink_path: String = str(args[3])
    var outside_escape_path: String = str(args[4])
    var outside_first_leaf: String = str(args[5])
    var outside_stable_leaf: String = str(args[6])
    var first_leaf: String = str(args[7])
    var stable_leaf: String = str(args[8])
    var normal_path: String = str(args[9])

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
    capture.free()

    var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.25, 0.5, 0.75, 1.0))
    var outside_first_before: PackedByteArray = FileAccess.get_file_as_bytes(outside_first_leaf)
    var outside_stable_before: PackedByteArray = FileAccess.get_file_as_bytes(outside_stable_leaf)

    var symlink_capture = CaptureScript.new()
    symlink_capture.set("_output_dir_global", prepared_valid)
    var symlink_publish_ok: bool = symlink_capture.call("_publish_capture_files", image)
    _expect(not symlink_publish_ok, "fixed symlink leaves rejected before publication")
    _expect(FileAccess.get_file_as_bytes(outside_first_leaf) == outside_first_before, "first symlink target changed")
    _expect(FileAccess.get_file_as_bytes(outside_stable_leaf) == outside_stable_before, "stable symlink target changed")
    _expect(FileAccess.file_exists(first_leaf) and FileAccess.file_exists(stable_leaf), "symlink leaves disappeared")
    _expect(
        FileAccess.get_file_as_bytes(first_leaf) == outside_first_before and FileAccess.get_file_as_bytes(stable_leaf) == outside_stable_before,
        "symlink leaves were written through",
    )
    _expect_no_temporary_files(prepared_valid, "temporary file leakage after rejection")
    symlink_capture.free()

    var normal_capture = CaptureScript.new()
    var prepared_normal: String = str(normal_capture.call("_prepare_output_dir", normal_path))
    _expect(not prepared_normal.is_empty(), "normal output preparation")
    normal_capture.set("_output_dir_global", prepared_normal)
    var old_first: FileAccess = FileAccess.open(prepared_normal.path_join("focused-nine-comparison00000000.png"), FileAccess.WRITE)
    var old_stable: FileAccess = FileAccess.open(prepared_normal.path_join("focused-nine-comparison.png"), FileAccess.WRITE)
    _expect(old_first != null and old_stable != null, "regular replacement leaves")
    old_first.store_buffer(PackedByteArray([1, 2, 3]))
    old_stable.store_buffer(PackedByteArray([4, 5, 6]))
    old_first = null
    old_stable = null
    var published_ok: bool = normal_capture.call("_publish_capture_files", image)
    _expect(published_ok, "normal temp-to-rename publication")
    var first_bytes: PackedByteArray = FileAccess.get_file_as_bytes(prepared_normal.path_join("focused-nine-comparison00000000.png"))
    var stable_bytes: PackedByteArray = FileAccess.get_file_as_bytes(prepared_normal.path_join("focused-nine-comparison.png"))
    _expect(not first_bytes.is_empty() and first_bytes == stable_bytes, "published bytes")
    _expect_no_temporary_files(prepared_normal, "temporary file leakage after publication")
    normal_capture.free()

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
        outside_first_leaf = outside_root / "outside-first.png"
        outside_stable_leaf = outside_root / "outside-stable.png"
        outside_first_leaf.write_bytes(b"outside-first-original")
        outside_stable_leaf.write_bytes(b"outside-stable-original")
        valid_path.mkdir(parents=True)
        (valid_path / "focused-nine-comparison00000000.png").symlink_to(outside_first_leaf)
        (valid_path / "focused-nine-comparison.png").symlink_to(outside_stable_leaf)
        normal_path = approved / "normal"

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
                str(outside_first_leaf),
                str(outside_stable_leaf),
                str(valid_path / "focused-nine-comparison00000000.png"),
                str(valid_path / "focused-nine-comparison.png"),
                str(normal_path),
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
        assert outside_first_leaf.read_bytes() == b"outside-first-original"
        assert outside_stable_leaf.read_bytes() == b"outside-stable-original"
        assert not list(normal_path.glob(".focused-nine-comparison*"))
