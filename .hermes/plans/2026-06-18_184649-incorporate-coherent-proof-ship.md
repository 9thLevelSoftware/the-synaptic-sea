# Coherent Proof Ship Main-Game Incorporation Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Promote the already-validated coherent proof ship from a proof-only sibling scene into the actual runnable main game path, with main-scene validation and a fresh in-engine main-scene viewport capture.
**Architecture:** Keep the coherent proof ship fixture and sibling scene as the source of truth, but make `scenes/main.tscn` boot that coherent scene by default instead of the older seed-17 generated ship. Add a focused main-scene boot smoke and a main-scene viewport capture script so future claims prove the project’s real `run/main_scene` path, not just a direct validation scene.
**Tech Stack:** Godot 4.6.2 GDScript, existing `PlayableGeneratedShip`, `GeneratedShipLoader`, `ship_structural_v0` kit, Hermes subagent-driven implementation + two-stage review.

---

## Current Context / Assumptions

- Project root: `/Users/christopherwilloughby/the-synaptic-sea-of-stars`
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`
- `project.godot` currently sets `run/main_scene="res://scenes/main.tscn"`.
- `scripts/main.gd` currently hardcodes `res://scenes/procgen/playable_generated_ship.tscn`, which uses the older seed-17 fixture by default.
- `scenes/procgen/playable_coherent_ship.tscn` already exists and overrides `PlayableGeneratedShip` exports to load:
  - `res://data/procgen/golden/coherent_ship_001/layout.json`
  - `res://data/kits/ship_structural_v0.json`
  - `res://data/procgen/golden/coherent_ship_001/gameplay_slice.json`
- Existing coherent proof evidence is green:
  - 8 rooms / 7 traversable links / 1 blocked link / 1 vertical connection
  - 5-room critical path
  - 3 side rooms
  - 2 landmarks
  - 4 objectives
  - real non-headless viewport capture at `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png`
- The repo is not currently a git repository from the shell. Use `/tmp/synaptic_sea_coherent_incorporation_no_git_changes.log` as the fallback change ledger if `git rev-parse --is-inside-work-tree` fails.
- Do **not** regenerate the golden fixture, rewrite the loader, or modify seed-17 data in this plan. The goal is incorporation into the main runnable path, not another proof-fixture build.

---

## Proposed Approach

1. Add a failing main-scene boot smoke that proves `res://scenes/main.tscn` itself boots the coherent ship.
2. Change `scripts/main.gd` and `scenes/main.tscn` so the actual game main scene instantiates `playable_coherent_ship.tscn` by default and no longer keeps a stale static `LockedIsoCamera` as the active camera.
3. Add a main-scene viewport capture script that captures the real `scenes/main.tscn` path, not the direct sibling scene path.
4. Append proof-log evidence showing that both the validation scene and the actual main scene produce in-engine proof.
5. Run the final coherent bundle, existing regression bundle, main-scene smoke, and main-scene capture.

---

## Files Likely To Change

- Create: `scripts/validation/main_coherent_boot_smoke.gd`
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn`
- Create: `scripts/validation/main_coherent_capture.gd`
- Modify: `docs/superpowers/proofs/coherent-proof-ship.md`
- Artifact output, outside repo: `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png`
- Fallback no-git ledger: `/tmp/synaptic_sea_coherent_incorporation_no_git_changes.log`

Files that must **not** change:

- `data/procgen/smoke/seed_000017/layout.json`
- `data/procgen/smoke/seed_000017/gameplay_slice.json`
- `data/procgen/golden/coherent_ship_001/layout.json`
- `data/procgen/golden/coherent_ship_001/gameplay_slice.json`
- `scripts/procgen/generated_ship_loader.gd`
- `scripts/procgen/playable_generated_ship.gd`
- `scenes/procgen/playable_coherent_ship.tscn`

---

## Task 1: Add a Main-Scene Coherent Boot Smoke

**Objective:** Create a failing validation script that proves the actual `res://scenes/main.tscn` boots the coherent proof ship, not the older seed-17 scene.

**Files:**
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/main_coherent_boot_smoke.gd`

### Step 1: Write the failing validation script

Create `scripts/validation/main_coherent_boot_smoke.gd`:

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

### Step 2: Run it to verify RED

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_coherent_boot_smoke.gd
```

Expected: FAIL because `scripts/main.gd` still instantiates `res://scenes/procgen/playable_generated_ship.tscn`, whose `layout_path` defaults to seed-17.

Expected failure line contains:

```text
MAIN COHERENT BOOT FAIL reason=expected coherent layout res://data/procgen/golden/coherent_ship_001/layout.json got res://data/procgen/smoke/seed_000017/layout.json
```

### Step 3: Record Task 1

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/validation/main_coherent_boot_smoke.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "test: add main coherent boot smoke"
else
  printf '%s\n' 'NO_GIT Incorporation Task 1 changed: scripts/validation/main_coherent_boot_smoke.gd' >> /tmp/synaptic_sea_coherent_incorporation_no_git_changes.log
fi
```

---

## Task 2: Promote the Coherent Ship Into the Main Boot Path

**Objective:** Make `scenes/main.tscn` boot the coherent proof ship by default and remove the stale static camera from main.

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd`
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/main.tscn`

### Step 1: Replace `scripts/main.gd`

Replace the current file with:

```gdscript
extends Node3D

const DEFAULT_PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")

@export var playable_ship_scene: PackedScene = DEFAULT_PLAYABLE_SHIP_SCENE

var playable_instance: PlayableGeneratedShip


func _ready() -> void:
	print("The Synaptic Sea coherent proof ship bootstrap loaded.")
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

### Step 2: Replace `scenes/main.tscn`

Remove the old `LockedIsoCamera` node. The playable coherent scene creates its own `IsoCameraRig` and current `PlayableIsoCamera` after loading.

Replace the file with:

```text
[gd_scene load_steps=2 format=3 uid="uid://synaptic_sea_main"]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]

[node name="Main" type="Node3D"]
script = ExtResource("1_main")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, -0.25, 0.433013, 0, 0.866025, 0.5, -0.5, -0.433013, 0.75, 0, 8, 0)
light_energy = 1.5
```

### Step 3: Run the main boot smoke to verify GREEN

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_coherent_boot_smoke.gd
```

Expected output contains:

```text
MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2
```

### Step 4: Run existing coherent scene and seed-17 regressions

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/coherent_playable_scene_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/procgen_playable_ship_smoke.gd
```

Expected pass markers:

```text
COHERENT PLAYABLE SCENE PASS
PLAYABLE SHIP SMOKE PASS
```

### Step 5: Record Task 2

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/main.gd scenes/main.tscn
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: boot coherent proof ship from main scene"
else
  printf '%s\n' 'NO_GIT Incorporation Task 2 changed: scripts/main.gd scenes/main.tscn' >> /tmp/synaptic_sea_coherent_incorporation_no_git_changes.log
fi
```

---

## Task 3: Add a Main-Scene Viewport Capture Script

**Objective:** Capture a fresh viewport through `res://scenes/main.tscn`, proving the project’s main scene path renders the coherent ship in-engine.

**Files:**
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/main_coherent_capture.gd`

### Step 1: Run the capture command before the script exists to verify RED

Run:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_coherent_capture.gd \
  -- \
  --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png \
  --capture-frame 180
```

Expected: FAIL because `res://scripts/validation/main_coherent_capture.gd` does not exist yet.

### Step 2: Create `main_coherent_capture.gd`

Create `scripts/validation/main_coherent_capture.gd`:

```gdscript
extends SceneTree

# Captures the real project main scene (`res://scenes/main.tscn`) after it
# boots the coherent proof ship. This is intentionally separate from
# `coherent_proof_ship_capture.gd`, which captures the sibling playable scene
# directly. This script proves the actual `project.godot` main-scene path.

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

### Step 3: Run the main-scene capture to verify GREEN

Run without `--headless`:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_coherent_capture.gd \
  -- \
  --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png \
  --capture-frame 180
```

Expected output contains:

```text
MAIN COHERENT CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png frame=180 mode=viewport
```

### Step 4: Verify PNG metadata

Run:

```bash
sips -g pixelWidth -g pixelHeight -g format /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
printf '\nsha256: '
shasum -a 256 /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png | awk '{print $1}'
```

Expected:

```text
pixelWidth: 1280
pixelHeight: 720
format: png
sha256: <64 hex characters>
```

### Step 5: Open the PNG for human review

Run:

```bash
open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
```

Expected: exit 0. If visual review shows the scene is too sparse or poorly framed, do **not** call that a functional failure if the pass markers are green; instead record it as a visual-staging follow-up. The implementation scope here is main-path incorporation and real in-engine capture.

### Step 6: Record Task 3

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/validation/main_coherent_capture.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "test: capture coherent ship through main scene"
else
  printf '%s\n' 'NO_GIT Incorporation Task 3 changed: scripts/validation/main_coherent_capture.gd' >> /tmp/synaptic_sea_coherent_incorporation_no_git_changes.log
fi
```

---

## Task 4: Append Main-Path Incorporation Evidence to the Proof Log

**Objective:** Update the existing proof log with the main-scene boot proof and main-scene viewport capture proof.

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

### Step 1: Append a new proof section

Append this section to `docs/superpowers/proofs/coherent-proof-ship.md`, replacing the hash placeholder with the actual `shasum` output from Task 3:

```markdown
## Main-Scene Incorporation

The coherent proof ship is now the default playable scene instantiated by `res://scenes/main.tscn`, the project `run/main_scene` path from `project.godot`. `scripts/main.gd` instantiates `res://scenes/procgen/playable_coherent_ship.tscn` by default and `scenes/main.tscn` no longer keeps a stale current `LockedIsoCamera`; the playable scene creates the active `PlayableIsoCamera` through `IsoCameraRig`.

Main boot smoke:

```text
MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2 frames=<n>
```

Main-scene viewport capture:

```text
MAIN COHERENT CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png frame=180 mode=viewport
```

Main-scene capture artifact:

```text
path: /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png
pixelWidth: 1280
pixelHeight: 720
format: png
sha256: <64-hex-main-capture-sha>
```

Human review note: `open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png` returned exit 0. This is a real Godot viewport capture through `scenes/main.tscn` (`mode=viewport`), not an HTML/mockup or synthetic diagnostic map.
```

### Step 2: Verify the proof log contains the new evidence

Run:

```bash
python3 - <<'PY'
from pathlib import Path
p = Path('/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md')
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

### Step 3: Record Task 4

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "docs: record coherent ship main-scene incorporation"
else
  printf '%s\n' 'NO_GIT Incorporation Task 4 changed: docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_incorporation_no_git_changes.log
fi
```

---

## Task 5: Final Main-Path Regression Bundle

**Objective:** Prove the coherent ship remains validated through both the direct coherent scene path and the actual main scene path, while seed-17 regression remains intact.

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/coherent-proof-ship.md`

### Step 1: Run the coherent + main validation bundle

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
    --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
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

### Step 2: Run the existing regression bundle

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
    --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
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

### Step 3: Re-run both viewport captures

Run:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/coherent_proof_ship_capture.gd \
  -- \
  --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/coherent_proof_ship_viewport.png \
  --capture-frame 180
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
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

### Step 4: Append final incorporation checklist

Append this checklist to `docs/superpowers/proofs/coherent-proof-ship.md` and fill in any exact frame/hash values from the run:

```markdown
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
```

### Step 5: Record final incorporation task

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add docs/superpowers/proofs/coherent-proof-ship.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "docs: record coherent ship main-path acceptance"
else
  printf '%s\n' 'NO_GIT Incorporation Task 5 changed: docs/superpowers/proofs/coherent-proof-ship.md' >> /tmp/synaptic_sea_coherent_incorporation_no_git_changes.log
fi
```

---

## Tests / Validation Summary

Run these before claiming completion:

```bash
# Main path smoke
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_coherent_boot_smoke.gd

# Coherent validation bundle
for script in \
  res://scripts/validation/coherent_static_fixture_validator.gd \
  res://scripts/validation/coherent_loader_metadata_smoke.gd \
  res://scripts/validation/coherent_runtime_loader_smoke.gd \
  res://scripts/validation/coherent_playable_scene_smoke.gd \
  res://scripts/validation/coherent_playable_traversal_smoke.gd; do
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script "$script"
done

# Existing regression bundle
for script in \
  res://scripts/validation/floor_wrapper_collision_footprint_smoke.gd \
  res://scripts/validation/player_gravity_floor_snap_smoke.gd \
  res://scripts/validation/interactable_distance_fallback_smoke.gd \
  res://scripts/validation/procgen_playable_ship_smoke.gd; do
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script "$script"
done

# Main path non-headless capture
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_coherent_capture.gd -- --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/coherent_proof_ship/main_coherent_viewport.png --capture-frame 180
```

Required pass markers:

```text
MAIN COHERENT BOOT PASS
COHERENT STATIC FIXTURE PASS
COHERENT LOADER METADATA PASS
COHERENT RUNTIME LOADER PASS
COHERENT PLAYABLE SCENE PASS
COHERENT PLAYABLE TRAVERSAL PASS
FLOOR WRAPPER COLLISION FOOTPRINT PASS
PLAYER GRAVITY FLOOR SNAP PASS
INTERACTABLE DISTANCE FALLBACK PASS
PLAYABLE SHIP SMOKE PASS
MAIN COHERENT CAPTURE PASS
```

---

## Risks, Tradeoffs, and Open Questions

- **Main scene becomes coherent proof ship by default.** This is intentional for incorporation, but if the desired default should remain seed-17, add a menu/launcher or `@export` scene override instead of changing the default.
- **Visual quality is still proof-level.** This plan proves main-path in-engine incorporation. It does not add art dressing, hull silhouettes, lighting passes, or a prettier hero camera beyond the current runtime camera. If the capture is still visually sparse, treat that as the next staging/art pass.
- **Synchronous loader assumption remains.** `PlayableGeneratedShip` currently relies on synchronous `GeneratedShipLoader.load_from_paths()`. This plan does not change that; validation should fail if it breaks.
- **No-git fallback.** The project is not a git repo in the shell. Subagents must not invent repo-local audit logs; use `/tmp/synaptic_sea_coherent_incorporation_no_git_changes.log` exactly.
- **No fixture edits.** If a validation fails because of the existing blocked-link fallback or sparse camera framing, do not “fix” fixture geometry as part of this incorporation plan. File a follow-up plan for staging/fixture polish.

---

## Execution Handoff

Plan complete. Implement with `subagent-driven-development`:

1. Dispatch one fresh subagent per task.
2. After each task, run spec compliance review.
3. Then run code quality review.
4. Parent must independently re-run the task’s validation command before marking complete.
5. Final integration review should confirm the real `project.godot` main path now opens the coherent proof ship and that both direct coherent capture and main-scene capture are real `mode=viewport` Godot renders.
