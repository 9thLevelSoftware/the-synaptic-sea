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


## Branch mutator on layout: convert some non-critical room_links into blocked_links.
## Preserves connectivity from entry by never blocking more than half of links and
## never blocking the first critical_path hop when present.
static func apply_branch_mutators(layout: Dictionary, seed_value: int) -> int:
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
	var protected: Dictionary = {}
	var crit: Variant = layout.get("critical_path", [])
	if crit is Array and (crit as Array).size() >= 2:
		protected["%s|%s" % [str(crit[0]), str(crit[1])]] = true
		protected["%s|%s" % [str(crit[1]), str(crit[0])]] = true
	var blocked: Array = []
	var bv: Variant = layout.get("blocked_links", [])
	if bv is Array:
		blocked = (bv as Array).duplicate(true)
	var kept: Array = []
	var blocked_n: int = 0
	var max_block: int = maxi(1, links.size() / 4)
	for link in links:
		if typeof(link) != TYPE_DICTIONARY:
			continue
		var L: Dictionary = (link as Dictionary).duplicate(true)
		var a: String = str(L.get("from_room", L.get("from", "")))
		var b: String = str(L.get("to_room", L.get("to", "")))
		var key: String = "%s|%s" % [a, b]
		var key_r: String = "%s|%s" % [b, a]
		if protected.has(key) or protected.has(key_r):
			kept.append(L)
			continue
		if blocked_n < max_block and rng.randf() < 0.28:
			L["module_id"] = "doorway_frame_blocked_1x1"
			L["reason"] = "branch_mutator"
			blocked.append(L)
			blocked_n += 1
		else:
			kept.append(L)
	layout["room_links"] = kept
	layout["blocked_links"] = blocked
	return blocked_n


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


static func _is_structural(module_kind: String) -> bool:
	if module_kind.is_empty():
		return false
	for prefix in WALL_PREFIXES:
		if module_kind.begins_with(prefix):
			return true
	return false


## Convenience: apply all mutators. flags: zone, branch, wreck.
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
		report["branch_blocks"] = apply_branch_mutators(layout, seed_value)
	if bool(flags.get("wreck", true)) and not layout.is_empty():
		var frac: float = float(flags.get("wreck_fraction", 0.35))
		report["wreck_damages"] = apply_wreck_mutator(layout, seed_value, null, frac)
	return report
