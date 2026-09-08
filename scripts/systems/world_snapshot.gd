extends RefCounted
class_name WorldSnapshot

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const FieldCraftingStateScript := preload("res://scripts/systems/field_crafting_state.gd")
const RecipeKnowledgeStateScript := preload("res://scripts/systems/recipe_knowledge_state.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")

## Top-level world save. Wraps the SynapticSeaWorld summary, the home ship's
## RunSnapshot (unchanged), a per-derelict slice registry keyed by marker_id,
## the player's current location, owner-local pose, and exact spatial authority. Pure data;
## serialization-agnostic (SaveLoadService owns file I/O). Geometry is never
## stored — derelict hulls regenerate deterministically from seed; only mutable
## state rides the per-ship slices.

const WORLD_SLICE_VERSION: String = "world-7"

const LEGACY_WORLD_KEYS: Array[String] = [
	"dock_edges", "player_position_in_ship", "opened_ports",
]
const DOCK_CONNECTION_KEYS: Array[String] = [
	"connection_id", "port_type", "slot_index", "host", "mobile",
]
const AIRLOCK_END_KEYS: Array[String] = ["ship_id", "endpoint_id", "port_id"]
const HANGAR_END_KEYS: Array[String] = ["ship_id", "attachment_id"]
const PLAYER_OWNER_POSE_KEYS: Array[String] = [
	"owner_ship_id", "location_kind", "local_position", "connection_id", "endpoint_id",
]
const BOARDING_PORT_STATE_KEYS: Array[String] = [
	"ship_id", "endpoint_id", "barrier_open",
]
const ROOT_COMMON_KEYS: Array[String] = ["ship_id", "authority_kind"]
const ROOT_WORLD_ANCHOR_KEYS: Array[String] = [
	"ship_id", "authority_kind", "location_id", "anchor_id",
]
const ROOT_CONNECTION_KEYS: Array[String] = [
	"ship_id", "authority_kind", "connection_id",
]
const ROOT_FREE_KEYS: Array[String] = [
	"ship_id", "authority_kind", "frame_ship_id", "local_transform",
]
const CARDINAL_Y_UP_BASES: Array = [
	[1, 0, 0, 0, 1, 0, 0, 0, 1],
	[0, 0, -1, 0, 1, 0, 1, 0, 0],
	[-1, 0, 0, 0, 1, 0, 0, 0, -1],
	[0, 0, 1, 0, 1, 0, -1, 0, 0],
]

var world_summary: Dictionary = {}
var home_ship: Dictionary = {}                  # a RunSnapshot.to_dict()
var meta_progression_summary: Dictionary = {}   # MetaProgressionState.to_dict()
var unique_item_summary: Dictionary = {}        # UniqueItemState.get_summary()
var home_looted_containers: Array = []          # home ship's searched loot-container ids
var home_ship_inventory: Dictionary = {}        # home ship's ShipInventory.get_summary()
var home_ship_carts: Array = []                  # home ship's [CartState.get_summary()...]
var home_floor_drops_v1: Dictionary = {}         # home ShipInstance.get_floor_drop_summary()
var home_pending_outputs_v1: Dictionary = {}     # home ShipInstance PendingOutputStore summary
var home_access_v1: Dictionary = {}              # exact ShipAccessState summary for the home ship
var home_breach_environment: Dictionary = {}     # home ShipInstance breach environment only
var player_equipment: Dictionary = {}           # EquipmentState.get_summary()
var visited_ships: Dictionary = {}              # marker_id -> ShipInstance.get_summary()
var current_location: String = ""               # "" = home ship, else marker_id
# Live Persistent Ships Phase 1: monotonic in-run simulation clock (seconds).
# Persisted additively; older saves default to 0.0 via .get("world_time", 0.0).
var world_time: float = 0.0
var dock_connections_v1: Array = []
var player_owner_pose_v1: Dictionary = {}
var boarding_port_states_v1: Array = []
var ship_root_authorities_v1: Array = []
var piloted_ship_id: String = ""
var aboard_ship_id: String = ""
# run_id slot-ownership rework (ADR-0043 addendum): stamped by
# SaveLoadService.save_world() with the writing run's identity. Empty
# default so legacy saves (predating this field) load without failing
# validation. Replaces manual_slots_written/_persisted_lineage_active: the
# freeze set is now computed by SaveLoadService.slot_ids_for_run(run_id)
# reading the index, not by convention-tracked flags mirrored through this
# snapshot.
var run_id: String = ""
var slice_version: String = ""
var godot_version: String = ""
var saved_at: String = ""

func to_dict() -> Dictionary:
	var result: Dictionary = {
		"world_summary": world_summary.duplicate(true),
		"home_ship": home_ship.duplicate(true),
		"meta_progression_summary": meta_progression_summary.duplicate(true),
		"unique_item_summary": unique_item_summary.duplicate(true),
		"home_looted_containers": home_looted_containers.duplicate(),
		"home_ship_carts": home_ship_carts.duplicate(true),
		"home_breach_environment": home_breach_environment.duplicate(true),
		"visited_ships": visited_ships.duplicate(true),
		"current_location": current_location,
		"world_time": world_time,
		"dock_connections_v1": _sorted_rows(dock_connections_v1, "connection_id"),
		"player_owner_pose_v1": player_owner_pose_v1.duplicate(true),
		"boarding_port_states_v1": _sorted_rows(boarding_port_states_v1, "ship_id", "endpoint_id"),
		"ship_root_authorities_v1": _sorted_rows(ship_root_authorities_v1, "ship_id"),
		"piloted_ship_id": piloted_ship_id,
		"aboard_ship_id": aboard_ship_id,
		"run_id": run_id,
		"slice_version": slice_version,
		"godot_version": godot_version,
		"saved_at": saved_at,
	}
	if not home_ship_inventory.is_empty():
		result["home_ship_inventory"] = home_ship_inventory.duplicate(true)
	if not home_floor_drops_v1.is_empty():
		result["home_floor_drops_v1"] = home_floor_drops_v1.duplicate(true)
	# world-5 owns the home store even when it has no receipts. Omission would
	# make a fresh-process load unable to distinguish an empty authority from a
	# ship-only payload whose owner graph was never captured.
	result["home_pending_outputs_v1"] = home_pending_outputs_v1.duplicate(true)
	if not home_access_v1.is_empty():
		result["home_access_v1"] = home_access_v1.duplicate(true)
	if not player_equipment.is_empty():
		result["player_equipment"] = player_equipment.duplicate(true)
	return result

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
	if not validate_world7_authority_fields(dict):
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
	if dict.has("home_ship_inventory"):
		if not (dict["home_ship_inventory"] is Dictionary) or (dict["home_ship_inventory"] as Dictionary).is_empty():
			return null
	ws.home_ship_inventory = _deep_copy_dict(dict.get("home_ship_inventory", {}))
	var hc_variant: Variant = dict.get("home_ship_carts", [])
	if not (hc_variant is Array):
		return null
	ws.home_ship_carts = (hc_variant as Array).duplicate(true)
	if dict.has("home_floor_drops_v1"):
		if not (dict["home_floor_drops_v1"] is Dictionary) or (dict["home_floor_drops_v1"] as Dictionary).is_empty():
			return null
	ws.home_floor_drops_v1 = _deep_copy_dict(dict.get("home_floor_drops_v1", {}))
	if not dict.has("home_pending_outputs_v1") \
			or not (dict["home_pending_outputs_v1"] is Dictionary) \
			or (dict["home_pending_outputs_v1"] as Dictionary).is_empty():
		return null
	ws.home_pending_outputs_v1 = _deep_copy_dict(dict.home_pending_outputs_v1)
	if dict.has("home_access_v1"):
		if not _is_valid_home_access(dict["home_access_v1"]):
			return null
	ws.home_access_v1 = _deep_copy_dict(dict.get("home_access_v1", {}))
	ws.home_breach_environment = _deep_copy_dict(dict.get("home_breach_environment", {}))
	if dict.has("player_equipment"):
		if not (dict["player_equipment"] is Dictionary) or (dict["player_equipment"] as Dictionary).is_empty():
			return null
	ws.player_equipment = _deep_copy_dict(dict.get("player_equipment", {}))
	if dict.has("visited_ships") and not (dict["visited_ships"] is Dictionary):
		return null
	ws.visited_ships = _deep_copy_dict(dict.get("visited_ships", {}))
	ws.current_location = str(dict.get("current_location", ""))
	ws.world_time = float(dict.get("world_time", 0.0))
	ws.dock_connections_v1 = (dict.dock_connections_v1 as Array).duplicate(true)
	ws.player_owner_pose_v1 = (dict.player_owner_pose_v1 as Dictionary).duplicate(true)
	ws.boarding_port_states_v1 = (dict.boarding_port_states_v1 as Array).duplicate(true)
	ws.ship_root_authorities_v1 = (dict.ship_root_authorities_v1 as Array).duplicate(true)
	ws.piloted_ship_id = str(dict.get("piloted_ship_id", ""))
	ws.aboard_ship_id = dict.aboard_ship_id as String
	# run_id slot-ownership rework: additive, no version bump -- older saves
	# without the field default to "" (matches breach_seeded's pattern).
	ws.run_id = str(dict.get("run_id", ""))
	ws.slice_version = str(dict.get("slice_version", ""))
	ws.godot_version = str(dict.get("godot_version", ""))
	ws.saved_at = str(dict.get("saved_at", ""))
	if not _validate_detached_nested_state(ws, expected_godot_version):
		return null
	return ws


## Validates only the world-7-owned syntax. Detached owner/endpoint/parent
## closure belongs to SaveRestoreCandidate after all ship summaries decode.
static func validate_world7_authority_fields(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var dict: Dictionary = data
	for legacy_key in LEGACY_WORLD_KEYS:
		if dict.has(legacy_key):
			return false
	for required_key in [
		"dock_connections_v1", "player_owner_pose_v1",
		"boarding_port_states_v1", "ship_root_authorities_v1", "aboard_ship_id",
	]:
		if not dict.has(required_key):
			return false
	if not dict.aboard_ship_id is String or (dict.aboard_ship_id as String).is_empty():
		return false
	if not _validate_dock_connections(dict.dock_connections_v1):
		return false
	if not _validate_player_owner_pose(dict.player_owner_pose_v1, dict.aboard_ship_id as String):
		return false
	if not _validate_boarding_port_states(dict.boarding_port_states_v1):
		return false
	return _validate_ship_root_authorities(dict.ship_root_authorities_v1)


static func _validate_dock_connections(value: Variant) -> bool:
	if not value is Array:
		return false
	var connection_ids: Dictionary = {}
	var endpoint_identities: Dictionary = {}
	var port_identities: Dictionary = {}
	var attachment_identities: Dictionary = {}
	for row_v in value as Array:
		if not row_v is Dictionary:
			return false
		var row: Dictionary = row_v
		if not _has_exact_string_keys(row, DOCK_CONNECTION_KEYS) \
				or not _nonempty_string(row.connection_id) \
				or not row.port_type is String \
				or connection_ids.has(row.connection_id):
			return false
		connection_ids[row.connection_id] = true
		if row.port_type == "airlock":
			if not _is_exact_integer(row.slot_index) or int(row.slot_index) != -1:
				return false
			for side_name in ["host", "mobile"]:
				var side_v: Variant = row[side_name]
				if not side_v is Dictionary \
						or not _has_exact_string_keys(side_v as Dictionary, AIRLOCK_END_KEYS):
					return false
				var side: Dictionary = side_v
				for key in AIRLOCK_END_KEYS:
					if not _nonempty_string(side[key]):
						return false
				var endpoint_identity: String = "%s\n%s" % [side.ship_id, side.endpoint_id]
				if endpoint_identities.has(endpoint_identity):
					return false
				endpoint_identities[endpoint_identity] = true
				var port_identity: String = "%s\n%s" % [side.ship_id, side.port_id]
				if port_identities.has(port_identity):
					return false
				port_identities[port_identity] = true
		elif row.port_type == "hangar":
			if not _is_exact_integer(row.slot_index) or int(row.slot_index) < 0:
				return false
			for side_name in ["host", "mobile"]:
				var side_v: Variant = row[side_name]
				if not side_v is Dictionary \
						or not _has_exact_string_keys(side_v as Dictionary, HANGAR_END_KEYS):
					return false
				var side: Dictionary = side_v
				for key in HANGAR_END_KEYS:
					if not _nonempty_string(side[key]):
						return false
				var attachment_identity: String = "%s\n%s" % [side.ship_id, side.attachment_id]
				if attachment_identities.has(attachment_identity):
					return false
				attachment_identities[attachment_identity] = true
			if str((row.host as Dictionary).attachment_id) != "hangar-slot:%d" % int(row.slot_index) \
					or str((row.mobile as Dictionary).attachment_id) != "ship-root":
				return false
		else:
			return false
		if str((row.host as Dictionary).ship_id) == str((row.mobile as Dictionary).ship_id):
			return false
	return true


static func _validate_player_owner_pose(value: Variant, aboard_ship_id: String) -> bool:
	if not value is Dictionary:
		return false
	var pose: Dictionary = value
	if not _has_exact_string_keys(pose, PLAYER_OWNER_POSE_KEYS):
		return false
	for key in ["owner_ship_id", "location_kind", "connection_id", "endpoint_id"]:
		if not pose[key] is String:
			return false
	if (pose.owner_ship_id as String).is_empty() or pose.owner_ship_id != aboard_ship_id \
			or not _is_exact_finite_numeric_array(pose.local_position, 3):
		return false
	var coordinates: Array = pose.local_position as Array
	if not Vector3(
			float(coordinates[0]), float(coordinates[1]), float(coordinates[2])).is_finite():
		return false
	if pose.location_kind == "interior":
		return (pose.connection_id as String).is_empty() and (pose.endpoint_id as String).is_empty()
	if pose.location_kind == "dock_threshold":
		return not (pose.connection_id as String).is_empty() \
			and not (pose.endpoint_id as String).is_empty()
	return false


static func _validate_boarding_port_states(value: Variant) -> bool:
	if not value is Array:
		return false
	var identities: Dictionary = {}
	for row_v in value as Array:
		if not row_v is Dictionary:
			return false
		var row: Dictionary = row_v
		if not _has_exact_string_keys(row, BOARDING_PORT_STATE_KEYS) \
				or not _nonempty_string(row.ship_id) or not _nonempty_string(row.endpoint_id) \
				or typeof(row.barrier_open) != TYPE_BOOL:
			return false
		var identity: String = "%s\n%s" % [row.ship_id, row.endpoint_id]
		if identities.has(identity):
			return false
		identities[identity] = true
	return true


static func _validate_ship_root_authorities(value: Variant) -> bool:
	if not value is Array:
		return false
	var ship_ids: Dictionary = {}
	for row_v in value as Array:
		if not row_v is Dictionary:
			return false
		var row: Dictionary = row_v
		if not _has_required_string_keys(row, ROOT_COMMON_KEYS) \
				or not _nonempty_string(row.ship_id) or not _nonempty_string(row.authority_kind) \
				or ship_ids.has(row.ship_id):
			return false
		ship_ids[row.ship_id] = true
		match row.authority_kind:
			"world_anchor":
				if not _has_exact_string_keys(row, ROOT_WORLD_ANCHOR_KEYS) \
						or not _nonempty_string(row.location_id) \
						or not _nonempty_string(row.anchor_id):
					return false
			"connection":
				if not _has_exact_string_keys(row, ROOT_CONNECTION_KEYS) \
						or not _nonempty_string(row.connection_id):
					return false
			"free":
				if not _has_exact_string_keys(row, ROOT_FREE_KEYS) \
						or not _nonempty_string(row.frame_ship_id) \
						or row.frame_ship_id == row.ship_id \
						or not _is_supported_free_transform(row.local_transform):
					return false
			_:
				return false
	return true


static func _is_supported_free_transform(value: Variant) -> bool:
	if not _is_exact_finite_numeric_array(value, 12):
		return false
	var values: Array = value as Array
	var cardinal: bool = false
	for supported_v in CARDINAL_Y_UP_BASES:
		var supported: Array = supported_v as Array
		var matches: bool = true
		for index in range(9):
			if float(values[index]) != float(supported[index]):
				matches = false
				break
		if matches:
			cardinal = true
			break
	if not cardinal:
		return false
	var transform := Transform3D(
		Basis(
			Vector3(float(values[0]), float(values[1]), float(values[2])),
			Vector3(float(values[3]), float(values[4]), float(values[5])),
			Vector3(float(values[6]), float(values[7]), float(values[8]))),
		Vector3(float(values[9]), float(values[10]), float(values[11])))
	return transform.is_finite()


static func _is_exact_finite_numeric_array(value: Variant, expected_size: int) -> bool:
	if not value is Array or (value as Array).size() != expected_size:
		return false
	for component in value as Array:
		if (typeof(component) != TYPE_INT and typeof(component) != TYPE_FLOAT) \
				or not is_finite(float(component)):
			return false
	return true


static func _is_exact_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) \
		and float(value) == floorf(float(value))


static func _nonempty_string(value: Variant) -> bool:
	return value is String and not (value as String).is_empty()


static func _has_exact_string_keys(row: Dictionary, expected: Array[String]) -> bool:
	return row.size() == expected.size() and _has_required_string_keys(row, expected)


static func _has_required_string_keys(row: Dictionary, expected: Array[String]) -> bool:
	for key_v in row.keys():
		if not key_v is String:
			return false
	for key in expected:
		if not row.has(key):
			return false
	return true


static func _sorted_rows(rows: Array, primary: String, secondary: String = "") -> Array:
	var result: Array = rows.duplicate(true)
	result.sort_custom(func(left_v: Variant, right_v: Variant) -> bool:
		var left: Dictionary = left_v as Dictionary
		var right: Dictionary = right_v as Dictionary
		var left_key: String = str(left.get(primary, ""))
		var right_key: String = str(right.get(primary, ""))
		if left_key == right_key and not secondary.is_empty():
			return str(left.get(secondary, "")) < str(right.get(secondary, ""))
		return left_key < right_key)
	return result

static func _deep_copy_dict(src: Variant) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return {}
	return (src as Dictionary).duplicate(true)


## Present world-4 access is a modern owner payload, not a permissive legacy
## hint. Absence alone selects the legacy bootstrap migration in the coordinator.
static func _is_valid_home_access(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var summary: Dictionary = value as Dictionary
	if summary.size() != 2 or not summary.has("owner_id") or not summary.has("access_ids") \
			or not (summary.owner_id is String) or not (summary.access_ids is Array):
		return false
	var owner_id: String = summary.owner_id as String
	if owner_id.is_empty():
		return false
	var seen: Dictionary = {}
	for access_id_v in summary.access_ids as Array:
		if not (access_id_v is String):
			return false
		var access_id: String = access_id_v as String
		if access_id.is_empty() or seen.has(access_id):
			return false
		seen[access_id] = true
	return seen.has(owner_id)


static func _validate_detached_nested_state(ws: WorldSnapshot, expected_godot: String) -> bool:
	var home_run = RunSnapshotScript.from_dict(
		ws.home_ship, "gate2-current-run-7", expected_godot)
	if home_run == null:
		return false
	var crafting = CraftingStateScript.new()
	var holder_id: String = _run_holder_id(home_run.inventory_summary, ws.run_id)
	if not crafting.configure_legacy_restore_owner("ship_start", holder_id) \
			or not crafting.apply_summary(home_run.crafting_summary):
		return false
	var field_crafting = FieldCraftingStateScript.new()
	if not field_crafting.configure_legacy_restore_owner("ship_start", holder_id) \
			or not field_crafting.apply_summary(home_run.crafting_summary):
		return false
	var knowledge = RecipeKnowledgeStateScript.new()
	var expected_owner: String = "player:%s" % ws.run_id if not ws.run_id.is_empty() \
		else str(home_run.recipe_knowledge_summary.get("owner_id", "player:legacy"))
	if expected_owner.is_empty():
		expected_owner = "player:legacy"
	knowledge.configure(expected_owner, crafting.get_recipe_catalog())
	if not knowledge.apply_summary(home_run.recipe_knowledge_summary):
		return false
	if str(home_run.recipe_knowledge_summary.get("migration_origin", "")) == "native" \
			and str(home_run.recipe_knowledge_summary.get("owner_id", "")) != expected_owner:
		return false
	var component = ComponentPlacementStateScript.new()
	if not component.apply_summary(home_run.component_placement_summary, "ship_start"):
		return false
	var home_summary: Dictionary = {
		"ship_id": "ship_start", "marker_id": "", "carts": ws.home_ship_carts.duplicate(true),
	}
	if not ws.home_ship_inventory.is_empty():
		home_summary["inventory"] = ws.home_ship_inventory.duplicate(true)
	if not ws.home_floor_drops_v1.is_empty():
		home_summary["floor_drops_v1"] = ws.home_floor_drops_v1.duplicate(true)
	if not ws.home_pending_outputs_v1.is_empty():
		home_summary["pending_outputs_v1"] = ws.home_pending_outputs_v1.duplicate(true)
	if not ws.home_access_v1.is_empty():
		home_summary["access"] = ws.home_access_v1.duplicate(true)
	var home_ship = ShipInstanceScript.create("ship_start", "", null, null, null)
	if not home_ship.apply_summary(home_summary):
		return false
	var seen_ship_ids: Dictionary = {"ship_start": true, "lifeboat": true}
	var current_location_found: bool = ws.current_location.is_empty()
	for marker_variant in ws.visited_ships:
		var marker_id: String = str(marker_variant)
		var raw_summary: Variant = ws.visited_ships[marker_variant]
		if marker_id.is_empty() or not raw_summary is Dictionary \
				or not (raw_summary as Dictionary).get("pending_outputs_v1", null) is Dictionary \
				or ((raw_summary as Dictionary).pending_outputs_v1 as Dictionary).is_empty():
			return false
		var ship = ShipInstanceScript.create("", "", ShipBlueprintScript.new(), null, null)
		if not ship.apply_summary(raw_summary) or str(ship.marker_id) != marker_id \
				or str(ship.ship_id).is_empty() or seen_ship_ids.has(str(ship.ship_id)):
			return false
		seen_ship_ids[str(ship.ship_id)] = true
		if marker_id == ws.current_location and not (raw_summary as Dictionary).has("combat"):
			return false
		if marker_id == ws.current_location:
			current_location_found = true
	if not current_location_found:
		return false
	return _validate_field_pin(home_run.crafting_summary, ws)


static func _run_holder_id(inventory_summary: Dictionary, run_id: String) -> String:
	var lots_v: Variant = inventory_summary.get("item_lots_v1", null)
	if lots_v is Dictionary:
		var holder: String = str((lots_v as Dictionary).get("holder_namespace", ""))
		if not holder.is_empty():
			return holder
	return "player:%s" % (run_id if not run_id.is_empty() else "legacy")


static func _validate_field_pin(crafting_summary: Dictionary, ws: WorldSnapshot) -> bool:
	var field_v: Variant = crafting_summary.get("field_crafting", null)
	if not field_v is Dictionary:
		return false
	var pending_v: Variant = (field_v as Dictionary).get("field_pending_v1", null)
	if not pending_v is Dictionary:
		return false
	var pending: Dictionary = pending_v
	var receipt_id: String = str(pending.get("active_receipt_id", ""))
	var pinned_ship_id: String = str(pending.get("pinned_destination_ship_id", ""))
	if receipt_id.is_empty() or pinned_ship_id.is_empty():
		return true
	var store_summary: Dictionary = {}
	if pinned_ship_id == "ship_start":
		store_summary = ws.home_pending_outputs_v1
	else:
		for ship_variant in ws.visited_ships.values():
			if ship_variant is Dictionary and str((ship_variant as Dictionary).get("ship_id", "")) == pinned_ship_id:
				var store_v: Variant = (ship_variant as Dictionary).get("pending_outputs_v1", null)
				if store_v is Dictionary:
					store_summary = store_v
				break
	if store_summary.is_empty() or str(store_summary.get("ship_id", "")) != pinned_ship_id:
		return false
	for record_variant in store_summary.get("records", []) as Array:
		if record_variant is Dictionary and str((record_variant as Dictionary).get("receipt_id", "")) == receipt_id:
			return true
	return false
