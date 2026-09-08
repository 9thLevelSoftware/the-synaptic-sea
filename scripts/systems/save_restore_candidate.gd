extends RefCounted
class_name SaveRestoreCandidate

## P10 detached owner graph. Building this model performs all pure-data restore
## and cross-owner conservation checks before a scene root may be staged.

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const FieldCraftingStateScript := preload("res://scripts/systems/field_crafting_state.gd")
const RecipeKnowledgeStateScript := preload("res://scripts/systems/recipe_knowledge_state.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ThreatSaveContractScript := preload("res://scripts/systems/threat_save_contract.gd")
const LEGACY_LOCAL_ACCESS_ID: String = "player_local"
# DockEndpointAuthoring.validate_layout() requires exactly one
# boarding_endpoints_v1 row for every accepted production layout. World 7 pins
# that current production invariant; a later multi-endpoint layout needs a new
# persistence schema instead of silently broadening this state map.
const CURRENT_BOARDING_ENDPOINTS_PER_OWNER: int = 1

var world_snapshot = null
var run_snapshot = null
var effective_run_id: String = ""
var expected_player_owner: String = ""
var player_inventory: RefCounted = null
var crafting_state: RefCounted = null
var field_crafting_state: RefCounted = null
var recipe_knowledge_state: RefCounted = null
var player_equipment: RefCounted = null
var home_ship: RefCounted = null
var visited_ships: Dictionary = {} # marker_id -> detached ShipInstance
var component_placements: Dictionary = {} # ship_id -> detached ComponentPlacementState
var station_positions_by_owner: Dictionary = {} # ship_id -> station kind -> Vector3
var source_path: String = ""
var source_sha256: String = ""
var migration_from_version: String = ""
var migration_to_version: String = ""
var migrated: bool = false
var migrated_dict: Dictionary = {}


static func build(world, target_run_id: String) -> Dictionary:
	if world == null or target_run_id.is_empty():
		return {"ok": false, "reason": "missing_restore_identity"}
	var script: GDScript = load("res://scripts/systems/save_restore_candidate.gd")
	var candidate = script.new()
	candidate.world_snapshot = world
	candidate.effective_run_id = target_run_id
	candidate.expected_player_owner = "player:%s" % target_run_id
	var reason: String = candidate._materialize()
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	return {"ok": true, "reason": "", "candidate": candidate}


func attach_source(record: Dictionary) -> void:
	source_path = str(record.get("source_path", ""))
	source_sha256 = str(record.get("source_sha256", ""))
	migration_from_version = str(record.get("from_version", ""))
	migration_to_version = str(record.get("to_version", ""))
	migrated = bool(record.get("migrated", false))
	migrated_dict = (record.get("migrated_dict", {}) as Dictionary).duplicate(true) \
		if record.get("migrated_dict", null) is Dictionary else {}


func _materialize() -> String:
	if str(world_snapshot.run_id) != effective_run_id:
		return "run_id_mismatch"
	run_snapshot = RunSnapshotScript.from_dict(
		world_snapshot.home_ship, "gate2-current-run-7", str(world_snapshot.godot_version))
	if run_snapshot == null:
		return "invalid_home_run"
	if not str(run_snapshot.run_id).is_empty() and str(run_snapshot.run_id) != effective_run_id:
		return "home_run_id_mismatch"
	run_snapshot.run_id = effective_run_id
	var home_threat_result: Dictionary = ThreatSaveContractScript.validate_current(
		run_snapshot.inventory_summary.get("threat_summary", null))
	if not bool(home_threat_result.get("ok", false)):
		return "invalid_home_combat"
	var home_threat_summary: Dictionary = (
		home_threat_result.summary as Dictionary).duplicate(true)
	var combat_hotbar_present: bool = run_snapshot.inventory_summary.has("combat_hotbar_text")
	var combat_hotbar_text: String = ""
	if combat_hotbar_present:
		if typeof(run_snapshot.inventory_summary.combat_hotbar_text) != TYPE_STRING:
			return "invalid_combat_hotbar_text"
		combat_hotbar_text = run_snapshot.inventory_summary.combat_hotbar_text as String

	player_inventory = InventoryStateScript.new(expected_player_owner)
	if not player_inventory.apply_summary(
			run_snapshot.inventory_summary, run_snapshot.material_summary, expected_player_owner):
		return "invalid_player_inventory"
	if str(player_inventory.get_holder_namespace()) != expected_player_owner:
		return "player_inventory_owner_mismatch"

	crafting_state = CraftingStateScript.new()
	if not crafting_state.configure_legacy_restore_owner("ship_start", expected_player_owner) \
			or not crafting_state.apply_summary(run_snapshot.crafting_summary):
		return "invalid_crafting_state"
	var station_position_reason: String = _materialize_station_positions(
		run_snapshot.crafting_summary.get("physical_station_positions_v1", {}))
	if not station_position_reason.is_empty():
		return station_position_reason
	field_crafting_state = FieldCraftingStateScript.new()
	if not field_crafting_state.configure_legacy_restore_owner("ship_start", expected_player_owner) \
			or not field_crafting_state.apply_summary(run_snapshot.crafting_summary):
		return "invalid_field_crafting_state"

	recipe_knowledge_state = RecipeKnowledgeStateScript.new()
	recipe_knowledge_state.configure(expected_player_owner, crafting_state.get_recipe_catalog())
	if not recipe_knowledge_state.apply_summary(run_snapshot.recipe_knowledge_summary) \
			or str(recipe_knowledge_state.owner_id) != expected_player_owner:
		return "recipe_knowledge_owner_mismatch"

	var home_component = ComponentPlacementStateScript.new()
	if not home_component.apply_summary(run_snapshot.component_placement_summary, "ship_start"):
		return "invalid_home_component_placement"
	component_placements["ship_start"] = home_component

	var home_summary: Dictionary = {
		"ship_id": "ship_start",
		"marker_id": "",
		"carts": world_snapshot.home_ship_carts.duplicate(true),
		"pending_outputs_v1": world_snapshot.home_pending_outputs_v1.duplicate(true),
		"combat": home_threat_summary,
	}
	if not world_snapshot.home_ship_inventory.is_empty():
		home_summary["inventory"] = world_snapshot.home_ship_inventory.duplicate(true)
	if not world_snapshot.home_floor_drops_v1.is_empty():
		home_summary["floor_drops_v1"] = world_snapshot.home_floor_drops_v1.duplicate(true)
	if not world_snapshot.home_access_v1.is_empty():
		home_summary["access"] = world_snapshot.home_access_v1.duplicate(true)
	home_ship = ShipInstanceScript.create("ship_start", "", null, null, null)
	if not home_ship.apply_summary(home_summary):
		return "invalid_home_ship_owner"
	if world_snapshot.home_access_v1.is_empty():
		# A recognized legacy omission is adapted once, while the owner graph is
		# still detached. Staging and full-world recapture then consume the same
		# explicit authority instead of comparing an absent source field with the
		# coordinator's required local bootstrap claim.
		if not home_ship.claim_home_access_for_bootstrap(
				LEGACY_LOCAL_ACCESS_ID, false, true):
			return "invalid_legacy_home_access"
		world_snapshot.home_access_v1 = home_ship.get_access().get_summary()

	for marker_variant in world_snapshot.visited_ships:
		var marker_id: String = str(marker_variant)
		var raw: Variant = world_snapshot.visited_ships[marker_variant]
		if marker_id.is_empty() or not raw is Dictionary:
			return "invalid_visited_ship"
		var ship = ShipInstanceScript.create("", "", ShipBlueprintScript.new(), null, null)
		if not ship.apply_summary(raw) or str(ship.marker_id) != marker_id \
				or str(ship.ship_id).is_empty() or visited_ships.has(marker_id):
			return "invalid_visited_ship"
		if str(ship.ship_id) in ["ship_start", "lifeboat"] \
				or _ship_id_exists(str(ship.ship_id)):
			return "duplicate_ship_id"
		visited_ships[marker_id] = ship
		var component_v: Variant = (raw as Dictionary).get("component_placement", null)
		if component_v is Dictionary:
			var component = ComponentPlacementStateScript.new()
			if not component.apply_summary(component_v as Dictionary, str(ship.ship_id)):
				return "invalid_visited_component_placement"
			component_placements[str(ship.ship_id)] = component

	var station_identity_reason: String = _validate_station_position_closure()
	if not station_identity_reason.is_empty():
		return station_identity_reason
	var known_owner_markers: Dictionary = {
		"ship_start": "",
		"lifeboat": "",
	}
	for ship in visited_ships.values():
		known_owner_markers[str((ship as RefCounted).get("ship_id"))] = str(
			(ship as RefCounted).get("marker_id"))
	var authority_reason: String = validate_world_authority_graph(
		world_snapshot, known_owner_markers)
	if not authority_reason.is_empty():
		return authority_reason

	if not world_snapshot.player_equipment.is_empty():
		player_equipment = EquipmentStateScript.create()
		if not player_equipment.apply_summary(world_snapshot.player_equipment):
			return "invalid_player_equipment"

	var conservation_reason: String = _validate_conservation()
	if not conservation_reason.is_empty():
		return conservation_reason
	_normalize_migrated_authority(
		home_threat_summary, combat_hotbar_present, combat_hotbar_text)
	return ""


## Pure detached closure for the world-7 owner graph. Registered endpoint
## geometry is validated during staging; this model proves that every decoded
## owner has one root authority and one durable boarding-endpoint state, and
## that every persisted relationship resolves without inventing an owner.
static func validate_world_authority_graph(world, known_owner_markers: Dictionary) -> String:
	if world == null or known_owner_markers.is_empty() \
			or not known_owner_markers.has("ship_start") \
			or not known_owner_markers.has("lifeboat"):
		return "invalid_known_owner_set"
	for owner_v in known_owner_markers:
		if not owner_v is String or (owner_v as String).is_empty() \
				or not known_owner_markers[owner_v] is String:
			return "invalid_known_owner_set"
	var marker_owners: Dictionary = {}
	for owner_v in known_owner_markers:
		var owner_id: String = owner_v as String
		var marker_id: String = known_owner_markers[owner_v] as String
		if marker_id.is_empty():
			if owner_id not in ["ship_start", "lifeboat"]:
				return "invalid_known_owner_set"
			continue
		if marker_owners.has(marker_id):
			return "duplicate_known_owner_marker"
		marker_owners[marker_id] = owner_id

	var connections_by_id: Dictionary = {}
	var mobile_parents: Dictionary = {}
	for row_v in world.dock_connections_v1:
		var row: Dictionary = row_v as Dictionary
		var connection_id: String = row.connection_id as String
		var host: Dictionary = row.host as Dictionary
		var mobile: Dictionary = row.mobile as Dictionary
		var host_id: String = host.ship_id as String
		var mobile_id: String = mobile.ship_id as String
		if not known_owner_markers.has(host_id) or not known_owner_markers.has(mobile_id):
			return "connection_foreign_owner"
		if mobile_parents.has(mobile_id):
			return "connection_multiple_parent"
		connections_by_id[connection_id] = row
		mobile_parents[mobile_id] = connection_id

	var roots_by_ship: Dictionary = {}
	for row_v in world.ship_root_authorities_v1:
		var row: Dictionary = row_v as Dictionary
		var ship_id: String = row.ship_id as String
		if not known_owner_markers.has(ship_id):
			return "root_authority_foreign_owner"
		roots_by_ship[ship_id] = row
	if not _same_identity_set(roots_by_ship, known_owner_markers):
		return "root_authority_coverage_mismatch"
	# The home frame is the root of world-7 authority, never a movable child.
	# Enforce this before generic traversal so an otherwise acyclic connection
	# or free chain cannot reinterpret ship_start through a visited anchor.
	var home_root: Dictionary = roots_by_ship["ship_start"]
	if str(home_root.authority_kind) != "world_anchor" \
			or str(home_root.location_id) != "home" \
			or str(home_root.anchor_id) != "home-origin-v1":
		return "invalid_home_world_anchor"
	var current_location: String = str(world.current_location)
	if not current_location.is_empty():
		if not marker_owners.has(current_location):
			return "current_location_owner_missing"
		var current_owner_id: String = marker_owners[current_location] as String
		var current_root: Dictionary = roots_by_ship[current_owner_id]
		if str(current_root.authority_kind) != "world_anchor" \
				or str(current_root.location_id) != current_location \
				or str(current_root.anchor_id) != "visited-host-v1":
			return "current_location_anchor_mismatch"

	for ship_id_v in roots_by_ship:
		var ship_id: String = ship_id_v as String
		var root: Dictionary = roots_by_ship[ship_id]
		match root.authority_kind:
			"world_anchor":
				if mobile_parents.has(ship_id):
					return "connection_mobile_has_second_root_authority"
				var location_id: String = root.location_id as String
				var anchor_id: String = root.anchor_id as String
				if ship_id == "ship_start":
					if location_id != "home" or anchor_id != "home-origin-v1":
						return "invalid_home_world_anchor"
				else:
					var marker_id: String = known_owner_markers[ship_id] as String
					if marker_id.is_empty() or location_id != marker_id \
							or anchor_id != "visited-host-v1":
						return "invalid_visited_world_anchor"
			"connection":
				var connection_id: String = root.connection_id as String
				if not connections_by_id.has(connection_id):
					return "root_connection_missing"
				var connection: Dictionary = connections_by_id[connection_id]
				if str((connection.mobile as Dictionary).ship_id) != ship_id \
						or str(mobile_parents.get(ship_id, "")) != connection_id:
					return "root_connection_mobile_mismatch"
			"free":
				if mobile_parents.has(ship_id):
					return "connection_mobile_has_second_root_authority"
				var frame_ship_id: String = root.frame_ship_id as String
				if not roots_by_ship.has(frame_ship_id) \
						or str((roots_by_ship[frame_ship_id] as Dictionary).authority_kind) != "world_anchor":
					return "free_root_frame_not_world_anchor"
			_:
				return "invalid_root_authority_kind"

	for mobile_id_v in mobile_parents:
		var mobile_id: String = mobile_id_v as String
		if str((roots_by_ship[mobile_id] as Dictionary).authority_kind) != "connection":
			return "connection_mobile_root_mismatch"
	for ship_id_v in roots_by_ship:
		var chain_reason: String = _validate_root_chain(
			ship_id_v as String, roots_by_ship, connections_by_id)
		if not chain_reason.is_empty():
			return chain_reason

	var states_by_ship: Dictionary = {}
	for row_v in world.boarding_port_states_v1:
		var row: Dictionary = row_v as Dictionary
		var ship_id: String = row.ship_id as String
		if not known_owner_markers.has(ship_id):
			return "boarding_state_foreign_owner"
		if states_by_ship.has(ship_id):
			# WorldSnapshot rejects duplicate owner/endpoint identity. The current
			# production manifest owns one boarding endpoint per ship, so a second
			# endpoint is also an unsupported coverage shape.
			return "boarding_state_multiple_endpoints"
		states_by_ship[ship_id] = row
	if world.boarding_port_states_v1.size() \
			!= known_owner_markers.size() * CURRENT_BOARDING_ENDPOINTS_PER_OWNER:
		return "boarding_state_coverage_mismatch"
	if not _same_identity_set(states_by_ship, known_owner_markers):
		return "boarding_state_coverage_mismatch"
	for connection_v in connections_by_id.values():
		var connection: Dictionary = connection_v as Dictionary
		if str(connection.port_type) != "airlock":
			continue
		for side_name in ["host", "mobile"]:
			var side: Dictionary = connection[side_name] as Dictionary
			var state: Dictionary = states_by_ship[side.ship_id]
			if str(state.endpoint_id) != str(side.endpoint_id):
				return "boarding_state_connection_endpoint_mismatch"

	var pose: Dictionary = world.player_owner_pose_v1
	var pose_owner: String = pose.owner_ship_id as String
	if not known_owner_markers.has(pose_owner):
		return "player_pose_foreign_owner"
	if str(pose.location_kind) == "dock_threshold":
		var connection_id: String = pose.connection_id as String
		if not connections_by_id.has(connection_id):
			return "player_threshold_connection_missing"
		var connection: Dictionary = connections_by_id[connection_id]
		var mobile: Dictionary = connection.mobile as Dictionary
		if str(connection.port_type) != "airlock" \
				or str(mobile.ship_id) != pose_owner \
				or str(mobile.endpoint_id) != str(pose.endpoint_id):
			return "player_threshold_mobile_endpoint_mismatch"
	return ""


static func _validate_root_chain(
		start_ship_id: String,
		roots_by_ship: Dictionary,
		connections_by_id: Dictionary) -> String:
	var seen: Dictionary = {}
	var ship_id: String = start_ship_id
	while true:
		if seen.has(ship_id):
			return "root_authority_cycle"
		seen[ship_id] = true
		if not roots_by_ship.has(ship_id):
			return "root_authority_chain_missing_owner"
		var root: Dictionary = roots_by_ship[ship_id]
		match root.authority_kind:
			"world_anchor":
				return ""
			"connection":
				var connection_id: String = root.connection_id as String
				if not connections_by_id.has(connection_id):
					return "root_connection_missing"
				ship_id = str(((connections_by_id[connection_id] as Dictionary).host as Dictionary).ship_id)
			"free":
				ship_id = root.frame_ship_id as String
			_:
				return "invalid_root_authority_kind"
	return "root_authority_chain_unresolved"


static func _same_identity_set(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for identity in left:
		if not right.has(identity):
			return false
	return true


func _normalize_migrated_authority(
		home_threat_summary: Dictionary,
		combat_hotbar_present: bool,
		combat_hotbar_text: String) -> void:
	run_snapshot.inventory_summary = player_inventory.get_summary()
	run_snapshot.inventory_summary["threat_summary"] = home_threat_summary.duplicate(true)
	if combat_hotbar_present:
		run_snapshot.inventory_summary["combat_hotbar_text"] = combat_hotbar_text
	run_snapshot.material_summary = {}
	run_snapshot.recipe_knowledge_summary = recipe_knowledge_state.get_summary()
	var crafting_summary: Dictionary = crafting_state.get_summary()
	crafting_summary["physical_station_positions_v1"] = _station_position_summary()
	crafting_summary["field_crafting"] = (
		field_crafting_state.get_summary().get("field_crafting", {}) as Dictionary).duplicate(true)
	run_snapshot.crafting_summary = crafting_summary
	run_snapshot.component_placement_summary = (
		component_placements["ship_start"] as RefCounted).call("get_summary")
	world_snapshot.home_ship = run_snapshot.to_dict()
	world_snapshot.run_id = effective_run_id


func _station_position_summary() -> Dictionary:
	var owners: Array = []
	var ship_ids: Array = station_positions_by_owner.keys()
	ship_ids.sort()
	for ship_id_v in ship_ids:
		var ship_id: String = str(ship_id_v)
		var positions: Dictionary = station_positions_by_owner[ship_id_v]
		var stations: Array = []
		var kinds: Array = positions.keys()
		kinds.sort()
		for kind_v in kinds:
			var kind: String = str(kind_v)
			var position: Vector3 = positions[kind_v]
			var local_key: String = "%d,%d,%d" % [
				roundi(position.x * 1000.0), roundi(position.y * 1000.0),
				roundi(position.z * 1000.0)]
			stations.append({
				"station_kind": kind,
				"station_instance_id": "station:%s@%s" % [kind, local_key],
				"floor_slot_id": "floor@%s" % local_key,
				"local_position": [position.x, position.y, position.z],
			})
		owners.append({"ship_id": ship_id, "stations": stations})
	return {"schema": "physical-station-positions-1", "owners": owners}


func _materialize_station_positions(raw: Variant) -> String:
	if not raw is Dictionary:
		return "invalid_station_position_summary"
	var summary: Dictionary = raw
	if str(summary.get("schema", "")) != "physical-station-positions-1" \
			or not summary.get("owners", null) is Array:
		return "invalid_station_position_summary"
	for owner_v in summary.owners as Array:
		if not owner_v is Dictionary:
			return "invalid_station_position_summary"
		var owner: Dictionary = owner_v
		var ship_id: String = str(owner.get("ship_id", ""))
		if ship_id.is_empty() or station_positions_by_owner.has(ship_id) \
				or not owner.get("stations", null) is Array:
			return "invalid_station_position_summary"
		var positions: Dictionary = {}
		var seen_local_positions: Dictionary = {}
		for station_v in owner.stations as Array:
			if not station_v is Dictionary:
				return "invalid_station_position_summary"
			var station: Dictionary = station_v
			var kind: String = str(station.get("station_kind", ""))
			var station_id: String = str(station.get("station_instance_id", ""))
			var floor_slot_id: String = str(station.get("floor_slot_id", ""))
			var local_v: Variant = station.get("local_position", null)
			if kind.is_empty() or station_id.is_empty() or floor_slot_id.is_empty() \
					or positions.has(kind) \
					or not local_v is Array or (local_v as Array).size() != 3:
				return "invalid_station_position_summary"
			for coordinate in local_v as Array:
				if (typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT) \
						or not is_finite(float(coordinate)):
					return "invalid_station_position_summary"
			var position := Vector3(float(local_v[0]), float(local_v[1]), float(local_v[2]))
			var local_key: String = "%d,%d,%d" % [
				roundi(position.x * 1000.0), roundi(position.y * 1000.0),
				roundi(position.z * 1000.0)]
			if seen_local_positions.has(local_key) \
					or floor_slot_id != "floor@%s" % local_key:
				return "station_position_collision"
			if station_id != _station_id_for(kind, position):
				return "station_position_identity_mismatch"
			seen_local_positions[local_key] = true
			positions[kind] = position
		station_positions_by_owner[ship_id] = positions
	return ""


func _validate_station_position_closure() -> String:
	var known_ship_ids: Dictionary = {"ship_start": true}
	for ship in visited_ships.values():
		known_ship_ids[str((ship as RefCounted).get("ship_id"))] = true
	for ship_id_v in station_positions_by_owner:
		if not known_ship_ids.has(str(ship_id_v)):
			return "station_position_unknown_ship"
	var crafting_summary: Dictionary = crafting_state.get_summary()
	for station_v in (crafting_summary.get("physical_station_summaries", {}) as Dictionary).values():
		if not station_v is Dictionary:
			return "invalid_physical_station"
		var station: Dictionary = station_v
		var station_reason: String = _validate_station_identity(
			str(station.get("ship_id", "")), str(station.get("station_instance_id", "")),
			str(station.get("station_kind", "")))
		if not station_reason.is_empty():
			return station_reason
	for owner_v in (crafting_summary.get("craft_jobs_v1", {}) as Dictionary).get("owners", []) as Array:
		if not owner_v is Dictionary:
			return "invalid_craft_owner"
		var owner: Dictionary = owner_v
		var job_ids: Array = owner.get("job_ids", []) as Array
		var station_id: String = str(owner.get("station_instance_id", ""))
		if station_id.begins_with("legacy:"):
			continue
		var station_kind: String = ""
		for job_id_v in job_ids:
			for job_v in (crafting_summary.craft_jobs_v1 as Dictionary).get("jobs", []) as Array:
				if job_v is Dictionary and str((job_v as Dictionary).get("job_id", "")) == str(job_id_v):
					station_kind = str((job_v as Dictionary).get("station_kind", ""))
					break
			if not station_kind.is_empty():
				break
		if station_kind.is_empty():
			var station_state = crafting_state.get_station_instance(str(owner.get("ship_id", "")), station_id)
			station_kind = str(station_state.get("station_kind")) if station_state != null else ""
		var owner_reason: String = _validate_station_identity(
			str(owner.get("ship_id", "")), station_id, station_kind)
		if not owner_reason.is_empty():
			return owner_reason
	return ""


func _validate_station_identity(ship_id: String, station_id: String, kind: String) -> String:
	if station_id.begins_with("legacy:"):
		return ""
	if ship_id.is_empty() or kind.is_empty() or not station_positions_by_owner.has(ship_id):
		return "missing_station_position_owner"
	var positions: Dictionary = station_positions_by_owner[ship_id]
	if not positions.has(kind) or station_id != _station_id_for(kind, positions[kind] as Vector3):
		return "station_position_identity_mismatch"
	return ""


static func _station_id_for(kind: String, position: Vector3) -> String:
	return "station:%s@%d,%d,%d" % [
		kind,
		roundi(position.x * 1000.0),
		roundi(position.y * 1000.0),
		roundi(position.z * 1000.0),
	]


func _ship_id_exists(ship_id: String) -> bool:
	for existing in visited_ships.values():
		if str((existing as RefCounted).get("ship_id")) == ship_id:
			return true
	return false


func _validate_conservation() -> String:
	var spendable_lots: Dictionary = {}
	var reason: String = _collect_physical_lots(spendable_lots)
	if not reason.is_empty():
		return reason

	var jobs_by_id: Dictionary = {}
	var escrow_lots: Dictionary = {}
	var craft_summary: Dictionary = crafting_state.get_summary()
	reason = _collect_jobs(craft_summary.get("craft_jobs_v1", {}), jobs_by_id, escrow_lots)
	if not reason.is_empty():
		return reason
	var field_summary: Dictionary = field_crafting_state.get_summary().get("field_crafting", {})
	var field_history_by_id: Dictionary = {}
	for history_v in field_crafting_state.get_receipt_history_v1():
		if not history_v is Dictionary:
			return "invalid_field_receipt_history"
		var history: Dictionary = history_v
		var history_id: String = str(history.get("receipt_id", ""))
		if history_id.is_empty() or field_history_by_id.has(history_id):
			return "invalid_field_receipt_history"
		field_history_by_id[history_id] = history
	reason = _collect_jobs(field_summary.get("craft_jobs_v1", {}), jobs_by_id, escrow_lots)
	if not reason.is_empty():
		return reason
	for lot_id in escrow_lots:
		if spendable_lots.has(lot_id):
			return "escrow_lot_is_spendable"

	var receipts: Dictionary = {}
	var receipt_lots: Dictionary = {}
	var pending_remaining_lots: Dictionary = {}
	var stores: Dictionary = {}
	reason = _collect_pending_store(
		world_snapshot.home_pending_outputs_v1, receipts, receipt_lots,
		pending_remaining_lots, stores)
	if not reason.is_empty():
		return reason
	for raw_ship_v in world_snapshot.visited_ships.values():
		var raw_ship: Dictionary = raw_ship_v as Dictionary
		reason = _collect_pending_store(
			raw_ship.get("pending_outputs_v1", {}), receipts, receipt_lots,
			pending_remaining_lots, stores)
		if not reason.is_empty():
			return reason
	for lot_id in pending_remaining_lots:
		if spendable_lots.has(lot_id) or escrow_lots.has(lot_id):
			return "pending_lot_has_second_authority"
	for receipt_id in receipts:
		var link_reason: String = _validate_receipt_link(
			receipts[receipt_id], jobs_by_id, field_history_by_id)
		if not link_reason.is_empty():
			return link_reason
	for job_id in jobs_by_id:
		var job: Dictionary = jobs_by_id[job_id]
		var state: String = str(job.get("state", ""))
		var receipt_id: String = str(job.get("output_receipt_id", ""))
		if state == "output_ready" and receipts.has(receipt_id):
			return "unpublished_output_has_receipt"
		if state == "collected" and (receipt_id.is_empty() or not receipts.has(receipt_id)):
			return "published_output_missing_receipt"

	var pending: Dictionary = field_summary.get("field_pending_v1", {})
	var active_field_receipt: String = str(pending.get("active_receipt_id", ""))
	var pinned_ship_id: String = str(pending.get("pinned_destination_ship_id", ""))
	if not active_field_receipt.is_empty():
		if pinned_ship_id.is_empty() or not stores.has(pinned_ship_id):
			return "field_pin_missing_destination_store"
		if receipts.has(active_field_receipt):
			return "unpublished_field_output_has_receipt"
	return ""


func _collect_physical_lots(seen: Dictionary) -> String:
	var summaries: Array = [
		player_inventory.get_summary(),
		world_snapshot.home_ship_inventory,
		world_snapshot.home_ship_carts,
		world_snapshot.home_floor_drops_v1,
		player_equipment.get_summary() if player_equipment != null else {},
		run_snapshot.component_placement_summary,
	]
	for raw_ship_v in world_snapshot.visited_ships.values():
		var raw_ship: Dictionary = raw_ship_v as Dictionary
		for key in ["inventory", "carts", "floor_drops_v1", "component_placement"]:
			if raw_ship.has(key):
				summaries.append(raw_ship[key])
	for summary in summaries:
		var lots: Array = []
		_find_physical_lots(summary, lots)
		for lot_v in lots:
			var lot: Dictionary = lot_v as Dictionary
			var lot_id: String = str(lot.get("lot_id", ""))
			if lot_id.is_empty() or seen.has(lot_id):
				return "duplicate_physical_lot"
			seen[lot_id] = true
	return ""


func _find_physical_lots(value: Variant, out: Array) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		if dict.has("item_lots_v1") and dict.item_lots_v1 is Dictionary:
			for lot_v in (dict.item_lots_v1 as Dictionary).get("lots", []) as Array:
				out.append(lot_v)
		if dict.has("slot_lots_v1") and dict.slot_lots_v1 is Dictionary:
			for lot_v in (dict.slot_lots_v1 as Dictionary).values():
				out.append(lot_v)
		# A vacant component slot keeps the last component descriptor so the UI
		# can address the stable mount, but its lot authority moved to inventory
		# at dismount. Count source_lot only while the component is mounted.
		if dict.has("source_lot") and dict.source_lot is Dictionary \
				and bool(dict.get("mounted", true)):
			out.append(dict.source_lot)
		for key in dict:
			if str(key) not in ["item_lots_v1", "slot_lots_v1", "source_lot"]:
				_find_physical_lots(dict[key], out)
	elif value is Array:
		for item in value as Array:
			_find_physical_lots(item, out)


func _collect_jobs(
		jobs_summary: Variant,
		jobs_by_id: Dictionary,
		escrow_lots: Dictionary) -> String:
	if not jobs_summary is Dictionary:
		return "invalid_job_summary"
	for job_v in (jobs_summary as Dictionary).get("jobs", []) as Array:
		if not job_v is Dictionary:
			return "invalid_job_summary"
		var job: Dictionary = job_v
		var job_id: String = str(job.get("job_id", ""))
		if job_id.is_empty() or jobs_by_id.has(job_id):
			return "duplicate_job_id"
		jobs_by_id[job_id] = job
		if str(job.get("state", "")) in ["queued", "blocked"]:
			for lot_v in job.get("ingredient_escrow", []) as Array:
				var lot_id: String = str((lot_v as Dictionary).get("lot_id", ""))
				if lot_id.is_empty() or escrow_lots.has(lot_id):
					return "duplicate_escrow_lot"
				escrow_lots[lot_id] = job_id
	return ""


func _collect_pending_store(
		store_v: Variant,
		receipts: Dictionary,
		receipt_lots: Dictionary,
		pending_remaining_lots: Dictionary,
		stores: Dictionary) -> String:
	if not store_v is Dictionary:
		return "missing_pending_store"
	var store: Dictionary = store_v
	var ship_id: String = str(store.get("ship_id", ""))
	if ship_id.is_empty() or stores.has(ship_id):
		return "duplicate_pending_store_owner"
	stores[ship_id] = store
	for record_v in store.get("records", []) as Array:
		var record: Dictionary = record_v as Dictionary
		var receipt_id: String = str(record.get("receipt_id", ""))
		if receipt_id.is_empty() or receipts.has(receipt_id):
			return "duplicate_receipt_id"
		receipts[receipt_id] = record
		for lot_v in record.get("original_lots", []) as Array:
			var lot_id: String = str((lot_v as Dictionary).get("lot_id", ""))
			if lot_id.is_empty() or receipt_lots.has(lot_id):
				return "duplicate_receipt_lot"
			receipt_lots[lot_id] = receipt_id
		for lot_v in record.get("remaining_lots", []) as Array:
			var remaining_id: String = str((lot_v as Dictionary).get("lot_id", ""))
			if remaining_id.is_empty() or pending_remaining_lots.has(remaining_id):
				return "duplicate_pending_lot"
			pending_remaining_lots[remaining_id] = receipt_id
	return ""


func _validate_receipt_link(
		record: Dictionary,
		jobs_by_id: Dictionary,
		field_history_by_id: Dictionary) -> String:
	var producer_kind: String = str(record.get("producer_kind", ""))
	var producer_id: String = str(record.get("producer_id", ""))
	var receipt_id: String = str(record.get("receipt_id", ""))
	var purpose: String = str(record.get("purpose", ""))
	if producer_kind == "craft_job":
		if not jobs_by_id.has(producer_id):
			return "orphan_craft_receipt"
		var job: Dictionary = jobs_by_id[producer_id]
		if str(record.get("ship_id", "")) != str(job.get("ship_id", "")) \
				or str(record.get("station_instance_id", "")) != str(job.get("station_instance_id", "")):
			return "craft_receipt_owner_mismatch"
		if purpose == "output":
			if receipt_id != "%s/output" % producer_id:
				return "craft_output_receipt_id_mismatch"
			if str(job.get("state", "")) != "collected":
				return "craft_output_job_state_mismatch"
			if str(job.get("output_receipt_id", "")) != receipt_id:
				return "craft_output_job_receipt_mismatch"
			if not _canonical_json_equal(
					job.get("output_lots", []), record.get("original_lots", [])):
				return "craft_output_receipt_mismatch"
		elif purpose == "refund":
			if receipt_id != "%s/refund" % producer_id \
					or str(job.get("state", "")) != "cancelled" \
					or str(record.get("source_holder_id", "")) != str(job.get("source_holder_id", "")) \
					or (job.get("refunded_lots_v1", []) as Array).is_empty() \
					or not _canonical_json_equal(
						job.get("refunded_lots_v1", []), record.get("original_lots", [])):
				return "craft_refund_receipt_mismatch"
		else:
			return "invalid_craft_receipt_purpose"
		return ""
	if producer_kind == "field_craft":
		if purpose != "output" or receipt_id != "%s/output" % producer_id \
				or str(record.get("station_instance_id", "")) != "field_crafting" \
				or not str(record.get("source_holder_id", "")).is_empty():
			return "field_receipt_mismatch"
		var field_history_v: Variant = field_history_by_id.get(receipt_id, null)
		if not field_history_v is Dictionary:
			return "field_receipt_missing_history"
		var field_history: Dictionary = field_history_v
		if str(record.get("ship_id", "")) != str(field_history.get("destination_ship_id", "")) \
				or not _canonical_json_equal(
					record.get("original_lots", []), field_history.get("original_lots", [])):
			return "field_receipt_history_mismatch"
		return ""
	return "unknown_receipt_producer"


static func _canonical_json_equal(left: Variant, right: Variant) -> bool:
	# Persistence authority is JSON. Packed arrays and ordinary Arrays encode the
	# same canonical lot identity. JSON also has one number domain, so an integer
	# producer value and the equivalent normalized float must remain identical.
	var left_text: String = JSON.stringify(left, "", true, true)
	var right_text: String = JSON.stringify(right, "", true, true)
	var left_json := JSON.new()
	var right_json := JSON.new()
	if left_json.parse(left_text) != OK or right_json.parse(right_text) != OK:
		return false
	return left_json.data == right_json.data
