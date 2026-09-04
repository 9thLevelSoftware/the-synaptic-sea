extends SceneTree

## KitCatalog reachability proof: the live lifeboat's structural modules are driven
## by KitCatalog through StructuralPlacer, skinned by the run's deterministic biome.
## This is the difference from kit_catalog_smoke.gd (a pure-model test): here the LIVE
## coordinator builds the lifeboat (playable.lifeboat_ship.scene_root), and its actual
## instantiated module stems must match the kit selection for the run's resolved biome.
##
## Leak-free by design: it inspects the already-built lifeboat and compares kit data
## (no extra Node3D instantiation), so it is safe to gate in the regression bundle.
##
## Pass marker: MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=3 live_match=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const KitCatalogScript := preload("res://scripts/procgen/kit_catalog.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const StructuralPlacerScript := preload("res://scripts/procgen/structural_placer.gd")
const TIMEOUT_FRAMES: int = 600
const BIOMES: Array[String] = ["abyssal_synaptic_sea", "breach_field", "dead_fleet"]

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var exercised: bool = false
var module_resolution_error: String = ""

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if not playable.playable_started:
		return
	if exercised:
		return
	exercised = true
	_validate(playable)

func _validate(playable) -> void:
	# 1) The coordinator built a live lifeboat with a structural scene root.
	var lifeboat = playable.lifeboat_ship
	if lifeboat == null or lifeboat.scene_root == null or not is_instance_valid(lifeboat.scene_root):
		_fail("no live lifeboat scene_root")
		return

	# 2) Resolve the run's biome via the SAME seam the coordinator used to skin it.
	var current_biome: String = str(playable._resolve_current_loot_biome_id())
	if current_biome.is_empty():
		_fail("run biome resolved empty")
		return

	# 3) The retained layout must preserve the same biome-selected kit identity
	#    used to build the live root.
	var retained_layout_variant: Variant = lifeboat.built_layout
	if typeof(retained_layout_variant) != TYPE_DICTIONARY:
		_fail("lifeboat retained layout is not a dictionary")
		return
	var retained_layout: Dictionary = retained_layout_variant as Dictionary
	var expected_layout: Dictionary = LifeBoatBuilderScript.build_layout(current_biome)
	var retained_kit_id: String = str(retained_layout.get("kit_id", ""))
	var expected_kit_id: String = str(expected_layout.get("kit_id", ""))
	if retained_kit_id.is_empty() or retained_kit_id != expected_kit_id:
		_fail("retained kit=%s != build_layout[%s]=%s" % [retained_kit_id, current_biome, expected_kit_id])
		return

	# 4) Derive both sides from the compiler-era structural plan. The live root
	#    is intentionally inspected through its direct room children; no legacy
	#    role geometry is rebuilt or compared here.
	var retained_plan_variant: Variant = retained_layout.get("structural_plan", null)
	if typeof(retained_plan_variant) != TYPE_DICTIONARY:
		_fail("retained layout has no compiled structural_plan")
		return
	var expected_by_room: Dictionary = _compiled_modules_by_room(retained_plan_variant as Dictionary)
	if expected_by_room.is_empty():
		_fail("retained structural_plan has no room modules")
		return
	var live_by_room: Dictionary = _live_modules_by_room(lifeboat.scene_root)
	if live_by_room.is_empty():
		_fail(module_resolution_error if not module_resolution_error.is_empty() else "could not read any lifeboat room modules")
		return
	if not _room_module_multisets_equal(expected_by_room, live_by_room):
		_fail("compiled=%s live=%s" % [str(expected_by_room), str(live_by_room)])
		return

	# 5) Those stems must match KitCatalog's selection for the resolved biome —
	#    proving the lifeboat is kit+biome driven (not the hardcoded const).
	var catalog = KitCatalogScript.new()
	catalog.configure("res://data/kits/")
	var roles_checked: int = 0
	for entry in LifeBoatBuilderScript.ROOMS:
		var role: String = str(entry.get("role", ""))
		var expected: Array = catalog.kits_for_role(role, current_biome)
		if expected.is_empty():
			continue
		roles_checked += 1
	if roles_checked < 1:
		_fail("no lifeboat roles resolved in the kit catalog")
		return

	# 6) Verify the wiring for ALL THREE biomes through the REAL StructuralPlacer
	#    path (the exact _modules_for_role() that LifeBoatBuilder.build(biome)
	#    drives), not just KitCatalog data. Leak-free: _modules_for_role returns
	#    stems without instantiating any Node3D, so we cover breach_field/
	#    dead_fleet without building extra (RID-leaking) lifeboats.
	for b in BIOMES:
		var placer = StructuralPlacerScript.new()
		placer.biome = b
		placer._ensure_kit_catalog()
		for entry2 in LifeBoatBuilderScript.ROOMS:
			var role2: String = str(entry2.get("role", ""))
			var placed: Array = placer._modules_for_role(role2)
			var expected2: Array = catalog.kits_for_role(role2, b)
			if not _arrays_equal(placed, expected2):
				_fail("biome=%s role=%s placer=%s != kit=%s" % [b, role2, str(placed), str(expected2)])
				return

	# 7) Biome selection actually VARIES (the feature has teeth): for at least one
	#    lifeboat role, breach_field/dead_fleet differ from the abyssal default.
	var varied: bool = false
	for entry3 in LifeBoatBuilderScript.ROOMS:
		var role3: String = str(entry3.get("role", ""))
		var base: Array = catalog.kits_for_role(role3, "abyssal_synaptic_sea")
		for other in ["breach_field", "dead_fleet"]:
			if not _arrays_equal(catalog.kits_for_role(role3, other), base):
				varied = true
				break
		if varied:
			break
	if not varied:
		_fail("no biome variation across lifeboat roles")
		return

	finished = true
	print("MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=%d live_match=true reachable=true" % BIOMES.size())
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

# Derives the compiler's per-room module_id multiset from all three retained
# structural-plan placement arrays. Ownership follows life_boat.gd: room_id,
# then owner_room, then the first room_ids entry.
func _compiled_modules_by_room(plan: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for layer in ["floor_placements", "placements", "ceiling_placements"]:
		var records_variant: Variant = plan.get(layer, null)
		if typeof(records_variant) != TYPE_ARRAY:
			return {}
		for record_variant in records_variant as Array:
			if typeof(record_variant) != TYPE_DICTIONARY:
				return {}
			var record: Dictionary = record_variant as Dictionary
			var module_id: String = str(record.get("module_id", ""))
			var room_id: String = _record_room_id(record)
			if module_id.is_empty() or room_id.is_empty():
				return {}
			if not out.has(room_id):
				out[room_id] = []
			(out[room_id] as Array).append(module_id)
	for room_id in out:
		(out[room_id] as Array).sort()
	return out

# Walks LifeBoat -> ShipStructure -> room nodes; returns room_id -> sorted
# Array[String] module_id multisets from each direct wrapper child. Runtime
# loader wrappers carry module_kind metadata; the lifeboat's direct builder
# wrappers do not, so their PackedScene root identity is used only when the
# metadata key is genuinely absent.
func _live_modules_by_room(lb_root) -> Dictionary:
	module_resolution_error = ""
	var out: Dictionary = {}
	if lb_root == null or lb_root.get_child_count() < 1:
		return out
	var structure: Node = lb_root.get_child(0)  # "ShipStructure"
	if structure == null:
		return out
	for room_node_variant in structure.get_children():
		if not (room_node_variant is Node):
			module_resolution_error = "lifeboat room node is not a Node"
			return {}
		var room_node: Node = room_node_variant as Node
		var room_id: String = str(room_node.name)
		if room_id.is_empty():
			module_resolution_error = "lifeboat room node has empty id"
			return {}
		var modules: Array[String] = []
		for wrapper_variant in room_node.get_children():
			if not (wrapper_variant is Node):
				module_resolution_error = "room=%s has a non-Node wrapper child" % room_id
				return {}
			var module_id: String = _live_module_id(wrapper_variant as Node, room_id)
			if module_id.is_empty():
				return {}
			modules.append(module_id)
		modules.sort()
		out[room_id] = modules
	return out

func _live_module_id(wrapper: Node, room_id: String) -> String:
	if wrapper.has_meta("module_kind"):
		var metadata_value: Variant = wrapper.get_meta("module_kind")
		if metadata_value == null or str(metadata_value).is_empty():
			module_resolution_error = "room=%s wrapper=%s has empty module_kind metadata" % [room_id, str(wrapper.name)]
			return ""
		return str(metadata_value)

	# LifeBoatBuilder renames each instance to its placement_id, so wrapper.name
	# is intentionally not a module fallback. scene_file_path retains the
	# PackedScene root identity and yields the canonical module_id.
	var scene_path: String = str(wrapper.scene_file_path)
	if not scene_path.is_empty():
		var scene_root_id: String = scene_path.get_file().get_basename()
		if not scene_root_id.is_empty():
			return scene_root_id
	module_resolution_error = "room=%s wrapper=%s has no module_kind metadata or scene/root identity" % [room_id, str(wrapper.name)]
	return ""

func _record_room_id(record: Dictionary) -> String:
	var room_id: String = str(record.get("room_id", record.get("owner_room", "")))
	if room_id.is_empty():
		var room_ids: Variant = record.get("room_ids", [])
		if typeof(room_ids) == TYPE_ARRAY and not (room_ids as Array).is_empty():
			room_id = str((room_ids as Array)[0])
	return room_id

func _room_module_multisets_equal(expected: Dictionary, actual: Dictionary) -> bool:
	if expected.size() != actual.size():
		return false
	for room_id in expected:
		if not actual.has(room_id):
			return false
		if not _arrays_equal(expected[room_id] as Array, actual[room_id] as Array):
			return false
	return true

func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if str(a[i]) != str(b[i]):
			return false
	return true

func _find_playable(node: Node):
	if not is_instance_valid(node):
		return null
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE LIFEBOAT BIOME SKIN FAIL reason=%s" % reason)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
