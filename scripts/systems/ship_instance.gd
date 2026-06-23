extends RefCounted
class_name ShipInstance

## Lightweight per-ship handle. Bundles the identity + data + systems + scene
## root that genuinely must be per-ship for multi-ship travel/docking. Pure
## data plus a systems handle and a Node3D reference; it never adds or frees
## its own scene_root — the coordinator owns scene-tree lifecycle (single
## ownership). Phase-5 docking fields are declared now so docking attaches to
## a stable shape; they are unused this phase.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const DerelictObjectiveControllerScript := preload("res://scripts/systems/derelict_objective_controller.gd")
const ShipAccessStateScript := preload("res://scripts/systems/ship_access_state.gd")
const HangarBayScript := preload("res://scripts/systems/hangar_bay.gd")

const ROOM_HALF_EXTENT: float = 4.0   # generous per-room half-box in X/Z (covers 2x1 rooms + module chains)
const ROOM_HALF_HEIGHT: float = 3.0   # half deck height + headroom

var ship_id: String = ""
var marker_id: String = ""          # "" for the starting ship; cell:cell:index for traveled ships
var blueprint                       # ShipBlueprint
var systems_manager                 # ShipSystemsManager (this ship's own systems)
var scene_root: Node3D = null       # generated/loaded tree; null when not instantiated
var built_layout: Dictionary = {}   # the layout dict scene_root was built from (for dock-port derivation)

# 5a: `ship_root` is the ship's positioned root — it IS scene_root, exposed
# under the docking-domain name. Alias so DockingManager/occupancy read
# naturally without renaming the coordinator's existing scene_root usage.
var ship_root: Node3D:
	get:
		return scene_root
	set(value):
		scene_root = value

# Phase 5 stubs — declared, unused this phase.
var parent_ship = null              # ShipInstance | null
var docked_ships: Array = []        # Array[ShipInstance]
var docking_ports: Array = []       # Array (DockingPort in Phase 5)

# Sub-project 5c: per-ship ownership/access. Lazily created; persisted under "access".
var access = null                        # ShipAccessState | null

# Sub-project 5d: per-ship hangar bay (stores other ships). Lazily created;
# persisted under "hangar" only when it actually has slots.
var hangar = null                        # HangarBay | null

# Sub-project #2: per-derelict objective loop state. Lazily created; null for the
# home ship (which uses the coordinator's singleton loop, not this controller).
var objective_controller = null          # DerelictObjectiveController | null

# Sub-project #3: ids of scattered loot containers already searched on this ship.
# Salvage-point loot reuses the objective `completed` flag, so it is not listed here.
var looted_container_ids: Array = []

# Static factory via load() self-reference (class_name globals unreliable under
# --headless --script).
static func create(p_ship_id: String, p_marker_id: String, p_blueprint, p_systems_manager, p_scene_root) -> ShipInstance:
	var script: GDScript = load("res://scripts/systems/ship_instance.gd")
	var inst = script.new()
	inst.ship_id = p_ship_id
	inst.marker_id = p_marker_id
	inst.blueprint = p_blueprint
	inst.systems_manager = p_systems_manager
	inst.scene_root = p_scene_root
	return inst

func get_summary() -> Dictionary:
	var bp_dict: Dictionary = {}
	if blueprint != null and blueprint.has_method("to_dict"):
		bp_dict = blueprint.to_dict()
	var sys_dict: Dictionary = {}
	if systems_manager != null and systems_manager.has_method("get_summary"):
		sys_dict = systems_manager.get_summary()
	var result: Dictionary = {
		"ship_id": ship_id,
		"marker_id": marker_id,
		"blueprint": bp_dict,
		"systems": sys_dict,
	}
	if objective_controller != null:
		result["objective"] = objective_controller.get_summary()
	if not looted_container_ids.is_empty():
		result["looted_containers"] = looted_container_ids.duplicate()
	if access != null:
		result["access"] = access.get_summary()
	if hangar != null and hangar.slot_count > 0:
		result["hangar"] = hangar.get_summary()
	return result

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	ship_id = str(summary.get("ship_id", ship_id))
	marker_id = str(summary.get("marker_id", marker_id))
	var bp_dict: Variant = summary.get("blueprint", null)
	if typeof(bp_dict) == TYPE_DICTIONARY and not (bp_dict as Dictionary).is_empty():
		blueprint = ShipBlueprintScript.from_dict(bp_dict as Dictionary)
	var sys_dict: Variant = summary.get("systems", null)
	if typeof(sys_dict) == TYPE_DICTIONARY and not (sys_dict as Dictionary).is_empty():
		if systems_manager == null:
			systems_manager = ShipSystemsManagerScript.new()
			systems_manager.configure(systems_manager.load_definitions(), 0, 0)
		systems_manager.apply_summary(sys_dict)
	var obj_summary: Variant = summary.get("objective", null)
	if typeof(obj_summary) == TYPE_DICTIONARY and not (obj_summary as Dictionary).is_empty():
		if objective_controller == null:
			objective_controller = DerelictObjectiveControllerScript.create()
		objective_controller.apply_summary(obj_summary as Dictionary)
	var looted_variant: Variant = summary.get("looted_containers", null)
	if typeof(looted_variant) == TYPE_ARRAY:
		looted_container_ids = []
		for cid in (looted_variant as Array):
			looted_container_ids.append(String(cid))
	var access_summary: Variant = summary.get("access", null)
	if typeof(access_summary) == TYPE_DICTIONARY and not (access_summary as Dictionary).is_empty():
		get_access().apply_summary(access_summary as Dictionary)
	var hangar_summary: Variant = summary.get("hangar", null)
	if typeof(hangar_summary) == TYPE_DICTIONARY and not (hangar_summary as Dictionary).is_empty():
		get_hangar().apply_summary(hangar_summary as Dictionary)
	return true

## Returns this ship's DerelictObjectiveController, creating it on first access.
func get_objective_controller():
	if objective_controller == null:
		objective_controller = DerelictObjectiveControllerScript.create()
	return objective_controller

## Returns this ship's ShipAccessState, creating it on first access.
func get_access():
	if access == null:
		access = ShipAccessStateScript.create()
	return access

## Returns this ship's HangarBay, creating an empty (0-slot) one on first access.
func get_hangar():
	if hangar == null:
		hangar = HangarBayScript.create(0, 0)
	return hangar

## True iff this ship has a configured bay (at least one slot).
func has_hangar() -> bool:
	return hangar != null and hangar.slot_count > 0

## A "working vessel" can be piloted: its own propulsion system is operational.
func is_working_vessel() -> bool:
	return systems_manager != null and systems_manager.is_operational("propulsion")

## Validation/runtime seam: the layout dict this ship's scene_root was built from.
func blueprint_layout_for_validation() -> Dictionary:
	return built_layout

## World-space AABB enclosing this ship's interior, derived from the built
## ShipStructure's room-node LOCAL positions (robust off-tree / headless, where
## VisualInstance3D world AABBs are unresolved). The merged local AABB is
## transformed by scene_root's world transform.
##
## Null/empty scene_root or no room nodes -> zero-size AABB at the root origin
## (the "unbuilt retained instance" fallback).
func interior_aabb() -> AABB:
	if not is_instance_valid(scene_root):
		return AABB()
	var structure: Node = scene_root.get_node_or_null("ShipStructure")
	if structure == null:
		for c in scene_root.get_children():
			if c.get_child_count() > 0:
				structure = c
				break
	var local := AABB()
	var seeded := false
	if structure != null:
		for room_node in structure.get_children():
			if not (room_node is Node3D):
				continue
			var p: Vector3 = (room_node as Node3D).position
			var box := AABB(p - Vector3(ROOM_HALF_EXTENT, ROOM_HALF_HEIGHT, ROOM_HALF_EXTENT),
				Vector3(ROOM_HALF_EXTENT, ROOM_HALF_HEIGHT, ROOM_HALF_EXTENT) * 2.0)
			if not seeded:
				local = box
				seeded = true
			else:
				local = local.merge(box)
	if not seeded:
		var o: Vector3 = scene_root.global_position if scene_root.is_inside_tree() else scene_root.position
		return AABB(o, Vector3.ZERO)
	var xform: Transform3D = scene_root.global_transform if scene_root.is_inside_tree() else Transform3D(Basis(), scene_root.position)
	return xform * local
