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

const STRUCTURAL_PREFIXES: Array[String] = [
	"wall_", "bulkhead_", "panel_", "door_",
	"doorway_", "floor_", "corridor_", "pillar_", "ramp_",
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


## True for every P0 structural module family, including floors and traversal pieces.
static func is_structural_kind(kind: String) -> bool:
	if kind.is_empty():
		return false
	var k: String = kind.to_lower()
	for prefix in STRUCTURAL_PREFIXES:
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
	return _seed_map_from_layout_filtered(module_map, layout, Callable(is_wall_kind))


## Seed every P0 structural module family from a layout.json-shaped document.
## This companion path preserves the wall-only seed API for existing callers while
## allowing visual/integrity systems to register floors, corridors, pillars, ramps,
## and doorway modules as well.
static func seed_structural_map_from_layout(module_map: RefCounted, layout: Dictionary) -> int:
	return _seed_map_from_layout_filtered(module_map, layout, Callable(is_structural_kind))


## Register compiler-keyed modules (floor/<cell>, edge/<edge>, ceiling/<cell>)
## and optionally apply layout.module_damage. Falls back to placement names when no plan.
static func seed_map_from_compiled_layout(module_map: RefCounted, layout: Dictionary, apply_wreck: bool = true) -> int:
	if module_map == null or not module_map.has_method("ensure_module"):
		return 0
	var plan_v: Variant = layout.get("structural_plan", {})
	if typeof(plan_v) != TYPE_DICTIONARY or (plan_v as Dictionary).is_empty():
		return seed_map_from_layout(module_map, layout)
	var plan: Dictionary = plan_v
	var registered: int = 0
	registered += _seed_compiled_records(module_map, plan.get("floor_placements", []), "floor")
	registered += _seed_compiled_records(module_map, plan.get("placements", []), "edge")
	registered += _seed_compiled_records(module_map, plan.get("ceiling_placements", []), "ceiling")
	if not apply_wreck:
		return registered
	var md_v: Variant = layout.get("module_damage", [])
	if typeof(md_v) == TYPE_ARRAY:
		for row_v in (md_v as Array):
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = row_v
			var mid: String = str(row.get("module_key", row.get("module_id", "")))
			if mid.is_empty():
				continue
			var kind: String = str(row.get("kind", ""))
			var room_id: String = str(row.get("room_id", ""))
			module_map.call("ensure_module", mid, kind, {}, room_id)
			var amount: float = float(row.get("amount", 0.0))
			if amount > 0.0 and module_map.has_method("apply_damage"):
				module_map.call("apply_damage", mid, amount, kind)
	return registered


static func _seed_compiled_records(module_map: RefCounted, records_v: Variant, layer: String) -> int:
	if typeof(records_v) != TYPE_ARRAY:
		return 0
	var n: int = 0
	for rec_v in (records_v as Array):
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var kind: String = str(rec.get("module_id", rec.get("module", "")))
		var key_part: String = str(rec.get("edge_key", rec.get("key", ""))) if layer == "edge" else str(rec.get("cell_key", ""))
		if key_part.is_empty():
			continue
		var mid: String = "%s/%s" % [layer, key_part]
		var owners: PackedStringArray = PackedStringArray()
		var rooms_v: Variant = rec.get("room_ids", [])
		if rooms_v is Array:
			for rid_v in (rooms_v as Array):
				var rid: String = str(rid_v)
				if not rid.is_empty() and not owners.has(rid):
					owners.append(rid)
		var room_id: String = str(rec.get("room_id", ""))
		if not room_id.is_empty() and not owners.has(room_id):
			owners.insert(0, room_id)
		var primary: String = owners[0] if owners.size() > 0 else ""
		var inst: RefCounted = module_map.call("ensure_module", mid, kind, {}, primary)
		if inst != null and owners.size() > 1:
			inst.set("owner_rooms", owners)
		n += 1
	return n


static func _seed_map_from_layout_filtered(
		module_map: RefCounted,
		layout: Dictionary,
		kind_filter: Callable) -> int:
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
			if not bool(kind_filter.call(kind)):
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
	# Shared compiled walls can belong to two burning compartments. Keep the
	# max intensity per module so room order cannot suppress a hotter fire.
	var exposure: Dictionary = {}
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
		var compiled_ids: Array = registered_ids_for_room(module_map, room_id, true)
		if not compiled_ids.is_empty():
			for mid_v in compiled_ids:
				var mid: String = str(mid_v)
				var rec: RefCounted = module_map.call("get_module", mid) if module_map.has_method("get_module") else null
				var kind: String = str(rec.get("kind")) if rec != null else ""
				_accumulate_fire_exposure(exposure, mid, intensity, kind)
			continue
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
			_accumulate_fire_exposure(exposure, mid, intensity, kind)
	for mid_v in exposure.keys():
		var mid: String = str(mid_v)
		var rec_exp: Dictionary = exposure[mid]
		var dmg: float = damage_rate * float(rec_exp.get("intensity", 0.0)) * delta
		var kind: String = str(rec_exp.get("kind", ""))
		var before: String = str(module_map.call("get_state", mid)) if module_map.has_method("get_state") else ""
		var after: String = str(module_map.call("apply_damage", mid, dmg, kind))
		if after != before:
			changed.append(mid)
	return changed


static func _accumulate_fire_exposure(exposure: Dictionary, mid: String, intensity: float, kind: String) -> void:
	if mid.is_empty() or intensity <= 0.0:
		return
	if exposure.has(mid):
		var prev: Dictionary = exposure[mid]
		if intensity > float(prev.get("intensity", 0.0)):
			prev["intensity"] = intensity
		if str(prev.get("kind", "")).is_empty() and not kind.is_empty():
			prev["kind"] = kind
		return
	exposure[mid] = {"intensity": intensity, "kind": kind}


## Registered map ids for a room. Prefers compiler `edge/` `floor/` `ceiling/`
## keys already seeded on the map; empty means the caller should use placement names.
static func registered_ids_for_room(module_map: RefCounted, room_id: String, walls_only: bool) -> Array:
	var out: Array = []
	if module_map == null or room_id.is_empty() or not module_map.has_method("module_ids"):
		return out
	for mid_v in module_map.call("module_ids"):
		var mid: String = str(mid_v)
		if not module_map.has_method("get_module"):
			continue
		var rec: RefCounted = module_map.call("get_module", mid)
		if rec == null:
			continue
		if not _module_owned_by_room(rec, room_id):
			continue
		var kind: String = str(rec.get("kind"))
		if walls_only and not is_wall_kind(kind):
			continue
		out.append(mid)
	return out


static func _module_owned_by_room(rec: RefCounted, room_id: String) -> bool:
	if str(rec.get("room_id")) == room_id:
		return true
	var owners_v: Variant = rec.get("owner_rooms")
	if owners_v is PackedStringArray:
		return (owners_v as PackedStringArray).has(room_id)
	if owners_v is Array:
		for rid_v in (owners_v as Array):
			if str(rid_v) == room_id:
				return true
	return false


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
	# Variant wrappers swap Intact/Damaged/Breached children; albedo tint fights
	# IntegrityVisualResolver and is reserved for legacy single-child meshes.
	if not _wrapper_has_variant_visuals(node):
		var mod_v: Variant = cons.get("modulate", [1.0, 1.0, 1.0, 1.0])
		if mod_v is Array and (mod_v as Array).size() >= 3:
			var col := Color(float(mod_v[0]), float(mod_v[1]), float(mod_v[2]), float(mod_v[3]) if (mod_v as Array).size() > 3 else 1.0)
			_tint_meshes(node, col)
	var collision_on: bool = bool(cons.get("collision_enabled", true))
	_set_collisions_enabled(node, collision_on)


static func _wrapper_has_variant_visuals(node: Node) -> bool:
	if node == null:
		return false
	var visual: Node = node.get_node_or_null("Visual")
	if visual == null:
		return false
	return visual.get_node_or_null("VisualInstance_Intact") != null \
		or visual.get_node_or_null("VisualInstance_Damaged") != null \
		or visual.get_node_or_null("VisualInstance_Breached") != null


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
