extends SceneTree

const Rules: GDScript = preload("res://scripts/procgen/room_dressing_rules.gd")
const RoomAssignerScript: GDScript = preload("res://scripts/procgen/room_assigner.gd")

const EXPECTED_IDS: Array[String] = [
	"cargo_restraint_frame_derelict_v1",
	"coolant_pump_skid_derelict_v1",
	"crew_bunk_derelict_v1",
	"fabrication_station_derelict_v1",
	"galley_heater_derelict_v1",
	"gravity_coil_housing_derelict_v1",
	"hydroponic_grow_tray_derelict_v1",
	"medical_stasis_pod_derelict_v1",
	"navigation_chart_table_derelict_v1",
	"oxygen_manifold_derelict_v1",
	"power_cell_cradle_derelict_v1",
	"salvage_sorter_derelict_v1",
	"sample_quarantine_cabinet_derelict_v1",
	"scanner_signal_cabinet_derelict_v1",
	"suit_service_stand_derelict_v1",
	"water_reclaimer_derelict_v1",
]


func _initialize() -> void:
	_run()


func _run() -> void:
	var rows: Array = Rules.rows()
	if not _require(rows.size() == 16, "live catalog rows=%d expected=16" % rows.size()):
		return

	var ids: Array[String] = Rules.all_ids()
	if not _require(ids == EXPECTED_IDS, "all_ids did not preserve the exact sorted sixteen-ID set"):
		return
	var seen_ids: Dictionary = {}
	for asset_id in ids:
		if not _require(not seen_ids.has(asset_id), "all_ids contains duplicate=%s" % asset_id):
			return
		seen_ids[asset_id] = true

	var current_expected: Dictionary = {
		"maintenance": [
			"coolant_pump_skid_derelict_v1",
			"fabrication_station_derelict_v1",
			"suit_service_stand_derelict_v1",
			"water_reclaimer_derelict_v1",
		],
		"engineering": [
			"coolant_pump_skid_derelict_v1",
			"fabrication_station_derelict_v1",
			"gravity_coil_housing_derelict_v1",
			"oxygen_manifold_derelict_v1",
			"scanner_signal_cabinet_derelict_v1",
		],
		"machine_shop": ["fabrication_station_derelict_v1"],
		"medical": [
			"medical_stasis_pod_derelict_v1",
			"sample_quarantine_cabinet_derelict_v1",
		],
		"medbay": [
			"medical_stasis_pod_derelict_v1",
			"sample_quarantine_cabinet_derelict_v1",
		],
		"reactor": [
			"coolant_pump_skid_derelict_v1",
			"gravity_coil_housing_derelict_v1",
			"power_cell_cradle_derelict_v1",
		],
		"power": ["power_cell_cradle_derelict_v1"],
		"engineering_power": ["power_cell_cradle_derelict_v1"],
		"cargo": [
			"cargo_restraint_frame_derelict_v1",
			"crew_bunk_derelict_v1",
			"gravity_coil_housing_derelict_v1",
			"hydroponic_grow_tray_derelict_v1",
			"oxygen_manifold_derelict_v1",
			"salvage_sorter_derelict_v1",
		],
		"storage": [
			"cargo_restraint_frame_derelict_v1",
			"salvage_sorter_derelict_v1",
			"suit_service_stand_derelict_v1",
		],
		"salvage": ["salvage_sorter_derelict_v1"],
	}
	for role_value in current_expected.keys():
		var role: String = str(role_value)
		var expected: Array = current_expected[role_value]
		var actual: Array[String] = Rules.candidates(role)
		if not _require(actual == expected, "current role %s eligibility=%s expected=%s" % [role, actual, expected]):
			return
		var candidate_ids: Dictionary = {}
		for asset_id in actual:
			if not _require(not candidate_ids.has(asset_id), "candidate duplicate role=%s id=%s" % [role, asset_id]):
				return
			candidate_ids[asset_id] = true

	if not _require(RoomAssignerScript.normalize_role("cockpit") == "bridge", "cockpit alias missing"):
		return
	if not _require(RoomAssignerScript.normalize_role("quarters") == "crew_quarters", "quarters alias missing"):
		return
	if not _require(RoomAssignerScript.normalize_role("tool_storage") == "storage", "tool_storage alias missing"):
		return
	if not _require(Rules.candidates("cockpit") == Rules.candidates("bridge"), "cockpit candidates diverged from bridge"):
		return
	if not _require(Rules.candidates("quarters") == Rules.candidates("crew_quarters"), "quarters candidates diverged from crew_quarters"):
		return
	if not _require(Rules.candidates("tool_storage") == Rules.candidates("storage"), "tool_storage candidates diverged from storage"):
		return

	for row_value in rows:
		var row: Dictionary = row_value
		var asset_id: String = str(row.get("asset_id", ""))
		var roles: Array = row.get("roles", [])
		if bool(row.get("new", false)):
			for role_value in roles:
				var role: String = str(role_value)
				if not _require(Rules.candidates(role).has(asset_id), "new ID %s is unreachable through role %s" % [asset_id, role]):
					return
			if not _require(asset_id in EXPECTED_IDS, "new ID escaped exact roster: %s" % asset_id):
				return

	if not _require(Rules.candidates("").is_empty(), "empty role invented candidates"):
		return
	if not _require(Rules.selected("", 3, 2).is_empty(), "empty role selected a value"):
		return
	if not _require(Rules.candidates("room_kit_unknown").is_empty(), "unknown role invented candidates"):
		return
	if not _require(Rules.selected("room_kit_unknown", 3, 2).is_empty(), "unknown role selected a value"):
		return

	var exact_integer_json: Variant = JSON.parse_string("{\"triangles_max\":10000,\"material_max\":4,\"footprint_cells\":[1,1]}")
	if not _require(exact_integer_json is Dictionary, "JSON integer fixture did not parse as a dictionary"):
		return
	var parsed_integer_values: Dictionary = exact_integer_json
	if not _require(typeof(parsed_integer_values["triangles_max"]) == TYPE_FLOAT, "JSON integer fixture did not exercise Godot's float numeric type"):
		return
	if not _require(Rules._valid_integer(parsed_integer_values["triangles_max"], 1, 10000), "exact JSON integer triangles_max was rejected"):
		return
	if not _require(Rules._valid_integer(parsed_integer_values["material_max"], 1, 4), "exact JSON integer material_max was rejected"):
		return
	var integer_validation_cases: Array = [
		[9999.999, 1, 10000, false, "fractional triangles_max 9999.999"],
		[3.000001, 1, 4, false, "fractional material_max 3.000001"],
		[true, 1, 10000, false, "boolean integer"],
		["3", 1, 4, false, "string integer"],
		[INF, 1, 10000, false, "infinite integer"],
		[-INF, 1, 10000, false, "negative infinite integer"],
		[NAN, 1, 10000, false, "NaN integer"],
		[0, 1, 10000, false, "below-range integer"],
		[10001, 1, 10000, false, "above-range integer"],
		[1.0, 1, 10000, true, "exact integral float"],
	]
	for validation_case in integer_validation_cases:
		var actual_valid: bool = Rules._valid_integer(validation_case[0], validation_case[1], validation_case[2])
		if not _require(actual_valid == validation_case[3], "integer validation mismatch: %s" % validation_case[4]):
			return

	var fractional_json: Dictionary = JSON.parse_string("{\"triangles_max\":9999.999,\"material_max\":3.000001}")
	for field in fractional_json:
		var fractional_budget_rows: Array = rows.duplicate(true)
		fractional_budget_rows[0][field] = fractional_json[field]
		if not _require(Rules.parse_rows(_catalog(fractional_budget_rows)).is_empty(), "fractional catalog budget accepted: %s" % field):
			return

	var fractional_footprint_rows: Array = rows.duplicate(true)
	var fractional_footprint_row: Dictionary = (fractional_footprint_rows[0] as Dictionary).duplicate(true)
	fractional_footprint_row["footprint_cells"] = [1.5, 1]
	fractional_footprint_rows[0] = fractional_footprint_row
	if not _require(Rules.parse_rows(_catalog(fractional_footprint_rows)).is_empty(), "fractional footprint cell was accepted"):
		return

	var coverage_roles: Array[String] = [
		"maintenance", "engineering", "machine_shop", "medical", "medbay",
		"reactor", "power", "engineering_power", "cargo", "storage", "salvage",
		"bridge", "life_support", "hydroponics", "mess_hall", "crew_quarters",
		"armory", "navigation", "scanner", "bay", "hangar",
	]
	for role in coverage_roles:
		var values: Array[String] = Rules.candidates(role)
		if values.is_empty():
			continue
		var covered: Dictionary = {}
		for index in range(values.size()):
			var first: String = Rules.selected(role, -17, index)
			var repeated: String = Rules.selected(role, -17, index)
			var expected: String = values[posmod(-17 + index, values.size())]
			if not _require(first == repeated and first == expected, "non-deterministic selection role=%s index=%d" % [role, index]):
				return
			covered[first] = true
		if not _require(covered.size() == values.size(), "selection cycle missed a candidate role=%s" % role):
			return

	var invalid_documents: Array = [
		null,
		{},
		{"schema_version": "1.0.0", "asset_pack": "room_kit_v2", "assets": "not-an-array"},
	]
	var duplicate_rows: Array = rows.duplicate(true)
	duplicate_rows[duplicate_rows.size() - 1] = (duplicate_rows[0] as Dictionary).duplicate(true)
	invalid_documents.append(_catalog(duplicate_rows))
	var malformed_record_rows: Array = rows.duplicate(true)
	malformed_record_rows[0] = {"asset_id": "broken_derelict_v1", "new": false, "behavior": "static_dressing"}
	invalid_documents.append(_catalog(malformed_record_rows))
	var malformed_role_rows: Array = rows.duplicate(true)
	var malformed_role: Dictionary = (malformed_role_rows[0] as Dictionary).duplicate(true)
	malformed_role["roles"] = ["Engineering"]
	malformed_role_rows[0] = malformed_role
	invalid_documents.append(_catalog(malformed_role_rows))
	var malformed_id_rows: Array = rows.duplicate(true)
	var malformed_id: Dictionary = (malformed_id_rows[0] as Dictionary).duplicate(true)
	malformed_id["asset_id"] = 42
	malformed_id_rows[0] = malformed_id
	invalid_documents.append(_catalog(malformed_id_rows))
	var partial_rows: Array = rows.duplicate(true)
	partial_rows.pop_back()
	invalid_documents.append(_catalog(partial_rows))
	for document in invalid_documents:
		if not _require(Rules.parse_rows(document).is_empty(), "malformed catalog was not rejected fail-closed"):
			return

	if not _require(Rules.rows().size() == 16, "live catalog failure was cached or mutated"):
		return
	print("ROOM_KIT_V2_RULES_PASS rows=16 ids=16 deterministic=true aliases=true malformed_fail_closed=true")
	quit(0)


func _catalog(assets: Array) -> Dictionary:
	return {
		"schema_version": "1.0.0",
		"asset_pack": "room_kit_v2",
		"assets": assets,
	}


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	print("ROOM_KIT_V2_RULES_FAIL %s" % message)
	quit(1)
	return false
