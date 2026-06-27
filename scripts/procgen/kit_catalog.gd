extends RefCounted
class_name KitCatalog

# KitCatalog — registry of ship structural kits indexed by kit_id
# and role. Decouples the role -> module-list mapping from
# StructuralPlacer so hazard-biased, industrial-biased, or
# biome-specific kits can dress the same room role differently.
#
# Kits are JSON files under `res://data/kits/` whose top-level
# schema matches the existing ship_structural_v0.json shape but
# adds a `role_modules` field that maps role names to ordered
# Array[String] module lists. configure() walks the directory,
# parses every *.json file, and builds:
#
#   _kits: Dictionary
#       kit_id -> {
#           "kit_id": String,
#           "description": String,
#           "modules": Array[String],      # raw module list (legacy)
#           "role_modules": Dictionary,    # role -> Array[String]
#           "default_role_module": String, # module used when role is unknown
#           "biome_preference": Dictionary # biome -> float affinity
#       }
#
# Public surface:
#   configure(kits_dir: String) -> int
#   kits_for_role(role: String, biome: String = "") -> Array[String]
#   module_id_for_role(kit_id: String, role: String) -> String
#   is_loaded(kit_id: String) -> bool
#   loaded_kit_ids() -> Array[String]
#
# Backward compatibility:
#   If no kit is registered, kits_for_role() falls back to the
#   built-in FALLBACK_MODULES constant so legacy callers see a
#   single-element array. The default kit id is "ship_structural_v0"
#   if a JSON of that name is present, else the first registered kit.

const FALLBACK_MODULES: Array[String] = ["floor_1x1"]

# Default kit id consulted when callers don't specify one.
const DEFAULT_KIT_ID: String = "ship_structural_v0"

var _kits: Dictionary = {}
var _default_kit_id: String = ""


# Loads every *.json file under `kits_dir`. Returns the number of
# kits successfully loaded. A malformed kit file is logged via
# push_warning and skipped; the loader never raises so a partial
# catalog is still usable. Idempotent — calling configure() twice
# re-loads the catalog from disk.
func configure(kits_dir: String = "res://data/kits/") -> int:
	_kits = {}
	var abs_dir: String = ProjectSettings.globalize_path(kits_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		push_warning("KIT CATALOG FAIL kits_dir not found: %s" % abs_dir)
		_default_kit_id = ""
		return 0

	var dir: DirAccess = DirAccess.open(abs_dir)
	if dir == null:
		push_warning("KIT CATALOG FAIL cannot open kits_dir: %s" % abs_dir)
		_default_kit_id = ""
		return 0

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	var loaded: int = 0
	while entry != "":
		if entry.ends_with(".json"):
			var full_path: String = abs_dir + "/" + entry
			var kit: Dictionary = _load_kit_file(full_path)
			if not kit.is_empty():
				var kid: String = str(kit.get("kit_id", ""))
				if not kid.is_empty() and not _kits.has(kid):
					_kits[kid] = kit
					loaded += 1
		entry = dir.get_next()
	dir.list_dir_end()

	# Pick a default kit id.
	if _kits.has(DEFAULT_KIT_ID):
		_default_kit_id = DEFAULT_KIT_ID
	elif _kits.size() > 0:
		# Use the first registered kit id.
		_default_kit_id = str(_kits.keys()[0])
	else:
		_default_kit_id = ""

	return loaded


# Returns the module list for `role` from the default kit. If
# `biome` is supplied and the active kit has a `biome_preference`
# map, the catalog consults that map to pick the best kit for the
# biome (highest affinity wins). Returns FALLBACK_MODULES (copy)
# if no kit is registered or the role is unknown to the catalog.
func kits_for_role(role: String, biome: String = "") -> Array[String]:
	if _kits.is_empty():
		return FALLBACK_MODULES.duplicate()

	var kit_id: String = _default_kit_id
	if not biome.is_empty():
		var candidate: String = _best_kit_for_biome(biome)
		if not candidate.is_empty():
			kit_id = candidate

	if not _kits.has(kit_id):
		return FALLBACK_MODULES.duplicate()

	var kit: Dictionary = _kits[kit_id]
	var role_modules: Dictionary = kit.get("role_modules", {})
	if role_modules.has(role):
		var raw: Variant = role_modules[role]
		if raw is Array:
			var typed: Array[String] = []
			for entry in raw:
				typed.append(String(entry))
			if not typed.is_empty():
				return typed

	# Fall back to default_role_module if role is unknown.
	var default_module: String = str(kit.get("default_role_module", ""))
	if not default_module.is_empty():
		return [default_module]
	return FALLBACK_MODULES.duplicate()


# True iff the kit selected for `biome` (default kit when biome is empty)
# defines `role` explicitly in its role_modules map. Lets callers distinguish
# a deliberate kit mapping — including a single-module one like ["floor_1x1"] —
# from kits_for_role()'s value-based default/fallback, so they don't wrongly
# override a kit's intentional choice.
func has_role_for(role: String, biome: String = "") -> bool:
	if _kits.is_empty():
		return false
	var kit_id: String = _default_kit_id
	if not biome.is_empty():
		var candidate: String = _best_kit_for_biome(biome)
		if not candidate.is_empty():
			kit_id = candidate
	if not _kits.has(kit_id):
		return false
	var kit: Dictionary = _kits[kit_id]
	var role_modules: Dictionary = kit.get("role_modules", {})
	return role_modules.has(role)


# Returns a single module id for `role` from `kit_id`. Returns the
# catalog default for unknown roles or missing kits.
func module_id_for_role(kit_id: String, role: String) -> String:
	if not _kits.has(kit_id):
		return "floor_1x1"
	var kit: Dictionary = _kits[kit_id]
	var role_modules: Dictionary = kit.get("role_modules", {})
	if role_modules.has(role):
		var raw: Variant = role_modules[role]
		if raw is Array and not (raw as Array).is_empty():
			return str((raw as Array)[0])
	return str(kit.get("default_role_module", "floor_1x1"))


# True iff `kit_id` is registered.
func is_loaded(kit_id: String) -> bool:
	return _kits.has(kit_id)


# Returns a copy of the registered kit ids (sorted lexicographically
# for deterministic iteration).
func loaded_kit_ids() -> Array[String]:
	var ids: Array = _kits.keys()
	ids.sort()
	var typed: Array[String] = []
	for entry in ids:
		typed.append(str(entry))
	return typed


# Returns the id of the catalog's default kit (empty if no kits
# loaded).
func default_kit_id() -> String:
	return _default_kit_id


# --- Internal helpers ---


func _load_kit_file(abs_path: String) -> Dictionary:
	if not FileAccess.file_exists(abs_path):
		return {}
	var text: String = FileAccess.get_file_as_string(abs_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("KIT CATALOG FAIL invalid JSON: %s" % abs_path)
		return {}
	var data: Dictionary = parsed
	var kit_id: String = str(data.get("kit_id", ""))
	if kit_id.is_empty():
		push_warning("KIT CATALOG FAIL missing kit_id: %s" % abs_path)
		return {}

	var role_modules_raw: Variant = data.get("role_modules", {})
	var role_modules: Dictionary = {}
	if role_modules_raw is Dictionary:
		for role_key in (role_modules_raw as Dictionary).keys():
			var v: Variant = (role_modules_raw as Dictionary)[role_key]
			if v is Array:
				var typed: Array[String] = []
				for entry in v:
					typed.append(String(entry))
				if not typed.is_empty():
					role_modules[str(role_key)] = typed

	# If the kit ships only the legacy `modules` list (e.g. the
	# existing ship_structural_v0.json), populate role_modules for
	# the well-known role set from that list. The default module
	# is the first entry.
	#
	# `modules` may be either a flat list of module-id strings (legacy
	# kits) OR an array of module-catalog objects (the asset-manifest
	# schema used by ship_structural_v0.json). For the object form we
	# read each entry's `module_id`; stringifying the whole Dictionary
	# (the old behaviour) produced unusable stems.
	var raw_modules: Variant = data.get("modules", [])
	var legacy_modules: Array[String] = []
	if raw_modules is Array:
		for entry in raw_modules:
			if entry is Dictionary:
				var mid: String = str((entry as Dictionary).get("module_id", ""))
				if not mid.is_empty():
					legacy_modules.append(mid)
			else:
				legacy_modules.append(str(entry))
	# Honour an explicit `default_role_module` from the kit JSON; only
	# fall back to the first module in the list when the field is absent.
	var default_module: String = str(data.get("default_role_module", ""))
	if default_module.is_empty():
		if not legacy_modules.is_empty():
			default_module = str(legacy_modules[0])
		else:
			default_module = "floor_1x1"

	# Legacy fall-back: if no role_modules field, build a uniform
	# map from the legacy module list for the standard role set so
	# callers that ask for kits_for_role(role) get a real list.
	if role_modules.is_empty() and not legacy_modules.is_empty():
		var default_list: Array[String] = [default_module]
		var roles_needing_default: Array[String] = [
			"airlock", "corridor", "engineering", "life_support", "bridge",
			"cargo", "crew_quarters", "medical", "maintenance",
			"cockpit", "engine_bay", "compartment", "bay", "quarters",
			"dock", "reactor", "main_spine", "hub", "ramp", "elevator",
			"storage", "mess_hall", "armory", "hangar",
		]
		for role in roles_needing_default:
			role_modules[role] = default_list.duplicate()

	var biome_pref_raw: Variant = data.get("biome_preference", {})
	var biome_pref: Dictionary = {}
	if biome_pref_raw is Dictionary:
		for biome_key in (biome_pref_raw as Dictionary).keys():
			biome_pref[str(biome_key)] = float((biome_pref_raw as Dictionary)[biome_key])

	return {
		"kit_id": kit_id,
		"description": str(data.get("description", "")),
		"modules": legacy_modules,
		"role_modules": role_modules,
		"default_role_module": default_module,
		"biome_preference": biome_pref,
	}


# Returns the registered kit id with the highest biome_preference
# affinity for `biome_id`. Falls back to the default kit id if no
# kit declares an affinity. Returns "" only if no kits are loaded.
func _best_kit_for_biome(biome_id: String) -> String:
	if _kits.is_empty():
		return ""
	var best_kit: String = _default_kit_id
	var best_score: float = -INF
	for kit_id_variant in _kits.keys():
		var kit_id: String = str(kit_id_variant)
		var kit: Dictionary = _kits[kit_id]
		var pref: Dictionary = kit.get("biome_preference", {})
		if not pref.has(biome_id):
			continue
		var score: float = float(pref[biome_id])
		if score > best_score:
			best_score = score
			best_kit = kit_id
	return best_kit
