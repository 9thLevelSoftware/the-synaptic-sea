from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CAPTURE_SCRIPT = PROJECT_ROOT / "scripts/validation/focused_nine_airlock_control_room_capture.gd"
HARNESS_SCENE = PROJECT_ROOT / "scenes/validation/focused_nine_airlock_control_room_harness.tscn"
GODOT = "/opt/homebrew/bin/godot"


def _source(path: Path) -> str:
    if not path.is_file():
        pytest.fail(f"expected Task 1 file is missing: {path}")
    return path.read_text(encoding="utf-8")


def test_room_capture_is_staged_only_and_declares_every_required_asset() -> None:
    source = _source(CAPTURE_SCRIPT)

    assert 'const STAGED_ROOT := "res://assets/_staging/focused_nine/"' in source
    assert "assets/imported" not in source
    for path in (
        "structural/floor_1x1/floor_1x1.glb",
        "structural/wall_straight_1x1/wall_straight_1x1.glb",
        "structural/doorway_frame_open_1x1/doorway_frame_open_1x1.glb",
        "structural/pillar_support_1x1/pillar_support_1x1.glb",
        "structural/ramp_up_1x2/ramp_up_1x2.glb",
        "structural/ceiling_cap_1x1/ceiling_cap_1x1.glb",
        "structural/pressure_door_1x1/pressure_door_1x1.glb",
        "props/hull_breach_seal_point.glb",
        "props/fire_suppression_station.glb",
    ):
        assert path in source
    assert "GLTFDocument" in source
    assert "append_from_file" in source
    assert "generate_scene" in source


def test_room_scene_has_exact_roots_locked_iso_camera_and_no_runtime_aliases() -> None:
    scene = _source(HARNESS_SCENE)

    for node_name in (
        "RoomCamera",
        "RoomKeyLight",
        "RoomFillLight",
        "RoomEnvironment",
        "Room",
    ):
        assert f'name="{node_name}"' in scene
    assert 'name="RoomCamera" type="Camera3D"' in scene
    assert "projection = 1" in scene and "size = 18.0" in scene
    assert 'name="Baseline"' not in scene
    assert 'name="Improved"' not in scene
    assert "assets/imported" not in scene
    assert "scenes/wrappers" not in scene
    assert 'type="Label"' not in scene
    assert 'type="Label3D"' not in scene
    assert "1600" in _source(CAPTURE_SCRIPT) and "900" in _source(CAPTURE_SCRIPT)


def test_layout_declares_exact_nine_floor_coordinates_and_composes_room_landmarks() -> None:
    source = _source(CAPTURE_SCRIPT)

    expected_coordinates = (
        "Vector3(-4.0, 0.0, -4.0)",
        "Vector3(0.0, 0.0, -4.0)",
        "Vector3(4.0, 0.0, -4.0)",
        "Vector3(-4.0, 0.0, 0.0)",
        "Vector3(0.0, 0.0, 0.0)",
        "Vector3(4.0, 0.0, 0.0)",
        "Vector3(-4.0, 0.0, 4.0)",
        "Vector3(0.0, 0.0, 4.0)",
        "Vector3(4.0, 0.0, 4.0)",
    )
    assert "const FLOOR_LAYOUT" in source
    assert all(coordinate in source for coordinate in expected_coordinates)
    assert re.search(r"for\s+index\s+in\s+FLOOR_LAYOUT\.size\(\)", source)
    for landmark in (
        "doorway",
        "ramp",
        "pressure_door",
        "wall",
        "pillar",
        "ceiling",
        "fire_suppression",
        "hull_breach",
    ):
        assert landmark in source.lower()
    assert "south" in source.lower()
    assert "north" in source.lower()
    assert "east" in source.lower()
    assert "rear" in source.lower()


def test_capture_parser_accepts_only_output_dir_and_rejects_unsafe_paths() -> None:
    source = _source(CAPTURE_SCRIPT)

    assert '"--output-dir"' in source
    assert "duplicate option" in source
    assert "unknown argument" in source
    assert "missing --output-dir DIR" in source
    assert "unexpected argument --" in source
    assert 'APPROVED_OUTPUT_ROOT := "res://artifacts/validation-previews/focused-nine"' in source
    assert "same-user concurrent filesystem mutation/rebinding" in source
    assert "defense-in-depth" in source
    assert "cannot pin Godot filesystem operations" in source
    assert "assets/imported" not in source
    assert "_contains_symlink_component" in source
    assert "missing staged source component" in source
    assert "symlinked staged source component" in source
    assert 'DisplayServer.get_name() == "headless"' in source


def test_capture_publishes_equal_nonempty_fixed_leaf_with_hidden_siblings() -> None:
    source = _source(CAPTURE_SCRIPT)

    assert "FOCUSED_NINE_AIRLOCK_ROOM_CAPTURE PASS output=" in source
    assert "FOCUSED_NINE_AIRLOCK_ROOM_CAPTURE FAIL reason=" in source
    assert "focused-nine-airlock-control-room00000000.png" in source
    assert "focused-nine-airlock-control-room.png" in source
    assert "rename_absolute" in source
    assert "_validate_publication_leaf" in source
    assert "_temporary" in source
    assert "get_file_as_bytes" in source
    assert re.search(r"stable_bytes\s*!=\s*frame_bytes|frame_bytes\s*!=\s*stable_bytes", source)
    assert "image.is_empty()" in source
    assert "image.get_width()" in source
    assert "image.get_height()" in source
    assert "get_viewport().get_root()" not in source
    assert "--write-movie" not in source


def test_capture_recursively_disables_embedded_local_lights() -> None:
    source = _source(CAPTURE_SCRIPT)
    helper = re.search(
        r"func _disable_local_lights\(node: Node\) -> void:(?P<body>.*?)(?=\n\nfunc |\Z)",
        source,
        flags=re.DOTALL,
    )

    assert helper is not None
    helper_body = helper.group("body")
    assert "if node is Light3D" in helper_body
    assert "if child is Light3D" in helper_body
    assert "child.visible = false" in helper_body
    assert "_disable_local_lights(child)" in helper_body
    assert "_disable_local_lights(visual)" in source


def _write_probe_project(project: Path, probe: Path) -> None:
    (project / "scripts/validation").mkdir(parents=True)
    shutil.copy2(CAPTURE_SCRIPT, project / "scripts/validation/focused_nine_airlock_control_room_capture.gd")
    (project / "project.godot").write_text(
        "\n".join(
            (
                "; Task 1 behavioral probe project",
                "config_version=5",
                "",
                "[application]",
                'config/name="Task 1 Capture Probe"',
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

const CaptureScript: GDScript = preload("res://scripts/validation/focused_nine_airlock_control_room_capture.gd")
const PASS_MARKER := "TASK1_CAPTURE_BEHAVIORAL_PROBE PASS"


func _expect(condition: bool, reason: String) -> void:
    if condition:
        return
    printerr("TASK1_CAPTURE_BEHAVIORAL_PROBE FAIL reason=%s" % reason)
    quit(1)


func _expect_no_temporary_files(directory: String, reason: String) -> void:
    for name: String in DirAccess.get_files_at(directory):
        _expect(not name.begins_with(".focused-nine-airlock-control-room"), reason)


func _init() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    _expect(args.size() == 9, "probe arguments")
    var capture = CaptureScript.new()

    var valid: Dictionary = capture.call(
        "_parse_user_args",
        PackedStringArray(["--output-dir", "res://artifacts/validation-previews/focused-nine/probe"]),
    )
    _expect(not valid.has("error"), "valid parser args")
    _expect(str(valid["output_dir"]).ends_with("focused-nine/probe"), "valid output option")

    var missing: Dictionary = capture.call("_parse_user_args", PackedStringArray([]))
    _expect(missing.has("error") and str(missing["error"]).contains("missing --output-dir"), "missing option")
    var missing_value: Dictionary = capture.call("_parse_user_args", PackedStringArray(["--output-dir"]))
    _expect(missing_value.has("error") and str(missing_value["error"]).contains("missing value"), "missing value")
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

    var valid_path: String = str(args[0])
    var outside_path: String = str(args[1])
    var traversal_path: String = str(args[2])
    var symlink_path: String = str(args[3])
    var outside_escape_path: String = str(args[4])
    var outside_first_leaf: String = str(args[5])
    var outside_stable_leaf: String = str(args[6])
    var missing_staged: String = str(args[7])
    var symlink_staged: String = str(args[8])

    _expect(str(capture.call("_resolve_output_dir", "res://artifacts/validation-previews/focused-nine/probe")) == valid_path, "valid intended output path")
    _expect(str(capture.call("_resolve_output_dir", outside_path)).is_empty(), "outside-root output")
    _expect(str(capture.call("_resolve_output_dir", traversal_path)).is_empty(), "traversal output")
    var prepared_escape: String = str(capture.call("_prepare_output_dir", symlink_path))
    _expect(prepared_escape.is_empty(), "symlink escape output")
    _expect(not DirAccess.dir_exists_absolute(outside_escape_path), "symlink escape wrote outside root")
    _expect(not bool(capture.call("_validate_staged_component", missing_staged)), "missing staged component")
    _expect(not bool(capture.call("_validate_staged_component", symlink_staged)), "symlink staged component")
    capture.free()

    var valid_dir: String = valid_path
    var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.25, 0.5, 0.75, 1.0))
    var outside_first_before: PackedByteArray = FileAccess.get_file_as_bytes(outside_first_leaf)
    var outside_stable_before: PackedByteArray = FileAccess.get_file_as_bytes(outside_stable_leaf)

    var symlink_capture = CaptureScript.new()
    symlink_capture.set("_output_dir_global", valid_dir)
    var symlink_publish_ok: bool = symlink_capture.call("_publish_capture_files", image)
    _expect(not symlink_publish_ok, "fixed symlink leaves rejected before publication")
    _expect(FileAccess.get_file_as_bytes(outside_first_leaf) == outside_first_before, "first symlink target changed")
    _expect(FileAccess.get_file_as_bytes(outside_stable_leaf) == outside_stable_before, "stable symlink target changed")
    _expect(FileAccess.file_exists(valid_dir.path_join("focused-nine-airlock-control-room00000000.png")), "first symlink leaf disappeared")
    _expect(FileAccess.file_exists(valid_dir.path_join("focused-nine-airlock-control-room.png")), "stable symlink leaf disappeared")
    _expect_no_temporary_files(valid_dir, "temporary file leakage after rejection")
    symlink_capture.free()

    var normal_path: String = valid_dir.get_base_dir().path_join("normal")
    var normal_capture = CaptureScript.new()
    var prepared_normal: String = str(normal_capture.call("_prepare_output_dir", normal_path))
    _expect(not prepared_normal.is_empty(), "normal output preparation")
    normal_capture.set("_output_dir_global", prepared_normal)
    var old_first: FileAccess = FileAccess.open(prepared_normal.path_join("focused-nine-airlock-control-room00000000.png"), FileAccess.WRITE)
    var old_stable: FileAccess = FileAccess.open(prepared_normal.path_join("focused-nine-airlock-control-room.png"), FileAccess.WRITE)
    _expect(old_first != null and old_stable != null, "regular replacement leaves")
    old_first.store_buffer(PackedByteArray([1, 2, 3]))
    old_stable.store_buffer(PackedByteArray([4, 5, 6]))
    old_first = null
    old_stable = null
    var published_ok: bool = normal_capture.call("_publish_capture_files", image)
    _expect(published_ok, "normal temp-to-rename publication")
    var first_bytes: PackedByteArray = FileAccess.get_file_as_bytes(prepared_normal.path_join("focused-nine-airlock-control-room00000000.png"))
    var stable_bytes: PackedByteArray = FileAccess.get_file_as_bytes(prepared_normal.path_join("focused-nine-airlock-control-room.png"))
    _expect(not first_bytes.is_empty() and first_bytes == stable_bytes, "published bytes")
    _expect_no_temporary_files(prepared_normal, "temporary file leakage after publication")
    normal_capture.free()

    print(PASS_MARKER)
    quit(0)
""",
        encoding="utf-8",
    )


def test_capture_behavioral_probe_exercises_parser_sources_containment_and_publication() -> None:
    with tempfile.TemporaryDirectory(prefix="task1-capture-probe-") as temporary:
        root = Path(temporary).resolve()
        project = root / "project"
        project.mkdir()
        probe = root / "task1_capture_behavioral_probe.gd"
        _write_probe_project(project, probe)

        approved = project / "artifacts/validation-previews/focused-nine"
        approved.mkdir(parents=True)
        outside_root = root / "outside-root"
        outside_root.mkdir()
        escape = approved / "escape"
        escape.symlink_to(outside_root, target_is_directory=True)

        valid_path = approved / "probe"
        valid_path.mkdir()
        outside_path = root / "outside-root-request"
        traversal_path = approved / ".." / "traversal-escape"
        symlink_path = escape / "new-output"
        outside_escape_path = outside_root / "new-output"
        outside_first_leaf = outside_root / "outside-first.png"
        outside_stable_leaf = outside_root / "outside-stable.png"
        outside_first_leaf.write_bytes(b"outside-first-original")
        outside_stable_leaf.write_bytes(b"outside-stable-original")
        (valid_path / "focused-nine-airlock-control-room00000000.png").symlink_to(outside_first_leaf)
        (valid_path / "focused-nine-airlock-control-room.png").symlink_to(outside_stable_leaf)

        staged = project / "assets/_staging/focused_nine/structural/floor_1x1"
        staged.mkdir(parents=True)
        (staged / "floor_1x1.glb").write_bytes(b"not-a-real-glb")
        staged_outside = root / "staged-outside"
        staged_outside.mkdir()
        (staged_outside / "wall_straight_1x1.glb").write_bytes(b"not-a-real-glb")
        symlink_staged_dir = project / "assets/_staging/focused_nine/structural/wall_straight_1x1"
        symlink_staged_dir.symlink_to(staged_outside, target_is_directory=True)

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
                "res://assets/_staging/focused_nine/structural/missing/missing.glb",
                "res://assets/_staging/focused_nine/structural/wall_straight_1x1/wall_straight_1x1.glb",
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        output = result.stdout + result.stderr

        assert result.returncode == 0, output
        assert "TASK1_CAPTURE_BEHAVIORAL_PROBE PASS" in output
        assert not re.search(r"\b(?:SCRIPT ERROR|ERROR|WARNING)\b", output), output
        assert not outside_escape_path.exists()
        assert outside_first_leaf.read_bytes() == b"outside-first-original"
        assert outside_stable_leaf.read_bytes() == b"outside-stable-original"
        assert not list((valid_path.parent / "normal").glob(".focused-nine-airlock-control-room*")) if (valid_path.parent / "normal").exists() else True


def test_target_harness_editor_loads_without_godot_diagnostics() -> None:
    with tempfile.TemporaryDirectory(prefix="task1-scene-smoke-") as temporary:
        project = Path(temporary) / "project"
        (project / "scripts/validation").mkdir(parents=True)
        (project / "scenes/validation").mkdir(parents=True)
        shutil.copy2(CAPTURE_SCRIPT, project / "scripts/validation/focused_nine_airlock_control_room_capture.gd")
        shutil.copy2(HARNESS_SCENE, project / "scenes/validation/focused_nine_airlock_control_room_harness.tscn")
        (project / "project.godot").write_text(
            "\n".join(
                (
                    "config_version=5",
                    "",
                    "[application]",
                    'config/name="Task 1 Scene Smoke"',
                    'config/features=PackedStringArray("4.6", "GL Compatibility")',
                    "",
                    "[rendering]",
                    'renderer/rendering_method="gl_compatibility"',
                    "",
                )
            ),
            encoding="utf-8",
        )
        result = subprocess.run(
            [
                GODOT,
                "--headless",
                "--path",
                str(project),
                "--editor",
                "--quit",
                "--scene",
                "res://scenes/validation/focused_nine_airlock_control_room_harness.tscn",
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert not re.search(r"\b(?:SCRIPT ERROR|ERROR|WARNING)\b", output), output
