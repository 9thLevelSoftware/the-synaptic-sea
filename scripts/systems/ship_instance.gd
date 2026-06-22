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

var ship_id: String = ""
var marker_id: String = ""          # "" for the starting ship; cell:cell:index for traveled ships
var blueprint                       # ShipBlueprint
var systems_manager                 # ShipSystemsManager (this ship's own systems)
var scene_root: Node3D = null       # generated/loaded tree; null when not instantiated

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
	return true

## Returns this ship's DerelictObjectiveController, creating it on first access.
func get_objective_controller():
	if objective_controller == null:
		objective_controller = DerelictObjectiveControllerScript.create()
	return objective_controller

## World-space AABB enclosing scene_root's visual instances. Used to build
## occupancy entries. Returns a zero-size AABB at scene_root's global origin
## when there is no geometry yet (e.g. an unbuilt retained instance).
func interior_aabb() -> AABB:
	if scene_root == null or not is_instance_valid(scene_root):
		return AABB()
	var acc := AABB()
	var seeded := false
	for node in _visual_descendants(scene_root):
		if node.is_inside_tree():
			var world: AABB = node.global_transform * node.get_aabb()
			if not seeded:
				acc = world
				seeded = true
			else:
				acc = acc.merge(world)
	if not seeded:
		var o: Vector3 = scene_root.global_position if scene_root.is_inside_tree() else scene_root.position
		return AABB(o, Vector3.ZERO)
	return acc

func _visual_descendants(node: Node) -> Array:
	var out: Array = []
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_visual_descendants(child))
	return out
