extends RefCounted
class_name FirstRunContract

## Data contract for the cold-player's first away derelict beat.
## The helper is pure at validation time: callers provide the generated layout
## and gameplay slice dictionaries, while seed selection remains deterministic.

const CONTRACT_PATH: String = "res://data/procgen/slice/first_run_contract.json"
const RoomVariantSelectorScript: GDScript = preload("res://scripts/procgen/room_variant_selector.gd")
const FireCompartmentResolverScript: GDScript = preload("res://scripts/procgen/fire_compartment_resolver.gd")

var contract: Dictionary = {}


func load_contract(path: String = CONTRACT_PATH) -> bool:
	contract = {}
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return false
	var data: Dictionary = parsed
	if str(data.get("version", "")) != "first-run-contract-1":
		return false
	if str(data.get("biome_id", "")).is_empty() or str(data.get("difficulty_id", "")).is_empty():
		return false
	if not (data.get("preferred_seeds", []) is Array) or (data.get("preferred_seeds", []) as Array).is_empty():
		return false
	contract = data.duplicate(true)
	return true


func validate(layout: Dictionary, gameplay_slice: Dictionary = {}) -> bool:
	if contract.is_empty() and not load_contract():
		return false
	if layout.is_empty() or gameplay_slice.is_empty():
		return false
	if not layout.has("biome_id") or str(layout.get("biome_id", "")) != str(contract.get("biome_id", "")):
		return false
	if not layout.has("difficulty_id") or str(layout.get("difficulty_id", "")) != str(contract.get("difficulty_id", "")):
		return false
	var critical_path: Variant = layout.get("critical_path", [])
	if not (critical_path is Array) or (critical_path as Array).size() < 2:
		return false
	var loot: Variant = gameplay_slice.get("loot_containers", [])
	if not (loot is Array) or (loot as Array).size() < int(contract.get("require_min_loot_containers", 0)):
		return false
	var encounters: Variant = layout.get("encounters", [])
	if not (encounters is Array) or (encounters as Array).size() < int(contract.get("require_min_encounters", 0)):
		return false
	var required_hazards: Variant = contract.get("require_any", [])
	if not (required_hazards is Array) or not _has_any_required_hazard(layout, gameplay_slice, required_hazards as Array):
		return false
	return true


## Returns the first preferred seed whose generated payload is accepted by the
## contract. A Dictionary maps seed -> {"layout": Dictionary,
## "gameplay_slice": Dictionary}; a Callable may be supplied when generation
## must happen lazily. Invalid candidates are simply skipped.
## If no preferred seed validates, the first preferred seed is returned so
## callers retain a deterministic fallback rather than introducing new RNG.
func pick_seed(candidates: Variant = null) -> int:
	if contract.is_empty() and not load_contract():
		return 0
	var preferred: Array = contract.get("preferred_seeds", []) as Array
	if preferred.is_empty():
		return 0
	for seed_variant in preferred:
		var seed_value: int = int(seed_variant)
		var candidate: Variant = null
		if candidates is Callable:
			var provider: Callable = candidates
			if provider.is_valid():
				candidate = provider.call(seed_value)
		elif candidates is Dictionary:
			candidate = (candidates as Dictionary).get(seed_value, {})
		if not (candidate is Dictionary):
			continue
		var candidate_dict: Dictionary = candidate
		if validate(candidate_dict.get("layout", {}), candidate_dict.get("gameplay_slice", {})):
			return seed_value
	return int(preferred[0])


func _has_any_required_hazard(layout: Dictionary, gameplay_slice: Dictionary, required: Array) -> bool:
	var available: Dictionary = {}
	_collect_hazard_array(layout.get("fire_zones", []), "fire_zone", available)
	_collect_hazard_array(layout.get("breach_zones", []), "breach_zone", available)
	_collect_hazard_array(gameplay_slice.get("fire_zones", []), "fire_zone", available)
	_collect_hazard_array(gameplay_slice.get("breach_zones", []), "breach_zone", available)
	var structural_plan: Variant = layout.get("structural_plan", {})
	if structural_plan is Dictionary:
		var edges: Variant = (structural_plan as Dictionary).get("edges", {})
		if edges is Dictionary:
			for edge_variant in (edges as Dictionary).values():
				if not (edge_variant is Dictionary):
					continue
				var edge: Dictionary = edge_variant
				if str(edge.get("kind", "")).to_upper() != "BREACH":
					continue
				var room_ids: Array = []
				var raw_room_ids: Variant = edge.get("room_ids", [])
				if raw_room_ids is Array:
					room_ids.append_array(raw_room_ids as Array)
				else:
					room_ids.append(edge.get("room_id", ""))
				for room_id_variant in room_ids:
					var room_id: String = str(room_id_variant).strip_edges()
					if room_id.is_empty():
						continue
					if not FireCompartmentResolverScript.from_room_id(room_id, [layout]).is_empty():
						available["breach_zone"] = true
						break
	# The live derelict path seeds hazards from room variants after loading. Count
	# those same authoritative variant effects here so seed validation exercises
	# the production generation contract rather than a smoke-only annotation.
	var rooms: Variant = layout.get("rooms", [])
	if rooms is Array:
		var selector = RoomVariantSelectorScript.new()
		const HAZARD_ROLES: Array[String] = [
			"bridge", "cockpit", "engineering", "reactor", "engine_bay",
			"hydroponics", "cargo", "storage",
		]
		for room_variant in rooms as Array:
			if not (room_variant is Dictionary):
				continue
			var room: Dictionary = room_variant
			var role: String = str(room.get("room_role", room.get("role", "")))
			if role not in HAZARD_ROLES:
				continue
			var variant: String = str(room.get("variant", "standard"))
			var hazard: Variant = (selector.effects_for(variant).get("sim", {}) as Dictionary).get("hazard", {})
			if hazard is Dictionary:
				var kind: String = str((hazard as Dictionary).get("kind", ""))
				if kind == "fire":
					available["fire_zone"] = true
				elif kind == "breach":
					available["breach_zone"] = true
	for required_variant in required:
		if available.has(str(required_variant)):
			return true
	return false


func _collect_hazard_array(value: Variant, key: String, available: Dictionary) -> void:
	if value is Array and not (value as Array).is_empty():
		available[key] = true
