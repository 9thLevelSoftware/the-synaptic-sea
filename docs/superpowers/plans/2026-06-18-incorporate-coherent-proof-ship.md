# Coherent Proof Ship Main-Game Incorporation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the already-validated coherent proof ship from proof-only validation artifacts into the actual project main-scene runtime path, with main-path validation and a fresh in-engine viewport capture.

**Architecture:** Keep the coherent golden fixture and `PlayableGeneratedShip` loader/playable pipeline as the source of truth. Change only the project bootstrap so `res://scenes/main.tscn` instantiates `res://scenes/procgen/playable_coherent_ship.tscn` by default, then add focused validation scripts proving both main-scene boot and main-scene non-headless viewport capture. Preserve seed-17 as a regression target and record all evidence in the existing proof log.

**Tech Stack:** Godot 4.6.2 GDScript; `SceneTree` validation scripts; existing `PlayableGeneratedShip`, `GeneratedShipLoader`, `IsoCameraRig`, and `ship_structural_v0` kit; macOS `sips`, `shasum`, and `open` for capture artifact verification.

## Global Constraints

- Project root is `/Users/christopherwilloughby/the-sargasso-of-stars`.
- Godot binary is `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Main scene in `project.godot` remains `run/main_scene="res://scenes/main.tscn"`.
- The project path is not expected to be a git repository from the shell; every record step must use a commit-or-record fallback writing to `/tmp/sargasso_coherent_incorporation_no_git_changes.log` if `git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree` fails.
- Do not mutate seed-17 data: `data/procgen/smoke/seed_000017/layout.json` and `data/procgen/smoke/seed_000017/gameplay_slice.json`.
- Do not mutate the coherent golden fixture JSON: `data/procgen/golden/coherent_ship_001/layout.json` and `data/procgen/golden/coherent_ship_001/gameplay_slice.json`.
- Do not rewrite the procgen loader or playable scene internals: `scripts/procgen/generated_ship_loader.gd`, `scripts/procgen/playable_generated_ship.gd`, and `scenes/procgen/playable_coherent_ship.tscn` are out of scope.
- All viewport capture proof must be real Godot viewport output with `mode=viewport`; do not add synthetic-map fallback for the main-scene capture script.
- If the viewport image is visually sparse, record that as a staging/art limitation rather than changing fixture topology or art assets in this plan.

---

## File Structure

- `scripts/validation/main_coherent_boot_smoke.gd`
  - New headless smoke test for the actual `res://scenes/main.tscn` boot path.
  - Responsibility: instantiate `main.tscn`, find the nested `PlayableGeneratedShip`, assert it uses the coherent fixture, and assert core runtime metadata is ready.

- `scripts/main.gd`
  - Existing project bootstrap script.
  - Responsibility after this plan: instantiate the coherent playable scene by default, name it `PlayableCoherentShip`, and let that scene spawn the player/camera/interactables.

- `scenes/main.tscn`
  - Existing project main scene.
  - Responsibility after this plan: minimal root + light + `scripts/main.gd`; no stale current static camera competing with `IsoCameraRig`.

- `scripts/validation/main_coherent_capture.gd`
  - New non-headless viewport capture script for the actual `res://scenes/main.tscn` path.
  - Responsibility: instantiate `main.tscn`, wait for coherent playable readiness, capture root viewport, save PNG, and print `MAIN COHERENT CAPTURE PASS ... mode=viewport`.

- `docs/superpowers/proofs/coherent-proof-ship.md`
  - Existing proof log.
  - Responsibility after this plan: include main-scene incorporation evidence, final main-path validation bundle output, capture artifact metadata, and a checked acceptance list.

- `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png`
  - New generated artifact outside the repo.
  - Responsibility: human-viewable proof that the actual main-scene path renders in Godot.

---

### Task 1: Main-Scene Coherent Boot Smoke

**Files:**
- Create: `scripts/validation/main_coherent_boot_smoke.gd`

**Interfaces:**
- Consumes: `res://scenes/main.tscn`; `PlayableGeneratedShip.layout_path: String`; `PlayableGeneratedShip.loader`; `PlayableGeneratedShip.get_playable_summary() -> Dictionary`; `GeneratedShipLoader.get_critical_path() -> Array`; `GeneratedShipLoader.get_landmark_nodes() -> Array`.
- Produces: Validation pass marker `MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=<int> critical_path=<int> landmarks=<int> frames=<int>` for later proof-log tasks.

- [ ] **Step 1: Write the failing test script**

Create `scripts/validation/main_coherent_boot_smoke.gd` with this exact content:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const COHERENT_LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const EXPECTED_OBJECTIVES: int = 4
const EXPECTED_CRITICAL_PATH: int = 5
const EXPECTED_LANDMARKS: int = 2
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var frame_count: int = 0
var finished: bool = false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip child found under main scene")
		return
	if playable.layout_path != COHERENT_LAYOUT_PATH:
		_fail("expected coherent layout %s got %s" % [COHERENT_LAYOUT_PATH, playable.layout_path])
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("coherent playable loader did not finish")
		return
	var summary: Dictionary = playable.get_playable_summary()
	var objective_count: int = int(summary.get("objective_count", 0))
	var critical_path_count: int = playable.loader.get_critical_path().size()
	var landmark_count: int = playable.loader.get_landmark_nodes().size()
	if not bool(summary.get("player_spawned", false)):
		_fail("player not spawned")
		return
	if not bool(summary.get("camera_spawned", false)):
		_fail("camera not spawned")
		return
	if objective_count != EXPECTED_OBJECTIVES:
		_fail("expected %d objectives got %d" % [EXPECTED_OBJECTIVES, objective_count])
		return
	if critical_path_count != EXPECTED_CRITICAL_PATH:
		_fail("expected critical_path=%d got %d" % [EXPECTED_CRITICAL_PATH, critical_path_count])
		return
	if landmark_count < EXPECTED_LANDMARKS:
		_fail("expected landmarks>=%d got %d" % [EXPECTED_LANDMARKS, landmark_count])
		return
	print("MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=%d critical_path=%d landmarks=%d frames=%d" % [objective_count, critical_path_count, landmark_count, frame_count])
	finished = true
	quit(0)


func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN COHERENT BOOT FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails for the expected reason**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-sargasso-of-stars \
  --script res://scripts/validation/main_coherent_boot_smoke.gd
```

Expected: exit code `1` with this substring, because `scripts/main.gd` still boots `res://scenes/procgen/playable_generated_ship.tscn` and therefore uses seed-17:

```text
MAIN COHERENT BOOT FAIL reason=expected coherent layout res://data/procgen/golden/coherent_ship_001/layout.json got res://data/procgen/smoke/seed_000017/layout.json
```

If the command fails with a parser error instead, fix the parser error in `scripts/validation/main_coherent_boot_smoke.gd` and rerun until it fails for the expected layout-path reason.

- [ ] **Step 3: Record Task 1**

Run:

```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/validation/main_coherent_boot_smoke.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m "test: add main coherent boot smoke"
else
  printf '%s\n' 'NO_GIT Incorporation Task 1 changed: scripts/validation/main_coherent_boot_smoke.gd' >> /tmp/sargasso_coherent_incorporation_no_git_changes.log
fi
```

---

### Task 2: Main Scene Boots the Coherent Playable Ship

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn`
- Test: `scripts/validation/main_coherent_boot_smoke.gd`

**Interfaces:**
- Consumes: `res://scenes/procgen/playable_coherent_ship.tscn`, which is a `PlayableGeneratedShip` scene with coherent fixture exports already set.
- Produces: `scripts/main.gd` exported property `playable_ship_scene: PackedScene`; runtime child named `PlayableCoherentShip`; `scenes/main.tscn` without a competing current `LockedIsoCamera`.

- [ ] **Step 1: Replace `scripts/main.gd` with the minimal coherent bootstrap**

Replace the entire file `scripts/main.gd` with:

```gdscript
extends Node3D

const DEFAULT_PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")

@export var playable_ship_scene: PackedScene = DEFAULT_PLAYABLE_SHIP_SCENE

var playable_instance: PlayableGeneratedShip


func _ready() -> void:
	print("The Sargasso of Stars coherent proof ship bootstrap loaded.")
	if playable_ship_scene == null:
		push_error("MAIN BOOT FAIL reason=missing playable_ship_scene")
		return
	playable_instance = playable_ship_scene.instantiate() as PlayableGeneratedShip
	if playable_instance == null:
		push_error("MAIN BOOT FAIL reason=playable scene is not PlayableGeneratedShip")
		return
	playable_instance.name = "PlayableCoherentShip"
	add_child(playable_instance)
```

- [ ] **Step 2: Replace `scenes/main.tscn` with a minimal root and light**

Replace the entire file `scenes/main.tscn` with:

```text
[gd_scene load_steps=2 format=3 uid="uid://sargasso_main"]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]

[node name="Main" type="Node3D"]
script = ExtResource("1_main")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.25, 0.433013, 0, 0.866025, 0.5, -0.5, -0.433013, 0.75, 0, 8, 0)
light_energy = 1.5
```

Reason: `PlayableGeneratedShip` spawns an `IsoCameraRig` and current `PlayableIsoCamera` after loading. Keeping the old static `LockedIsoCamera` risks capturing or playing through the wrong camera.

- [ ] **Step 3: Run the main boot smoke to verify it passes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-sargasso-of-stars \
  --script res://scripts/validation/main_coherent_boot_smoke.gd
```

Expected: exit code `0` and output contains:

```text
The Sargasso of Stars coherent proof ship bootstrap loaded.
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4 collision_shapes=31
MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2
```

The `frames=` value at the end of the pass marker may vary and is not part of the acceptance comparison.

- [ ] **Step 4: Run direct coherent-scene and seed-17 regression smokes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/coherent_playable_scene_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/procgen_playable_ship_smoke.gd
```

Expected pass markers:

```text
COHERENT PLAYABLE SCENE PASS frames=1
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 5: Record Task 2**

Run:

```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/main.gd scenes/main.tscn
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m "feat: boot coherent proof ship from main scene"
else
  printf '%s\n' 'NO_GIT Incorporation Task 2 changed: scripts/main.gd scenes/main.tscn' >> /tmp/sargasso_coherent_incorporation_no_git_changes.log
fi
```

---

### Task 3: Main-Scene Viewport Capture

**Files:**
- Create: `scripts/validation/main_coherent_capture.gd`
- Artifact: `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png`

**Interfaces:**
- Consumes: `res://scenes/main.tscn`; `PlayableGeneratedShip.loader.has_loaded_ship() -> bool`; root viewport texture from `get_root().get_texture()`.
- Produces: Pass marker `MAIN COHERENT CAPTURE PASS output=<absolute png path> frame=<int> mode=viewport`; 1280x720 PNG at the requested output path.

- [ ] **Step 1: Run the capture command to verify it fails before the script exists**

Run:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-sargasso-of-stars \
  --script res://scripts/validation/main_coherent_capture.gd \
  -- \
  --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png \
  --capture-frame 180
```

Expected: exit code `1` or Godot script-load failure because `res://scripts/validation/main_coherent_capture.gd` does not exist.

- [ ] **Step 2: Create `scripts/validation/main_coherent_capture.gd`**

Create `scripts/validation/main_coherent_capture.gd` with this exact content:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_OUTPUT_PATH: String = "res://artifacts/validation-previews/main-coherent-proof-ship.png"
const DEFAULT_CAPTURE_FRAME: int = 180
const POST_READY_SETTLE_FRAMES: int = 6
const TIMEOUT_FRAMES: int = 360

var output_path: String = DEFAULT_OUTPUT_PATH
var capture_frame: int = DEFAULT_CAPTURE_FRAME
var frame_count: int = 0
var finished: bool = false
var main_node: Node
var playable_ship: PlayableGeneratedShip
var post_ready_settle_remaining: int = -1


func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail("arg_parse %s" % parsed["error"])
		return
	output_path = parsed.get("output", DEFAULT_OUTPUT_PATH)
	capture_frame = int(parsed.get("capture_frame", DEFAULT_CAPTURE_FRAME))
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--output":
			if index + 1 >= args.size():
				result["error"] = "missing value for --output"
				return result
			result["output"] = args[index + 1]
			index += 2
			continue
		if token == "--capture-frame":
			if index + 1 >= args.size():
				result["error"] = "missing value for --capture-frame"
				return result
			var value: String = args[index + 1]
			if not value.is_valid_int():
				result["error"] = "--capture-frame must be an integer"
				return result
			result["capture_frame"] = int(value)
			index += 2
			continue
		index += 1
	if not result.has("output"):
		result["error"] = "missing --output <png>"
	return result


func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable_ship == null:
		playable_ship = _find_playable(main_node)
	if playable_ship == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip child found under main")
		return
	if playable_ship.loader == null or not playable_ship.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable loader did not finish")
		return
	if post_ready_settle_remaining < 0:
		post_ready_settle_remaining = POST_READY_SETTLE_FRAMES
		return
	if post_ready_settle_remaining > 0:
		post_ready_settle_remaining -= 1
		return
	if frame_count < capture_frame:
		return
	_capture_and_finish()


func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null


func _capture_and_finish() -> void:
	finished = true
	var image: Image = _capture_viewport_image()
	if image == null:
		_fail("viewport_texture_unavailable display=%s headless=%s" % [DisplayServer.get_name(), str(DisplayServer.get_name() == "headless")])
		return
	var resolved_path: String = ProjectSettings.globalize_path(output_path) if output_path.begins_with("res://") else output_path
	var base_dir: String = resolved_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var save_error: int = image.save_png(resolved_path)
	if save_error != OK:
		_fail("save_png error=%d output=%s" % [save_error, resolved_path])
		return
	print("MAIN COHERENT CAPTURE PASS output=%s frame=%d mode=viewport" % [resolved_path, frame_count])
	quit(0)


func _capture_viewport_image() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var texture: ViewportTexture = get_root().get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	return image


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN COHERENT CAPTURE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 3: Run the non-headless capture to verify it passes**

Run:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-sargasso-of-stars \
  --script res://scripts/validation/main_coherent_capture.gd \
  -- \
  --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png \
  --capture-frame 180
```

Expected: exit code `0` and output contains:

```text
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M4 (Apple9)
MAIN COHERENT CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png frame=180 mode=viewport
```

- [ ] **Step 4: Verify capture metadata and hash**

Run:

```bash
sips -g pixelWidth -g pixelHeight -g format /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
printf '\nsha256: '
shasum -a 256 /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png | awk '{print $1}'
```

Expected:

```text
/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
  pixelWidth: 1280
  pixelHeight: 720
  format: png
sha256:
```

The `sha256:` line must be followed by exactly one 64-character lowercase hexadecimal hash.

- [ ] **Step 5: Open the PNG for human review**

Run:

```bash
open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
```

Expected: exit code `0`.

- [ ] **Step 6: Record Task 3**

Run:

```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/validation/main_coherent_capture.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m "test: capture coherent ship through main scene"
else
  printf '%s\n' 'NO_GIT Incorporation Task 3 changed: scripts/validation/main_coherent_capture.gd' >> /tmp/sargasso_coherent_incorporation_no_git_changes.log
fi
```

---

### Task 4: Main-Scene Incorporation Proof Log

**Files:**
- Modify: `docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes: Task 1 `MAIN COHERENT BOOT PASS` output; Task 3 `MAIN COHERENT CAPTURE PASS` output; Task 3 PNG metadata and hash.
- Produces: Proof-log section `## Main-Scene Incorporation` and pass marker `MAIN INCORPORATION PROOF LOG PASS markers=5`.

- [ ] **Step 1: Append proof-log evidence using captured command outputs**

Run this shell block from `/Users/christopherwilloughby/the-sargasso-of-stars`:

```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
ARTIFACT=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
PROOF=$ROOT/docs/superpowers/proofs/coherent-proof-ship.md
BOOT_LOG=$(mktemp)
CAPTURE_LOG=$(mktemp)
META_LOG=$(mktemp)

$GODOT --headless --path "$ROOT" --script res://scripts/validation/main_coherent_boot_smoke.gd | tee "$BOOT_LOG"
$GODOT --path "$ROOT" --script res://scripts/validation/main_coherent_capture.gd -- --output "$ARTIFACT" --capture-frame 180 | tee "$CAPTURE_LOG"
sips -g pixelWidth -g pixelHeight -g format "$ARTIFACT" | tee "$META_LOG"
CAPTURE_SHA=$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')
OPEN_STATUS=not_run
if open "$ARTIFACT"; then
  OPEN_STATUS=exit_0
else
  OPEN_STATUS=failed
fi

python3 - <<'PY' "$PROOF" "$BOOT_LOG" "$CAPTURE_LOG" "$META_LOG" "$CAPTURE_SHA" "$ARTIFACT" "$OPEN_STATUS"
from pathlib import Path
import sys
proof_path = Path(sys.argv[1])
boot_log = Path(sys.argv[2]).read_text().strip()
capture_log = Path(sys.argv[3]).read_text().strip()
meta_log = Path(sys.argv[4]).read_text().strip()
sha = sys.argv[5]
artifact = sys.argv[6]
open_status = sys.argv[7]
if len(sha) != 64 or any(c not in '0123456789abcdef' for c in sha):
    raise SystemExit(f'invalid sha256: {sha}')
section = f'''

## Main-Scene Incorporation

The coherent proof ship is now the default playable scene instantiated by `res://scenes/main.tscn`, the project `run/main_scene` path from `project.godot`. `scripts/main.gd` instantiates `res://scenes/procgen/playable_coherent_ship.tscn` by default and `scenes/main.tscn` no longer keeps a stale current `LockedIsoCamera`; the playable scene creates the active `PlayableIsoCamera` through `IsoCameraRig`.

Main boot smoke:

```text
{boot_log}
```

Main-scene viewport capture:

```text
{capture_log}
```

Main-scene capture artifact:

```text
{meta_log}
sha256: {sha}
```

Human review note: `open {artifact}` returned `{open_status}`. This is a real Godot viewport capture through `scenes/main.tscn` (`mode=viewport`), not an HTML/mockup or synthetic diagnostic map.
'''
text = proof_path.read_text()
if '## Main-Scene Incorporation' in text:
    before = text.split('\n## Main-Scene Incorporation\n', 1)[0]
    proof_path.write_text(before.rstrip() + section + '\n')
else:
    proof_path.write_text(text.rstrip() + section + '\n')
PY
```

Expected: both embedded command runs exit `0`, `open` returns `exit_0`, and the proof log contains the new `## Main-Scene Incorporation` section.

- [ ] **Step 2: Verify the proof log contains the required markers**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
p = Path('/Users/christopherwilloughby/the-sargasso-of-stars/docs/superpowers/proofs/coherent-proof-ship.md')
text = p.read_text()
required = [
    '## Main-Scene Incorporation',
    'MAIN COHERENT BOOT PASS',
    'MAIN COHERENT CAPTURE PASS',
    'mode=viewport',
    'main_coherent_viewport.png',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('missing proof markers: ' + ', '.join(missing))
print('MAIN INCORPORATION PROOF LOG PASS markers=%d' % len(required))
PY
```

Expected:

```text
MAIN INCORPORATION PROOF LOG PASS markers=5
```

- [ ] **Step 3: Record Task 4**

Run:

```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m "docs: record coherent ship main-scene incorporation"
else
  printf '%s\n' 'NO_GIT Incorporation Task 4 changed: docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/sargasso_coherent_incorporation_no_git_changes.log
fi
```

---

### Task 5: Final Main-Path Regression and Acceptance Record

**Files:**
- Modify: `docs/superpowers/proofs/coherent-proof-ship.md`

**Interfaces:**
- Consumes: all validation scripts from prior tasks plus existing coherent and seed-17 validation scripts.
- Produces: Final proof-log section `## Final Main-Path Incorporation Checklist` with all acceptance items checked and evidence-backed.

- [ ] **Step 1: Run the coherent + main validation bundle**

Run:

```bash
set -o pipefail
for script in \
  res://scripts/validation/coherent_static_fixture_validator.gd \
  res://scripts/validation/coherent_loader_metadata_smoke.gd \
  res://scripts/validation/coherent_runtime_loader_smoke.gd \
  res://scripts/validation/coherent_playable_scene_smoke.gd \
  res://scripts/validation/coherent_playable_traversal_smoke.gd \
  res://scripts/validation/main_coherent_boot_smoke.gd; do
  echo "=== $script ==="
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 \
    --headless \
    --path /Users/christopherwilloughby/the-sargasso-of-stars \
    --script "$script"
done
```

Expected pass markers:

```text
COHERENT STATIC FIXTURE PASS
COHERENT LOADER METADATA PASS
COHERENT RUNTIME LOADER PASS
COHERENT PLAYABLE SCENE PASS
COHERENT PLAYABLE TRAVERSAL PASS
MAIN COHERENT BOOT PASS
```

- [ ] **Step 2: Run the existing regression bundle**

Run:

```bash
set -o pipefail
for script in \
  res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd \
  res://scripts/validation/player_gravity_floor_snap_smoke.gd \
  res://scripts/validation/interactable_distance_fallback_smoke.gd \
  res://scripts/validation/procgen_playable_ship_smoke.gd; do
  echo "=== $script ==="
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 \
    --headless \
    --path /Users/christopherwilloughby/the-sargasso-of-stars \
    --script "$script"
done
```

Expected pass markers:

```text
FLOOR WRAPPER COLLISION FOOTPRINT PASS
PLAYER GRAVITY FLOOR SNAP PASS
INTERACTABLE DISTANCE FALLBACK PASS
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 3: Re-run direct coherent capture and main-scene capture**

Run:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-sargasso-of-stars \
  --script res://scripts/validation/coherent_proof_ship_capture.gd \
  -- \
  --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png \
  --capture-frame 180
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-sargasso-of-stars \
  --script res://scripts/validation/main_coherent_capture.gd \
  -- \
  --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png \
  --capture-frame 180
```

Expected pass markers:

```text
COHERENT PROOF SHIP CAPTURE PASS
MAIN COHERENT CAPTURE PASS
```

- [ ] **Step 4: Append final incorporation checklist**

Run this shell block to append the acceptance checklist after all validation commands pass:

```bash
python3 - <<'PY'
from pathlib import Path
proof = Path('/Users/christopherwilloughby/the-sargasso-of-stars/docs/superpowers/proofs/coherent-proof-ship.md')
text = proof.read_text().rstrip()
section = '''

## Final Main-Path Incorporation Checklist

- [x] `project.godot` still points to `res://scenes/main.tscn`.
- [x] `scenes/main.tscn` instantiates the coherent proof ship through `scripts/main.gd`.
- [x] Main path uses `res://scenes/procgen/playable_coherent_ship.tscn` by default.
- [x] Main boot smoke passes: `MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2`.
- [x] Direct coherent scene validation remains green: `COHERENT PLAYABLE SCENE PASS` and `COHERENT PLAYABLE TRAVERSAL PASS`.
- [x] Existing seed-17 regression remains green: `PLAYABLE SHIP SMOKE PASS`.
- [x] Direct coherent viewport capture remains green: `COHERENT PROOF SHIP CAPTURE PASS ... mode=viewport`.
- [x] Main-scene viewport capture is green: `MAIN COHERENT CAPTURE PASS ... mode=viewport`.
- [x] Main-scene capture artifact exists at `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png`.
- [x] No fixture JSON files were modified during incorporation.
'''
if '## Final Main-Path Incorporation Checklist' in text:
    before = text.split('\n## Final Main-Path Incorporation Checklist\n', 1)[0]
    proof.write_text(before.rstrip() + section + '\n')
else:
    proof.write_text(text + section + '\n')
PY
```

- [ ] **Step 5: Verify final proof-log markers**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
p = Path('/Users/christopherwilloughby/the-sargasso-of-stars/docs/superpowers/proofs/coherent-proof-ship.md')
text = p.read_text()
required = [
    '## Main-Scene Incorporation',
    '## Final Main-Path Incorporation Checklist',
    '`project.godot` still points to `res://scenes/main.tscn`',
    'MAIN COHERENT BOOT PASS',
    'MAIN COHERENT CAPTURE PASS',
    'COHERENT PROOF SHIP CAPTURE PASS',
    'PLAYABLE SHIP SMOKE PASS',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('missing final proof markers: ' + ', '.join(missing))
print('MAIN INCORPORATION FINAL PROOF PASS markers=%d' % len(required))
PY
```

Expected:

```text
MAIN INCORPORATION FINAL PROOF PASS markers=7
```

- [ ] **Step 6: Record Task 5**

Run:

```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m "docs: record coherent ship main-path acceptance"
else
  printf '%s\n' 'NO_GIT Incorporation Task 5 changed: docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/sargasso_coherent_incorporation_no_git_changes.log
fi
```

---

## Final Verification Bundle

Run this command before claiming the plan is complete:

```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
ARTIFACT_DIR=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
mkdir -p "$ARTIFACT_DIR"

echo '--- coherent + main validation ---'
for script in \
  res://scripts/validation/coherent_static_fixture_validator.gd \
  res://scripts/validation/coherent_loader_metadata_smoke.gd \
  res://scripts/validation/coherent_runtime_loader_smoke.gd \
  res://scripts/validation/coherent_playable_scene_smoke.gd \
  res://scripts/validation/coherent_playable_traversal_smoke.gd \
  res://scripts/validation/main_coherent_boot_smoke.gd; do
  echo "=== $script ==="
  "$GODOT" --headless --path "$ROOT" --script "$script"
done

echo '--- existing regressions ---'
for script in \
  res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd \
  res://scripts/validation/player_gravity_floor_snap_smoke.gd \
  res://scripts/validation/interactable_distance_fallback_smoke.gd \
  res://scripts/validation/procgen_playable_ship_smoke.gd; do
  echo "=== $script ==="
  "$GODOT" --headless --path "$ROOT" --script "$script"
done

echo '--- viewport captures ---'
"$GODOT" --path "$ROOT" --script res://scripts/validation/coherent_proof_ship_capture.gd -- --output "$ARTIFACT_DIR/coherent_proof_ship_viewport.png" --capture-frame 180
"$GODOT" --path "$ROOT" --script res://scripts/validation/main_coherent_capture.gd -- --output "$ARTIFACT_DIR/main_coherent_viewport.png" --capture-frame 180

echo '--- main capture metadata ---'
sips -g pixelWidth -g pixelHeight -g format "$ARTIFACT_DIR/main_coherent_viewport.png"
printf 'sha256: '
shasum -a 256 "$ARTIFACT_DIR/main_coherent_viewport.png" | awk '{print $1}'
```

Required pass markers:

```text
COHERENT STATIC FIXTURE PASS
COHERENT LOADER METADATA PASS
COHERENT RUNTIME LOADER PASS
COHERENT PLAYABLE SCENE PASS
COHERENT PLAYABLE TRAVERSAL PASS
MAIN COHERENT BOOT PASS
FLOOR WRAPPER COLLISION FOOTPRINT PASS
PLAYER GRAVITY FLOOR SNAP PASS
INTERACTABLE DISTANCE FALLBACK PASS
PLAYABLE SHIP SMOKE PASS
COHERENT PROOF SHIP CAPTURE PASS
MAIN COHERENT CAPTURE PASS
```

Required main capture metadata:

```text
pixelWidth: 1280
pixelHeight: 720
format: png
```

The final `sha256:` line must contain one 64-character lowercase hexadecimal hash.

---

## Risks, Tradeoffs, and Open Questions

- This plan intentionally changes the default runnable main scene from seed-17 to the coherent proof ship. If the product direction changes to require a launcher/menu or seed selector, that should be a separate plan after this incorporation is validated.
- The coherent proof ship is still a structural/proof-quality in-engine scene. This plan does not add art dressing, hull silhouettes, lighting polish, camera choreography, animation, or user-facing menus.
- The main-scene capture proves the `project.godot` main path renders a real viewport. It does not prove hand-play feel beyond the existing player/interactable smoke coverage.
- `PlayableGeneratedShip` still depends on synchronous `GeneratedShipLoader.load_from_paths()` behavior. This plan preserves that behavior and adds no asynchronous loading.
- The no-git ledger is outside the repo at `/tmp/sargasso_coherent_incorporation_no_git_changes.log`; implementers must not create repo-local audit logs.

---

## Self-Review

- Spec coverage: the plan promotes the coherent proof ship into `scenes/main.tscn`, adds main-scene boot validation, adds main-scene viewport capture, preserves seed-17 regression, records proof evidence, and includes final validation.
- Placeholder scan: the plan contains no `TBD`, no `TODO`, no unspecified error-handling step, no `fill in details`, and no code step that omits actual code.
- Type consistency: `PlayableGeneratedShip`, `get_playable_summary()`, `loader.get_critical_path()`, `loader.get_landmark_nodes()`, `loader.has_loaded_ship()`, and pass-marker names are consistent across tasks.
- No-git condition: every record step uses the required commit-or-record fallback and writes to `/tmp/sargasso_coherent_incorporation_no_git_changes.log` when the workspace is not a git repo.

---

## Execution Handoff

Plan complete. Execute with `superpowers:subagent-driven-development` unless the user explicitly chooses inline execution. Each task should have a fresh implementer subagent, then a spec-compliance review, then a code-quality review, followed by parent-side verification of the task's exact commands and file scope.
