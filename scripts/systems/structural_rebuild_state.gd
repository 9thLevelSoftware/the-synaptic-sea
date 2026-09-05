extends RefCounted
class_name StructuralRebuildState

## Runtime registry of immutable, authored structural descriptors (ADR-0059).
## Replacement transactions and persistence are added by later feature cards.

## Stable placed module id -> immutable original descriptor.
var _originals: Dictionary = {}


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
