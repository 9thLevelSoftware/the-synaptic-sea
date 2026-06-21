extends RefCounted
class_name ScannerState

## Resolves which markers are visible and at what detail, gated by the ship's
## navigation/scanners systems and the player's scanner_operation skill. Pure
## logic — callers pass operational status as a plain dict.

const MAX_DETAIL := 6

var range_radius: float = 250.0   # spatial reach
var hardware_detail: int = 1      # base detail from scanner hardware (upgradeable)

## systems_ops: { "navigation": bool, "scanners": bool }. scanner_skill: 0..10.
## Returns { "detail_level": int, "markers": Array[Dictionary] }.
func scan(world, systems_ops: Dictionary, scanner_skill: int) -> Dictionary:
	if not bool(systems_ops.get("navigation", false)):
		return {"detail_level": 0, "markers": []}
	var detail: int = 1
	if bool(systems_ops.get("scanners", false)):
		detail = mini(MAX_DETAIL, hardware_detail + _skill_bonus(scanner_skill))
	var views: Array = []
	for m in world.markers_in_range(range_radius):
		views.append(_marker_view(m, world.player_position, detail))
	return {"detail_level": detail, "markers": views}

func _skill_bonus(skill: int) -> int:
	return int(skill / 2)   # every 2 skill points -> +1 detail

func _marker_view(m, player_pos: Vector3, detail: int) -> Dictionary:
	var view: Dictionary = {
		"marker_id": m.marker_id,
		"position": [m.position.x, m.position.y, m.position.z],
		"distance": m.position.distance_to(player_pos),
		"size_class": m.size_class,
	}
	if detail >= 2:
		view["ship_type"] = m.ship_type
	if detail >= 3:
		view["condition"] = m.condition
	if detail >= 4:
		view["predicted_status"] = _predicted_status(m.condition)
	if detail >= 5:
		view["predicted_offline"] = _predicted_offline(m.condition, m.size_class)
	if detail >= 6:
		view["loot_hint"] = _loot_hint(m.size_class, m.condition)
	return view

func _predicted_status(condition: int) -> String:
	match condition:
		0: return "systems nominal"
		1: return "systems degraded"
		_: return "systems critical"

func _predicted_offline(condition: int, _size_class: int) -> Array:
	# Deterministic guess of likely-offline systems from condition.
	match condition:
		0: return []
		1: return ["scanners"]
		_: return ["scanners", "navigation", "propulsion"]

func _loot_hint(size_class: int, condition: int) -> String:
	var scale: String = ["meagre", "modest", "rich"][clampi(size_class, 0, 2)]
	var salvage: String = "intact" if condition == 0 else "salvageable"
	return "%s cache, %s" % [scale, salvage]

func get_summary() -> Dictionary:
	return {"range_radius": range_radius, "hardware_detail": hardware_detail}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	range_radius = float(summary.get("range_radius", range_radius))
	hardware_detail = int(summary.get("hardware_detail", hardware_detail))
	return true
