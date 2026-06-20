extends RefCounted
class_name ShipSystemState

## Runtime model for ship systems on the main playable slice.
## Mutates only via apply_objective(); never reaches into the scene tree.
## Each (sequence) can be applied at most once; repeat calls are no-ops.

const INITIAL_POWER_PERCENT: int = 18
const INITIAL_REACTOR_STABILITY_PERCENT: int = 22
const RESTORED_POWER_PERCENT: int = 72
const STABILIZED_REACTOR_PERCENT: int = 100

var emergency_supplies_recovered: bool = false
var main_power_restored: bool = false
var navigation_logs_downloaded: bool = false
var reactor_stabilized: bool = false
var blocked_routes_cleared: bool = false
var extraction_unlocked: bool = false
var power_percent: int = INITIAL_POWER_PERCENT
var reactor_stability_percent: int = INITIAL_REACTOR_STABILITY_PERCENT
var completed_sequences: Array = []

func apply_objective(sequence: int, objective_type: String, _objective_id: String, _room_id: String) -> bool:
	if sequence <= 0:
		return false
	if completed_sequences.has(sequence):
		return false
	completed_sequences.append(sequence)
	match objective_type:
		"recover_supplies":
			emergency_supplies_recovered = true
		"restore_systems":
			main_power_restored = true
			blocked_routes_cleared = true
			power_percent = RESTORED_POWER_PERCENT
		"download_logs":
			navigation_logs_downloaded = true
		"stabilize_reactor":
			reactor_stabilized = true
			reactor_stability_percent = STABILIZED_REACTOR_PERCENT
			extraction_unlocked = true
		_:
			# Unknown objective type still records the sequence as completed
			# but does not flip any flags.
			pass
	return true

func get_summary() -> Dictionary:
	return {
		"emergency_supplies_recovered": emergency_supplies_recovered,
		"main_power_restored": main_power_restored,
		"navigation_logs_downloaded": navigation_logs_downloaded,
		"reactor_stabilized": reactor_stabilized,
		"blocked_routes_cleared": blocked_routes_cleared,
		"extraction_unlocked": extraction_unlocked,
		"power_percent": power_percent,
		"reactor_stability_percent": reactor_stability_percent,
		"completed_sequences": completed_sequences.duplicate(),
		"completed_system_count": completed_sequences.size(),
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Power: %d%%" % power_percent)
	lines.append("Reactor: %d%%" % reactor_stability_percent)
	lines.append("Supplies: %s" % ("OK" if emergency_supplies_recovered else "LOW"))
	lines.append("Main Power: %s" % ("ON" if main_power_restored else "OFF"))
	lines.append("Routes: %s" % ("CLEAR" if blocked_routes_cleared else "BLOCKED"))
	lines.append("Logs: %s" % ("DOWNLOADED" if navigation_logs_downloaded else "PENDING"))
	lines.append("Reactor: %s" % ("STABLE" if reactor_stabilized else "UNSTABLE"))
	lines.append("Extraction: %s" % ("UNLOCKED" if extraction_unlocked else "LOCKED"))
	return lines

func reset() -> void:
	emergency_supplies_recovered = false
	main_power_restored = false
	navigation_logs_downloaded = false
	reactor_stabilized = false
	blocked_routes_cleared = false
	extraction_unlocked = false
	power_percent = INITIAL_POWER_PERCENT
	reactor_stability_percent = INITIAL_REACTOR_STABILITY_PERCENT
	completed_sequences.clear()

## REQ-012: restore this model from a summary dictionary matching
## get_summary()'s shape. Returns true if any field changed. Unknown keys
## are ignored for forward compatibility. The snapshot is the source of
## truth; the live apply_objective() path is not re-invoked.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_emergency: bool = bool(summary.get("emergency_supplies_recovered", emergency_supplies_recovered))
	if new_emergency != emergency_supplies_recovered:
		emergency_supplies_recovered = new_emergency
		changed = true
	var new_power: bool = bool(summary.get("main_power_restored", main_power_restored))
	if new_power != main_power_restored:
		main_power_restored = new_power
		changed = true
	var new_logs: bool = bool(summary.get("navigation_logs_downloaded", navigation_logs_downloaded))
	if new_logs != navigation_logs_downloaded:
		navigation_logs_downloaded = new_logs
		changed = true
	var new_reactor: bool = bool(summary.get("reactor_stabilized", reactor_stabilized))
	if new_reactor != reactor_stabilized:
		reactor_stabilized = new_reactor
		changed = true
	var new_routes: bool = bool(summary.get("blocked_routes_cleared", blocked_routes_cleared))
	if new_routes != blocked_routes_cleared:
		blocked_routes_cleared = new_routes
		changed = true
	var new_extraction: bool = bool(summary.get("extraction_unlocked", extraction_unlocked))
	if new_extraction != extraction_unlocked:
		extraction_unlocked = new_extraction
		changed = true
	var new_power_percent: int = int(summary.get("power_percent", power_percent))
	if new_power_percent != power_percent:
		power_percent = new_power_percent
		changed = true
	var new_reactor_percent: int = int(summary.get("reactor_stability_percent", reactor_stability_percent))
	if new_reactor_percent != reactor_stability_percent:
		reactor_stability_percent = new_reactor_percent
		changed = true
	var new_sequences: Variant = summary.get("completed_sequences", completed_sequences)
	if typeof(new_sequences) == TYPE_ARRAY and (new_sequences as Array) != completed_sequences:
		var arr: Array = new_sequences as Array
		completed_sequences = []
		for seq in arr:
			completed_sequences.append(int(seq))
		changed = true
	return changed