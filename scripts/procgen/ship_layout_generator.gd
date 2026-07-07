extends RefCounted
class_name ShipLayoutGenerator

# Top-level orchestrator for the procgen layout pipeline.
# Runs the 5-stage pipeline:
#   TemplateSelector -> RoomAssigner -> CellLayoutEngine ->
#   WallDoorResolver -> LayoutSerializer
# Returns a complete layout.json Dictionary.
#
# Task 12 package extensions:
#   - generate() accepts biome_id / difficulty_id kwargs and forwards
#     them to RoomAssigner (for variant selection) and EncounterInjector
#     (for encounter spawn markers).
#   - generate() optionally accepts a RoomVariantSelector.
#   - generate() returns a layout with schema_version "1.2.0" and a
#     new top-level "encounters" array populated by EncounterInjector.

const TemplateSelectorScript := preload("res://scripts/procgen/template_selector.gd")
const RoomAssignerScript := preload("res://scripts/procgen/room_assigner.gd")
const CellLayoutEngineScript := preload("res://scripts/procgen/cell_layout_engine.gd")
const WallDoorResolverScript := preload("res://scripts/procgen/wall_door_resolver.gd")
const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
const RoomVariantSelectorScript := preload("res://scripts/procgen/room_variant_selector.gd")
const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")
const DifficultyProfileScript := preload("res://scripts/procgen/difficulty_profile.gd")
const EncounterInjectorScript := preload("res://scripts/procgen/encounter_injector.gd")

var template_selector: RefCounted = TemplateSelectorScript.new()
var room_assigner: RefCounted = RoomAssignerScript.new()
var cell_layout_engine: RefCounted = CellLayoutEngineScript.new()
var wall_door_resolver: RefCounted = WallDoorResolverScript.new()
var layout_serializer: RefCounted = LayoutSerializerScript.new()
var variant_selector: RefCounted = null
var biome_id: String = ""
var difficulty_id: String = ""


func generate(blueprint: RefCounted, archetype: Dictionary = {}) -> Dictionary:
	return generate_with_options(blueprint, archetype, "", "", false)


# Extended entry point. When `biome_id` / `difficulty_id` are
# non-empty, the RoomAssigner is given the variant selector (if
# one is built), and after Stage 5 the EncounterInjector populates
# `layout.encounters`. When the biome / difficulty ids are empty
# strings, the legacy behaviour is preserved exactly.
func generate_with_options(
		blueprint: RefCounted,
		archetype: Dictionary = {},
		biome_id: String = "",
		difficulty_id: String = "",
		extended_templates: bool = false) -> Dictionary:
	assert(blueprint != null, "ShipLayoutGenerator: blueprint must not be null")

	self.biome_id = biome_id
	self.difficulty_id = difficulty_id

	# Stage 1: Select topology template.
	var template: RefCounted
	if extended_templates:
		template = template_selector.select_with_options(
			blueprint, archetype, true, true)
	else:
		template = template_selector.select(blueprint, archetype)
	if template == null:
		push_error("SHIP LAYOUT GENERATOR FAIL template selection returned null")
		return {}

	# Stage 2: Assign rooms to template zones (with variant selector).
	var room_plan: Array[Dictionary]
	if variant_selector == null and not biome_id.is_empty():
		variant_selector = RoomVariantSelectorScript.new()
	if variant_selector != null:
		room_plan = room_assigner.assign_with_selector(
			template, blueprint, archetype, variant_selector, biome_id)
	else:
		room_plan = room_assigner.assign(template, blueprint, archetype)
	if room_plan.is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL room assignment returned empty")
		return {}

	# Stage 3: Place rooms on 2D grid.
	var cell_grid: Dictionary = cell_layout_engine.layout(room_plan, template, int(blueprint.seed_value))
	if cell_grid.get("rooms", {}).is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL cell layout returned empty rooms")
		return {}

	# Stage 4: Resolve walls, doors, interior zones.
	var geometry: Dictionary = wall_door_resolver.resolve(cell_grid, room_plan)

	# Stage 5: Serialize to layout.json format.
	var archetype_name: String = str(archetype.get("name", str(archetype.get("template", "default"))))
	var layout: Dictionary = layout_serializer.serialize(
		cell_grid, geometry, room_plan,
		str(template.id), int(blueprint.seed_value), archetype_name)

	# Stage 6 (optional): Inject encounter markers when biome and/or
	# difficulty are non-empty.
	if not biome_id.is_empty() or not difficulty_id.is_empty():
		var biome_data: Dictionary = _resolve_biome(biome_id)
		var difficulty_data: Dictionary = _resolve_difficulty(difficulty_id)
		var biome = BiomeProfileScript.from_dict(biome_data)
		var difficulty = DifficultyProfileScript.from_dict(difficulty_data)
		var injector: RefCounted = EncounterInjectorScript.new()
		layout = injector.inject(layout, biome, difficulty, int(blueprint.seed_value))

	# Stamp biome / difficulty / kit_id on the layout for the
	# scanner / HUD layer to read without re-running the seed.
	if not biome_id.is_empty():
		layout["biome_id"] = biome_id
	if not difficulty_id.is_empty():
		layout["difficulty_id"] = difficulty_id

	return layout


# Resolves a biome dictionary from `biome_id`. When `biome_id` is
# empty, returns a minimal abyssal_synaptic_sea default so the encounter
# injector still runs (but the encounter density stays at 1.0 and
# the resulting encounter list is typically empty for the standard
# difficulty).
func _resolve_biome(biome_id: String) -> Dictionary:
	if biome_id.is_empty():
		return {"id": "abyssal_synaptic_sea"}
	# Try to load the JSON file first; fall back to a built-in
	# default for the three known biomes so the smoke bundle works
	# even without a fully populated data/ tree.
	var rel_path: String = "res://data/procgen/biomes/" + biome_id + ".json"
	if FileAccess.file_exists(rel_path):
		var text: String = FileAccess.get_file_as_string(rel_path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			return parsed
	match biome_id:
		"breach_field":
			return {
				"id": "breach_field",
				"hazard_modifier": 1.4,
				"loot_quality_modifier": 1.1,
				"encounter_density_modifier": 1.3,
				"ambient_intensity": 0.85,
				"encounter_table_id": "biomatter_lurker",
			}
		"dead_fleet":
			return {
				"id": "dead_fleet",
				"hazard_modifier": 1.1,
				"loot_quality_modifier": 1.4,
				"encounter_density_modifier": 0.8,
				"ambient_intensity": 1.1,
				"encounter_table_id": "derelict_pirate",
			}
		_:
			return {
				"id": "abyssal_synaptic_sea",
				"hazard_modifier": 1.0,
				"loot_quality_modifier": 1.0,
				"encounter_density_modifier": 1.0,
				"ambient_intensity": 1.0,
				"encounter_table_id": "biomatter_lurker",
			}


func _resolve_difficulty(difficulty_id: String) -> Dictionary:
	# Tranche 4 (2026-07-06 audit): the id -> dials mapping moved verbatim to
	# DifficultyProfile.resolve_dict() so the settings menu renders the same
	# canonical values this generator consumes (no split-brain).
	return DifficultyProfileScript.resolve_dict(difficulty_id)
