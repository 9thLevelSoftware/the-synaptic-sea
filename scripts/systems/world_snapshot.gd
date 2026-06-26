extends RefCounted
class_name WorldSnapshot

## Top-level world save. Wraps the SargassoWorld summary, the home ship's
## RunSnapshot (unchanged), a per-derelict slice registry keyed by marker_id,
## the player's current location, and the in-ship player position. Pure data;
## serialization-agnostic (SaveLoadService owns file I/O). Geometry is never
## stored — derelict hulls regenerate deterministically from seed; only mutable
## state rides the per-ship slices.

const WORLD_SLICE_VERSION: String = "world-4"

var world_summary: Dictionary = {}
var home_ship: Dictionary = {}                  # a RunSnapshot.to_dict()
var meta_progression_summary: Dictionary = {}   # MetaProgressionState.to_dict()
var unique_item_summary: Dictionary = {}        # UniqueItemState.get_summary()
var home_looted_containers: Array = []          # home ship's searched loot-container ids
var home_ship_inventory: Dictionary = {}        # home ship's ShipInventory.get_summary()
var home_ship_carts: Array = []                  # home ship's [CartState.get_summary()...]
var player_equipment: Dictionary = {}           # EquipmentState.get_summary()
var visited_ships: Dictionary = {}              # marker_id -> ShipInstance.get_summary()
var current_location: String = ""               # "" = home ship, else marker_id
var player_position_in_ship: Array = [0.0, 0.0, 0.0]
var dock_edges: Array = []          # [{host, mobile, port_type:"airlock"|"hangar", slot_index:int}]
var piloted_ship_id: String = ""
var aboard_ship_id: String = ""
var opened_ports: Array = []        # marker_ids with an opened dock barrier
var slice_version: String = ""
var godot_version: String = ""
var saved_at: String = ""

func to_dict() -> Dictionary:
	return {
		"world_summary": world_summary.duplicate(true),
		"home_ship": home_ship.duplicate(true),
		"meta_progression_summary": meta_progression_summary.duplicate(true),
		"unique_item_summary": unique_item_summary.duplicate(true),
		"home_looted_containers": home_looted_containers.duplicate(),
		"home_ship_inventory": home_ship_inventory.duplicate(true),
		"home_ship_carts": home_ship_carts.duplicate(true),
		"player_equipment": player_equipment.duplicate(true),
		"visited_ships": visited_ships.duplicate(true),
		"current_location": current_location,
		"player_position_in_ship": player_position_in_ship.duplicate(),
		"dock_edges": dock_edges.duplicate(true),
		"piloted_ship_id": piloted_ship_id,
		"aboard_ship_id": aboard_ship_id,
		"opened_ports": opened_ports.duplicate(),
		"slice_version": slice_version,
		"godot_version": godot_version,
		"saved_at": saved_at,
	}

## Reconstructs a WorldSnapshot. Returns null when data is missing/not a dict,
## or when either version marker does not match (per ADR-0007/0012: incompatible
## saves are rejected so load always falls back to a fresh run).
static func from_dict(data: Variant, expected_world_version: String, expected_godot_version: String) -> WorldSnapshot:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data as Dictionary
	if dict.is_empty():
		return null
	if str(dict.get("slice_version", "")) != expected_world_version:
		return null
	if str(dict.get("godot_version", "")) != expected_godot_version:
		return null
	# Construct via load() self-reference rather than WorldSnapshot.new():
	# under --headless --script Godot does not rebuild the global class
	# registry, so a freshly added class_name is not resolvable on a fresh
	# checkout / CI / regenerated .godot. Mirrors ShipInstance.create.
	var script: GDScript = load("res://scripts/systems/world_snapshot.gd")
	var ws: WorldSnapshot = script.new()
	ws.world_summary = _deep_copy_dict(dict.get("world_summary", {}))
	ws.home_ship = _deep_copy_dict(dict.get("home_ship", {}))
	ws.meta_progression_summary = _deep_copy_dict(dict.get("meta_progression_summary", {}))
	ws.unique_item_summary = _deep_copy_dict(dict.get("unique_item_summary", {}))
	var looted_variant: Variant = dict.get("home_looted_containers", [])
	if typeof(looted_variant) == TYPE_ARRAY:
		ws.home_looted_containers = []
		for cid in (looted_variant as Array):
			ws.home_looted_containers.append(String(cid))
	ws.home_ship_inventory = _deep_copy_dict(dict.get("home_ship_inventory", {}))
	var hc_variant: Variant = dict.get("home_ship_carts", [])
	ws.home_ship_carts = (hc_variant as Array).duplicate(true) if hc_variant is Array else []
	ws.player_equipment = _deep_copy_dict(dict.get("player_equipment", {}))
	ws.visited_ships = _deep_copy_dict(dict.get("visited_ships", {}))
	ws.current_location = str(dict.get("current_location", ""))
	var edges_v: Variant = dict.get("dock_edges", [])
	if typeof(edges_v) == TYPE_ARRAY:
		ws.dock_edges = (edges_v as Array).duplicate(true)
	ws.piloted_ship_id = str(dict.get("piloted_ship_id", ""))
	ws.aboard_ship_id = str(dict.get("aboard_ship_id", ""))
	var op_v: Variant = dict.get("opened_ports", [])
	if typeof(op_v) == TYPE_ARRAY:
		ws.opened_ports = []
		for m in (op_v as Array):
			ws.opened_ports.append(String(m))
	var pos = dict.get("player_position_in_ship", [0.0, 0.0, 0.0])
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 3:
		var pa: Array = pos as Array
		ws.player_position_in_ship = [float(pa[0]), float(pa[1]), float(pa[2])]
	ws.slice_version = str(dict.get("slice_version", ""))
	ws.godot_version = str(dict.get("godot_version", ""))
	ws.saved_at = str(dict.get("saved_at", ""))
	return ws

static func _deep_copy_dict(src: Variant) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return {}
	return (src as Dictionary).duplicate(true)
