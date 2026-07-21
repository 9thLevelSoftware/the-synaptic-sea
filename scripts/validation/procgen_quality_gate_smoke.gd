extends SceneTree

## Procgen program V1: end-to-end pure-model quality gate.
## Seeds × biomes × difficulties; schema, connectivity, floors, nav, encounters, determinism.
## Marker: PROCGEN QUALITY GATE PASS seeds=<n> layouts=<m> walkable=true encounters=true schema=true

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
const ThreatPathfinderScript := preload("res://scripts/systems/threat_pathfinder.gd")
const RoomAssignerScript := preload("res://scripts/procgen/room_assigner.gd")

const SEED_COUNT: int = 16
const BIOMES: Array[String] = ["abyssal_synaptic_sea", "breach_field", "dead_fleet"]
const DIFFS: Array[String] = ["standard", "hardened"]

func _initialize() -> void:
	var gen := ShipLayoutGeneratorScript.new()
	var archetype: Dictionary = _load_json("res://data/procgen/archetypes/derelict.json")
	if archetype.is_empty():
		archetype = {"name": "Derelict", "guaranteed_roles": ["dock"], "max_duplicates": 3}

	var layouts_ok: int = 0
	var seeds_run: int = 0
	for s in range(SEED_COUNT):
		seeds_run += 1
		var biome: String = BIOMES[s % BIOMES.size()]
		var diff: String = DIFFS[s % DIFFS.size()]
		var bp = ShipBlueprintScript.new(1, 1, 1000 + s * 17)
		var layout: Dictionary = gen.generate_with_options(bp, archetype, biome, diff, true)
		if layout.is_empty():
			_fail("empty layout seed=%d biome=%s diff=%s" % [s, biome, diff])
			return
		if str(layout.get("schema_version", "")) != "1.2.0":
			_fail("schema seed=%d got %s" % [s, str(layout.get("schema_version", ""))])
			return
		for key in ["rooms", "room_links", "encounters", "prototype", "fire_zones", "arc_zones", "breach_zones"]:
			if not layout.has(key):
				_fail("missing key '%s' seed=%d" % [key, s])
				return
		var rooms: Array = layout.get("rooms", []) as Array
		if rooms.size() < 3:
			_fail("too few rooms seed=%d count=%d" % [s, rooms.size()])
			return
		for room_v in rooms:
			if not (room_v is Dictionary):
				continue
			var placements: Array = (room_v as Dictionary).get("structural_placements", []) as Array
			var floors: int = 0
			for p in placements:
				if p is Dictionary:
					var mod: String = str((p as Dictionary).get("module", (p as Dictionary).get("module_id", "")))
					if mod.find("floor") >= 0 or mod.find("ramp") >= 0 or mod.find("corridor_floor") >= 0:
						floors += 1
			if floors < 1:
				_fail("room %s has no floor placements seed=%d" % [str((room_v as Dictionary).get("id", "?")), s])
				return
		# Connectivity via room_links BFS (same as generator helper).
		if not gen._layout_is_connected(layout):
			_fail("disconnected layout seed=%d" % s)
			return
		# Guaranteed dock after alias normalization.
		var roles: Dictionary = {}
		for room_v2 in rooms:
			if room_v2 is Dictionary:
				roles[str((room_v2 as Dictionary).get("room_role", (room_v2 as Dictionary).get("role", "")))] = true
				# serializer uses room_role
				var rr: String = str((room_v2 as Dictionary).get("room_role", ""))
				if not rr.is_empty():
					roles[rr] = true
		var has_board: bool = roles.has("dock") or roles.has("airlock")
		if not has_board:
			_fail("layout has neither dock nor airlock boarding role seed=%d roles=%s" % [s, str(roles.keys())])
			return
		# Nav graph walkable start → goal
		var graph = ShipNavGraphScript.new()
		var n: int = graph.build_from_layout(layout)
		if n < rooms.size():
			_fail("nav nodes %d < rooms %d seed=%d" % [n, rooms.size(), s])
			return
		var start_id: String = str((layout.get("prototype", {}) as Dictionary).get("start_room", ""))
		var goal_id: String = str((layout.get("prototype", {}) as Dictionary).get("goal_room", ""))
		var start_pos := Vector3.ZERO
		var goal_pos := Vector3(8, 0, 0)
		for room_v3 in rooms:
			if not (room_v3 is Dictionary):
				continue
			var rid: String = str((room_v3 as Dictionary).get("id", ""))
			if rid == start_id or rid == goal_id:
				var pl: Array = (room_v3 as Dictionary).get("structural_placements", []) as Array
				if not pl.is_empty() and pl[0] is Dictionary:
					var wp: Variant = (pl[0] as Dictionary).get("world_position", null)
					if wp is Array and (wp as Array).size() >= 3:
						var pos := Vector3(float(wp[0]), float(wp[1]), float(wp[2]))
						if rid == start_id:
							start_pos = pos
						if rid == goal_id:
							goal_pos = pos
		var path: Array = ThreatPathfinderScript.find_path(graph, start_pos, goal_pos)
		if path.is_empty() and start_id != goal_id:
			_fail("no nav path start→goal seed=%d" % s)
			return
		# Encounters well-formed when density path active
		var enc: Array = layout.get("encounters", []) as Array
		for e in enc:
			if not (e is Dictionary):
				_fail("encounter not dict seed=%d" % s)
				return
			var eroom: String = str((e as Dictionary).get("room_id", ""))
			if eroom.is_empty():
				_fail("encounter missing room_id seed=%d" % s)
				return
		# Determinism: regenerate same seed
		var layout2: Dictionary = gen.generate_with_options(bp, archetype, biome, diff, true)
		if JSON.stringify(layout) != JSON.stringify(layout2):
			_fail("non-deterministic layout seed=%d" % s)
			return
		if str(layout.get("hazard_source", "")) != "runtime":
			_fail("hazard_source missing/wrong seed=%d" % s)
			return
		layouts_ok += 1

	# Alias normalization unit check
	var nrm: Dictionary = RoomAssignerScript.normalize_archetype({
		"role_weights": {"compartment": 2, "cargo": 1},
		"guaranteed_roles": ["compartment", "dock"],
	})
	var rw: Dictionary = nrm.get("role_weights", {}) as Dictionary
	if int(rw.get("cargo", 0)) < 3:
		_fail("role alias weights not merged for cargo")
		return
	var gr: Array = nrm.get("guaranteed_roles", []) as Array
	if not ("cargo" in gr) or not ("dock" in gr):
		_fail("role alias guarantees failed: %s" % str(gr))
		return

	print("PROCGEN QUALITY GATE PASS seeds=%d layouts=%d walkable=true encounters=true schema=true" % [
		seeds_run, layouts_ok])
	quit(0)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var p: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return p if p is Dictionary else {}

func _fail(reason: String) -> void:
	push_error("PROCGEN QUALITY GATE FAIL reason=%s" % reason)
	quit(1)
