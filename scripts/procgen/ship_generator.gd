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
# This class carries no scene nodes of its own; the returned root is
# a freshly-built Node3D that the caller is responsible for adding to
# the scene tree (or for using as a transient scene for tests,
# save/load fixtures, etc.).
#
# Both sub-generators (RoomGraphGenerator and StructuralPlacer) are
# public so callers can swap them for fakes/seeds in tests, but the
# default constructor wires up the standard pair so production code
# can just write `ShipGenerator.new().generate(bp)`.
#
# NOTE: GDScript `class_name` globals may not be available at parse
# time in `godot --headless --script` mode, so type annotations on
# the public methods use the preloaded script aliases (`ShipBlueprintScript`,
# `RoomGraphGeneratorScript`, `StructuralPlacerScript`) that the rest
# of the procgen scripts use. This keeps parse clean under both
# editor parse and headless run.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const StructuralPlacerScript := preload("res://scripts/procgen/structural_placer.gd")

# Sub-generators. Declared with explicit script types so consumers can
# see what each one is for without having to follow the preload.
var graph_generator: RefCounted = RoomGraphGeneratorScript.new()
var structural_placer: RefCounted = StructuralPlacerScript.new()


# Builds the full Node3D tree for the given blueprint.
#
# Steps:
#   1. Generate a RoomGraph from the blueprint via `graph_generator`.
#   2. Lay out the structural shell from that graph via
#      `structural_placer.place_structure` (returns a Node3D named
#      "ShipStructure" with one child Node3D per room).
#   3. Wrap the structure in a fresh root Node3D named "GeneratedShip"
#      and reparent the structure under it.
#
# The returned root is NOT attached to the scene tree — the caller
# decides where (and whether) to add it. This keeps the generator
# trivially usable from a smoke, a loader, or a save/load fixture
# without coupling to any particular scene path.
#
# Returns a Node3D named "GeneratedShip" whose single direct child is
# the ShipStructure produced by the placer. Returns null only if the
# placer itself returned null (which only happens if it cannot
# instantiate any module; the placer already pushes an error in that
# case).
func generate(blueprint) -> Node3D:
	assert(blueprint != null, "ShipGenerator: blueprint must not be null")

	# RoomGraphGenerator is deterministic given the blueprint's
	# seed_value, so calling generate() twice with the same blueprint
	# produces identical graphs and therefore identical structures.
	var graph = graph_generator.generate(blueprint)
	var structure: Node3D = structural_placer.place_structure(graph)
	if structure == null:
		# StructuralPlacer.push_error() already fired inside
		# place_structure; we surface the failure as a null return
		# so callers can branch without relying on the engine's
		# error stream being attached to anything.
		return null

	var ship_root: Node3D = Node3D.new()
	ship_root.name = "GeneratedShip"
	ship_root.add_child(structure)

	return ship_root


# Convenience wrapper that builds a ShipBlueprint from the given
# seed/size/condition triple and then runs `generate(blueprint)`.
#
# This is the entry point smoke tests and one-off generation scripts
# use; production code that already has a blueprint should call
# `generate(blueprint)` directly to avoid constructing a throwaway
# blueprint instance.
#
# `size` defaults to LIFE_BOAT and `condition` defaults to DAMAGED so
# a call like `generate_from_seed(42)` produces a small, slightly
# beat-up ship — a sensible default for the "show me a ship" use
# case (not too pristine, not totally wrecked).
func generate_from_seed(
		seed_value: int,
		size: int = 0,
		condition: int = 1) -> Node3D:
	# The default values are the integer forms of the ShipBlueprint
	# enum members (LIFE_BOAT = 0, DAMAGED = 1). Using numeric
	# defaults keeps the signature parseable even when class_name
	# globals aren't registered yet in headless --script mode;
	# callers that want to be explicit can still pass the enum
	# members and they'll coerce to the same integers.
	var blueprint = ShipBlueprintScript.new(size, condition, seed_value)
	return generate(blueprint)