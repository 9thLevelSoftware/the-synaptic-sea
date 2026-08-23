extends RefCounted
class_name LayoutMutator

## PKG-D5.4: pure zone/branch/wreck mutators for procgen layouts.
## Operates on TopologyTemplate clones and layout.json dictionaries.
## Wreck pre-applies module damage into layout.module_damage + ModuleIntegrityMap.

const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")

const WALL_PREFIXES: Array[String] = [
	"wall_", "bulkhead_", "doorway_", "pillar_",
]


## Mutate a TopologyTemplate in place: optionally drop non-critical lateral zones
## and nudge zone counts (seeded). Returns number of zone mutations applied.
static func apply_zone_mutators(template: RefCounted, seed_value: int) -> int:
	if template == null:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(seed_value) ^ 0xA0A1E5) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var mutations: int = 0
	# Copy zones array for mutation
	var zones: Array = []
	for z in template.zones:
		zones.append((z as Dictionary).duplicate(true) if typeof(z) == TYPE_DICTIONARY else z)
	var kept: Array = []
	for z in zones:
		if typeof(z) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = z
		var zid: String = str(zone.get("id", ""))
		var hint: String = str(zone.get("position_hint", ""))
		# Never drop entry/destination
		if zid == "entry" or zid == "destination" or zid.begins_with("destination"):
			kept.append(zone)
			continue
		# 20% chance to drop optional lateral pockets (not corridors)
		var layout: String = str(zone.get("layout", "single"))
		if hint == "lateral" and layout == "clustered" and rng.randf() < 0.2:
			mutations += 1
			continue
		# Nudge array counts
		var count_v: Variant = zone.get("count", 1)
		if count_v is Array and (count_v as Array).size() >= 2:
			var lo: int = int((count_v as Array)[0])
			var hi: int = int((count_v as Array)[1])
			if hi > lo and rng.randf() < 0.35:
				var pick: int = rng.randi_range(lo, hi)
				zone["count"] = pick
				mutations += 1
		kept.append(zone)
	# Rebuild template.zones typed array
	template.zones.clear()
	for k in kept:
		template.zones.append(k)
	# Drop connections that reference missing zones
	var alive: Dictionary = {}
	for z2 in template.zones:
		alive[str((z2 as Dictionary).get("id", ""))] = true
	var new_conns: Array[Dictionary] = []
	for c in template.connections:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var from_id: String = str((c as Dictionary).get("from", ""))
		var to_id: String = str((c as Dictionary).get("to", ""))
		if alive.has(from_id) and alive.has(to_id):
			new_conns.append(c)
		else:
			mutations += 1
	template.connections = new_conns
	return mutations


## Overlay branch locks: copy non-critical hops into blocked_links and leave
## every room_link in place. Live generation uses this so room-link BFS stays true.
static func apply_branch_overlays(layout: Dictionary, seed_value: int) -> int:
	return apply_branch_mutators(layout, seed_value, true)


## Branch mutator on layout. Legacy (overlay=false) removes blocked hops from
## room_links. Overlay mode keeps room_links and stamps blocked_links copies.
## Cap is links.size()/4. Overlay protects every critical_path hop; legacy
## protects only the first hop (historical templates_wreck_mutator contract).
static func apply_branch_mutators(layout: Dictionary, seed_value: int, overlay: bool = false) -> int:
	if layout.is_empty():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(seed_value) ^ 0xB1A4C4) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var links_v: Variant = layout.get("room_links", [])
	if typeof(links_v) != TYPE_ARRAY:
		return 0
	var links: Array = (links_v as Array).duplicate(true)
	if links.size() < 3:
		return 0
	var protected: Dictionary = _protected_hops(layout, overlay)
	var blocked: Array = []
	var bv: Variant = layout.get("blocked_links", [])
	if bv is Array:
		blocked = (bv as Array).duplicate(true)
	var kept: Array = []
	var blocked_n: int = 0
	var max_block: int = maxi(1, links.size() / 4)
	var overlay_fallback: Dictionary = {}
	for link in links:
		if typeof(link) != TYPE_DICTIONARY:
			continue
		var original: Dictionary = (link as Dictionary).duplicate(true)
		var a: String = str(original.get("from_room", original.get("from", "")))
		var b: String = str(original.get("to_room", original.get("to", "")))
		var key: String = "%s|%s" % [a, b]
		var key_r: String = "%s|%s" % [b, a]
		var vertical: bool = _link_is_vertical(original)
		var can_block: bool = not protected.has(key) and not protected.has(key_r) and not vertical
		if overlay:
			kept.append(original)
			if can_block:
				if overlay_fallback.is_empty():
					overlay_fallback = original
				if blocked_n < max_block and rng.randf() < 0.28:
					var stamped: Dictionary = original.duplicate(true)
					stamped["module_id"] = "doorway_frame_blocked_1x1"
					stamped["reason"] = "branch_mutator"
					blocked.append(stamped)
					blocked_n += 1
			continue
		if not can_block:
			kept.append(original)
			continue
		if blocked_n < max_block and rng.randf() < 0.28:
			original["module_id"] = "doorway_frame_blocked_1x1"
			original["reason"] = "branch_mutator"
			blocked.append(original)
			blocked_n += 1
		else:
			kept.append(original)
	if overlay and blocked_n == 0 and not overlay_fallback.is_empty():
		var forced: Dictionary = overlay_fallback.duplicate(true)
		forced["module_id"] = "doorway_frame_blocked_1x1"
		forced["reason"] = "branch_mutator"
		blocked.append(forced)
		blocked_n = 1
	layout["room_links"] = kept
	layout["blocked_links"] = blocked
	return blocked_n


## Stamp matching portals[].state from blocked_links (LOCKED) and optionally
## convert one non-critical remaining DOOR to BREACH. Never inserts a portal.
static func apply_portal_overlays(layout: Dictionary, seed_value: int, allow_breach: bool = false) -> int:
	if layout.is_empty():
		return 0
	var portals_v: Variant = layout.get("portals", [])
	if typeof(portals_v) != TYPE_ARRAY:
		return 0
	var portals: Array = portals_v
	var stamped: int = 0
	var blocked_v: Variant = layout.get("blocked_links", [])
	var blocked: Array = blocked_v if blocked_v is Array else []
	for i in range(portals.size()):
		if typeof(portals[i]) != TYPE_DICTIONARY:
			continue
		var portal: Dictionary = portals[i]
		if not _portal_matches_any_link(portal, blocked):
			continue
		portal["state"] = "LOCKED"
		portal["module_id"] = "doorway_frame_blocked_1x1"
		portals[i] = portal
		stamped += 1
	if allow_breach:
		stamped += _stamp_one_breach_portal(layout, seed_value)
	layout["portals"] = portals
	return stamped


## Wreck mutator: pre-tear structural modules. Writes layout["module_damage"] and
## optionally fills a ModuleIntegrityMap. Returns damage event count.
static func apply_wreck_mutator(
		layout: Dictionary,
		seed_value: int,
		integrity_map: RefCounted = null,
		damage_fraction: float = 0.35) -> int:
	if layout.is_empty():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(seed_value) ^ 0x1EC4001) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var frac: float = clampf(damage_fraction, 0.05, 0.9)
	var damages: Array = []
	var rooms_v: Variant = layout.get("rooms", [])
	if typeof(rooms_v) != TYPE_ARRAY:
		return 0
	var map = integrity_map
	if map == null:
		map = ModuleIntegrityMapScript.new()
	var damaged: int = 0
	for room_v in rooms_v:
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var room_id: String = str(room.get("id", ""))
		var placements_v: Variant = room.get("structural_placements", [])
		if typeof(placements_v) != TYPE_ARRAY:
			continue
		var p_idx: int = 0
		for pv in placements_v:
			if typeof(pv) != TYPE_DICTIONARY:
				p_idx += 1
				continue
			var p: Dictionary = pv
			var module_kind: String = str(p.get("module_id", p.get("module", "")))
			if not _is_structural(module_kind):
				p_idx += 1
				continue
			if rng.randf() > frac:
				p_idx += 1
				continue
			var amount: float = 0.25 + rng.randf() * 0.7  # 0.25..0.95
			var module_id: String = "%s/%s_%d" % [room_id, module_kind, p_idx]
			if map.has_method("ensure_module"):
				map.call("ensure_module", module_id, module_kind, {}, room_id)
			if map.has_method("apply_damage"):
				map.call("apply_damage", module_id, amount, module_kind)
			damages.append({
				"module_id": module_id,
				"kind": module_kind,
				"room_id": room_id,
				"amount": amount,
			})
			damaged += 1
			p_idx += 1
	layout["module_damage"] = damages
	layout["wreck_applied"] = true
	layout["wreck_seed"] = seed_value
	return damaged


## Wreck stamp keyed by loader module_key after compile. Does not restamp.
static func apply_wreck_to_compiled_plan(
		layout: Dictionary,
		seed_value: int,
		integrity_map: RefCounted = null,
		damage_fraction: float = 0.35) -> int:
	if layout.is_empty():
		return 0
	if bool(layout.get("wreck_applied", false)):
		var existing: Variant = layout.get("module_damage", [])
		return (existing as Array).size() if existing is Array else 0
	var plan_v: Variant = layout.get("structural_plan", {})
	if typeof(plan_v) != TYPE_DICTIONARY or (plan_v as Dictionary).is_empty():
		return 0
	var plan: Dictionary = plan_v
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(seed_value) ^ 0x1EC4001) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var frac: float = clampf(damage_fraction, 0.05, 0.9)
	var map = integrity_map
	if map == null:
		map = ModuleIntegrityMapScript.new()
	var candidates: Array = []
	_collect_compiled_records(candidates, plan.get("floor_placements", []), "floor")
	_collect_compiled_records(candidates, plan.get("placements", []), "edge")
	_collect_compiled_records(candidates, plan.get("ceiling_placements", []), "ceiling")
	var damages: Array = []
	var damaged: int = 0
	var fallback: Dictionary = {}
	for rec_v in candidates:
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		if rng.randf() > frac:
			if fallback.is_empty():
				fallback = rec
			continue
		_stamp_compiled_damage(rec, map, rng, damages)
		damaged += 1
	if damaged == 0 and not fallback.is_empty():
		_stamp_compiled_damage(fallback, map, rng, damages)
		damaged = 1
	layout["module_damage"] = damages
	layout["wreck_applied"] = true
	layout["wreck_seed"] = seed_value
	return damaged


static func seed_integrity_map_from_module_damage(module_map: RefCounted, layout: Dictionary) -> int:
	if module_map == null or not module_map.has_method("ensure_module"):
		return 0
	var registered: int = 0
	var plan_v: Variant = layout.get("module_damage", [])
	if typeof(plan_v) != TYPE_ARRAY:
		return 0
	for row_v in (plan_v as Array):
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
		registered += 1
	return registered


static func _is_structural(module_kind: String) -> bool:
	if module_kind.is_empty():
		return false
	for prefix in WALL_PREFIXES:
		if module_kind.begins_with(prefix):
			return true
	var k: String = module_kind.to_lower()
	if k.begins_with("floor_") or k.begins_with("corridor_") or k.begins_with("ceiling_"):
		return true
	return false


## Convenience: apply all mutators. flags: zone, branch, wreck, overlay.
static func apply_all(
		template: RefCounted,
		layout: Dictionary,
		seed_value: int,
		flags: Dictionary = {}) -> Dictionary:
	var report: Dictionary = {
		"zone_mutations": 0,
		"branch_blocks": 0,
		"wreck_damages": 0,
	}
	if bool(flags.get("zone", true)) and template != null:
		report["zone_mutations"] = apply_zone_mutators(template, seed_value)
	if bool(flags.get("branch", true)) and not layout.is_empty():
		if bool(flags.get("overlay", false)):
			report["branch_blocks"] = apply_branch_overlays(layout, seed_value)
			apply_portal_overlays(layout, seed_value, bool(flags.get("breach", false)))
		else:
			report["branch_blocks"] = apply_branch_mutators(layout, seed_value)
	if bool(flags.get("wreck", true)) and not layout.is_empty():
		var frac: float = float(flags.get("wreck_fraction", 0.35))
		if bool(flags.get("compiled", false)):
			report["wreck_damages"] = apply_wreck_to_compiled_plan(layout, seed_value, null, frac)
		else:
			report["wreck_damages"] = apply_wreck_mutator(layout, seed_value, null, frac)
	return report


static func _protected_hops(layout: Dictionary, overlay: bool) -> Dictionary:
	var protected: Dictionary = {}
	var crit: Variant = layout.get("critical_path", [])
	if not (crit is Array) or (crit as Array).size() < 2:
		return protected
	var path: Array = crit
	var last: int = path.size() - 1 if overlay else 1
	last = mini(last, path.size() - 1)
	for i in range(last):
		var a: String = str(path[i])
		var b: String = str(path[i + 1])
		protected["%s|%s" % [a, b]] = true
		protected["%s|%s" % [b, a]] = true
	return protected


static func _link_is_vertical(link: Dictionary) -> bool:
	var from_cell: Variant = link.get("from_cell", null)
	var to_cell: Variant = link.get("to_cell", null)
	if from_cell is Array and to_cell is Array:
		var fa: Array = from_cell
		var ta: Array = to_cell
		if fa.size() >= 3 and ta.size() >= 3:
			return int(fa[2]) != int(ta[2])
	return false


static func _portal_matches_any_link(portal: Dictionary, links: Array) -> bool:
	for link_v in links:
		if typeof(link_v) != TYPE_DICTIONARY:
			continue
		if _portal_matches_link(portal, link_v):
			return true
	return false


static func _portal_matches_link(portal: Dictionary, link: Dictionary) -> bool:
	var pf: String = str(portal.get("from_room", ""))
	var pt: String = str(portal.get("to_room", ""))
	var lf: String = str(link.get("from_room", link.get("from", "")))
	var lt: String = str(link.get("to_room", link.get("to", "")))
	if pf.is_empty() or pt.is_empty() or lf.is_empty() or lt.is_empty():
		return false
	var rooms_match: bool = (pf == lf and pt == lt) or (pf == lt and pt == lf)
	if not rooms_match:
		return false
	var p_from: Vector2i = _cell_xz(portal.get("from_cell", portal.get("cell", null)))
	var p_to: Vector2i = _cell_xz(portal.get("to_cell", null))
	var l_from: Vector2i = _cell_xz(link.get("from_cell", null))
	var l_to: Vector2i = _cell_xz(link.get("to_cell", null))
	if l_from == Vector2i(-99999, -99999) or l_to == Vector2i(-99999, -99999):
		return true
	if p_from == Vector2i(-99999, -99999) or p_to == Vector2i(-99999, -99999):
		return true
	return (p_from == l_from and p_to == l_to) or (p_from == l_to and p_to == l_from)


static func _stamp_one_breach_portal(layout: Dictionary, seed_value: int) -> int:
	var portals_v: Variant = layout.get("portals", [])
	if typeof(portals_v) != TYPE_ARRAY:
		return 0
	var portals: Array = portals_v
	var protected: Dictionary = _protected_hops(layout, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(seed_value) ^ 0xB4EAC4) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1
	var candidates: Array[int] = []
	for i in range(portals.size()):
		if typeof(portals[i]) != TYPE_DICTIONARY:
			continue
		var portal: Dictionary = portals[i]
		var state: String = str(portal.get("state", "DOOR")).to_upper()
		if state != "DOOR":
			continue
		var a: String = str(portal.get("from_room", ""))
		var b: String = str(portal.get("to_room", ""))
		if protected.has("%s|%s" % [a, b]) or protected.has("%s|%s" % [b, a]):
			continue
		candidates.append(i)
	if candidates.is_empty():
		return 0
	var pick: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	var chosen: Dictionary = portals[pick]
	chosen["state"] = "BREACH"
	chosen["module_id"] = ""
	portals[pick] = chosen
	layout["portals"] = portals
	return 1


static func _cell_xz(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i(-99999, -99999)


static func _collect_compiled_records(out: Array, records_v: Variant, layer: String) -> void:
	if typeof(records_v) != TYPE_ARRAY:
		return
	for rec_v in (records_v as Array):
		if typeof(rec_v) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_v
		var module_kind: String = str(rec.get("module_id", rec.get("module", "")))
		if not _is_structural(module_kind):
			continue
		var key_part: String = ""
		if layer == "edge":
			key_part = str(rec.get("edge_key", rec.get("key", "")))
		else:
			key_part = str(rec.get("cell_key", ""))
		if key_part.is_empty():
			continue
		var room_id: String = str(rec.get("room_id", ""))
		if room_id.is_empty():
			var rooms_v: Variant = rec.get("room_ids", [])
			if rooms_v is Array and not (rooms_v as Array).is_empty():
				room_id = str((rooms_v as Array)[0])
		out.append({
			"layer": layer,
			"key_part": key_part,
			"kind": module_kind,
			"room_id": room_id,
			"placement_id": str(rec.get("placement_id", rec.get("id", ""))),
		})


static func _stamp_compiled_damage(
		rec: Dictionary,
		map: RefCounted,
		rng: RandomNumberGenerator,
		damages: Array) -> void:
	var amount: float = 0.30 + rng.randf() * 0.38
	var module_key: String = "%s/%s" % [str(rec.get("layer", "edge")), str(rec.get("key_part", ""))]
	var module_kind: String = str(rec.get("kind", ""))
	var room_id: String = str(rec.get("room_id", ""))
	if map.has_method("ensure_module"):
		map.call("ensure_module", module_key, module_kind, {}, room_id)
	var state: String = "damaged"
	if map.has_method("apply_damage"):
		state = str(map.call("apply_damage", module_key, amount, module_kind))
	else:
		state = _state_for_amount(amount)
	damages.append({
		"module_id": module_key,
		"module_key": module_key,
		"placement_id": str(rec.get("placement_id", "")),
		"kind": module_kind,
		"room_id": room_id,
		"amount": amount,
		"state": state,
	})


static func _state_for_amount(amount: float) -> String:
	var integrity: float = clampf(1.0 - amount, 0.0, 1.0)
	if integrity <= 0.05:
		return "destroyed"
	if integrity <= 0.40:
		return "breached"
	if integrity <= 0.75:
		return "damaged"
	return "intact"
