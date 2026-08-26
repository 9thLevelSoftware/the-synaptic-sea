extends RefCounted
class_name StartSceneBuilder

# Builds the combined start scene: an authoritative-bundle derelict with a
# fixed authored life boat attached at the dock.
#
# Pipeline:
#   1. Generate and validate one complete Rust ProcgenBundle in memory.
#   2. Map that bundle once to loader documents.
#   3. Build the fixed life boat's authored layout/gameplay documents.
#   4. Load both from in-memory documents.
#   5. Position life boat adjacent to derelict's dock room.
#   6. Return a root Node3D containing both loaders.
#
# The root is NOT attached to the scene tree — the caller decides
# where to add it (playable scene, test scene, etc.).

const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")

# Gap between the derelict dock and the life boat airlock (world units).
const DOCK_GAP: float = 6.0


# Builds the combined start scene for the given seed.
# Returns a Node3D named "StartScene" containing both the derelict
# GeneratedShipLoader and the life boat GeneratedShipLoader, or null on failure.
static func build(seed_value: int) -> Node3D:
	# ---- Step 1: Generate one complete derelict bundle ----
	var generator: RefCounted = ShipGeneratorScript.new()
	generator.configure_run_context("", "standard")
	generator.configure_procgen_site("", 0, 0)
	var documents: Dictionary = generator.generate_documents_from_seed(
		seed_value, 1, 2, "freighter")
	if documents.is_empty():
		push_error("StartSceneBuilder: derelict bundle generation failed: %s" % generator.last_error)
		return null
	var derelict_layout: Dictionary = (documents.layout as Dictionary).duplicate(true)

	# ---- Step 2: Generate life boat layout ----
	var lb_layout: Dictionary = LifeBoatBuilderScript.build_layout()
	if lb_layout.is_empty():
		push_error("StartSceneBuilder: life boat layout generation failed")
		return null

	# ---- Step 3: Use bundle gameplay + fixed authored life boat gameplay ----
	var derelict_gameplay: Dictionary = (documents.gameplay_slice as Dictionary).duplicate(true)
	var lb_gameplay: Dictionary = LifeBoatBuilderScript.build_gameplay_document()
	if lb_gameplay.is_empty():
		push_error("StartSceneBuilder: life boat gameplay document missing")
		return null

	# ---- Step 4: Load both from in-memory documents ----
	var derelict: Node3D = generator.instantiate_documents(documents, false)
	if derelict == null:
		push_error("StartSceneBuilder: derelict document assembly failed")
		return null
	derelict.name = "Derelict"

	var life_boat: GeneratedShipLoaderScript = GeneratedShipLoaderScript.new()
	life_boat.name = "LifeBoat"
	var lb_ok: bool = life_boat.load_from_documents(
		lb_layout,
		(documents.kit as Dictionary).duplicate(true),
		lb_gameplay,
		false)
	if not lb_ok:
		push_error("StartSceneBuilder: life boat document assembly failed")
		derelict.queue_free()
		life_boat.queue_free()
		return null

	# ---- Step 5: Position life boat adjacent to derelict's dock room ----
	var dock_pos: Vector3 = _find_dock_position(derelict_layout)
	if dock_pos == Vector3.INF:
		push_error("StartSceneBuilder: no dock room found in derelict layout; cannot position life boat")
		derelict.queue_free()
		life_boat.queue_free()
		return null
	life_boat.position = dock_pos + Vector3(0.0, 0.0, DOCK_GAP)

	# ---- Step 6: Combine under a single root ----
	var root: Node3D = Node3D.new()
	root.name = "StartScene"
	root.set_meta("procgen_request", (documents.request as Dictionary).duplicate(true))
	root.set_meta("procgen_semantic_hash", str(documents.semantic_hash))
	root.add_child(derelict)
	root.add_child(life_boat)

	return root

# Finds the center of the dock room in the derelict layout.
# Returns the average position of all floor cells (floor_1x1, corridor_floor_1x1)
# in the dock room, or Vector3.INF if no dock room is found.
static func _find_dock_position(layout: Dictionary) -> Vector3:
	const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]
	var rooms: Array = layout.get("rooms", [])
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var role: String = str(room.get("room_role", ""))
		var rid: String = str(room.get("id", ""))
		if role not in ["dock", "airlock"] \
				and not rid.begins_with("dock") and not rid.begins_with("airlock"):
			continue
		# Compute the average position of all floor cells in this room.
		var placements: Array = room.get("structural_placements", [])
		var sum: Vector3 = Vector3.ZERO
		var count: int = 0
		for placement_variant in placements:
			if typeof(placement_variant) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_variant
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id not in FLOOR_MODULES:
				continue
			var pos: Variant = placement.get("world_position", placement.get("position", null))
			if pos == null or typeof(pos) != TYPE_ARRAY:
				continue
			var pos_arr: Array = pos
			if pos_arr.size() < 3:
				continue
			sum += Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			count += 1
		if count > 0:
			return sum / float(count)
	return Vector3.INF
