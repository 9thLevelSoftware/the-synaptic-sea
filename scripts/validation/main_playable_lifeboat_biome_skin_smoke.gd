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
## Pass marker: MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=3 reachable=true

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
	var biome: String = str(playable._resolve_current_loot_biome_id())
	if biome.is_empty():
		_fail("run biome resolved empty")
		return

	# 3) Collect the live lifeboat's actual per-role module stems.
	var live_by_role: Dictionary = _live_modules_by_role(lifeboat.scene_root)
	if live_by_role.is_empty():
		_fail("could not read any lifeboat room modules")
		return

	# 4) Those stems must match KitCatalog's selection for the resolved biome —
	#    proving the lifeboat is kit+biome driven (not the hardcoded const).
	var catalog = KitCatalogScript.new()
	catalog.configure("res://data/kits/")
	var roles_checked: int = 0
	for entry in LifeBoatBuilderScript.ROOMS:
		var role: String = str(entry.get("role", ""))
		if not live_by_role.has(role):
			continue
		var expected: Array = catalog.kits_for_role(role, biome)
		var actual: Array = live_by_role[role]
		if not _arrays_equal(actual, expected):
			_fail("role=%s live=%s != kit[%s]=%s" % [role, str(actual), biome, str(expected)])
			return
		roles_checked += 1
	if roles_checked < 1:
		_fail("no lifeboat roles matched against the kit catalog")
		return

	# 5) Verify the wiring for ALL THREE biomes through the REAL StructuralPlacer
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

	# 6) Biome selection actually VARIES (the feature has teeth): for at least one
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

# Walks LifeBoat -> ShipStructure -> room nodes; returns role -> ordered Array[String]
# of module stems (the "stem_<index>" child names with the index suffix stripped).
func _live_modules_by_role(lb_root) -> Dictionary:
	var out: Dictionary = {}
	if lb_root.get_child_count() < 1:
		return out
	var structure: Node = lb_root.get_child(0)  # "ShipStructure"
	if structure == null:
		return out
	# Map room_id -> role from the lifeboat definition.
	var role_for_id: Dictionary = {}
	for entry in LifeBoatBuilderScript.ROOMS:
		role_for_id[str(entry.get("id", ""))] = str(entry.get("role", ""))
	for room_node in structure.get_children():
		var rid: String = str(room_node.name)
		if not role_for_id.has(rid):
			continue
		var stems: Array[String] = []
		for mod_node in room_node.get_children():
			stems.append(_strip_index(str(mod_node.name)))
		out[role_for_id[rid]] = stems
	return out

# "doorway_frame_open_1x1_2" -> "doorway_frame_open_1x1" (strip a trailing _<int>).
func _strip_index(node_name: String) -> String:
	var idx: int = node_name.rfind("_")
	if idx <= 0:
		return node_name
	var suffix: String = node_name.substr(idx + 1)
	if suffix.is_valid_int():
		return node_name.substr(0, idx)
	return node_name

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
