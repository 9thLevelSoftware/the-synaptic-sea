extends RefCounted
class_name StructuralRebuildCatalog

## Canonical runtime authority for P17 replacement policy. The service has no
## alternate-path loader: authored changes must pass the repository's Python
## review gate, while runtime always reads the shipped catalog at this path.

const CATALOG_PATH: String = "res://data/construction/structural_rebuild_catalog.json"
const SCHEMA: String = "structural_rebuild_catalog_v1"
const MODULAR_ASSET_SPEC_SCRIPT_PATH: String = "res://scripts/placement/modular_asset_spec.gd"
const ROOT_KEYS: Array[String] = ["schema", "rows"]
const ROW_KEYS: Array[String] = [
    "row_id", "active", "layout_kit_id", "structural_kit_id",
    "structural_contract_id", "original_structural_module_id",
    "replacement_structural_module_id", "replacement_wrapper_id",
    "footprint_cells", "socket_mapping", "action_id", "requirements",
]
const REQUIREMENT_KEYS: Array[String] = [
    "materials", "tool_class", "skill_id", "min_skill", "duration_seconds",
]
const SOCKET_MAPPING_KEYS: Array[String] = ["original_socket", "replacement_socket"]

var _rows: Dictionary = {}
var _loaded: bool = false


func load_canonical() -> bool:
    if _loaded:
        return true
    if not FileAccess.file_exists(CATALOG_PATH):
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if not parsed is Dictionary:
        return false
    var root: Dictionary = parsed as Dictionary
    if not _has_exact_keys(root, ROOT_KEYS) or str(root.get("schema", "")) != SCHEMA:
        return false
    var rows_variant: Variant = root.get("rows", null)
    if not rows_variant is Array or (rows_variant as Array).is_empty():
        return false
    var candidate: Dictionary = {}
    for row_variant in rows_variant as Array:
        if not row_variant is Dictionary:
            return false
        var row: Dictionary = row_variant as Dictionary
        if not _is_valid_row(row):
            return false
        if not bool(row.get("active", false)):
            continue
        var row_id: String = str(row.get("row_id", ""))
        if candidate.has(row_id):
            return false
        candidate[row_id] = _freeze_variant(row)
    if candidate.is_empty():
        return false
    _rows = candidate
    _rows.make_read_only()
    _loaded = true
    return true


func is_loaded() -> bool:
    return _loaded


func row_count() -> int:
    return _rows.size()


func row_ids() -> PackedStringArray:
    var ids: PackedStringArray = PackedStringArray()
    for row_id_variant in _rows.keys():
        ids.append(str(row_id_variant))
    ids.sort()
    return ids


## Returns the service-owned recursively read-only row. Callers that need to
## transform presentation data must duplicate it; the authoritative row cannot
## be modified through this reference.
func resolve_row(row_id: String) -> Dictionary:
    if not _loaded or row_id.is_empty() or not _rows.has(row_id):
        return {}
    return _rows[row_id] as Dictionary


## Evidence/query seam: a caller may assert that a copied row is still equal to
## canonical policy, but the claimed row is never used by evaluation.
func verify_row_claim(row_id: String, claimed_row: Dictionary) -> Dictionary:
    var canonical: Dictionary = resolve_row(row_id)
    if canonical.is_empty() or claimed_row.is_empty():
        return {"ok": false, "reason": "missing_rebuild_policy", "row_id": row_id}
    if JSON.stringify(canonical, "", true) != JSON.stringify(claimed_row, "", true):
        return {"ok": false, "reason": "catalog_authority_mismatch", "row_id": row_id}
    return {"ok": true, "reason": "", "row_id": row_id}


func _is_valid_row(row: Dictionary) -> bool:
    if not _has_exact_keys(row, ROW_KEYS) or typeof(row.get("active", null)) != TYPE_BOOL:
        return false
    for key in [
        "row_id", "layout_kit_id", "structural_kit_id", "structural_contract_id",
        "original_structural_module_id", "replacement_structural_module_id",
        "replacement_wrapper_id", "action_id",
    ]:
        if typeof(row.get(key, null)) != TYPE_STRING or str(row.get(key, "")).is_empty():
            return false
    var original_id: String = str(row.get("original_structural_module_id", ""))
    var expected_row_id: String = "%s:%s" % [str(row.get("layout_kit_id", "")), original_id]
    if str(row.get("row_id", "")) != expected_row_id \
            or str(row.get("replacement_structural_module_id", "")) != original_id:
        return false
    if not _is_valid_footprint(row.get("footprint_cells", null)) \
            or not _is_valid_socket_mapping(row.get("socket_mapping", null)) \
            or not _is_valid_requirements(row.get("requirements", null)):
        return false
    var contract_id: String = str(row.get("structural_contract_id", ""))
    var wrapper_id: String = str(row.get("replacement_wrapper_id", ""))
    return contract_id.begins_with("res://") and wrapper_id.begins_with("res://") \
        and ResourceLoader.exists(contract_id) and ResourceLoader.exists(wrapper_id) \
        and _matches_contract_resource(row)


func _matches_contract_resource(row: Dictionary) -> bool:
    var contract_id: String = str(row.get("structural_contract_id", ""))
    var contract: Resource = ResourceLoader.load(contract_id)
    var script: Script = contract.get_script() as Script if contract != null else null
    if contract == null or script == null or script.resource_path != MODULAR_ASSET_SPEC_SCRIPT_PATH \
            or str(contract.get("module_id")) != str(row.get("original_structural_module_id", "")) \
            or str(contract.get("wrapper_scene")) != str(row.get("replacement_wrapper_id", "")) \
            or str(contract.get("contract_path")) != contract_id:
        return false
    var contract_footprint_variant: Variant = contract.get("footprint_cells")
    var row_footprint: Array = row.get("footprint_cells", []) as Array
    if not contract_footprint_variant is Array \
            or not _same_integral_pair(row_footprint, contract_footprint_variant as Array):
        return false
    var contract_sockets_variant: Variant = contract.get("sockets")
    if not contract_sockets_variant is Array:
        return false
    var available: Dictionary = {}
    for socket_variant in contract_sockets_variant as Array:
        if not socket_variant is Dictionary:
            return false
        var socket_id: String = str((socket_variant as Dictionary).get("id", ""))
        if socket_id.is_empty() or available.has(socket_id):
            return false
        available[socket_id] = true
    for mapping_variant in row.get("socket_mapping", []) as Array:
        var socket_name: String = str((mapping_variant as Dictionary).get("original_socket", ""))
        if not available.has(socket_name.trim_prefix("SOCK_")):
            return false
    return true


func _is_valid_requirements(value: Variant) -> bool:
    if not value is Dictionary:
        return false
    var requirements: Dictionary = value as Dictionary
    if not _has_exact_keys(requirements, REQUIREMENT_KEYS):
        return false
    var materials_variant: Variant = requirements.get("materials", null)
    if not materials_variant is Dictionary or (materials_variant as Dictionary).is_empty():
        return false
    for item_id_variant in (materials_variant as Dictionary).keys():
        if not item_id_variant is String or str(item_id_variant).is_empty() \
                or not _is_finite_integral_number(
                    (materials_variant as Dictionary)[item_id_variant], 1):
            return false
    return typeof(requirements.get("tool_class", null)) == TYPE_STRING \
        and not str(requirements.get("tool_class", "")).is_empty() \
        and typeof(requirements.get("skill_id", null)) == TYPE_STRING \
        and not str(requirements.get("skill_id", "")).is_empty() \
        and _is_finite_integral_number(requirements.get("min_skill", null), 0) \
        and _is_finite_integral_number(requirements.get("duration_seconds", null), 1)


func _is_valid_footprint(value: Variant) -> bool:
    if not value is Array or (value as Array).size() != 2:
        return false
    for dimension in value as Array:
        if not _is_finite_integral_number(dimension, 0) or float(dimension) > 2.0:
            return false
    return int((value as Array)[0]) != 0 or int((value as Array)[1]) != 0


func _same_integral_pair(left: Array, right: Array) -> bool:
    if left.size() != 2 or right.size() != 2:
        return false
    for index in range(2):
        var left_value: Variant = left[index]
        var right_value: Variant = right[index]
        if not _is_finite_integral_number(left_value, 0) \
                or not _is_finite_integral_number(right_value, 0) \
                or int(left_value) != int(right_value):
            return false
    return true


func _is_valid_socket_mapping(value: Variant) -> bool:
    if not value is Array or (value as Array).is_empty():
        return false
    var seen: Dictionary = {}
    for mapping_variant in value as Array:
        if not mapping_variant is Dictionary:
            return false
        var mapping: Dictionary = mapping_variant as Dictionary
        if not _has_exact_keys(mapping, SOCKET_MAPPING_KEYS):
            return false
        var original_socket: Variant = mapping.get("original_socket", null)
        var replacement_socket: Variant = mapping.get("replacement_socket", null)
        if typeof(original_socket) != TYPE_STRING or typeof(replacement_socket) != TYPE_STRING:
            return false
        var socket_id: String = str(original_socket)
        if socket_id.is_empty() or not socket_id.begins_with("SOCK_") \
                or str(replacement_socket) != socket_id or seen.has(socket_id):
            return false
        seen[socket_id] = true
    return true


func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
    if value.size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true


func _is_finite_integral_number(value: Variant, minimum: int) -> bool:
    if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
        return false
    var numeric: float = float(value)
    return is_finite(numeric) and numeric >= float(minimum) \
        and numeric <= 9007199254740992.0 and numeric == floorf(numeric)


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
