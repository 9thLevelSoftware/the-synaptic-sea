extends Node3D
class_name PlayableGeneratedShip

const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const IsoCameraRigScript := preload("res://scripts/camera/iso_camera_rig.gd")
const InteractableScript := preload("res://scripts/interaction/interactable.gd")
const ObjectiveTrackerScript := preload("res://scripts/ui/objective_tracker.gd")
const ScannerPanelScript := preload("res://scripts/ui/scanner_panel.gd")
const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")
const ReadabilityPropFactoryScript := preload("res://scripts/procgen/readability_prop_factory.gd")
const RouteControlStateScript := preload("res://scripts/systems/route_control_state.gd")
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const ToolPickupScript := preload("res://scripts/tools/tool_pickup.gd")
const FireStateScript := preload("res://scripts/systems/fire_state.gd")
const ElectricalArcStateScript := preload("res://scripts/systems/electrical_arc_state.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const SargassoWorldScript := preload("res://scripts/systems/sargasso_world.gd")
const ScannerStateScript := preload("res://scripts/systems/scanner_state.gd")
const TravelControllerScript := preload("res://scripts/systems/travel_controller.gd")
const LootContainerScript := preload("res://scripts/tools/loot_container.gd")
const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")
const RepairPointScript := preload("res://scripts/tools/repair_point.gd")

signal playable_ready(summary: Dictionary)
signal playable_failed(reason: String)
signal playable_interaction_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String)
signal playable_slice_completed(summary: Dictionary)

const DEFAULT_LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const DEFAULT_KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const DEFAULT_GAMEPLAY_SLICE_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
const PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR: float = 0.55
const ROUTE_GATE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 0.7)
const ROUTE_GATE_VISUAL_COLOR_CLOSED: Color = Color(1.0, 0.22, 0.18, 0.82)
const ROUTE_GATE_VISUAL_COLOR_OPEN: Color = Color(0.18, 0.75, 1.0, 0.18)
const BREACH_ZONE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 1.6)
const BREACH_ZONE_VISUAL_COLOR_OPEN: Color = Color(0.95, 0.32, 0.22, 0.65)
const BREACH_ZONE_VISUAL_COLOR_BLOCKED: Color = Color(0.65, 0.05, 0.05, 0.92)
const BREACH_ZONE_VISUAL_COLOR_SEALED: Color = Color(0.18, 0.55, 1.0, 0.55)
const BREACH_ZONE_FALLBACK_ID: String = "corridor_to_reactor"
const BREACH_ZONE_PROXIMITY_RADIUS: float = 2.4
const BREACH_ZONE_UNSAFE_LABEL_TEXT: String = "OXYGEN LOW"
const FIRE_ZONE_FALLBACK_ID: String = "side_corridor_fire"
# REQ-010: fire zone must live on a non-critical side room so it never
# blocks the objective 3 -> 4 breach corridor or any other main objective
# (objective 1 cargo loot is the only thing the fire can lock out).
const FIRE_ZONE_FALLBACK_ROOM_ID: String = "cargo_01"
const FIRE_ZONE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 1.6)
const FIRE_ZONE_VISUAL_COLOR_CLEARED: Color = Color(0.18, 0.75, 1.0, 0.35)
const FIRE_ZONE_VISUAL_COLOR_BURNING: Color = Color(1.0, 0.22, 0.18, 0.82)
const FIRE_ZONE_LABEL_TEXT_CLEARED: String = "FIRE CLEARED"
const FIRE_ZONE_LABEL_TEXT_BURNING: String = "FIRE BURNING — WAIT"
# REQ-013: electrical-arc zone. Mirrors the fire-zone visual sizing so the
# third hazard reads the same scale on screen; placement is template-
# specific (no fallback room is injected per hazard_type_3.md).
const ARC_ZONE_FALLBACK_ID: String = "side_corridor_arc"
const ARC_ZONE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 1.6)
const ARC_ZONE_VISUAL_COLOR_DISCHARGED: Color = Color(0.35, 0.85, 1.0, 0.35)
const ARC_ZONE_VISUAL_COLOR_ARCING: Color = Color(0.95, 0.32, 1.0, 0.82)
const ARC_ZONE_LABEL_TEXT_DISCHARGED: String = "ARC GROUNDED — CROSS"
const ARC_ZONE_LABEL_TEXT_ARCING: String = "ARC LIVE — WAIT"

# Objective bridge: which manager subcomponents each objective brings operational.
# restore_systems delivers main power (distribution + battery); stabilize_reactor
# brings the reactor core to full health (extraction). download_logs/recover_supplies
# are narrative beats with no system backing.
const OBJECTIVE_REPAIR_MAP: Dictionary = {
	"restore_systems": [["power", "power_distribution"], ["power", "battery_cells"]],
	"download_logs": [["navigation", "nav_computer"]],
	"stabilize_reactor": [["power", "reactor_core"]],
}

@export var layout_path: String = DEFAULT_LAYOUT_PATH
@export var kit_path: String = DEFAULT_KIT_PATH
@export var gameplay_slice_path: String = DEFAULT_GAMEPLAY_SLICE_PATH
@export var blueprint_path: String = "res://data/procgen/golden/coherent_ship_001/blueprint.json"
@export var starting_class_id: String = "engineer"
var loader
var player
var camera_rig
var hud_layer: CanvasLayer
var scanner_panel   # ScannerPanel
var tracker
var interaction_root: Node3D
var affordance_root: Node3D
var affordance_labels: Dictionary = {}
@export var debug_affordance_labels_enabled: bool = false
# A11Y-P1-001: world Label3D pixel_size values for the affordance/landmark,
# breach unsafe, and fire-zone labels all flow through this single settings
# object. Default scale=1.0 reproduces the prior hard-coded pixel_size
# values (0.003 / 0.0035) exactly. Replace via
# apply_accessibility_settings() to enlarge world labels.
var accessibility_settings: RefCounted = AccessibilitySettingsScript.new()
var affordance_props: Dictionary = {}
var interactables: Array = []
var objective_completion_count: int = 0
var current_objective_sequence: int = 1
var slice_complete: bool = false
var ready_summary: Dictionary = {}
var playable_started: bool = false
var last_failure_reason: String = ""
var ship_systems_manager   # ShipSystemsManager (untyped: class_name globals unreliable under --headless --script)
var player_progression   # PlayerProgressionState (untyped: class_name unreliable headless)
var current_ship           # ShipInstance (untyped: class_name globals unreliable headless)
var sargasso_world         # SargassoWorld
var scanner_state          # ScannerState
var travel_controller      # TravelController
var ship_generator         # ShipGenerator (injected into travel)
# True while the player is aboard a traveled derelict (not the starting ship).
# Gates the starting-ship hazard/objective _process so the unoccupied starting
# ship does not keep simulating in the background.
var away_from_start: bool = false
# Sub-project #1 (world persistence): every visited derelict is retained by
# marker_id so its mutable state survives leaving. Only the ACTIVE ship has a
# live scene_root; a derelict's geometry is regenerated from seed on revisit
# while its systems_manager (and later objective/hazard/loot summaries) ride the
# retained ShipInstance.
var visited_ships: Dictionary = {}          # marker_id -> ShipInstance
var home_ship = null                        # the home ShipInstance (marker_id "")
# Sub-project #2: the active derelict's objective interactables live under a
# dedicated root (empty while on the home ship). Separate from the home gameplay
# roots so it stays attached when away_from_start.
var derelict_objective_root: Node3D = null
var derelict_interactables: Array = []
# Sub-project #3: scattered loot containers for the active derelict.
var loot_container_root: Node3D = null
var loot_containers: Array = []
# Sub-project #4: timed repair points for damaged subcomponents.
var repair_point_root: Node3D = null
var repair_points: Array = []
var _loot_tables: Dictionary = {}
var _salvage_loot_tables: Dictionary = {}   # objective_id -> loot_table key
var _home_player_position: Vector3 = Vector3.ZERO
const REPAIR_OBJECTIVE_XP: int = 50
# Narrative objective flags with no manager backing (supplies/logs). Set on
# completion; persisted in the snapshot; read by _manager_compat_summary().
var completed_objective_types: Dictionary = {}
var route_control_state: RouteControlState
var route_control_root: Node3D
var route_gate_nodes: Array = []
var oxygen_state: OxygenState
var oxygen_root: Node3D
var breach_zone_node: StaticBody3D
var unsafe_room_marker: Label3D
# --- Inventory / Tool pickup integration -------------------------------------
# REQ-007: a single ToolPickup carrying the portable_oxygen_pump lives in a
# fixed side room (tool_storage_01 if the loader defines it, otherwise a
# fallback position near the player start). Acquiring the pickup adds the
# tool id to InventoryState exactly once; OxygenState reads the inventory
# summary each frame to halve the drain rate inside an unsealed breach.
#
# REQ-014: a second ToolPickup carrying the junction_calibrator lives in
# a different side room (galley_01 with a player-spawn fallback offset).
# Acquiring the pickup adds "junction_calibrator" to InventoryState; the
# next interaction with a `kind == "repair_junction"` objective node
# triggers objective_progress_state.apply_junction_calibrator(sequence),
# which reduces required_steps by one (min 1) and marks the sequence
# calibrator_applied. The pickup is single-use; a successful application
# removes the calibrator from inventory and hides the pickup marker.

var inventory_state: InventoryState
var tool_pickup: ToolPickup
var tool_pickup_root: Node3D
const TOOL_PICKUP_INTERACTION_RADIUS: float = 1.8
const TOOL_PICKUP_FALLBACK_OFFSET: Vector3 = Vector3(4.0, 0.0, 0.0)
# REQ-014: junction calibrator pickup. Sits in a different side room so
# the player can pick it up independently of the oxygen pump.
var junction_calibrator_pickup: ToolPickup
const JUNCTION_CALIBRATOR_INTERACTION_RADIUS: float = 1.8
const JUNCTION_CALIBRATOR_FALLBACK_OFFSET: Vector3 = Vector3(-4.0, 0.0, 0.0)
const JUNCTION_CALIBRATOR_FALLBACK_ROOM_ID: String = "galley_01"
# Sequence -> "repair_junction" / "single" lookup. Populated in
# _build_interactables alongside the interactable group so the
# completion handler can apply the calibrator to the right sequences
# without re-walking the loader's objective specs.
var sequence_kinds: Dictionary = {}
var fire_state: FireState
var fire_root: Node3D
var fire_zone_node: StaticBody3D
var fire_zone_label: Label3D
# Resolved room id for the fire zone: the `to_room` of the fire_zones
# marker when one is present in the layout, otherwise the
# FIRE_ZONE_FALLBACK_ROOM_ID constant. Empty when neither source supplied
# a room id (the last-ditch player-spawn offset path).
var fire_zone_resolved_room_id: String = ""
# REQ-013: electrical-arc hazard runtime state. electrical_arc_state is
# the pure model; arc_root owns the scene node; arc_zone_node is the
# StaticBody3D whose collision is toggled; arc_zone_label is the
# localized Label3D that swaps between DISCHARGED and ARCING text.
var electrical_arc_state: ElectricalArcState
var arc_root: Node3D
var arc_zone_node: StaticBody3D
var arc_zone_label: Label3D
var arc_zone_resolved_room_id: String = ""
var objective_progress_state: ObjectiveProgressState
var sequence_interactables: Dictionary = {}
# REQ-012: current-run save/load state.
var save_load_service: SaveLoadService
var last_saved_snapshot: RunSnapshot
var _is_reloading: bool = false

## NOTE: This scene relies on GeneratedShipLoader.load_from_paths() being
## SYNCHRONOUS and emitting `ship_loaded` on the same call stack — the
## _on_ship_loaded handler (and therefore _spawn_player / _spawn_camera /
## _build_interactables) depends on that ordering. If the loader is ever
## refactored to run on a thread, use call_deferred(), or otherwise defer
## emission of `ship_loaded`, this scene must be adjusted (e.g. move
## ready-signal logic out of _ready and gate it on ship_loaded explicitly).
func _ready() -> void:
	ensure_default_input_actions()
	_build_runtime_nodes()
	loader.load_from_paths(layout_path, kit_path, gameplay_slice_path)

# A11Y-P1-002 (P1 accessibility: alternate keyboard bindings): movement,
# interaction, and manual save/load expose at least one alternate keyboard
# path beyond the original WASD/E/F5/F9 layout. The primary bindings stay
# active so the existing keyboard-only path remains discoverable; alternates
# (arrow keys for movement, Enter/Space for interact) are added to the same
# InputMap actions so the player can pick whichever layout they prefer.
# The chosen keycodes do not collide with F5/F9 (save/load) or with each
# other, so adding them cannot change the save/load binding discoverability.
# Each entry is intentionally an Array literal so the alternate-binding
# surface is data — future feature/options work can swap in remap sources
# without touching the registration call sites.
const DEFAULT_MOVE_BINDINGS: Dictionary = {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
}
const DEFAULT_INTERACT_BINDINGS: Array[Key] = [KEY_E, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]
const DEFAULT_SAVE_RUN_BINDINGS: Array[Key] = [KEY_F5]
const DEFAULT_LOAD_RUN_BINDINGS: Array[Key] = [KEY_F9]

func ensure_default_input_actions() -> void:
	for action_name in DEFAULT_MOVE_BINDINGS:
		_ensure_key_action_set(action_name, DEFAULT_MOVE_BINDINGS[action_name])
	_ensure_key_action_set("interact", DEFAULT_INTERACT_BINDINGS)
	# REQ-012: manual save/load input actions. F5 saves, F9 loads.
	_ensure_key_action_set("save_run", DEFAULT_SAVE_RUN_BINDINGS)
	_ensure_key_action_set("load_run", DEFAULT_LOAD_RUN_BINDINGS)
	_ensure_key_action_set("toggle_scanner", [KEY_TAB])

## A11Y-P1-001: swap in a new accessibility settings object and re-apply
## its scale to the HUD tracker and all existing world Label3D nodes.
## Existing labels are updated in place; nothing needs to be rebuilt. The
## scale itself flows through the new settings' clamp range, so callers
## can pass a freshly-instantiated AccessibilitySettingsScript with
## any scale in [1.0, 2.0] without worrying about out-of-range
## pixel_size values.
func apply_accessibility_settings(settings: RefCounted) -> void:
	if settings == null:
		return
	accessibility_settings = settings
	if tracker != null and tracker.has_method("apply_accessibility_settings"):
		tracker.apply_accessibility_settings(settings)
	_apply_world_label_scale()

func _apply_world_label_scale() -> void:
	if affordance_root != null:
		for child in affordance_root.get_children():
			if child is Label3D:
				# Default base pixel_size for the affordance/landmark labels is
				# 0.003 (matches the pre-A11Y-P1-001 constant in
				# _make_affordance_label). This pass is idempotent: every call
				# rewrites the value from the same base, so swapping the scale
				# repeatedly does not drift.
				_apply_pixel_size_to_label(child, 0.003)
	if unsafe_room_marker != null:
		_apply_pixel_size_to_label(unsafe_room_marker, 0.0035)
	if fire_zone_label != null:
		_apply_pixel_size_to_label(fire_zone_label, 0.0035)
	if arc_zone_label != null:
		_apply_pixel_size_to_label(arc_zone_label, 0.0035)

func _apply_pixel_size_to_label(label: Node, base_pixel_size: float) -> void:
	if not (label is Label3D):
		return
	(label as Label3D).pixel_size = accessibility_settings.scaled_world_pixel_size(base_pixel_size)

## Headless-validation seam: must be called only after `playable_ready`
## has fired (i.e. ship loaded, player spawned, interactables populated).
## Calling it earlier short-circuits to false because player / interactables
## are not yet wired up.
##
## Deliberately uses `set_validation_player_in_range(player)` on the
## interactable to bypass the normal Area3D body-entered physics overlap
## check (which is unreliable / never fires deterministically in a
## headless smoke run), then teleports the player onto the interactable
## and requests the interaction so the harness can assert the full
## _on_interactable_completed path runs end-to-end.
##
## Returns true once at least one objective has been completed.
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

## Headless-validation seam: teleports the player to the room center of the
## given room_id (as resolved by the loader) plus the standard spawn height
## offset above the navigation floor. Returns false (without mutating player
## state) if the player / loader are not ready, the loader does not implement
## `get_room_center`, or the loader cannot resolve the room id (i.e. it
## returns Vector3.INF). Must be called only after `playable_ready` has
## fired.
func teleport_player_to_room_for_validation(room_id: String) -> bool:
	if player == null or loader == null or not loader.has_method("get_room_center"):
		return false
	var room_center: Vector3 = loader.get_room_center(room_id)
	if room_center == Vector3.INF:
		return false
	player.teleport_to(room_center + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0))
	return true

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

## Blueprint-driven entry point: build a GeneratedShip Node3D tree from a
## ShipBlueprint via the ShipGenerator and add it as a direct child of this
## playable scene. The generator returns a freshly-built GeneratedShipLoader
## root named "GeneratedShip" with "StructuralRoot" (geometry + nav) and
## "ObjectiveRoot" Node3D children nested inside it; we re-parent that root
## under self so the existing playable infrastructure (player spawn, camera
## rig, interactables) can reference it the same way it references the
## GeneratedShipLoader output.
##
## This is intentionally orthogonal to loader.load_from_paths(): callers
## who already have a ShipBlueprint (e.g. generated procedurally, replayed
## from a save fixture, or seeded for tests) can use this seam to bypass
## the layout/kit JSON paths entirely. The caller still owns subsequent
## ship_loaded wiring (the loader's `ship_loaded` signal is the production
## trigger for _on_ship_loaded — this method does NOT fire that signal,
## since the loader has not run).
##
## Returns the generated root Node3D on success, or null if the blueprint
## is null or the generator produced no ship.
##
## NOTE: parameter is intentionally untyped (`Variant`) because Godot
## `class_name` globals are not always registered at parse time in
## `godot --headless --script` mode. The runtime check via
## `ShipBlueprintScript.new(...)` in ShipGenerator is the same pattern
## used by ShipGenerator.generate(blueprint) itself.
func load_from_blueprint(blueprint) -> Node3D:
	if blueprint == null:
		push_error("PlayableGeneratedShip.load_from_blueprint: blueprint must not be null")
		return null
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()
	var generated: Node3D = generator.generate(blueprint)
	if generated == null:
		push_error("PlayableGeneratedShip.load_from_blueprint: ShipGenerator failed to build a ship")
		return null
	add_child(generated)
	return generated

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

func get_objective_progress_summary() -> Dictionary:
	if objective_progress_state == null:
		return {}
	return objective_progress_state.get_summary()

func get_interactable_by_sequence(sequence: int):
	var group: Array = sequence_interactables.get(sequence, [])
	for interactable in group:
		if is_instance_valid(interactable) and int(interactable.get("sequence")) == sequence:
			return interactable
	return null

## Validation seam: every interactable belonging to a sequence. Multi-step
## objectives (e.g. the repair_junction at objective 2) expose one
## interactable per step at distinct positions; drivers that only touch the
## first (see get_interactable_by_sequence) cannot complete the junction.
func get_interactables_by_sequence(sequence: int) -> Array:
	var out: Array = []
	for interactable in sequence_interactables.get(sequence, []):
		if is_instance_valid(interactable) and int(interactable.get("sequence")) == sequence:
			out.append(interactable)
	return out

func teleport_player_to_objective_for_validation(sequence: int) -> bool:
	if player == null:
		return false
	var interactable = get_interactable_by_sequence(sequence)
	if interactable == null or not (interactable is Node3D):
		return false
	player.teleport_to((interactable as Node3D).global_position)
	return true

## Headless-validation seam: teleports the player to the breach zone center
## so the smoke can drive runtime oxygen drain via real _process frames.
## Must be called only after `playable_ready` has fired.
func teleport_player_to_breach_zone_for_validation() -> bool:
	if player == null or breach_zone_node == null:
		return false
	player.teleport_to(breach_zone_node.global_position)
	return true

## Headless-validation seam: returns true while the runtime per-frame tick
## considers the player to be inside the breach zone (uses the same horizontal
## proximity radius as the live hazard integration).
func is_player_in_breach_zone_for_validation() -> bool:
	return is_player_in_breach_zone()

## Headless-validation seam: drives oxygen to zero by reconfiguring OxygenState
## with drain_rate = 1000 and tick(delta=10) so the runtime tick path itself
## (the same _refresh_oxygen_state(false, delta) the live game uses) flips
## passability_blocked to true. This is a runtime consequence, not a direct
## model mutation: OxygenState.tick(...) still runs from the scene tree on
## the next frame. Returns true when passability_blocked is now true.
func force_runtime_oxygen_to_zero_for_validation() -> bool:
	if oxygen_state == null:
		return false
	# Duplicate the breach_zone_ids array because OxygenState.configure()
	# clears its stored breach_zone_ids first and then iterates the passed-
	# in array; if we hand it the same Array reference, the iteration sees
	# an empty list and configure() leaves breach_open=false.
	oxygen_state.configure({
		"zone_ids": oxygen_state.breach_zone_ids.duplicate(),
		"max_oxygen": oxygen_state.max_oxygen,
		"drain_rate": 1000.0,
		"regen_rate": oxygen_state.regen_rate,
		"recovery_threshold": oxygen_state.recovery_threshold,
		"safe_threshold": oxygen_state.safe_threshold,
	})
	# Force-apply the scene state derived from the current model so the
	# collision toggle and HUD line update without waiting for the player to
	# be in the breach zone; the next _process tick will continue driving
	# drain via the live runtime path. Per ADR-0005 the tick context is a
	# Dictionary; passing a bool is preserved as a legacy positional form
	# so this validation seam still works without an explicit wrapping
	# dictionary.
	if is_player_in_breach_zone():
		oxygen_state.tick(10.0, true)
	else:
		oxygen_state.tick(10.0, false)
	_refresh_oxygen_state(false, 0.0)
	return oxygen_state.is_passability_blocked()

func complete_objective_sequence_for_validation(sequence: int) -> bool:
	if sequence != current_objective_sequence:
		return false
	var group: Array = sequence_interactables.get(sequence, [])
	if group.is_empty():
		return false
	for interactable in group:
		if not (interactable is Node3D):
			continue
		player.teleport_to((interactable as Node3D).global_position)
		if not interactable.has_method("set_validation_player_in_range"):
			return false
		interactable.set_validation_player_in_range(player)
		# If this interactable was already completed (e.g. multi-step and we
		# are finishing the second step after the first one), skip.
		if bool(interactable.get("completed")):
			continue
		player.request_interact()
	# Sequence complete iff current_objective_sequence has advanced past
	# the requested sequence. For multi-step sequences, the per-step path
	# in _on_interactable_completed only fires once for the whole sequence,
	# so objective_completion_count lags by one (it is incremented AFTER
	# the last step), while current_objective_sequence is incremented
	# immediately on sequence completion.
	return current_objective_sequence > sequence or slice_complete

func complete_all_objectives_for_validation() -> bool:
	var expected_total: int = sequence_interactables.size()
	if expected_total <= 0:
		return false
	while not slice_complete:
		var sequence: int = current_objective_sequence
		if sequence > expected_total:
			break
		if not complete_objective_sequence_for_validation(sequence):
			return false
	return slice_complete and objective_completion_count == expected_total

func get_affordance_summary() -> Dictionary:
	var objective_labels: int = _count_affordance_prefix("ObjectiveAffordance_")
	var blocked_labels: int = _count_affordance_prefix("BlockedAffordance_")
	var vertical_labels: int = _count_affordance_prefix("VerticalAffordance_")
	var landmark_labels: int = _count_affordance_prefix("LandmarkAffordance_")
	var readability: Dictionary = get_readability_summary()
	var entry_beacons: int = int(readability.get("entry_beacons", 0))
	var destination_markers: int = int(readability.get("destination_markers", 0))
	if landmark_labels < 2 and entry_beacons + destination_markers >= 2:
		landmark_labels = entry_beacons + destination_markers
	return {
		"objective_labels": objective_labels,
		"blocked_labels": blocked_labels,
		"vertical_labels": vertical_labels,
		"landmark_labels": landmark_labels,
		"has_blocked_text": blocked_labels > 0 or _any_affordance_text_contains("Blocked"),
		"has_vertical_text": vertical_labels > 0 or _any_affordance_text_contains("Ramp"),
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
		if interactable == null:
			continue
		var marker_node: Variant = interactable.get("marker")
		if marker_node != null and marker_node is Node3D and (marker_node as Node3D).visible:
			count += 1
	return count

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
	if destination_position == Vector3.INF and not interactables.is_empty() and interactables[interactables.size() - 1] is Node3D:
		destination_position = (interactables[interactables.size() - 1] as Node3D).global_position
	if destination_position != Vector3.INF:
		_register_affordance_prop(ReadabilityPropFactoryScript.create_destination_reactor_core(), destination_position)

func _build_route_readability_props() -> void:
	if loader == null:
		return
	var critical_path: Array = []
	if loader.has_method("get_critical_path"):
		var raw_critical_path: Variant = loader.get_critical_path()
		if typeof(raw_critical_path) == TYPE_ARRAY:
			critical_path = raw_critical_path
	var points: Array = []
	var start_position: Vector3 = loader.get_start_transform().origin
	if start_position != Vector3.INF:
		points.append(start_position)
	for room_id_variant in critical_path:
		var room_center: Vector3 = Vector3.INF
		if loader.has_method("get_room_center"):
			room_center = loader.get_room_center(str(room_id_variant))
		if room_center != Vector3.INF:
			points.append(room_center)
	var destination_position: Vector3 = loader.get_goal_position()
	if destination_position != Vector3.INF:
		points.append(destination_position)
	var cue_index: int = 0
	var pair_count: int = max(points.size() - 1, 0)
	for i in range(pair_count):
		var from_pos: Vector3 = points[i]
		var to_pos: Vector3 = points[i + 1]
		if from_pos.distance_to(to_pos) < 0.25:
			continue
		cue_index += 1
		var cue: Node3D = ReadabilityPropFactoryScript.create_route_cue(cue_index, from_pos, to_pos)
		_register_affordance_prop(cue, cue.position)

func _build_route_control_gates() -> void:
	if route_control_root == null:
		return
	for child in route_control_root.get_children():
		route_control_root.remove_child(child)
		child.queue_free()
	route_gate_nodes.clear()
	var gate_ids: Array = []
	if loader == null:
		if route_control_state != null:
			route_control_state.configure_from_blocked_routes(gate_ids)
		return
	var index: int = 0
	for node in loader.get_blocked_route_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var gate_id: String = "powered_route_gate_%02d" % index
		var gate: StaticBody3D = _create_route_gate(gate_id, index, (node as Node3D).global_position)
		route_control_root.add_child(gate)
		route_gate_nodes.append(gate)
		gate_ids.append(gate_id)
	if route_control_state != null:
		route_control_state.configure_from_blocked_routes(gate_ids)
	_apply_route_gate_scene_state()

func _create_route_gate(gate_id: String, index: int, world_position: Vector3) -> StaticBody3D:
	var gate: StaticBody3D = StaticBody3D.new()
	gate.name = "RouteGate_%02d_PoweredBlocker" % index
	gate.position = world_position
	gate.collision_layer = 1
	gate.collision_mask = 1
	gate.set_meta("route_gate_id", gate_id)
	gate.set_meta("route_gate_kind", "powered_blocker")
	gate.set_meta("required_system", "main_power_restored")
	gate.set_meta("route_gate_open", false)
	gate.set_meta("system_cleared", false)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "RouteGateCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = ROUTE_GATE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, ROUTE_GATE_COLLISION_SIZE.y * 0.5, 0.0)
	gate.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "RouteGateVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = ROUTE_GATE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_route_gate_material(false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(visual)
	return gate

func _make_route_gate_material(is_open: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = ROUTE_GATE_VISUAL_COLOR_OPEN if is_open else ROUTE_GATE_VISUAL_COLOR_CLOSED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _register_affordance_prop(prop: Node3D, world_position: Vector3) -> void:
	if prop == null or affordance_root == null:
		return
	prop.position = world_position
	affordance_root.add_child(prop)
	affordance_props[prop.name] = prop

func _build_objective_affordance_labels() -> void:
	for interactable_variant in interactables:
		if not (interactable_variant is Node3D):
			continue
		var interactable: Node3D = interactable_variant as Node3D
		var sequence: int = int(interactable.get("sequence"))
		var objective_type: String = str(interactable.get("objective_type"))
		var text: String = "%02d %s\nE" % [sequence, _short_objective_label(objective_type)]
		_make_affordance_label("ObjectiveAffordance_%02d" % sequence, text, interactable.global_position + Vector3(0.0, 2.4, 0.0), Color(0.35, 1.0, 0.45, 1.0))

func _build_blocked_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_blocked_route_nodes():
		if not (node is Node3D):
			continue
		index += 1
		_make_affordance_label("BlockedAffordance_%02d" % index, "Blocked\nBio", (node as Node3D).global_position + Vector3(0.0, 2.8, 0.0), Color(1.0, 0.28, 0.22, 1.0))

func _build_vertical_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_visible_vertical_transition_nodes():
		if not (node is Node3D):
			continue
		index += 1
		_make_affordance_label("VerticalAffordance_%02d" % index, "Ramp\nUp", (node as Node3D).global_position + Vector3(0.0, 2.2, 0.0), Color(1.0, 0.78, 0.25, 1.0))

func _build_landmark_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_landmark_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var text: String = "Beacon" if index == 1 else "Core"
		_make_affordance_label("LandmarkAffordance_%02d" % index, text, (node as Node3D).global_position + Vector3(0.0, 2.8, 0.0), Color(0.28, 0.75, 1.0, 1.0))

func _make_affordance_label(node_name: String, text: String, world_position: Vector3, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = node_name
	label.text = text
	label.position = world_position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	# A11Y-P1-001: world label pixel_size flows through the single
	# accessibility_settings seam. Default scale=1.0 keeps the prior
	# 0.003 value exactly; larger scales divide the pixel_size so the
	# label renders larger on screen for the same world position.
	label.pixel_size = accessibility_settings.scaled_world_pixel_size(0.003)
	label.modulate = color
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	affordance_root.add_child(label)
	affordance_labels[node_name] = label
	return label

func _short_objective_label(raw: String) -> String:
	match raw:
		"recover_supplies":
			return "Supplies"
		"restore_systems":
			return "Systems"
		"download_logs":
			return "Logs"
		"stabilize_reactor":
			return "Reactor"
		_:
			return _title_from_snake(raw)

func _title_from_snake(raw: String) -> String:
	var words: PackedStringArray = PackedStringArray()
	for part in raw.split("_", false):
		words.append(part.capitalize())
	return " ".join(words)

func _build_runtime_nodes() -> void:
	ship_systems_manager = ShipSystemsManagerScript.new()
	var bp = _load_blueprint_for_systems()
	ship_systems_manager.configure(ship_systems_manager.load_definitions(), bp.condition, bp.seed_value)
	_apply_lifeboat_opening_damage()
	player_progression = PlayerProgressionScript.new()
	_configure_player_progression()
	route_control_state = RouteControlStateScript.new()
	route_gate_nodes.clear()
	objective_progress_state = ObjectiveProgressStateScript.new()
	loader = GeneratedShipLoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(_on_ship_loaded)
	loader.load_failed.connect(_on_loader_failed)
	add_child(loader)
	interaction_root = Node3D.new()
	interaction_root.name = "InteractionRoot"
	add_child(interaction_root)
	affordance_root = Node3D.new()
	affordance_root.name = "SliceAffordanceRoot"
	add_child(affordance_root)
	route_control_root = Node3D.new()
	route_control_root.name = "RouteControlRoot"
	add_child(route_control_root)
	oxygen_state = OxygenStateScript.new()
	oxygen_root = Node3D.new()
	oxygen_root.name = "OxygenRoot"
	add_child(oxygen_root)
	# REQ-007 inventory/tool runtime nodes. InventoryState is a pure model
	# (RefCounted); tool_pickup_root is the parent for any ToolPickup node
	# the coordinator spawns during ship load.
	inventory_state = InventoryStateScript.new()
	tool_pickup_root = Node3D.new()
	tool_pickup_root.name = "ToolPickupRoot"
	add_child(tool_pickup_root)
	fire_state = FireStateScript.new()
	fire_root = Node3D.new()
	fire_root.name = "FireRoot"
	add_child(fire_root)
	# REQ-013: electrical-arc runtime nodes. The model + scene root are
	# always allocated so _process and _refresh_arc_state can be called
	# unconditionally; the per-template `_build_arc_zone()` decides
	# whether to spawn a real StaticBody3D / Label3D or to leave them
	# null (the loader returns an empty `arc_zone_specs` when no marker
	# is present and the scene must skip arc setup without crashing).
	electrical_arc_state = ElectricalArcStateScript.new()
	arc_root = Node3D.new()
	arc_root.name = "ElectricalArcRoot"
	add_child(arc_root)
	derelict_objective_root = Node3D.new()
	derelict_objective_root.name = "DerelictObjectiveRoot"
	add_child(derelict_objective_root)
	loot_container_root = Node3D.new()
	loot_container_root.name = "LootContainerRoot"
	add_child(loot_container_root)
	repair_point_root = Node3D.new()
	repair_point_root.name = "RepairPointRoot"
	add_child(repair_point_root)
	_loot_tables = LootRollerScript.load_tables()
	_build_hud_layer()
	# REQ-012: current-run save/load service. Single slot at
	# user://saves/current_run.json; deleted on playable_slice_completed.
	save_load_service = SaveLoadServiceScript.new()
	# Phase 4.5: Sargasso map + scanner + travel. Seed the world from the
	# starting blueprint's seed so the marker field is deterministic per run.
	# Player starts at Sargasso map origin (abstract X-Z map space — NOT the
	# physical scene origin where ship geometry is instantiated).
	var start_bp = _load_blueprint_for_systems()
	sargasso_world = SargassoWorldScript.new(start_bp.seed_value, Vector3.ZERO)
	scanner_state = ScannerStateScript.new()
	travel_controller = TravelControllerScript.new()
	ship_generator = ShipGeneratorScript.new()

## Configures the progression model from starting_class_id (defaults to engineer
## when the id is unknown). Idempotent: re-callable on reload.
func _configure_player_progression() -> void:
	if player_progression == null:
		return
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var class_def = classes.get(starting_class_id, classes.get("engineer", null))
	if class_def == null:
		push_error("PlayableGeneratedShip: no class definition for '%s' or fallback 'engineer' (data/player/classes.json missing or malformed)" % starting_class_id)
	player_progression.configure(class_def, PlayerProgressionScript.load_skills_catalog())

## Loads the blueprint sidecar that seeds the ShipSystemsManager's condition
## damage. Falls back to a DAMAGED/seed=17 default (never crashes the slice)
## when the sidecar is absent or malformed.
func _load_blueprint_for_systems():
	var fallback = ShipBlueprintScript.new(ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.DAMAGED, 17)
	if blueprint_path.is_empty() or not FileAccess.file_exists(blueprint_path):
		push_warning("PlayableGeneratedShip: blueprint sidecar missing at %s; using DAMAGED/seed=17 default" % blueprint_path)
		return fallback
	var text: String = FileAccess.get_file_as_string(blueprint_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PlayableGeneratedShip: blueprint sidecar malformed at %s; using default" % blueprint_path)
		return fallback
	return ShipBlueprintScript.from_dict(parsed as Dictionary)

## Validation seam: the live ShipSystemsManager (null before _build_runtime_nodes()).
func get_ship_systems_manager():
	return ship_systems_manager

## Validation seam: the live PlayerProgressionState (null before _build_runtime_nodes()).
func get_player_progression():
	return player_progression

## Phase 4.5 validation seam: the current ShipInstance (null before the first
## ship loads).
func get_current_ship():
	return current_ship

## Phase 4.5 validation seam: the SargassoWorld map model.
func get_sargasso_world():
	return sargasso_world

## Operational status feeding scan/travel. Travel capability always comes from the
## player's functional ship — the lifeboat (the coordinator-owned starting systems
## manager) — whether the player is on the lifeboat or boarded on a docked derelict.
## The lifeboat is the guaranteed ride, so a boarded derelict's broken systems never
## strand the player; an unrepaired lifeboat simply cannot jump until its propulsion
## is restored. (Retires ADR-0011 placeholder.)
func _current_systems_ops() -> Dictionary:
	var mgr = ship_systems_manager
	return {
		"navigation": mgr != null and mgr.is_operational("navigation"),
		"scanners": mgr != null and mgr.is_operational("scanners"),
		"propulsion": mgr != null and mgr.is_operational("propulsion"),
	}

## Resolves the visible markers at the gated detail level, deriving operational
## status from the CURRENT ship's systems and scanner skill from progression.
func scan() -> Dictionary:
	if current_ship == null or sargasso_world == null or scanner_state == null:
		return {"detail_level": 0, "markers": []}
	var ops: Dictionary = _current_systems_ops()
	var skill: int = 0
	if player_progression != null and player_progression.has_method("get_skill_level"):
		skill = int(player_progression.get_skill_level("scanner_operation"))
	return scanner_state.scan(sargasso_world, ops, skill)

## Resolves a marker by id from the in-range set and travels to it. Returns
## {success:false, reason:"unknown_marker"} if the id is not currently in range.
func travel_to_marker_id(marker_id: String) -> Dictionary:
	if sargasso_world == null or scanner_state == null:
		return {"success": false, "reason": "not_ready", "ship": null}
	for m in sargasso_world.markers_in_range(scanner_state.range_radius):
		if String(m.marker_id) == marker_id:
			return travel_to(m)
	return {"success": false, "reason": "unknown_marker", "ship": null}

## The starting ship's per-slice gameplay roots (siblings of the loader). They
## sit at the coordinator's local origin, so while the player is aboard a
## traveled derelict (also at origin) they must be detached from the tree —
## otherwise their collision volumes / interactables overlay the boarded ship.
func _starting_gameplay_roots() -> Array:
	return [interaction_root, affordance_root, route_control_root, oxygen_root, tool_pickup_root, fire_root, arc_root]

func _detach_starting_gameplay_roots() -> void:
	for r in _starting_gameplay_roots():
		if r != null and is_instance_valid(r) and r.get_parent() == self:
			remove_child(r)

func _reattach_starting_gameplay_roots() -> void:
	for r in _starting_gameplay_roots():
		if r != null and is_instance_valid(r) and r.get_parent() == null:
			add_child(r)

## Makes `inst` the active boarded derelict: detaches the home gameplay roots
## (so they do not overlay the derelict at the shared local origin), attaches the
## freshly built `new_root`, and flips away_from_start. Shared by travel_to
## (revisit/first-visit) and world-load (_apply_world_snapshot). Does NOT re-home
## the player — callers position the player afterwards.
func _attach_derelict_active(inst, new_root: Node3D) -> void:
	# Detach the home hull if it is still parented under the coordinator. In a
	# normal travel_to() the home loader/scene_root was already removed before
	# this call, so this is a no-op there (get_parent() != self). It only fires
	# on the world-load path, where _apply_world_snapshot rebuilds the home ship
	# (leaving its scene_root parented) and then re-activates a derelict — without
	# this detach both hulls overlap at the local origin for the whole visit.
	# Detach-not-free: travel_home re-adds the same home scene_root.
	if home_ship != null and home_ship.scene_root != null and is_instance_valid(home_ship.scene_root) and home_ship.scene_root.get_parent() == self:
		remove_child(home_ship.scene_root)
	_detach_starting_gameplay_roots()
	inst.scene_root = new_root
	add_child(new_root)
	current_ship = inst
	away_from_start = true
	_build_derelict_objectives()
	_build_loot_containers()
	_build_repair_points()

## Builds the active derelict's objective interactables from its loader specs and
## restores completed/cleared state from its (retained or loaded) controller. Called
## whenever a derelict becomes active. No-op on the home ship.
func _build_derelict_objectives() -> void:
	_clear_derelict_objectives()
	_salvage_loot_tables.clear()
	if current_ship == null or String(current_ship.marker_id) == "":
		return
	var active_loader = current_ship.scene_root
	if not is_instance_valid(active_loader) or not active_loader.has_method("get_objective_specs_copy"):
		return
	var specs: Array = active_loader.get_objective_specs_copy()
	var controller = current_ship.get_objective_controller()
	# First visit registers the set; a retained/restored controller is already
	# configured, so this is a no-op that preserves progress.
	controller.configure(specs)
	for spec_variant in specs:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var sequence: int = int(spec.get("sequence", 0))
		if sequence <= 0:
			continue
		var position_variant: Variant = spec.get("position", Vector3.INF)
		if typeof(position_variant) != TYPE_VECTOR3:
			continue
		# Record salvage objective loot tables for grant on completion.
		if str(spec.get("type", "")) == "salvage":
			_salvage_loot_tables[str(spec.get("id", ""))] = str(spec.get("loot_table", "salvage_cargo"))
		var interactable = InteractableScript.new()
		interactable.configure_from_objective(spec, position_variant, 1.8)
		interactable.interaction_completed.connect(_on_derelict_interactable_completed)
		# Restore: a persisted-complete objective reads as done and cannot be re-fired
		# (try_interact returns false when completed).
		if controller.is_objective_complete(sequence):
			interactable.completed = true
			interactable.set_active(false)
		derelict_objective_root.add_child(interactable)
		derelict_interactables.append(interactable)
	# Show the derelict's objectives in the HUD while aboard, then reflect any
	# persisted/restored completion (set_objectives resets the tracker's completed
	# set, so this must run after it).
	if tracker != null:
		tracker.set_objectives(specs)
		_refresh_derelict_tracker()

## Mirrors the active derelict's controller state into the ObjectiveTracker: marks
## completed sequences, advances the "Current" pointer to the lowest incomplete
## objective, and flags run-complete once the derelict is cleared. Idempotent
## (tracker.mark_completed keys a dict), so it serves both restore-on-board and
## per-completion updates. No-op on the home ship (driven by the singleton loop).
func _refresh_derelict_tracker() -> void:
	if tracker == null or current_ship == null or String(current_ship.marker_id) == "":
		return
	var controller = current_ship.get_objective_controller()
	var first_incomplete: int = -1
	for it in derelict_interactables:
		if not is_instance_valid(it):
			continue
		var seq: int = int(it.sequence)
		if controller.is_objective_complete(seq):
			tracker.mark_completed(seq)
		elif first_incomplete < 0 or seq < first_incomplete:
			first_incomplete = seq
	if controller.is_cleared():
		tracker.mark_run_complete()
	elif first_incomplete > 0:
		tracker.set_current_sequence(first_incomplete)

## Frees the active derelict's interactables. The controller (state) lives on the
## ShipInstance and is untouched.
func _clear_derelict_objectives() -> void:
	if is_instance_valid(derelict_objective_root):
		for child in derelict_objective_root.get_children():
			derelict_objective_root.remove_child(child)
			child.queue_free()
	derelict_interactables.clear()

## Pushes the current inventory state to the HUD. Reuses _refresh_tracker_system_status_lines
## so the full combined status (systems + oxygen + inventory) is always consistent.
func _refresh_inventory_hud() -> void:
	_refresh_tracker_system_status_lines()

## Builds scattered loot containers for the active ship (derelict or home lifeboat).
## Containers already in the ship's looted_container_ids read as searched (no respawn).
## Sub-project #4: the home ship early-return is removed; the home loader is used when home.
func _build_loot_containers() -> void:
	_clear_loot_containers()
	if current_ship == null:
		return
	var active_loader = current_ship.scene_root if (away_from_start and current_ship != null) else loader
	if not is_instance_valid(active_loader) or not active_loader.has_method("get_loot_container_specs_copy"):
		return
	var looted: Array = current_ship.looted_container_ids
	for spec_variant in active_loader.get_loot_container_specs_copy():
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var cid: String = str(spec.get("id", ""))
		var pos_variant: Variant = spec.get("position", Vector3.INF)
		if cid.is_empty() or typeof(pos_variant) != TYPE_VECTOR3:
			continue
		var lc = LootContainerScript.new()
		var seed_source: String = "%s:%s" % [String(current_ship.marker_id), cid]
		lc.configure(cid, str(spec.get("loot_table", "generic_crate")), seed_source,
			inventory_state, _loot_tables, pos_variant, 1.8)
		if looted.has(cid):
			lc.set_searched(true)
		if not lc.container_searched.is_connected(_on_loot_container_searched):
			lc.container_searched.connect(_on_loot_container_searched)
		loot_container_root.add_child(lc)
		loot_containers.append(lc)

func _clear_loot_containers() -> void:
	if is_instance_valid(loot_container_root):
		for child in loot_container_root.get_children():
			loot_container_root.remove_child(child)
			child.queue_free()
	loot_containers.clear()

## Builds repair points for every currently-damaged subcomponent of the active ship,
## distributing them across the ship's rooms. Works for the lifeboat (home) and derelicts.
func _build_repair_points() -> void:
	_clear_repair_points()
	var mgr = _active_systems_manager()
	if mgr == null:
		return
	var positions: Array = _distributed_room_positions()
	if positions.is_empty():
		return
	var idx: int = 0
	for sid in mgr.system_order:
		var system = mgr.get_system(sid)
		if system == null:
			continue
		for sub in system.subcomponents:
			if sub.is_functional():
				continue
			var pos: Vector3 = positions[idx % positions.size()]
			idx += 1
			var rp = RepairPointScript.new()
			rp.configure(sid, sub.subcomponent_id, mgr, inventory_state, player_progression,
				pos, sub.repair_seconds, sub.min_skill, 1.8)
			if not rp.repair_completed.is_connected(_on_repair_completed):
				rp.repair_completed.connect(_on_repair_completed)
			repair_point_root.add_child(rp)
			repair_points.append(rp)

func _clear_repair_points() -> void:
	if is_instance_valid(repair_point_root):
		for child in repair_point_root.get_children():
			repair_point_root.remove_child(child)
			child.queue_free()
	repair_points.clear()

## The systems manager of the ship the player is currently aboard: the derelict's when away,
## the lifeboat's when home. (Repair points act on the ship under the player's feet; the
## travel gate separately reads the lifeboat — see _current_systems_ops.)
func _active_systems_manager():
	if away_from_start and current_ship != null and current_ship.systems_manager != null:
		return current_ship.systems_manager
	return ship_systems_manager

## Floor-cell world positions distributed across the active ship's rooms, for repair-point
## placement. Reuses the active loader's room/cell resolution where available.
func _distributed_room_positions() -> Array:
	var out: Array = []
	var active_loader = current_ship.scene_root if (away_from_start and current_ship != null) else loader
	if is_instance_valid(active_loader) and active_loader.has_method("get_objective_specs_copy"):
		for spec in active_loader.get_objective_specs_copy():
			if typeof(spec) == TYPE_DICTIONARY and typeof(spec.get("position", null)) == TYPE_VECTOR3:
				out.append(spec["position"])
	# Fallback: derive from loot container specs if no objective positions exist.
	if out.is_empty() and is_instance_valid(active_loader) and active_loader.has_method("get_loot_container_specs_copy"):
		for spec in active_loader.get_loot_container_specs_copy():
			if typeof(spec) == TYPE_DICTIONARY and typeof(spec.get("position", null)) == TYPE_VECTOR3:
				out.append(spec["position"])
	return out

func _on_repair_completed(system_id: String, subcomponent_id: String) -> void:
	_refresh_inventory_hud()
	print("REPAIR COMPLETED system=%s sub=%s operational=%s" % [
		system_id, subcomponent_id, str(_active_systems_manager().is_operational(system_id)).to_lower()])

## Validation seam: start a repair-point channel via the real path, by subcomponent.
func repair_subcomponent_for_validation(system_id: String, subcomponent_id: String) -> bool:
	for rp in repair_points:
		if is_instance_valid(rp) and rp.system_id == system_id and rp.subcomponent_id == subcomponent_id and not rp.repaired:
			rp.set_validation_player_in_range(player)
			return rp.try_start(player)
	return false

## Validation seam: pump all channeling repair points by delta (deterministic timed advance).
func advance_repair_channels_for_validation(delta: float) -> void:
	for rp in repair_points:
		if is_instance_valid(rp) and rp.channeling:
			rp.advance_channel(delta)

## Curates the lifeboat's propulsion so the opening blocker is a single low-skill repair:
## nav_linkage broken (circuit_board, skill 2, no tool), the other propulsion subs healthy.
## Propulsion is offline at boot (and stays so until repaired), making "repair the lifeboat to
## travel" the opening. Other systems keep their deterministic condition damage (the existing
## objective loop repairs power/navigation; nothing else depends on propulsion's start health).
func _apply_lifeboat_opening_damage() -> void:
	if ship_systems_manager == null:
		return
	var prop = ship_systems_manager.get_system("propulsion")
	if prop == null:
		return
	for sub in prop.subcomponents:
		sub.health = 1.0
	var blocker = prop.get_subcomponent("nav_linkage")
	if blocker != null:
		blocker.health = ShipSystemsManagerScript.DAMAGED_HEALTH

## Records a searched scattered container on the per-ship slice + refreshes the HUD.
func _on_loot_container_searched(container_id: String, granted: Array) -> void:
	if current_ship != null and not current_ship.looted_container_ids.has(container_id):
		current_ship.looted_container_ids.append(container_id)
	_refresh_inventory_hud()
	print("LOOT CONTAINER SEARCHED marker=%s container=%s granted=%d" % [
		String(current_ship.marker_id) if current_ship != null else "", container_id, granted.size()])

## Validation seam: search a loot container by id through the real interaction path.
func search_loot_container_for_validation(container_id: String) -> bool:
	for lc in loot_containers:
		if is_instance_valid(lc) and String(lc.container_id) == container_id and not lc.searched:
			lc.set_validation_player_in_range(player)
			return lc.try_interact(player)
	return false

## Routes a derelict interactable completion to the active ship's controller.
func _on_derelict_interactable_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String, step_id: String) -> void:
	if current_ship == null:
		return
	var controller = current_ship.get_objective_controller()
	controller.complete(sequence)
	# Reflect the completion (and run-complete on clear) in the HUD.
	_refresh_derelict_tracker()
	# Sub-project #3: grant salvage-point loot on objective completion (once only —
	# the interactable cannot re-fire after completed = true).
	if objective_type == "salvage" and _salvage_loot_tables.has(objective_id):
		var seed_source: String = "%s:%s" % [String(current_ship.marker_id), objective_id]
		var rolled: Array = LootRollerScript.roll(_salvage_loot_tables[objective_id], seed_source, _loot_tables)
		for entry in rolled:
			inventory_state.add_item(str(entry.get("item_id", "")), int(entry.get("quantity", 0)))
		_refresh_inventory_hud()
	print("DERELICT OBJECTIVE COMPLETE marker=%s sequence=%d type=%s cleared=%s" % [
		String(current_ship.marker_id), sequence, objective_type, str(controller.is_cleared()).to_lower()])

## Validation seam: complete a derelict objective by sequence through the real
## interaction path (bypassing proximity via set_validation_player_in_range).
func complete_derelict_objective_for_validation(sequence: int) -> bool:
	for it in derelict_interactables:
		if is_instance_valid(it) and int(it.sequence) == sequence and not it.completed:
			it.set_validation_player_in_range(player)
			return it.try_interact(player)
	return false

## Validates + executes a jump to a marker, swapping current_ship and re-homing
## the player on success. Travel is gated by the CURRENT ship's propulsion.
func travel_to(marker) -> Dictionary:
	if current_ship == null or sargasso_world == null or travel_controller == null or ship_generator == null:
		return {"success": false, "reason": "not_ready", "ship": null}
	var ops_t: Dictionary = {"propulsion": bool(_current_systems_ops().get("propulsion", false))}
	var result: Dictionary = travel_controller.attempt_travel(
		marker, ops_t, sargasso_world, ship_generator, scanner_state.range_radius)
	if not bool(result.get("success", false)):
		return result
	var new_root: Node3D = result.get("ship", null)
	if new_root == null:
		return {"success": false, "reason": "generation_failed", "ship": null}

	# Leaving the current ship. The HOME ship is detached-not-freed (retains its
	# live sim); a DERELICT keeps its retained ShipInstance in visited_ships but
	# frees its scene_root (geometry regenerates from seed on revisit).
	var leaving = current_ship
	if String(leaving.marker_id) == "":
		_home_player_position = (player as Node3D).global_position if player != null and player is Node3D else _home_player_position
		if leaving.scene_root != null and is_instance_valid(leaving.scene_root) and leaving.scene_root.get_parent() == self:
			remove_child(leaving.scene_root)
		_detach_starting_gameplay_roots()
	else:
		if leaving.scene_root != null and is_instance_valid(leaving.scene_root):
			if leaving.scene_root.get_parent() == self:
				remove_child(leaving.scene_root)
			leaving.scene_root.queue_free()
		leaving.scene_root = null  # retained instance, scene dropped

	var mid: String = String(marker.marker_id)
	var inst
	if visited_ships.has(mid):
		# Revisit: reuse the retained instance (its systems state is preserved);
		# the freshly generated geometry replaces the freed scene.
		inst = visited_ships[mid]
	else:
		# First visit: build the per-ship systems manager seeded by condition so a
		# wrecked ship boards with mostly-offline systems, and register it.
		var new_bp = ShipBlueprintScript.new(int(marker.size_class), int(marker.condition), int(marker.seed_value))
		var new_mgr = ShipSystemsManagerScript.new()
		new_mgr.configure(new_mgr.load_definitions(), new_bp.condition, new_bp.seed_value)
		inst = ShipInstanceScript.create("ship_%s" % mid, mid, new_bp, new_mgr, null)
		visited_ships[mid] = inst

	_attach_derelict_active(inst, new_root)

	# Re-home the existing player + camera into the new ship's spawn. The player
	# node, camera, HUD, progression and inventory are NEVER freed (player-owned).
	if player != null and new_root.has_method("get_start_transform"):
		player.teleport_to(new_root.get_start_transform().origin + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0))
	return result

## Returns the player to the home ship instance: frees the active derelict's
## scene (its retained instance stays in visited_ships), re-attaches the home
## scene_root and gameplay roots, restores current_ship = home_ship, and re-homes
## the player at the position they left from. Returns false if not currently away
## or the home ship is unavailable.
func travel_home() -> bool:
	if not away_from_start or home_ship == null:
		return false
	var leaving = current_ship
	if leaving != null and String(leaving.marker_id) != "":
		if leaving.scene_root != null and is_instance_valid(leaving.scene_root):
			if leaving.scene_root.get_parent() == self:
				remove_child(leaving.scene_root)
			leaving.scene_root.queue_free()
		leaving.scene_root = null
	if home_ship.scene_root != null and is_instance_valid(home_ship.scene_root) and home_ship.scene_root.get_parent() == null:
		add_child(home_ship.scene_root)
	_reattach_starting_gameplay_roots()
	current_ship = home_ship
	away_from_start = false
	_clear_derelict_objectives()
	_clear_loot_containers()
	_clear_repair_points()
	if tracker != null and loader != null and loader.has_method("get_objective_specs_copy"):
		# set_objectives resets the tracker's completed set; re-apply the home loop's
		# progress so returning home does not blank a partially-completed home HUD.
		tracker.set_objectives(loader.get_objective_specs_copy())
		_refresh_home_tracker_completed()
	if player != null and player is Node3D:
		(player as Node3D).global_position = _home_player_position
	return true

## Re-applies the home objective loop's completion state to the ObjectiveTracker
## after a set_objectives reset (sequences below current_objective_sequence are
## complete). Mirrors, for the home ship's singleton loop, what
## _refresh_derelict_tracker does for a derelict.
func _refresh_home_tracker_completed() -> void:
	if tracker == null:
		return
	for s in range(1, current_objective_sequence):
		tracker.mark_completed(s)
	tracker.set_current_sequence(current_objective_sequence)
	if slice_complete:
		tracker.mark_run_complete()

## Validation seam: the marker_ids of every retained visited derelict.
func get_visited_ship_ids() -> Array:
	return visited_ships.keys()

## Validation seam: true if any combined status line contains `token`.
func get_combined_system_status_lines_contains(token: String) -> bool:
	for line in _combined_system_status_lines():
		if String(line).contains(token):
			return true
	return false

## Allocates the HUD CanvasLayer and the ObjectiveTracker that lives
## inside it. Called from _build_runtime_nodes (initial slice setup)
## and from _on_ship_loaded (reload via REQ-012). Extracted from
## _build_runtime_nodes so the reload path can rebuild the tracker
## after _reset_runtime_for_reload frees it — without this, the
## reload path left `tracker` pointing at a freed Node and every
## post-load interaction crashed with "Nonexistent function
## 'mark_completed' in base 'previously freed'" (REQ-014 blocking
## finding B / pre-existing REQ-012 reload lifecycle debt).
func _build_hud_layer() -> void:
	# Always release the prior hud_layer if the caller (reload) is
	# rebuilding on top of a stale one. The node itself is freed by
	# _reset_runtime_for_reload's hud_layer teardown; nulling here is
	# the safety net so the helper is idempotent.
	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.queue_free()
	hud_layer = CanvasLayer.new()
	hud_layer.name = "PlayableHudLayer"
	hud_layer.layer = 20
	add_child(hud_layer)
	tracker = ObjectiveTrackerScript.new()
	tracker.name = "ObjectiveTracker"
	# A11Y-P1-001: pass the ship's accessibility_settings into the tracker
	# so the HUD font_size and panel size come from the same seam as the
	# world Label3D labels. Tracker is parented to the hud_layer below, so
	# the tracker's _ready() will run after this call returns.
	if tracker.has_method("apply_accessibility_settings"):
		tracker.apply_accessibility_settings(accessibility_settings)
	hud_layer.add_child(tracker)
	scanner_panel = ScannerPanelScript.new()
	scanner_panel.name = "ScannerPanel"
	scanner_panel.visible = false
	hud_layer.add_child(scanner_panel)
	scanner_panel.bind(self)
	# Restore player control on every panel close path via the signal, not just
	# the two close paths wired into _input.
	scanner_panel.panel_closed.connect(_on_scanner_panel_closed)

func _on_scanner_panel_closed() -> void:
	if player != null:
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)

func _on_ship_loaded(summary: Dictionary) -> void:
	if playable_started:
		return
	playable_started = true
	# REQ-014 blocking finding B: rebuild the HUD/tracker on every ship
	# load, not just the first one. After _reset_runtime_for_reload
	# tears down the previous slice (incl. hud_layer and tracker), the
	# coordinator must rebuild them or the post-load interaction path
	# (e.g. completing a repair_junction after load) crashes with
	# "Nonexistent function 'mark_completed' in base 'previously freed'".
	_build_hud_layer()
	_spawn_player()
	_spawn_camera()
	# Phase 4.5: wrap the freshly-loaded starting ship as current_ship. Reuses
	# the coordinator's existing ship_systems_manager (Approach A: the starting
	# slice's systems are untouched). marker_id "" marks it as the home ship.
	if current_ship == null:
		current_ship = ShipInstanceScript.create("ship_start", "", _load_blueprint_for_systems(), ship_systems_manager, loader)
		# Sub-project #1: keep a stable reference to the home ship so travel_home
		# and world-load can restore it.
		home_ship = current_ship
	_build_interactables()
	_build_slice_affordance_labels()
	_build_route_control_gates()
	_refresh_route_control_from_ship_systems()
	_build_breach_zone()
	# REQ-007: spawn the portable oxygen pump pickup now that the player,
	# interactables, and breach zone exist. The pickup is parented to
	# tool_pickup_root and reads its world position from a side room
	# (tool_storage_01 if defined) with a player-spawn fallback.
	_build_tool_pickup()
	# REQ-014: spawn the junction_calibrator pickup in a different side
	# room (galley_01 with a player-spawn fallback offset on the
	# opposite side of the spawn). Same parent root as the oxygen pump
	# so the existing reset/reload teardown covers it.
	_build_junction_calibrator_pickup()
	_refresh_oxygen_state(true, 0.0)
	_build_fire_zone()
	_refresh_fire_state(true)
	_build_arc_zone()
	_refresh_arc_state(true)
	_build_loot_containers()
	_build_repair_points()
	tracker.set_objectives(loader.get_objective_specs_copy())
	current_objective_sequence = 1
	slice_complete = false
	_activate_current_objective()
	ready_summary = summary.duplicate(true)
	ready_summary["player_spawned"] = player != null
	ready_summary["camera_spawned"] = camera_rig != null
	ready_summary["collision_shape_count"] = loader.count_collision_shapes()
	ready_summary["playable_interactable_count"] = interactables.size()
	print("PLAYABLE SHIP READY player_spawned=%s camera_spawned=%s objectives=%d collision_shapes=%d" % [str(player != null).to_lower(), str(camera_rig != null).to_lower(), interactables.size(), loader.count_collision_shapes()])
	emit_signal("playable_ready", get_playable_summary())

func _on_loader_failed(reason: String) -> void:
	last_failure_reason = reason
	push_error("PLAYABLE SHIP FAIL reason=%s" % reason)
	emit_signal("playable_failed", reason)

func _spawn_player() -> void:
	player = PlayerControllerScript.new()
	player.name = "PlayerController"
	add_child(player)
	player.teleport_to(loader.get_start_transform().origin + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0))
	player.interact_requested.connect(_on_player_interact_requested)

func _spawn_camera() -> void:
	camera_rig = IsoCameraRigScript.new()
	camera_rig.name = "IsoCameraRig"
	add_child(camera_rig)
	camera_rig.set_follow_target(player)
	camera_rig.make_current()

func _build_interactables() -> void:
	interactables.clear()
	sequence_interactables.clear()
	# REQ-014: clear the per-sequence kind lookup so a fresh interactable
	# build reflects only the current loader's objective specs (e.g. after
	# a save/load reload).
	sequence_kinds.clear()
	if objective_progress_state != null:
		objective_progress_state.reset()
	for child in interaction_root.get_children():
		interaction_root.remove_child(child)
		child.free()
	for objective_variant in loader.get_objective_specs_copy():
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var sequence: int = int(objective.get("sequence", 0))
		var kind: String = str(objective.get("kind", "single"))
		# REQ-014: cache the kind per sequence so _on_interactable_completed
		# can decide whether to apply the junction_calibrator without
		# re-walking the loader's objective specs.
		sequence_kinds[sequence] = kind
		var steps: Array = []
		var steps_variant: Variant = objective.get("steps", [])
		if typeof(steps_variant) == TYPE_ARRAY:
			steps = steps_variant
		if kind == "repair_junction" and steps.size() > 1:
			var required_steps: int = steps.size()
			var objective_type: String = str(objective.get("type", "unknown"))
			if objective_progress_state != null:
				objective_progress_state.register_objective(sequence, objective_type, required_steps)
			for step_variant in steps:
				if typeof(step_variant) != TYPE_DICTIONARY:
					continue
				var step: Dictionary = step_variant
				var step_position_variant: Variant = step.get("position", Vector3.INF)
				if typeof(step_position_variant) != TYPE_VECTOR3:
					continue
				var interactable = InteractableScript.new()
				interactable.configure_from_step(objective, step, step_position_variant, 1.8)
				interactable.interaction_completed.connect(_on_interactable_completed)
				interaction_root.add_child(interactable)
				interactables.append(interactable)
				_add_interactable_to_sequence(sequence, interactable)
		else:
			var position_variant: Variant = objective.get("position", Vector3.INF)
			if typeof(position_variant) != TYPE_VECTOR3:
				continue
			var interactable = InteractableScript.new()
			interactable.configure_from_objective(objective, position_variant, 1.8)
			interactable.interaction_completed.connect(_on_interactable_completed)
			interaction_root.add_child(interactable)
			interactables.append(interactable)
			_add_interactable_to_sequence(sequence, interactable)

func _add_interactable_to_sequence(sequence: int, interactable: Node) -> void:
	if not sequence_interactables.has(sequence):
		sequence_interactables[sequence] = []
	sequence_interactables[sequence].append(interactable)

func _on_player_interact_requested(player_body: PlayerController) -> void:
	# Phase 4.5: while aboard a traveled derelict the starting ship's retained
	# interactables/pickups are detached but still referenced here; gate them so
	# a derelict cannot complete stale starting-ship objectives.
	if away_from_start:
		# Sub-project #4: try repair points before loot/objectives.
		for rp in repair_points:
			if is_instance_valid(rp) and rp.try_start(player_body):
				return
		# Sub-project #3: derelict loot containers are pickup-like interactables.
		# Try them before objectives, matching the home ship's tool-pickup
		# precedence when an objective and pickup share the same interaction area.
		for lc in loot_containers:
			if is_instance_valid(lc) and lc.try_interact(player_body):
				return
		# Sub-project #2: the boarded derelict has its own objective interactables.
		for it in derelict_interactables:
			if is_instance_valid(it) and it.try_interact(player_body):
				return
		return
	# Sub-project #4: try lifeboat repair points before pickups/objectives.
	for rp in repair_points:
		if is_instance_valid(rp) and rp.try_start(player_body):
			return
	# REQ-007: tool pickup is an interaction like any other. Try it first
	# (before objective interactables) so the player can pick up the pump
	# when standing in front of it.
	if tool_pickup != null and tool_pickup.try_interact(player_body):
		return
	# REQ-014: junction_calibrator pickup is a second pickup; the
	# acquisition event is dispatched through the same shared ToolPickup
	# signal as the oxygen pump so the coordinator can refresh the HUD
	# via the same code path.
	if junction_calibrator_pickup != null and junction_calibrator_pickup.try_interact(player_body):
		return
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if interactable.try_interact(player_body):
			return

func _on_interactable_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String, step_id: String) -> void:
	if sequence != current_objective_sequence:
		return

	# REQ-014: apply the junction_calibrator BEFORE the step completion
	# so the reduced required_steps is reflected in the same interaction
	# frame's progress summary. Only sequences whose gameplay_slice spec
	# declared `kind == "repair_junction"` are eligible; the sequence_kinds
	# lookup is populated by _build_interactables from the loader specs.
	#
	# The pre-calibration required_steps is what governs whether we take
	# the multi-step complete_step path or the single-step completion path.
	# Reading the value AFTER the calibrator consume would observe the
	# post-calibration required_steps (e.g. 1 for a 2-step junction reduced
	# by the calibrator) and skip complete_step, leaving the model with
	# completed_steps=0 even though the coordinator advanced the sequence.
	# That is the exact REQ-014 blocking-finding-A symptom (the model is
	# "complete=false" while the ship/route/inventory state already moved on).
	var pre_required_steps: int = 1
	if objective_progress_state != null:
		pre_required_steps = int(objective_progress_state.get_step_progress(sequence).get("required_steps", 1))
	_consume_junction_calibrator_if_eligible(sequence)
	var is_multi_step: bool = pre_required_steps > 1
	if is_multi_step:
		var step_changed: bool = objective_progress_state.complete_step(sequence, step_id)
		if not step_changed:
			return
		var progress: Dictionary = objective_progress_state.get_step_progress(sequence)
		if tracker != null:
			tracker.set_step_progress(sequence, progress)
		print("OBJECTIVE STEP COMPLETED sequence=%d step=%s progress=%d/%d" % [
			sequence,
			step_id,
			int(progress.get("completed_steps", 0)),
			int(progress.get("required_steps", 1)),
		])
		if not objective_progress_state.is_sequence_complete(sequence):
			return
		# Fall through to single-step completion path exactly once.

	objective_completion_count += 1
	if ship_systems_manager != null:
		completed_objective_types[objective_type] = true
		for pair in OBJECTIVE_REPAIR_MAP.get(objective_type, []):
			ship_systems_manager.force_repair(str(pair[0]), str(pair[1]))
		if player_progression != null and (objective_type == "restore_systems" or objective_type == "stabilize_reactor"):
			player_progression.grant_xp("repair", REPAIR_OBJECTIVE_XP)
		var compat: Dictionary = _manager_compat_summary()
		_apply_ship_systems_consequences(objective_type)
		_refresh_route_control_from_ship_systems()
		if oxygen_state != null:
			oxygen_state.apply_ship_systems_summary(compat)
			_refresh_oxygen_state(false, 0.0)
		var route_summary: Dictionary = get_route_control_summary()
		print("SHIP SYSTEM UPDATED sequence=%d type=%s power=%d reactor=%d extraction=%s route_opened=%d blockers=%d" % [
			sequence,
			objective_type,
			int(compat.get("power_percent", 0)),
			int(compat.get("reactor_stability_percent", 0)),
			str(bool(compat.get("extraction_unlocked", false))),
			int(route_summary.get("opened_gate_count", 0)),
			int(route_summary.get("active_blocker_count", 0)),
		])
	tracker.mark_completed(sequence)
	print("PLAYABLE INTERACTION interaction=%s objective=%s sequence=%d type=%s room=%s" % [interaction_id, objective_id, sequence, objective_type, room_id])
	emit_signal("playable_interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id)
	# A "sequence" is one logical objective; multi-step objectives contribute
	# one objective_completion_count increment (here) and N interactables
	# (one per step). Compare against the number of sequences, not the
	# number of interactables, so the slice is considered complete once
	# every distinct sequence has fired apply_objective() exactly once.
	var total_sequences: int = sequence_interactables.size()
	if objective_completion_count >= total_sequences:
		slice_complete = true
		current_objective_sequence = total_sequences + 1
		tracker.mark_run_complete()
		print("PLAYABLE SLICE COMPLETE objectives_completed=%d" % objective_completion_count)
		# REQ-012: drop the current-run save file so a stale snapshot
		# cannot be resumed into a finished run. A fresh run
		# automatically starts with no save file (delete returns true
		# when the file is already absent).
		if save_load_service != null:
			save_load_service.delete_current_run()
		emit_signal("playable_slice_completed", get_slice_completion_summary())
		return
	# REQ-012: auto-save at every stable objective-completion boundary.
	# Multi-step objectives only fire this once (after the final step
	# completes), which matches the auto-save contract.
	# Order matters: advance the live sequence FIRST so the snapshot
	# captures the resumed sequence the player is about to be working
	# on (after objective 1 -> 2). Saving before the increment would
	# persist the just-completed sequence and a load would put the
	# player back on the same objective they just finished.
	current_objective_sequence += 1
	_auto_save_current_run()
	_activate_current_objective()

func _apply_ship_systems_consequences(objective_type: String) -> void:
	if objective_type == "restore_systems":
		_clear_blocked_affordances()

func _clear_blocked_affordances() -> void:
	if affordance_root == null:
		return
	for child in affordance_root.get_children():
		if String(child.name).begins_with("BlockedAffordance_"):
			child.visible = false
			child.set_meta("system_cleared", true)

func get_blocked_affordance_visible_count() -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if String(child.name).begins_with("BlockedAffordance_") and child.visible:
			count += 1
	return count

func _refresh_route_control_from_ship_systems() -> void:
	if route_control_state == null or ship_systems_manager == null:
		_refresh_tracker_system_status_lines()
		return
	route_control_state.apply_ship_systems_summary(_manager_compat_summary())
	_apply_route_gate_scene_state()
	_refresh_tracker_system_status_lines()

func _apply_route_gate_scene_state() -> void:
	if route_control_state == null:
		return
	for gate_variant in route_gate_nodes:
		if not (gate_variant is Node):
			continue
		var gate: Node = gate_variant as Node
		var gate_id: String = str(gate.get_meta("route_gate_id", ""))
		var is_open: bool = route_control_state.is_gate_open(gate_id)
		gate.set_meta("route_gate_open", is_open)
		gate.set_meta("system_cleared", is_open)
		gate.visible = true
		_set_route_gate_collision_enabled(gate, not is_open)
		_update_route_gate_visual(gate, is_open)

func _set_route_gate_collision_enabled(gate: Node, enabled: bool) -> void:
	for child in gate.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_route_gate_visual(gate: Node, is_open: bool) -> void:
	for child in gate.get_children():
		if child is MeshInstance3D and child.name == "RouteGateVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_route_gate_material(is_open)
			visual.visible = not is_open

func _refresh_tracker_system_status_lines() -> void:
	if tracker == null:
		return
	tracker.set_system_status_lines(_combined_system_status_lines())

func _combined_system_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if ship_systems_manager != null:
		var compat: Dictionary = _manager_compat_summary()
		lines.append("Power: %d%%" % int(compat.get("power_percent", 0)))
		lines.append("Reactor: %d%%" % int(compat.get("reactor_stability_percent", 0)))
		lines.append("Supplies: %s" % ("OK" if bool(compat.get("emergency_supplies_recovered", false)) else "LOW"))
		lines.append("Main Power: %s" % ("ON" if bool(compat.get("main_power_restored", false)) else "OFF"))
		lines.append("Logs: %s" % ("DOWNLOADED" if bool(compat.get("navigation_logs_downloaded", false)) else "PENDING"))
		lines.append("Reactor: %s" % ("STABLE" if bool(compat.get("reactor_stabilized", false)) else "UNSTABLE"))
	if route_control_state != null:
		for line in route_control_state.get_status_lines():
			lines.append(String(line))
	if oxygen_state != null:
		for line in oxygen_state.get_status_lines():
			lines.append(String(line))
	# REQ-007: surface carried tools on the HUD via inventory status lines.
	if inventory_state != null:
		for line in inventory_state.get_status_lines():
			lines.append(String(line))
	if player_progression != null:
		lines.append("Repair Skill: %d" % player_progression.get_skill_level("repair"))
	return lines

func get_combined_system_status_lines() -> PackedStringArray:
	return _combined_system_status_lines()

func _sub_health(system_id: String, sub_id: String) -> float:
	if ship_systems_manager == null:
		return 0.0
	var system = ship_systems_manager.get_system(system_id)
	if system == null:
		return 0.0
	var sub = system.get_subcomponent(sub_id)
	return sub.health if sub != null else 0.0

func _sub_functional(system_id: String, sub_id: String) -> bool:
	if ship_systems_manager == null:
		return false
	var system = ship_systems_manager.get_system(system_id)
	if system == null:
		return false
	var sub = system.get_subcomponent(sub_id)
	return sub != null and sub.is_functional()

## Flag-shaped summary derived from manager subcomponent state + the narrative
## record. Feeds the unchanged route_control_state / breach oxygen_state models
## and the HUD (ShipSystemsManager is the sole source of truth for ship-system state).
func _manager_compat_summary() -> Dictionary:
	var power_restored: bool = _sub_functional("power", "power_distribution") and _sub_functional("power", "battery_cells")
	var reactor_full: bool = _sub_health("power", "reactor_core") >= 1.0
	var power_health: float = 0.0
	if ship_systems_manager != null and ship_systems_manager.get_system("power") != null:
		power_health = ship_systems_manager.get_system("power").health()
	return {
		"emergency_supplies_recovered": completed_objective_types.has("recover_supplies"),
		"main_power_restored": power_restored,
		"navigation_logs_downloaded": completed_objective_types.has("download_logs"),
		"reactor_stabilized": reactor_full,
		"blocked_routes_cleared": power_restored,
		"extraction_unlocked": reactor_full,
		"power_percent": int(round(power_health * 100.0)),
		"reactor_stability_percent": int(round(_sub_health("power", "reactor_core") * 100.0)),
	}

func get_ship_systems_summary() -> Dictionary:
	var summary: Dictionary = {}
	if ship_systems_manager == null:
		summary["main_power_restored"] = false
		summary["extraction_unlocked"] = false
		summary["power_percent"] = 0
		summary["reactor_stability_percent"] = 0
		summary["blocked_affordance_visible_count"] = 0
		return summary
	summary = _manager_compat_summary()
	summary["blocked_affordance_visible_count"] = get_blocked_affordance_visible_count()
	return summary

func get_route_control_summary() -> Dictionary:
	var summary: Dictionary = {}
	if route_control_state == null:
		summary["route_gate_count"] = 0
		summary["active_blocker_count"] = 0
		summary["opened_gate_count"] = 0
		summary["powered_gates_open"] = false
		summary["extraction_unlocked"] = false
		summary["gate_ids"] = []
		summary["route_gate_collision_enabled_count"] = 0
		return summary
	summary = route_control_state.get_summary()
	summary["route_gate_collision_enabled_count"] = get_route_gate_collision_enabled_count()
	return summary

func get_route_gate_nodes() -> Array:
	return route_gate_nodes.duplicate()

func get_route_gate_collision_enabled_count() -> int:
	var count: int = 0
	for gate_variant in route_gate_nodes:
		if not (gate_variant is Node):
			continue
		var gate: Node = gate_variant as Node
		for child in gate.get_children():
			if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
				count += 1
	return count

# --- Hazard / OxygenState integration -----------------------------------------
# Per-frame oxygen ticks are wired here so the Gate 1 hazard pressure loop
# is a real runtime system (see docs/game/features/hazards.md lines 24, 39,
# 52, 74, 83-88 and REQ-006). The tick reads the actual player position
# (via is_player_in_breach_zone) and delegates drain/regen to OxygenState.
# It runs while the playable slice is alive (started but not yet complete)
# and is intentionally a no-op before ship load completes.

func _process(delta: float) -> void:
	if away_from_start:
		return
	if not playable_started or slice_complete:
		return
	if oxygen_state == null:
		return
	if ship_systems_manager != null:
		ship_systems_manager.advance(delta)
	_refresh_oxygen_state(false, delta)
	if fire_state != null:
		fire_state.tick(delta)
		_refresh_fire_state(false)
	# REQ-013: tick the electrical-arc model with the same per-frame
	# delta so its phase / passability advance in lock-step with fire.
	# electrical_arc_state.tick ignores the second arg (no per-frame
	# context is needed; oxygen is the only Alpha hazard that uses it).
	if electrical_arc_state != null:
		electrical_arc_state.tick(delta, {})
		_refresh_arc_state(false)

func _build_breach_zone() -> void:
	if oxygen_root == null:
		return
	for child in oxygen_root.get_children():
		oxygen_root.remove_child(child)
		child.queue_free()
	breach_zone_node = null
	unsafe_room_marker = null
	var world_position: Vector3 = _resolve_breach_zone_world_position()
	if oxygen_state == null:
		oxygen_state = OxygenStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary so
	# each hazard model unpacks the fields it cares about. OxygenState
	# reads max_oxygen / drain_rate / regen_rate / recovery_threshold /
	# safe_threshold plus the zone_ids array.
	oxygen_state.configure({
		"zone_ids": [BREACH_ZONE_FALLBACK_ID],
		"max_oxygen": OxygenStateScript.DEFAULT_MAX_OXYGEN,
		"drain_rate": OxygenStateScript.DEFAULT_DRAIN_RATE,
		"regen_rate": OxygenStateScript.DEFAULT_REGEN_RATE,
		"recovery_threshold": OxygenStateScript.DEFAULT_RECOVERY_THRESHOLD,
		"safe_threshold": OxygenStateScript.DEFAULT_SAFE_THRESHOLD,
	})
	breach_zone_node = _create_breach_zone_node(world_position)
	oxygen_root.add_child(breach_zone_node)
	unsafe_room_marker = _create_unsafe_room_marker(world_position)
	oxygen_root.add_child(unsafe_room_marker)

func _resolve_breach_zone_world_position() -> Vector3:
	if loader != null and loader.has_method("get_breach_zone_markers"):
		var markers: Array = loader.get_breach_zone_markers()
		if markers.size() > 0 and markers[0] is Vector3:
			var candidate: Vector3 = markers[0]
			if candidate != Vector3.INF:
				return candidate
	# Fallback: midpoint between objective-3 and objective-4 interactable positions.
	var obj3_pos: Vector3 = Vector3.INF
	var obj4_pos: Vector3 = Vector3.INF
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if not (interactable is Node3D):
			continue
		var seq: int = int(interactable.get("sequence"))
		if seq == 3:
			obj3_pos = (interactable as Node3D).global_position
		elif seq == 4:
			obj4_pos = (interactable as Node3D).global_position
	if obj3_pos == Vector3.INF or obj4_pos == Vector3.INF:
		# Last-ditch: fall back to player spawn + 6m forward.
		if player != null:
			return player.global_position + Vector3(0.0, 0.0, 6.0)
		return Vector3.ZERO
	return (obj3_pos + obj4_pos) * 0.5

func _create_breach_zone_node(world_position: Vector3) -> StaticBody3D:
	var zone: StaticBody3D = StaticBody3D.new()
	zone.name = "BreachZone_OxygenCorridor"
	zone.position = world_position
	zone.collision_layer = 1
	zone.collision_mask = 1
	zone.set_meta("breach_zone_id", BREACH_ZONE_FALLBACK_ID)
	zone.set_meta("breach_zone_kind", "oxygen_breach")
	zone.set_meta("breach_zone_open", true)
	zone.set_meta("breach_zone_sealed", false)
	zone.set_meta("breach_zone_passability_blocked", false)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "BreachZoneCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = BREACH_ZONE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, BREACH_ZONE_COLLISION_SIZE.y * 0.5, 0.0)
	zone.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "BreachZoneVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = BREACH_ZONE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_breach_zone_material(true, false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.add_child(visual)
	return zone

func _make_breach_zone_material(is_open: bool, is_blocked: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	if is_blocked:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_BLOCKED
	elif is_open:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_OPEN
	else:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_SEALED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _create_unsafe_room_marker(world_position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "BreachUnsafeMarker"
	label.text = BREACH_ZONE_UNSAFE_LABEL_TEXT
	label.position = world_position + Vector3(0.0, BREACH_ZONE_COLLISION_SIZE.y + 0.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	# A11Y-P1-001: world label pixel_size flows through the single
	# accessibility_settings seam. Default scale=1.0 keeps the prior
	# 0.0035 value exactly; larger scales divide the pixel_size so the
	# label renders larger on screen for the same world position.
	label.pixel_size = accessibility_settings.scaled_world_pixel_size(0.0035)
	label.modulate = Color(1.0, 0.32, 0.22, 1.0)
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	label.visible = false
	return label

func _refresh_oxygen_state(force_initial: bool, delta_seconds: float) -> void:
	if oxygen_state == null:
		_refresh_tracker_system_status_lines()
		return
	# REQ-007: keep OxygenState's view of the inventory in sync with the
	# coordinator's InventoryState BEFORE the per-frame tick so the drain
	# multiplier reflects any tools acquired this frame.
	if inventory_state != null:
		oxygen_state.apply_inventory_summary(inventory_state.get_summary())
	if force_initial:
		oxygen_state.apply_ship_systems_summary({})  # no-op; recompute passability
		_apply_breach_zone_scene_state()
		_refresh_tracker_system_status_lines()
		return
	# Per-tick path: read player position, decide breach presence, tick.
	var player_in_zone: bool = is_player_in_breach_zone()
	oxygen_state.tick(delta_seconds, player_in_zone)
	_apply_breach_zone_scene_state()
	_refresh_tracker_system_status_lines()

func _apply_breach_zone_scene_state() -> void:
	if oxygen_state == null or breach_zone_node == null:
		return
	var summary: Dictionary = oxygen_state.get_summary()
	var breach_open: bool = bool(summary.get("breach_open", false))
	var breach_sealed: bool = bool(summary.get("breach_sealed", false))
	var passability_blocked: bool = bool(summary.get("passability_blocked", false))
	breach_zone_node.set_meta("breach_zone_open", breach_open)
	breach_zone_node.set_meta("breach_zone_sealed", breach_sealed)
	breach_zone_node.set_meta("breach_zone_passability_blocked", passability_blocked)
	# Per the feature spec: the breach zone is passable while the player has
	# oxygen above the recovery threshold; once oxygen hits zero, the
	# collision is enabled to block forward traversal until oxygen recovers.
	# Once sealed (objective 2), the corridor is safe and collision is off.
	var collision_enabled: bool = breach_open and passability_blocked
	_set_breach_zone_collision_enabled(breach_zone_node, collision_enabled)
	_update_breach_zone_visual(breach_zone_node, breach_open, passability_blocked)
	if unsafe_room_marker != null:
		unsafe_room_marker.visible = breach_open and not breach_sealed

func _set_breach_zone_collision_enabled(zone: Node, enabled: bool) -> void:
	for child in zone.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_breach_zone_visual(zone: Node, is_open: bool, is_blocked: bool) -> void:
	for child in zone.get_children():
		if child is MeshInstance3D and child.name == "BreachZoneVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_breach_zone_material(is_open, is_blocked)
			visual.visible = is_open

func get_oxygen_summary() -> Dictionary:
	var summary: Dictionary = {}
	if oxygen_state == null:
		summary["oxygen"] = 0.0
		summary["max_oxygen"] = 0.0
		summary["drain_rate"] = 0.0
		summary["regen_rate"] = 0.0
		summary["recovery_threshold"] = 0.0
		summary["safe_threshold"] = 0.0
		summary["breach_open"] = false
		summary["breach_sealed"] = false
		summary["passability_blocked"] = false
		summary["player_in_breach_zone"] = false
		summary["breach_zone_ids"] = []
		return summary
	summary = oxygen_state.get_summary()
	return summary

func get_breach_zone_node() -> Node:
	return breach_zone_node

func get_breach_zone_collision_enabled_count() -> int:
	if breach_zone_node == null:
		return 0
	for child in breach_zone_node.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return 1
	return 0

func is_player_in_breach_zone() -> bool:
	if breach_zone_node == null or player == null:
		return false
	if not (player is Node3D):
		return false
	var zone_pos: Vector3 = breach_zone_node.global_position
	var player_pos: Vector3 = (player as Node3D).global_position
	var dx: float = player_pos.x - zone_pos.x
	var dz: float = player_pos.z - zone_pos.z
	# Use a horizontal proximity radius (the corridor is wider than tall; using
	# 3D distance would falsely report "in zone" when the player is one floor up).
	return (dx * dx + dz * dz) <= (BREACH_ZONE_PROXIMITY_RADIUS * BREACH_ZONE_PROXIMITY_RADIUS)

func _activate_current_objective() -> void:
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if interactable.has_method("set_active"):
			interactable.set_active(int(interactable.get("sequence")) == current_objective_sequence)
	if tracker != null:
		tracker.set_current_sequence(current_objective_sequence)
		var progress: Dictionary = {}
		if objective_progress_state != null:
			progress = objective_progress_state.get_step_progress(current_objective_sequence)
		tracker.set_step_progress(current_objective_sequence, progress)
		var current = get_interactable_by_sequence(current_objective_sequence)
		if current != null:
			tracker.set_interaction_prompt(str(current.get("prompt_text")))

func _ensure_key_action_set(action_name: String, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var existing_keycodes: Dictionary = {}
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event: InputEventKey = event
			existing_keycodes[int(key_event.keycode)] = true
	for keycode_variant in keycodes:
		var keycode: int = int(keycode_variant)
		if existing_keycodes.has(keycode):
			continue
		var input_event: InputEventKey = InputEventKey.new()
		input_event.keycode = keycode
		InputMap.action_add_event(action_name, input_event)
		existing_keycodes[keycode] = true

# Returns the keycodes currently registered on an action, in InputMap
# registration order. Used by validation to assert the alternate-binding
# surface (A11Y-P1-002) without leaking any new public state onto the
# playable coordinator. Returns an empty array if the action does not
# exist or has no InputEventKey bindings.
func get_input_action_keycodes_for_validation(action_name: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action_name):
		return out
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event: InputEventKey = event
			out.append(int(key_event.keycode))
	return out

# --- Hazard / FireState integration -----------------------------------------
# Per the Gate 2 timed fire-zone feature spec, FireState cycles between
# CLEARED and BURNING on fixed durations, toggles the fire-zone collision
# segment, and updates a localized Label3D. The model is parallel to
# OxygenState and never reaches into the scene tree. The fire zone is on a
# side corridor (cargo_01 fallback, non-critical side room off the spine) and does NOT overlap the objective
# 3 -> 4 breach corridor. Fire is independent of oxygen, route control,
# objectives, and extraction; it does not deplete oxygen or any other
# resource and cannot be disabled by the player in Gate 2.

func _build_fire_zone() -> void:
	if fire_root == null:
		return
	for child in fire_root.get_children():
		fire_root.remove_child(child)
		child.queue_free()
	fire_zone_node = null
	fire_zone_label = null
	fire_zone_resolved_room_id = ""
	var resolution: Dictionary = _resolve_fire_zone_world_position()
	var world_position: Vector3 = resolution.get("position", Vector3.INF)
	fire_zone_resolved_room_id = str(resolution.get("room_id", ""))
	if fire_state == null:
		fire_state = FireStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary so
	# each hazard model unpacks the fields it cares about. FireState reads
	# burn_duration / clear_duration plus the zone_ids array.
	fire_state.configure({
		"zone_ids": [FIRE_ZONE_FALLBACK_ID],
		"burn_duration": FireStateScript.DEFAULT_BURN_DURATION,
		"clear_duration": FireStateScript.DEFAULT_CLEAR_DURATION,
	})
	fire_zone_node = _create_fire_zone_node(world_position)
	fire_root.add_child(fire_zone_node)
	fire_zone_label = _create_fire_zone_label(world_position)
	fire_root.add_child(fire_zone_label)

func _resolve_fire_zone_world_position() -> Dictionary:
	if loader != null and loader.has_method("get_fire_zone_markers"):
		var markers: Array = loader.get_fire_zone_markers()
		if markers.size() > 0 and markers[0] is Vector3:
			var candidate: Vector3 = markers[0]
			if candidate != Vector3.INF:
				return {
					"position": candidate,
					"room_id": _resolved_marker_room_id(),
				}
	# Fallback: side corridor room center (must not be the objective 3 -> 4 corridor).
	if loader != null and loader.has_method("get_room_center"):
		var room_center: Vector3 = loader.get_room_center(FIRE_ZONE_FALLBACK_ROOM_ID)
		if room_center != Vector3.INF:
			return {
				"position": room_center,
				"room_id": FIRE_ZONE_FALLBACK_ROOM_ID,
			}
	# Last-ditch: player spawn + offset. No room id is known in this branch.
	if player != null:
		return {
			"position": player.global_position + Vector3(6.0, 0.0, 0.0),
			"room_id": "",
		}
	return {
		"position": Vector3.ZERO,
		"room_id": "",
	}

# Returns the `to_room` of the first fire_zones marker the loader exposes, or
# "" if no marker is present. Used to attach a stable room id to the resolved
# fire zone world position so validation can confirm marker-to-resolved-room
# agreement without re-walking the loader's internal arrays.
func _resolved_marker_room_id() -> String:
	if loader == null or not (loader is Node):
		return ""
	var loader_node: Node = loader as Node
	if not loader_node.has_method("get_fire_zone_specs"):
		return ""
	var specs_variant: Variant = loader_node.call("get_fire_zone_specs")
	if typeof(specs_variant) != TYPE_ARRAY:
		return ""
	for spec_variant in (specs_variant as Array):
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var to_room: String = str((spec_variant as Dictionary).get("to_room", ""))
		if not to_room.is_empty():
			return to_room
	return ""

func _create_fire_zone_node(world_position: Vector3) -> StaticBody3D:
	var zone: StaticBody3D = StaticBody3D.new()
	zone.name = "FireZone_SideCorridor"
	zone.position = world_position
	zone.collision_layer = 1
	zone.collision_mask = 1
	zone.set_meta("fire_zone_id", FIRE_ZONE_FALLBACK_ID)
	zone.set_meta("fire_zone_kind", "timed_fire")
	zone.set_meta("fire_zone_phase", "CLEARED")
	zone.set_meta("fire_zone_passability_blocked", false)
	zone.set_meta("fire_zone_resolved_room_id", fire_zone_resolved_room_id)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "FireZoneCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = FIRE_ZONE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, FIRE_ZONE_COLLISION_SIZE.y * 0.5, 0.0)
	zone.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "FireZoneVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = FIRE_ZONE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_fire_zone_material(false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.add_child(visual)
	return zone

func _make_fire_zone_material(is_burning: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = FIRE_ZONE_VISUAL_COLOR_BURNING if is_burning else FIRE_ZONE_VISUAL_COLOR_CLEARED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _create_fire_zone_label(world_position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "FireZoneLabel"
	label.text = FIRE_ZONE_LABEL_TEXT_CLEARED
	label.position = world_position + Vector3(0.0, FIRE_ZONE_COLLISION_SIZE.y + 0.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	# A11Y-P1-001: world label pixel_size flows through the single
	# accessibility_settings seam. Default scale=1.0 keeps the prior
	# 0.0035 value exactly; larger scales divide the pixel_size so the
	# label renders larger on screen for the same world position.
	label.pixel_size = accessibility_settings.scaled_world_pixel_size(0.0035)
	label.modulate = FIRE_ZONE_VISUAL_COLOR_CLEARED
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	return label

func _refresh_fire_state(force_initial: bool) -> void:
	if fire_state == null or fire_zone_node == null:
		return
	_apply_fire_zone_scene_state()

func _apply_fire_zone_scene_state() -> void:
	if fire_state == null or fire_zone_node == null:
		return
	var summary: Dictionary = fire_state.get_summary()
	var burning: bool = bool(summary.get("burning", false))
	var state_text: String = str(summary.get("state", "CLEARED"))
	fire_zone_node.set_meta("fire_zone_phase", state_text)
	fire_zone_node.set_meta("fire_zone_passability_blocked", burning)
	_set_fire_zone_collision_enabled(fire_zone_node, burning)
	_update_fire_zone_visual(fire_zone_node, burning)
	if fire_zone_label != null:
		fire_zone_label.text = FIRE_ZONE_LABEL_TEXT_BURNING if burning else FIRE_ZONE_LABEL_TEXT_CLEARED
		fire_zone_label.modulate = FIRE_ZONE_VISUAL_COLOR_BURNING if burning else FIRE_ZONE_VISUAL_COLOR_CLEARED

func _set_fire_zone_collision_enabled(zone: Node, enabled: bool) -> void:
	for child in zone.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_fire_zone_visual(zone: Node, is_burning: bool) -> void:
	for child in zone.get_children():
		if child is MeshInstance3D and child.name == "FireZoneVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_fire_zone_material(is_burning)

func get_fire_summary() -> Dictionary:
	var summary: Dictionary = {}
	if fire_state == null:
		summary["state"] = "CLEARED"
		summary["phase"] = 0
		summary["time_in_state"] = 0.0
		summary["cycle_duration"] = 0.0
		summary["burning"] = false
		summary["passability_blocked"] = false
		summary["burn_duration"] = 0.0
		summary["clear_duration"] = 0.0
		summary["zone_ids"] = []
		return summary
	return fire_state.get_summary()

func get_fire_zone_node() -> Node:
	return fire_zone_node

func get_fire_zone_resolved_room_id() -> String:
	return fire_zone_resolved_room_id

func get_fire_zone_collision_enabled_count() -> int:
	if fire_zone_node == null:
		return 0
	for child in fire_zone_node.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return 1
	return 0

func teleport_player_to_fire_zone_for_validation() -> bool:
	if player == null or fire_zone_node == null:
		return false
	player.teleport_to(fire_zone_node.global_position)
	return true

# --- Hazard / ElectricalArcState integration ----------------------------------
# REQ-013: electrical-arc zone scene integration. Mirrors the
# FireState integration above; the third hazard's pure model
# (ElectricalArcState) ticks from _process and toggles a localized
# StaticBody3D / CollisionShape3D collision segment and a Label3D.
# Placement is template-specific (no fallback room id is injected), so
# when the loader reports an empty `arc_zone_specs` the scene simply
# skips arc setup and _refresh_arc_state becomes a no-op.

func _build_arc_zone() -> void:
	if arc_root == null:
		return
	for child in arc_root.get_children():
		arc_root.remove_child(child)
		child.queue_free()
	arc_zone_node = null
	arc_zone_label = null
	arc_zone_resolved_room_id = ""
	# Per ADR-0005: configure() is called even when no markers exist so
	# the model state is always coherent (DISCHARGED, time_in_state == 0.0,
	# passability_blocked == false). This is the FRESH state the smoke
	# asserts on the very first frame after ship load.
	if electrical_arc_state == null:
		electrical_arc_state = ElectricalArcStateScript.new()
	electrical_arc_state.configure({
		"zone_ids": [],
		"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
		"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
	})
	var resolution: Dictionary = _resolve_arc_zone_world_position()
	var world_position: Vector3 = resolution.get("position", Vector3.INF)
	arc_zone_resolved_room_id = str(resolution.get("room_id", ""))
	# No marker and no fallback -> skip arc setup. Refresh later will
	# stay a no-op because arc_zone_node / arc_zone_label are null.
	if world_position == Vector3.INF:
		return
	var zone_id: String = str(resolution.get("zone_id", ARC_ZONE_FALLBACK_ID))
	if zone_id.is_empty():
		zone_id = ARC_ZONE_FALLBACK_ID
	electrical_arc_state.configure({
		"zone_ids": [zone_id],
		"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
		"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
	})
	arc_zone_node = _create_arc_zone_node(zone_id, world_position)
	arc_root.add_child(arc_zone_node)
	arc_zone_label = _create_arc_zone_label(world_position)
	arc_root.add_child(arc_zone_label)

func _resolve_arc_zone_world_position() -> Dictionary:
	if loader != null and loader.has_method("get_arc_zone_markers"):
		var markers: Array = loader.call("get_arc_zone_markers")
		if markers.size() > 0 and markers[0] is Vector3:
			var candidate: Vector3 = markers[0]
			if candidate != Vector3.INF:
				return {
					"position": candidate,
					"room_id": _resolved_arc_marker_room_id(),
					"zone_id": _resolved_arc_marker_zone_id(),
				}
	# No fallback room is injected per hazard_type_3.md (placement is
	# template-specific). An empty arc_zones array means the template
	# does not include this hazard; skip arc setup cleanly.
	return {"position": Vector3.INF, "room_id": "", "zone_id": ""}

# Returns the `to_room` of the first arc_zones marker the loader exposes,
# or "" if no marker is present. Mirrors _resolved_marker_room_id() for
# fire zones so the validation smoke can confirm marker-to-resolved-room
# agreement without re-walking the loader's internal arrays.
func _resolved_arc_marker_room_id() -> String:
	if loader == null or not (loader is Node):
		return ""
	var loader_node: Node = loader as Node
	if not loader_node.has_method("get_arc_zone_specs"):
		return ""
	var specs_variant: Variant = loader_node.call("get_arc_zone_specs")
	if typeof(specs_variant) != TYPE_ARRAY:
		return ""
	for spec_variant in (specs_variant as Array):
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var to_room: String = str((spec_variant as Dictionary).get("to_room", ""))
		if not to_room.is_empty():
			return to_room
	return ""

func _resolved_arc_marker_zone_id() -> String:
	if loader == null or not (loader is Node):
		return ""
	var loader_node: Node = loader as Node
	if not loader_node.has_method("get_arc_zone_specs"):
		return ""
	var specs_variant: Variant = loader_node.call("get_arc_zone_specs")
	if typeof(specs_variant) != TYPE_ARRAY:
		return ""
	for spec_variant in (specs_variant as Array):
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var zone_id: String = str((spec_variant as Dictionary).get("id", ""))
		if not zone_id.is_empty():
			return zone_id
	return ""

func _create_arc_zone_node(zone_id: String, world_position: Vector3) -> StaticBody3D:
	var zone: StaticBody3D = StaticBody3D.new()
	zone.name = "ElectricalArcZone_NonCriticalLink"
	zone.position = world_position
	zone.collision_layer = 1
	zone.collision_mask = 1
	zone.set_meta("arc_zone_id", zone_id)
	zone.set_meta("arc_zone_kind", "electrical_arc")
	zone.set_meta("arc_zone_phase", "DISCHARGED")
	zone.set_meta("arc_zone_passability_blocked", false)
	zone.set_meta("arc_zone_resolved_room_id", arc_zone_resolved_room_id)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "ArcZoneCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = ARC_ZONE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, ARC_ZONE_COLLISION_SIZE.y * 0.5, 0.0)
	# The arc zone starts DISCHARGED -> passable. Collision is enabled
	# by _apply_arc_zone_scene_state when the model flips to ARCING.
	collision_shape.disabled = true
	zone.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "ArcZoneVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = ARC_ZONE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_arc_zone_material(false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.add_child(visual)
	return zone

func _make_arc_zone_material(is_arcing: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = ARC_ZONE_VISUAL_COLOR_ARCING if is_arcing else ARC_ZONE_VISUAL_COLOR_DISCHARGED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _create_arc_zone_label(world_position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "ArcZoneLabel"
	label.text = ARC_ZONE_LABEL_TEXT_DISCHARGED
	label.position = world_position + Vector3(0.0, ARC_ZONE_COLLISION_SIZE.y + 0.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	# A11Y-P1-001: world label pixel_size flows through the single
	# accessibility_settings seam. Default scale=1.0 keeps the prior
	# 0.0035 value exactly; larger scales divide the pixel_size so the
	# label renders larger on screen for the same world position.
	label.pixel_size = accessibility_settings.scaled_world_pixel_size(0.0035)
	label.modulate = ARC_ZONE_VISUAL_COLOR_DISCHARGED
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	return label

func _refresh_arc_state(force_initial: bool) -> void:
	if electrical_arc_state == null:
		return
	# When no arc zone was built (template has no arc marker), keep the
	# model in DISCHARGED so its summary remains coherent for save/load
	# but skip scene-state application entirely.
	if arc_zone_node == null:
		return
	_apply_arc_zone_scene_state()

func _apply_arc_zone_scene_state() -> void:
	if electrical_arc_state == null or arc_zone_node == null:
		return
	var summary: Dictionary = electrical_arc_state.get_summary()
	var arcing: bool = bool(summary.get("arcing", false))
	var state_text: String = str(summary.get("state", "DISCHARGED"))
	arc_zone_node.set_meta("arc_zone_phase", state_text)
	arc_zone_node.set_meta("arc_zone_passability_blocked", arcing)
	_set_arc_zone_collision_enabled(arc_zone_node, arcing)
	_update_arc_zone_visual(arc_zone_node, arcing)
	if arc_zone_label != null:
		arc_zone_label.text = ARC_ZONE_LABEL_TEXT_ARCING if arcing else ARC_ZONE_LABEL_TEXT_DISCHARGED
		arc_zone_label.modulate = ARC_ZONE_VISUAL_COLOR_ARCING if arcing else ARC_ZONE_VISUAL_COLOR_DISCHARGED

func _set_arc_zone_collision_enabled(zone: Node, enabled: bool) -> void:
	for child in zone.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_arc_zone_visual(zone: Node, is_arcing: bool) -> void:
	for child in zone.get_children():
		if child is MeshInstance3D and child.name == "ArcZoneVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_arc_zone_material(is_arcing)

func get_arc_summary() -> Dictionary:
	var summary: Dictionary = {}
	if electrical_arc_state == null:
		summary["hazard_kind"] = "electrical_arc"
		summary["state"] = "DISCHARGED"
		summary["phase"] = 0
		summary["time_in_state"] = 0.0
		summary["cycle_duration"] = 0.0
		summary["arcing"] = false
		summary["passability_blocked"] = false
		summary["arcing_duration"] = 0.0
		summary["discharged_duration"] = 0.0
		summary["zone_ids"] = []
		return summary
	return electrical_arc_state.get_summary()

func get_arc_zone_node() -> Node:
	return arc_zone_node

func get_arc_zone_resolved_room_id() -> String:
	return arc_zone_resolved_room_id

func get_arc_zone_collision_enabled_count() -> int:
	if arc_zone_node == null:
		return 0
	for child in arc_zone_node.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return 1
	return 0

func teleport_player_to_arc_zone_for_validation() -> bool:
	if player == null or arc_zone_node == null:
		return false
	player.teleport_to(arc_zone_node.global_position)
	return true

# --- Inventory / Tool pickup integration -------------------------------------
# REQ-007: a single ToolPickup carrying the portable_oxygen_pump lives in a
# fixed side room (tool_storage_01 if the loader defines it, otherwise a
# fallback position near the player start). Acquiring the pickup adds the
# tool id to InventoryState exactly once; OxygenState reads the inventory
# summary each frame to halve the drain rate inside an unsealed breach.

func _build_tool_pickup() -> void:
	if tool_pickup_root == null:
		return
	for child in tool_pickup_root.get_children():
		tool_pickup_root.remove_child(child)
		child.queue_free()
	tool_pickup = null
	var world_position: Vector3 = _resolve_tool_pickup_world_position()
	tool_pickup = ToolPickupScript.new()
	tool_pickup.configure("portable_oxygen_pump", inventory_state, world_position, TOOL_PICKUP_INTERACTION_RADIUS)
	if not tool_pickup.tool_acquired.is_connected(_on_tool_pickup_acquired):
		tool_pickup.tool_acquired.connect(_on_tool_pickup_acquired)
	tool_pickup_root.add_child(tool_pickup)

func _resolve_tool_pickup_world_position() -> Vector3:
	if loader != null and loader.has_method("get_room_center"):
		var room_center: Vector3 = loader.get_room_center("tool_storage_01")
		if room_center != Vector3.INF:
			return room_center + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	# Fallback: near player start (no tool_storage_01 in the Gate 2 fixture).
	if player != null:
		return player.global_position + TOOL_PICKUP_FALLBACK_OFFSET
	if loader != null:
		return loader.get_start_transform().origin + TOOL_PICKUP_FALLBACK_OFFSET + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	return TOOL_PICKUP_FALLBACK_OFFSET

func _on_tool_pickup_acquired(p_tool_id: String) -> void:
	_refresh_tracker_system_status_lines()
	print("PLAYABLE TOOL ACQUIRED tool_id=%s" % p_tool_id)

# --- REQ-014: junction_calibrator pickup -------------------------------------
# A second ToolPickup configured with tool_id = "junction_calibrator".
# Acquiring the pickup adds the id to InventoryState exactly once; the
# next interaction with a repair_junction sequence consumes it via
# _consume_junction_calibrator_if_eligible. The acquisition signal is
# the same shared ToolPickup.tool_acquired; _on_tool_pickup_acquired
# handles the HUD refresh / log line for both pickups.

func _build_junction_calibrator_pickup() -> void:
	if tool_pickup_root == null:
		return
	# Keep only the junction_calibrator pickup in scope for this build.
	# The REQ-007 oxygen pump child stays in the tree; we just create a
	# sibling ToolPickup under the same tool_pickup_root.
	var world_position: Vector3 = _resolve_junction_calibrator_world_position()
	junction_calibrator_pickup = ToolPickupScript.new()
	junction_calibrator_pickup.configure(
		"junction_calibrator",
		inventory_state,
		world_position,
		JUNCTION_CALIBRATOR_INTERACTION_RADIUS
	)
	if not junction_calibrator_pickup.tool_acquired.is_connected(_on_tool_pickup_acquired):
		junction_calibrator_pickup.tool_acquired.connect(_on_tool_pickup_acquired)
	tool_pickup_root.add_child(junction_calibrator_pickup)

func _resolve_junction_calibrator_world_position() -> Vector3:
	if loader != null and loader.has_method("get_room_center"):
		var room_center: Vector3 = loader.get_room_center(JUNCTION_CALIBRATOR_FALLBACK_ROOM_ID)
		if room_center != Vector3.INF:
			return room_center + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	# Fallback: opposite side of the player spawn from the oxygen pump so
	# the two pickups do not collide in space.
	if player != null:
		return player.global_position + JUNCTION_CALIBRATOR_FALLBACK_OFFSET
	if loader != null:
		return loader.get_start_transform().origin + JUNCTION_CALIBRATOR_FALLBACK_OFFSET + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	return JUNCTION_CALIBRATOR_FALLBACK_OFFSET

## REQ-014: hide the junction_calibrator pickup marker after a reload
## when the restored state already represents a carried or spent
## calibrator. `_build_junction_calibrator_pickup` always creates a
## fresh ToolPickup with its marker visible; the only live code path
## that hides the marker is `_consume_junction_calibrator_if_eligible`,
## which the reload cannot reach because the snapshot is applied AFTER
## the pickup is built. The reload path therefore needs its own
## reconciliation step, driven by the same two model summaries the
## pickup's runtime visibility depends on.
func _reconcile_junction_calibrator_marker_after_reload() -> void:
	if junction_calibrator_pickup == null:
		return
	var carried: bool = inventory_state != null and inventory_state.has_tool("junction_calibrator")
	var spent: bool = false
	if objective_progress_state != null:
		for sequence_variant in objective_progress_state.get_summary().keys():
			var seq: int = int(sequence_variant)
			if seq <= 0:
				continue
			if objective_progress_state.has_calibrator_applied(seq):
				spent = true
				break
	if carried or spent:
		junction_calibrator_pickup.set_marker_visible(false)
	_refresh_tracker_system_status_lines()

## REQ-014: consume a carried junction_calibrator against the given
## sequence iff the sequence is registered as `kind == "repair_junction"`
## in the loader specs. On a successful application the calibrator is
## removed from inventory and the HUD status line is refreshed.
## Called at the start of `_on_interactable_completed` so the reduced
## required_steps is in force before `complete_step` runs in the same
## interaction frame.
func _consume_junction_calibrator_if_eligible(sequence: int) -> void:
	if sequence <= 0:
		return
	if inventory_state == null or objective_progress_state == null:
		return
	if str(sequence_kinds.get(sequence, "single")) != "repair_junction":
		return
	if not inventory_state.has_tool("junction_calibrator"):
		return
	if not objective_progress_state.apply_junction_calibrator(sequence):
		# One-step junction or already-applied or already-complete: do
		# NOT remove the calibrator. The spec's "minimum one step"
		# contract is the model's responsibility; we trust its return.
		return
	if not inventory_state.remove_tool("junction_calibrator"):
		# Defensive: roll the model back so the calibrator is not
		# silently spent while still in inventory. The model's apply
		# method leaves no public rollback, so we re-apply the prior
		# step count from a fresh get_step_progress and reset the
		# calibrator_applied flag through a tiny inverse. We prefer to
		# fail loudly here rather than desync inventory vs. model.
		var before: Dictionary = objective_progress_state.get_step_progress(sequence)
		var after: Dictionary = before.duplicate()
		after["required_steps"] = int(before.get("required_steps", 1)) + 1
		after["calibrator_applied"] = false
		# Re-store via apply_summary round-trip on a single-sequence
		# summary to avoid poking at the model's internals.
		objective_progress_state.apply_summary({
			sequence: {
				"objective_type": str(after.get("objective_type", "")),
				"required_steps": int(after.get("required_steps", 1)),
				"completed_steps": int(before.get("completed_steps", 0)),
				"completed_step_ids": (before.get("completed_step_ids", []) as Array).duplicate(),
				"complete": bool(before.get("complete", false)),
				"calibrator_applied": false,
			}
		})
		push_warning("PlayableGeneratedShip: junction_calibrator consumed by model but not removed from inventory; rolled back")
	# Hide the pickup marker if it is still visible (the pickup is one-
	# shot per slice run regardless of the order of consume vs pickup).
	if junction_calibrator_pickup != null:
		junction_calibrator_pickup.set_marker_visible(false)
	_refresh_tracker_system_status_lines()
	var progress: Dictionary = objective_progress_state.get_step_progress(sequence)
	print("JUNCTION CALIBRATOR APPLIED sequence=%d required_steps=%d completed_steps=%d" % [
		sequence,
		int(progress.get("required_steps", 1)),
		int(progress.get("completed_steps", 0)),
	])

# --- Headless validation seams ------------------------------------------------

func get_inventory_summary() -> Dictionary:
	if inventory_state == null:
		return { "tool_ids": [], "active_effects": [] }
	return inventory_state.get_summary()

func get_tool_pickup_node() -> Node:
	return tool_pickup

## REQ-014: returns the second ToolPickup (junction_calibrator), or null
## before _build_junction_calibrator_pickup has run.
func get_junction_calibrator_pickup_node() -> Node:
	return junction_calibrator_pickup

## REQ-014: teleports the player to the junction_calibrator pickup so
## the main-scene smoke can drive the acquisition through the real
## PlayerController.request_interact() path.
func teleport_player_to_junction_calibrator_for_validation() -> bool:
	if player == null or junction_calibrator_pickup == null:
		return false
	player.teleport_to(junction_calibrator_pickup.global_position)
	return true

## REQ-014: drives the same ToolPickup.try_interact path as a real
## player press, returning true only when the inventory model now
## contains the calibrator. Mirrors acquire_tool_for_validation but
## for the second pickup; intentionally does not duplicate the oxygen-
## pump helper so each pickup keeps a single canonical acquisition seam.
func acquire_junction_calibrator_for_validation() -> bool:
	if junction_calibrator_pickup == null or inventory_state == null:
		return false
	if junction_calibrator_pickup.tool_id != "junction_calibrator":
		return false
	if not teleport_player_to_junction_calibrator_for_validation():
		return false
	junction_calibrator_pickup.set_validation_player_in_range(player)
	player.request_interact()
	return inventory_state.has_tool("junction_calibrator")

## REQ-014: validation seam for the main-scene smoke. Equivalent to
## the coordinator's auto-consume path but invoked directly so the
## smoke can assert required_steps=2 (etc.) without running the full
## interactable complete handshake a second time.
func apply_junction_calibrator_for_validation(sequence: int) -> bool:
	if sequence <= 0:
		return false
	_consume_junction_calibrator_if_eligible(sequence)
	return true

## REQ-014: validation seam for the main-scene smoke. Registers a
## `repair_junction`-kind sequence in the objective_progress_state with
## the given required_steps and caches the kind in sequence_kinds so
## the smoke can drive `_consume_junction_calibrator_if_eligible`
## end-to-end without depending on the seed template's exact step
## count. The seed template's sequence 2 is a 2-step junction; REQ-014
## acceptance criteria require a 3-step reduction target so the main-
## scene smoke registers its own synthetic sequence here and asserts
## `required_steps=2` after the calibrator is applied.
func register_junction_sequence_for_validation(sequence: int, required_steps: int) -> bool:
	if sequence <= 0 or required_steps < 1:
		return false
	if objective_progress_state == null:
		return false
	sequence_kinds[sequence] = "repair_junction"
	# Reset the existing record first so the smoke gets a clean state
	# even if a same-numbered sequence was loaded from the template.
	objective_progress_state.reset()
	for spec_variant in loader.get_objective_specs_copy():
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var spec_sequence: int = int(spec.get("sequence", 0))
		var spec_kind: String = str(spec.get("kind", "single"))
		sequence_kinds[spec_sequence] = spec_kind
		var spec_steps: Array = []
		var spec_steps_variant: Variant = spec.get("steps", [])
		if typeof(spec_steps_variant) == TYPE_ARRAY:
			spec_steps = spec_steps_variant
		if spec_kind == "repair_junction" and spec_steps.size() > 1:
			objective_progress_state.register_objective(spec_sequence, str(spec.get("type", "unknown")), spec_steps.size())
	# Then layer the smoke's synthetic junction on top. If the smoke
	# re-uses a real sequence number from the template, this registration
	# overwrites the prior record; that is acceptable because the smoke
	# will not complete that real sequence afterward.
	objective_progress_state.register_objective(sequence, "repair_junction", required_steps)
	return true

func teleport_player_to_tool_pickup_for_validation() -> bool:
	if player == null or tool_pickup == null:
		return false
	player.teleport_to(tool_pickup.global_position)
	return true

func acquire_tool_for_validation(p_tool_id: String) -> bool:
	if tool_pickup == null or inventory_state == null:
		return false
	if tool_pickup.tool_id != p_tool_id:
		return false
	if not teleport_player_to_tool_pickup_for_validation():
		return false
	tool_pickup.set_validation_player_in_range(player)
	player.request_interact()
	return inventory_state.has_tool(p_tool_id)

# --- REQ-012 current-run save/load -------------------------------------------
# Per ADR-0007, only current-run state is serialized. The hub ship, derelict
# selection, meta-currency, unlocks, faction/narrative progress, and
# cross-run bookkeeping are explicitly excluded. Adding a new field to
# RunSnapshot requires a new ADR.

## Captures a fresh RunSnapshot from the current runtime state. Returns
## null if the slice is not started or any required model is missing.
func _build_run_snapshot() -> RunSnapshot:
	if not playable_started or slice_complete:
		return null
	if save_load_service == null:
		return null
	var snapshot := RunSnapshotScript.new()
	snapshot.layout_path = layout_path
	snapshot.kit_path = kit_path
	snapshot.gameplay_slice_path = gameplay_slice_path
	if player != null and player is Node3D:
		var pos: Vector3 = (player as Node3D).global_position
		snapshot.player_position = [pos.x, pos.y, pos.z]
	snapshot.current_objective_sequence = current_objective_sequence
	if ship_systems_manager != null:
		snapshot.ship_systems_summary = ship_systems_manager.get_summary()
		# Persist only the authoritative objective record; flag-shaped fields
		# (main_power_restored, emergency_supplies_recovered, ...) are derived
		# live from manager health + this record via _manager_compat_summary(),
		# never stored (ADR-0009).
		snapshot.ship_systems_summary["completed_objective_types"] = completed_objective_types.keys()
	if route_control_state != null:
		snapshot.route_control_summary = get_route_control_summary()
	if oxygen_state != null:
		snapshot.oxygen_summary = get_oxygen_summary()
	if inventory_state != null:
		snapshot.inventory_summary = inventory_state.get_summary()
	if fire_state != null:
		snapshot.fire_summary = fire_state.get_summary()
	if electrical_arc_state != null:
		snapshot.electrical_arc_summary = electrical_arc_state.get_summary()
	if objective_progress_state != null:
		snapshot.objective_progress_summary = objective_progress_state.get_summary()
	if player_progression != null:
		snapshot.player_progression_summary = player_progression.get_summary()
	snapshot.slice_version = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	snapshot.godot_version = Engine.get_version_info()["string"]
	snapshot.saved_at = Time.get_datetime_string_from_system(true)
	return snapshot

## Writes the whole world to the single save slot. Routed through the
## world-save format (ADR-0012) so every write to user://saves/current_run.json
## — auto-save here AND manual request_save — is a WorldSnapshot. Otherwise an
## auto-save on objective completion would overwrite a manual F5 world-save with
## a RunSnapshot and fail the version gate on the next load. The in-memory
## RunSnapshot seam (last_saved_snapshot / get_last_saved_snapshot) is preserved
## because the auto-save regression smokes assert its current_objective_sequence.
func _auto_save_current_run() -> bool:
	if save_load_service == null or slice_complete:
		return false
	var ws = _build_world_snapshot()
	if ws == null:
		return false
	if save_load_service.save_world(ws):
		last_saved_snapshot = _build_run_snapshot()  # preserve in-memory RunSnapshot seam (get_last_saved_snapshot)
		return true
	return false

## Manual save trigger (F5 / save_run input). Saves the whole world, so saving is
## allowed anywhere — including aboard a traveled derelict (save-anywhere; ADR-0012
## supersedes the Phase 4.5 away-save rejection). Refuses only before the slice has
## started or after it has completed.
func request_save() -> bool:
	if not playable_started or slice_complete:
		return false
	if save_load_service == null:
		return false
	var ws = _build_world_snapshot()
	if ws == null:
		return false
	var result: bool = save_load_service.save_world(ws)
	if result:
		print("PLAYABLE SHIP SAVED location=%s sequence=%d" % [ws.current_location, current_objective_sequence])
	return result

## Validation / public seam: the SaveLoadService instance. Returns null
## before _build_runtime_nodes() has run.
func get_save_load_service() -> SaveLoadService:
	return save_load_service

## Validation / public seam: the most recent successful snapshot. Null
## until the first request_save() (or auto-save) has completed.
func get_last_saved_snapshot() -> RunSnapshot:
	return last_saved_snapshot

## Validation / public seam: true if a save file currently exists on
## disk (regardless of version compatibility).
func is_load_available() -> bool:
	if save_load_service == null:
		return false
	return save_load_service.has_save()

## Manual load trigger (F9 / load_run input). Loads the whole world and applies it
## (home ship + visited-ship registry + active location + in-ship position).
func request_load() -> bool:
	if save_load_service == null:
		return false
	var ws = save_load_service.load_world()
	if ws == null:
		push_warning("PlayableGeneratedShip: no compatible world save to load")
		return false
	return _apply_world_snapshot(ws)

## Reconstructs the slice through the normal load path, then applies
## the saved model summaries. Designed to be called from a fully
## bootstrapped coordinator (e.g. during a manual F9 load). Returns
## true on success.
func _apply_run_snapshot(snapshot: RunSnapshot) -> bool:
	if snapshot == null or not playable_started:
		return false
	# Reset the live slice to a fresh state. _ready() will be re-driven
	# by resetting the loader and asking it to reload from the saved
	# paths synchronously.
	_is_reloading = true
	_reset_runtime_for_reload()
	layout_path = snapshot.layout_path
	kit_path = snapshot.kit_path
	gameplay_slice_path = snapshot.gameplay_slice_path
	# The loader is sync; ship_loaded fires on the same call stack, but
	# we guard _on_ship_loaded with a reload-aware flag so the first
	# _on_ship_loaded after a reload does NOT mark playable_started
	# prematurely (it must re-emit).
	playable_started = false
	loader.load_from_paths(layout_path, kit_path, gameplay_slice_path)
	if not playable_started:
		# Loader must have failed; _on_ship_loaded bailed out.
		_is_reloading = false
		push_error("PlayableGeneratedShip: load failed because slice did not start")
		return false
	# Apply the saved model state to the freshly-built slice.
	if ship_systems_manager != null and not snapshot.ship_systems_summary.is_empty():
		ship_systems_manager.apply_summary(snapshot.ship_systems_summary)
		completed_objective_types.clear()
		for t in snapshot.ship_systems_summary.get("completed_objective_types", []):
			completed_objective_types[str(t)] = true
		objective_completion_count = max(0, snapshot.current_objective_sequence - 1)
		# Re-apply scene consequences for every completed objective. The reload
		# rebuilds affordances visible (via _build_slice_affordance_labels), so a
		# completed restore_systems must re-clear the blocked-biomatter props or
		# they reappear after loading (PR #2 review finding). The handler is a
		# no-op for objective types without scene consequences, so iterating all
		# completed types is safe and future-proof.
		for completed_type in completed_objective_types:
			_apply_ship_systems_consequences(str(completed_type))
		_refresh_route_control_from_ship_systems()
		if oxygen_state != null:
			oxygen_state.apply_ship_systems_summary(_manager_compat_summary())
	if route_control_state != null and not snapshot.route_control_summary.is_empty():
		route_control_state.apply_summary(snapshot.route_control_summary)
		_apply_route_gate_scene_state()
	if oxygen_state != null and not snapshot.oxygen_summary.is_empty():
		oxygen_state.apply_summary(snapshot.oxygen_summary)
		_refresh_oxygen_state(true, 0.0)
	if inventory_state != null and not snapshot.inventory_summary.is_empty():
		inventory_state.apply_summary(snapshot.inventory_summary)
	if fire_state != null and not snapshot.fire_summary.is_empty():
		fire_state.apply_summary(snapshot.fire_summary)
		_refresh_fire_state(true)
	# REQ-013: restore the electrical-arc summary alongside fire. The
	# model's apply_summary rejects summaries whose hazard_kind does
	# not match, so an older snapshot written before REQ-013 lands is
	# silently ignored instead of corrupting the live state.
	if electrical_arc_state != null and not snapshot.electrical_arc_summary.is_empty():
		electrical_arc_state.apply_summary(snapshot.electrical_arc_summary)
		_refresh_arc_state(true)
	if objective_progress_state != null and not snapshot.objective_progress_summary.is_empty():
		objective_progress_state.apply_summary(snapshot.objective_progress_summary)
	if player_progression != null and not snapshot.player_progression_summary.is_empty():
		player_progression.apply_summary(snapshot.player_progression_summary)
	# REQ-014: reconcile the junction_calibrator pickup marker visibility
	# with the restored inventory + objective_progress summaries. The
	# marker is rebuilt visible by `_build_junction_calibrator_pickup`,
	# but a loaded save may have already carried or consumed the tool.
	# Without this, the reload path resurrects the pickup marker even
	# though the calibrator is in the carried inventory (or already spent),
	# which lets the reviewer probe re-acquire the calibrator after load.
	_reconcile_junction_calibrator_marker_after_reload()
	# Restore the saved objective sequence AFTER all model state has
	# been applied so the subsequent _activate_current_objective() call
	# sees the right state.
	current_objective_sequence = max(1, snapshot.current_objective_sequence)
	_activate_current_objective()
	# Teleport the player to the saved position last so any spawn-side
	# effects (e.g. hazard proximity) do not overwrite the snapshot.
	if player != null and player is Node3D and snapshot.player_position.size() >= 3:
		(player as Node3D).global_position = Vector3(
			snapshot.player_position[0],
			snapshot.player_position[1],
			snapshot.player_position[2],
		)
	last_saved_snapshot = snapshot
	_is_reloading = false
	print("PLAYABLE SHIP LOADED sequence=%d position=(%.2f,%.2f,%.2f)" % [
		current_objective_sequence,
		snapshot.player_position[0],
		snapshot.player_position[1],
		snapshot.player_position[2],
	])
	return true

## Builds a full WorldSnapshot from live state. The home-ship slice is the
## existing RunSnapshot; when the player is aboard a derelict the home slice's
## player_position is overridden with the position they left home from (the live
## player position belongs to the derelict and is stored separately). Each
## retained ShipInstance contributes its own slice; current_location names the
## active ship.
func _build_world_snapshot():
	var ws = WorldSnapshotScript.new()
	if sargasso_world != null:
		ws.world_summary = sargasso_world.get_summary()
	var home_snap = _build_run_snapshot()
	if home_snap != null:
		if away_from_start:
			home_snap.player_position = [_home_player_position.x, _home_player_position.y, _home_player_position.z]
		ws.home_ship = home_snap.to_dict()
	ws.visited_ships = {}
	for mid in visited_ships:
		ws.visited_ships[String(mid)] = visited_ships[mid].get_summary()
	ws.current_location = String(current_ship.marker_id) if current_ship != null else ""
	if player != null and player is Node3D:
		var p: Vector3 = (player as Node3D).global_position
		ws.player_position_in_ship = [p.x, p.y, p.z]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = Time.get_datetime_string_from_system(true)
	return ws

## Regenerates a derelict's geometry from its retained blueprint, makes it the
## active ship (re-applying its persisted systems state is implicit — the
## ShipInstance already holds it), and re-homes the player at pos_in_ship.
func _activate_derelict_from_instance(inst, pos_in_ship: Array) -> bool:
	if inst == null or ship_generator == null:
		return false
	var new_root: Node3D = ship_generator.generate(inst.blueprint)
	if new_root == null:
		return false
	_attach_derelict_active(inst, new_root)
	if player != null and player is Node3D and pos_in_ship.size() >= 3:
		(player as Node3D).global_position = Vector3(float(pos_in_ship[0]), float(pos_in_ship[1]), float(pos_in_ship[2]))
	return true

## Applies a WorldSnapshot: rebuilds the home ship first (this resets the runtime
## and returns to home if currently away), restores the SargassoWorld and the
## visited-ships registry, then re-activates the saved derelict if the snapshot
## was taken aboard one. Returns false on any hard failure.
func _apply_world_snapshot(ws) -> bool:
	if ws == null:
		return false
	# 1. Home ship via the existing single-ship reload path. Reconstruct a
	#    RunSnapshot object from the embedded dict (version-gated like a disk load).
	var home_snap = RunSnapshotScript.from_dict(ws.home_ship, SaveLoadServiceScript.CURRENT_SLICE_VERSION, Engine.get_version_info()["string"])
	if home_snap == null:
		push_warning("PlayableGeneratedShip: world load rejected — embedded home slice incompatible")
		return false
	# Restore the home-departure position. On an away-save the home slice's
	# player_position holds where the player left home from (see _build_world_snapshot);
	# without copying it back, a later travel_home() after a fresh process would
	# teleport the player to the origin instead of their saved home position.
	if home_snap.player_position.size() >= 3:
		_home_player_position = Vector3(home_snap.player_position[0], home_snap.player_position[1], home_snap.player_position[2])
	if not _apply_run_snapshot(home_snap):
		return false
	# 2. World model. _apply_run_snapshot reset us to the home ship; home_ship is
	#    re-wrapped by _on_ship_loaded during that reload.
	if sargasso_world != null and not ws.world_summary.is_empty():
		sargasso_world.apply_summary(ws.world_summary)
	# 3. Rebuild the retained-derelict registry from the slices.
	visited_ships.clear()
	for mid in ws.visited_ships:
		var inst = ShipInstanceScript.create("", "", ShipBlueprintScript.new(), null, null)
		if inst.apply_summary(ws.visited_ships[mid]):
			visited_ships[String(mid)] = inst
	# 4. If saved aboard a derelict, re-activate it.
	if String(ws.current_location) != "":
		var active = visited_ships.get(String(ws.current_location), null)
		if active == null:
			push_warning("PlayableGeneratedShip: world load — current_location '%s' missing from visited_ships" % String(ws.current_location))
			return true  # home is already correctly restored; treat as on-home
		if not _activate_derelict_from_instance(active, ws.player_position_in_ship):
			push_warning("PlayableGeneratedShip: world load — failed to re-activate derelict '%s'" % String(ws.current_location))
			return true
	return true

## Tear down every runtime child so a fresh load can rebuild the slice
## cleanly. Mirrors the setup done by _build_runtime_nodes() and the
## various _build_*_zone helpers, but in reverse.
func _reset_runtime_for_reload() -> void:
	# REQ-012 fix: if the player is aboard a traveled derelict when a reload is
	# triggered, we must return to the starting ship BEFORE rebuilding the slice.
	# Without this block:
	#   - away_from_start stays true → _process returns forever (sim wedged)
	#   - current_ship still points at the stale derelict → _on_ship_loaded's
	#     `if current_ship == null` guard is false → the reloaded starting ship
	#     is never wrapped as current_ship
	#   - the derelict root remains a child of this coordinator → leaked scene
	#   - loader is still off-tree → load_from_paths rebuilds into an off-tree
	#     loader, and the reloaded slice is never in the scene
	# Fix: free the stateless derelict root, re-attach the detached start loader
	# (so the subsequent load_from_paths builds in-tree), clear away_from_start,
	# and null current_ship so _on_ship_loaded re-wraps the freshly-reloaded
	# starting ship.
	if away_from_start:
		if current_ship != null and String(current_ship.marker_id) != "":
			var derelict_root = current_ship.scene_root
			if derelict_root != null and is_instance_valid(derelict_root):
				if derelict_root.get_parent() == self:
					remove_child(derelict_root)
				# queue_free is the safe choice for a Node3D tree that may own
				# physics bodies / navigation agents: it defers destruction to the
				# end of the current frame so the engine can cleanly unregister
				# those resources. The smoke asserts detachment (get_parent() !=
				# playable), not immediate invalidation, so this is correct.
				derelict_root.queue_free()
		# The start loader was detached by travel_to (remove_child) but kept alive.
		# Re-attach it so the subsequent load_from_paths() rebuilds the starting
		# ship in-tree and _on_ship_loaded fires with the coordinator as parent.
		var loader_node: Node = loader as Node
		if loader_node != null and is_instance_valid(loader_node) and loader_node.get_parent() == null:
			add_child(loader_node)
		_reattach_starting_gameplay_roots()
		away_from_start = false
		current_ship = null  # allow _on_ship_loaded to re-wrap the starting ship
		# Sub-project #2 (I1): free the prior derelict's objective interactables on
		# reload. _build_derelict_objectives (the only other caller of
		# _clear_derelict_objectives) does not run on a reload-into-home path
		# (_apply_world_snapshot skips re-activation when current_location == ""),
		# so without this the Area3D interactables stay orphaned under
		# derelict_objective_root, overlaying the home ship. Harmless on the
		# reload-into-derelict path (_build_derelict_objectives re-clears anyway).
		_clear_derelict_objectives()
		_clear_loot_containers()
		_clear_repair_points()
	# Player first so the camera unfollows before the rig is freed.
	if player != null and is_instance_valid(player):
		player.queue_free()
		player = null
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.queue_free()
		camera_rig = null
	if interaction_root != null and is_instance_valid(interaction_root):
		for child in interaction_root.get_children():
			interaction_root.remove_child(child)
			child.queue_free()
	if affordance_root != null and is_instance_valid(affordance_root):
		for child in affordance_root.get_children():
			affordance_root.remove_child(child)
			child.queue_free()
	if route_control_root != null and is_instance_valid(route_control_root):
		for child in route_control_root.get_children():
			route_control_root.remove_child(child)
			child.queue_free()
	if oxygen_root != null and is_instance_valid(oxygen_root):
		for child in oxygen_root.get_children():
			oxygen_root.remove_child(child)
			child.queue_free()
	if tool_pickup_root != null and is_instance_valid(tool_pickup_root):
		for child in tool_pickup_root.get_children():
			tool_pickup_root.remove_child(child)
			child.queue_free()
	if fire_root != null and is_instance_valid(fire_root):
		for child in fire_root.get_children():
			fire_root.remove_child(child)
			child.queue_free()
	if arc_root != null and is_instance_valid(arc_root):
		for child in arc_root.get_children():
			arc_root.remove_child(child)
			child.queue_free()
	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.queue_free()
	# REQ-014 blocking finding B: null the hud_layer and tracker
	# references so a subsequent _build_hud_layer() rebuild starts from
	# a clean slate. Without nulling tracker, _build_hud_layer would
	# overwrite the field but the old tracker Node would still be
	# parented to a freed CanvasLayer; without nulling hud_layer, the
	# helper's idempotent guard would re-free the same node twice.
	hud_layer = null
	tracker = null
	scanner_panel = null
	interactables.clear()
	sequence_interactables.clear()
	affordance_labels.clear()
	affordance_props.clear()
	route_gate_nodes.clear()
	# Sub-project #1: drop retained visited-derelict instances on reload. The
	# active derelict scene is already freed and current_ship nulled below; a
	# stale ShipInstance left in visited_ships would make a post-reload revisit
	# reuse pre-reload systems state instead of building a fresh condition-seeded
	# instance. home_ship is NOT cleared — _on_ship_loaded reassigns it.
	visited_ships.clear()
	objective_completion_count = 0
	slice_complete = false
	# Reset pure models so a fresh load starts from a clean state and
	# then has the snapshot re-applied.
	if ship_systems_manager != null:
		var bp_reset = _load_blueprint_for_systems()
		ship_systems_manager.configure(ship_systems_manager.load_definitions(), bp_reset.condition, bp_reset.seed_value)
		_apply_lifeboat_opening_damage()
	_configure_player_progression()
	completed_objective_types.clear()
	if route_control_state != null:
		route_control_state.configure_from_blocked_routes([])
	if oxygen_state != null:
		oxygen_state.configure({
			"zone_ids": [],
			"max_oxygen": OxygenStateScript.DEFAULT_MAX_OXYGEN,
			"drain_rate": OxygenStateScript.DEFAULT_DRAIN_RATE,
			"regen_rate": OxygenStateScript.DEFAULT_REGEN_RATE,
			"recovery_threshold": OxygenStateScript.DEFAULT_RECOVERY_THRESHOLD,
			"safe_threshold": OxygenStateScript.DEFAULT_SAFE_THRESHOLD,
		})
	if inventory_state != null:
		inventory_state.reset()
	if fire_state != null:
		fire_state.configure({
			"zone_ids": [],
			"burn_duration": FireStateScript.DEFAULT_BURN_DURATION,
			"clear_duration": FireStateScript.DEFAULT_CLEAR_DURATION,
		})
	if electrical_arc_state != null:
		electrical_arc_state.configure({
			"zone_ids": [],
			"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
			"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
		})
	if objective_progress_state != null:
		objective_progress_state.reset()
	breach_zone_node = null
	unsafe_room_marker = null
	fire_zone_node = null
	fire_zone_label = null
	arc_zone_node = null
	arc_zone_label = null
	tool_pickup = null
	fire_zone_resolved_room_id = ""
	arc_zone_resolved_room_id = ""
	# REQ-014: drop the second ToolPickup reference so a fresh load
	# rebuilds it cleanly. The node itself is freed by the
	# tool_pickup_root teardown above.
	junction_calibrator_pickup = null
	# REQ-014: clear the per-sequence kind lookup so a reload reflects
	# the freshly-built interactable group, not the prior run's.
	sequence_kinds.clear()
	# The loader's own load_from_paths() entry point calls
	# clear_loaded_ship() first, so re-driving it is safe without any
	# extra reset here.

func _input(event: InputEvent) -> void:
	if not playable_started or slice_complete:
		return
	# Phase 4.5: scanner panel toggle + navigation. Opening the panel freezes
	# player movement/interaction so the shared arrow/Enter keys drive the panel.
	# Control is restored on close by the panel_closed signal handler, which
	# covers every close path — not just toggle-close / confirm-success.
	if scanner_panel != null:
		if event.is_action_pressed("toggle_scanner"):
			scanner_panel.toggle()
			if player != null and scanner_panel.is_open():
				player.set_physics_process(false)
				player.set_process_input(false)
				player.set_process_unhandled_input(false)
			get_viewport().set_input_as_handled()
			return
		if scanner_panel.is_open():
			if event.is_action_pressed("ui_down"):
				scanner_panel.move_selection(1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_up"):
				scanner_panel.move_selection(-1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_accept"):
				scanner_panel.confirm_selection()
				get_viewport().set_input_as_handled()
			return  # swallow other input while the scanner is open
	if save_load_service == null:
		return
	if event.is_action_pressed("save_run"):
		request_save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("load_run"):
		request_load()
		get_viewport().set_input_as_handled()
