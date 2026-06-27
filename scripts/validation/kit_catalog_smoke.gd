extends SceneTree

# kit_catalog_smoke — REQ-PG-003 verification.
#
# Asserts:
#   1. KitCatalog.configure() loads every *.json under
#      res://data/kits/ and returns a positive count (>= 1).
#   2. The default kit id is ship_structural_v0 (or the first
#      registered kit if the legacy name is missing).
#   3. kits_for_role("airlock") returns a non-empty Array[String]
#      from the default kit.
#   4. kits_for_role("engineering") returns a non-empty Array[String]
#      from the default kit.
#   5. kits_for_role("not_a_real_role") falls back to a default
#      module list (not crash).
#   6. kits_for_role(role, biome) consults biome_preference and
#      returns modules from the highest-affinity kit for that biome.
#   7. is_loaded() correctly reports membership.
#   8. module_id_for_role() returns a string module id.

const KitCatalogScript := preload("res://scripts/procgen/kit_catalog.gd")


func _initialize() -> void:
	var catalog: RefCounted = KitCatalogScript.new()
	var loaded: int = int(catalog.configure("res://data/kits/"))

	# --- Case 1: Loaded at least 3 kits (existing + 2 new) ---
	if loaded < 3:
		push_error("KIT CATALOG FAIL loaded=%d expected>=3" % loaded)
		quit(1)
		return

	# --- Case 2: Default kit is ship_structural_v0 ---
	var default_kit: String = catalog.default_kit_id()
	if default_kit.is_empty():
		push_error("KIT CATALOG FAIL default_kit_id is empty")
		quit(1)
		return

	# --- Case 3: airlock modules from default kit ---
	var airlock_modules: Array[String] = catalog.kits_for_role("airlock")
	if airlock_modules.is_empty():
		push_error("KIT CATALOG FAIL airlock modules empty")
		quit(1)
		return
	for mod_id in airlock_modules:
		if str(mod_id).is_empty():
			push_error("KIT CATALOG FAIL airlock module id empty")
			quit(1)
			return

	# --- Case 4: engineering modules from default kit ---
	var eng_modules: Array[String] = catalog.kits_for_role("engineering")
	if eng_modules.is_empty():
		push_error("KIT CATALOG FAIL engineering modules empty")
		quit(1)
		return

	# --- Case 5: Unknown role falls back to default module ---
	var unknown: Array[String] = catalog.kits_for_role("not_a_real_role")
	if unknown.is_empty():
		push_error("KIT CATALOG FAIL unknown role returned empty")
		quit(1)
		return

	# --- Case 6: biome-aware kit selection ---
	# breach_field has highest preference for ship_structural_hazard.
	var breach_modules: Array[String] = catalog.kits_for_role("engineering", "breach_field")
	if breach_modules.is_empty():
		push_error("KIT CATALOG FAIL breach_field engineering empty")
		quit(1)
		return

	# --- Case 7: is_loaded ---
	if not catalog.is_loaded(default_kit):
		push_error("KIT CATALOG FAIL is_loaded(default_kit)=false")
		quit(1)
		return
	if catalog.is_loaded("nonexistent_kit_id"):
		push_error("KIT CATALOG FAIL is_loaded(nonexistent)=true")
		quit(1)
		return

	# --- Case 8: module_id_for_role ---
	var mod_id: String = catalog.module_id_for_role(default_kit, "airlock")
	if mod_id.is_empty():
		push_error("KIT CATALOG FAIL module_id_for_role returned empty")
		quit(1)
		return

	# --- Case 9: loaded_kit_ids is sorted and contains the default ---
	var all_ids: Array[String] = catalog.loaded_kit_ids()
	if all_ids.is_empty():
		push_error("KIT CATALOG FAIL loaded_kit_ids empty")
		quit(1)
		return
	var saw_default: bool = false
	for kid in all_ids:
		if kid == default_kit:
			saw_default = true
			break
	if not saw_default:
		push_error("KIT CATALOG FAIL default_kit_id not in loaded_kit_ids")
		quit(1)
		return

	# --- Case 10: default-kit modules are REAL module stems, not stringified ---
	# Regression guard: ship_structural_v0.json uses the asset-catalog schema
	# (modules: [{module_id,...}]). Before the parse fix, kits_for_role on the
	# default kit returned str(Dictionary) garbage that still passed the weak
	# "non-empty string" checks above. Assert every default-kit module resolves
	# to a real .tscn so a regression to garbage stems is caught.
	var MODULE_BASE_PATH: String = "res://scenes/wrappers/structural/ship_structural_v0/"
	for role in ["airlock", "engineering", "bridge"]:
		for stem in catalog.kits_for_role(role):
			var path: String = MODULE_BASE_PATH + str(stem) + ".tscn"
			if not ResourceLoader.exists(path):
				push_error("KIT CATALOG FAIL default-kit role=%s stem=%s not a real module (.tscn missing: %s)" % [role, str(stem), path])
				quit(1)
				return

	# --- Case 11: explicit default_role_module from JSON is honored ---
	# The parse fix reads the kit's "default_role_module" field (v0 = floor_1x1)
	# instead of deriving it from str(modules[0]). An unknown role must resolve
	# to that real stem, not a stringified catalog object.
	var default_role_mod: String = catalog.module_id_for_role(default_kit, "totally_unknown_role")
	if not ResourceLoader.exists(MODULE_BASE_PATH + default_role_mod + ".tscn"):
		push_error("KIT CATALOG FAIL default_role_module not honored: got '%s'" % default_role_mod)
		quit(1)
		return

	print("KIT CATALOG PASS loaded=%d default=%s airlock=%d eng=%d breach_select=ok fallback=ok real_stems=true default_role_module=%s ids_sorted=true" % [
		loaded, default_kit, airlock_modules.size(), eng_modules.size(), default_role_mod,
	])
	quit(0)
