extends RefCounted
class_name RoomDressingRules

const PATH: String = "res://data/procgen/dressing/room_kit_v2.json"
const RoomAssignerScript: GDScript = preload("res://scripts/procgen/room_assigner.gd")

const REQUIRED_ROW_FIELDS: Dictionary = {
	"asset_id": true,
	"new": true,
	"max_size_m": true,
	"triangles_max": true,
	"material_max": true,
	"roles": true,
	"footprint_cells": true,
	"behavior": true,
}
const IMPROVED_IDS: Dictionary = {
	"fabrication_station_derelict_v1": true,
	"medical_stasis_pod_derelict_v1": true,
	"power_cell_cradle_derelict_v1": true,
	"salvage_sorter_derelict_v1": true,
}
const NEW_IDS: Dictionary = {
	"oxygen_manifold_derelict_v1": true,
	"coolant_pump_skid_derelict_v1": true,
	"navigation_chart_table_derelict_v1": true,
	"scanner_signal_cabinet_derelict_v1": true,
	"hydroponic_grow_tray_derelict_v1": true,
	"water_reclaimer_derelict_v1": true,
	"galley_heater_derelict_v1": true,
	"crew_bunk_derelict_v1": true,
	"suit_service_stand_derelict_v1": true,
	"sample_quarantine_cabinet_derelict_v1": true,
	"gravity_coil_housing_derelict_v1": true,
	"cargo_restraint_frame_derelict_v1": true,
}


# Read and validate the live catalog on every call. A failed read is not cached,
# so a later corrected catalog can be observed without restarting the process.
static func rows() -> Array:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return []
	var document: Variant = JSON.parse_string(file.get_as_text())
	return parse_rows(document)


# Pure validation seam used by rows() and focused malformed-document fixtures.
# It returns no partial rows: any invalid document is rejected as an empty array.
static func parse_rows(document: Variant) -> Array:
	if not document is Dictionary:
		return []
	var doc: Dictionary = document
	if str(doc.get("schema_version", "")) != "1.0.0":
		return []
	if str(doc.get("asset_pack", "")) != "room_kit_v2":
		return []
	var assets_value: Variant = doc.get("assets", null)
	if not assets_value is Array:
		return []
	var assets: Array = assets_value
	if assets.size() != 16:
		return []

	var accepted: Array = []
	var seen_ids: Dictionary = {}
	var new_count: int = 0
	for row_value in assets:
		if not row_value is Dictionary:
			return []
		var row: Dictionary = row_value
		if not _valid_row(row):
			return []
		var asset_id: String = str(row["asset_id"])
		if seen_ids.has(asset_id):
			return []
		seen_ids[asset_id] = true
		if bool(row["new"]):
			new_count += 1
		accepted.append(row.duplicate(true))

	if new_count != 12:
		return []
	accepted.sort_custom(_sort_rows)
	return accepted


static func candidates(role: String) -> Array[String]:
	var normalized: String = RoomAssignerScript.normalize_role(role.to_lower())
	if normalized.is_empty():
		return []
	var result: Array[String] = []
	var seen_ids: Dictionary = {}
	for row_value in rows():
		if not row_value is Dictionary:
			return []
		var row: Dictionary = row_value
		var roles_value: Variant = row.get("roles", null)
		if not roles_value is Array:
			return []
		for permitted_value in (roles_value as Array):
			var permitted: String = RoomAssignerScript.normalize_role(str(permitted_value).to_lower())
			if permitted == normalized:
				var asset_id: String = str(row.get("asset_id", ""))
				if not seen_ids.has(asset_id):
					seen_ids[asset_id] = true
					result.append(asset_id)
				break
	result.sort()
	return result


static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for row_value in rows():
		if not row_value is Dictionary:
			return []
		result.append(str((row_value as Dictionary).get("asset_id", "")))
	result.sort()
	return result


static func selected(role: String, seed_value: int, room_index: int) -> String:
	var values: Array[String] = candidates(role)
	if values.is_empty():
		return ""
	return values[posmod(seed_value + room_index, values.size())]


static func _valid_row(row: Dictionary) -> bool:
	if row.size() != REQUIRED_ROW_FIELDS.size():
		return false
	for key in row.keys():
		if not REQUIRED_ROW_FIELDS.has(str(key)):
			return false
	for field in REQUIRED_ROW_FIELDS:
		if not row.has(field):
			return false

	var asset_value: Variant = row["asset_id"]
	if not asset_value is String:
		return false
	var asset_id: String = str(asset_value)
	if not _valid_asset_id(asset_id):
		return false
	var new_value: Variant = row["new"]
	if not new_value is bool:
		return false
	var is_new: bool = bool(new_value)
	if is_new != NEW_IDS.has(asset_id):
		return false
	if not is_new and not IMPROVED_IDS.has(asset_id):
		return false
	if str(row["behavior"]) != "static_dressing":
		return false

	var size_value: Variant = row["max_size_m"]
	if not size_value is Array:
		return false
	var sizes: Array = size_value
	if sizes.size() != 3:
		return false
	for size_value_item in sizes:
		if not _valid_number(size_value_item) or float(size_value_item) <= 0.0 or float(size_value_item) > 2.2:
			return false

	if not _valid_integer(row["triangles_max"], 1, 10000):
		return false
	if not _valid_integer(row["material_max"], 1, 4):
		return false

	var roles_value: Variant = row["roles"]
	if not roles_value is Array:
		return false
	var roles: Array = roles_value
	if roles.is_empty():
		return false
	var seen_roles: Dictionary = {}
	for role_value in roles:
		if not role_value is String:
			return false
		var role: String = str(role_value)
		if role.is_empty() or role != role.to_lower() or role.strip_edges() != role:
			return false
		if seen_roles.has(role):
			return false
		seen_roles[role] = true

	var footprint_value: Variant = row["footprint_cells"]
	if not footprint_value is Array:
		return false
	var footprint: Array = footprint_value
	if footprint.size() != 2:
		return false
	return _valid_integer(footprint[0], 1, 1) and _valid_integer(footprint[1], 1, 1)


static func _valid_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not _valid_number(value):
		return false
	var numeric: float = float(value)
	return is_equal_approx(numeric, roundf(numeric)) and numeric >= minimum and numeric <= maximum


static func _valid_asset_id(asset_id: String) -> bool:
	return not asset_id.is_empty() \
		and asset_id == asset_id.to_lower() \
		and asset_id.strip_edges() == asset_id \
		and asset_id.find("/") < 0 \
		and asset_id.find("\\") < 0 \
		and asset_id.ends_with("_derelict_v1")


static func _sort_rows(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("asset_id", "")) < str(right.get("asset_id", ""))
