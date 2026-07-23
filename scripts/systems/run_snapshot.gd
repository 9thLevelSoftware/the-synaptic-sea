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
##
## Per ADR-0031 / Task 11: `slot_id`, `slot_kind`, `is_autosave`,
## `is_quicksave`, `parent_world_slot`, and `saved_at_epoch` were added
## so the multi-slot API can stamp every save with stable identity
## without parsing file names. They are pure additive fields; old saves
## that lack them load with empty defaults.
##
## Per ADR-0046 (schema gate2-current-run-4): `play_time_seconds`,
## `current_location`, and `world_seed` carry real slot metadata so
## SaveLoadService._index_run_slot no longer derives placeholders from
## player_position / saved_at_epoch. All three are current-run state
## (no hub/meta scope creep); _migrate_v3_to_v4 defaults them for
## older saves.

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
var player_progression_summary: Dictionary = {}
var skill_tree_summary: Dictionary = {}
var settings_summary: Dictionary = {}
var audio_summary: Dictionary = {}
var spoilage_summary: Dictionary = {}
var hydroponics_summary: Dictionary = {}
var water_recycler_summary: Dictionary = {}
var crafting_summary: Dictionary = {}
var material_summary: Dictionary = {}
var consumable_summary: Dictionary = {}
var medicine_summary: Dictionary = {}
var stimulant_summary: Dictionary = {}
var addiction_summary: Dictionary = {}
var ammo_summary: Dictionary = {}
var utility_summary: Dictionary = {}

# REQ-SV: survival vitals summaries
var vitals_summary: Dictionary = {}
var sanity_summary: Dictionary = {}
var radiation_summary: Dictionary = {}
var temperature_summary: Dictionary = {}
var status_effects_summary: Dictionary = {}
# Session 3 B3 (audit, rides ADR-0046's gate2-current-run-4 bump):
# HallucinationDirector state (ADR-0042) — active events, rng step, tier
# teeth — was never persisted, so saving mid-hallucination silently reset
# the director on load.
var hallucination_summary: Dictionary = {}
# PKG-D8: pre-polish pillar models (empty defaults for historical fixtures).
var module_integrity_summary: Dictionary = {}
var component_placement_summary: Dictionary = {}
var work_action_summary: Dictionary = {}
# PKG-D2.6: hub ship modification install manifest (power budget / plating).
var ship_modification_summary: Dictionary = {}

# ADR-0046: real slot metadata. play_time_seconds is the coordinator's
# accumulated in-run play time (ticked every _process frame on BOTH the
# home and away branches); current_location is the active ship's marker
# id or "home"; world_seed is the Synaptic Sea world seed the run was
# generated from. Stamped by _build_run_snapshot; consumed by
# _index_run_slot for the slot browser.
var play_time_seconds: float = 0.0
var current_location: String = ""
var world_seed: int = 0

var slot_id: String = ""
var slot_kind: String = ""
var is_autosave: bool = false
var is_quicksave: bool = false
# ADR-0043: reserved/unused. Manual-slot loads (the interactive slot
# screen's Load verb, PlayableGeneratedShip.apply_manual_slot) apply the
# RunSnapshot onto the currently-active ship only and never read this
# field -- full world-coherent slot pairing (validating a manual slot
# against a compatible world.json) is explicitly out of scope; see
# ADR-0043 section 4.
var parent_world_slot: String = ""
# run_id slot-ownership rework (ADR-0043 addendum): stamped by
# SaveLoadService on every write with the writing run's identity. Empty
# default so legacy saves (predating this field) load without failing
# validation; SaveLoadService.freeze_run() uses this to find every slot
# a dying run owns instead of the old convention-based lineage flags.
var run_id: String = ""
var slice_version: String = ""
var godot_version: String = ""
var saved_at: String = ""
var saved_at_epoch: int = 0

# The model summaries the snapshot carries. Used by the model
# smoke to assert the round-trip captured every required system.
const SUMMARY_FIELDS: Array = [
	"ship_systems_summary",
	"route_control_summary",
	"oxygen_summary",
	"inventory_summary",
	"fire_summary",
	"electrical_arc_summary",
	"objective_progress_summary",
	"player_progression_summary",
	"skill_tree_summary",
	"settings_summary",
	"audio_summary",
	"spoilage_summary",
	"hydroponics_summary",
	"water_recycler_summary",
	"consumable_summary",
	"medicine_summary",
	"stimulant_summary",
	"addiction_summary",
	"ammo_summary",
	"utility_summary",
	"crafting_summary",
	"material_summary",
	"vitals_summary",
	"sanity_summary",
	"radiation_summary",
	"temperature_summary",
	"status_effects_summary",
	"hallucination_summary",
	"module_integrity_summary",
	"component_placement_summary",
	"work_action_summary",
	"ship_modification_summary",
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
		"player_progression_summary": player_progression_summary.duplicate(true),
		"skill_tree_summary": skill_tree_summary.duplicate(true),
		"settings_summary": settings_summary.duplicate(true),
		"audio_summary": audio_summary.duplicate(true),
		"spoilage_summary": spoilage_summary.duplicate(true),
		"hydroponics_summary": hydroponics_summary.duplicate(true),
		"water_recycler_summary": water_recycler_summary.duplicate(true),
		"crafting_summary": crafting_summary.duplicate(true),
		"material_summary": material_summary.duplicate(true),
		"consumable_summary": consumable_summary.duplicate(true),
		"medicine_summary": medicine_summary.duplicate(true),
		"stimulant_summary": stimulant_summary.duplicate(true),
		"addiction_summary": addiction_summary.duplicate(true),
		"ammo_summary": ammo_summary.duplicate(true),
		"utility_summary": utility_summary.duplicate(true),
		"vitals_summary": vitals_summary.duplicate(true),
		"sanity_summary": sanity_summary.duplicate(true),
		"radiation_summary": radiation_summary.duplicate(true),
		"temperature_summary": temperature_summary.duplicate(true),
		"status_effects_summary": status_effects_summary.duplicate(true),
		"hallucination_summary": hallucination_summary.duplicate(true),
		"module_integrity_summary": module_integrity_summary.duplicate(true),
		"component_placement_summary": component_placement_summary.duplicate(true),
		"work_action_summary": work_action_summary.duplicate(true),
		"ship_modification_summary": ship_modification_summary.duplicate(true),
		"play_time_seconds": play_time_seconds,
		"current_location": current_location,
		"world_seed": world_seed,
		"slot_id": slot_id,
		"slot_kind": slot_kind,
		"is_autosave": is_autosave,
		"is_quicksave": is_quicksave,
		"parent_world_slot": parent_world_slot,
		"run_id": run_id,
		"slice_version": slice_version,
		"godot_version": godot_version,
		"saved_at": saved_at,
		"saved_at_epoch": saved_at_epoch,
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
	snapshot.player_progression_summary = _deep_copy_dict(dict.get("player_progression_summary", {}))
	snapshot.skill_tree_summary = _deep_copy_dict(dict.get("skill_tree_summary", {}))
	snapshot.settings_summary = _deep_copy_dict(dict.get("settings_summary", {}))
	snapshot.audio_summary = _deep_copy_dict(dict.get("audio_summary", {}))
	snapshot.spoilage_summary = _deep_copy_dict(dict.get("spoilage_summary", {}))
	snapshot.hydroponics_summary = _deep_copy_dict(dict.get("hydroponics_summary", {}))
	snapshot.water_recycler_summary = _deep_copy_dict(dict.get("water_recycler_summary", {}))
	snapshot.crafting_summary = _deep_copy_dict(dict.get("crafting_summary", {}))
	snapshot.material_summary = _deep_copy_dict(dict.get("material_summary", {}))
	snapshot.consumable_summary = _deep_copy_dict(dict.get("consumable_summary", {}))
	snapshot.medicine_summary = _deep_copy_dict(dict.get("medicine_summary", {}))
	snapshot.stimulant_summary = _deep_copy_dict(dict.get("stimulant_summary", {}))
	snapshot.addiction_summary = _deep_copy_dict(dict.get("addiction_summary", {}))
	snapshot.ammo_summary = _deep_copy_dict(dict.get("ammo_summary", {}))
	snapshot.utility_summary = _deep_copy_dict(dict.get("utility_summary", {}))
	snapshot.vitals_summary = _deep_copy_dict(dict.get("vitals_summary", {}))
	snapshot.sanity_summary = _deep_copy_dict(dict.get("sanity_summary", {}))
	snapshot.radiation_summary = _deep_copy_dict(dict.get("radiation_summary", {}))
	snapshot.temperature_summary = _deep_copy_dict(dict.get("temperature_summary", {}))
	snapshot.status_effects_summary = _deep_copy_dict(dict.get("status_effects_summary", {}))
	snapshot.hallucination_summary = _deep_copy_dict(dict.get("hallucination_summary", {}))
	snapshot.module_integrity_summary = _deep_copy_dict(dict.get("module_integrity_summary", {}))
	snapshot.component_placement_summary = _deep_copy_dict(dict.get("component_placement_summary", {}))
	snapshot.work_action_summary = _deep_copy_dict(dict.get("work_action_summary", {}))
	snapshot.ship_modification_summary = _deep_copy_dict(dict.get("ship_modification_summary", {}))
	snapshot.play_time_seconds = float(dict.get("play_time_seconds", 0.0))
	snapshot.current_location = str(dict.get("current_location", ""))
	snapshot.world_seed = int(dict.get("world_seed", 0))
	snapshot.slot_id = str(dict.get("slot_id", ""))
	snapshot.slot_kind = str(dict.get("slot_kind", ""))
	snapshot.is_autosave = bool(dict.get("is_autosave", false))
	snapshot.is_quicksave = bool(dict.get("is_quicksave", false))
	snapshot.parent_world_slot = str(dict.get("parent_world_slot", ""))
	snapshot.run_id = str(dict.get("run_id", ""))
	snapshot.slice_version = str(dict.get("slice_version", ""))
	snapshot.godot_version = str(dict.get("godot_version", ""))
	snapshot.saved_at = str(dict.get("saved_at", ""))
	snapshot.saved_at_epoch = int(dict.get("saved_at_epoch", 0))
	return snapshot

static func _deep_copy_dict(src: Variant) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return {}
	return (src as Dictionary).duplicate(true)
