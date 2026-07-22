extends RefCounted
class_name ModuleIntegrityConsequences

## PKG-B2.1b: pure scene-consequence contract for ModuleIntegrityState (ADR-0051).
## Maps integrity states → collision / passability / atmosphere / mesh tags.
## Also seeds maps from layouts and routes fire damage into wall modules.

const ModuleIntegrityStateScript: GDScript = preload("res://scripts/systems/module_integrity_state.gd")
const ModuleIntegrityMapScript: GDScript = preload("res://scripts/systems/module_integrity_map.gd")

const WALL_PREFIXES: Array[String] = [
	"wall_", "bulkhead_", "panel_", "door_",
]

## Damage to a wall module per unit fire intensity per second.
const FIRE_MODULE_DAMAGE_PER_INTENSITY: float = 0.08


static func is_wall_kind(kind: String) -> bool:
	if kind.is_empty():
		return false
	var k: String = kind.to_lower()
	for prefix in WALL_PREFIXES:
		if k.begins_with(prefix) or k.find(prefix) >= 0:
			return true
	return false


## Pure consequence descriptor consumed by scene / nav layers.
static func consequence_for_state(state: String) -> Dictionary:
	match state:
		ModuleIntegrityStateScript.STATE_INTACT:
			return {
				"state": state,
				"collision_enabled": true,
				"crawl_passable": false,
				"atmosphere_link": false,
				"nav_gap": false,
				"mesh_suffix": "",
				"modulate": [1.0, 1.0, 1.0, 1.0],
			}
		ModuleIntegrityStateScript.STATE_DAMAGED:
			return {
				"state": state,
				"collision_enabled": true,
				"crawl_passable": false,
				"atmosphere_link": false,
				"nav_gap": false,
				"mesh_suffix": "_damaged",
				"modulate": [0.85, 0.70, 0.55, 1.0],
			}
		ModuleIntegrityStateScript.STATE_BREACHED:
			return {
				"state": state,
				"collision_enabled": true,
				"crawl_passable": true,
				"atmosphere_link": true,
				"nav_gap": true,
				"mesh_suffix": "_breached",
				"modulate": [0.55, 0.60, 0.75, 1.0],
			}
		ModuleIntegrityStateScript.STATE_DESTROYED:
			return {
				"state": state,
				"collision_enabled": false,
				"crawl_passable": true,
				"atmosphere_link": true,
				"nav_gap": true,
				"mesh_suffix": "_destroyed",
				"modulate": [0.35, 0.35, 0.35, 0.55],
			}
		_:
			return consequence_for_state(ModuleIntegrityStateScript.STATE_INTACT)


## Count wall modules that open atmosphere (breached or destroyed).
static func derived_breach_count(module_map: RefCounted) -> int:
	if module_map == null or not module_map.has_method("get_module"):
		return 0
	var count: int = 0
	var summary: Dictionary = {}
	if module_map.has_method("get_summary"):
		summary = module_map.call("get_summary")
	var deltas: Variant = summary.get("deltas", [])
	if typeof(deltas) != TYPE_ARRAY:
		# fall back: walk registered modules via fingerprint-like iteration
		return _count_breaches_via_size(module_map)
	for entry in deltas:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kind: String = str(entry.get("kind", ""))
		if not is_wall_kind(kind):
			continue
		var st: String = str(entry.get("state", ""))
		if st == ModuleIntegrityStateScript.STATE_BREACHED or st == ModuleIntegrityStateScript.STATE_DESTROYED:
			count += 1
	return count


static func _count_breaches_via_size(module_map: RefCounted) -> int:
	# Prefer explicit iteration API if present.
	if module_map.has_method("count_wall_breaches"):
		return int(module_map.call("count_wall_breaches"))
	return 0


## Seed wall modules from a layout.json-shaped document. Returns modules registered.
static func seed_map_from_layout(module_map: RefCounted, layout: Dictionary) -> int:
	if module_map == null or not module_map.has_method("ensure_module"):
		return 0
	var rooms_v: Variant = layout.get("rooms", [])
	if typeof(rooms_v) != TYPE_ARRAY:
		return 0
	var registered: int = 0
	for room_v in (rooms_v as Array):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var room_id: String = str(room.get("id", ""))
		var placements_v: Variant = room.get("structural_placements", [])
		if typeof(placements_v) != TYPE_ARRAY:
			continue
		for placement_v in (placements_v as Array):
			if typeof(placement_v) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_v
			var kind: String = str(placement.get("module_id", placement.get("module", "")))
			if not is_wall_kind(kind):
				continue
			var pname: String = str(placement.get("name", kind))
			var mid: String = "%s/%s" % [room_id, pname]
			module_map.call("ensure_module", mid, kind, {}, room_id)
			registered += 1
	return registered


## Apply fire intensity damage to wall modules in rooms belonging to burning compartments.
## compartment_for_role: room_role -> compartment_id
## burning: compartment_id -> intensity
## Returns list of module_ids whose state changed.
static func apply_fire_damage(
		module_map: RefCounted,
		layout: Dictionary,
		burning: Dictionary,
		compartment_for_role: Dictionary,
		delta: float,
		damage_rate: float = FIRE_MODULE_DAMAGE_PER_INTENSITY) -> Array:
	var changed: Array = []
	if module_map == null or delta <= 0.0 or burning.is_empty():
		return changed
	var rooms_v: Variant = layout.get("rooms", [])
	if typeof(rooms_v) != TYPE_ARRAY:
		return changed
	for room_v in (rooms_v as Array):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var role: String = str(room.get("room_role", room.get("role", "")))
		var compartment: String = str(compartment_for_role.get(role, ""))
		if compartment.is_empty() or not burning.has(compartment):
			continue
		var intensity: float = float(burning[compartment])
		if intensity <= 0.0:
			continue
		var room_id: String = str(room.get("id", ""))
		var dmg: float = damage_rate * intensity * delta
		var placements_v: Variant = room.get("structural_placements", [])
		if typeof(placements_v) != TYPE_ARRAY:
			continue
		for placement_v in (placements_v as Array):
			if typeof(placement_v) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_v
			var kind: String = str(placement.get("module_id", placement.get("module", "")))
			if not is_wall_kind(kind):
				continue
			var pname: String = str(placement.get("name", kind))
			var mid: String = "%s/%s" % [room_id, pname]
			var before: String = str(module_map.call("get_state", mid)) if module_map.has_method("get_state") else ""
			var after: String = str(module_map.call("apply_damage", mid, dmg, kind))
			if after != before:
				changed.append(mid)
	return changed


## Apply collision / modulate consequences to a structural wrapper Node3D.
static func apply_to_node(node: Node3D, state: String) -> void:
	if node == null:
		return
	var cons: Dictionary = consequence_for_state(state)
	node.set_meta("integrity_state", state)
	node.set_meta("mesh_suffix", str(cons.get("mesh_suffix", "")))
	node.set_meta("crawl_passable", bool(cons.get("crawl_passable", false)))
	node.set_meta("atmosphere_link", bool(cons.get("atmosphere_link", false)))
	node.set_meta("nav_gap", bool(cons.get("nav_gap", false)))
	var mod_v: Variant = cons.get("modulate", [1.0, 1.0, 1.0, 1.0])
	if mod_v is Array and (mod_v as Array).size() >= 3:
		var col := Color(float(mod_v[0]), float(mod_v[1]), float(mod_v[2]), float(mod_v[3]) if (mod_v as Array).size() > 3 else 1.0)
		_tint_meshes(node, col)
	var collision_on: bool = bool(cons.get("collision_enabled", true))
	_set_collisions_enabled(node, collision_on)


static func _tint_meshes(node: Node, color: Color) -> void:
	# Godot 4 MeshInstance3D has no modulate; use material override albedo.
	if node is MeshInstance3D:
		var mesh_i: MeshInstance3D = node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		if color.a < 0.99:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_i.material_override = mat
	for child in node.get_children():
		_tint_meshes(child, color)


static func _set_collisions_enabled(node: Node, enabled: bool) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = not enabled
	if node is CollisionPolygon3D:
		(node as CollisionPolygon3D).disabled = not enabled
	for child in node.get_children():
		_set_collisions_enabled(child, enabled)


## Open nav gaps for rooms that have breached/destroyed walls (lower edge cost).
static func apply_nav_gaps(nav_graph: RefCounted, room_ids_with_gaps: Array) -> void:
	if nav_graph == null or room_ids_with_gaps.is_empty():
		return
	if not nav_graph.has_method("set_edge_cost_multiplier"):
		return
	var gap_set: Dictionary = {}
	for rid in room_ids_with_gaps:
		gap_set[str(rid)] = true
	# Soften edges that touch gap rooms (walkable hole fantasy).
	if not nav_graph.has_method("neighbors") or not ("nodes" in nav_graph):
		return
	var nodes: Dictionary = nav_graph.get("nodes")
	for key in nodes.keys():
		var room_id: String = ""
		if nav_graph.has_method("get_node_room"):
			room_id = str(nav_graph.call("get_node_room", str(key)))
		if not gap_set.has(room_id):
			continue
		var neigh: Array = nav_graph.call("neighbors", str(key))
		for n in neigh:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var to_id: String = str(n.get("to", ""))
			if to_id.is_empty():
				continue
			nav_graph.call("set_edge_cost_multiplier", str(key), to_id, 0.35)
