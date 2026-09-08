extends SceneTree

## Current run-7/world-7 module-integrity admission and exact staged application.
## Marker: R10-A INTEGRITY ADMISSION PASS run=true world=true syntax=true apply=true exact=true

const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

const RUN_7: String = "gate2-current-run-7"
const WORLD_7: String = "world-7"
const LARGE_EXACT_FLOAT_INTEGER: int = 9007199254740994
const LARGE_INEXACT_FLOAT_INTEGER: int = 9007199254740993
const INT64_MAX_VALUE: int = 9223372036854775807


func _initialize() -> void:
	var godot_version: String = Engine.get_version_info()["string"]
	if not _validate_pure_syntax_and_run(godot_version):
		return
	if not _validate_full_world(godot_version):
		return
	if not _validate_descriptor_application():
		return
	print("R10-A INTEGRITY ADMISSION PASS run=true world=true syntax=true apply=true exact=true")
	quit(0)


func _validate_pure_syntax_and_run(godot_version: String) -> bool:
	var exact_row: Dictionary = _valid_row("edge/a", "wall_straight_1x1", "bridge")
	var exact_summary: Dictionary = {
		"schema": "module_integrity_map_v1",
		"deltas": [exact_row.duplicate(true)],
		"registered": 2.0,
	}
	var accepted: Dictionary = ModuleIntegrityMapScript.validate_current_summary(exact_summary)
	if not bool(accepted.get("ok", false)) or not bool(accepted.get("initialized", false)) \
			or accepted.get("summary", null) != exact_summary:
		return _fail_bool("valid syntax was rejected or normalized: %s" % str(accepted))
	var serialized_v: Variant = JSON.parse_string(JSON.stringify(exact_summary, "", true, true))
	var serialized_result: Dictionary = ModuleIntegrityMapScript.validate_current_summary(serialized_v)
	if not bool(serialized_result.get("ok", false)) \
			or serialized_result.get("summary", null) != serialized_v:
		return _fail_bool("valid JSON round-trip was rejected or normalized")
	var empty_result: Dictionary = ModuleIntegrityMapScript.validate_current_summary({})
	if not bool(empty_result.get("ok", false)) or bool(empty_result.get("initialized", true)):
		return _fail_bool("empty summary did not remain uninitialized")
	var repaired: Dictionary = {
		"schema": "module_integrity_map_v1", "deltas": [], "registered": 2,
	}
	var repaired_result: Dictionary = ModuleIntegrityMapScript.validate_current_summary(repaired)
	if not bool(repaired_result.get("ok", false)) \
			or not bool(repaired_result.get("initialized", false)) \
			or repaired_result.get("summary", null) != repaired:
		return _fail_bool("explicit no-delta summary lost initialized identity")
	var large_exact: Dictionary = exact_summary.duplicate(true)
	large_exact.deltas[0]["integrity"] = LARGE_EXACT_FLOAT_INTEGER
	large_exact.deltas[0]["base_integrity"] = LARGE_EXACT_FLOAT_INTEGER
	large_exact.deltas[0]["state"] = "intact"
	var large_exact_result: Dictionary = ModuleIntegrityMapScript.validate_current_summary(large_exact)
	if not bool(large_exact_result.get("ok", false)) \
			or large_exact_result.get("summary", null) != large_exact:
		return _fail_bool("large exactly representable integer health was rejected or normalized")

	var invalid_cases: Array[Dictionary] = []
	invalid_cases.append({"label": "wrong type", "value": [], "reason": "integrity_summary_not_dictionary"})
	var extra_envelope: Dictionary = exact_summary.duplicate(true)
	extra_envelope["legacy"] = true
	invalid_cases.append({"label": "extra envelope key", "value": extra_envelope, "reason": "integrity_summary_invalid_shape"})
	var missing_envelope: Dictionary = exact_summary.duplicate(true)
	missing_envelope.erase("registered")
	invalid_cases.append({"label": "missing envelope key", "value": missing_envelope, "reason": "integrity_summary_invalid_shape"})
	var bad_schema: Dictionary = exact_summary.duplicate(true)
	bad_schema["schema"] = "module_integrity_map_v0"
	invalid_cases.append({"label": "schema", "value": bad_schema, "reason": "integrity_summary_invalid_schema"})
	var bad_deltas: Dictionary = exact_summary.duplicate(true)
	bad_deltas["deltas"] = {}
	invalid_cases.append({"label": "deltas type", "value": bad_deltas, "reason": "integrity_summary_invalid_deltas"})
	for bad_count in [true, "2", -1, 1.5, NAN, INF, 9007199254740992.0]:
		var count_case: Dictionary = exact_summary.duplicate(true)
		count_case["registered"] = bad_count
		invalid_cases.append({
			"label": "registered %s" % str(bad_count),
			"value": count_case,
			"reason": "integrity_summary_invalid_registered",
		})
	var duplicate: Dictionary = exact_summary.duplicate(true)
	duplicate.deltas.append(exact_row.duplicate(true))
	invalid_cases.append({"label": "duplicate id", "value": duplicate, "reason": "integrity_delta_duplicate_module_id"})
	var missing_row_key: Dictionary = exact_summary.duplicate(true)
	missing_row_key.deltas[0].erase("tool_class")
	invalid_cases.append({"label": "missing row key", "value": missing_row_key, "reason": "integrity_delta_invalid_shape"})
	var extra_row_key: Dictionary = exact_summary.duplicate(true)
	extra_row_key.deltas[0]["legacy"] = true
	invalid_cases.append({"label": "extra row key", "value": extra_row_key, "reason": "integrity_delta_invalid_shape"})
	var empty_id: Dictionary = exact_summary.duplicate(true)
	empty_id.deltas[0]["module_id"] = ""
	invalid_cases.append({"label": "empty id", "value": empty_id, "reason": "integrity_delta_invalid_module_id"})
	var coerced_string: Dictionary = exact_summary.duplicate(true)
	coerced_string.deltas[0]["kind"] = 3
	invalid_cases.append({"label": "coerced string", "value": coerced_string, "reason": "integrity_delta_invalid_string"})
	for bad_health in [true, "0.2", NAN, INF, -0.1, 0.006]:
		var health_case: Dictionary = exact_summary.duplicate(true)
		health_case.deltas[0]["integrity"] = bad_health
		invalid_cases.append({
			"label": "integrity %s" % str(bad_health),
			"value": health_case,
			"reason": "integrity_delta_invalid_health",
		})
	for bad_base in [true, "0.005", NAN, INF, 0.0, -1.0]:
		var base_case: Dictionary = exact_summary.duplicate(true)
		base_case.deltas[0]["base_integrity"] = bad_base
		invalid_cases.append({
			"label": "base %s" % str(bad_base),
			"value": base_case,
			"reason": "integrity_delta_invalid_health",
		})
	var inexact_health: Dictionary = exact_summary.duplicate(true)
	inexact_health.deltas[0]["integrity"] = LARGE_INEXACT_FLOAT_INTEGER
	inexact_health.deltas[0]["base_integrity"] = LARGE_EXACT_FLOAT_INTEGER
	inexact_health.deltas[0]["state"] = "intact"
	invalid_cases.append({
		"label": "integer health not exactly representable as float",
		"value": inexact_health,
		"reason": "integrity_delta_invalid_health",
	})
	var inexact_base: Dictionary = exact_summary.duplicate(true)
	inexact_base.deltas[0]["integrity"] = 9007199254740992
	inexact_base.deltas[0]["base_integrity"] = LARGE_INEXACT_FLOAT_INTEGER
	inexact_base.deltas[0]["state"] = "intact"
	invalid_cases.append({
		"label": "integer base not exactly representable as float",
		"value": inexact_base,
		"reason": "integrity_delta_invalid_health",
	})
	var int64_boundary: Dictionary = exact_summary.duplicate(true)
	int64_boundary.deltas[0]["integrity"] = INT64_MAX_VALUE
	int64_boundary.deltas[0]["base_integrity"] = INT64_MAX_VALUE
	int64_boundary.deltas[0]["state"] = "intact"
	invalid_cases.append({
		"label": "int64 upper boundary not exactly representable as float",
		"value": int64_boundary,
		"reason": "integrity_delta_invalid_health",
	})
	var state_mismatch: Dictionary = exact_summary.duplicate(true)
	state_mismatch.deltas[0]["state"] = "intact"
	invalid_cases.append({"label": "state mismatch", "value": state_mismatch, "reason": "integrity_delta_state_mismatch"})
	var unknown_state: Dictionary = exact_summary.duplicate(true)
	unknown_state.deltas[0]["state"] = "repairing"
	invalid_cases.append({"label": "unknown state", "value": unknown_state, "reason": "integrity_delta_state_mismatch"})
	var bad_composition: Dictionary = exact_summary.duplicate(true)
	bad_composition.deltas[0]["material_composition"] = []
	invalid_cases.append({"label": "composition type", "value": bad_composition, "reason": "integrity_delta_invalid_composition"})
	var bad_mounted: Dictionary = exact_summary.duplicate(true)
	bad_mounted.deltas[0]["mounted_components"] = {}
	invalid_cases.append({"label": "mounted type", "value": bad_mounted, "reason": "integrity_delta_invalid_mounted"})
	for bad_nested in [NAN, INF, Resource.new()]:
		var nested_case: Dictionary = exact_summary.duplicate(true)
		nested_case.deltas[0].material_composition["nested"] = {"array": [bad_nested]}
		invalid_cases.append({
			"label": "nested non-json %s" % typeof(bad_nested),
			"value": nested_case,
			"reason": "integrity_delta_invalid_json",
		})
	for case_v in invalid_cases:
		var case: Dictionary = case_v
		var denied: Dictionary = ModuleIntegrityMapScript.validate_current_summary(case.value)
		if bool(denied.get("ok", false)) or str(denied.get("reason", "")) != str(case.reason):
			return _fail_bool("%s lost exact denial: %s" % [case.label, str(denied)])

	var run: Dictionary = _valid_run_dict(godot_version)
	var absent: Dictionary = run.duplicate(true)
	absent.erase("module_integrity_summary")
	if RunSnapshotScript.from_dict(absent, RUN_7, godot_version) == null:
		return _fail_bool("current run rejected absent uninitialized summary")
	var empty: Dictionary = run.duplicate(true)
	empty["module_integrity_summary"] = {}
	if RunSnapshotScript.from_dict(empty, RUN_7, godot_version) == null:
		return _fail_bool("current run rejected empty uninitialized summary")
	var current_valid: Dictionary = run.duplicate(true)
	current_valid["module_integrity_summary"] = exact_summary.duplicate(true)
	var decoded = RunSnapshotScript.from_dict(current_valid, RUN_7, godot_version)
	if decoded == null or decoded.module_integrity_summary != exact_summary:
		return _fail_bool("current run rejected or normalized valid integrity")
	for invalid_v in invalid_cases:
		var invalid: Dictionary = invalid_v
		var mutant: Dictionary = run.duplicate(true)
		mutant["module_integrity_summary"] = invalid.value
		if RunSnapshotScript.from_dict(mutant, RUN_7, godot_version) != null:
			return _fail_bool("current run laundered %s" % str(invalid.label))
	var historical: Dictionary = _valid_run_dict(godot_version)
	historical["slice_version"] = "gate2-current-run-6"
	historical["module_integrity_summary"] = "historical-permissive"
	var historical_decoded = RunSnapshotScript.from_dict(
		historical, "gate2-current-run-6", godot_version)
	if historical_decoded == null or not historical_decoded.module_integrity_summary.is_empty():
		return _fail_bool("run-6 version-specific permissive behavior changed")
	return true


func _validate_full_world(godot_version: String) -> bool:
	var world: Dictionary = _valid_world_dict(godot_version)
	if world.has("_fixture_error"):
		return _fail_bool(str(world._fixture_error))
	var home_summary: Dictionary = {
		"schema": "module_integrity_map_v1", "deltas": [], "registered": 3,
	}
	var visited_summary: Dictionary = {
		"schema": "module_integrity_map_v1",
		"deltas": [_valid_row("edge/away", "bulkhead_portal_2x1", "engineering")],
		"registered": 5,
	}
	world.home_ship["module_integrity_summary"] = home_summary.duplicate(true)
	world.visited_ships["marker-away"]["module_integrity"] = visited_summary.duplicate(true)
	var decoded = WorldSnapshotScript.from_dict(world, WORLD_7, godot_version)
	if decoded == null:
		return _fail_bool("full current world rejected valid home/visited integrity")
	var recaptured: Dictionary = decoded.to_dict()
	if recaptured.home_ship.module_integrity_summary != home_summary \
			or recaptured.visited_ships["marker-away"].module_integrity != visited_summary:
		return _fail_bool("full current world normalized valid integrity")
	for owner in ["home", "visited"]:
		for bad_value in ["bad", [], 7, true]:
			var mutant: Dictionary = world.duplicate(true)
			if owner == "home":
				mutant.home_ship["module_integrity_summary"] = bad_value
			else:
				mutant.visited_ships["marker-away"]["module_integrity"] = bad_value
			if WorldSnapshotScript.from_dict(mutant, WORLD_7, godot_version) != null:
				return _fail_bool("world laundered %s integrity wrong type" % owner)
	var malformed_summaries: Array[Dictionary] = []
	var extra_envelope: Dictionary = visited_summary.duplicate(true)
	extra_envelope["legacy"] = true
	malformed_summaries.append({"label": "extra envelope", "value": extra_envelope})
	var missing_envelope: Dictionary = visited_summary.duplicate(true)
	missing_envelope.erase("registered")
	malformed_summaries.append({"label": "missing envelope", "value": missing_envelope})
	var bad_schema: Dictionary = visited_summary.duplicate(true)
	bad_schema["schema"] = "module_integrity_map_v0"
	malformed_summaries.append({"label": "schema", "value": bad_schema})
	for bad_count in [true, "5", 2.5]:
		var count_case: Dictionary = visited_summary.duplicate(true)
		count_case["registered"] = bad_count
		malformed_summaries.append({"label": "count %s" % str(bad_count), "value": count_case})
	var missing_row: Dictionary = visited_summary.duplicate(true)
	missing_row.deltas[0].erase("room_id")
	malformed_summaries.append({"label": "missing row key", "value": missing_row})
	var extra_row: Dictionary = visited_summary.duplicate(true)
	extra_row.deltas[0]["legacy"] = true
	malformed_summaries.append({"label": "extra row key", "value": extra_row})
	var duplicate: Dictionary = visited_summary.duplicate(true)
	duplicate.deltas.append(duplicate.deltas[0].duplicate(true))
	malformed_summaries.append({"label": "duplicate id", "value": duplicate})
	for bad_health in [true, "0.002", NAN, INF]:
		var health_case: Dictionary = visited_summary.duplicate(true)
		health_case.deltas[0]["integrity"] = bad_health
		malformed_summaries.append({"label": "health %s" % str(bad_health), "value": health_case})
	var state_mismatch: Dictionary = visited_summary.duplicate(true)
	state_mismatch.deltas[0]["state"] = "intact"
	malformed_summaries.append({"label": "state mismatch", "value": state_mismatch})
	for owner in ["home", "visited"]:
		for malformed_v in malformed_summaries:
			var malformed: Dictionary = malformed_v
			var mutant: Dictionary = world.duplicate(true)
			if owner == "home":
				mutant.home_ship["module_integrity_summary"] = malformed.value
			else:
				mutant.visited_ships["marker-away"]["module_integrity"] = malformed.value
			if WorldSnapshotScript.from_dict(mutant, WORLD_7, godot_version) != null:
				return _fail_bool("world accepted %s %s" % [owner, malformed.label])
	for owner in ["home", "visited"]:
		for mode in ["absent", "empty"]:
			var pristine: Dictionary = world.duplicate(true)
			var ship_summary: Dictionary = pristine.home_ship if owner == "home" \
				else pristine.visited_ships["marker-away"]
			var key: String = "module_integrity_summary" if owner == "home" else "module_integrity"
			if mode == "absent":
				ship_summary.erase(key)
			else:
				ship_summary[key] = {}
			if WorldSnapshotScript.from_dict(pristine, WORLD_7, godot_version) == null:
				return _fail_bool("world rejected %s %s uninitialized integrity" % [owner, mode])
	return true


func _validate_descriptor_application() -> bool:
	var integrity_map = ModuleIntegrityMapScript.new()
	var descriptor_a: Dictionary = _descriptor(
		"edge/a", "wall_straight_1x1", ["bridge", "engineering"])
	var descriptor_b: Dictionary = _descriptor("floor/b", "floor_1x1", ["bridge"])
	if not integrity_map.register_original_descriptor(descriptor_a) \
			or not integrity_map.register_original_descriptor(descriptor_b):
		return _fail_bool("could not register real descriptor authority")
	integrity_map.apply_damage("edge/a", 0.3, "wall_straight_1x1")
	var source_before: Dictionary = integrity_map.get_summary().duplicate(true)
	var descriptors_before: Array = integrity_map.get_structural_rebuild_state() \
		.call("get_original_descriptors").duplicate(true)
	var exact_row: Dictionary = _valid_row("edge/a", "wall_straight_1x1", "bridge")
	var exact_summary: Dictionary = {
		"schema": "module_integrity_map_v1",
		"deltas": [exact_row.duplicate(true)],
		"registered": 2.0,
	}
	var rejection_cases: Array[Dictionary] = []
	var bad_count: Dictionary = exact_summary.duplicate(true)
	bad_count["registered"] = 1
	rejection_cases.append({"label": "count", "summary": bad_count, "reason": "integrity_registered_count_mismatch"})
	var unknown: Dictionary = exact_summary.duplicate(true)
	unknown.deltas[0]["module_id"] = "edge/unknown"
	rejection_cases.append({"label": "unknown id", "summary": unknown, "reason": "integrity_delta_unknown_module"})
	var bad_kind: Dictionary = exact_summary.duplicate(true)
	bad_kind.deltas[0]["kind"] = "floor_1x1"
	rejection_cases.append({"label": "kind", "summary": bad_kind, "reason": "integrity_delta_kind_mismatch"})
	var bad_room: Dictionary = exact_summary.duplicate(true)
	bad_room.deltas[0]["room_id"] = "engineering"
	rejection_cases.append({"label": "room", "summary": bad_room, "reason": "integrity_delta_room_mismatch"})
	var inexact_health: Dictionary = exact_summary.duplicate(true)
	inexact_health.deltas[0]["integrity"] = LARGE_INEXACT_FLOAT_INTEGER
	inexact_health.deltas[0]["base_integrity"] = LARGE_EXACT_FLOAT_INTEGER
	inexact_health.deltas[0]["state"] = "intact"
	rejection_cases.append({
		"label": "inexact integer health",
		"summary": inexact_health,
		"reason": "integrity_delta_invalid_health",
	})
	var inexact_base: Dictionary = exact_summary.duplicate(true)
	inexact_base.deltas[0]["integrity"] = 9007199254740992
	inexact_base.deltas[0]["base_integrity"] = LARGE_INEXACT_FLOAT_INTEGER
	inexact_base.deltas[0]["state"] = "intact"
	rejection_cases.append({
		"label": "inexact integer base",
		"summary": inexact_base,
		"reason": "integrity_delta_invalid_health",
	})
	for case_v in rejection_cases:
		var case: Dictionary = case_v
		var denied: Dictionary = integrity_map.apply_current_summary(case.summary)
		if bool(denied.get("ok", false)) or str(denied.get("reason", "")) != str(case.reason):
			return _fail_bool("descriptor %s lost exact denial: %s" % [case.label, str(denied)])
		if integrity_map.get_summary() != source_before \
				or integrity_map.get_structural_rebuild_state().call(
					"get_original_descriptors") != descriptors_before:
			return _fail_bool("descriptor %s denial mutated live or rebuild state" % case.label)

	var large_exact_row: Dictionary = exact_row.duplicate(true)
	large_exact_row["integrity"] = LARGE_EXACT_FLOAT_INTEGER
	large_exact_row["base_integrity"] = LARGE_EXACT_FLOAT_INTEGER
	large_exact_row["state"] = "intact"
	var large_exact_summary: Dictionary = {
		"schema": "module_integrity_map_v1",
		"deltas": [large_exact_row],
		"registered": 2,
	}
	var large_applied: Dictionary = integrity_map.apply_current_summary(large_exact_summary)
	var large_restored = integrity_map.get_module("edge/a")
	if not bool(large_applied.get("ok", false)) or large_restored == null \
			or large_restored.get("integrity") != float(LARGE_EXACT_FLOAT_INTEGER) \
			or large_restored.get("base_integrity") != float(LARGE_EXACT_FLOAT_INTEGER):
		return _fail_bool("large exactly representable integer health failed strict application")
	var large_recaptured: Dictionary = integrity_map.get_summary()
	if (large_recaptured.deltas as Array).size() != 1 \
			or large_recaptured.deltas[0].integrity != float(LARGE_EXACT_FLOAT_INTEGER) \
			or large_recaptured.deltas[0].base_integrity != float(LARGE_EXACT_FLOAT_INTEGER):
		return _fail_bool("large exactly representable integer health changed on recapture")

	var applied: Dictionary = integrity_map.apply_current_summary(exact_summary)
	if not bool(applied.get("ok", false)) or not bool(applied.get("initialized", false)):
		return _fail_bool("valid descriptor-authenticated summary rejected: %s" % str(applied))
	var restored = integrity_map.get_module("edge/a")
	if restored == null or restored.get("integrity") != 0.002 \
			or restored.get("base_integrity") != 0.005 or restored.get("state") != "breached" \
			or restored.get("material_composition") != exact_row.material_composition \
			or restored.get("mounted_components") != exact_row.mounted_components:
		return _fail_bool("valid health/payload was normalized during strict apply")
	var owners: PackedStringArray = restored.get("owner_rooms") as PackedStringArray
	if owners != PackedStringArray(["bridge", "engineering"]):
		return _fail_bool("strict apply lost descriptor room owners: %s" % str(owners))
	var pristine = integrity_map.get_module("floor/b")
	if pristine == null or pristine.get("kind") != "floor_1x1" \
			or pristine.get("room_id") != "bridge" \
			or pristine.get("owner_rooms") != PackedStringArray(["bridge"]):
		return _fail_bool("omitted pristine descriptor was not rebuilt exactly")
	if integrity_map.get_summary() != exact_summary:
		return _fail_bool("strict apply did not exactly recapture accepted summary")

	var near_row: Dictionary = _valid_row("edge/a", "wall_straight_1x1", "bridge")
	near_row["base_integrity"] = 1.0
	near_row["integrity"] = 0.99995
	near_row["state"] = "intact"
	near_row["material_composition"] = {}
	near_row["mounted_components"] = []
	var near_summary: Dictionary = {
		"schema": "module_integrity_map_v1", "deltas": [near_row], "registered": 2,
	}
	if not bool(integrity_map.apply_current_summary(near_summary).get("ok", false)) \
			or integrity_map.get_summary() != near_summary:
		return _fail_bool("near-pristine explicit delta disappeared through epsilon sparsity")
	var explicit_pristine_row: Dictionary = near_row.duplicate(true)
	explicit_pristine_row["integrity"] = 1.0
	var explicit_pristine: Dictionary = {
		"schema": "module_integrity_map_v1",
		"deltas": [explicit_pristine_row],
		"registered": 2,
	}
	if not bool(integrity_map.apply_current_summary(explicit_pristine).get("ok", false)) \
			or integrity_map.get_summary() != explicit_pristine:
		return _fail_bool("explicit pristine row disappeared during exact recapture")
	var repaired: Dictionary = {
		"schema": "module_integrity_map_v1", "deltas": [], "registered": 2,
	}
	if not bool(integrity_map.apply_current_summary(repaired).get("ok", false)) \
			or integrity_map.get_summary() != repaired:
		return _fail_bool("explicit repaired summary was not retained")
	integrity_map.apply_damage("floor/b", 0.00005, "floor_1x1")
	var tiny_damage_summary: Dictionary = integrity_map.get_summary()
	if (tiny_damage_summary.deltas as Array).size() != 1 \
			or tiny_damage_summary.deltas[0].module_id != "floor/b" \
			or tiny_damage_summary.deltas[0].integrity != 0.99995:
		return _fail_bool("current exact sparsity dropped new sub-epsilon damage")
	var detached_map = ModuleIntegrityMapScript.new()
	var detached: Dictionary = detached_map.apply_current_summary({
		"schema": "module_integrity_map_v1", "deltas": [], "registered": 0,
	})
	if bool(detached.get("ok", false)) \
			or str(detached.get("reason", "")) != "integrity_descriptor_authority_missing":
		return _fail_bool("detached syntax load falsely claimed geometry closure: %s" % str(detached))
	return true


func _valid_row(module_id: String, kind: String, room_id: String) -> Dictionary:
	return {
		"module_id": module_id,
		"kind": kind,
		"room_id": room_id,
		"integrity": 0.002,
		"base_integrity": 0.005,
		"state": "breached",
		"material_composition": {
			"alloy": {"quantity": 3, "qualities": [0.25, true, null, "forged"]},
		},
		"mounted_components": [{
			"component_id": "relay", "metadata": {"condition": 0.75, "tags": ["live"]},
		}],
		"tool_class": "welding_lance",
	}


func _descriptor(module_id: String, structural_kind: String, rooms: Array) -> Dictionary:
	return {
		"module_id": module_id,
		"structural_module_id": structural_kind,
		"placement_id": "placement:%s" % module_id,
		"layout_layer": module_id.get_slice("/", 0),
		"wrapper_id": "res://wrapper/%s.tscn" % structural_kind,
		"layout_kit_id": "derelict_v1",
		"structural_kit_id": "ship_structural_v0",
		"structural_contract_id": "contract:%s" % structural_kind,
		"rebuild_contract_status": "supported",
		"transform": {"position": [0, 0, 0], "yaw_degrees": 0.0, "scale": [1, 1, 1]},
		"footprint": [1, 1],
		"sockets": [],
		"socket_bindings": [],
		"room_bindings": rooms.duplicate(true),
		"edge_binding": {},
		"component_bindings": [],
		"system_links": [],
		"layout_revision": "fixture-revision",
		"layout_revision_source": "explicit",
		"layout_fingerprint": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	}


func _valid_run_dict(godot_version: String) -> Dictionary:
	var snapshot = RunSnapshotScript.new()
	snapshot.slice_version = RUN_7
	snapshot.godot_version = godot_version
	snapshot.run_id = "fixture-world"
	snapshot.recipe_knowledge_summary["owner_id"] = "player:fixture-world"
	var threat_manager = ThreatManagerScript.new()
	snapshot.inventory_summary = {
		"tools": [], "combat_hotbar_text": "", "threat_summary": threat_manager.get_summary(),
	}
	threat_manager.free()
	return snapshot.to_dict()


func _valid_world_dict(godot_version: String) -> Dictionary:
	var source_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/feature_completion/p10_world_v5_transactional.json"))
	if not source_v is Dictionary:
		return {"_fixture_error": "world source fixture parse failed"}
	var source: Dictionary = (source_v as Dictionary).duplicate(true)
	source["godot_version"] = godot_version
	source.home_ship["godot_version"] = godot_version
	var migrated: Dictionary = SaveMigrationServiceScript.new().migrate_world(source)
	if not migrated.get("dict", null) is Dictionary:
		return {"_fixture_error": "world fixture migration failed: %s" % str(migrated)}
	var world: Dictionary = (migrated.dict as Dictionary).duplicate(true)
	world["home_ship"] = _valid_run_dict(godot_version)
	world["slice_version"] = WORLD_7
	world["godot_version"] = godot_version
	world.erase("dock_edges")
	world.erase("player_position_in_ship")
	world.erase("opened_ports")
	world["dock_connections_v1"] = [
		_airlock_connection("dock:home-lifeboat", "ship_start", "lifeboat"),
	]
	world["player_owner_pose_v1"] = {
		"owner_ship_id": "ship-away", "location_kind": "interior",
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
	world["current_location"] = "marker-away"
	world["aboard_ship_id"] = "ship-away"
	world.visited_ships["marker-away"]["combat"] = (
		world.home_ship.inventory_summary.threat_summary as Dictionary).duplicate(true)
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


func _fail_bool(reason: String) -> bool:
	_fail(reason)
	return false


func _fail(reason: String) -> void:
	push_error("R10-A INTEGRITY ADMISSION FAIL reason=%s" % reason)
	quit(1)
