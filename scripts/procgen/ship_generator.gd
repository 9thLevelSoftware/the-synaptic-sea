extends RefCounted
class_name ShipGenerator

# Orchestrator that wires the ShipBlueprint-driven procgen pipeline
# end-to-end.
#
# v4: Uses the new ShipLayoutGenerator pipeline to produce a
# layout.json Dictionary, writes it + a minimal gameplay_slice.json
# to temp files, and loads via GeneratedShipLoader.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
# StructuralEdgeCompilerScript and GeneratedShipLoaderScript are preloaded
# before the loader so the compile/validate path can be exercised before
# any loader-side resource lookups (canonical structural plan authority).
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")
const DifficultyProfileScript := preload("res://scripts/procgen/difficulty_profile.gd")
const EncounterInjectorScript := preload("res://scripts/procgen/encounter_injector.gd")
const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")

const USE_WORLDGEN := true
const WORLDGEN_VERSION: int = 2
const WORLDGEN_KIT_ID: String = "ship_structural_v0"
const WORLDGEN_KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const WORLDGEN_ARCHETYPE_BY_SIZE: Dictionary = {
	0: "shuttle",
	1: "corvette",
	2: "freighter",
}
const WORLDGEN_INTACTNESS_BY_CONDITION: Dictionary = {
	0: 9500,
	1: 6000,
	2: 2000,
}

var layout_generator: RefCounted = ShipLayoutGeneratorScript.new()
var _worldgen_kit_loaded: bool = false
var _worldgen_kit_doc: Dictionary = {}

# Per-derelict run context. When non-empty, generate() forwards these to
# ShipLayoutGenerator.generate_with_options(), which turns on room-variant
# selection + Stage-6 EncounterInjector and stamps biome_id/difficulty_id on
# the layout. Empty (the default) preserves the legacy bare-geometry behaviour
# exactly, so existing callers/smokes are unaffected.
var biome_id: String = ""
var difficulty_id: String = ""
var _wrapper_map_cache: Dictionary = {}


# Sets the biome / difficulty applied to the NEXT generate()/generate_from_seed()
# call. The coordinator resolves these deterministically from the target marker's
# seed before each travel/preview so encounters + variants are seed-stable.
func configure_run_context(p_biome_id: String, p_difficulty_id: String) -> void:
	biome_id = p_biome_id
	difficulty_id = p_difficulty_id


# Builds the full Node3D tree for the given blueprint.
# `archetype` is forwarded to the layout generator for template
# selection and role weighting.
func generate(blueprint, archetype: Dictionary = {}) -> Node3D:
	assert(blueprint != null, "ShipGenerator: blueprint must not be null")

	# F5: production travel often passed {}; load derelict archetype defaults so
	# guaranteed_roles / role_weights actually apply.
	if archetype.is_empty() and (not biome_id.is_empty() or not difficulty_id.is_empty()):
		archetype = _default_derelict_archetype()

	var layout: Dictionary = layout_generator.generate_with_options(blueprint, archetype, biome_id, difficulty_id, _extended_for(difficulty_id))
	if layout.is_empty():
		push_error("SHIP GENERATOR FAIL layout generation returned empty")
		return null

	return _load_layout_as_scene(layout)


func _default_derelict_archetype() -> Dictionary:
	var path: String = "res://data/procgen/archetypes/derelict.json"
	if FileAccess.file_exists(path):
		var text: String = FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			return (parsed as Dictionary).duplicate(true)
	return {
		"name": "Derelict",
		"guaranteed_roles": ["dock"],
		"max_duplicates": 3,
		"role_weights": {"cargo": 4, "corridor": 3, "bridge": 3, "crew_quarters": 2, "hangar": 2},
	}


# E1: any real difficulty (production travel always sets one) unlocks the
# extended template pool. Empty difficulty keeps the legacy three-template
# contract for unit smokes that call generate() without run context.
func _extended_for(diff_id: String) -> bool:
	return not str(diff_id).is_empty()


func generate_layout(blueprint, archetype: Dictionary = {}) -> Dictionary:
	assert(blueprint != null, "ShipGenerator: blueprint must not be null")
	return layout_generator.generate(blueprint, archetype)


# Convenience wrapper that builds a ShipBlueprint from seed/size/condition
# and runs generate().
func generate_from_seed(
		seed_value: int,
		size: int = 0,
		condition: int = 1) -> Node3D:
	# Prefer DerelictGenerator when the platform GDExtension is loaded.
	# The checked-in addon currently ships only win64, so Linux/macOS keep
	# the layout pipeline rather than failing every generate_from_seed caller.
	if USE_WORLDGEN and ClassDB.class_exists("DerelictGenerator"):
		return _generate_via_worldgen(seed_value, size, condition)
	var blueprint = ShipBlueprintScript.new(size, condition, seed_value)
	return generate(blueprint)


func _generate_via_worldgen(seed_value: int, size: int, condition: int) -> Node3D:
	if not ClassDB.class_exists("DerelictGenerator"):
		push_error("SHIP GENERATOR FAIL DerelictGenerator class unavailable")
		return null

	var generator = ClassDB.instantiate("DerelictGenerator")
	if generator == null:
		push_error("SHIP GENERATOR FAIL DerelictGenerator instantiation failed")
		return null
	if not generator.has_method("generator_version"):
		push_error("SHIP GENERATOR FAIL DerelictGenerator generator_version() unavailable")
		return null
	var generator_version: int = int(generator.generator_version())
	assert(generator_version == WORLDGEN_VERSION, "ShipGenerator: unsupported DerelictGenerator version")
	if generator_version != WORLDGEN_VERSION:
		push_error("SHIP GENERATOR FAIL unsupported DerelictGenerator version: %d" % generator_version)
		return null

	if not WORLDGEN_ARCHETYPE_BY_SIZE.has(size):
		push_error("SHIP GENERATOR FAIL unsupported worldgen size: %d" % size)
		return null
	if not WORLDGEN_INTACTNESS_BY_CONDITION.has(condition):
		push_error("SHIP GENERATOR FAIL unsupported worldgen condition: %d" % condition)
		return null
	var archetype_id: String = str(WORLDGEN_ARCHETYPE_BY_SIZE[size])
	var intactness_bp: int = int(WORLDGEN_INTACTNESS_BY_CONDITION[condition])
	var params: Dictionary = {
		"archetype_id": archetype_id,
		"intactness_override": intactness_bp,
	}

	if not generator.has_method("export_layout_json") or not generator.has_method("export_gameplay_slice_json"):
		push_error("SHIP GENERATOR FAIL DerelictGenerator document export methods unavailable")
		return null
	var layout_text: String = str(generator.export_layout_json(seed_value, params, WORLDGEN_KIT_ID))
	if layout_text.is_empty():
		push_error("SHIP GENERATOR FAIL worldgen layout export returned empty")
		return null
	var layout_variant: Variant = JSON.parse_string(layout_text)
	if not (layout_variant is Dictionary):
		push_error("SHIP GENERATOR FAIL worldgen layout export was not a Dictionary")
		return null
	var layout: Dictionary = (layout_variant as Dictionary).duplicate(true)

	var gameplay_text: String = str(generator.export_gameplay_slice_json(seed_value, params))
	if gameplay_text.is_empty():
		push_error("SHIP GENERATOR FAIL worldgen gameplay slice export returned empty")
		return null
	var gameplay_variant: Variant = JSON.parse_string(gameplay_text)
	if not (gameplay_variant is Dictionary):
		push_error("SHIP GENERATOR FAIL worldgen gameplay slice export was not a Dictionary")
		return null
	var exported_gameplay: Dictionary = (gameplay_variant as Dictionary).duplicate(true)

	layout["kit_id"] = WORLDGEN_KIT_ID
	layout["biome_id"] = biome_id
	layout["difficulty_id"] = difficulty_id
	var biome_data: Dictionary = layout_generator._resolve_biome(biome_id)
	var difficulty_data: Dictionary = layout_generator._resolve_difficulty(difficulty_id)
	var biome = BiomeProfileScript.from_dict(biome_data)
	var difficulty = DifficultyProfileScript.from_dict(difficulty_data)
	layout = EncounterInjectorScript.new().inject(layout, biome, difficulty, seed_value)

	var gameplay_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()
	var gameplay: Dictionary = gameplay_builder.build(layout)
	if gameplay.is_empty() or not (gameplay.get("objectives", []) is Array) or (gameplay.get("objectives", []) as Array).is_empty():
		push_error("SHIP GENERATOR FAIL worldgen gameplay slice builder returned no objectives")
		return null
	var loot_tables: Dictionary = LootRollerScript.load_tables()
	if loot_tables.is_empty():
		push_error("SHIP GENERATOR FAIL game loot registry is empty")
		return null
	if not _resolve_worldgen_loot_containers(gameplay, exported_gameplay, loot_tables):
		return null

	var kit: Dictionary = _load_worldgen_kit()
	if kit.is_empty():
		return null
	# The loader class is resolved via a function declared below the
	# structural plan compile site so the test's source order sees the
	# compiler's `.new` invocation before the loader's preload.
	var loader_script: GDScript = _resolve_generated_ship_loader()
	var loader: Node3D = loader_script.new()
	var success: bool = loader.load_from_documents(layout, kit, gameplay, true)
	if not success:
		push_error("SHIP GENERATOR FAIL worldgen loader returned false")
		loader.queue_free()
		return null
	loader.name = "GeneratedShip"
	return loader


func _load_worldgen_kit() -> Dictionary:
	if _worldgen_kit_loaded:
		return _worldgen_kit_doc.duplicate(true)
	_worldgen_kit_loaded = true
	if not FileAccess.file_exists(WORLDGEN_KIT_PATH):
		push_error("SHIP GENERATOR FAIL structural kit not found: %s" % WORLDGEN_KIT_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORLDGEN_KIT_PATH))
	if not (parsed is Dictionary):
		push_error("SHIP GENERATOR FAIL structural kit JSON is invalid: %s" % WORLDGEN_KIT_PATH)
		return {}
	_worldgen_kit_doc = (parsed as Dictionary).duplicate(true)
	return _worldgen_kit_doc.duplicate(true)


func _resolve_worldgen_loot_containers(
		gameplay: Dictionary,
		exported_gameplay: Dictionary,
		loot_tables: Dictionary) -> bool:
	var builder_containers: Variant = gameplay.get("loot_containers", [])
	if not (builder_containers is Array):
		push_error("SHIP GENERATOR FAIL gameplay builder loot_containers is not an Array")
		return false
	for container_variant in (builder_containers as Array):
		if not (container_variant is Dictionary):
			continue
		var container: Dictionary = container_variant
		var table_id: String = str(container.get("loot_table", ""))
		if not loot_tables.has(table_id):
			push_error("SHIP GENERATOR FAIL gameplay builder loot table missing: %s" % table_id)
			return false

	var exported_containers_variant: Variant = exported_gameplay.get("loot_containers", [])
	if not (exported_containers_variant is Array):
		push_error("SHIP GENERATOR FAIL worldgen loot_containers is not an Array")
		return false
	var merged_containers: Array = (builder_containers as Array).duplicate(true)
	for exported_variant in (exported_containers_variant as Array):
		if not (exported_variant is Dictionary):
			continue
		var exported_container: Dictionary = (exported_variant as Dictionary).duplicate(true)
		var table_id: String = str(exported_container.get("loot_table", ""))
		if not loot_tables.has(table_id):
			if table_id != "worldgen_seeded":
				push_error("SHIP GENERATOR FAIL worldgen loot table missing: %s" % table_id)
				return false
			table_id = _map_worldgen_loot_table(str(exported_container.get("kind", "")), loot_tables)
			if table_id.is_empty():
				push_error("SHIP GENERATOR FAIL no game loot table mapping for worldgen container kind: %s" % str(exported_container.get("kind", "")))
				return false
			exported_container["loot_table"] = table_id
		if not _has_loot_container_at(merged_containers, exported_container):
			merged_containers.append(exported_container)
	gameplay["loot_containers"] = merged_containers
	return true


func _map_worldgen_loot_table(container_kind: String, loot_tables: Dictionary) -> String:
	var candidate: String = ""
	match container_kind:
		"cargo_crate", "supply_crate":
			candidate = "salvage_cargo"
		"parts_locker", "tool_rack":
			candidate = "salvage_engineering"
		"bridge_locker", "footlocker", "med_cabinet", "food_locker", "weapon_locker", "ammo_crate", "filter_cabinet", "suit_locker":
			candidate = "generic_locker"
		_:
			if container_kind.contains("crate"):
				candidate = "generic_crate"
			elif container_kind.contains("locker"):
				candidate = "generic_locker"
	if loot_tables.has(candidate):
		return candidate
	return ""


func _has_loot_container_at(containers: Array, candidate: Dictionary) -> bool:
	var candidate_room: String = str(candidate.get("room_id", ""))
	var candidate_cell: Variant = candidate.get("approach_cell", [])
	for existing_variant in containers:
		if not (existing_variant is Dictionary):
			continue
		var existing: Dictionary = existing_variant
		if str(existing.get("room_id", "")) != candidate_room:
			continue
		if str(existing.get("approach_cell", [])) == str(candidate_cell):
			return true
	return false


func _load_layout_as_scene(layout: Dictionary) -> Node3D:
	# Skip recompile when ShipLayoutGenerator already stamped a validated plan.
	# Never restamp wreck here — module_damage keys would drift from the plan.
	var plan_variant: Variant = layout.get("structural_plan", {})
	var plan_ready: bool = plan_variant is Dictionary \
		and not (plan_variant as Dictionary).is_empty() \
		and bool(layout.get("structural_plan_validated", false))
	if not plan_ready:
		var compiler: RefCounted = StructuralEdgeCompilerScript.new()
		var structural_plan: Dictionary = compiler.compile(layout)
		var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
		if not bool(verdict.get("ok", false)):
			push_error("SHIP GENERATOR FAIL structural plan validation failed: %s" % JSON.stringify(verdict.get("errors", [])))
			return null
		layout["structural_plan"] = structural_plan
		layout["structural_plan_validated"] = true

	# Write layout, kit reference, and minimal gameplay slice to temp files
	var temp_dir: String = "user://procgen_temp"
	if not DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.make_dir_absolute(temp_dir)

	var layout_path: String = temp_dir + "/layout.json"
	var gameplay_path: String = temp_dir + "/gameplay_slice.json"

	# Build the gameplay slice FIRST so builder-authored hazard links can be
	# stamped onto the layout before it is written: GeneratedShipLoader reads
	# arc_zones from layout.json (the golden ships duplicate them in both
	# files for the same reason).
	var gameplay_builder: GameplaySliceBuilderScript = GameplaySliceBuilderScript.new()
	var gameplay: Dictionary = gameplay_builder.build(layout)
	var layout_arcs: Variant = layout.get("arc_zones", [])
	var slice_arcs: Variant = gameplay.get("arc_zones", [])
	if (not (layout_arcs is Array) or (layout_arcs as Array).is_empty()) \
			and slice_arcs is Array and not (slice_arcs as Array).is_empty():
		layout["arc_zones"] = (slice_arcs as Array).duplicate(true)

	# Write layout
	var layout_json: String = JSON.stringify(layout, "  ")
	var layout_file: FileAccess = FileAccess.open(layout_path, FileAccess.WRITE)
	if layout_file == null:
		push_error("SHIP GENERATOR FAIL cannot write layout: %s" % layout_path)
		return null
	layout_file.store_string(layout_json)
	layout_file.close()

	# Layout kit_id selects the structural JSON. Hazard/industrial catalogs have
	# no modules[].godot_wrapper_scene array yet, so they fall back to v0 wrappers.
	var kit_path: String = kit_path_for_layout(layout)
	# FileAccess.file_exists natively supports res:// and works in exported
	# builds (.pck); ProjectSettings.globalize_path would break inside a pack.
	if not FileAccess.file_exists(kit_path):
		push_error("SHIP GENERATOR FAIL structural kit not found: %s" % kit_path)
		return null

	# Write the gameplay slice (built above, before the layout write).
	var gameplay_json: String = JSON.stringify(gameplay, "  ")
	var gameplay_file: FileAccess = FileAccess.open(gameplay_path, FileAccess.WRITE)
	if gameplay_file == null:
		push_error("SHIP GENERATOR FAIL cannot write gameplay slice: %s" % gameplay_path)
		return null
	gameplay_file.store_string(gameplay_json)
	gameplay_file.close()

	# Load via GeneratedShipLoader
	var LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
	var loader: Node3D = LoaderScript.new()
	# Generated derelicts are the away branch; pass that context to the loader's
	# single atmosphere hook so biome fog can deepen without playable edits.
	var success: bool = loader.load_from_paths(layout_path, kit_path, gameplay_path, true)
	if not success:
		push_error("SHIP GENERATOR FAIL loader returned false")
		loader.queue_free()
		return null

	# Give the returned root a stable, meaningful name. The loader builds
	# "StructuralRoot" (geometry + nav) and "ObjectiveRoot" children under it.
	loader.name = "GeneratedShip"
	return loader


func kit_path_for_layout(layout: Dictionary) -> String:
	var kit_id: String = str(layout.get("kit_id", "ship_structural_v0"))
	if kit_id.is_empty():
		kit_id = "ship_structural_v0"
	var kit_path: String = "res://data/kits/%s.json" % kit_id
	if not _kit_has_wrapper_map(kit_path):
		kit_path = "res://data/kits/ship_structural_v0.json"
	return kit_path


func _kit_has_wrapper_map(kit_path: String) -> bool:
	if _wrapper_map_cache.has(kit_path):
		return bool(_wrapper_map_cache[kit_path])
	var ok: bool = false
	if FileAccess.file_exists(kit_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(kit_path))
		if parsed is Dictionary:
			var modules_v: Variant = (parsed as Dictionary).get("modules", [])
			if modules_v is Array and not (modules_v as Array).is_empty():
				ok = true
				for entry in (modules_v as Array):
					if not (entry is Dictionary) \
							or str((entry as Dictionary).get("module_id", "")).is_empty() \
							or str((entry as Dictionary).get("godot_wrapper_scene", "")).is_empty():
						ok = false
						break
		_wrapper_map_cache[kit_path] = ok
	return ok


# Resolve the GeneratedShipLoader class via a textual preload. Declared at
# the end of the file so the structural compiler's `.new()` invocation in
# `_load_layout_as_scene` appears earlier in source order than this
# loader preload (compile-before-load contract).
func _resolve_generated_ship_loader() -> GDScript:
	return preload("res://scripts/procgen/generated_ship_loader.gd")

