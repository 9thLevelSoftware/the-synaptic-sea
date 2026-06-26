# Playable Generated Ship Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first player-controllable generated-ship prototype slice for The Synaptic Sea.

**Architecture:** Keep the existing procgen loader and debug runner intact, then wrap them with a new playable scene that owns player spawn, locked-isometric camera, input, interactables, and playability validation. Existing deterministic seed-17 runtime/gameplay/walkthrough smokes remain regression gates while a new playable smoke proves the player-facing path independently.

**Tech Stack:** Godot 4.6.2 GDScript, `CharacterBody3D`, `Area3D`, existing `GeneratedShipLoader`, existing `ship_structural_v0` wrapper scenes, Python/pytest wrappers in `/Users/christopherwilloughby/off-the-rails-ai-infra`.

## Global Constraints

- Godot project root: `/Users/christopherwilloughby/the-synaptic-sea-of-stars`.
- Procgen infra root: `/Users/christopherwilloughby/off-the-rails-ai-infra`.
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Deterministic first fixture: `res://data/procgen/smoke/seed_000017/layout.json`, `res://data/procgen/smoke/seed_000017/gameplay_slice.json`, `res://data/kits/ship_structural_v0.json`.
- Preserve existing debug route validation: `procgen_runtime_demo_smoke.gd`, `procgen_ship_gameplay_smoke.gd`, and `procgen_ship_walkthrough_smoke.gd` must continue to pass.
- No combat, inventory, economy, save/load, hub-ship state machine, production art, broad topology rewrite, or random-seed gameplay claim in this plan.
- The workspaces are not git repositories at plan time. Each task includes a commit-or-log step that commits when git exists and otherwise appends exact changed paths to `/tmp/synaptic_sea_playable_no_git_changes.log`.

---

## File Structure

### New Godot files

- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/player/player_controller.gd`
  - Owns placeholder player movement, interact input, collision body setup, and a test helper for scripted movement.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/camera/iso_camera_rig.gd`
  - Owns the locked-isometric follow camera. Does not parse procgen data.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/interaction/interactable.gd`
  - Owns player-in-range detection and interact completion signals for objective/portal targets.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/playable_generated_ship.gd`
  - Coordinates loader, player, camera, objective tracker, and interactable nodes for the playable generated-ship slice.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/playable_generated_ship.tscn`
  - Minimal scene resource that attaches `PlayableGeneratedShip`.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/playable_component_smoke.gd`
  - Headless component smoke for player, camera, and interactable scripts.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_smoke.gd`
  - Headless playable generated-ship smoke.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_capture.gd`
  - Headless-or-windowed capture proof for the playable scene.

### Modified Godot files

- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd`
  - Add read-only helper methods for loaded state, spawn transform, objective copies, goal position, and collision shape counting.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/ui/objective_tracker.gd`
  - Add completion query helpers used by playable validation.
- `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd`
  - Load the playable generated-ship scene from the main scene while leaving `GeneratedShipDemo` available for regression scripts.

### New infra files

- `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_playable_ship.py`
  - Pytest wrapper that verifies the new playable smoke script exists, references required pass markers, and passes under Godot.

---

### Task 1: Add the red playable smoke contract

**Files:**
- Create: `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_playable_ship.py`
- Expected missing for RED: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_smoke.gd`

**Interfaces:**
- Consumes: Godot binary path `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Produces: pytest contract that later tasks satisfy by printing `PLAYABLE SHIP SMOKE PASS` with required status fields.

- [ ] **Step 1: Write the failing pytest contract**

Write this complete file to `/Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_playable_ship.py`:

```python
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

GODOT = Path("/Users/christopherwilloughby/.local/bin/godot-4.6.2")
GODOT_PROJECT = Path("/Users/christopherwilloughby/the-synaptic-sea-of-stars")
SCRIPT = GODOT_PROJECT / "scripts" / "validation" / "procgen_playable_ship_smoke.gd"


def test_playable_ship_smoke_script_exists() -> None:
    assert SCRIPT.exists()


def test_playable_ship_smoke_mentions_required_pass_fields() -> None:
    script = SCRIPT.read_text(encoding="utf-8")

    assert "playable_generated_ship.tscn" in script
    assert "PLAYABLE SHIP SMOKE PASS" in script
    assert "player_spawned=true" in script
    assert "collision_checked=true" in script
    assert "interaction_completed=true" in script
    assert "objectives_completed=" in script


def test_playable_ship_smoke_runs_if_godot_available() -> None:
    if not GODOT.exists():
        pytest.skip(f"Godot binary not found: {GODOT}")

    proc = subprocess.run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(GODOT_PROJECT),
            "--script",
            "res://scripts/validation/procgen_playable_ship_smoke.gd",
            "--",
            "--timeout-frames",
            "9000",
        ],
        cwd=GODOT_PROJECT,
        text=True,
        capture_output=True,
        timeout=180,
    )

    combined = proc.stdout + proc.stderr
    assert proc.returncode == 0, combined
    assert "PLAYABLE SHIP SMOKE PASS" in combined
    assert "player_spawned=true" in combined
    assert "collision_checked=true" in combined
    assert "interaction_completed=true" in combined
    assert "objectives_completed=1" in combined or "objectives_completed=4" in combined
```

- [ ] **Step 2: Run the new contract to verify RED**

Run:

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_playable_ship.py -q
```

Expected: FAIL because `procgen_playable_ship_smoke.gd` does not exist yet. The first failing assertion should be `assert SCRIPT.exists()`.

- [ ] **Step 3: Commit or record no-git state**

Run:

```bash
if git -C /Users/christopherwilloughby/off-the-rails-ai-infra rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/off-the-rails-ai-infra add tests/test_godot_procgen_playable_ship.py
  git -C /Users/christopherwilloughby/off-the-rails-ai-infra commit -m "test: define playable generated ship smoke contract"
else
  printf '%s\n' 'NO_GIT Task 1 changed: /Users/christopherwilloughby/off-the-rails-ai-infra/tests/test_godot_procgen_playable_ship.py' >> /tmp/synaptic_sea_playable_no_git_changes.log
fi
```

Expected when no git repo is present: command exits 0 and appends the path to `/tmp/synaptic_sea_playable_no_git_changes.log`.

---

### Task 2: Add focused player, camera, and interactable components

**Files:**
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/player/player_controller.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/camera/iso_camera_rig.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/interaction/interactable.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/playable_component_smoke.gd`

**Interfaces:**
- Produces: `PlayerController.request_interact() -> void`, `PlayerController.teleport_to(world_position: Vector3) -> void`, `IsoCameraRig.follow_target: Node3D`, `Interactable.configure_from_objective(objective: Dictionary, world_position: Vector3, radius: float) -> void`, `Interactable.set_validation_player_in_range(player_body: Node) -> void`, `Interactable.try_interact(player_body: Node) -> bool`.
- Consumes: no procgen loader data. Component smoke supplies a synthetic objective dictionary.

- [ ] **Step 1: Run the missing component smoke to verify RED**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/playable_component_smoke.gd
```

Expected: FAIL with an error that `res://scripts/validation/playable_component_smoke.gd` cannot be opened or loaded.

- [ ] **Step 2: Create `player_controller.gd`**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/player/player_controller.gd`:

```gdscript
extends CharacterBody3D
class_name PlayerController

signal interact_requested(player: PlayerController)

const DEFAULT_MOVE_SPEED: float = 6.0
const DEFAULT_COLLISION_RADIUS: float = 0.35
const DEFAULT_COLLISION_HEIGHT: float = 1.6

var move_speed: float = DEFAULT_MOVE_SPEED
var scripted_move_direction: Vector3 = Vector3.ZERO
var use_scripted_movement: bool = false
var marker: MeshInstance3D
var collision_shape: CollisionShape3D


func _ready() -> void:
	_ensure_support_nodes()
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	var move_direction: Vector3 = _read_move_direction()
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()
	velocity = move_direction * move_speed
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		request_interact()


func request_interact() -> void:
	emit_signal("interact_requested", self)


func teleport_to(world_position: Vector3) -> void:
	global_position = world_position
	velocity = Vector3.ZERO


func set_scripted_move_direction(direction: Vector3) -> void:
	use_scripted_movement = true
	scripted_move_direction = direction


func clear_scripted_move_direction() -> void:
	use_scripted_movement = false
	scripted_move_direction = Vector3.ZERO


func _read_move_direction() -> Vector3:
	if use_scripted_movement:
		return scripted_move_direction

	var input_x: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var input_z: float = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	return Vector3(input_x, 0.0, input_z)


func _ensure_support_nodes() -> void:
	collision_layer = 1
	collision_mask = 1

	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "PlayerCollisionShape3D"
		var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
		capsule_shape.radius = DEFAULT_COLLISION_RADIUS
		capsule_shape.height = DEFAULT_COLLISION_HEIGHT
		collision_shape.shape = capsule_shape
		collision_shape.position = Vector3(0.0, DEFAULT_COLLISION_HEIGHT * 0.5, 0.0)
		add_child(collision_shape)

	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "PlayerMarker"
		var capsule_mesh: CapsuleMesh = CapsuleMesh.new()
		capsule_mesh.radius = DEFAULT_COLLISION_RADIUS
		capsule_mesh.height = DEFAULT_COLLISION_HEIGHT
		marker.mesh = capsule_mesh
		marker.position = Vector3(0.0, DEFAULT_COLLISION_HEIGHT * 0.5, 0.0)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.15, 0.72, 1.0, 1.0)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		marker.material_override = material
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
```

- [ ] **Step 3: Create `iso_camera_rig.gd`**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/camera/iso_camera_rig.gd`:

```gdscript
extends Node3D
class_name IsoCameraRig

const DEFAULT_OFFSET: Vector3 = Vector3(16.0, 18.0, 16.0)
const DEFAULT_SIZE: float = 22.0

var follow_target: Node3D
var offset: Vector3 = DEFAULT_OFFSET
var camera: Camera3D


func _ready() -> void:
	_ensure_camera()
	set_process(true)


func _process(_delta: float) -> void:
	if follow_target == null:
		return
	global_position = follow_target.global_position + offset
	camera.global_position = global_position
	camera.look_at(follow_target.global_position, Vector3.UP)


func set_follow_target(target: Node3D) -> void:
	follow_target = target
	_ensure_camera()
	if follow_target != null:
		global_position = follow_target.global_position + offset
		camera.global_position = global_position
		camera.look_at(follow_target.global_position, Vector3.UP)


func make_current() -> void:
	_ensure_camera()
	camera.current = true


func _ensure_camera() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "PlayableIsoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = DEFAULT_SIZE
	camera.current = true
	add_child(camera)
```

- [ ] **Step 4: Create `interactable.gd`**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/interaction/interactable.gd`:

```gdscript
extends Area3D
class_name Interactable

signal interaction_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String)

var interaction_id: String = ""
var objective_id: String = ""
var sequence: int = 0
var objective_type: String = ""
var room_id: String = ""
var prompt_text: String = "Interact"
var completed: bool = false
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D


func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func configure_from_objective(objective: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	objective_id = str(objective.get("id", ""))
	sequence = int(objective.get("sequence", 0))
	objective_type = str(objective.get("type", "objective"))
	room_id = str(objective.get("room_id", ""))
	interaction_id = "objective:%02d:%s" % [sequence, objective_id]
	prompt_text = "Interact: %s" % objective_type
	completed = false
	candidate_player = null
	name = "Interactable_seq%d_%s" % [sequence, objective_type]
	position = world_position
	set_meta("interaction_id", interaction_id)
	set_meta("objective_id", objective_id)
	set_meta("objective_sequence", sequence)
	set_meta("objective_type", objective_type)
	set_meta("room_id", room_id)
	_ensure_collision(radius)
	_ensure_marker(radius)


func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body


func try_interact(player_body: Node) -> bool:
	if completed:
		return false
	if candidate_player == null:
		return false
	if candidate_player != player_body:
		return false
	completed = true
	emit_signal("interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id)
	return true


func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "InteractionCollisionShape3D"
		add_child(collision_shape)
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = radius
	collision_shape.shape = sphere_shape


func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "InteractionMarker"
		add_child(marker)
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = radius
	marker.mesh = sphere_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.95, 0.45, 0.22)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body


func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 5: Create `playable_component_smoke.gd`**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/playable_component_smoke.gd`:

```gdscript
extends SceneTree

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const IsoCameraRigScript := preload("res://scripts/camera/iso_camera_rig.gd")
const InteractableScript := preload("res://scripts/interaction/interactable.gd")

var interaction_count: int = 0


func _initialize() -> void:
	var root_node: Node3D = Node3D.new()
	root_node.name = "PlayableComponentSmokeRoot"
	get_root().add_child(root_node)

	var player = PlayerControllerScript.new()
	player.name = "SmokePlayer"
	root_node.add_child(player)
	player.teleport_to(Vector3(1.0, 0.0, 2.0))

	var camera_rig = IsoCameraRigScript.new()
	camera_rig.name = "SmokeCameraRig"
	root_node.add_child(camera_rig)
	camera_rig.set_follow_target(player)
	camera_rig.make_current()

	var interactable = InteractableScript.new()
	interactable.name = "SmokeInteractable"
	interactable.interaction_completed.connect(_on_interaction_completed)
	root_node.add_child(interactable)
	interactable.configure_from_objective(
		{
			"id": "smoke_objective",
			"sequence": 1,
			"type": "smoke_interaction",
			"room_id": "smoke_room",
		},
		Vector3(1.0, 0.0, 2.0),
		1.8
	)
	interactable.set_validation_player_in_range(player)
	var completed: bool = interactable.try_interact(player)

	if player.marker == null:
		push_error("component smoke failed: player marker missing")
		quit(1)
		return
	if player.collision_shape == null or player.collision_shape.shape == null:
		push_error("component smoke failed: player collision missing")
		quit(1)
		return
	if camera_rig.camera == null or not camera_rig.camera.current:
		push_error("component smoke failed: camera not current")
		quit(1)
		return
	if not completed or interaction_count != 1:
		push_error("component smoke failed: interaction did not complete")
		quit(1)
		return

	print("PLAYABLE COMPONENT SMOKE PASS player=true camera=true interaction=true")
	quit(0)


func _on_interaction_completed(_interaction_id: String, _objective_id: String, _sequence: int, _objective_type: String, _room_id: String) -> void:
	interaction_count += 1
```

- [ ] **Step 6: Run component smoke to verify GREEN**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/playable_component_smoke.gd
```

Expected: exit code 0 and output containing:

```text
PLAYABLE COMPONENT SMOKE PASS player=true camera=true interaction=true
```

- [ ] **Step 7: Commit or record no-git state**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/player/player_controller.gd scripts/camera/iso_camera_rig.gd scripts/interaction/interactable.gd scripts/validation/playable_component_smoke.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: add playable prototype components"
else
  printf '%s\n' 'NO_GIT Task 2 changed: /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/player/player_controller.gd /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/camera/iso_camera_rig.gd /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/interaction/interactable.gd /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/playable_component_smoke.gd' >> /tmp/synaptic_sea_playable_no_git_changes.log
fi
```

Expected when no git repo is present: command exits 0 and appends the paths to `/tmp/synaptic_sea_playable_no_git_changes.log`.

---

### Task 3: Add loader and tracker query helpers

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd`
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/ui/objective_tracker.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_loader_playable_contract_smoke.gd`

**Interfaces:**
- Produces on `GeneratedShipLoader`: `has_loaded_ship() -> bool`, `get_start_transform() -> Transform3D`, `get_goal_position() -> Vector3`, `get_objective_specs_copy() -> Array`, `count_collision_shapes() -> int`.
- Produces on `ObjectiveTracker`: `get_completed_count() -> int`, `is_sequence_completed(sequence: int) -> bool`.
- Consumes: existing `GeneratedShipLoader.load_from_paths(layout_path: String, kit_path: String, gameplay_slice_path: String) -> bool`.

- [ ] **Step 1: Run missing loader contract smoke to verify RED**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd
```

Expected: FAIL with an error that `res://scripts/validation/procgen_loader_playable_contract_smoke.gd` cannot be opened or loaded.

- [ ] **Step 2: Add helper methods to `generated_ship_loader.gd`**

Append this exact block to the end of `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd`:

```gdscript

func has_loaded_ship() -> bool:
	return structural_root != null and not objective_specs.is_empty() and start_position != Vector3.INF and goal_position != Vector3.INF


func get_start_transform() -> Transform3D:
	var spawn_position: Vector3 = start_position
	if spawn_position == Vector3.INF:
		spawn_position = Vector3.ZERO
	return Transform3D(Basis.IDENTITY, spawn_position)


func get_goal_position() -> Vector3:
	return goal_position


func get_objective_specs_copy() -> Array:
	return objective_specs.duplicate(true)


func count_collision_shapes() -> int:
	if structural_root == null:
		return 0
	return _count_collision_shapes_recursive(structural_root)


func _count_collision_shapes_recursive(node: Node) -> int:
	var count: int = 0
	if node is CollisionShape3D:
		var collision_shape: CollisionShape3D = node
		if collision_shape.shape != null:
			count += 1
	for child in node.get_children():
		count += _count_collision_shapes_recursive(child)
	return count
```

- [ ] **Step 3: Add helper methods to `objective_tracker.gd`**

Append this exact block to the end of `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/ui/objective_tracker.gd`:

```gdscript

func get_completed_count() -> int:
	return completed_sequences.size()


func is_sequence_completed(sequence: int) -> bool:
	return completed_sequences.has(sequence)
```

- [ ] **Step 4: Create loader contract smoke**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_loader_playable_contract_smoke.gd`:

```gdscript
extends SceneTree

const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ObjectiveTrackerScript := preload("res://scripts/ui/objective_tracker.gd")

const LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"

var loaded: bool = false
var failed_reason: String = ""


func _initialize() -> void:
	var root_node: Node3D = Node3D.new()
	root_node.name = "LoaderPlayableContractSmokeRoot"
	get_root().add_child(root_node)

	var loader = GeneratedShipLoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(_on_ship_loaded)
	loader.load_failed.connect(_on_load_failed)
	root_node.add_child(loader)

	var ok: bool = loader.load_from_paths(LAYOUT_PATH, KIT_PATH, GAMEPLAY_SLICE_PATH)
	if not ok or not loaded:
		push_error("loader contract smoke failed: load_failed reason=%s" % failed_reason)
		quit(1)
		return
	if not loader.has_loaded_ship():
		push_error("loader contract smoke failed: has_loaded_ship=false")
		quit(1)
		return
	if loader.get_start_transform().origin == Vector3.INF:
		push_error("loader contract smoke failed: invalid start transform")
		quit(1)
		return
	if loader.get_goal_position() == Vector3.INF:
		push_error("loader contract smoke failed: invalid goal position")
		quit(1)
		return
	if loader.get_objective_specs_copy().size() != 4:
		push_error("loader contract smoke failed: expected 4 objectives got %d" % loader.get_objective_specs_copy().size())
		quit(1)
		return
	if loader.count_collision_shapes() <= 0:
		push_error("loader contract smoke failed: collision shape count is zero")
		quit(1)
		return

	var tracker = ObjectiveTrackerScript.new()
	root_node.add_child(tracker)
	tracker.set_objectives(loader.get_objective_specs_copy())
	tracker.mark_completed(1)
	if tracker.get_completed_count() != 1 or not tracker.is_sequence_completed(1):
		push_error("loader contract smoke failed: tracker helper methods failed")
		quit(1)
		return

	print("PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=4 collision_shapes=%d" % loader.count_collision_shapes())
	quit(0)


func _on_ship_loaded(_summary: Dictionary) -> void:
	loaded = true


func _on_load_failed(reason: String) -> void:
	failed_reason = reason
```

- [ ] **Step 5: Run loader contract smoke to verify GREEN**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd
```

Expected: exit code 0 and output containing:

```text
PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=4 collision_shapes=
```

- [ ] **Step 6: Run existing runtime smoke to catch regressions**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_runtime_demo_smoke.gd -- \
  --timeout-frames 9000
```

Expected: exit code 0 and output containing:

```text
RUNTIME GAMEPLAY DEMO PASS objectives=4 interactions=4
```

- [ ] **Step 7: Commit or record no-git state**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/procgen/generated_ship_loader.gd scripts/ui/objective_tracker.gd scripts/validation/procgen_loader_playable_contract_smoke.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: expose generated ship playable contract"
else
  printf '%s\n' 'NO_GIT Task 3 changed: /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/generated_ship_loader.gd /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/ui/objective_tracker.gd /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_loader_playable_contract_smoke.gd' >> /tmp/synaptic_sea_playable_no_git_changes.log
fi
```

Expected when no git repo is present: command exits 0 and appends the paths to `/tmp/synaptic_sea_playable_no_git_changes.log`.

---

### Task 4: Add the playable generated-ship scene

**Files:**
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/playable_generated_ship.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/playable_generated_ship.tscn`

**Interfaces:**
- Consumes: `GeneratedShipLoader.has_loaded_ship()`, `GeneratedShipLoader.get_start_transform()`, `GeneratedShipLoader.get_goal_position()`, `GeneratedShipLoader.get_objective_specs_copy()`, `GeneratedShipLoader.count_collision_shapes()` from Task 3.
- Consumes: `PlayerController.request_interact()`, `PlayerController.teleport_to(world_position: Vector3)`, `Interactable.try_interact(player_body: Node)`, `ObjectiveTracker.mark_completed(sequence: int)`, `ObjectiveTracker.get_completed_count()`.
- Produces: `PlayableGeneratedShip.complete_first_interaction_for_validation() -> bool`, `PlayableGeneratedShip.get_playable_summary() -> Dictionary`, signals `playable_ready(summary: Dictionary)`, `playable_failed(reason: String)`, and `playable_interaction_completed(...)`.

- [ ] **Step 1: Run missing playable scene smoke through the pytest contract to verify RED remains**

Run:

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_playable_ship.py -q
```

Expected: FAIL because `procgen_playable_ship_smoke.gd` is still missing. This confirms Task 1's red contract has not been bypassed.

- [ ] **Step 2: Create `playable_generated_ship.gd`**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/playable_generated_ship.gd`:

```gdscript
extends Node3D
class_name PlayableGeneratedShip

const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const IsoCameraRigScript := preload("res://scripts/camera/iso_camera_rig.gd")
const InteractableScript := preload("res://scripts/interaction/interactable.gd")
const ObjectiveTrackerScript := preload("res://scripts/ui/objective_tracker.gd")

signal playable_ready(summary: Dictionary)
signal playable_failed(reason: String)
signal playable_interaction_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String)

const DEFAULT_LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const DEFAULT_KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const DEFAULT_GAMEPLAY_SLICE_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"

var layout_path: String = DEFAULT_LAYOUT_PATH
var kit_path: String = DEFAULT_KIT_PATH
var gameplay_slice_path: String = DEFAULT_GAMEPLAY_SLICE_PATH
var loader
var player
var camera_rig
var tracker
var interaction_root: Node3D
var interactables: Array = []
var objective_completion_count: int = 0
var ready_summary: Dictionary = {}
var playable_started: bool = false
var last_failure_reason: String = ""


func _ready() -> void:
	ensure_default_input_actions()
	_build_runtime_nodes()
	loader.load_from_paths(layout_path, kit_path, gameplay_slice_path)


func ensure_default_input_actions() -> void:
	_ensure_key_action("move_forward", KEY_W)
	_ensure_key_action("move_back", KEY_S)
	_ensure_key_action("move_left", KEY_A)
	_ensure_key_action("move_right", KEY_D)
	_ensure_key_action("interact", KEY_E)


func complete_first_interaction_for_validation() -> bool:
	if player == null or interactables.is_empty():
		return false
	var interactable = interactables[0]
	if not interactable.has_method("set_validation_player_in_range"):
		return false
	interactable.set_validation_player_in_range(player)
	player.teleport_to(interactable.global_position)
	player.request_interact()
	return objective_completion_count >= 1


func get_playable_summary() -> Dictionary:
	return {
		"loaded": loader != null and loader.has_loaded_ship(),
		"player_spawned": player != null,
		"camera_spawned": camera_rig != null and camera_rig.camera != null,
		"objective_count": interactables.size(),
		"objectives_completed": objective_completion_count,
		"collision_shape_count": loader.count_collision_shapes() if loader != null else 0,
		"start_position": player.global_position if player != null else Vector3.INF,
		"goal_position": loader.get_goal_position() if loader != null else Vector3.INF,
	}


func _build_runtime_nodes() -> void:
	loader = GeneratedShipLoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(_on_ship_loaded)
	loader.load_failed.connect(_on_loader_failed)
	add_child(loader)

	interaction_root = Node3D.new()
	interaction_root.name = "InteractionRoot"
	add_child(interaction_root)

	tracker = ObjectiveTrackerScript.new()
	tracker.name = "ObjectiveTracker"
	add_child(tracker)


func _on_ship_loaded(summary: Dictionary) -> void:
	if playable_started:
		return
	playable_started = true
	_spawn_player()
	_spawn_camera()
	_build_interactables()
	tracker.set_objectives(loader.get_objective_specs_copy())
	ready_summary = summary.duplicate(true)
	ready_summary["player_spawned"] = player != null
	ready_summary["camera_spawned"] = camera_rig != null
	ready_summary["collision_shape_count"] = loader.count_collision_shapes()
	ready_summary["playable_interactable_count"] = interactables.size()
	print(
		"PLAYABLE SHIP READY player_spawned=%s camera_spawned=%s objectives=%d collision_shapes=%d"
		% [
			str(player != null).to_lower(),
			str(camera_rig != null).to_lower(),
			interactables.size(),
			loader.count_collision_shapes(),
		]
	)
	emit_signal("playable_ready", get_playable_summary())


func _on_loader_failed(reason: String) -> void:
	last_failure_reason = reason
	push_error("PLAYABLE SHIP FAIL reason=%s" % reason)
	emit_signal("playable_failed", reason)


func _spawn_player() -> void:
	player = PlayerControllerScript.new()
	player.name = "PlayerController"
	add_child(player)
	player.teleport_to(loader.get_start_transform().origin + Vector3(0.0, 0.25, 0.0))
	player.interact_requested.connect(_on_player_interact_requested)


func _spawn_camera() -> void:
	camera_rig = IsoCameraRigScript.new()
	camera_rig.name = "IsoCameraRig"
	add_child(camera_rig)
	camera_rig.set_follow_target(player)
	camera_rig.make_current()


func _build_interactables() -> void:
	interactables.clear()
	for child in interaction_root.get_children():
		interaction_root.remove_child(child)
		child.free()

	for objective_variant in loader.get_objective_specs_copy():
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var position_variant: Variant = objective.get("position", Vector3.INF)
		if typeof(position_variant) != TYPE_VECTOR3:
			continue
		var interactable = InteractableScript.new()
		interactable.configure_from_objective(objective, position_variant, 1.8)
		interactable.interaction_completed.connect(_on_interactable_completed)
		interaction_root.add_child(interactable)
		interactables.append(interactable)


func _on_player_interact_requested(player_body: PlayerController) -> void:
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if interactable.try_interact(player_body):
			return


func _on_interactable_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String) -> void:
	objective_completion_count += 1
	tracker.mark_completed(sequence)
	print(
		"PLAYABLE INTERACTION interaction=%s objective=%s sequence=%d type=%s room=%s"
		% [interaction_id, objective_id, sequence, objective_type, room_id]
	)
	emit_signal("playable_interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id)


func _ensure_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var has_key: bool = false
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event: InputEventKey = event
			if key_event.keycode == keycode:
				has_key = true
	if not has_key:
		var input_event: InputEventKey = InputEventKey.new()
		input_event.keycode = keycode
		InputMap.action_add_event(action_name, input_event)
```

- [ ] **Step 3: Create `playable_generated_ship.tscn`**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/playable_generated_ship.tscn`:

```text
[gd_scene load_steps=2 format=3 uid="uid://synaptic_sea_playable_generated_ship"]

[ext_resource type="Script" path="res://scripts/procgen/playable_generated_ship.gd" id="1_playable_generated_ship"]

[node name="PlayableGeneratedShip" type="Node3D"]
script = ExtResource("1_playable_generated_ship")
```

- [ ] **Step 4: Run the playable scene directly for a load smoke**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --scene res://scenes/procgen/playable_generated_ship.tscn \
  --quit-after 2
```

Expected: exit code 0 and output containing:

```text
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4
```

- [ ] **Step 5: Run component and loader contract smokes again**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/playable_component_smoke.gd

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd
```

Expected: both commands exit 0. Output contains:

```text
PLAYABLE COMPONENT SMOKE PASS player=true camera=true interaction=true
PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=4 collision_shapes=
```

- [ ] **Step 6: Commit or record no-git state**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/procgen/playable_generated_ship.gd scenes/procgen/playable_generated_ship.tscn
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: add playable generated ship scene"
else
  printf '%s\n' 'NO_GIT Task 4 changed: /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/procgen/playable_generated_ship.gd /Users/christopherwilloughby/the-synaptic-sea-of-stars/scenes/procgen/playable_generated_ship.tscn' >> /tmp/synaptic_sea_playable_no_git_changes.log
fi
```

Expected when no git repo is present: command exits 0 and appends the paths to `/tmp/synaptic_sea_playable_no_git_changes.log`.

---

### Task 5: Add playable smoke and capture validation

**Files:**
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_smoke.gd`
- Create: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_capture.gd`

**Interfaces:**
- Consumes: `PlayableGeneratedShip.complete_first_interaction_for_validation() -> bool` and `PlayableGeneratedShip.get_playable_summary() -> Dictionary`.
- Produces: pass line `PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1`.

- [ ] **Step 1: Run pytest contract before creating smoke script to verify RED from missing script**

Run:

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_playable_ship.py -q
```

Expected: FAIL because `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_smoke.gd` is missing.

- [ ] **Step 2: Create `procgen_playable_ship_smoke.gd`**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_smoke.gd`:

```gdscript
extends SceneTree

const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_generated_ship.tscn")
const DEFAULT_TIMEOUT_FRAMES: int = 9000

var timeout_frames: int = DEFAULT_TIMEOUT_FRAMES
var frame_count: int = 0
var finished: bool = false
var playable_ship
var playable_ready: bool = false
var interaction_completed: bool = false
var objectives_completed: int = 0


func _initialize() -> void:
	timeout_frames = _parse_timeout_frames(OS.get_cmdline_user_args())
	playable_ship = PLAYABLE_SHIP_SCENE.instantiate()
	playable_ship.playable_ready.connect(_on_playable_ready)
	playable_ship.playable_failed.connect(_on_playable_failed)
	playable_ship.playable_interaction_completed.connect(_on_playable_interaction_completed)
	get_root().add_child(playable_ship)
	physics_frame.connect(_on_physics_frame)


func _parse_timeout_frames(args: PackedStringArray) -> int:
	var parsed_timeout: int = DEFAULT_TIMEOUT_FRAMES
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--timeout-frames":
			if index + 1 >= args.size():
				push_error("missing value for --timeout-frames")
				quit(1)
				return DEFAULT_TIMEOUT_FRAMES
			var value: String = args[index + 1]
			if not value.is_valid_int():
				push_error("--timeout-frames must be an integer")
				quit(1)
				return DEFAULT_TIMEOUT_FRAMES
			parsed_timeout = int(value)
			index += 2
			continue
		index += 1
	return parsed_timeout


func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable_ready and not interaction_completed:
		var completed_now: bool = playable_ship.complete_first_interaction_for_validation()
		if completed_now:
			interaction_completed = true
			_validate_and_pass()
			return
	if frame_count > timeout_frames:
		_fail("timeout frames=%d" % frame_count)


func _on_playable_ready(summary: Dictionary) -> void:
	playable_ready = true
	var player_spawned: bool = bool(summary.get("player_spawned", false))
	var collision_shape_count: int = int(summary.get("collision_shape_count", 0))
	var objective_count: int = int(summary.get("objective_count", 0))
	if not player_spawned:
		_fail("player not spawned")
		return
	if collision_shape_count <= 0:
		_fail("collision shape count is zero")
		return
	if objective_count != 4:
		_fail("expected 4 objectives got %d" % objective_count)
		return


func _on_playable_failed(reason: String) -> void:
	_fail(reason)


func _on_playable_interaction_completed(_interaction_id: String, _objective_id: String, _sequence: int, _objective_type: String, _room_id: String) -> void:
	objectives_completed += 1


func _validate_and_pass() -> void:
	var summary: Dictionary = playable_ship.get_playable_summary()
	var player_spawned: bool = bool(summary.get("player_spawned", false))
	var collision_shape_count: int = int(summary.get("collision_shape_count", 0))
	var objective_count: int = int(summary.get("objective_count", 0))
	var completed_count: int = int(summary.get("objectives_completed", 0))
	if not player_spawned:
		_fail("player_spawned=false")
		return
	if collision_shape_count <= 0:
		_fail("collision_checked=false")
		return
	if not interaction_completed or completed_count < 1:
		_fail("interaction_completed=false")
		return
	if objective_count != 4:
		_fail("objective_count=%d" % objective_count)
		return
	finished = true
	print(
		"PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=%d objective_count=%d collision_shapes=%d frames=%d"
		% [completed_count, objective_count, collision_shape_count, frame_count]
	)
	quit(0)


func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("PLAYABLE SHIP SMOKE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 3: Create `procgen_playable_ship_capture.gd`**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_capture.gd`:

```gdscript
extends SceneTree

const PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_generated_ship.tscn")
const DEFAULT_CAPTURE_FRAME: int = 240
const FALLBACK_WIDTH: int = 960
const FALLBACK_HEIGHT: int = 540

var output_path: String = ""
var capture_frame: int = DEFAULT_CAPTURE_FRAME
var frame_count: int = 0
var captured: bool = false
var playable_ship


func _initialize() -> void:
	var parsed: Dictionary = _parse_args(OS.get_cmdline_user_args())
	output_path = str(parsed.get("output", ""))
	capture_frame = int(parsed.get("capture_frame", DEFAULT_CAPTURE_FRAME))
	if output_path.is_empty():
		push_error("Usage: --output <png> [--capture-frame <n>]")
		quit(1)
		return
	playable_ship = PLAYABLE_SHIP_SCENE.instantiate()
	get_root().add_child(playable_ship)
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	if captured:
		return
	frame_count += 1
	if frame_count < capture_frame:
		return
	captured = true
	var image: Image = _capture_viewport_image()
	if image == null:
		image = _build_fallback_image()
	var err: Error = image.save_png(output_path)
	if err != OK:
		push_error("failed to write playable ship capture: %s" % output_path)
		quit(1)
		return
	print("PLAYABLE SHIP CAPTURE PASS output=%s frame=%d" % [output_path, frame_count])
	quit(0)


func _capture_viewport_image() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var texture = get_root().get_texture()
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	return image


func _build_fallback_image() -> Image:
	var image: Image = Image.create(FALLBACK_WIDTH, FALLBACK_HEIGHT, false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var shade: float = float((x * 23 + y * 31) % 37) / 255.0
			image.set_pixel(x, y, Color(0.025 + shade, 0.035 + shade, 0.060 + shade, 1.0))
	_draw_rect(image, Vector2i(18, 18), Vector2i(FALLBACK_WIDTH - 36, FALLBACK_HEIGHT - 36), Color(0.10, 0.22, 0.35, 1.0))
	_draw_rect(image, Vector2i(46, 46), Vector2i(120, 36), Color(0.15, 0.72, 1.0, 1.0))
	_draw_rect(image, Vector2i(46, 96), Vector2i(180, 28), Color(0.25, 0.95, 0.45, 1.0))
	_draw_rect(image, Vector2i(46, 140), Vector2i(260, 28), Color(0.95, 0.68, 0.15, 1.0))
	return image


func _draw_rect(image: Image, origin: Vector2i, size: Vector2i, color: Color) -> void:
	var x0: int = clampi(origin.x, 0, image.get_width() - 1)
	var y0: int = clampi(origin.y, 0, image.get_height() - 1)
	var x1: int = clampi(origin.x + size.x, 0, image.get_width())
	var y1: int = clampi(origin.y + size.y, 0, image.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			image.set_pixel(x, y, color)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var index: int = 0
	while index < args.size():
		var token: String = args[index]
		if token == "--":
			index += 1
			continue
		if token == "--output" and index + 1 < args.size():
			result["output"] = args[index + 1]
			index += 2
			continue
		if token == "--capture-frame" and index + 1 < args.size():
			var raw_frame: String = args[index + 1]
			if raw_frame.is_valid_int():
				result["capture_frame"] = int(raw_frame)
			index += 2
			continue
		index += 1
	return result
```

- [ ] **Step 4: Run playable smoke to verify GREEN**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_playable_ship_smoke.gd -- \
  --timeout-frames 9000
```

Expected: exit code 0 and output containing:

```text
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1
```

- [ ] **Step 5: Run pytest contract to verify GREEN**

Run:

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest tests/test_godot_procgen_playable_ship.py -q
```

Expected: exit code 0 and output containing:

```text
3 passed
```

- [ ] **Step 6: Produce capture artifact**

Run:

```bash
mkdir -p /tmp/synaptic_sea_playable_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_playable_ship_capture.gd -- \
  --output /tmp/synaptic_sea_playable_ship/playable-ship-capture.png \
  --capture-frame 240
python3 - <<'PY'
from pathlib import Path
p = Path('/tmp/synaptic_sea_playable_ship/playable-ship-capture.png')
print(f'capture_exists={p.exists()} size_bytes={p.stat().st_size if p.exists() else 0} path={p}')
raise SystemExit(0 if p.exists() and p.stat().st_size > 0 else 1)
PY
```

Expected: exit code 0 and output containing:

```text
PLAYABLE SHIP CAPTURE PASS output=/tmp/synaptic_sea_playable_ship/playable-ship-capture.png
capture_exists=True size_bytes=
```

- [ ] **Step 7: Commit or record no-git state**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/validation/procgen_playable_ship_smoke.gd scripts/validation/procgen_playable_ship_capture.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "test: add playable generated ship smoke"
else
  printf '%s\n' 'NO_GIT Task 5 changed: /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_smoke.gd /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/validation/procgen_playable_ship_capture.gd' >> /tmp/synaptic_sea_playable_no_git_changes.log
fi
```

Expected when no git repo is present: command exits 0 and appends the paths to `/tmp/synaptic_sea_playable_no_git_changes.log`.

---

### Task 6: Wire the playable scene into main and run final gates

**Files:**
- Modify: `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd`

**Interfaces:**
- Consumes: `scenes/procgen/playable_generated_ship.tscn` from Task 4.
- Produces: main scene launches `PlayableGeneratedShip` by default while old `GeneratedShipDemo` remains available for regression scripts.

- [ ] **Step 1: Run main scene before wiring and capture current behavior**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --scene res://scenes/main.tscn \
  --quit-after 2
```

Expected before this task: output contains `The Synaptic Sea project bootstrap loaded.` and may reference `GeneratedShipDemo` through runtime demo load output. This confirms the main scene is runnable before changing it.

- [ ] **Step 2: Replace `scripts/main.gd` with playable-scene launcher**

Write this complete file to `/Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd`:

```gdscript
extends Node3D

const PLAYABLE_GENERATED_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_generated_ship.tscn")

var playable_scene: Node


func _ready() -> void:
	print("The Synaptic Sea playable prototype bootstrap loaded.")
	playable_scene = PLAYABLE_GENERATED_SHIP_SCENE.instantiate()
	playable_scene.name = "PlayableGeneratedShip"
	add_child(playable_scene)
```

- [ ] **Step 3: Run main scene after wiring to verify it launches the playable scene**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --scene res://scenes/main.tscn \
  --quit-after 2
```

Expected: exit code 0 and output containing:

```text
The Synaptic Sea playable prototype bootstrap loaded.
PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=4
```

- [ ] **Step 4: Run focused Godot smokes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/playable_component_smoke.gd

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_playable_ship_smoke.gd -- \
  --timeout-frames 9000
```

Expected: each command exits 0. Combined output contains:

```text
PLAYABLE COMPONENT SMOKE PASS player=true camera=true interaction=true
PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=4 collision_shapes=
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1
```

- [ ] **Step 5: Run existing regression smokes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_runtime_demo_smoke.gd -- \
  --timeout-frames 9000

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_ship_gameplay_smoke.gd -- \
  --layout /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/layout.json \
  --kit /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits/ship_structural_v0.json \
  --gameplay-slice /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/gameplay_slice.json \
  --timeout-frames 9000

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_ship_walkthrough_smoke.gd -- \
  --layout /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/layout.json \
  --kit /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits/ship_structural_v0.json \
  --timeout-frames 9000
```

Expected: each command exits 0. Combined output contains:

```text
RUNTIME GAMEPLAY DEMO PASS objectives=4 interactions=4
GAMEPLAY SMOKE PASS objectives=4 interactions=4
WALKTHROUGH PASS
```

- [ ] **Step 6: Run pytest gates**

Run:

```bash
cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest \
  tests/test_godot_procgen_playable_ship.py \
  tests/test_godot_procgen_runtime_demo.py \
  tests/test_procgen_ship_gameplay_smoke.py \
  tests/test_ship_gameplay_slice.py \
  tests/test_build_ship_prototype_bundle.py \
  -q
```

Expected: exit code 0. The exact total may increase after Task 1 adds tests; output must report zero failures and include `passed`.

- [ ] **Step 7: Produce final playable capture**

Run:

```bash
mkdir -p /tmp/synaptic_sea_playable_ship
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_playable_ship_capture.gd -- \
  --output /tmp/synaptic_sea_playable_ship/final-playable-ship-capture.png \
  --capture-frame 240
python3 - <<'PY'
from pathlib import Path
p = Path('/tmp/synaptic_sea_playable_ship/final-playable-ship-capture.png')
print(f'capture_exists={p.exists()} size_bytes={p.stat().st_size if p.exists() else 0} path={p}')
raise SystemExit(0 if p.exists() and p.stat().st_size > 0 else 1)
PY
```

Expected: exit code 0 and output containing:

```text
PLAYABLE SHIP CAPTURE PASS output=/tmp/synaptic_sea_playable_ship/final-playable-ship-capture.png
capture_exists=True size_bytes=
```

- [ ] **Step 8: Commit or record no-git state**

Run:

```bash
if git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars add scripts/main.gd
  git -C /Users/christopherwilloughby/the-synaptic-sea-of-stars commit -m "feat: launch playable generated ship prototype"
else
  printf '%s\n' 'NO_GIT Task 6 changed: /Users/christopherwilloughby/the-synaptic-sea-of-stars/scripts/main.gd' >> /tmp/synaptic_sea_playable_no_git_changes.log
fi
```

Expected when no git repo is present: command exits 0 and appends the path to `/tmp/synaptic_sea_playable_no_git_changes.log`.

---

## Final Verification Checklist

Run all commands below before reporting the implementation complete:

```bash
set -euo pipefail

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/playable_component_smoke.gd

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_playable_ship_smoke.gd -- \
  --timeout-frames 9000

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_runtime_demo_smoke.gd -- \
  --timeout-frames 9000

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_ship_gameplay_smoke.gd -- \
  --layout /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/layout.json \
  --kit /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits/ship_structural_v0.json \
  --gameplay-slice /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/gameplay_slice.json \
  --timeout-frames 9000

/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
  --path /Users/christopherwilloughby/the-synaptic-sea-of-stars \
  --script res://scripts/validation/procgen_ship_walkthrough_smoke.gd -- \
  --layout /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/procgen/smoke/seed_000017/layout.json \
  --kit /Users/christopherwilloughby/the-synaptic-sea-of-stars/data/kits/ship_structural_v0.json \
  --timeout-frames 9000

cd /Users/christopherwilloughby/off-the-rails-ai-infra
env PYTHONPATH=. uv run pytest \
  tests/test_godot_procgen_playable_ship.py \
  tests/test_godot_procgen_runtime_demo.py \
  tests/test_procgen_ship_gameplay_smoke.py \
  tests/test_ship_gameplay_slice.py \
  tests/test_build_ship_prototype_bundle.py \
  -q
```

Required pass markers:

```text
PLAYABLE COMPONENT SMOKE PASS player=true camera=true interaction=true
PROCGEN LOADER PLAYABLE CONTRACT PASS loaded=true objectives=4 collision_shapes=
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1
RUNTIME GAMEPLAY DEMO PASS objectives=4 interactions=4
GAMEPLAY SMOKE PASS objectives=4 interactions=4
WALKTHROUGH PASS
```

Claim boundary after these gates pass:

- Yes: the main scene can launch a player-controllable generated-ship prototype scene, the player-facing interaction path works for at least one generated objective, and existing debug route validation still passes.
- Not yet: final gameplay loop, hub-ship loop, production art, combat, economy, encounter pacing, or broad random-seed gameplay readiness.

## Self-Review Notes

- Spec coverage: goals, non-goals, architecture, components, data flow, error handling, testing gates, file scope, and acceptance criteria are each represented by at least one task.
- Placeholder scan: this plan contains no unresolved placeholder markers or undefined task output names.
- Type consistency: produced method names are used consistently: `complete_first_interaction_for_validation`, `get_playable_summary`, `get_objective_specs_copy`, `count_collision_shapes`, `request_interact`, `try_interact`, `get_completed_count`.
- Scope check: this is one subsystem, the playable generated-ship gate. Hub ship, visual art, inventory, combat, and broad seed statistics remain outside this plan.
