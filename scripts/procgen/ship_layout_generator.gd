extends RefCounted
class_name ShipLayoutGenerator

# Top-level orchestrator for the procgen layout pipeline.
# Runs the 5-stage pipeline:
#   TemplateSelector -> RoomAssigner -> CellLayoutEngine ->
#   WallDoorResolver -> LayoutSerializer
# Returns a complete layout.json Dictionary.

const TemplateSelectorScript := preload("res://scripts/procgen/template_selector.gd")
const RoomAssignerScript := preload("res://scripts/procgen/room_assigner.gd")
const CellLayoutEngineScript := preload("res://scripts/procgen/cell_layout_engine.gd")
const WallDoorResolverScript := preload("res://scripts/procgen/wall_door_resolver.gd")
const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")

var template_selector: RefCounted = TemplateSelectorScript.new()
var room_assigner: RefCounted = RoomAssignerScript.new()
var cell_layout_engine: RefCounted = CellLayoutEngineScript.new()
var wall_door_resolver: RefCounted = WallDoorResolverScript.new()
var layout_serializer: RefCounted = LayoutSerializerScript.new()


func generate(blueprint: RefCounted, archetype: Dictionary = {}) -> Dictionary:
	assert(blueprint != null, "ShipLayoutGenerator: blueprint must not be null")

	# Stage 1: Select topology template
	var template: RefCounted = template_selector.select(blueprint, archetype)
	if template == null:
		push_error("SHIP LAYOUT GENERATOR FAIL template selection returned null")
		return {}

	# Stage 2: Assign rooms to template zones
	var room_plan: Array[Dictionary] = room_assigner.assign(template, blueprint, archetype)
	if room_plan.is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL room assignment returned empty")
		return {}

	# Stage 3: Place rooms on 2D grid
	var cell_grid: Dictionary = cell_layout_engine.layout(room_plan, template, int(blueprint.seed_value))
	if cell_grid.get("rooms", {}).is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL cell layout returned empty rooms")
		return {}

	# Stage 4: Resolve walls, doors, interior zones
	var geometry: Dictionary = wall_door_resolver.resolve(cell_grid, room_plan)

	# Stage 5: Serialize to layout.json format
	var archetype_name: String = str(archetype.get("name", str(archetype.get("template", "default"))))
	var layout: Dictionary = layout_serializer.serialize(
		cell_grid, geometry, room_plan,
		str(template.id), int(blueprint.seed_value), archetype_name)

	return layout
