extends RefCounted
class_name RuntimePhysicalVolumeCatalog

## Canonical authority for runtime physical occupancy profiles.  There is no
## alternate-path loader: scene helpers resolve a profile id through this
## immutable catalog before creating any physical primitive.

const CATALOG_PATH: String = "res://data/physics/runtime_physical_volume_profiles.json"
const SCHEMA: String = "runtime_physical_volume_profiles_v1"
const ROOT_KEYS: Array[String] = ["schema", "profiles"]
const PROFILE_KEYS: Array[String] = [
    "profile_id", "shape_kind", "dimensions", "local_position",
    "local_yaw_degrees", "mount_kind", "collision_layer", "collision_mask",
    "blocking_purposes",
]
const REQUIRED_PROFILE_IDS: Array[String] = [
    "cart", "floor_drop", "air_recycler", "conduit", "console_generic_wall",
    "console_generic_deck", "hull_plating", "locker_wall", "machinery_block",
    "nav_console", "pump", "reactor_console", "sensor_rack", "thruster_control",
]
const SHAPE_KINDS: Array[String] = ["box", "capsule"]
const MOUNT_KINDS: Array[String] = ["floor", "deck", "wall"]

var _profiles: Dictionary = {}
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
    var profiles_variant: Variant = root.get("profiles", null)
    if not profiles_variant is Array or (profiles_variant as Array).size() != REQUIRED_PROFILE_IDS.size():
        return false
    var candidate: Dictionary = {}
    for profile_variant in profiles_variant as Array:
        if not profile_variant is Dictionary:
            return false
        var profile: Dictionary = profile_variant as Dictionary
        if not _is_valid_profile(profile):
            return false
        var profile_id: String = str(profile.get("profile_id", ""))
        if candidate.has(profile_id):
            return false
        candidate[profile_id] = _freeze_variant(profile)
    var candidate_ids: Array = candidate.keys()
    candidate_ids.sort()
    var required_ids: Array = REQUIRED_PROFILE_IDS.duplicate()
    required_ids.sort()
    if candidate_ids != required_ids:
        return false
    candidate.make_read_only()
    _profiles = candidate
    _loaded = true
    return true


func is_loaded() -> bool:
    return _loaded


func profile_count() -> int:
    return _profiles.size()


func profile_ids() -> PackedStringArray:
    var ids: PackedStringArray = PackedStringArray()
    for profile_id_variant in _profiles.keys():
        ids.append(str(profile_id_variant))
    ids.sort()
    return ids


## Returns a service-owned, recursively read-only profile.  Callers must never
## supply their own numeric profile dictionary to the scene helper.
func resolve_profile(profile_id: String) -> Dictionary:
    if not _loaded or profile_id.is_empty() or not _profiles.has(profile_id):
        return {}
    return _profiles[profile_id] as Dictionary


func _is_valid_profile(profile: Dictionary) -> bool:
    if not _has_exact_keys(profile, PROFILE_KEYS):
        return false
    var profile_id: Variant = profile.get("profile_id", null)
    var shape_kind: Variant = profile.get("shape_kind", null)
    var mount_kind: Variant = profile.get("mount_kind", null)
    if typeof(profile_id) != TYPE_STRING or str(profile_id).is_empty() \
            or typeof(shape_kind) != TYPE_STRING or not SHAPE_KINDS.has(str(shape_kind)) \
            or typeof(mount_kind) != TYPE_STRING or not MOUNT_KINDS.has(str(mount_kind)):
        return false
    if int(profile.get("collision_layer", -1)) != 2 or int(profile.get("collision_mask", -1)) != 0 \
            or not _is_exact_integer(profile.get("collision_layer", null), 2) \
            or not _is_exact_integer(profile.get("collision_mask", null), 0):
        return false
    if not _is_finite_vector(profile.get("local_position", null), 3) \
            or not _is_finite_number(profile.get("local_yaw_degrees", null)):
        return false
    var dimensions: Variant = profile.get("dimensions", null)
    if str(shape_kind) == "box":
        if not _is_positive_vector(dimensions, 3):
            return false
    elif not _is_valid_capsule_dimensions(dimensions):
        return false
    var purposes: Variant = profile.get("blocking_purposes", null)
    return purposes is Array and (purposes as Array).size() == 1 \
        and (purposes as Array)[0] == "structural_rebuild"


func _is_valid_capsule_dimensions(value: Variant) -> bool:
    if not _is_positive_vector(value, 2):
        return false
    var dimensions: Array = value as Array
    return float(dimensions[1]) >= float(dimensions[0]) * 2.0


func _is_positive_vector(value: Variant, expected_size: int) -> bool:
    if not _is_finite_vector(value, expected_size):
        return false
    for dimension in value as Array:
        if float(dimension) <= 0.0:
            return false
    return true


func _is_finite_vector(value: Variant, expected_size: int) -> bool:
    if not value is Array or (value as Array).size() != expected_size:
        return false
    for coordinate in value as Array:
        if not _is_finite_number(coordinate):
            return false
    return true


func _is_finite_number(value: Variant) -> bool:
    return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _is_exact_integer(value: Variant, expected: int) -> bool:
    return _is_finite_number(value) and float(value) == float(expected)


func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
    if value.size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true


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
