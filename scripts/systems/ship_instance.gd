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
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const CartStateScript := preload("res://scripts/systems/cart_state.gd")
const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")

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

# Sub-project #6 (cargo): per-ship cargo hold (stores items). Lazily created;
# persisted under "inventory" only when it actually holds something.
var inventory = null                     # ShipInventory | null

# Sub-project #6 (carts): carts parked on this ship. Persisted under "carts" only
# when non-empty. Each entry is a CartState.
var carts: Array = []                    # Array[CartState]

# Sub-project #2: per-derelict objective loop state. Lazily created; null for the
# home ship (which uses the coordinator's singleton loop, not this controller).
var objective_controller = null          # DerelictObjectiveController | null

# Sub-project #3: ids of scattered loot containers already searched on this ship.
# Salvage-point loot reuses the objective `completed` flag, so it is not listed here.
var looted_container_ids: Array = []

# Task 06: per-ship combat/threat persistence. The live ThreatManager node belongs to
# the coordinator; this summary lets traveled ships free/rebuild scene roots without
# losing threat positions, detection memory, or the last combat result.
var combat_summary: Dictionary = {}

# Derelict-side fire: per-ship authoritative FireSuppressionState. Lazily created;
# persisted under "fire" only when a compartment is actually burning. Home fire stays
# on the coordinator (fire_suppression_state); this is for boarded derelicts.
var fire = null                          # FireSuppressionState | null
# True once the coordinator has run its one-time environmental fire pre-seed for this
# derelict. Persisted so a revisit/reload does NOT re-roll the presence gate or re-ignite
# compartments the player already extinguished. Set even when the presence gate yields no
# fire — "seeded to empty" must survive reload too.
var fire_seeded: bool = false

# Domain 4: is this ship still in contact with the biomatter web? Derelicts
# generate attached (floating in the Sargasso). The foundation reads this to
# decide whether docking to this ship accelerates the hub's web growth; the
# follow-on cut-free action will flip it. Persisted only when false (additive).
var web_attached: bool = true

# Live Persistent Ships Phase 1: world_time at which this ship's sim was last
# advanced. Catch-up on revisit (Phase 4) advances the ship by
# (world_time - last_sim_time). Persisted only when nonzero (additive).
var last_sim_time: float = 0.0

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
	if not combat_summary.is_empty():
		result["combat"] = combat_summary.duplicate(true)
	if access != null:
		result["access"] = access.get_summary()
	if hangar != null and hangar.slot_count > 0:
		result["hangar"] = hangar.get_summary()
	if has_cargo():
		result["inventory"] = inventory.get_summary()
	if not carts.is_empty():
		var cart_dicts: Array = []
		for c in carts:
			cart_dicts.append(c.get_summary())
		result["carts"] = cart_dicts
	if has_fire():
		result["fire"] = fire.get_summary()
	if fire_seeded:
		result["fire_seeded"] = true
	if not web_attached:
		result["web_attached"] = false
	if last_sim_time != 0.0:
		result["last_sim_time"] = last_sim_time
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
	var combat_variant: Variant = summary.get("combat", null)
	if typeof(combat_variant) == TYPE_DICTIONARY:
		combat_summary = (combat_variant as Dictionary).duplicate(true)
	var access_summary: Variant = summary.get("access", null)
	if typeof(access_summary) == TYPE_DICTIONARY and not (access_summary as Dictionary).is_empty():
		get_access().apply_summary(access_summary as Dictionary)
	var hangar_summary: Variant = summary.get("hangar", null)
	if typeof(hangar_summary) == TYPE_DICTIONARY and not (hangar_summary as Dictionary).is_empty():
		get_hangar().apply_summary(hangar_summary as Dictionary)
	var inventory_summary: Variant = summary.get("inventory", null)
	if typeof(inventory_summary) == TYPE_DICTIONARY and not (inventory_summary as Dictionary).is_empty():
		get_inventory().apply_summary(inventory_summary as Dictionary)
	var carts_variant: Variant = summary.get("carts", null)
	if typeof(carts_variant) == TYPE_ARRAY:
		carts = []
		for cd in (carts_variant as Array):
			if typeof(cd) == TYPE_DICTIONARY:
				var cart = CartStateScript.create()
				cart.apply_summary(cd as Dictionary)
				carts.append(cart)
	var fire_summary: Variant = summary.get("fire", null)
	if typeof(fire_summary) == TYPE_DICTIONARY and not (fire_summary as Dictionary).is_empty():
		get_fire().apply_summary(fire_summary as Dictionary)
	fire_seeded = bool(summary.get("fire_seeded", fire_seeded))
	web_attached = bool(summary.get("web_attached", web_attached))
	last_sim_time = float(summary.get("last_sim_time", last_sim_time))
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

## Returns this ship's ShipInventory cargo hold, creating an empty one on first access.
func get_inventory():
	if inventory == null:
		inventory = ShipInventoryScript.create()
	return inventory

## True iff this ship's hold exists and holds at least one item.
func has_cargo() -> bool:
	return inventory != null and not inventory.items.is_empty()

## Returns this ship's FireSuppressionState, creating a bare one on first access.
## The coordinator configures it from tuning before seeding/use.
func get_fire():
	if fire == null:
		fire = FireSuppressionStateScript.new()
	return fire

## True iff this ship has at least one burning compartment.
func has_fire() -> bool:
	return fire != null and not fire.get_burning_compartments().is_empty()

## True iff this ship is still in contact with the biomatter web.
func is_web_attached() -> bool:
	return web_attached

## Returns this ship's live carts array (parked carts).
func get_carts() -> Array:
	return carts

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
