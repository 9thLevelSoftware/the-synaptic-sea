extends RefCounted
class_name ModularSocketCatalog

## Loads ModularAssetSpec JSON for a structural kit and answers socket queries.
## The compiler owns topology; this catalog only reports authored sockets.

const CONTRACTS_ROOT: String = "res://data/placement/contracts/structural/"
const DEFAULT_KIT_ID: String = "ship_structural_v0"
const GRID_SNAP_M: float = 4.0
const POSITION_EPSILON_M: float = 0.05

const ENCLOSURE_KINDS: Array[String] = [
	"floor_edge",
	"corridor_edge",
	"wall_base",
	"wall_end",
	"wall_edge",
	"portal_edge",
	"portal_center",
	"inner_corner_vertex",
	"outer_corner_vertex",
	"ceiling_edge",
	"floor_top",
	"ceiling_bottom",
]

var kit_id: String = ""
var modules: Dictionary = {}


func load_kit(p_kit_id: String) -> bool:
	modules.clear()
	kit_id = p_kit_id if not p_kit_id.is_empty() else DEFAULT_KIT_ID
	if not _load_kit_directory(kit_id) or modules.is_empty():
		if kit_id != DEFAULT_KIT_ID:
			_load_kit_directory(DEFAULT_KIT_ID)
	return not modules.is_empty()


func has_module(module_id: String) -> bool:
	return modules.has(module_id)


func sockets_of(module_id: String) -> Array:
	if not modules.has(module_id):
		return []
	var record_variant: Variant = modules[module_id]
	if typeof(record_variant) != TYPE_DICTIONARY:
		return []
	var sockets_variant: Variant = (record_variant as Dictionary).get("sockets", [])
	if typeof(sockets_variant) != TYPE_ARRAY:
		return []
	return sockets_variant


func kinds_of(module_id: String) -> Array[String]:
	var kinds: Array[String] = []
	for socket_variant in sockets_of(module_id):
		if typeof(socket_variant) != TYPE_DICTIONARY:
			continue
		var kind: String = str((socket_variant as Dictionary).get("kind", ""))
		if not kind.is_empty() and not kinds.has(kind):
			kinds.append(kind)
	return kinds


func has_kind(module_id: String, kind: String) -> bool:
	return kinds_of(module_id).has(kind)


func has_all_kinds(module_id: String, required_kinds: Array) -> bool:
	var kinds: Array[String] = kinds_of(module_id)
	for kind_variant in required_kinds:
		if not kinds.has(str(kind_variant)):
			return false
	return true


func module_family(module_id: String) -> String:
	if not modules.has(module_id):
		return ""
	var record_variant: Variant = modules[module_id]
	if typeof(record_variant) != TYPE_DICTIONARY:
		return ""
	return str((record_variant as Dictionary).get("module_family", ""))


func choose_module(required_kinds: Array, preferred_id: String = "") -> String:
	if not preferred_id.is_empty() and has_module(preferred_id) and has_all_kinds(preferred_id, required_kinds):
		return preferred_id
	var ids: Array = modules.keys()
	ids.sort()
	for id_variant in ids:
		var module_id: String = str(id_variant)
		if has_all_kinds(module_id, required_kinds):
			return module_id
	if not preferred_id.is_empty() and has_module(preferred_id):
		return preferred_id
	return ""


func sockets_compatible(socket_a: Dictionary, socket_b: Dictionary) -> bool:
	var kind_a: String = str(socket_a.get("kind", ""))
	var kind_b: String = str(socket_b.get("kind", ""))
	if kind_a.is_empty() or kind_b.is_empty():
		return false
	if not ENCLOSURE_KINDS.has(kind_a) or not ENCLOSURE_KINDS.has(kind_b):
		return false
	var compatible_a: Array = _compatible_kinds(socket_a)
	var compatible_b: Array = _compatible_kinds(socket_b)
	if compatible_a.is_empty():
		compatible_a = [kind_a]
	if compatible_b.is_empty():
		compatible_b = [kind_b]
	return compatible_a.has(kind_b) and compatible_b.has(kind_a)


func world_socket_position(placement_position: Vector3, yaw_degrees: float, local_position: Vector3) -> Vector3:
	var rotated: Vector3 = local_position.rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	return placement_position + rotated


func positions_agree(world_a: Vector3, world_b: Vector3) -> bool:
	if world_a.distance_to(world_b) <= POSITION_EPSILON_M:
		return true
	var snap_a: Vector3 = _snap_to_grid(world_a)
	var snap_b: Vector3 = _snap_to_grid(world_b)
	return snap_a.is_equal_approx(snap_b)


func socket_local_position(socket: Dictionary) -> Vector3:
	return _vec3(socket.get("position_m", socket.get("position", [])))


func _load_kit_directory(load_kit_id: String) -> bool:
	var dir_path: String = CONTRACTS_ROOT.path_join(load_kit_id)
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return false
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with("_contract.json"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for file_name in names:
		_load_contract(dir_path.path_join(file_name))
	if not names.is_empty():
		kit_id = load_kit_id
	return not modules.is_empty()


func _load_contract(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var contract: Dictionary = parsed
	var module_id: String = str(contract.get("module_id", contract.get("asset_id", "")))
	if module_id.is_empty():
		var asset_variant: Variant = contract.get("asset", null)
		if typeof(asset_variant) == TYPE_DICTIONARY:
			module_id = str((asset_variant as Dictionary).get("module_id", (asset_variant as Dictionary).get("id", "")))
	if module_id.is_empty():
		return
	var sockets: Array = _sockets_of_contract(contract)
	modules[module_id] = {
		"module_id": module_id,
		"module_family": str(contract.get("module_family", "")),
		"kit_id": str(contract.get("kit_id", kit_id)),
		"sockets": sockets,
		"path": path,
	}


func _sockets_of_contract(contract: Dictionary) -> Array:
	var sockets_variant: Variant = contract.get("sockets", null)
	if typeof(sockets_variant) == TYPE_ARRAY and not (sockets_variant as Array).is_empty():
		return (sockets_variant as Array).duplicate(true)
	var asset_variant: Variant = contract.get("asset", null)
	if typeof(asset_variant) == TYPE_DICTIONARY:
		var nested: Variant = (asset_variant as Dictionary).get("sockets", [])
		if typeof(nested) == TYPE_ARRAY:
			return (nested as Array).duplicate(true)
	return []


func _compatible_kinds(socket: Dictionary) -> Array:
	var kinds_variant: Variant = socket.get("compatible_kinds", [])
	if typeof(kinds_variant) != TYPE_ARRAY:
		return []
	return kinds_variant


func _snap_to_grid(value: Vector3) -> Vector3:
	return Vector3(
		snappedf(value.x, GRID_SNAP_M),
		snappedf(value.y, GRID_SNAP_M),
		snappedf(value.z, GRID_SNAP_M)
	)


func _vec3(raw: Variant) -> Vector3:
	if typeof(raw) == TYPE_VECTOR3:
		return raw
	if typeof(raw) != TYPE_ARRAY:
		return Vector3.ZERO
	var arr: Array = raw
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
