extends RefCounted

## Procgen fixtures produced by the pure-GDScript layout pipeline
## (ShipLayoutGenerator), never ShipGenerator.generate_from_seed (which routes
## to the native DerelictGenerator GDExtension on Windows).

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const SeedDeterminismContractScript := preload("res://scripts/procgen/seed_determinism_contract.gd")

const SEED17_LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const SEED17_GAMEPLAY_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
const DERELICT_ARCHETYPE_PATH: String = "res://data/procgen/archetypes/derelict.json"
const DEBUG_EXPORT_SEEDS: Array = [42, 777, 999, 7777]
const BIOME_DIR: String = "res://data/procgen/biomes"
const DIFFICULTY_DIR: String = "res://data/procgen/difficulty"
const MATRIX_SEED: int = 42

var summary: Dictionary = {}


func run(writer) -> bool:
	var ok: bool = true
	ok = _seed17(writer) and ok
	for seed_variant in DEBUG_EXPORT_SEEDS:
		ok = _debug_export_recipe(writer, int(seed_variant)) and ok
	ok = _biome_difficulty_matrix(writer) and ok
	return ok


func _size_name(size: int) -> String:
	for key in ShipBlueprintScript.Size.keys():
		if int(ShipBlueprintScript.Size[key]) == size:
			return str(key)
	return str(size)


func _condition_name(condition: int) -> String:
	for key in ShipBlueprintScript.Condition.keys():
		if int(ShipBlueprintScript.Condition[key]) == condition:
			return str(key)
	return str(condition)


func _blueprint_record(blueprint) -> Dictionary:
	return {
		"size": int(blueprint.size),
		"size_name": _size_name(int(blueprint.size)),
		"condition": int(blueprint.condition),
		"condition_name": _condition_name(int(blueprint.condition)),
		"seed_value": int(blueprint.seed_value),
		"room_count_range": [int(blueprint.room_count_range.x), int(blueprint.room_count_range.y)],
	}


## Production pure-data slice step (mirrors ShipGenerator._load_layout_as_scene
## minus the file writes / GeneratedShipLoader): recompile the structural plan
## only when the generator did not stamp a validated one, build the gameplay
## slice, and copy builder arc_zones onto the layout when the layout has none.
func _production_slice(layout: Dictionary) -> Dictionary:
	var plan_variant: Variant = layout.get("structural_plan", {})
	var plan_ready: bool = plan_variant is Dictionary \
		and not (plan_variant as Dictionary).is_empty() \
		and bool(layout.get("structural_plan_validated", false))
	var recompiled: bool = false
	if not plan_ready:
		var structural_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(layout)
		var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
		if not bool(verdict.get("ok", false)):
			return {"ok": false, "error": "structural validation failed: %s" % JSON.stringify(verdict.get("errors", []))}
		layout["structural_plan"] = structural_plan
		layout["structural_plan_validated"] = true
		recompiled = true
	var gameplay: Dictionary = GameplaySliceBuilderScript.new().build(layout)
	var arcs_copied: bool = _copy_arcs(layout, gameplay)
	return {"ok": true, "gameplay": gameplay, "recompiled_plan": recompiled, "arc_zones_copied_to_layout": arcs_copied}


func _copy_arcs(layout: Dictionary, gameplay: Dictionary) -> bool:
	var layout_arcs: Variant = layout.get("arc_zones", [])
	var slice_arcs: Variant = gameplay.get("arc_zones", [])
	if (not (layout_arcs is Array) or (layout_arcs as Array).is_empty()) \
			and slice_arcs is Array and not (slice_arcs as Array).is_empty():
		layout["arc_zones"] = (slice_arcs as Array).duplicate(true)
		return true
	return false


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_tag(writer, tag: String, layout: Dictionary, gameplay: Dictionary, recipe: Dictionary) -> bool:
	# SeedDeterminismContract-style fingerprint of the raw (non-canonical)
	# JSON.stringify(layout, "  ") text, i.e. what ShipGenerator writes to
	# user://procgen_temp/layout.json.
	var raw_text: String = JSON.stringify(layout, "  ")
	recipe["fingerprints"] = {
		"layout_fnv1a_64_raw_stringify_2space": SeedDeterminismContractScript.fnv1a_64(raw_text),
		"layout_raw_stringify_2space_length": raw_text.length(),
		"note": "fnv1a_64 over JSON.stringify(layout, \"  \") BEFORE canonicalization (Vector2i values render as \"(x, y)\" strings there).",
	}
	var ok: bool = writer.write_json("procgen/layout_%s.json" % tag, layout)
	ok = writer.write_json("procgen/gameplay_slice_%s.json" % tag, gameplay) and ok
	ok = writer.write_json("procgen/recipe_%s.json" % tag, recipe) and ok
	summary[tag] = {
		"rooms": (layout.get("rooms", []) as Array).size() if layout.get("rooms", []) is Array else -1,
		"template_id": str(layout.get("template_id", "")),
		"objectives": (gameplay.get("objectives", []) as Array).size() if gameplay.get("objectives", []) is Array else -1,
	}
	return ok


# --- seed 17 (refresh_seed_000017_fixture.gd recipe) ---------------------------

func _seed17(writer) -> bool:
	var tag: String = "s17_medium_pristine"
	var blueprint = ShipBlueprintScript.new(ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 17)
	var blueprint_record: Dictionary = _blueprint_record(blueprint)
	var layout: Dictionary = ShipLayoutGeneratorScript.new().generate_with_options(blueprint, {}, "", "", false)
	if layout.is_empty():
		writer.errors.append("%s: layout generation returned empty" % tag)
		return false
	var structural_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(layout)
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
	if not bool(verdict.get("ok", false)):
		writer.errors.append("%s: structural validation failed %s" % [tag, JSON.stringify(verdict.get("errors", []))])
		return false
	layout["structural_plan"] = structural_plan
	var gameplay: Dictionary = GameplaySliceBuilderScript.new().build(layout)
	if gameplay.is_empty() or not (gameplay.get("objectives", []) is Array) or (gameplay.get("objectives", []) as Array).is_empty():
		writer.errors.append("%s: gameplay slice returned no objectives" % tag)
		return false
	var arcs_copied: bool = _copy_arcs(layout, gameplay)

	var comparison: Dictionary = _compare_with_checked_in(writer, layout, gameplay)
	var recipe: Dictionary = {
		"tag": tag,
		"recipe_source": "res://scripts/validation/refresh_seed_000017_fixture.gd",
		"blueprint": blueprint_record,
		"generator_call": "ShipLayoutGenerator.new().generate_with_options(blueprint, {}, \"\", \"\", false)",
		"archetype": {},
		"biome_id": "",
		"difficulty_id": "",
		"extended_templates": false,
		"post_steps": [
			"structural_plan = StructuralEdgeCompiler.new().compile(layout); StructuralPlanValidator.new().validate(plan, layout) must be ok; layout.structural_plan = plan (recompiled even though generate_with_options already stamped one)",
			"gameplay = GameplaySliceBuilder.new().build(layout)",
			"if layout.arc_zones is empty and gameplay.arc_zones is not: layout.arc_zones = gameplay.arc_zones.duplicate(true)",
		],
		"arc_zones_copied_to_layout": arcs_copied,
		"serialization": "canonical (Vector2i/Vector3 -> arrays, sorted keys), JSON.stringify(value, \"\\t\"); the refresh script itself writes JSON.stringify(layout, \"  \") without canonicalization",
		"checked_in_comparison": comparison,
	}
	summary["seed17_comparison"] = comparison
	return _write_tag(writer, tag, layout, gameplay, recipe)


func _compare_with_checked_in(writer, layout: Dictionary, gameplay: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for pair in [["layout", SEED17_LAYOUT_PATH, layout], ["gameplay_slice", SEED17_GAMEPLAY_PATH, gameplay]]:
		var key: String = pair[0]
		var path: String = pair[1]
		var generated: Dictionary = pair[2]
		if not FileAccess.file_exists(path):
			result[key] = {"checked_in_path": path, "exists": false}
			continue
		# Normalize CRLF (core.autocrlf checkouts) to the git blob's LF bytes.
		var checked_text: String = FileAccess.get_file_as_string(path).replace("\r\n", "\n")
		var refresh_style_text: String = JSON.stringify(generated, "  ")
		var generated_parsed: Variant = JSON.parse_string(JSON.stringify(writer.canonical(generated)))
		var checked_parsed: Variant = JSON.parse_string(checked_text)
		var diffs: Array = []
		writer.diff_paths(checked_parsed, generated_parsed, "$", diffs, 60)
		var top_level_keys_checked: Array = (checked_parsed as Dictionary).keys() if checked_parsed is Dictionary else []
		var top_level_keys_generated: Array = (generated_parsed as Dictionary).keys() if generated_parsed is Dictionary else []
		top_level_keys_checked.sort()
		top_level_keys_generated.sort()
		result[key] = {
			"checked_in_path": path,
			"exists": true,
			"byte_identical_to_refresh_style_stringify_2space": refresh_style_text == checked_text,
			"refresh_style_length": refresh_style_text.length(),
			"checked_in_length": checked_text.length(),
			"semantically_equal": writer.deep_equal(checked_parsed, generated_parsed),
			"first_differences_checked_vs_generated": diffs,
			"checked_in_generator_block": (checked_parsed as Dictionary).get("generator", {}) if checked_parsed is Dictionary else {},
			"top_level_keys_only_in_checked_in": top_level_keys_checked.filter(func(k): return not top_level_keys_generated.has(k)),
			"top_level_keys_only_in_generated": top_level_keys_generated.filter(func(k): return not top_level_keys_checked.has(k)),
		}
	return result


# --- procgen_structural_debug_export.gd recipe ----------------------------------

func _debug_derelict_archetype() -> Dictionary:
	return {
		"name": "Derelict",
		"type": "derelict",
		"template": "derelict_a",
		"guaranteed_roles": [],
		"role_weights": {},
		"max_duplicates": 3,
	}


func _debug_export_recipe(writer, seed_value: int) -> bool:
	var tag: String = "s%d_small_wrecked_ext" % seed_value
	var blueprint = ShipBlueprintScript.new(ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Condition.WRECKED, seed_value)
	blueprint.room_count_range = Vector2i(5, 8)
	var blueprint_record: Dictionary = _blueprint_record(blueprint)
	var archetype: Dictionary = _debug_derelict_archetype()
	var layout: Dictionary = ShipLayoutGeneratorScript.new().generate_with_options(blueprint, archetype, "", "", true)
	if layout.is_empty():
		writer.errors.append("%s: layout generation returned empty" % tag)
		return false
	var slice: Dictionary = _production_slice(layout)
	if not bool(slice.get("ok", false)):
		writer.errors.append("%s: %s" % [tag, str(slice.get("error", ""))])
		return false
	var recipe: Dictionary = {
		"tag": tag,
		"recipe_source": "res://scripts/validation/procgen_structural_debug_export.gd (_export_seed generation inputs)",
		"blueprint": blueprint_record,
		"blueprint_overrides": {"room_count_range": [5, 8]},
		"generator_call": "ShipLayoutGenerator.new().generate_with_options(blueprint, archetype, \"\", \"\", true)",
		"archetype": archetype,
		"biome_id": "",
		"difficulty_id": "",
		"extended_templates": true,
		"post_steps": [
			"layout written as returned by generate_with_options (NOT the debug exporter's sorted/canonicalized compiler input; see procgen/structural_debug/seed_<n>/ for the exporter's own documents)",
			"production slice step (ShipGenerator._load_layout_as_scene data path): recompile structural plan only if structural_plan_validated is not true; gameplay = GameplaySliceBuilder.new().build(layout); copy gameplay.arc_zones to layout when layout.arc_zones is empty",
		],
		"recompiled_plan": slice.get("recompiled_plan", false),
		"arc_zones_copied_to_layout": slice.get("arc_zones_copied_to_layout", false),
		"serialization": "canonical (Vector2i/Vector3 -> arrays, sorted keys), JSON.stringify(value, \"\\t\")",
	}
	return _write_tag(writer, tag, layout, slice["gameplay"], recipe)


# --- biome x difficulty matrix (ShipGenerator.generate() production data path) ---

func _ids_in(dir_path: String) -> Array:
	var ids: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return ids
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			var parsed: Variant = _load_json(dir_path.path_join(file_name))
			var id: String = file_name.get_basename()
			if parsed is Dictionary and not str((parsed as Dictionary).get("id", "")).is_empty():
				id = str(parsed["id"])
			if not ids.has(id):
				ids.append(id)
	ids.sort()
	return ids


func _biome_difficulty_matrix(writer) -> bool:
	var ok: bool = true
	var biomes: Array = _ids_in(BIOME_DIR)
	var difficulties: Array = _ids_in(DIFFICULTY_DIR)
	var archetype_variant: Variant = _load_json(DERELICT_ARCHETYPE_PATH)
	if not (archetype_variant is Dictionary):
		writer.errors.append("cannot load %s" % DERELICT_ARCHETYPE_PATH)
		return false
	var archetype: Dictionary = archetype_variant
	summary["matrix_biomes"] = biomes
	summary["matrix_difficulties"] = difficulties
	for biome_variant in biomes:
		for difficulty_variant in difficulties:
			var biome_id: String = str(biome_variant)
			var difficulty_id: String = str(difficulty_variant)
			var tag: String = "s%d_%s_%s" % [MATRIX_SEED, biome_id, difficulty_id]
			var blueprint = ShipBlueprintScript.new(ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Condition.DAMAGED, MATRIX_SEED)
			var blueprint_record: Dictionary = _blueprint_record(blueprint)
			# ShipGenerator.generate(): empty archetype + run context -> derelict.json;
			# _extended_for(difficulty_id) == not difficulty_id.is_empty().
			var extended: bool = not difficulty_id.is_empty()
			var layout: Dictionary = ShipLayoutGeneratorScript.new().generate_with_options(
				blueprint, archetype.duplicate(true), biome_id, difficulty_id, extended)
			if layout.is_empty():
				writer.errors.append("%s: layout generation returned empty" % tag)
				ok = false
				continue
			var slice: Dictionary = _production_slice(layout)
			if not bool(slice.get("ok", false)):
				writer.errors.append("%s: %s" % [tag, str(slice.get("error", ""))])
				ok = false
				continue
			var recipe: Dictionary = {
				"tag": tag,
				"recipe_source": "res://scripts/procgen/ship_generator.gd generate() data path (configure_run_context(biome, difficulty) then generate(blueprint, {})); blueprint size/condition as procgen_variation_smoke.gd (Blueprint.new(1, 1, seed))",
				"blueprint": blueprint_record,
				"generator_call": "ShipLayoutGenerator.new().generate_with_options(blueprint, derelict_archetype, biome_id, difficulty_id, extended_templates)",
				"archetype_source": DERELICT_ARCHETYPE_PATH,
				"archetype": archetype,
				"biome_id": biome_id,
				"difficulty_id": difficulty_id,
				"biome_source": "%s/%s.json" % [BIOME_DIR, biome_id],
				"difficulty_source": "%s/%s.json" % [DIFFICULTY_DIR, difficulty_id],
				"extended_templates": extended,
				"post_steps": [
					"production slice step (ShipGenerator._load_layout_as_scene data path): recompile structural plan only if structural_plan_validated is not true; gameplay = GameplaySliceBuilder.new().build(layout); copy gameplay.arc_zones to layout when layout.arc_zones is empty",
				],
				"recompiled_plan": slice.get("recompiled_plan", false),
				"arc_zones_copied_to_layout": slice.get("arc_zones_copied_to_layout", false),
				"serialization": "canonical (Vector2i/Vector3 -> arrays, sorted keys), JSON.stringify(value, \"\\t\")",
			}
			ok = _write_tag(writer, tag, layout, slice["gameplay"], recipe) and ok
	return ok
