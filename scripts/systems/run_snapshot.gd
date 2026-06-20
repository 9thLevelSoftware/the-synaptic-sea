extends RefCounted
class_name RunSnapshot

## REQ-012 current-run save snapshot.
##
## Pure data class. Holds only current-run state explicitly allowed by
## ADR-0007 (no hub/meta/cross-run fields). Persistence is handled by
## `SaveLoadService`; the snapshot itself is serialization-agnostic.
##
## Per ADR-0007, adding a new field requires a new ADR. Do not add
## hub/meta/unlock/faction/currency state here.

var layout_path: String = ""
var kit_path: String = ""
var gameplay_slice_path: String = ""
var player_position: Array = [0.0, 0.0, 0.0]
var current_objective_sequence: int = 1
var ship_systems_summary: Dictionary = {}
var route_control_summary: Dictionary = {}
var oxygen_summary: Dictionary = {}
var inventory_summary: Dictionary = {}
var fire_summary: Dictionary = {}
var electrical_arc_summary: Dictionary = {}
var objective_progress_summary: Dictionary = {}
var slice_version: String = ""
var godot_version: String = ""
var saved_at: String = ""

# The seven model summaries the snapshot carries. Used by the model
# smoke to assert the round-trip captured every required Gate 2 +
# Alpha hazard model (REQ-013 adds the electrical-arc summary).
const SUMMARY_FIELDS: Array = [
	"ship_systems_summary",
	"route_control_summary",
	"oxygen_summary",
	"inventory_summary",
	"fire_summary",
	"electrical_arc_summary",
	"objective_progress_summary",
]

func get_summary_count() -> int:
	return SUMMARY_FIELDS.size()

func to_dict() -> Dictionary:
	return {
		"layout_path": layout_path,
		"kit_path": kit_path,
		"gameplay_slice_path": gameplay_slice_path,
		"player_position": player_position.duplicate(),
		"current_objective_sequence": current_objective_sequence,
		"ship_systems_summary": ship_systems_summary.duplicate(true),
		"route_control_summary": route_control_summary.duplicate(true),
		"oxygen_summary": oxygen_summary.duplicate(true),
		"inventory_summary": inventory_summary.duplicate(true),
		"fire_summary": fire_summary.duplicate(true),
		"electrical_arc_summary": electrical_arc_summary.duplicate(true),
		"objective_progress_summary": objective_progress_summary.duplicate(true),
		"slice_version": slice_version,
		"godot_version": godot_version,
		"saved_at": saved_at,
	}

## Reconstructs a RunSnapshot from a parsed JSON dictionary.
## Returns null if the data is missing, not a dictionary, or the version
## markers do not match the expected values (per ADR-0007: incompatible
## saves are rejected so a load attempt always starts a fresh run).
static func from_dict(data: Variant, expected_slice_version: String, expected_godot_version: String) -> RunSnapshot:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data as Dictionary
	if dict.is_empty():
		return null
	if str(dict.get("slice_version", "")) != expected_slice_version:
		return null
	if str(dict.get("godot_version", "")) != expected_godot_version:
		return null
	var snapshot := RunSnapshot.new()
	snapshot.layout_path = str(dict.get("layout_path", ""))
	snapshot.kit_path = str(dict.get("kit_path", ""))
	snapshot.gameplay_slice_path = str(dict.get("gameplay_slice_path", ""))
	var pos = dict.get("player_position", [0.0, 0.0, 0.0])
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 3:
		var pos_array: Array = pos as Array
		snapshot.player_position = [float(pos_array[0]), float(pos_array[1]), float(pos_array[2])]
	snapshot.current_objective_sequence = int(dict.get("current_objective_sequence", 1))
	snapshot.ship_systems_summary = _deep_copy_dict(dict.get("ship_systems_summary", {}))
	snapshot.route_control_summary = _deep_copy_dict(dict.get("route_control_summary", {}))
	snapshot.oxygen_summary = _deep_copy_dict(dict.get("oxygen_summary", {}))
	snapshot.inventory_summary = _deep_copy_dict(dict.get("inventory_summary", {}))
	snapshot.fire_summary = _deep_copy_dict(dict.get("fire_summary", {}))
	snapshot.electrical_arc_summary = _deep_copy_dict(dict.get("electrical_arc_summary", {}))
	snapshot.objective_progress_summary = _deep_copy_dict(dict.get("objective_progress_summary", {}))
	snapshot.slice_version = str(dict.get("slice_version", ""))
	snapshot.godot_version = str(dict.get("godot_version", ""))
	snapshot.saved_at = str(dict.get("saved_at", ""))
	return snapshot

static func _deep_copy_dict(src: Variant) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return {}
	return (src as Dictionary).duplicate(true)
