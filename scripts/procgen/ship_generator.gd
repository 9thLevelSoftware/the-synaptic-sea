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

var layout_generator: RefCounted = ShipLayoutGeneratorScript.new()

# Per-derelict run context. When non-empty, generate() forwards these to
# ShipLayoutGenerator.generate_with_options(), which turns on room-variant
# selection + Stage-6 EncounterInjector and stamps biome_id/difficulty_id on
# the layout. Empty (the default) preserves the legacy bare-geometry behaviour
# exactly, so existing callers/smokes are unaffected.
var biome_id: String = ""
var difficulty_id: String = ""


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
	var blueprint = ShipBlueprintScript.new(size, condition, seed_value)
	return generate(blueprint)


func _load_layout_as_scene(layout: Dictionary) -> Node3D:
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

	# The GeneratedShipLoader needs the shared structural module kit JSON.
	var kit_path: String = "res://data/kits/ship_structural_v0.json"
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
	var success: bool = loader.load_from_paths(layout_path, kit_path, gameplay_path)
	if not success:
		push_error("SHIP GENERATOR FAIL loader returned false")
		loader.queue_free()
		return null

	# Give the returned root a stable, meaningful name. The loader builds
	# "StructuralRoot" (geometry + nav) and "ObjectiveRoot" children under it.
	loader.name = "GeneratedShip"
	return loader
