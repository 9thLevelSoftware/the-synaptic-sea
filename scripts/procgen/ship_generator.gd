extends RefCounted
class_name ShipGenerator

# Orchestrator that wires the ShipBlueprint-driven procgen pipeline
# end-to-end:
#
#   ShipBlueprint  ──►  RoomGraphGenerator  ──►  RoomGraph
#                                                    │
#                                                    ▼
#                          Node3D  ◄──  StructuralPlacer.place_structure
#                              │
#                              └── "GeneratedShip" (root)
#                                  └── "ShipStructure" (per-room Node3Ds)
#
# v2: accepts an optional archetype Dictionary that is forwarded to
# RoomGraphGenerator for weighted role selection. When present,
# the generated ship has a sensible role distribution (freighters
# get cargo, life boats get minimal roles, etc.).

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const StructuralPlacerScript := preload("res://scripts/procgen/structural_placer.gd")

var graph_generator: RefCounted = RoomGraphGeneratorScript.new()
var structural_placer: RefCounted = StructuralPlacerScript.new()


# Builds the full Node3D tree for the given blueprint.
# `archetype` is forwarded to RoomGraphGenerator for weighted role
# selection. Pass {} or omit for default (uniform random) weights.
func generate(blueprint, archetype: Dictionary = {}) -> Node3D:
	assert(blueprint != null, "ShipGenerator: blueprint must not be null")

	var graph = graph_generator.generate(blueprint, archetype)
	var structure: Node3D = structural_placer.place_structure(graph, int(blueprint.seed_value))
	if structure == null:
		return null

	var ship_root: Node3D = Node3D.new()
	ship_root.name = "GeneratedShip"
	ship_root.add_child(structure)

	return ship_root


# Convenience wrapper that builds a ShipBlueprint from seed/size/condition
# and runs generate(). No archetype support — callers who want weighted
# role selection should build their own blueprint and call generate() directly.
func generate_from_seed(
		seed_value: int,
		size: int = 0,
		condition: int = 1) -> Node3D:
	var blueprint = ShipBlueprintScript.new(size, condition, seed_value)
	return generate(blueprint)
