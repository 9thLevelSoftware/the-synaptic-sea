extends RefCounted
class_name HullIntegrityState

var compartments: Dictionary = {}

func configure(config: Dictionary) -> void:
	compartments.clear()
	for entry in config.get("compartments", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		var compartment_id: String = str(row.get("compartment_id", ""))
		if compartment_id.is_empty():
			continue
		compartments[compartment_id] = {
			"health": clampf(float(row.get("health", 1.0)), 0.0, 1.0),
			"breach_open": bool(row.get("breach_open", false)),
			"isolation_rating": clampf(float(row.get("isolation_rating", 0.5)), 0.0, 1.0),
		}

func damage_compartment(compartment_id: String, amount: float, force_breach: bool = false) -> bool:
	if not compartments.has(compartment_id):
		return false
	var row: Dictionary = (compartments[compartment_id] as Dictionary).duplicate(true)
	row["health"] = maxf(0.0, float(row.get("health", 1.0)) - maxf(0.0, amount))
	if force_breach or float(row["health"]) <= 0.45:
		row["breach_open"] = true
	compartments[compartment_id] = row
	return true

func seal_compartment(compartment_id: String, repair_amount: float) -> bool:
	if not compartments.has(compartment_id):
		return false
	var row: Dictionary = (compartments[compartment_id] as Dictionary).duplicate(true)
	row["health"] = minf(1.0, float(row.get("health", 1.0)) + maxf(0.0, repair_amount))
	if float(row["health"]) >= 0.75:
		row["breach_open"] = false
	compartments[compartment_id] = row
	return true

func get_breach_count() -> int:
	var count: int = 0
	for compartment_id in compartments:
		if bool((compartments[compartment_id] as Dictionary).get("breach_open", false)):
			count += 1
	return count

func average_integrity() -> float:
	if compartments.is_empty():
		return 1.0
	var total: float = 0.0
	for compartment_id in compartments:
		total += float((compartments[compartment_id] as Dictionary).get("health", 1.0))
	return total / float(compartments.size())

func get_summary() -> Dictionary:
	return {"compartments": compartments.duplicate(true)}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var rows: Variant = summary.get("compartments", null)
	if typeof(rows) != TYPE_DICTIONARY:
		return false
	var new_rows: Dictionary = (rows as Dictionary).duplicate(true)
	if JSON.stringify(new_rows) == JSON.stringify(compartments):
		return false
	compartments = new_rows
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Hull Integrity %d%% breaches=%d" % [int(round(average_integrity() * 100.0)), get_breach_count()])
	for compartment_id in compartments:
		var row: Dictionary = compartments[compartment_id]
		if bool(row.get("breach_open", false)):
			lines.append("Hull %s BREACHED %d%%" % [compartment_id, int(round(float(row.get("health", 0.0)) * 100.0))])
	return lines
