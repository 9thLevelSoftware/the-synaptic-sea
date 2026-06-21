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

var ship_id: String = ""
var marker_id: String = ""          # "" for the starting ship; cell:cell:index for traveled ships
var blueprint                       # ShipBlueprint
var systems_manager                 # ShipSystemsManager (this ship's own systems)
var scene_root: Node3D = null       # generated/loaded tree; null when not instantiated

# Phase 5 stubs — declared, unused this phase.
var parent_ship = null              # ShipInstance | null
var docked_ships: Array = []        # Array[ShipInstance]
var docking_ports: Array = []       # Array (DockingPort in Phase 5)

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
	return {
		"ship_id": ship_id,
		"marker_id": marker_id,
		"blueprint": bp_dict,
		"systems": sys_dict,
	}

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
	return true
