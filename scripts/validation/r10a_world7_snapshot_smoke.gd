extends SceneTree

## Pure-model RED/GREEN coverage for the current world-7 authority envelope.
## Marker: R10-A WORLD7 SNAPSHOT PASS schema=true graph=true values=true

const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const SaveRestoreCandidateScript := preload("res://scripts/systems/save_restore_candidate.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")

const WORLD_7: String = "world-7"
const RUN_7: String = "gate2-current-run-7"


func _initialize() -> void:
	var godot_version: String = Engine.get_version_info()["string"]
	var current: Dictionary = _valid_world_dict(godot_version)
	if current.has("_fixture_error"):
		_fail(str(current._fixture_error))
		return
	if current.is_empty():
		_fail("could not construct current fixture")
		return
	if not _validate_roundtrip_and_legacy_presence(current, godot_version):
		return
	if not _validate_exact_rows_and_values(current, godot_version):
		return
	if not _validate_candidate_graph(current, godot_version):
		return
	print("R10-A WORLD7 SNAPSHOT PASS schema=true graph=true values=true")
	quit(0)


func _validate_roundtrip_and_legacy_presence(
		current: Dictionary, godot_version: String) -> bool:
	if WorldSnapshotScript.WORLD_SLICE_VERSION != WORLD_7:
		return _fail_bool("world-7 is not current")
	var decoded = WorldSnapshotScript.from_dict(current, WORLD_7, godot_version)
	if decoded == null:
		return _fail_bool("valid world-7 fixture did not decode")
	var encoded: Dictionary = decoded.to_dict()
	for required_key in [
		"dock_connections_v1", "player_owner_pose_v1",
		"boarding_port_states_v1", "ship_root_authorities_v1", "aboard_ship_id",
	]:
		if not encoded.has(required_key):
			return _fail_bool("encoder omitted %s" % required_key)
	for forbidden_key in ["dock_edges", "player_position_in_ship", "opened_ports"]:
		if encoded.has(forbidden_key):
			return _fail_bool("encoder retained %s" % forbidden_key)
		for forbidden_value in [null, [], {}, 0, ""]:
			var mutant: Dictionary = current.duplicate(true)
			mutant[forbidden_key] = forbidden_value
			if WorldSnapshotScript.from_dict(mutant, WORLD_7, godot_version) != null:
				return _fail_bool("decoder accepted legacy %s presence" % forbidden_key)
	var accepted_pose: Array = current.player_owner_pose_v1.local_position
	if encoded.player_owner_pose_v1.local_position != accepted_pose:
		return _fail_bool("owner-local pose array was normalized during round-trip")
	var json_roundtrip_v: Variant = JSON.parse_string(JSON.stringify(encoded, "", true, true))
	if not json_roundtrip_v is Dictionary \
			or WorldSnapshotScript.from_dict(json_roundtrip_v, WORLD_7, godot_version) == null:
		return _fail_bool("valid JSON number representation did not round-trip")
	return true


func _validate_exact_rows_and_values(
		current: Dictionary, godot_version: String) -> bool:
	var row_mutations: Array[Dictionary] = []
	var extra_connection: Dictionary = current.duplicate(true)
	extra_connection.dock_connections_v1[0]["legacy"] = true
	row_mutations.append({"label": "connection extra key", "world": extra_connection})
	var missing_endpoint: Dictionary = current.duplicate(true)
	missing_endpoint.dock_connections_v1[0].mobile.erase("endpoint_id")
	row_mutations.append({"label": "airlock endpoint missing", "world": missing_endpoint})
	var coerced_slot: Dictionary = current.duplicate(true)
	coerced_slot.dock_connections_v1[0]["slot_index"] = "-1"
	row_mutations.append({"label": "coerced slot", "world": coerced_slot})
	var fractional_slot: Dictionary = current.duplicate(true)
	fractional_slot.dock_connections_v1[0]["slot_index"] = -1.5
	row_mutations.append({"label": "fractional slot", "world": fractional_slot})
	var coerced_barrier: Dictionary = current.duplicate(true)
	coerced_barrier.boarding_port_states_v1[0]["barrier_open"] = 0
	row_mutations.append({"label": "coerced barrier", "world": coerced_barrier})
	var boolean_coordinate: Dictionary = current.duplicate(true)
	boolean_coordinate.player_owner_pose_v1.local_position[1] = false
	row_mutations.append({"label": "boolean coordinate", "world": boolean_coordinate})
	var nonfinite_coordinate: Dictionary = current.duplicate(true)
	nonfinite_coordinate.player_owner_pose_v1.local_position[1] = INF
	row_mutations.append({"label": "nonfinite coordinate", "world": nonfinite_coordinate})
	var wrong_owner: Dictionary = current.duplicate(true)
	wrong_owner.player_owner_pose_v1.owner_ship_id = "lifeboat"
	row_mutations.append({"label": "owner aboard mismatch", "world": wrong_owner})
	var bad_interior_reference: Dictionary = current.duplicate(true)
	bad_interior_reference.player_owner_pose_v1.connection_id = "dock:home-lifeboat"
	row_mutations.append({"label": "interior connection reference", "world": bad_interior_reference})
	var bad_root_keys: Dictionary = current.duplicate(true)
	bad_root_keys.ship_root_authorities_v1[0]["local_transform"] = _identity_transform()
	row_mutations.append({"label": "root union extra key", "world": bad_root_keys})
	for case_v in row_mutations:
		var case: Dictionary = case_v
		if WorldSnapshotScript.from_dict(case.world, WORLD_7, godot_version) != null:
			return _fail_bool("accepted malformed %s" % str(case.label))

	var union_world: Dictionary = current.duplicate(true)
	union_world.dock_connections_v1.append({
		"connection_id": "dock:away-hangar-home",
		"port_type": "hangar",
		"slot_index": 0,
		"host": {"ship_id": "ship-away", "attachment_id": "hangar-slot:0"},
		"mobile": {"ship_id": "ship_start", "attachment_id": "ship-root"},
	})
	var cardinal_transforms: Array = [
		[1, 0, 0, 0, 1, 0, 0, 0, 1, 12.25, 0, -4.5],
		[0, 0, -1, 0, 1, 0, 1, 0, 0, 12.25, 0, -4.5],
		[-1, 0, 0, 0, 1, 0, 0, 0, -1, 12.25, 0, -4.5],
		[0, 0, 1, 0, 1, 0, -1, 0, 0, 12.25, 0, -4.5],
	]
	var accepted_transform: Array = cardinal_transforms[1]
	var free_source: Dictionary = _row_for_ship(
		union_world.ship_root_authorities_v1, "ship-away")
	free_source.clear()
	free_source.merge({
		"ship_id": "ship-away", "authority_kind": "free",
		"frame_ship_id": "ship_start", "local_transform": accepted_transform.duplicate(),
	})
	for cardinal_v in cardinal_transforms:
		var cardinal: Array = cardinal_v as Array
		var cardinal_world: Dictionary = union_world.duplicate(true)
		_row_for_ship(cardinal_world.ship_root_authorities_v1, "ship-away")[
			"local_transform"] = cardinal.duplicate()
		var cardinal_decoded = WorldSnapshotScript.from_dict(
			cardinal_world, WORLD_7, godot_version)
		if cardinal_decoded == null:
			return _fail_bool("strict tagged-union syntax rejected cardinal %s" % str(cardinal))
		var free_row: Dictionary = _row_for_ship(
			cardinal_decoded.to_dict().ship_root_authorities_v1, "ship-away")
		if free_row.get("local_transform", []) != cardinal:
			return _fail_bool("accepted cardinal free transform array was normalized")

	for invalid_transform in [
		[1, 0, 0, 0, 1, 0, 0, 0, 1, INF, 0, 0],
		[1, 0, 0, 0, 1, 0, 0, 0, 0, 12, 0, -4],
		[2, 0, 0, 0, 1, 0, 0, 0, 1, 12, 0, -4],
		[1, 0.01, 0, 0, 1, 0, 0, 0, 1, 12, 0, -4],
		[-1, 0, 0, 0, 1, 0, 0, 0, 1, 12, 0, -4],
		[0.999999999, 0, 0, 0, 1, 0, 0, 0, 1, 12, 0, -4],
		[1, 0, 0, 0, 1, 0, 0, 0, 1, 1.0e100, 0, -4],
	]:
		var bad_transform: Dictionary = union_world.duplicate(true)
		_row_for_ship(bad_transform.ship_root_authorities_v1, "ship-away")[
			"local_transform"] = invalid_transform
		if WorldSnapshotScript.from_dict(bad_transform, WORLD_7, godot_version) != null:
			return _fail_bool("accepted unsupported free-root transform %s" % str(invalid_transform))
	var duplicate_root: Dictionary = current.duplicate(true)
	duplicate_root.ship_root_authorities_v1.append(
		duplicate_root.ship_root_authorities_v1[0].duplicate(true))
	if WorldSnapshotScript.from_dict(duplicate_root, WORLD_7, godot_version) != null:
		return _fail_bool("accepted duplicate root authority")
	return true


func _validate_candidate_graph(current: Dictionary, godot_version: String) -> bool:
	var decoded = WorldSnapshotScript.from_dict(current, WORLD_7, godot_version)
	if decoded == null:
		return _fail_bool("candidate baseline failed world decoding")
	var markers: Dictionary = {
		"ship_start": "",
		"lifeboat": "",
		"ship-away": "marker-away",
	}
	if not SaveRestoreCandidateScript.validate_world_authority_graph(decoded, markers).is_empty():
		return _fail_bool("valid detached authority graph rejected")

	var home_connection_dict: Dictionary = current.duplicate(true)
	home_connection_dict.dock_connections_v1.append(
		_hangar_connection("dock:away-home", "ship-away", "ship_start", 0))
	var home_root: Dictionary = _row_for_ship(
		home_connection_dict.ship_root_authorities_v1, "ship_start")
	home_root.clear()
	home_root.merge({
		"ship_id": "ship_start", "authority_kind": "connection",
		"connection_id": "dock:away-home",
	})
	var home_connection = WorldSnapshotScript.from_dict(
		home_connection_dict, WORLD_7, godot_version)
	if home_connection == null:
		return _fail_bool("acyclic home-connection fixture failed syntax")
	var home_connection_reason: String = SaveRestoreCandidateScript \
		.validate_world_authority_graph(home_connection, markers)
	if home_connection_reason != "invalid_home_world_anchor":
		return _fail_bool("connection-owned home lost exact rejection: %s" % home_connection_reason)

	var home_free_dict: Dictionary = current.duplicate(true)
	var home_free_root: Dictionary = _row_for_ship(
		home_free_dict.ship_root_authorities_v1, "ship_start")
	home_free_root.clear()
	home_free_root.merge({
		"ship_id": "ship_start", "authority_kind": "free",
		"frame_ship_id": "ship-away", "local_transform": _identity_transform(),
	})
	var home_free = WorldSnapshotScript.from_dict(home_free_dict, WORLD_7, godot_version)
	if home_free == null:
		return _fail_bool("acyclic home-free fixture failed syntax")
	var home_free_reason: String = SaveRestoreCandidateScript.validate_world_authority_graph(
		home_free, markers)
	if home_free_reason != "invalid_home_world_anchor":
		return _fail_bool("free home lost exact rejection: %s" % home_free_reason)
	var away_current_dict: Dictionary = current.duplicate(true)
	away_current_dict.current_location = "marker-away"
	away_current_dict.visited_ships["marker-away"]["combat"] = (
		away_current_dict.home_ship.inventory_summary.threat_summary as Dictionary).duplicate(true)
	var away_current = WorldSnapshotScript.from_dict(
		away_current_dict, WORLD_7, godot_version)
	if away_current == null \
			or not SaveRestoreCandidateScript.validate_world_authority_graph(
				away_current, markers).is_empty():
		return _fail_bool("valid away-current world-anchor authority rejected")

	var missing_current_dict: Dictionary = current.duplicate(true)
	missing_current_dict.current_location = "marker-missing"
	if WorldSnapshotScript.from_dict(
			missing_current_dict, WORLD_7, godot_version) != null:
		return _fail_bool("nonempty current_location without retained owner accepted")
	var duplicate_owner_dict: Dictionary = current.duplicate(true)
	var duplicate_owner_summary: Dictionary = (
		duplicate_owner_dict.visited_ships["marker-away"] as Dictionary).duplicate(true)
	duplicate_owner_summary.marker_id = "marker-duplicate"
	duplicate_owner_dict.visited_ships["marker-duplicate"] = duplicate_owner_summary
	if WorldSnapshotScript.from_dict(
			duplicate_owner_dict, WORLD_7, godot_version) != null:
		return _fail_bool("duplicate retained ship identity accepted")

	var mismatched_current_dict: Dictionary = current.duplicate(true)
	mismatched_current_dict.current_location = "marker-away"
	mismatched_current_dict.visited_ships["marker-away"]["combat"] = (
		mismatched_current_dict.home_ship.inventory_summary.threat_summary as Dictionary).duplicate(true)
	var current_root: Dictionary = _row_for_ship(
		mismatched_current_dict.ship_root_authorities_v1, "ship-away")
	current_root.clear()
	current_root.merge({
		"ship_id": "ship-away", "authority_kind": "free",
		"frame_ship_id": "ship_start", "local_transform": _identity_transform(),
	})
	var mismatched_current = WorldSnapshotScript.from_dict(
		mismatched_current_dict, WORLD_7, godot_version)
	if mismatched_current == null:
		return _fail_bool("current-anchor mismatch fixture failed syntax")
	var current_anchor_reason: String = SaveRestoreCandidateScript \
		.validate_world_authority_graph(mismatched_current, markers)
	if current_anchor_reason != "current_location_anchor_mismatch":
		return _fail_bool("current anchor mismatch lost exact rejection: %s" % current_anchor_reason)

	var hangar_dict: Dictionary = current.duplicate(true)
	hangar_dict.dock_connections_v1 = [
		_hangar_connection("dock:home-lifeboat", "ship_start", "lifeboat", 0),
	]
	var hangar = WorldSnapshotScript.from_dict(hangar_dict, WORLD_7, godot_version)
	if hangar == null \
			or not SaveRestoreCandidateScript.validate_world_authority_graph(
				hangar, markers).is_empty():
		return _fail_bool("valid hangar attachment authority graph rejected")

	var free_dict: Dictionary = current.duplicate(true)
	free_dict.dock_connections_v1 = []
	var lifeboat_root: Dictionary = _row_for_ship(
		free_dict.ship_root_authorities_v1, "lifeboat")
	lifeboat_root.clear()
	lifeboat_root.merge({
		"ship_id": "lifeboat", "authority_kind": "free",
		"frame_ship_id": "ship_start", "local_transform": _identity_transform(),
	})
	var free = WorldSnapshotScript.from_dict(free_dict, WORLD_7, godot_version)
	if free == null \
			or not SaveRestoreCandidateScript.validate_world_authority_graph(
				free, markers).is_empty():
		return _fail_bool("valid detached free-root authority graph rejected")

	var threshold_dict: Dictionary = current.duplicate(true)
	threshold_dict.aboard_ship_id = "lifeboat"
	threshold_dict.player_owner_pose_v1 = {
		"owner_ship_id": "lifeboat", "location_kind": "dock_threshold",
		"local_position": [0.0, 0.55, 0.0],
		"connection_id": "dock:home-lifeboat", "endpoint_id": "boarding:lifeboat",
	}
	var threshold = WorldSnapshotScript.from_dict(
		threshold_dict, WORLD_7, godot_version)
	if threshold == null \
			or not SaveRestoreCandidateScript.validate_world_authority_graph(
				threshold, markers).is_empty():
		return _fail_bool("valid mobile threshold authority rejected")

	var missing_root = WorldSnapshotScript.from_dict(current.duplicate(true), WORLD_7, godot_version)
	missing_root.ship_root_authorities_v1.pop_back()
	if SaveRestoreCandidateScript.validate_world_authority_graph(missing_root, markers).is_empty():
		return _fail_bool("missing known-owner root authority accepted")
	var missing_state = WorldSnapshotScript.from_dict(current.duplicate(true), WORLD_7, godot_version)
	missing_state.boarding_port_states_v1.pop_back()
	if SaveRestoreCandidateScript.validate_world_authority_graph(missing_state, markers).is_empty():
		return _fail_bool("missing known-owner endpoint state accepted")
	var foreign_state = WorldSnapshotScript.from_dict(current.duplicate(true), WORLD_7, godot_version)
	foreign_state.boarding_port_states_v1[0].ship_id = "hallucinated-owner"
	if SaveRestoreCandidateScript.validate_world_authority_graph(foreign_state, markers).is_empty():
		return _fail_bool("foreign endpoint-state owner accepted")

	var bad_threshold = WorldSnapshotScript.from_dict(current.duplicate(true), WORLD_7, godot_version)
	bad_threshold.aboard_ship_id = "lifeboat"
	bad_threshold.player_owner_pose_v1 = {
		"owner_ship_id": "lifeboat", "location_kind": "dock_threshold",
		"local_position": [0.0, 0.55, 0.0],
		"connection_id": "dock:home-lifeboat", "endpoint_id": "boarding:home",
	}
	if SaveRestoreCandidateScript.validate_world_authority_graph(bad_threshold, markers).is_empty():
		return _fail_bool("threshold pose accepted host endpoint instead of mobile endpoint")

	var cycle_dict: Dictionary = current.duplicate(true)
	cycle_dict.dock_connections_v1 = [
		_hangar_connection("dock:away-lifeboat", "ship-away", "lifeboat", 0),
		_hangar_connection("dock:lifeboat-away", "lifeboat", "ship-away", 0),
	]
	cycle_dict.ship_root_authorities_v1 = [
		{"ship_id": "ship_start", "authority_kind": "world_anchor", "location_id": "home", "anchor_id": "home-origin-v1"},
		{"ship_id": "lifeboat", "authority_kind": "connection", "connection_id": "dock:away-lifeboat"},
		{"ship_id": "ship-away", "authority_kind": "connection", "connection_id": "dock:lifeboat-away"},
	]
	var cycle = WorldSnapshotScript.from_dict(cycle_dict, WORLD_7, godot_version)
	if cycle == null:
		return _fail_bool("cycle fixture failed syntax before graph validation")
	var cycle_reason: String = SaveRestoreCandidateScript.validate_world_authority_graph(
		cycle, markers)
	if cycle_reason != "root_authority_cycle":
		return _fail_bool("cyclic parent graph lost exact rejection: %s" % cycle_reason)
	return true


func _valid_world_dict(godot_version: String) -> Dictionary:
	var source_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/feature_completion/p10_world_v5_transactional.json"))
	if not source_v is Dictionary:
		return {}
	var source: Dictionary = (source_v as Dictionary).duplicate(true)
	source["godot_version"] = godot_version
	source.home_ship["godot_version"] = godot_version
	var migrated: Dictionary = SaveMigrationServiceScript.new().migrate_world(source)
	if not migrated.get("dict", null) is Dictionary:
		return {"_fixture_error": "world fixture migration failed: %s" % str(migrated)}
	var world: Dictionary = (migrated.dict as Dictionary).duplicate(true)
	var run = RunSnapshotScript.new()
	run.slice_version = RUN_7
	run.godot_version = godot_version
	run.run_id = str(world.get("run_id", "fixture-world"))
	run.recipe_knowledge_summary["owner_id"] = "player:%s" % run.run_id
	var threat_manager = ThreatManagerScript.new()
	run.inventory_summary = {
		"tools": [],
		"combat_hotbar_text": "",
		"threat_summary": threat_manager.get_summary(),
	}
	threat_manager.free()
	world["home_ship"] = run.to_dict()
	world["slice_version"] = WORLD_7
	world["godot_version"] = godot_version
	world.erase("dock_edges")
	world.erase("player_position_in_ship")
	world.erase("opened_ports")
	world["dock_connections_v1"] = [
		_airlock_connection("dock:home-lifeboat", "ship_start", "lifeboat"),
	]
	world["player_owner_pose_v1"] = {
		"owner_ship_id": "ship_start", "location_kind": "interior",
		"local_position": [1.25, -2.5, 3.75], "connection_id": "", "endpoint_id": "",
	}
	world["boarding_port_states_v1"] = [
		{"ship_id": "lifeboat", "endpoint_id": "boarding:lifeboat", "barrier_open": false},
		{"ship_id": "ship-away", "endpoint_id": "boarding:ship-away", "barrier_open": true},
		{"ship_id": "ship_start", "endpoint_id": "boarding:ship_start", "barrier_open": false},
	]
	world["ship_root_authorities_v1"] = [
		{"ship_id": "lifeboat", "authority_kind": "connection", "connection_id": "dock:home-lifeboat"},
		{"ship_id": "ship-away", "authority_kind": "world_anchor", "location_id": "marker-away", "anchor_id": "visited-host-v1"},
		{"ship_id": "ship_start", "authority_kind": "world_anchor", "location_id": "home", "anchor_id": "home-origin-v1"},
	]
	world["aboard_ship_id"] = "ship_start"
	return world


func _airlock_connection(id: String, host_id: String, mobile_id: String) -> Dictionary:
	return {
		"connection_id": id, "port_type": "airlock", "slot_index": -1,
		"host": {
			"ship_id": host_id, "endpoint_id": "boarding:%s" % host_id,
			"port_id": "airlock:%s" % host_id,
		},
		"mobile": {
			"ship_id": mobile_id, "endpoint_id": "boarding:%s" % mobile_id,
			"port_id": "airlock:%s" % mobile_id,
		},
	}


func _hangar_connection(
		id: String, host_id: String, mobile_id: String, slot_index: int) -> Dictionary:
	return {
		"connection_id": id, "port_type": "hangar", "slot_index": slot_index,
		"host": {"ship_id": host_id, "attachment_id": "hangar-slot:%d" % slot_index},
		"mobile": {"ship_id": mobile_id, "attachment_id": "ship-root"},
	}


func _identity_transform() -> Array:
	return [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]


func _row_for_ship(rows: Array, ship_id: String) -> Dictionary:
	for row_v in rows:
		if row_v is Dictionary and str((row_v as Dictionary).get("ship_id", "")) == ship_id:
			return row_v as Dictionary
	return {}


func _fail_bool(reason: String) -> bool:
	_fail(reason)
	return false


func _fail(reason: String) -> void:
	push_error("R10-A WORLD7 SNAPSHOT FAIL reason=%s" % reason)
	quit(1)
