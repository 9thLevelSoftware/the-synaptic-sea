extends RefCounted
class_name StructuralRebuildState

## Runtime registry of immutable, authored structural descriptors (ADR-0059).
## Replacement transactions and persistence are added by later feature cards.

## Stable placed module id -> immutable original descriptor.
var _originals: Dictionary = {}
var _integrity_owner_ref: WeakRef
var _catalog_authority_ref: WeakRef

const INTEGRITY_OWNER_SCRIPT_PATH: String = "res://scripts/systems/module_integrity_map.gd"
const CATALOG_AUTHORITY_SCRIPT_PATH: String = "res://scripts/systems/structural_rebuild_catalog.gd"


## One registry belongs to one concrete map for its entire lifetime. WeakRef
## avoids the map/state ownership cycle while retaining exact object identity.
func bind_integrity_owner(owner: RefCounted) -> bool:
	if not _has_exact_script(owner, INTEGRITY_OWNER_SCRIPT_PATH):
		return false
	if _integrity_owner_ref != null:
		return _integrity_owner_ref.get_ref() == owner
	_integrity_owner_ref = weakref(owner)
	return true


## The map binds one concrete, canonical-path catalog instance. No caller can
## replace it during evaluation with a method-compatible adapter or copied row.
func bind_catalog_authority(catalog: RefCounted) -> bool:
	if not _has_exact_script(catalog, CATALOG_AUTHORITY_SCRIPT_PATH) \
			or not catalog.has_method("is_loaded") or not bool(catalog.call("is_loaded")):
		return false
	if _catalog_authority_ref != null:
		return _catalog_authority_ref.get_ref() == catalog
	_catalog_authority_ref = weakref(catalog)
	return true


func clear() -> void:
	_originals.clear()


func size() -> int:
	return _originals.size()


## Registers one descriptor without allowing later load/damage code to overwrite it.
## Re-registering byte-equivalent authored data is idempotent; a conflict is rejected.
func register_original(descriptor: Dictionary) -> bool:
	if not _is_valid_descriptor(descriptor):
		return false
	var module_id: String = str(descriptor.get("module_id", ""))
	var frozen: Dictionary = descriptor.duplicate(true)
	if _originals.has(module_id):
		return JSON.stringify(_originals[module_id], "", true) == JSON.stringify(frozen, "", true)
	_originals[module_id] = frozen
	return true


## Immutable half of the inspection contract. ModuleIntegrityMap adds live state
## from its ModuleIntegrityState owner; this registry never mirrors mutable damage.
func inspect_target(module_id: String) -> Dictionary:
	if module_id.is_empty() or not _originals.has(module_id):
		return {
			"ok": false,
			"reason": "missing_original_descriptor",
			"module_id": module_id,
		}
	return {
		"ok": true,
		"reason": "",
		"module_id": module_id,
		"original_descriptor": (_originals[module_id] as Dictionary).duplicate(true),
	}


func module_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for module_id_variant in _originals.keys():
		ids.append(str(module_id_variant))
	ids.sort()
	return ids


## Runtime inspection copy. This is not a save payload; P19 owns persistence.
func get_original_descriptors() -> Array:
	var out: Array = []
	for module_id in module_ids():
		out.append((_originals[module_id] as Dictionary).duplicate(true))
	return out


## P17's pure, fail-closed replacement-policy step. The caller identifies a row;
## the model resolves the authoritative descriptor and canonical row from its
## bound owners. This model never reserves lots or accepts scene safety evidence;
## a successful result still requires scene-owned preflight before timed work.
func evaluate_replace(
		integrity_map: RefCounted,
		module_id: String,
		replacement_row_id: String,
		current_layout_revision: String,
		current_layout_fingerprint: String) -> Dictionary:
	if integrity_map == null:
		return _denial("missing_integrity_owner", module_id)
	var bound_owner: RefCounted = _integrity_owner_ref.get_ref() as RefCounted \
		if _integrity_owner_ref != null else null
	if bound_owner == null or integrity_map != bound_owner \
			or not _has_exact_script(integrity_map, INTEGRITY_OWNER_SCRIPT_PATH):
		return _denial("integrity_owner_mismatch", module_id)
	if module_id.is_empty() or not _originals.has(module_id):
		return _denial("missing_original_descriptor", module_id)
	if not integrity_map.has_method("get_state") \
			or str(integrity_map.call("get_state", module_id)) != "destroyed":
		return _denial("target_not_destroyed", module_id)
	var descriptor: Dictionary = _originals[module_id] as Dictionary
	if not _is_valid_descriptor(descriptor):
		return _denial("missing_original_descriptor", module_id)
	var rebuild_contract_status: String = str(descriptor.get(
		"rebuild_contract_status", "unsupported_rebuild"))
	if rebuild_contract_status == "missing_socket_contract":
		return _denial("missing_socket_contract", module_id)
	if rebuild_contract_status != "supported":
		return _denial("unsupported_rebuild", module_id)
	var layout_kit_id: String = str(descriptor.get("layout_kit_id", ""))
	var structural_kit_id: String = str(descriptor.get("structural_kit_id", ""))
	var structural_contract_id: String = str(descriptor.get("structural_contract_id", ""))
	if layout_kit_id.is_empty() or structural_kit_id.is_empty() or structural_contract_id.is_empty():
		return _denial("missing_layout_identity", module_id)
	if current_layout_revision.is_empty() or current_layout_fingerprint.is_empty() \
		or str(descriptor.get("layout_revision", "")) != current_layout_revision \
		or str(descriptor.get("layout_fingerprint", "")) != current_layout_fingerprint:
		return _denial("stale_layout", module_id)
	var catalog: RefCounted = _catalog_authority_ref.get_ref() as RefCounted \
		if _catalog_authority_ref != null else null
	if catalog == null or not _has_exact_script(catalog, CATALOG_AUTHORITY_SCRIPT_PATH) \
			or not catalog.has_method("resolve_row") or not bool(catalog.call("is_loaded")):
		return _denial("missing_rebuild_policy", module_id)
	var row_id: String = "%s:%s" % [layout_kit_id, str(descriptor.get("structural_module_id", ""))]
	if replacement_row_id != row_id:
		return _denial("missing_rebuild_policy", module_id)
	var row_variant: Variant = catalog.call("resolve_row", replacement_row_id)
	if not row_variant is Dictionary:
		return _denial("missing_rebuild_policy", module_id)
	var row: Dictionary = row_variant as Dictionary
	if not _is_exact_policy_row(row, descriptor, row_id):
		return _denial("invalid_rebuild_policy", module_id)
	if not _is_compatible_same_module_replacement(row, descriptor):
		return _denial("incompatible_replacement", module_id)
	var normalized_row: Dictionary = row.duplicate(true)
	var normalized_requirements: Dictionary = _normalized_requirements(row.get("requirements", {}))
	normalized_row["requirements"] = normalized_requirements
	var plan: Dictionary = {
		"ok": true,
		"reason": "",
		"module_id": module_id,
		"layout_revision": current_layout_revision,
		"layout_fingerprint": current_layout_fingerprint,
		"original_descriptor": descriptor.duplicate(true),
		"catalog_row": normalized_row,
		"action_id": str(row.get("action_id", "")),
		"requirements": normalized_requirements,
		"preflight_required": true,
		"scene_authorized": false,
	}
	return _freeze_variant(plan) as Dictionary


func _has_exact_script(value: RefCounted, expected_path: String) -> bool:
	if value == null:
		return false
	var script: Script = value.get_script() as Script
	return script != null and script.resource_path == expected_path


func _denial(reason: String, module_id: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"module_id": module_id,
		"preflight_required": true,
		"scene_authorized": false,
	}


func _is_exact_policy_row(row: Dictionary, descriptor: Dictionary, row_id: String) -> bool:
	const ROW_KEYS: Array[String] = [
		"row_id", "active", "layout_kit_id", "structural_kit_id",
		"structural_contract_id", "original_structural_module_id",
		"replacement_structural_module_id", "replacement_wrapper_id",
		"footprint_cells", "socket_mapping", "action_id", "requirements",
	]
	if row.size() != ROW_KEYS.size() or typeof(row.get("active", null)) != TYPE_BOOL \
		or not bool(row.get("active", false)) or typeof(row.get("row_id", null)) != TYPE_STRING \
		or str(row.get("row_id", "")) != row_id or typeof(row.get("action_id", null)) != TYPE_STRING \
		or str(row.get("action_id", "")) != "rebuild_structure":
		return false
	for key in ROW_KEYS:
		if not row.has(key):
			return false
	for identity_key in [
		"layout_kit_id", "structural_kit_id", "structural_contract_id",
		"original_structural_module_id", "replacement_structural_module_id",
		"replacement_wrapper_id",
	]:
		if typeof(row.get(identity_key, null)) != TYPE_STRING \
			or str(row.get(identity_key, "")).is_empty():
			return false
	if not _is_valid_requirements(row.get("requirements", null)):
		return false
	return true


func _is_compatible_same_module_replacement(row: Dictionary, descriptor: Dictionary) -> bool:
	var original_module_id: String = str(descriptor.get("structural_module_id", ""))
	if str(row.get("layout_kit_id", "")) != str(descriptor.get("layout_kit_id", "")) \
		or str(row.get("structural_kit_id", "")) != str(descriptor.get("structural_kit_id", "")) \
		or str(row.get("structural_contract_id", "")) != str(descriptor.get("structural_contract_id", "")) \
		or str(row.get("original_structural_module_id", "")) != original_module_id \
		or str(row.get("replacement_structural_module_id", "")) != original_module_id \
		or str(row.get("replacement_wrapper_id", "")) != str(descriptor.get("wrapper_id", "")):
		return false
	if not _same_integral_footprint(row.get("footprint_cells", null), descriptor.get("footprint", null)):
		return false
	return _same_socket_mapping(row.get("socket_mapping", null), descriptor.get("sockets", null))


func _is_valid_requirements(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var requirements: Dictionary = value as Dictionary
	var expected_keys: Array[String] = ["materials", "tool_class", "skill_id", "min_skill", "duration_seconds"]
	if requirements.size() != expected_keys.size():
		return false
	for key in expected_keys:
		if not requirements.has(key):
			return false
	var materials_variant: Variant = requirements.get("materials", null)
	if not materials_variant is Dictionary or (materials_variant as Dictionary).is_empty():
		return false
	for item_id_variant in (materials_variant as Dictionary).keys():
		var quantity: Variant = (materials_variant as Dictionary)[item_id_variant]
		if not item_id_variant is String or str(item_id_variant).is_empty() \
			or not _is_finite_integral_number(quantity, 1):
			return false
	return typeof(requirements.get("tool_class", null)) == TYPE_STRING \
		and str(requirements.get("tool_class", "")).is_empty() == false \
		and typeof(requirements.get("skill_id", null)) == TYPE_STRING \
		and str(requirements.get("skill_id", "")).is_empty() == false \
		and _is_finite_integral_number(requirements.get("min_skill", null), 0) \
		and _is_finite_integral_number(requirements.get("duration_seconds", null), 1)


func _normalized_requirements(value: Variant) -> Dictionary:
	var source: Dictionary = value as Dictionary
	var materials: Dictionary = {}
	for item_id_variant in (source.get("materials", {}) as Dictionary).keys():
		materials[str(item_id_variant)] = int((source.get("materials", {}) as Dictionary)[item_id_variant])
	return {
		"materials": materials,
		"tool_class": str(source.get("tool_class", "")),
		"skill_id": str(source.get("skill_id", "")),
		"min_skill": int(source.get("min_skill", 0)),
		"duration_seconds": int(source.get("duration_seconds", 0)),
	}


func _same_integral_footprint(left: Variant, right: Variant) -> bool:
	if not left is Array or not right is Array or (left as Array).size() != 2 or (right as Array).size() != 2:
		return false
	for index in range(2):
		var left_value: Variant = (left as Array)[index]
		var right_value: Variant = (right as Array)[index]
		if not _is_finite_integral_dimension(left_value) or not _is_finite_integral_dimension(right_value):
			return false
		if int(left_value) != int(right_value):
			return false
	return int((left as Array)[0]) != 0 or int((left as Array)[1]) != 0


func _is_finite_integral_dimension(value: Variant) -> bool:
	return _is_finite_integral_number(value, 0) and float(value) <= 2.0


func _is_finite_integral_number(value: Variant, minimum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric: float = float(value)
	return is_finite(numeric) and numeric >= float(minimum) \
		and numeric <= 9007199254740992.0 and numeric == floorf(numeric)


func _same_socket_mapping(mapping_variant: Variant, sockets_variant: Variant) -> bool:
	if not mapping_variant is Array or not sockets_variant is Array or (mapping_variant as Array).size() != (sockets_variant as Array).size():
		return false
	var expected: Dictionary = {}
	for socket_variant in sockets_variant as Array:
		if not socket_variant is String or str(socket_variant).is_empty() or expected.has(str(socket_variant)):
			return false
		expected[str(socket_variant)] = true
	for mapping_entry_variant in mapping_variant as Array:
		if not mapping_entry_variant is Dictionary:
			return false
		var mapping_entry: Dictionary = mapping_entry_variant as Dictionary
		if mapping_entry.size() != 2 or not mapping_entry.has("original_socket") or not mapping_entry.has("replacement_socket"):
			return false
		if typeof(mapping_entry.get("original_socket", null)) != TYPE_STRING \
			or typeof(mapping_entry.get("replacement_socket", null)) != TYPE_STRING:
			return false
		var original_socket: String = str(mapping_entry.get("original_socket", ""))
		if original_socket.is_empty() or str(mapping_entry.get("replacement_socket", "")) != original_socket \
			or not expected.has(original_socket):
			return false
		expected.erase(original_socket)
	return expected.is_empty()


func _freeze_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var frozen_dictionary: Dictionary = (value as Dictionary).duplicate()
		for key in frozen_dictionary.keys():
			frozen_dictionary[key] = _freeze_variant(frozen_dictionary[key])
		frozen_dictionary.make_read_only()
		return frozen_dictionary
	if value is Array:
		var frozen_array: Array = []
		for item in value as Array:
			frozen_array.append(_freeze_variant(item))
		frozen_array.make_read_only()
		return frozen_array
	return value


func _is_valid_descriptor(descriptor: Dictionary) -> bool:
	if str(descriptor.get("module_id", "")).is_empty():
		return false
	if str(descriptor.get("layout_revision", "")).is_empty():
		return false
	if str(descriptor.get("layout_fingerprint", "")).length() != 64:
		return false
	if str(descriptor.get("wrapper_id", "")).is_empty():
		return false
	if not descriptor.get("transform", null) is Dictionary:
		return false
	if not descriptor.get("footprint", null) is Array:
		return false
	if not descriptor.get("sockets", null) is Array:
		return false
	return true
