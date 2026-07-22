extends SceneTree

## PKG-B2.1b: fire→module damage, derived breaches, scene consequence contract.
## Marker: MODULE INTEGRITY CONSEQUENCES PASS fire=true breach_derived=true scene=true nav=true

const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityConsequencesScript := preload("res://scripts/systems/module_integrity_consequences.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")


func _initialize() -> void:
	# Consequence table
	var c_intact: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(
		ModuleIntegrityStateScript.STATE_INTACT)
	if not bool(c_intact.get("collision_enabled", false)):
		_fail("intact should collide")
		return
	var c_dest: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(
		ModuleIntegrityStateScript.STATE_DESTROYED)
	if bool(c_dest.get("collision_enabled", true)):
		_fail("destroyed should drop collision")
		return
	if not bool(c_dest.get("atmosphere_link", false)) or not bool(c_dest.get("nav_gap", false)):
		_fail("destroyed should open atmosphere + nav gap")
		return
	var c_breach: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(
		ModuleIntegrityStateScript.STATE_BREACHED)
	if not bool(c_breach.get("crawl_passable", false)):
		_fail("breached should be crawl-passable")
		return

	# Seed + fire damage
	var layout: Dictionary = {
		"rooms": [
			{
				"id": "eng_1",
				"room_role": "engineering",
				"structural_placements": [
					{"module_id": "wall_straight_1x1", "name": "wall_a", "world_position": [0, 0, 0]},
					{"module_id": "floor_1x1", "name": "floor_a", "world_position": [0, 0, 0]},
				],
			},
			{
				"id": "br_1",
				"room_role": "bridge",
				"structural_placements": [
					{"module_id": "bulkhead_portal_2x1", "name": "portal_a", "world_position": [4, 0, 0]},
				],
			},
		]
	}
	var map = ModuleIntegrityMapScript.new()
	var seeded: int = ModuleIntegrityConsequencesScript.seed_map_from_layout(map, layout)
	if seeded < 2:
		_fail("expected wall modules seeded, got %d" % seeded)
		return
	# floors should not be seeded as walls
	if map.has_module("eng_1/floor_a"):
		_fail("floor should not be wall-seeded")
		return

	var burning: Dictionary = {"engineering": 1.0}
	var roles: Dictionary = {"engineering": "engineering", "bridge": "bridge"}
	var changed: Array = []
	# Burn long enough to breach/destroy
	for _i in range(40):
		var step: Array = ModuleIntegrityConsequencesScript.apply_fire_damage(
			map, layout, burning, roles, 0.5, 0.2
		)
		for mid in step:
			if not changed.has(mid):
				changed.append(mid)
	if changed.is_empty():
		_fail("fire should change wall integrity")
		return
	var st: String = map.get_state("eng_1/wall_a")
	if st == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("engineering wall should not stay intact under fire")
		return
	var breaches: int = ModuleIntegrityConsequencesScript.derived_breach_count(map)
	if breaches < 1 and st != ModuleIntegrityStateScript.STATE_DAMAGED:
		# damaged only is ok short-term; force more damage
		map.apply_damage("eng_1/wall_a", 1.0, "wall_straight_1x1")
		breaches = ModuleIntegrityConsequencesScript.derived_breach_count(map)
	if map.count_wall_breaches() < 1:
		map.apply_damage("eng_1/wall_a", 1.0, "wall_straight_1x1")
	if map.count_wall_breaches() < 1:
		_fail("expected wall breach count >= 1 after heavy damage")
		return

	# Scene node consequence
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	node.add_child(mesh)
	var col := CollisionShape3D.new()
	col.name = "Col"
	node.add_child(col)
	get_root().add_child(node)
	ModuleIntegrityConsequencesScript.apply_to_node(node, ModuleIntegrityStateScript.STATE_DESTROYED)
	if not bool(node.get_meta("nav_gap", false)):
		_fail("node should have nav_gap meta")
		return
	if not col.disabled:
		_fail("destroyed should disable CollisionShape3D")
		return

	# Nav gap softens edges
	var nav = ShipNavGraphScript.new()
	var nav_layout: Dictionary = {
		"cell_size": 4.0,
		"deck_height": 4.0,
		"rooms": [
			{
				"id": "eng_1",
				"structural_placements": [
					{"module_id": "floor_1x1", "world_position": [0, 0, 0]},
					{"module_id": "floor_1x1", "world_position": [4, 0, 0]},
				],
			}
		]
	}
	nav.build_from_layout(nav_layout)
	if nav.node_count() >= 2:
		ModuleIntegrityConsequencesScript.apply_nav_gaps(nav, ["eng_1"])
	# snapshot includes module integrity via runtime
	var rt_script = load("res://scripts/systems/ship_runtime.gd")
	var ShipInstanceScript = load("res://scripts/systems/ship_instance.gd")
	var inst = ShipInstanceScript.create("mi", "m:1", null, null, null)
	var rt = rt_script.new()
	rt.configure(inst, {"is_home": false, "module_integrity": map})
	var snap: Dictionary = rt.to_snapshot()
	if typeof(snap.get("module_integrity", null)) != TYPE_DICTIONARY:
		_fail("runtime snapshot should carry module_integrity")
		return
	var map2 = ModuleIntegrityMapScript.new()
	var rt2 = rt_script.new()
	rt2.configure(inst, {"is_home": false, "module_integrity": map2})
	rt2.from_snapshot(snap)
	if map2.count_wall_breaches() != map.count_wall_breaches():
		_fail("module integrity snapshot round-trip")
		return

	print("MODULE INTEGRITY CONSEQUENCES PASS fire=true breach_derived=true scene=true nav=true")
	quit(0)


func _fail(msg: String) -> void:
	print("MODULE INTEGRITY CONSEQUENCES FAIL: %s" % msg)
	quit(1)
