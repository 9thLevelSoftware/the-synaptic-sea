extends RefCounted
class_name AmmoState

## Ammo reserve tracker for consumable ammo packs. Combat does not exist yet, so
## this package owns reserve increments/decrements and hotbar/runtime visibility.

var reserves: Dictionary = {}
var last_ammo_kind: String = ""
var total_consumed: int = 0

func configure(config: Dictionary = {}) -> void:
	reserves.clear()
	last_ammo_kind = ""
	total_consumed = 0
	var raw: Variant = config.get("reserves", {})
	if raw is Dictionary:
		for ammo_kind in (raw as Dictionary):
			reserves[str(ammo_kind)] = max(0, int((raw as Dictionary)[ammo_kind]))

func add_ammo(ammo_kind: String, amount: int) -> int:
	if ammo_kind.is_empty() or amount <= 0:
		return 0
	var current: int = get_reserve(ammo_kind)
	reserves[ammo_kind] = current + amount
	last_ammo_kind = ammo_kind
	return amount

func consume(ammo_kind: String, amount: int) -> int:
	if ammo_kind.is_empty() or amount <= 0:
		return 0
	var current: int = get_reserve(ammo_kind)
	var removed: int = min(amount, current)
	if removed <= 0:
		return 0
	reserves[ammo_kind] = current - removed
	if int(reserves[ammo_kind]) <= 0:
		reserves.erase(ammo_kind)
	last_ammo_kind = ammo_kind
	total_consumed += removed
	return removed

func get_reserve(ammo_kind: String) -> int:
	return int(reserves.get(ammo_kind, 0))

func get_summary() -> Dictionary:
	return {
		"reserves": reserves.duplicate(true),
		"last_ammo_kind": last_ammo_kind,
		"total_consumed": total_consumed,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	configure({"reserves": summary.get("reserves", {})})
	last_ammo_kind = str(summary.get("last_ammo_kind", last_ammo_kind))
	total_consumed = int(summary.get("total_consumed", total_consumed))
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var ammo_kinds: Array = reserves.keys()
	ammo_kinds.sort()
	for ammo_kind in ammo_kinds:
		lines.append("Ammo %s=%d" % [String(ammo_kind), int(reserves[ammo_kind])])
	return lines
