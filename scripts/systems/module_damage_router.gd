extends RefCounted
class_name ModuleDamageRouter

## REQ-MI-004: single entry for structure damage into ModuleIntegrityMap.
## Sources: fire | decompression | threat | tool
## Pure — never touches the scene tree. Scene applies consequences separately.

const SOURCE_FIRE: String = "fire"
const SOURCE_DECOMPRESSION: String = "decompression"
const SOURCE_THREAT: String = "threat"
const SOURCE_TOOL: String = "tool"

const DEFAULT_FIRE_AMOUNT: float = 0.08
const DEFAULT_DECOMPRESSION_AMOUNT: float = 0.25
const DEFAULT_THREAT_AMOUNT: float = 0.35
const DEFAULT_TOOL_AMOUNT: float = 1.0


## Apply damage from a named source. Returns:
## { ok, source, module_id, amount, state_before, state_after, reason }
## resist: 0..1 fraction reduced before apply (e.g. hub hull_plating_bonus).
static func apply(
		module_map: RefCounted,
		module_id: String,
		source: String,
		amount: float = -1.0,
		kind: String = "",
		resist: float = 0.0) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"source": source,
		"module_id": module_id,
		"amount": 0.0,
		"state_before": "",
		"state_after": "",
		"reason": "",
	}
	if module_map == null or module_id.is_empty():
		out["reason"] = "bad_args"
		return out
	if not _is_known_source(source):
		out["reason"] = "unknown_source"
		return out
	var dmg: float = amount
	if dmg < 0.0:
		dmg = _default_amount(source)
	var r: float = clampf(resist, 0.0, 0.9)
	if r > 0.0:
		dmg *= (1.0 - r)
	if dmg <= 0.0:
		out["reason"] = "zero_damage"
		return out
	out["amount"] = dmg
	if module_map.has_method("get_state"):
		out["state_before"] = str(module_map.call("get_state", module_id))
	if module_map.has_method("apply_damage"):
		var after: String = str(module_map.call("apply_damage", module_id, dmg, kind))
		out["state_after"] = after
		out["ok"] = true
		return out
	out["reason"] = "no_apply"
	return out


## Damage all wall modules whose room_id maps to a compartment via role map.
## compartment_for_role: room_role -> compartment_id
## Returns list of module_ids changed.
static func apply_decompression_to_compartment(
		module_map: RefCounted,
		layout: Dictionary,
		compartment_id: String,
		compartment_for_role: Dictionary,
		amount: float = DEFAULT_DECOMPRESSION_AMOUNT) -> Array:
	var changed: Array = []
	if module_map == null or compartment_id.is_empty() or amount <= 0.0:
		return changed
	var rooms_v: Variant = layout.get("rooms", [])
	if typeof(rooms_v) != TYPE_ARRAY:
		return changed
	for room_v in (rooms_v as Array):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var role: String = str(room.get("room_role", room.get("role", "")))
		var comp: String = str(compartment_for_role.get(role, role))
		if comp != compartment_id and role != compartment_id:
			# Also match room id directly for simple layouts.
			if str(room.get("id", "")) != compartment_id:
				continue
		var room_id: String = str(room.get("id", ""))
		var placements_v: Variant = room.get("structural_placements", [])
		if typeof(placements_v) != TYPE_ARRAY:
			# Fall back: damage any registered modules with this room_id prefix.
			if module_map.has_method("module_ids"):
				for mid_v in module_map.call("module_ids"):
					var mid: String = str(mid_v)
					if mid.begins_with(room_id + "/") or mid.find(room_id) >= 0:
						var r: Dictionary = apply(module_map, mid, SOURCE_DECOMPRESSION, amount)
						if bool(r.get("ok", false)):
							changed.append(mid)
			continue
		for p_v in (placements_v as Array):
			if typeof(p_v) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_v
			var kind: String = str(p.get("module_id", p.get("module", "")))
			var pname: String = str(p.get("name", kind))
			var mid2: String = "%s/%s" % [room_id, pname]
			var r2: Dictionary = apply(module_map, mid2, SOURCE_DECOMPRESSION, amount, kind)
			if bool(r2.get("ok", false)):
				changed.append(mid2)
	return changed


## Threat structure strike against a single module (hull tendril fantasy).
static func apply_threat_structure_hit(
		module_map: RefCounted,
		module_id: String,
		amount: float = DEFAULT_THREAT_AMOUNT,
		kind: String = "",
		resist: float = 0.0) -> Dictionary:
	return apply(module_map, module_id, SOURCE_THREAT, amount, kind, resist)


## Player tool damage (WorkAction cut/pry already uses map.apply_damage; this
## keeps a uniform source tag for audits/smokes).
static func apply_tool_damage(
		module_map: RefCounted,
		module_id: String,
		amount: float = DEFAULT_TOOL_AMOUNT,
		kind: String = "",
		resist: float = 0.0) -> Dictionary:
	return apply(module_map, module_id, SOURCE_TOOL, amount, kind, resist)


static func _is_known_source(source: String) -> bool:
	return source in [SOURCE_FIRE, SOURCE_DECOMPRESSION, SOURCE_THREAT, SOURCE_TOOL]


static func _default_amount(source: String) -> float:
	match source:
		SOURCE_FIRE:
			return DEFAULT_FIRE_AMOUNT
		SOURCE_DECOMPRESSION:
			return DEFAULT_DECOMPRESSION_AMOUNT
		SOURCE_THREAT:
			return DEFAULT_THREAT_AMOUNT
		SOURCE_TOOL:
			return DEFAULT_TOOL_AMOUNT
		_:
			return 0.0


static func known_sources() -> PackedStringArray:
	return PackedStringArray([SOURCE_FIRE, SOURCE_DECOMPRESSION, SOURCE_THREAT, SOURCE_TOOL])
