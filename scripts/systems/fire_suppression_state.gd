extends RefCounted
class_name FireSuppressionState

var compartments: Array[String] = []
var active_fires: Dictionary = {}
var suppressant_units: float = 100.0
var suppression_rate_per_second: float = 25.0
var power_threshold: float = 0.5

func configure(config: Dictionary) -> void:
	compartments.clear()
	for entry in config.get("compartments", []):
		compartments.append(str(entry))
	active_fires.clear()
	suppressant_units = maxf(0.0, float(config.get("suppressant_units", 100.0)))
	suppression_rate_per_second = maxf(0.1, float(config.get("suppression_rate_per_second", 25.0)))
	power_threshold = clampf(float(config.get("power_threshold", 0.5)), 0.05, 1.0)

func ignite(compartment_id: String, intensity: float = 1.0) -> bool:
	if compartment_id.is_empty():
		return false
	active_fires[compartment_id] = clampf(float(active_fires.get(compartment_id, 0.0)) + intensity, 0.1, 10.0)
	return true

func tick(delta: float, context: Dictionary) -> void:
	if delta <= 0.0 or active_fires.is_empty():
		return
	if float(context.get("powered_ratio", 0.0)) < power_threshold or suppressant_units <= 0.0:
		return
	var to_clear: Array[String] = []
	for compartment_id in active_fires.keys():
		var remaining: float = float(active_fires[compartment_id]) - suppression_rate_per_second * 0.01 * delta
		suppressant_units = maxf(0.0, suppressant_units - delta * 0.5)
		if remaining <= 0.0:
			to_clear.append(str(compartment_id))
		else:
			active_fires[compartment_id] = remaining
	for compartment_id in to_clear:
		active_fires.erase(compartment_id)

func get_active_fire_count() -> int:
	return active_fires.size()

func get_summary() -> Dictionary:
	return {
		"compartments": compartments.duplicate(),
		"active_fires": active_fires.duplicate(true),
		"suppressant_units": suppressant_units,
		"suppression_rate_per_second": suppression_rate_per_second,
		"power_threshold": power_threshold,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var fires: Variant = summary.get("active_fires", null)
	if typeof(fires) == TYPE_DICTIONARY and JSON.stringify(fires) != JSON.stringify(active_fires):
		active_fires = (fires as Dictionary).duplicate(true)
		changed = true
	var new_suppressant: float = float(summary.get("suppressant_units", suppressant_units))
	if absf(new_suppressant - suppressant_units) > 0.001:
		suppressant_units = new_suppressant
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Fire Suppression fires=%d suppressant=%.1f" % [get_active_fire_count(), suppressant_units])
	for compartment_id in active_fires.keys():
		lines.append("Fire %s intensity=%.2f" % [str(compartment_id), float(active_fires[compartment_id])])
	return lines
