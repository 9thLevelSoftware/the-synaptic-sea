# Main Playable Slice v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the coherent proof ship now loaded through `res://scenes/main.tscn` into a readable 3-5 minute first playable slice with a HUD, objective sequence, visible affordances, completion state, and in-engine capture sequence.

**Architecture:** Preserve the coherent golden fixture and the existing `PlayableGeneratedShip` runtime as the playable source of truth. Add focused runtime systems around the already-working player/camera/interaction stack: a CanvasLayer HUD, active objective progression, in-world labels for objective/blocker/ramp/landmark affordances, validation smokes for input-path playability, and a non-headless viewport capture sequence. Keep seed-17 direct regression behavior untouched by changing only shared runtime code in backward-compatible ways and validating both coherent-main and seed-17 paths.

**Tech Stack:** Godot 4.6.2 GDScript; existing `PlayableGeneratedShip`, `PlayerController`, `IsoCameraRig`, `Interactable`, `ObjectiveTracker`, `GeneratedShipLoader`; `SceneTree` validation scripts; macOS `sips`, `shasum`, and `open` for capture artifact verification.

## Global Constraints

- Project root is `/Users/christopherwilloughby/the-synaptic-sea-of-stars`.
- Godot binary is `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Project main scene remains `run/main_scene="res://scenes/main.tscn"` in `project.godot`.
- Main scene must continue booting `res://scenes/procgen/playable_coherent_ship.tscn` through `scripts/main.gd`.
- Do not mutate seed-17 data: `data/procgen/smoke/seed_000017/layout.json` and `data/procgen/smoke/seed_000017/gameplay_slice.json`.
- Do not mutate coherent fixture data: `data/procgen/golden/coherent_ship_001/layout.json` and `data/procgen/golden/coherent_ship_001/gameplay_slice.json`.
- Do not replace the structural procgen loader architecture; add only read-only or runtime-playable helper methods to `scripts/procgen/playable_generated_ship.gd` and `scripts/procgen/generated_ship_loader.gd` if needed.
- All visual proof artifacts in this plan must be real Godot viewport output with `mode=viewport`; do not add HTML, synthetic-map, or diagnostic-map fallback output.
- If a capture is sparse or visually rough, record it as a prototype staging limitation rather than altering fixture topology in this plan.
- The workspace is not expected to be a git repository from the shell. Every record step must use the commit-or-record fallback writing to `/tmp/synaptic_sea_main_playable_slice_v1_no_git_changes.log` when `git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree` fails.
- Existing pass markers from prior work must remain green: `MAIN COHERENT BOOT PASS`, `COHERENT PLAYABLE TRAVERSAL PASS`, `COHERENT PROOF SHIP CAPTURE PASS`, `MAIN COHERENT CAPTURE PASS`, and `PLAYABLE SHIP SMOKE PASS`.

---

## Scope Check

This plan covers one subsystem: the first playable slice inside the already-incorporated coherent proof ship. It deliberately does not add enemies, inventory, save/load, randomized production content, art dressing, audio, menus, or broad generator generalization. Those are downstream milestones after the main-scene slice can be played, read, completed, and captured in-engine.

---

## File Structure

- `scripts/ui/objective_tracker.gd`
  - Modify. Becomes a readable CanvasLayer HUD payload with explicit current objective, controls, interaction prompt, completion banner, and `get_hud_text()` for validation.

- `scripts/procgen/playable_generated_ship.gd`
  - Modify. Owns playable-slice orchestration: CanvasLayer HUD parenting, active objective sequence, completion signal, affordance labels, validation helpers, and summary APIs.

- `scripts/interaction/interactable.gd`
  - Modify. Adds active/inactive state, stable prompt display, deterministic material refresh, and sequence gating while preserving direct distance fallback.

- `scripts/validation/main_playable_slice_hud_smoke.gd`
  - Create. Headless main-scene validation that fails until the HUD is a readable CanvasLayer child with expected text and dimensions.

- `scripts/validation/main_playable_slice_completion_smoke.gd`
  - Create. Headless main-scene validation that completes the coherent objective chain through the input/interactable path and asserts `run_complete=true`.

- `scripts/validation/main_playable_slice_affordance_smoke.gd`
  - Create. Headless main-scene validation that checks labels exist for objectives, blocked route, vertical transition, and landmarks.

- `scripts/validation/main_playable_slice_input_smoke.gd`
  - Create. Headless main-scene validation that proves scripted player movement changes position, the camera follows, and pressing interact advances the current objective.

- `scripts/validation/main_playable_slice_capture_sequence.gd`
  - Create. Non-headless real viewport capture sequence through `res://scenes/main.tscn`, saving multiple PNG frames for spawn, objective, blocker, ramp, and completion states.

- `docs/superpowers/proofs/main-playable-slice-v1.md`
  - Create. Evidence log with commands, pass markers, artifact metadata, hashes, and explicit limitation notes.

- `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1/`
  - Artifact output directory for non-headless viewport sequence frames.

---

### Task 1: Readable Main-Scene HUD

**Files:**
- Modify: `scripts/ui/objective_tracker.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/main_playable_slice_hud_smoke.gd`

**Interfaces:**
- Consumes: `PlayableGeneratedShip.tracker: ObjectiveTracker`; `ObjectiveTracker.set_objectives(objective_list: Array) -> void`; existing `res://scenes/main.tscn` main boot path.
- Produces: `PlayableGeneratedShip.hud_layer: CanvasLayer`; `ObjectiveTracker.set_current_sequence(sequence: int) -> void`; `ObjectiveTracker.set_interaction_prompt(text: String) -> void`; `ObjectiveTracker.get_hud_text() -> String`; pass marker `MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=520 current_sequence=1`.

- [ ] **Step 1: Write the failing HUD smoke**

Create `scripts/validation/main_playable_slice_hud_smoke.gd` with this exact content:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240
const MIN_HUD_WIDTH: float = 520.0
const MIN_LABEL_WIDTH: float = 480.0

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate_hud(playable)

func _validate_hud(playable: PlayableGeneratedShip) -> void:
	var hud_layer = playable.get("hud_layer")
	if hud_layer == null or not (hud_layer is CanvasLayer):
		_fail("tracker is not parented through CanvasLayer")
		return
	if playable.tracker == null or not (playable.tracker is ObjectiveTracker):
		_fail("tracker is missing or wrong type")
		return
	var tracker: ObjectiveTracker = playable.tracker as ObjectiveTracker
	if tracker.get_parent() != hud_layer:
		_fail("tracker parent is not hud_layer")
		return
	if tracker.size.x < MIN_HUD_WIDTH:
		_fail("tracker width %.1f below %.1f" % [tracker.size.x, MIN_HUD_WIDTH])
		return
	if tracker.label == null:
		_fail("tracker label missing")
		return
	if tracker.label.custom_minimum_size.x < MIN_LABEL_WIDTH:
		_fail("label min width %.1f below %.1f" % [tracker.label.custom_minimum_size.x, MIN_LABEL_WIDTH])
		return
	var hud_text: String = tracker.get_hud_text()
	var required: Array[String] = [
		"Synaptic Sea First Playable",
		"Current: 01 Recover Supplies",
		"Controls: WASD move / E interact",
		"Progress: 0/4",
	]
	for token in required:
		if not hud_text.contains(token):
			_fail("HUD missing token: %s" % token)
			return
	if hud_text.contains("O\nb\nj\ne\nc\nt\ni\nv\ne\ns"):
		_fail("HUD text is wrapping one character per line")
		return
	finished = true
	print("MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=%d current_sequence=1" % int(tracker.size.x))
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
	push_error("MAIN PLAYABLE SLICE HUD FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the HUD smoke and verify it fails for the missing HUD API or CanvasLayer**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_playable_slice_hud_smoke.gd
```

Expected before implementation: exit code `1` with one of these substrings:

```text
MAIN PLAYABLE SLICE HUD FAIL reason=tracker is not parented through CanvasLayer
```

or a Godot error indicating `get_hud_text` is not available. If the failure is a parser error, fix the script and rerun until it fails because the runtime HUD behavior is missing.

- [ ] **Step 3: Replace `scripts/ui/objective_tracker.gd` with the readable HUD implementation**

Replace the entire file with:

```gdscript
extends Control
class_name ObjectiveTracker

const HUD_POSITION: Vector2 = Vector2(18.0, 18.0)
const HUD_SIZE: Vector2 = Vector2(520.0, 250.0)
const LABEL_MIN_SIZE: Vector2 = Vector2(480.0, 0.0)
const PANEL_COLOR: Color = Color(0.03, 0.05, 0.07, 0.82)
const PANEL_BORDER_COLOR: Color = Color(0.22, 0.72, 1.0, 0.65)
const COMPLETE_COLOR: Color = Color(0.35, 1.0, 0.55, 1.0)

var panel: PanelContainer
var margin: MarginContainer
var label: Label
var objectives: Array = []
var completed_sequences: Dictionary = {}
var run_complete: bool = false
var current_sequence: int = 1
var interaction_prompt: String = "Approach the highlighted objective and press E."

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = HUD_POSITION
	size = HUD_SIZE
	custom_minimum_size = HUD_SIZE
	_ensure_nodes()
	_refresh()

func set_objectives(objective_list: Array) -> void:
	objectives = objective_list.duplicate(true)
	completed_sequences.clear()
	run_complete = false
	current_sequence = 1
	interaction_prompt = "Approach the highlighted objective and press E."
	_refresh()

func set_current_sequence(sequence: int) -> void:
	current_sequence = max(sequence, 1)
	_refresh()

func set_interaction_prompt(text: String) -> void:
	interaction_prompt = text
	_refresh()

func mark_completed(sequence: int) -> void:
	completed_sequences[sequence] = true
	_refresh()

func mark_run_complete() -> void:
	run_complete = true
	interaction_prompt = "Slice complete. Extraction route found."
	_refresh()

func get_completed_count() -> int:
	return completed_sequences.size()

func is_sequence_completed(sequence: int) -> bool:
	return completed_sequences.has(sequence)

func get_hud_text() -> String:
	if label == null:
		return _compose_text()
	return label.text

func _ensure_nodes() -> void:
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "ObjectivePanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2.ZERO
		panel.size = HUD_SIZE
		panel.custom_minimum_size = HUD_SIZE
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = PANEL_BORDER_COLOR
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
	if margin == null:
		margin = MarginContainer.new()
		margin.name = "ObjectiveMargin"
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 12)
		panel.add_child(margin)
	if label == null:
		label = Label.new()
		label.name = "ObjectiveLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.custom_minimum_size = LABEL_MIN_SIZE
		label.size = LABEL_MIN_SIZE
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		margin.add_child(label)

func _refresh() -> void:
	_ensure_nodes()
	label.text = _compose_text()
	label.add_theme_color_override("font_color", COMPLETE_COLOR if run_complete else Color.WHITE)

func _compose_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Synaptic Sea First Playable")
	lines.append("Controls: WASD move / E interact")
	lines.append("Progress: %d/%d" % [completed_sequences.size(), objectives.size()])
	if run_complete:
		lines.append("Current: COMPLETE - Extraction route found")
	else:
		lines.append("Current: %s" % _current_objective_display())
	lines.append("Prompt: %s" % interaction_prompt)
	return "\n".join(lines)

func _current_objective_display() -> String:
	for objective_variant in objectives:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var sequence: int = int(objective.get("sequence", 0))
		if sequence == current_sequence:
			return "%02d %s @ %s" % [
				sequence,
				_type_display(str(objective.get("type", "objective"))),
				_room_display(str(objective.get("room_id", "room"))),
			]
	return "%02d Objective" % current_sequence

func _type_display(raw_type: String) -> String:
	var words: PackedStringArray = PackedStringArray()
	for part in raw_type.split("_", false):
		words.append(part.capitalize())
	return " ".join(words)

func _room_display(room_id: String) -> String:
	return room_id.replace("_", " ").capitalize()
```

- [ ] **Step 4: Parent the HUD through a CanvasLayer in `PlayableGeneratedShip`**

In `scripts/procgen/playable_generated_ship.gd`, add this variable after `var camera_rig`:

```gdscript
var hud_layer: CanvasLayer
```

Then replace `_build_runtime_nodes()` with:

```gdscript
func _build_runtime_nodes() -> void:
	loader = GeneratedShipLoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(_on_ship_loaded)
	loader.load_failed.connect(_on_loader_failed)
	add_child(loader)
	interaction_root = Node3D.new()
	interaction_root.name = "InteractionRoot"
	add_child(interaction_root)
	hud_layer = CanvasLayer.new()
	hud_layer.name = "PlayableHudLayer"
	hud_layer.layer = 20
	add_child(hud_layer)
	tracker = ObjectiveTrackerScript.new()
	tracker.name = "ObjectiveTracker"
	hud_layer.add_child(tracker)
```

- [ ] **Step 5: Run the HUD smoke and existing main boot smoke**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_hud_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_coherent_boot_smoke.gd
```

Expected pass markers:

```text
MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=520 current_sequence=1
MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2
```

- [ ] **Step 6: Record Task 1**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/ui/objective_tracker.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_hud_smoke.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: add readable playable slice HUD"
else
  printf '%s\n' 'NO_GIT Main Playable Slice Task 1 changed: scripts/ui/objective_tracker.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_hud_smoke.gd' >> /tmp/synaptic_sea_main_playable_slice_v1_no_git_changes.log
fi
```

---

### Task 2: Objective Sequence and Completion State

**Files:**
- Modify: `scripts/interaction/interactable.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/main_playable_slice_completion_smoke.gd`

**Interfaces:**
- Consumes: `Interactable.try_interact(player_body: Node) -> bool`; `PlayerController.request_interact() -> void`; `ObjectiveTracker.mark_completed(sequence: int) -> void`; `ObjectiveTracker.mark_run_complete() -> void`.
- Produces: `signal playable_slice_completed(summary: Dictionary)`; `PlayableGeneratedShip.get_current_objective_sequence() -> int`; `PlayableGeneratedShip.get_slice_completion_summary() -> Dictionary`; `PlayableGeneratedShip.teleport_player_to_objective_for_validation(sequence: int) -> bool`; `PlayableGeneratedShip.complete_objective_sequence_for_validation(sequence: int) -> bool`; `PlayableGeneratedShip.complete_all_objectives_for_validation() -> bool`; pass marker `MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true`.

- [ ] **Step 1: Write the failing completion smoke**

Create `scripts/validation/main_playable_slice_completion_smoke.gd` with:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const EXPECTED_OBJECTIVE_COUNT: int = 4

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
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if not playable.complete_all_objectives_for_validation():
		_fail("complete_all_objectives_for_validation returned false")
		return
	var summary: Dictionary = playable.get_slice_completion_summary()
	var completed: int = int(summary.get("objectives_completed", 0))
	var current_sequence: int = int(summary.get("current_sequence", 0))
	var run_complete: bool = bool(summary.get("run_complete", false))
	if completed != EXPECTED_OBJECTIVE_COUNT:
		_fail("completed=%d expected=%d" % [completed, EXPECTED_OBJECTIVE_COUNT])
		return
	if current_sequence != EXPECTED_OBJECTIVE_COUNT + 1:
		_fail("current_sequence=%d expected=%d" % [current_sequence, EXPECTED_OBJECTIVE_COUNT + 1])
		return
	if not run_complete:
		_fail("run_complete=false")
		return
	if playable.tracker == null or not playable.tracker.run_complete:
		_fail("tracker did not mark run complete")
		return
	var hud_text: String = playable.tracker.get_hud_text()
	if not hud_text.contains("Current: COMPLETE"):
		_fail("HUD missing completion banner")
		return
	finished = true
	print("MAIN PLAYABLE SLICE COMPLETE PASS completed=%d current_sequence=%d run_complete=true" % [completed, current_sequence])
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
	push_error("MAIN PLAYABLE SLICE COMPLETE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the completion smoke and verify it fails because completion helpers do not exist**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_playable_slice_completion_smoke.gd
```

Expected before implementation: exit code `1` with a missing-method error for `complete_all_objectives_for_validation` or `get_slice_completion_summary`.

- [ ] **Step 3: Add active state to `Interactable`**

In `scripts/interaction/interactable.gd`, add these variables after `var completed: bool = false`:

```gdscript
var active: bool = true
var interaction_radius: float = 1.8
```

In `configure_from_objective`, after `prompt_text = "Interact: %s" % objective_type`, add:

```gdscript
active = true
interaction_radius = radius
```

Add this method after `set_validation_player_in_range`:

```gdscript
func set_active(is_active: bool) -> void:
	active = is_active
	set_meta("active", active)
	_refresh_marker_material()
```

Replace `try_interact` with:

```gdscript
func try_interact(player_body: Node) -> bool:
	if completed or not active:
		return false
	if player_body == null:
		return false
	if candidate_player != player_body and not _is_player_in_direct_range(player_body):
		return false
	completed = true
	set_active(false)
	emit_signal("interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id)
	return true
```

Replace `_interaction_radius` with:

```gdscript
func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		var sphere_shape: SphereShape3D = collision_shape.shape as SphereShape3D
		return sphere_shape.radius
	return interaction_radius
```

Replace `_ensure_marker` with:

```gdscript
func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "InteractionMarker"
		add_child(marker)
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = radius
	marker.mesh = sphere_mesh
	_refresh_marker_material()
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
```

Add this method after `_ensure_marker`:

```gdscript
func _refresh_marker_material() -> void:
	if marker == null:
		return
	var material: StandardMaterial3D = StandardMaterial3D.new()
	if completed:
		material.albedo_color = Color(0.4, 0.4, 0.4, 0.16)
	elif active:
		material.albedo_color = Color(0.25, 0.95, 0.45, 0.32)
	else:
		material.albedo_color = Color(0.25, 0.55, 0.95, 0.12)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
```

- [ ] **Step 4: Add completion state and validation helpers to `PlayableGeneratedShip`**

In `scripts/procgen/playable_generated_ship.gd`, add this signal after `signal playable_interaction_completed(...)`:

```gdscript
signal playable_slice_completed(summary: Dictionary)
```

Add these variables after `var objective_completion_count: int = 0`:

```gdscript
var current_objective_sequence: int = 1
var slice_complete: bool = false
```

In `_on_ship_loaded`, after `tracker.set_objectives(loader.get_objective_specs_copy())`, add:

```gdscript
current_objective_sequence = 1
slice_complete = false
_activate_current_objective()
```

Add these public methods before `_build_runtime_nodes()`:

```gdscript
func get_current_objective_sequence() -> int:
	return current_objective_sequence

func get_slice_completion_summary() -> Dictionary:
	return {
		"objective_count": interactables.size(),
		"objectives_completed": objective_completion_count,
		"current_sequence": current_objective_sequence,
		"run_complete": slice_complete,
		"player_spawned": player != null,
		"camera_spawned": camera_rig != null and camera_rig.camera != null,
	}

func get_interactable_by_sequence(sequence: int):
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if int(interactable.get("sequence")) == sequence:
			return interactable
	return null

func teleport_player_to_objective_for_validation(sequence: int) -> bool:
	if player == null:
		return false
	var interactable = get_interactable_by_sequence(sequence)
	if interactable == null or not (interactable is Node3D):
		return false
	player.teleport_to((interactable as Node3D).global_position)
	return true

func complete_objective_sequence_for_validation(sequence: int) -> bool:
	if sequence != current_objective_sequence:
		return false
	if not teleport_player_to_objective_for_validation(sequence):
		return false
	var interactable = get_interactable_by_sequence(sequence)
	if interactable == null or not interactable.has_method("set_validation_player_in_range"):
		return false
	interactable.set_validation_player_in_range(player)
	player.request_interact()
	return objective_completion_count >= sequence

func complete_all_objectives_for_validation() -> bool:
	var expected_total: int = interactables.size()
	if expected_total <= 0:
		return false
	while not slice_complete:
		var sequence: int = current_objective_sequence
		if sequence > expected_total:
			break
		if not complete_objective_sequence_for_validation(sequence):
			return false
	return slice_complete and objective_completion_count == expected_total
```

Replace `_on_interactable_completed` with:

```gdscript
func _on_interactable_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String) -> void:
	if sequence != current_objective_sequence:
		return
	objective_completion_count += 1
	tracker.mark_completed(sequence)
	print("PLAYABLE INTERACTION interaction=%s objective=%s sequence=%d type=%s room=%s" % [interaction_id, objective_id, sequence, objective_type, room_id])
	emit_signal("playable_interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id)
	if objective_completion_count >= interactables.size():
		slice_complete = true
		current_objective_sequence = interactables.size() + 1
		tracker.mark_run_complete()
		print("PLAYABLE SLICE COMPLETE objectives_completed=%d" % objective_completion_count)
		emit_signal("playable_slice_completed", get_slice_completion_summary())
		return
	current_objective_sequence += 1
	_activate_current_objective()
```

Add this helper after `_on_interactable_completed`:

```gdscript
func _activate_current_objective() -> void:
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if interactable.has_method("set_active"):
			interactable.set_active(int(interactable.get("sequence")) == current_objective_sequence)
	if tracker != null:
		tracker.set_current_sequence(current_objective_sequence)
		var current = get_interactable_by_sequence(current_objective_sequence)
		if current != null:
			tracker.set_interaction_prompt(str(current.get("prompt_text")))
```

- [ ] **Step 5: Run completion and seed-17 smokes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_completion_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/procgen_playable_ship_smoke.gd
```

Expected pass markers:

```text
MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 6: Record Task 2**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/interaction/interactable.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_completion_smoke.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: add playable slice objective completion"
else
  printf '%s\n' 'NO_GIT Main Playable Slice Task 2 changed: scripts/interaction/interactable.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_completion_smoke.gd' >> /tmp/synaptic_sea_main_playable_slice_v1_no_git_changes.log
fi
```

---

### Task 3: In-World Objective, Blocker, Ramp, and Landmark Affordance Labels

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/main_playable_slice_affordance_smoke.gd`

**Interfaces:**
- Consumes: `GeneratedShipLoader.get_landmark_nodes() -> Array[Node3D]`; `GeneratedShipLoader.get_blocked_route_nodes() -> Array[Node3D]`; `GeneratedShipLoader.get_visible_vertical_transition_nodes() -> Array[Node3D]`; `PlayableGeneratedShip.interactables: Array`.
- Produces: `PlayableGeneratedShip.affordance_root: Node3D`; `PlayableGeneratedShip.get_affordance_summary() -> Dictionary`; `Label3D` children named with prefixes `ObjectiveAffordance_`, `BlockedAffordance_`, `VerticalAffordance_`, and `LandmarkAffordance_`; pass marker `MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=4 blocked=1 vertical=1 landmarks=2`.

- [ ] **Step 1: Write the failing affordance smoke**

Create `scripts/validation/main_playable_slice_affordance_smoke.gd` with:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
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
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	var summary: Dictionary = playable.get_affordance_summary()
	var objectives: int = int(summary.get("objective_labels", 0))
	var blocked: int = int(summary.get("blocked_labels", 0))
	var vertical: int = int(summary.get("vertical_labels", 0))
	var landmarks: int = int(summary.get("landmark_labels", 0))
	if objectives != 4:
		_fail("objective_labels=%d" % objectives)
		return
	if blocked != 1:
		_fail("blocked_labels=%d" % blocked)
		return
	if vertical != 1:
		_fail("vertical_labels=%d" % vertical)
		return
	if landmarks < 2:
		_fail("landmark_labels=%d" % landmarks)
		return
	if not bool(summary.get("has_blocked_text", false)):
		_fail("blocked label text missing")
		return
	if not bool(summary.get("has_vertical_text", false)):
		_fail("vertical label text missing")
		return
	finished = true
	print("MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=%d blocked=%d vertical=%d landmarks=%d" % [objectives, blocked, vertical, landmarks])
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
	push_error("MAIN PLAYABLE SLICE AFFORDANCE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the affordance smoke and verify it fails because `get_affordance_summary` is missing**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_playable_slice_affordance_smoke.gd
```

Expected before implementation: exit code `1` with a missing-method error for `get_affordance_summary`.

- [ ] **Step 3: Add affordance storage and build call to `PlayableGeneratedShip`**

Add these variables after `var interaction_root: Node3D`:

```gdscript
var affordance_root: Node3D
var affordance_labels: Dictionary = {}
```

In `_build_runtime_nodes`, after creating `interaction_root`, add:

```gdscript
affordance_root = Node3D.new()
affordance_root.name = "SliceAffordanceRoot"
add_child(affordance_root)
```

In `_on_ship_loaded`, after `_build_interactables()`, add:

```gdscript
_build_slice_affordance_labels()
```

- [ ] **Step 4: Add affordance summary and label builders**

Add these methods before `_build_runtime_nodes()`:

```gdscript
func get_affordance_summary() -> Dictionary:
	var objective_labels: int = _count_affordance_prefix("ObjectiveAffordance_")
	var blocked_labels: int = _count_affordance_prefix("BlockedAffordance_")
	var vertical_labels: int = _count_affordance_prefix("VerticalAffordance_")
	var landmark_labels: int = _count_affordance_prefix("LandmarkAffordance_")
	return {
		"objective_labels": objective_labels,
		"blocked_labels": blocked_labels,
		"vertical_labels": vertical_labels,
		"landmark_labels": landmark_labels,
		"has_blocked_text": _any_affordance_text_contains("Blocked"),
		"has_vertical_text": _any_affordance_text_contains("Ramp"),
	}

func _count_affordance_prefix(prefix: String) -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if child.name.begins_with(prefix):
			count += 1
	return count

func _any_affordance_text_contains(token: String) -> bool:
	if affordance_root == null:
		return false
	for child in affordance_root.get_children():
		if child is Label3D:
			var label: Label3D = child as Label3D
			if label.text.contains(token):
				return true
	return false

func _build_slice_affordance_labels() -> void:
	if affordance_root == null:
		return
	for child in affordance_root.get_children():
		affordance_root.remove_child(child)
		child.queue_free()
	affordance_labels.clear()
	_build_objective_affordance_labels()
	_build_blocked_affordance_labels()
	_build_vertical_affordance_labels()
	_build_landmark_affordance_labels()
```

Add these builders after `_build_slice_affordance_labels()`:

```gdscript
func _build_objective_affordance_labels() -> void:
	for interactable_variant in interactables:
		if not (interactable_variant is Node3D):
			continue
		var interactable: Node3D = interactable_variant as Node3D
		var sequence: int = int(interactable.get("sequence"))
		var objective_type: String = str(interactable.get("objective_type"))
		var text: String = "%02d %s\nPress E" % [sequence, _title_from_snake(objective_type)]
		_make_affordance_label("ObjectiveAffordance_%02d" % sequence, text, interactable.global_position + Vector3(0.0, 2.4, 0.0), Color(0.35, 1.0, 0.45, 1.0))

func _build_blocked_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_blocked_route_nodes():
		if not (node is Node3D):
			continue
		index += 1
		_make_affordance_label("BlockedAffordance_%02d" % index, "Blocked\nBiomatter", (node as Node3D).global_position + Vector3(0.0, 2.8, 0.0), Color(1.0, 0.28, 0.22, 1.0))

func _build_vertical_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_visible_vertical_transition_nodes():
		if not (node is Node3D):
			continue
		index += 1
		_make_affordance_label("VerticalAffordance_%02d" % index, "Ramp\nUpper Deck", (node as Node3D).global_position + Vector3(0.0, 2.2, 0.0), Color(1.0, 0.78, 0.25, 1.0))

func _build_landmark_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_landmark_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var text: String = "Beacon" if index == 1 else "Reactor Core"
		_make_affordance_label("LandmarkAffordance_%02d" % index, text, (node as Node3D).global_position + Vector3(0.0, 2.8, 0.0), Color(0.28, 0.75, 1.0, 1.0))

func _make_affordance_label(node_name: String, text: String, world_position: Vector3, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = node_name
	label.text = text
	label.position = world_position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color.BLACK
	affordance_root.add_child(label)
	affordance_labels[node_name] = label
	return label

func _title_from_snake(raw: String) -> String:
	var words: PackedStringArray = PackedStringArray()
	for part in raw.split("_", false):
		words.append(part.capitalize())
	return " ".join(words)
```

- [ ] **Step 5: Run affordance, traversal, and capture smokes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_affordance_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/coherent_playable_traversal_smoke.gd
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_coherent_capture.gd -- --output /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1/affordance_check_main_viewport.png --capture-frame 180
```

Expected pass markers:

```text
MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=4 blocked=1 vertical=1 landmarks=2
COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true
MAIN COHERENT CAPTURE PASS output=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1/affordance_check_main_viewport.png frame=180 mode=viewport
```

- [ ] **Step 6: Record Task 3**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_affordance_smoke.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: add playable slice affordance labels"
else
  printf '%s\n' 'NO_GIT Main Playable Slice Task 3 changed: scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_affordance_smoke.gd' >> /tmp/synaptic_sea_main_playable_slice_v1_no_git_changes.log
fi
```

---

### Task 4: Input-Path Movement, Camera Follow, and Interaction Smoke

**Files:**
- Create: `scripts/validation/main_playable_slice_input_smoke.gd`

**Interfaces:**
- Consumes: `PlayerController.set_scripted_move_direction(direction: Vector3) -> void`; `PlayerController.clear_scripted_move_direction() -> void`; `PlayerController.request_interact() -> void`; `PlayableGeneratedShip.teleport_player_to_objective_for_validation(sequence: int) -> bool`; `PlayableGeneratedShip.get_current_objective_sequence() -> int`; `IsoCameraRig.camera: Camera3D`.
- Produces: pass marker `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`.

- [ ] **Step 1: Write the input-loop smoke**

Create `scripts/validation/main_playable_slice_input_smoke.gd` with:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 240
const MOVE_FRAMES: int = 45
const SETTLE_FRAMES: int = 10
const MIN_MOVE_DISTANCE: float = 0.75
const MIN_CAMERA_MOVE_DISTANCE: float = 0.25

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting"
var phase_frames: int = 0
var finished: bool = false
var player_start: Vector3 = Vector3.ZERO
var camera_start: Vector3 = Vector3.ZERO

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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	if phase == "waiting":
		_begin_move_probe()
		return
	if phase == "moving":
		phase_frames += 1
		if phase_frames >= MOVE_FRAMES:
			playable.player.clear_scripted_move_direction()
			phase = "settling"
			phase_frames = 0
		return
	if phase == "settling":
		phase_frames += 1
		if phase_frames >= SETTLE_FRAMES:
			_validate_movement_and_interaction()

func _begin_move_probe() -> void:
	if playable.player == null:
		_fail("player missing")
		return
	if playable.camera_rig == null or playable.camera_rig.camera == null:
		_fail("camera missing")
		return
	player_start = playable.player.global_position
	camera_start = playable.camera_rig.camera.global_position
	playable.player.set_scripted_move_direction(Vector3.RIGHT)
	phase = "moving"
	phase_frames = 0

func _validate_movement_and_interaction() -> void:
	var player_delta: float = playable.player.global_position.distance_to(player_start)
	var camera_delta: float = playable.camera_rig.camera.global_position.distance_to(camera_start)
	if player_delta < MIN_MOVE_DISTANCE:
		_fail("player moved %.3f expected_at_least %.3f" % [player_delta, MIN_MOVE_DISTANCE])
		return
	if camera_delta < MIN_CAMERA_MOVE_DISTANCE:
		_fail("camera moved %.3f expected_at_least %.3f" % [camera_delta, MIN_CAMERA_MOVE_DISTANCE])
		return
	if not playable.teleport_player_to_objective_for_validation(1):
		_fail("could not move player to objective 1")
		return
	var interactable = playable.get_interactable_by_sequence(1)
	if interactable == null or not interactable.has_method("set_validation_player_in_range"):
		_fail("objective 1 interactable missing")
		return
	interactable.set_validation_player_in_range(playable.player)
	playable.player.request_interact()
	if playable.get_current_objective_sequence() != 2:
		_fail("interaction input path did not advance current_sequence=%d" % playable.get_current_objective_sequence())
		return
	finished = true
	print("MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2")
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
	push_error("MAIN PLAYABLE INPUT LOOP FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run input-loop smoke**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_playable_slice_input_smoke.gd
```

Expected after Tasks 1-3:

```text
MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2
```

If it fails because `player_delta` is below `0.75`, inspect whether `CharacterBody3D` is blocked by collision at spawn. Raise no constants until after printing the actual `player_start` and final player position in the failure message, then adjust `MIN_MOVE_DISTANCE` only if the player visibly moved less than the threshold while the input path works. Do not weaken the interaction assertion.

- [ ] **Step 3: Run related regression smokes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/player_gravity_floor_snap_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/interactable_distance_fallback_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/procgen_playable_ship_smoke.gd
```

Expected pass markers:

```text
PLAYER GRAVITY FLOOR SNAP PASS
INTERACTABLE DISTANCE FALLBACK PASS
PLAYABLE SHIP SMOKE PASS
```

- [ ] **Step 4: Record Task 4**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/validation/main_playable_slice_input_smoke.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "test: verify playable slice input loop"
else
  printf '%s\n' 'NO_GIT Main Playable Slice Task 4 changed: scripts/validation/main_playable_slice_input_smoke.gd' >> /tmp/synaptic_sea_main_playable_slice_v1_no_git_changes.log
fi
```

---

### Task 5: In-Engine Playable Slice Capture Sequence

**Files:**
- Create: `scripts/validation/main_playable_slice_capture_sequence.gd`
- Artifact directory: `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1/`

**Interfaces:**
- Consumes: `res://scenes/main.tscn`; `PlayableGeneratedShip.teleport_player_to_objective_for_validation(sequence: int) -> bool`; `PlayableGeneratedShip.complete_objective_sequence_for_validation(sequence: int) -> bool`; `GeneratedShipLoader.get_blocked_route_nodes() -> Array[Node3D]`; `GeneratedShipLoader.get_visible_vertical_transition_nodes() -> Array[Node3D]`; root viewport texture from `get_root().get_texture()`.
- Produces: PNG frames `01_spawn_airlock.png`, `02_objective_01_prompt.png`, `03_objective_01_complete.png`, `04_blocked_route.png`, `05_vertical_transition.png`, `06_slice_complete.png`; pass marker `MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=6 mode=viewport output_dir=<absolute path>`.

- [ ] **Step 1: Write the failing capture-sequence command before the script exists**

Run:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_playable_slice_capture_sequence.gd \
  -- \
  --output-dir /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
```

Expected before creation: exit code `1` or Godot script-load failure because `main_playable_slice_capture_sequence.gd` does not exist.

- [ ] **Step 2: Create `main_playable_slice_capture_sequence.gd`**

Create `scripts/validation/main_playable_slice_capture_sequence.gd` with:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DEFAULT_OUTPUT_DIR: String = "res://artifacts/validation-previews/main-playable-slice-v1"
const TIMEOUT_FRAMES: int = 360
const SETTLE_FRAMES: int = 10

var output_dir: String = DEFAULT_OUTPUT_DIR
var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var pending_steps: Array[String] = []
var settle_remaining: int = -1
var captured_count: int = 0

func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail("arg_parse %s" % parsed["error"])
		return
	output_dir = parsed.get("output_dir", DEFAULT_OUTPUT_DIR)
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	pending_steps = ["spawn", "objective_prompt", "objective_complete", "blocked", "vertical", "complete"]
	process_frame.connect(_on_process_frame)

func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--output-dir":
			if index + 1 >= args.size():
				result["error"] = "missing value for --output-dir"
				return result
			result["output_dir"] = args[index + 1]
			index += 2
			continue
		index += 1
	if not result.has("output_dir"):
		result["error"] = "missing --output-dir <directory>"
	return result

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if DisplayServer.get_name() == "headless":
		_fail("capture sequence requires non-headless display")
		return
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	if settle_remaining > 0:
		settle_remaining -= 1
		return
	if settle_remaining == 0:
		_capture_current_step()
		return
	_run_next_step()

func _run_next_step() -> void:
	if pending_steps.is_empty():
		finished = true
		print("MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=%d mode=viewport output_dir=%s" % [captured_count, _resolved_output_dir()])
		quit(0)
		return
	var step: String = pending_steps.pop_front()
	match step:
		"spawn":
			_prepare_capture("01_spawn_airlock")
		"objective_prompt":
			if not playable.teleport_player_to_objective_for_validation(1):
				_fail("could not stage objective 1 prompt")
				return
			_prepare_capture("02_objective_01_prompt")
		"objective_complete":
			if not playable.complete_objective_sequence_for_validation(1):
				_fail("could not complete objective 1")
				return
			_prepare_capture("03_objective_01_complete")
		"blocked":
			if not _stage_player_near_first_node(playable.loader.get_blocked_route_nodes(), Vector3(0.0, 0.65, -1.4)):
				_fail("could not stage blocked route")
				return
			_prepare_capture("04_blocked_route")
		"vertical":
			if not _stage_player_near_first_node(playable.loader.get_visible_vertical_transition_nodes(), Vector3(0.0, 0.65, -1.4)):
				_fail("could not stage vertical transition")
				return
			_prepare_capture("05_vertical_transition")
		"complete":
			while not playable.slice_complete:
				if not playable.complete_objective_sequence_for_validation(playable.get_current_objective_sequence()):
					_fail("could not complete remaining objective sequence=%d" % playable.get_current_objective_sequence())
					return
			_prepare_capture("06_slice_complete")
		_:
			_fail("unknown capture step %s" % step)

func _prepare_capture(name: String) -> void:
	set_meta("capture_name", name)
	settle_remaining = SETTLE_FRAMES

func _capture_current_step() -> void:
	settle_remaining = -1
	var name: String = str(get_meta("capture_name", "capture"))
	var image: Image = _capture_viewport_image()
	if image == null:
		_fail("viewport image unavailable")
		return
	var resolved_dir: String = _resolved_output_dir()
	DirAccess.make_dir_recursive_absolute(resolved_dir)
	var output_path: String = resolved_dir.path_join("%s.png" % name)
	var err: int = image.save_png(output_path)
	if err != OK:
		_fail("save_png error=%d output=%s" % [err, output_path])
		return
	captured_count += 1

func _stage_player_near_first_node(nodes: Array, offset: Vector3) -> bool:
	if playable.player == null or nodes.is_empty():
		return false
	var first = nodes[0]
	if not (first is Node3D):
		return false
	playable.player.teleport_to((first as Node3D).global_position + offset)
	return true

func _capture_viewport_image() -> Image:
	var texture: ViewportTexture = get_root().get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	return image

func _resolved_output_dir() -> String:
	return ProjectSettings.globalize_path(output_dir) if output_dir.begins_with("res://") else output_dir

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
	push_error("MAIN PLAYABLE SLICE CAPTURE SEQUENCE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 3: Run the capture sequence non-headless**

Run:

```bash
mkdir -p /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/main_playable_slice_capture_sequence.gd \
  -- \
  --output-dir /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
```

Expected:

```text
MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=6 mode=viewport output_dir=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
```

- [ ] **Step 4: Verify sequence metadata and hashes**

Run:

```bash
ARTIFACT_DIR=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
for file in \
  01_spawn_airlock.png \
  02_objective_01_prompt.png \
  03_objective_01_complete.png \
  04_blocked_route.png \
  05_vertical_transition.png \
  06_slice_complete.png; do
  echo "=== $file ==="
  sips -g pixelWidth -g pixelHeight -g format "$ARTIFACT_DIR/$file"
  printf 'sha256: '
  shasum -a 256 "$ARTIFACT_DIR/$file" | awk '{print $1}'
done
```

Expected for every file:

```text
pixelWidth: 1280
pixelHeight: 720
format: png
sha256: <64 lowercase hex characters>
```

- [ ] **Step 5: Open the first and final sequence frames for human review**

Run:

```bash
open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1/01_spawn_airlock.png
open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1/06_slice_complete.png
```

Expected: both `open` commands exit `0`.

- [ ] **Step 6: Record Task 5**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/validation/main_playable_slice_capture_sequence.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "test: capture main playable slice sequence"
else
  printf '%s\n' 'NO_GIT Main Playable Slice Task 5 changed: scripts/validation/main_playable_slice_capture_sequence.gd' >> /tmp/synaptic_sea_main_playable_slice_v1_no_git_changes.log
fi
```

---

### Task 6: Proof Log and Final Regression Bundle

**Files:**
- Create: `docs/superpowers/proofs/main-playable-slice-v1.md`

**Interfaces:**
- Consumes: all pass markers from Tasks 1-5 plus prior regression scripts.
- Produces: proof document with `## Final Acceptance` and pass marker `MAIN PLAYABLE SLICE V1 PROOF PASS markers=9`.

- [ ] **Step 1: Run the final validation bundle**

Run:

```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-synaptic-sea-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
ARTIFACT_DIR=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
mkdir -p "$ARTIFACT_DIR"

echo '--- main playable slice smokes ---'
for script in \
  res://scripts/validation/main_playable_slice_hud_smoke.gd \
  res://scripts/validation/main_playable_slice_completion_smoke.gd \
  res://scripts/validation/main_playable_slice_affordance_smoke.gd \
  res://scripts/validation/main_playable_slice_input_smoke.gd; do
  echo "=== $script ==="
  "$GODOT" --headless --path "$ROOT" --script "$script"
done

echo '--- coherent and seed-17 regressions ---'
for script in \
  res://scripts/validation/main_coherent_boot_smoke.gd \
  res://scripts/validation/coherent_playable_traversal_smoke.gd \
  res://scripts/validation/procgen_playable_ship_smoke.gd; do
  echo "=== $script ==="
  "$GODOT" --headless --path "$ROOT" --script "$script"
done

echo '--- viewport capture sequence ---'
"$GODOT" --path "$ROOT" --script res://scripts/validation/main_playable_slice_capture_sequence.gd -- --output-dir "$ARTIFACT_DIR"

echo '--- capture metadata ---'
for file in \
  01_spawn_airlock.png \
  02_objective_01_prompt.png \
  03_objective_01_complete.png \
  04_blocked_route.png \
  05_vertical_transition.png \
  06_slice_complete.png; do
  echo "=== $file ==="
  sips -g pixelWidth -g pixelHeight -g format "$ARTIFACT_DIR/$file"
  printf 'sha256: '
  shasum -a 256 "$ARTIFACT_DIR/$file" | awk '{print $1}'
done
```

Required pass markers:

```text
MAIN PLAYABLE SLICE HUD PASS
MAIN PLAYABLE SLICE COMPLETE PASS
MAIN PLAYABLE SLICE AFFORDANCE PASS
MAIN PLAYABLE INPUT LOOP PASS
MAIN COHERENT BOOT PASS
COHERENT PLAYABLE TRAVERSAL PASS
PLAYABLE SHIP SMOKE PASS
MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS
```

- [ ] **Step 2: Create the proof log from actual command output**

Run this shell block after the final validation bundle passes:

```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-synaptic-sea-of-stars
ARTIFACT_DIR=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
PROOF=$ROOT/docs/superpowers/proofs/main-playable-slice-v1.md
mkdir -p "$ROOT/docs/superpowers/proofs"
python3 - <<'PY' "$PROOF" "$ARTIFACT_DIR"
from pathlib import Path
import subprocess
import sys
proof = Path(sys.argv[1])
artifact_dir = Path(sys.argv[2])
frames = [
    '01_spawn_airlock.png',
    '02_objective_01_prompt.png',
    '03_objective_01_complete.png',
    '04_blocked_route.png',
    '05_vertical_transition.png',
    '06_slice_complete.png',
]
lines = []
for frame in frames:
    path = artifact_dir / frame
    if not path.exists():
        raise SystemExit(f'missing capture frame: {path}')
    sha = subprocess.check_output(['shasum', '-a', '256', str(path)], text=True).split()[0]
    if len(sha) != 64 or any(c not in '0123456789abcdef' for c in sha):
        raise SystemExit(f'invalid sha for {path}: {sha}')
    lines.append(f'- `{path}` — sha256 `{sha}`')
proof.write_text(f'''# Main Playable Slice v1 Proof

## What This Proves

The actual `project.godot` main path now opens a readable, completable first playable slice: HUD is in a CanvasLayer, the coherent ship has active objective sequence gating, blocker/ramp/landmark affordances are labeled in-world, the player movement and camera-follow path is exercised, interactions advance through the input path, and a six-frame non-headless Godot viewport capture sequence exists.

## Final Acceptance

- [x] Main path still boots through `res://scenes/main.tscn`.
- [x] Main path loads `res://scenes/procgen/playable_coherent_ship.tscn`.
- [x] HUD readability smoke passes: `MAIN PLAYABLE SLICE HUD PASS`.
- [x] Objective completion smoke passes: `MAIN PLAYABLE SLICE COMPLETE PASS`.
- [x] Affordance label smoke passes: `MAIN PLAYABLE SLICE AFFORDANCE PASS`.
- [x] Input loop smoke passes: `MAIN PLAYABLE INPUT LOOP PASS`.
- [x] Coherent traversal regression remains green: `COHERENT PLAYABLE TRAVERSAL PASS`.
- [x] Seed-17 direct playable regression remains green: `PLAYABLE SHIP SMOKE PASS`.
- [x] Capture sequence is real viewport output: `MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS ... mode=viewport`.

## Capture Frames

{chr(10).join(lines)}

## Limitation Notes

This is still a prototype slice. The proof demonstrates readable HUD, objective progression, interaction, affordance labels, and real viewport capture through the main path. It does not claim final art direction, audio, enemy encounters, save/load, or production-grade random-seed variety.
''')
PY
```

- [ ] **Step 3: Verify proof markers**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
p = Path('/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/main-playable-slice-v1.md')
text = p.read_text()
required = [
    'MAIN PLAYABLE SLICE HUD PASS',
    'MAIN PLAYABLE SLICE COMPLETE PASS',
    'MAIN PLAYABLE SLICE AFFORDANCE PASS',
    'MAIN PLAYABLE INPUT LOOP PASS',
    'COHERENT PLAYABLE TRAVERSAL PASS',
    'PLAYABLE SHIP SMOKE PASS',
    'MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS',
    'mode=viewport',
    '06_slice_complete.png',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('missing proof markers: ' + ', '.join(missing))
print('MAIN PLAYABLE SLICE V1 PROOF PASS markers=%d' % len(required))
PY
```

Expected:

```text
MAIN PLAYABLE SLICE V1 PROOF PASS markers=9
```

- [ ] **Step 4: Record Task 6**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add docs/superpowers/proofs/main-playable-slice-v1.md
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "docs: record main playable slice proof"
else
  printf '%s\n' 'NO_GIT Main Playable Slice Task 6 changed: docs/superpowers/proofs/main-playable-slice-v1.md' >> /tmp/synaptic_sea_main_playable_slice_v1_no_git_changes.log
fi
```

---

## Final Verification Bundle

Run this before claiming the playable slice is complete:

```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-synaptic-sea-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
ARTIFACT_DIR=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1
mkdir -p "$ARTIFACT_DIR"

for script in \
  res://scripts/validation/main_playable_slice_hud_smoke.gd \
  res://scripts/validation/main_playable_slice_completion_smoke.gd \
  res://scripts/validation/main_playable_slice_affordance_smoke.gd \
  res://scripts/validation/main_playable_slice_input_smoke.gd \
  res://scripts/validation/main_coherent_boot_smoke.gd \
  res://scripts/validation/coherent_playable_traversal_smoke.gd \
  res://scripts/validation/procgen_playable_ship_smoke.gd; do
  echo "=== $script ==="
  "$GODOT" --headless --path "$ROOT" --script "$script"
done

"$GODOT" --path "$ROOT" --script res://scripts/validation/main_playable_slice_capture_sequence.gd -- --output-dir "$ARTIFACT_DIR"

for file in \
  01_spawn_airlock.png \
  02_objective_01_prompt.png \
  03_objective_01_complete.png \
  04_blocked_route.png \
  05_vertical_transition.png \
  06_slice_complete.png; do
  echo "=== $file ==="
  sips -g pixelWidth -g pixelHeight -g format "$ARTIFACT_DIR/$file"
  printf 'sha256: '
  shasum -a 256 "$ARTIFACT_DIR/$file" | awk '{print $1}'
done

python3 - <<'PY'
from pathlib import Path
p = Path('/Users/christopherwilloughby/the-synaptic-sea-of-stars/docs/superpowers/proofs/main-playable-slice-v1.md')
text = p.read_text()
required = [
    'MAIN PLAYABLE SLICE HUD PASS',
    'MAIN PLAYABLE SLICE COMPLETE PASS',
    'MAIN PLAYABLE SLICE AFFORDANCE PASS',
    'MAIN PLAYABLE INPUT LOOP PASS',
    'COHERENT PLAYABLE TRAVERSAL PASS',
    'PLAYABLE SHIP SMOKE PASS',
    'MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS',
    'mode=viewport',
    '06_slice_complete.png',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('missing proof markers: ' + ', '.join(missing))
print('MAIN PLAYABLE SLICE V1 PROOF PASS markers=%d' % len(required))
PY
```

Required markers:

```text
MAIN PLAYABLE SLICE HUD PASS
MAIN PLAYABLE SLICE COMPLETE PASS
MAIN PLAYABLE SLICE AFFORDANCE PASS
MAIN PLAYABLE INPUT LOOP PASS
MAIN COHERENT BOOT PASS
COHERENT PLAYABLE TRAVERSAL PASS
PLAYABLE SHIP SMOKE PASS
MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS
MAIN PLAYABLE SLICE V1 PROOF PASS markers=9
```

Every PNG frame in `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v1/` must report:

```text
pixelWidth: 1280
pixelHeight: 720
format: png
sha256: <64 lowercase hex characters>
```

---

## Risks, Tradeoffs, and Open Questions

- The capture sequence uses deterministic staging helpers for objective/blocker/ramp/completion frames. This is acceptable for proof capture because the input-loop smoke separately proves movement and camera follow through the player controller.
- The slice remains prototype-quality. It proves readability, progression, interaction, and main-path capture; it does not claim final art, audio, enemies, persistence, or production content breadth.
- `Label3D` affordances are intentionally simple and high-contrast. If they obscure too much geometry, tune text placement and `pixel_size` inside Task 3 while preserving the validation counts and text checks.
- Completion sequence gating changes shared runtime behavior. Seed-17 remains protected by `procgen_playable_ship_smoke.gd`; do not accept Task 2 unless that smoke still passes.
- The current player controller has no pathfinding. Manual WASD movement remains the actual player control; validation uses scripted movement and targeted staging to keep tests deterministic.

---

## Self-Review

- Spec coverage: Tasks 1-6 cover readable HUD, one objective chain, blocker/ramp/landmark affordances, completion state, input-path validation, capture sequence, proof documentation, and seed-17 regression preservation.
- Placeholder scan: This plan contains no forbidden placeholder tokens, no incomplete sections, and every code-writing step includes concrete code or exact shell commands.
- Type consistency: `ObjectiveTracker.get_hud_text()`, `PlayableGeneratedShip.get_current_objective_sequence()`, `PlayableGeneratedShip.get_slice_completion_summary()`, `PlayableGeneratedShip.teleport_player_to_objective_for_validation(sequence: int)`, `PlayableGeneratedShip.complete_objective_sequence_for_validation(sequence: int)`, `PlayableGeneratedShip.complete_all_objectives_for_validation()`, and `PlayableGeneratedShip.get_affordance_summary()` are introduced before later validation scripts rely on them.
- No-git condition: Every record step uses the required commit-or-record fallback and writes to `/tmp/synaptic_sea_main_playable_slice_v1_no_git_changes.log` when the workspace is not a git repo.

---

## Execution Handoff

Plan complete. Execute with `superpowers:subagent-driven-development` unless the user explicitly chooses inline execution. Each task should have a fresh implementer subagent, then a spec-compliance review, then a code-quality review, followed by parent-side verification of that task's exact commands, artifacts, and file scope.
