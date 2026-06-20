# Main Playable Slice v2 Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace debug-text/colored-block readability with semantic in-engine props and navigation cues in the actual Godot main scene while preserving the existing playable objective loop.

**Architecture:** Keep `GeneratedShipLoader` as the source of loaded ship/marker data. Add a focused readability prop factory that builds simple semantic Godot primitive props, then have `PlayableGeneratedShip` instantiate those props from existing objective, blocker, vertical, start, destination, and critical-path marker data. Validation remains Godot-script based and proves props/readability on the main path, not a separate mockup.

**Tech Stack:** Godot 4.6.2 GDScript, existing `SceneTree` validation scripts, macOS `sips`/`shasum` for capture metadata, no external art assets.

## Global Constraints

- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Project root: `/Users/christopherwilloughby/the-sargasso-of-stars`.
- Workspace state: no git repository; use `/tmp/sargasso_main_playable_slice_v2_readability_no_git_changes.log` for record steps instead of assuming commits.
- Main scene path must remain `res://scenes/main.tscn`.
- Do not move player input, HUD, camera, or gameplay-prop behavior into `GeneratedShipLoader`.
- Preserve the interaction chain: `Player.request_interact()` -> `interact_requested` signal -> `PlayableGeneratedShip._on_player_interact_requested` -> `Interactable.try_interact(player_body)` -> objective advance.
- Do not add combat, inventory, save/load, resource drain, enemies, final art, asset-pack ingestion, broad procgen rewrites, or new objectives.
- Normal gameplay/capture mode must use semantic props and must not rely on giant in-world `Label3D` text for readability.
- Existing v1 pass markers must remain green unless a task explicitly says to add a new marker.

---

## File Structure

- Create `scripts/procgen/readability_prop_factory.gd`
  - Single responsibility: build simple semantic `Node3D` props using Godot primitive meshes/materials.
  - Exposes static factory methods consumed by `PlayableGeneratedShip`.
- Modify `scripts/procgen/playable_generated_ship.gd`
  - Consumes loader markers/objective data and the prop factory.
  - Builds semantic props under existing `affordance_root`.
  - Exposes `get_readability_summary()` for validation.
  - Keeps optional debug labels off in normal mode.
- Modify `scripts/interaction/interactable.gd`
  - Adds explicit control over the old translucent interaction marker so normal mode can hide debug spheres while preserving interaction collision.
- Create `scripts/validation/readability_prop_factory_smoke.gd`
  - Proves the factory creates the required semantic prop kinds without loading the full scene.
- Create `scripts/validation/main_playable_slice_readability_smoke.gd`
  - Proves the actual main scene exposes objective props, blocker, ramp cue, entry beacon, destination marker, route cues, and no visible debug label clutter.
- Modify `scripts/validation/main_playable_slice_affordance_smoke.gd`
  - Keeps the existing pass marker, but validates semantic prop affordances instead of requiring visible blocked/ramp label text.
- Modify `scripts/validation/main_playable_slice_capture_sequence.gd`
  - Captures the actual semantic props in normal mode and fails if visible `Label3D` clutter is present.
- Create `docs/superpowers/proofs/main-playable-slice-v2-readability.md`
  - Records the final validation bundle, capture paths, visual-inspection note, and limitations.

---

### Task 1: Semantic Prop Factory and Factory Smoke

**Files:**
- Create: `scripts/procgen/readability_prop_factory.gd`
- Create: `scripts/validation/readability_prop_factory_smoke.gd`

**Interfaces:**
- Produces: `ReadabilityPropFactory.create_objective_prop(sequence: int, objective_type: String) -> Node3D`
- Produces: `ReadabilityPropFactory.create_blocked_biomatter() -> Node3D`
- Produces: `ReadabilityPropFactory.create_ramp_cue() -> Node3D`
- Produces: `ReadabilityPropFactory.create_entry_beacon() -> Node3D`
- Produces: `ReadabilityPropFactory.create_destination_reactor_core() -> Node3D`
- Produces: `ReadabilityPropFactory.create_route_cue(index: int, from_pos: Vector3, to_pos: Vector3) -> Node3D`
- Later tasks rely on returned nodes having metadata key `readability_kind` and stable semantic names.

- [ ] **Step 1: Create the failing factory smoke**

Create `scripts/validation/readability_prop_factory_smoke.gd`:

```gdscript
extends SceneTree

const FactoryScript := preload("res://scripts/procgen/readability_prop_factory.gd")

var finished: bool = false

func _initialize() -> void:
	var checks: Array[Dictionary] = [
		{"name": "ObjectiveAffordance_01_ObjectiveSupplyCache", "node": FactoryScript.create_objective_prop(1, "recover_supplies"), "kind": "ObjectiveSupplyCache"},
		{"name": "ObjectiveAffordance_02_ObjectiveBreakerPanel", "node": FactoryScript.create_objective_prop(2, "restore_systems"), "kind": "ObjectiveBreakerPanel"},
		{"name": "ObjectiveAffordance_03_ObjectiveMedTerminal", "node": FactoryScript.create_objective_prop(3, "download_logs"), "kind": "ObjectiveMedTerminal"},
		{"name": "ObjectiveAffordance_04_ObjectiveReactorConsole", "node": FactoryScript.create_objective_prop(4, "stabilize_reactor"), "kind": "ObjectiveReactorConsole"},
		{"name": "BlockedAffordance_01_BlockedBiomatter", "node": FactoryScript.create_blocked_biomatter(), "kind": "BlockedBiomatter"},
		{"name": "VerticalAffordance_01_RampCue", "node": FactoryScript.create_ramp_cue(), "kind": "RampCue"},
		{"name": "EntryBeacon", "node": FactoryScript.create_entry_beacon(), "kind": "EntryBeacon"},
		{"name": "DestinationReactorCore", "node": FactoryScript.create_destination_reactor_core(), "kind": "DestinationReactorCore"},
	]
	for check in checks:
		_validate_prop(check["node"], str(check["name"]), str(check["kind"]))
		if finished:
			return
	var cue: Node3D = FactoryScript.create_route_cue(1, Vector3.ZERO, Vector3(4.0, 0.0, 0.0))
	_validate_prop(cue, "RouteCue_01", "RouteCue")
	if finished:
		return
	finished = true
	print("READABILITY PROP FACTORY PASS props=9")
	quit(0)

func _validate_prop(node: Node3D, expected_name: String, expected_kind: String) -> void:
	if node == null:
		_fail("node null for %s" % expected_name)
		return
	if node.name != expected_name:
		_fail("name mismatch expected=%s actual=%s" % [expected_name, node.name])
		return
	if str(node.get_meta("readability_kind", "")) != expected_kind:
		_fail("kind mismatch expected=%s actual=%s" % [expected_kind, str(node.get_meta("readability_kind", ""))])
		return
	if node.get_child_count() <= 0:
		_fail("prop has no visible children name=%s" % node.name)
		return
	var visual_count: int = 0
	for child in node.get_children():
		if child is MeshInstance3D or child is OmniLight3D or child is Marker3D:
			visual_count += 1
	if visual_count <= 0:
		_fail("prop lacks visual child name=%s" % node.name)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("READABILITY PROP FACTORY FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the factory smoke to verify it fails before implementation**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/readability_prop_factory_smoke.gd
```

Expected: exit `1` with a preload/parse failure because `res://scripts/procgen/readability_prop_factory.gd` does not exist yet.

- [ ] **Step 3: Create the prop factory implementation**

Create `scripts/procgen/readability_prop_factory.gd`:

```gdscript
extends RefCounted
class_name ReadabilityPropFactory

static func create_objective_prop(sequence: int, objective_type: String) -> Node3D:
	match objective_type:
		"recover_supplies":
			return _objective_supply_cache(sequence)
		"restore_systems":
			return _objective_breaker_panel(sequence)
		"download_logs":
			return _objective_med_terminal(sequence)
		"stabilize_reactor":
			return _objective_reactor_console(sequence)
		_:
			var fallback: Node3D = _base_prop("ObjectiveAffordance_%02d_ObjectiveGeneric" % sequence, "ObjectiveGeneric")
			_add_box(fallback, "GenericObjectiveBody", Vector3(0.9, 0.55, 0.65), Vector3(0.0, 0.35, 0.0), Color(0.35, 0.95, 0.55, 1.0), true)
			return fallback

static func create_blocked_biomatter() -> Node3D:
	var root: Node3D = _base_prop("BlockedAffordance_01_BlockedBiomatter", "BlockedBiomatter")
	_add_box(root, "BlockedMembrane", Vector3(1.7, 0.9, 0.22), Vector3(0.0, 0.55, 0.0), Color(0.95, 0.12, 0.12, 1.0), true)
	_add_sphere(root, "BiomatterNodeLeft", 0.32, Vector3(-0.55, 0.75, 0.0), Color(0.55, 0.05, 0.09, 1.0), true)
	_add_sphere(root, "BiomatterNodeRight", 0.26, Vector3(0.58, 0.42, 0.02), Color(0.70, 0.08, 0.12, 1.0), true)
	return root

static func create_ramp_cue() -> Node3D:
	var root: Node3D = _base_prop("VerticalAffordance_01_RampCue", "RampCue")
	_add_box(root, "RampArrowStem", Vector3(0.28, 0.10, 1.35), Vector3(0.0, 0.12, 0.0), Color(1.0, 0.82, 0.24, 1.0), true)
	_add_box(root, "RampArrowHead", Vector3(0.80, 0.12, 0.40), Vector3(0.0, 0.14, -0.72), Color(1.0, 0.92, 0.35, 1.0), true)
	return root

static func create_entry_beacon() -> Node3D:
	var root: Node3D = _base_prop("EntryBeacon", "EntryBeacon")
	_add_cylinder(root, "EntryBeaconPost", 0.16, 1.20, Vector3(0.0, 0.62, 0.0), Color(0.15, 0.90, 1.0, 1.0), true)
	_add_sphere(root, "EntryBeaconGlow", 0.30, Vector3(0.0, 1.32, 0.0), Color(0.25, 0.95, 1.0, 1.0), true)
	return root

static func create_destination_reactor_core() -> Node3D:
	var root: Node3D = _base_prop("DestinationReactorCore", "DestinationReactorCore")
	_add_cylinder(root, "ReactorColumn", 0.34, 1.55, Vector3(0.0, 0.78, 0.0), Color(0.10, 0.70, 1.0, 1.0), true)
	_add_sphere(root, "ReactorGlow", 0.48, Vector3(0.0, 1.62, 0.0), Color(0.25, 0.95, 1.0, 1.0), true)
	return root

static func create_route_cue(index: int, from_pos: Vector3, to_pos: Vector3) -> Node3D:
	var root: Node3D = _base_prop("RouteCue_%02d" % index, "RouteCue")
	var delta: Vector3 = to_pos - from_pos
	var distance: float = max(delta.length(), 0.5)
	root.position = from_pos.lerp(to_pos, 0.5) + Vector3(0.0, 0.04, 0.0)
	if abs(delta.x) > 0.001 or abs(delta.z) > 0.001:
		root.rotation.y = atan2(delta.x, delta.z)
	_add_box(root, "RouteCueStrip", Vector3(0.18, 0.035, min(distance, 3.0)), Vector3.ZERO, Color(0.35, 1.0, 0.85, 1.0), true)
	return root

static func _objective_supply_cache(sequence: int) -> Node3D:
	var root: Node3D = _base_prop("ObjectiveAffordance_%02d_ObjectiveSupplyCache" % sequence, "ObjectiveSupplyCache")
	_add_box(root, "SupplyCrate", Vector3(0.95, 0.55, 0.70), Vector3(0.0, 0.33, 0.0), Color(0.30, 0.82, 0.42, 1.0), true)
	_add_box(root, "SupplyLid", Vector3(1.05, 0.12, 0.80), Vector3(0.0, 0.68, 0.0), Color(0.52, 1.0, 0.58, 1.0), true)
	return root

static func _objective_breaker_panel(sequence: int) -> Node3D:
	var root: Node3D = _base_prop("ObjectiveAffordance_%02d_ObjectiveBreakerPanel" % sequence, "ObjectiveBreakerPanel")
	_add_box(root, "BreakerPanelBody", Vector3(0.24, 1.05, 0.90), Vector3(0.0, 0.75, 0.0), Color(0.95, 0.72, 0.18, 1.0), true)
	_add_box(root, "BreakerSwitch", Vector3(0.34, 0.18, 0.20), Vector3(0.0, 0.92, -0.50), Color(0.12, 0.12, 0.10, 1.0), false)
	return root

static func _objective_med_terminal(sequence: int) -> Node3D:
	var root: Node3D = _base_prop("ObjectiveAffordance_%02d_ObjectiveMedTerminal" % sequence, "ObjectiveMedTerminal")
	_add_box(root, "TerminalBase", Vector3(0.75, 0.72, 0.45), Vector3(0.0, 0.42, 0.0), Color(0.30, 0.78, 1.0, 1.0), true)
	_add_box(root, "TerminalScreen", Vector3(0.62, 0.36, 0.08), Vector3(0.0, 0.86, -0.25), Color(0.15, 1.0, 0.92, 1.0), true)
	return root

static func _objective_reactor_console(sequence: int) -> Node3D:
	var root: Node3D = _base_prop("ObjectiveAffordance_%02d_ObjectiveReactorConsole" % sequence, "ObjectiveReactorConsole")
	_add_box(root, "ConsoleBase", Vector3(0.95, 0.62, 0.72), Vector3(0.0, 0.36, 0.0), Color(0.25, 0.55, 1.0, 1.0), true)
	_add_cylinder(root, "ConsoleCore", 0.22, 0.58, Vector3(0.0, 0.92, 0.0), Color(0.25, 0.95, 1.0, 1.0), true)
	return root

static func _base_prop(node_name: String, kind: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = node_name
	root.set_meta("readability_kind", kind)
	root.set_meta("normal_mode_visual", true)
	return root

static func _add_box(root: Node3D, node_name: String, size: Vector3, local_position: Vector3, color: Color, emissive: bool) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = local_position
	mesh_instance.material_override = _material(color, emissive)
	root.add_child(mesh_instance)
	return mesh_instance

static func _add_sphere(root: Node3D, node_name: String, radius: float, local_position: Vector3, color: Color, emissive: bool) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.position = local_position
	mesh_instance.material_override = _material(color, emissive)
	root.add_child(mesh_instance)
	return mesh_instance

static func _add_cylinder(root: Node3D, node_name: String, radius: float, height: float, local_position: Vector3, color: Color, emissive: bool) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh_instance.mesh = mesh
	mesh_instance.position = local_position
	mesh_instance.material_override = _material(color, emissive)
	root.add_child(mesh_instance)
	return mesh_instance

static func _material(color: Color, emissive: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.45
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.7
	return material
```

- [ ] **Step 4: Run the factory smoke to verify it passes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/readability_prop_factory_smoke.gd
```

Expected marker:

```text
READABILITY PROP FACTORY PASS props=9
```

- [ ] **Step 5: Record Task 1**

Run:

```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" add scripts/procgen/readability_prop_factory.gd scripts/validation/readability_prop_factory_smoke.gd
  git -C "$ROOT" commit -m "feat: add readability prop factory"
else
  printf '%s\n' 'NO_GIT Main Playable Slice v2 Task 1 changed: scripts/procgen/readability_prop_factory.gd scripts/validation/readability_prop_factory_smoke.gd' >> /tmp/sargasso_main_playable_slice_v2_readability_no_git_changes.log
fi
```

---

### Task 2: Integrate Semantic Props into the Main Playable Scene

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `scripts/interaction/interactable.gd`
- Create: `scripts/validation/main_playable_slice_readability_smoke.gd`

**Interfaces:**
- Consumes: `ReadabilityPropFactory` static methods from Task 1.
- Produces: `PlayableGeneratedShip.get_readability_summary() -> Dictionary` with keys:
  - `objective_props: int`
  - `blocked_props: int`
  - `ramp_props: int`
  - `entry_beacons: int`
  - `destination_markers: int`
  - `route_cues: int`
  - `visible_label3d_count: int`
  - `visible_interaction_markers: int`
  - `objective_prop_kinds: Array[String]`
- Produces: normal mode with old translucent `Interactable.marker` hidden.

- [ ] **Step 1: Create the failing main readability smoke**

Create `scripts/validation/main_playable_slice_readability_smoke.gd`:

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
	if not playable.has_method("get_readability_summary"):
		_fail("get_readability_summary missing")
		return
	_validate_readability(playable.get_readability_summary())

func _validate_readability(summary: Dictionary) -> void:
	var required_kinds: Array[String] = [
		"ObjectiveSupplyCache",
		"ObjectiveBreakerPanel",
		"ObjectiveMedTerminal",
		"ObjectiveReactorConsole",
	]
	var kinds: Array = summary.get("objective_prop_kinds", [])
	if int(summary.get("objective_props", 0)) != 4:
		_fail("objective_props=%d" % int(summary.get("objective_props", 0)))
		return
	for kind in required_kinds:
		if not kinds.has(kind):
			_fail("missing objective prop kind=%s kinds=%s" % [kind, str(kinds)])
			return
	if int(summary.get("blocked_props", 0)) != 1:
		_fail("blocked_props=%d" % int(summary.get("blocked_props", 0)))
		return
	if int(summary.get("ramp_props", 0)) != 1:
		_fail("ramp_props=%d" % int(summary.get("ramp_props", 0)))
		return
	if int(summary.get("entry_beacons", 0)) < 1:
		_fail("entry_beacons=%d" % int(summary.get("entry_beacons", 0)))
		return
	if int(summary.get("destination_markers", 0)) < 1:
		_fail("destination_markers=%d" % int(summary.get("destination_markers", 0)))
		return
	if int(summary.get("visible_label3d_count", 0)) != 0:
		_fail("visible_label3d_count=%d" % int(summary.get("visible_label3d_count", 0)))
		return
	if int(summary.get("visible_interaction_markers", 0)) != 0:
		_fail("visible_interaction_markers=%d" % int(summary.get("visible_interaction_markers", 0)))
		return
	finished = true
	print("MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1 entry=%d destination=%d labels=0" % [int(summary.get("entry_beacons", 0)), int(summary.get("destination_markers", 0))])
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
	push_error("MAIN PLAYABLE SLICE READABILITY FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the main readability smoke to verify it fails before integration**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_readability_smoke.gd
```

Expected: exit `1` with `MAIN PLAYABLE SLICE READABILITY FAIL reason=get_readability_summary missing`.

- [ ] **Step 3: Hide old interaction debug marker by default**

Modify `scripts/interaction/interactable.gd`:

1. Add a boolean field after `var marker: MeshInstance3D`:

```gdscript
var marker_visible: bool = false
```

2. Add this public method after `set_active`:

```gdscript
func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if marker != null:
		marker.visible = marker_visible
```

3. In `_ensure_marker(radius: float)`, after `marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF`, add:

```gdscript
	marker.visible = marker_visible
	marker.set_meta("debug_interaction_marker", true)
```

This preserves collision and interaction behavior while removing translucent debug spheres from normal visual evidence.

- [ ] **Step 4: Add prop-factory preload and normal-mode fields to PlayableGeneratedShip**

Modify `scripts/procgen/playable_generated_ship.gd`:

1. Add preload near the existing constants:

```gdscript
const ReadabilityPropFactoryScript := preload("res://scripts/procgen/readability_prop_factory.gd")
```

2. Add fields near `affordance_labels`:

```gdscript
@export var debug_affordance_labels_enabled: bool = false
var affordance_props: Dictionary = {}
```

- [ ] **Step 5: Replace normal affordance-label construction with semantic prop construction**

In `scripts/procgen/playable_generated_ship.gd`, replace `_build_slice_affordance_labels()` with this implementation:

```gdscript
func _build_slice_affordance_labels() -> void:
	if affordance_root == null:
		return
	for child in affordance_root.get_children():
		affordance_root.remove_child(child)
		child.queue_free()
	affordance_labels.clear()
	affordance_props.clear()
	_build_objective_affordance_props()
	_build_blocked_affordance_props()
	_build_vertical_affordance_props()
	_build_entry_destination_props()
	_build_route_readability_props()
	if debug_affordance_labels_enabled:
		_build_objective_affordance_labels()
		_build_blocked_affordance_labels()
		_build_vertical_affordance_labels()
		_build_landmark_affordance_labels()
```

Add these new helper methods before the existing `_build_objective_affordance_labels()` method:

```gdscript
func _build_objective_affordance_props() -> void:
	for interactable_variant in interactables:
		if not (interactable_variant is Node3D):
			continue
		var interactable: Node3D = interactable_variant as Node3D
		var sequence: int = int(interactable.get("sequence"))
		var objective_type: String = str(interactable.get("objective_type"))
		var prop: Node3D = ReadabilityPropFactoryScript.create_objective_prop(sequence, objective_type)
		_register_affordance_prop(prop, interactable.global_position)

func _build_blocked_affordance_props() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_blocked_route_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var prop: Node3D = ReadabilityPropFactoryScript.create_blocked_biomatter()
		prop.name = "BlockedAffordance_%02d_BlockedBiomatter" % index
		_register_affordance_prop(prop, (node as Node3D).global_position)

func _build_vertical_affordance_props() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_visible_vertical_transition_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var prop: Node3D = ReadabilityPropFactoryScript.create_ramp_cue()
		prop.name = "VerticalAffordance_%02d_RampCue" % index
		_register_affordance_prop(prop, (node as Node3D).global_position)

func _build_entry_destination_props() -> void:
	if loader == null:
		return
	var entry_position: Vector3 = loader.get_start_transform().origin
	if entry_position != Vector3.INF:
		_register_affordance_prop(ReadabilityPropFactoryScript.create_entry_beacon(), entry_position)
	var destination_position: Vector3 = loader.get_goal_position()
	if destination_position == Vector3.INF and not interactables.is_empty() and interactables[-1] is Node3D:
		destination_position = (interactables[-1] as Node3D).global_position
	if destination_position != Vector3.INF:
		_register_affordance_prop(ReadabilityPropFactoryScript.create_destination_reactor_core(), destination_position)

func _build_route_readability_props() -> void:
	if loader == null:
		return
	var critical_path: Array[String] = loader.get_critical_path() if loader.has_method("get_critical_path") else []
	var points: Array[Vector3] = []
	var start_position: Vector3 = loader.get_start_transform().origin
	if start_position != Vector3.INF:
		points.append(start_position)
	for room_id in critical_path:
		var room_center: Vector3 = loader.get_room_center(str(room_id)) if loader.has_method("get_room_center") else Vector3.INF
		if room_center != Vector3.INF:
			points.append(room_center)
	var destination_position: Vector3 = loader.get_goal_position()
	if destination_position != Vector3.INF:
		points.append(destination_position)
	var cue_index: int = 0
	for i in range(max(points.size() - 1, 0)):
		var from_pos: Vector3 = points[i]
		var to_pos: Vector3 = points[i + 1]
		if from_pos.distance_to(to_pos) < 0.25:
			continue
		cue_index += 1
		var cue: Node3D = ReadabilityPropFactoryScript.create_route_cue(cue_index, from_pos, to_pos)
		_register_affordance_prop(cue, cue.position)

func _register_affordance_prop(prop: Node3D, world_position: Vector3) -> void:
	if prop == null or affordance_root == null:
		return
	prop.position = world_position
	affordance_root.add_child(prop)
	affordance_props[prop.name] = prop
```

- [ ] **Step 6: Add readability summary helpers**

In `scripts/procgen/playable_generated_ship.gd`, add these public and private methods after `get_affordance_summary()`:

```gdscript
func get_readability_summary() -> Dictionary:
	return {
		"objective_props": _count_readability_kind_prefix("Objective"),
		"blocked_props": _count_readability_kind("BlockedBiomatter"),
		"ramp_props": _count_readability_kind("RampCue"),
		"entry_beacons": _count_readability_kind("EntryBeacon"),
		"destination_markers": _count_readability_kind("DestinationReactorCore"),
		"route_cues": _count_readability_kind("RouteCue"),
		"visible_label3d_count": _count_visible_label3d(),
		"visible_interaction_markers": _count_visible_interaction_markers(),
		"objective_prop_kinds": _objective_readability_kinds(),
	}

func _count_readability_kind(kind: String) -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if str(child.get_meta("readability_kind", "")) == kind:
			count += 1
	return count

func _count_readability_kind_prefix(prefix: String) -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if str(child.get_meta("readability_kind", "")).begins_with(prefix):
			count += 1
	return count

func _objective_readability_kinds() -> Array[String]:
	var out: Array[String] = []
	if affordance_root == null:
		return out
	for child in affordance_root.get_children():
		var kind: String = str(child.get_meta("readability_kind", ""))
		if kind.begins_with("Objective") and not out.has(kind):
			out.append(kind)
	return out

func _count_visible_label3d() -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if child is Label3D and child.visible:
			count += 1
	return count

func _count_visible_interaction_markers() -> int:
	var count: int = 0
	for interactable_variant in interactables:
		var interactable = interactable_variant
		var marker_node = interactable.get("marker") if interactable != null else null
		if marker_node != null and marker_node is Node3D and marker_node.visible:
			count += 1
	return count
```

Then update `get_affordance_summary()` so the existing affordance smoke still passes without requiring `Label3D` text. Keep existing keys but source them from prop counts:

```gdscript
func get_affordance_summary() -> Dictionary:
	var objective_count: int = _count_affordance_prefix("ObjectiveAffordance_")
	var blocked_count: int = _count_affordance_prefix("BlockedAffordance_")
	var vertical_count: int = _count_affordance_prefix("VerticalAffordance_")
	var landmark_count: int = _count_affordance_prefix("LandmarkAffordance_")
	var readability: Dictionary = get_readability_summary()
	if landmark_count < 2:
		landmark_count = int(readability.get("entry_beacons", 0)) + int(readability.get("destination_markers", 0))
	return {
		"objective_labels": objective_count,
		"blocked_labels": blocked_count,
		"vertical_labels": vertical_count,
		"landmark_labels": landmark_count,
		"has_blocked_text": blocked_count > 0 or _any_affordance_text_contains("Blocked"),
		"has_vertical_text": vertical_count > 0 or _any_affordance_text_contains("Ramp"),
	}
```

- [ ] **Step 7: Run the readability smoke and existing affected smokes**

Run:

```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_affordance_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
```

Expected markers:

```text
MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1 entry=1 destination=1 labels=0
MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=4 blocked=1 vertical=1 landmarks=2
MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2
MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true
```

- [ ] **Step 8: Record Task 2**

Run:

```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" add scripts/procgen/playable_generated_ship.gd scripts/interaction/interactable.gd scripts/validation/main_playable_slice_readability_smoke.gd
  git -C "$ROOT" commit -m "feat: add playable readability props"
else
  printf '%s\n' 'NO_GIT Main Playable Slice v2 Task 2 changed: scripts/procgen/playable_generated_ship.gd scripts/interaction/interactable.gd scripts/validation/main_playable_slice_readability_smoke.gd' >> /tmp/sargasso_main_playable_slice_v2_readability_no_git_changes.log
fi
```

---

### Task 3: Capture Sequence Uses Normal Readability Mode and Rejects Label Clutter

**Files:**
- Modify: `scripts/validation/main_playable_slice_capture_sequence.gd`
- Modify: `scripts/validation/main_playable_slice_readability_smoke.gd`

**Interfaces:**
- Consumes: `PlayableGeneratedShip.get_readability_summary() -> Dictionary` from Task 2.
- Produces: capture frames that show semantic props and no visible debug labels.
- Preserves pass marker: `MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=%d mode=viewport output_dir=%s`.

- [ ] **Step 1: Add route cue assertion to the readability smoke**

In `scripts/validation/main_playable_slice_readability_smoke.gd`, add this check after the destination marker check:

```gdscript
	if int(summary.get("route_cues", 0)) < 1:
		_fail("route_cues=%d" % int(summary.get("route_cues", 0)))
		return
```

Update the pass marker line to include route cues:

```gdscript
	print("MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1 entry=%d destination=%d route_cues=%d labels=0" % [int(summary.get("entry_beacons", 0)), int(summary.get("destination_markers", 0)), int(summary.get("route_cues", 0))])
```

- [ ] **Step 2: Run the updated readability smoke**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_readability_smoke.gd
```

Expected marker starts with this text and reports a positive route cue count:

```text
MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1 entry=1 destination=1 route_cues=
```

If it fails with `route_cues=0`, fix `_build_route_readability_props()` from Task 2 before continuing.

- [ ] **Step 3: Make capture fail on visible debug labels**

In `scripts/validation/main_playable_slice_capture_sequence.gd`, add this helper before `_capture_viewport_image()`:

```gdscript
func _assert_no_visible_label_clutter() -> bool:
	if playable == null or not playable.has_method("get_readability_summary"):
		return true
	var summary: Dictionary = playable.get_readability_summary()
	var visible_labels: int = int(summary.get("visible_label3d_count", 0))
	if visible_labels > 0:
		_fail("visible label clutter count=%d" % visible_labels)
		return false
	return true
```

In `_capture_current_step()`, immediately after `var name: String = str(get_meta("capture_name", "capture"))`, add:

```gdscript
	if not _assert_no_visible_label_clutter():
		return
```

- [ ] **Step 4: Keep frame-specific prop visibility but stop hiding all semantic props on spawn/complete**

The existing `_set_affordance_visibility()` filters by prefix. For v2, it should keep entry/destination/route cues visible in frames where they help orientation. Replace calls in `_run_next_step()` as follows:

```gdscript
"spawn":
	_set_affordance_visibility(PackedStringArray(["EntryBeacon", "RouteCue_", "DestinationReactorCore"]))
	_prepare_capture("01_spawn_airlock")
"objective_prompt":
	if not playable.teleport_player_to_objective_for_validation(1):
		_fail("could not stage objective 1 prompt")
		return
	_set_affordance_visibility(PackedStringArray(["ObjectiveAffordance_01", "RouteCue_", "EntryBeacon", "DestinationReactorCore"]))
	_prepare_capture("02_objective_01_prompt")
"objective_complete":
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("could not complete objective 1")
		return
	_set_affordance_visibility(PackedStringArray(["ObjectiveAffordance_02", "RouteCue_", "EntryBeacon", "DestinationReactorCore"]))
	_prepare_capture("03_objective_01_complete")
"blocked":
	if not _stage_player_near_first_node(playable.loader.get_blocked_route_nodes(), Vector3(0.0, 0.65, -1.4)):
		_fail("could not stage blocked route")
		return
	_set_affordance_visibility(PackedStringArray(["BlockedAffordance_", "RouteCue_", "DestinationReactorCore"]))
	_prepare_capture("04_blocked_route")
"vertical":
	if not _stage_player_near_first_node(playable.loader.get_visible_vertical_transition_nodes(), Vector3(0.0, 0.65, -1.4)):
		_fail("could not stage vertical transition")
		return
	_set_affordance_visibility(PackedStringArray(["VerticalAffordance_", "RouteCue_", "DestinationReactorCore"]))
	_prepare_capture("05_vertical_transition")
"complete":
	var completion_guard: int = 0
	var max_completion_steps: int = max(playable.interactables.size() + 2, 8)
	while not playable.slice_complete:
		completion_guard += 1
		if completion_guard > max_completion_steps:
			_fail("completion loop exceeded max steps=%d current_sequence=%d" % [max_completion_steps, playable.get_current_objective_sequence()])
			return
		if not playable.complete_objective_sequence_for_validation(playable.get_current_objective_sequence()):
			_fail("could not complete remaining objective sequence=%d" % playable.get_current_objective_sequence())
			return
	_set_affordance_visibility(PackedStringArray(["EntryBeacon", "RouteCue_", "DestinationReactorCore"]))
	_prepare_capture("06_slice_complete")
```

- [ ] **Step 5: Run capture sequence and inspect metadata**

Run:

```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
ARTIFACT_DIR=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability
mkdir -p "$ARTIFACT_DIR"
"$GODOT" --path "$ROOT" --script res://scripts/validation/main_playable_slice_capture_sequence.gd -- --output-dir "$ARTIFACT_DIR"
for file in 01_spawn_airlock.png 02_objective_01_prompt.png 03_objective_01_complete.png 04_blocked_route.png 05_vertical_transition.png 06_slice_complete.png; do
  echo "=== $file ==="
  sips -g pixelWidth -g pixelHeight -g format "$ARTIFACT_DIR/$file"
  printf 'sha256: '
  shasum -a 256 "$ARTIFACT_DIR/$file" | awk '{print $1}'
done
```

Expected marker:

```text
MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=6 mode=viewport output_dir=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability
```

Expected metadata for every PNG: `pixelWidth: 1280`, `pixelHeight: 720`, `format: png`, 64-character lowercase sha256.

- [ ] **Step 6: Record Task 3**

Run:

```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" add scripts/validation/main_playable_slice_capture_sequence.gd scripts/validation/main_playable_slice_readability_smoke.gd
  git -C "$ROOT" commit -m "test: verify readable viewport captures"
else
  printf '%s\n' 'NO_GIT Main Playable Slice v2 Task 3 changed: scripts/validation/main_playable_slice_capture_sequence.gd scripts/validation/main_playable_slice_readability_smoke.gd' >> /tmp/sargasso_main_playable_slice_v2_readability_no_git_changes.log
fi
```

---

### Task 4: Contact Sheet and Proof Log with Visual Inspection Requirement

**Files:**
- Create: `scripts/validation/main_playable_slice_v2_contact_sheet.py`
- Create: `docs/superpowers/proofs/main-playable-slice-v2-readability.md`

**Interfaces:**
- Consumes capture PNGs under `/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability`.
- Produces `main_playable_slice_v2_readability_contact_sheet.png` in that same artifact directory.
- Produces proof marker: `MAIN PLAYABLE SLICE V2 READABILITY PROOF PASS markers=10 hashes=6`.

- [ ] **Step 1: Create the contact sheet helper**

Create `scripts/validation/main_playable_slice_v2_contact_sheet.py`:

```python
#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

FRAMES = [
    ("01 Spawn / entry", "01_spawn_airlock.png"),
    ("02 Objective prop", "02_objective_01_prompt.png"),
    ("03 Next route", "03_objective_01_complete.png"),
    ("04 Blocker prop", "04_blocked_route.png"),
    ("05 Ramp cue", "05_vertical_transition.png"),
    ("06 Destination complete", "06_slice_complete.png"),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: main_playable_slice_v2_contact_sheet.py <artifact_dir>", file=sys.stderr)
        return 2
    artifact_dir = Path(sys.argv[1]).expanduser().resolve()
    if not artifact_dir.exists():
        print(f"artifact_dir does not exist: {artifact_dir}", file=sys.stderr)
        return 1
    thumb_w, thumb_h = 640, 360
    label_h = 34
    pad = 16
    cols = 2
    rows = 3
    sheet_w = cols * thumb_w + (cols + 1) * pad
    sheet_h = rows * (thumb_h + label_h) + (rows + 1) * pad
    sheet = Image.new("RGB", (sheet_w, sheet_h), (28, 28, 28))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 22)
    except Exception:
        font = ImageFont.load_default()
    for idx, (label, filename) in enumerate(FRAMES):
        frame_path = artifact_dir / filename
        if not frame_path.exists():
            print(f"missing frame: {frame_path}", file=sys.stderr)
            return 1
        img = Image.open(frame_path).convert("RGB")
        if img.size != (1280, 720):
            print(f"unexpected frame size: {frame_path} {img.size}", file=sys.stderr)
            return 1
        img = img.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        col = idx % cols
        row = idx // cols
        x = pad + col * (thumb_w + pad)
        y = pad + row * (thumb_h + label_h + pad)
        draw.text((x, y), label, fill=(245, 245, 245), font=font)
        sheet.paste(img, (x, y + label_h))
    out = artifact_dir / "main_playable_slice_v2_readability_contact_sheet.png"
    sheet.save(out)
    print(f"CONTACT_SHEET {out}")
    for _, filename in FRAMES:
        frame_path = artifact_dir / filename
        print(f"{filename} sha256={sha256(frame_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Generate the contact sheet**

Run:

```bash
python3 /Users/christopherwilloughby/the-sargasso-of-stars/scripts/validation/main_playable_slice_v2_contact_sheet.py /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability
```

Expected output begins with:

```text
CONTACT_SHEET /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/main_playable_slice_v2_readability_contact_sheet.png
```

- [ ] **Step 3: Open and visually inspect the contact sheet**

Run:

```bash
open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/main_playable_slice_v2_readability_contact_sheet.png
```

Expected: exit `0`. The implementer must inspect the pixels with a vision-capable tool or by direct human review before claiming visual readability. The inspection must answer these concrete questions in the final proof:

- Are objective props visible as objects rather than giant words?
- Is the blocked route visibly represented by a blocker prop?
- Is the ramp/vertical transition visibly cued?
- Is the entry/destination context visible enough for a prototype?
- Are there any visible `Label3D` word piles?

- [ ] **Step 4: Create the v2 proof log from actual output**

After Step 3 visual inspection succeeds, generate `docs/superpowers/proofs/main-playable-slice-v2-readability.md` from current artifact hashes with this command. If the visual inspection sentence is not true for the current contact sheet, stop and fix the scene/capture composition instead of writing the proof.

```bash
VISUAL_INSPECTION='The contact sheet was visually inspected after generation. Objective, blocker, ramp, entry, route, and destination cues are represented by semantic primitive props rather than giant in-world words. No visible Label3D word piles are present. Remaining limitations: props are primitive silhouettes, lighting is provisional, and full production walls/VFX/audio are outside this slice.' \
python3 - <<'PY'
from pathlib import Path
import hashlib
import os

artifact_dir = Path('/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability')
proof = Path('/Users/christopherwilloughby/the-sargasso-of-stars/docs/superpowers/proofs/main-playable-slice-v2-readability.md')
frames = [
    '01_spawn_airlock.png',
    '02_objective_01_prompt.png',
    '03_objective_01_complete.png',
    '04_blocked_route.png',
    '05_vertical_transition.png',
    '06_slice_complete.png',
]
inspection = os.environ['VISUAL_INSPECTION']
frame_lines = []
for frame in frames:
    frame_path = artifact_dir / frame
    sha = hashlib.sha256(frame_path.read_bytes()).hexdigest()
    frame_lines.append(f'- `{frame_path}`\n  - sha256: `{sha}`')
proof.parent.mkdir(parents=True, exist_ok=True)
proof.write_text(f'''# Main Playable Slice v2 Readability Proof

## What This Proves

The actual `project.godot` main path now presents the coherent playable ship with semantic objective/blocker/ramp/entry/destination props instead of relying on giant in-world debug text. The existing objective loop remains completable, and the new readability smoke verifies the normal scene exposes semantic props with no visible label clutter.

## Final Acceptance

- [x] `READABILITY PROP FACTORY PASS props=9`
- [x] `MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1`
- [x] `MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=520 current_sequence=1`
- [x] `MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true`
- [x] `MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=4 blocked=1 vertical=1 landmarks=2`
- [x] `MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2`
- [x] `MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2`
- [x] `COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true`
- [x] `PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4`
- [x] `MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=6 mode=viewport output_dir=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability`

## Capture Frames

{chr(10).join(frame_lines)}

## Contact Sheet

`/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/main_playable_slice_v2_readability_contact_sheet.png`

## Visual Inspection

{inspection}

## Limitations

This is still primitive in-engine readability, not production art. Props are simple Godot primitive silhouettes. Lighting, VFX, audio, final walls, enemies, inventory, resource pressure, and broad procgen variety remain outside this slice.
''')
print(f'WROTE_PROOF {proof}')
PY
```

- [ ] **Step 5: Verify proof markers and hashes**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
import hashlib
proof = Path('/Users/christopherwilloughby/the-sargasso-of-stars/docs/superpowers/proofs/main-playable-slice-v2-readability.md')
artifact_dir = Path('/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability')
text = proof.read_text()
required = [
    'READABILITY PROP FACTORY PASS',
    'MAIN PLAYABLE SLICE READABILITY PASS',
    'MAIN PLAYABLE SLICE HUD PASS',
    'MAIN PLAYABLE SLICE COMPLETE PASS',
    'MAIN PLAYABLE SLICE AFFORDANCE PASS',
    'MAIN PLAYABLE INPUT LOOP PASS',
    'MAIN COHERENT BOOT PASS',
    'COHERENT PLAYABLE TRAVERSAL PASS',
    'PLAYABLE SHIP SMOKE PASS',
    'MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('missing proof markers: ' + ', '.join(missing))
frames = ['01_spawn_airlock.png','02_objective_01_prompt.png','03_objective_01_complete.png','04_blocked_route.png','05_vertical_transition.png','06_slice_complete.png']
for frame in frames:
    sha = hashlib.sha256((artifact_dir / frame).read_bytes()).hexdigest()
    if sha not in text:
        raise SystemExit(f'proof missing current sha for {frame}: {sha}')
if 'PLACEHOLDER_TOKEN' in text:
    raise SystemExit('proof contains placeholder text')
print('MAIN PLAYABLE SLICE V2 READABILITY PROOF PASS markers=%d hashes=6' % len(required))
PY
```

Expected marker:

```text
MAIN PLAYABLE SLICE V2 READABILITY PROOF PASS markers=10 hashes=6
```

- [ ] **Step 6: Record Task 4**

Run:

```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" add scripts/validation/main_playable_slice_v2_contact_sheet.py docs/superpowers/proofs/main-playable-slice-v2-readability.md
  git -C "$ROOT" commit -m "docs: prove main playable slice v2 readability"
else
  printf '%s\n' 'NO_GIT Main Playable Slice v2 Task 4 changed: scripts/validation/main_playable_slice_v2_contact_sheet.py docs/superpowers/proofs/main-playable-slice-v2-readability.md' >> /tmp/sargasso_main_playable_slice_v2_readability_no_git_changes.log
fi
```

---

### Task 5: Final Regression Bundle

**Files:**
- Modify only if verification exposes a blocker in a file already listed in Tasks 1-4.
- No new planned files.

**Interfaces:**
- Consumes all pass markers from Tasks 1-4.
- Produces final evidence that v1 functionality and v2 readability both pass together.

- [ ] **Step 1: Run the complete final validation bundle**

Run:

```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
ARTIFACT_DIR=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability
mkdir -p "$ARTIFACT_DIR"

echo '--- readability smokes ---'
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/readability_prop_factory_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd

echo '--- main playable slice smokes ---'
for script in \
  res://scripts/validation/main_playable_slice_hud_smoke.gd \
  res://scripts/validation/main_playable_slice_completion_smoke.gd \
  res://scripts/validation/main_playable_slice_affordance_smoke.gd \
  res://scripts/validation/main_playable_slice_input_smoke.gd; do
  echo "=== $script ==="
  "$GODOT" --headless --path "$ROOT" --script "$script"
done

echo '--- coherent and seed regressions ---'
for script in \
  res://scripts/validation/main_coherent_boot_smoke.gd \
  res://scripts/validation/coherent_playable_traversal_smoke.gd \
  res://scripts/validation/procgen_playable_ship_smoke.gd; do
  echo "=== $script ==="
  "$GODOT" --headless --path "$ROOT" --script "$script"
done

echo '--- viewport capture sequence ---'
"$GODOT" --path "$ROOT" --script res://scripts/validation/main_playable_slice_capture_sequence.gd -- --output-dir "$ARTIFACT_DIR"

echo '--- contact sheet ---'
python3 "$ROOT/scripts/validation/main_playable_slice_v2_contact_sheet.py" "$ARTIFACT_DIR"

echo '--- proof check ---'
python3 - <<'PY'
from pathlib import Path
import hashlib
proof = Path('/Users/christopherwilloughby/the-sargasso-of-stars/docs/superpowers/proofs/main-playable-slice-v2-readability.md')
artifact_dir = Path('/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability')
text = proof.read_text()
required = [
    'READABILITY PROP FACTORY PASS',
    'MAIN PLAYABLE SLICE READABILITY PASS',
    'MAIN PLAYABLE SLICE HUD PASS',
    'MAIN PLAYABLE SLICE COMPLETE PASS',
    'MAIN PLAYABLE SLICE AFFORDANCE PASS',
    'MAIN PLAYABLE INPUT LOOP PASS',
    'MAIN COHERENT BOOT PASS',
    'COHERENT PLAYABLE TRAVERSAL PASS',
    'PLAYABLE SHIP SMOKE PASS',
    'MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('missing proof markers: ' + ', '.join(missing))
frames = ['01_spawn_airlock.png','02_objective_01_prompt.png','03_objective_01_complete.png','04_blocked_route.png','05_vertical_transition.png','06_slice_complete.png']
for frame in frames:
    sha = hashlib.sha256((artifact_dir / frame).read_bytes()).hexdigest()
    if sha not in text:
        raise SystemExit(f'proof missing current sha for {frame}: {sha}')
print('MAIN PLAYABLE SLICE V2 READABILITY PROOF PASS markers=%d hashes=6' % len(required))
PY
```

Expected final markers include:

```text
READABILITY PROP FACTORY PASS props=9
MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1
MAIN PLAYABLE SLICE HUD PASS canvas_layer=true width=520 current_sequence=1
MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true
MAIN PLAYABLE SLICE AFFORDANCE PASS objectives=4 blocked=1 vertical=1 landmarks=2
MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2
MAIN COHERENT BOOT PASS scene=playable_coherent_ship objectives=4 critical_path=5 landmarks=2
COHERENT PLAYABLE TRAVERSAL PASS rooms_traversed=5 side_rooms=3 blocked_route_blocked=true objective_completed=true
PLAYABLE SHIP SMOKE PASS player_spawned=true collision_checked=true interaction_completed=true objectives_completed=1 objective_count=4
MAIN PLAYABLE SLICE CAPTURE SEQUENCE PASS frames=6 mode=viewport output_dir=/Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability
MAIN PLAYABLE SLICE V2 READABILITY PROOF PASS markers=10 hashes=6
```

- [ ] **Step 2: Open final contact sheet for visual review**

Run:

```bash
open /Users/christopherwilloughby/off-the-rails-ai-infra/artifacts/in_engine_show/main_playable_slice_v2_readability/main_playable_slice_v2_readability_contact_sheet.png
```

Expected: exit `0`. The implementer must visually inspect it before claiming completion. If it still reads like a debug-artifact or word pile, do not mark the task complete; fix the prop/capture composition first.

- [ ] **Step 3: Record Task 5**

Run:

```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" status --short
  git -C "$ROOT" add scripts/procgen/readability_prop_factory.gd scripts/procgen/playable_generated_ship.gd scripts/interaction/interactable.gd scripts/validation/readability_prop_factory_smoke.gd scripts/validation/main_playable_slice_readability_smoke.gd scripts/validation/main_playable_slice_capture_sequence.gd scripts/validation/main_playable_slice_v2_contact_sheet.py docs/superpowers/proofs/main-playable-slice-v2-readability.md
  git -C "$ROOT" commit -m "feat: make main playable slice readable"
else
  printf '%s\n' 'NO_GIT Main Playable Slice v2 Task 5 final verification complete' >> /tmp/sargasso_main_playable_slice_v2_readability_no_git_changes.log
fi
```

---

## Self-Review Checklist for Implementers

Before reporting completion, verify:

- The actual main scene path `res://scenes/main.tscn` is used by every main smoke/capture.
- `GeneratedShipLoader` still owns loading data only; it does not own HUD, player input, camera, or prop behavior.
- The old objective loop still completes all four objectives.
- New semantic prop kinds exist: `ObjectiveSupplyCache`, `ObjectiveBreakerPanel`, `ObjectiveMedTerminal`, `ObjectiveReactorConsole`, `BlockedBiomatter`, `RampCue`, `EntryBeacon`, `DestinationReactorCore`, `RouteCue`.
- Normal mode has `visible_label3d_count=0` and `visible_interaction_markers=0`.
- The contact sheet was inspected visually, not accepted from hashes alone.
- The proof log has no placeholder text and its hashes match current files.
- The no-git ledger contains records for each completed task.
