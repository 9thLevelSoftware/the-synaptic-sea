extends RefCounted
class_name RunSnapshot

const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")
const ThreatSaveContractScript := preload("res://scripts/systems/threat_save_contract.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const MAX_SAFE_JSON_INTEGER: float = 9007199254740991.0

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
var crafting_summary: Dictionary = {
	"recipe_count": 0,
	"active_craft": {},
	"station_summaries": {},
	"physical_station_summaries": {},
	"physical_station_positions_v1": {"schema": "physical-station-positions-1", "owners": []},
	"craft_jobs_v1": {"schema": "craft-jobs-2", "jobs": [], "owners": []},
	"field_crafting": {
		"recipe_count": 0,
		"active_craft": {},
		"station_summaries": {},
		"physical_station_summaries": {},
		"craft_jobs_v1": {"schema": "craft-jobs-2", "jobs": [], "owners": []},
		"field_pending_v1": {
			"schema": "field-pending-2",
			"ship_id": "", "receipt_sequence": 0, "active_receipt_id": "",
			"pinned_destination_ship_id": "", "pinned_local_position": [],
			"receipt_history_v1": [],
		},
	},
}
var recipe_knowledge_summary: Dictionary = {
	"schema": "recipe-knowledge-1",
	"owner_id": "",
	"known_recipe_ids": [],
	"event_receipt_ids": [],
	"event_sequence": 0,
	"dismantle_counts": {},
	"migration_origin": "native",
}
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
# PKG-D8: pre-polish pillar models (empty defaults for historical fixtures).
var module_integrity_summary: Dictionary = {}
var component_placement_summary: Dictionary = {
	"schema": "component_placement_v2",
	"condition_authority_version": 1,
	"condition_lot_sequence": 0,
	"seed": 0,
	"count": 0,
	"placed": [],
	"rejected_saved_components": [],
}
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
	"recipe_knowledge_summary",
	"material_summary",
	"vitals_summary",
	"sanity_summary",
	"radiation_summary",
	"temperature_summary",
	"status_effects_summary",
	"module_integrity_summary",
	"component_placement_summary",
	"work_action_summary",
	"ship_modification_summary",
]

func get_summary_count() -> int:
	# Kept as the established core-system metric used by pre-v5 validation.
	# recipe_knowledge_summary is an additive transaction owner, not a second
	# runtime system row in that historical count.
	return SUMMARY_FIELDS.size() - 1

func to_dict() -> Dictionary:
	return {
		"layout_path": layout_path,
		"kit_path": kit_path,
		"gameplay_slice_path": gameplay_slice_path,
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
		"recipe_knowledge_summary": recipe_knowledge_summary.duplicate(true),
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
	if expected_slice_version == "gate2-current-run-7" \
			and (dict.has("player_position") or dict.has("hallucination_summary")):
		return null
	if expected_slice_version == "gate2-current-run-7" \
			and dict.has("module_integrity_summary"):
		var integrity_admission: Dictionary = ModuleIntegrityMapScript \
			.validate_current_summary(dict.module_integrity_summary)
		if not bool(integrity_admission.get("ok", false)):
			return null
	if expected_slice_version in [
		"gate2-current-run-5", "gate2-current-run-6", "gate2-current-run-7",
	]:
		# Modern v5 never turns an omitted transaction into an empty one. Empty
		# state is represented by the complete schema envelopes emitted above.
		for required_summary in [
			"inventory_summary", "crafting_summary", "recipe_knowledge_summary",
			"component_placement_summary",
		]:
			if not dict.has(required_summary) or not dict[required_summary] is Dictionary \
					or (dict[required_summary] as Dictionary).is_empty():
				return null
		if not _is_structural_v5_crafting(dict.crafting_summary as Dictionary) \
				or not _is_structural_v5_knowledge(dict.recipe_knowledge_summary as Dictionary) \
				or not _is_structural_v5_component(dict.component_placement_summary as Dictionary) \
				or not _is_structural_v5_oxygen(dict.get("oxygen_summary", {})):
			return null
	if expected_slice_version in ["gate2-current-run-6", "gate2-current-run-7"]:
		var inventory: Dictionary = dict.inventory_summary as Dictionary
		if not inventory.has("threat_summary"):
			return null
		var combat_result: Dictionary = ThreatSaveContractScript.validate_current(
			inventory.get("threat_summary", null))
		if not bool(combat_result.get("ok", false)):
			return null
		if not inventory.has("combat_hotbar_text") \
				or typeof(inventory.combat_hotbar_text) != TYPE_STRING:
			return null
	var snapshot := RunSnapshot.new()
	snapshot.layout_path = str(dict.get("layout_path", ""))
	snapshot.kit_path = str(dict.get("kit_path", ""))
	snapshot.gameplay_slice_path = str(dict.get("gameplay_slice_path", ""))
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
	snapshot.recipe_knowledge_summary = _deep_copy_dict(dict.get("recipe_knowledge_summary", {}))
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


static func _is_structural_v5_crafting(summary: Dictionary) -> bool:
	var current_keys: Array[String] = [
		"recipe_count", "active_craft", "station_summaries",
		"physical_station_summaries", "physical_station_positions_v1",
		"craft_jobs_v1", "field_crafting",
	]
	for key in current_keys:
		if not summary.has(key):
			return false
	if not summary.active_craft is Dictionary or not summary.station_summaries is Dictionary \
			or not summary.physical_station_summaries is Dictionary \
			or not _is_structural_station_positions(summary.physical_station_positions_v1) \
			or not summary.craft_jobs_v1 is Dictionary or not summary.field_crafting is Dictionary:
		return false
	var jobs: Dictionary = summary.craft_jobs_v1
	if str(jobs.get("schema", "")) != "craft-jobs-2" \
			or not jobs.get("jobs", null) is Array or not jobs.get("owners", null) is Array:
		return false
	for job_v in jobs.jobs as Array:
		if not job_v is Dictionary \
				or not (job_v as Dictionary).get("refunded_lots_v1", null) is Array \
				or typeof((job_v as Dictionary).get(
					"legacy_unreserved_cancelled_v1", null)) != TYPE_BOOL \
				or typeof((job_v as Dictionary).get(
					"legacy_unrecorded_cancelled_v1", null)) != TYPE_BOOL:
			return false
	var field: Dictionary = summary.field_crafting
	for key in [
		"recipe_count", "active_craft", "station_summaries",
		"physical_station_summaries", "craft_jobs_v1", "field_pending_v1",
	]:
		if not field.has(key):
			return false
	if not field.active_craft is Dictionary or not field.station_summaries is Dictionary \
			or not field.physical_station_summaries is Dictionary \
			or not field.craft_jobs_v1 is Dictionary or not field.field_pending_v1 is Dictionary:
		return false
	var field_jobs: Dictionary = field.craft_jobs_v1
	if str(field_jobs.get("schema", "")) != "craft-jobs-2" \
			or not field_jobs.get("jobs", null) is Array \
			or not field_jobs.get("owners", null) is Array:
		return false
	for job_v in field_jobs.jobs as Array:
		if not job_v is Dictionary \
				or not (job_v as Dictionary).get("refunded_lots_v1", null) is Array \
				or typeof((job_v as Dictionary).get(
					"legacy_unreserved_cancelled_v1", null)) != TYPE_BOOL \
				or typeof((job_v as Dictionary).get(
					"legacy_unrecorded_cancelled_v1", null)) != TYPE_BOOL:
			return false
	var pending: Dictionary = field.field_pending_v1
	if typeof(pending.get("schema", null)) != TYPE_STRING \
			or str(pending.get("schema", "")) != "field-pending-2" \
			or typeof(pending.get("ship_id", null)) != TYPE_STRING \
			or not _is_nonnegative_json_integer(pending.get("receipt_sequence", null)) \
			or typeof(pending.get("active_receipt_id", null)) != TYPE_STRING \
			or typeof(pending.get("pinned_destination_ship_id", null)) != TYPE_STRING \
			or not pending.get("pinned_local_position", null) is Array \
			or not pending.get("receipt_history_v1", null) is Array:
		return false
	var pinned_ship: String = str(pending.pinned_destination_ship_id)
	var pinned_position: Array = pending.pinned_local_position
	if pinned_ship.is_empty():
		return pinned_position.is_empty()
	if str(pending.active_receipt_id).is_empty() or pinned_ship != str(pending.ship_id) \
			or pinned_position.size() != 3:
		return false
	for coordinate in pinned_position:
		if not _is_finite_number(coordinate):
			return false
	return true


static func _is_structural_station_positions(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var summary: Dictionary = value
	if str(summary.get("schema", "")) != "physical-station-positions-1" \
			or not summary.get("owners", null) is Array:
		return false
	var seen_owners: Dictionary = {}
	var seen_station_ids: Dictionary = {}
	for owner_v in summary.owners as Array:
		if not owner_v is Dictionary:
			return false
		var owner: Dictionary = owner_v
		var ship_id: String = str(owner.get("ship_id", ""))
		if ship_id.is_empty() or seen_owners.has(ship_id) \
				or not owner.get("stations", null) is Array:
			return false
		seen_owners[ship_id] = true
		var seen_local_positions: Dictionary = {}
		for station_v in owner.stations as Array:
			if not station_v is Dictionary:
				return false
			var station: Dictionary = station_v
			var kind: String = str(station.get("station_kind", ""))
			var station_id: String = str(station.get("station_instance_id", ""))
			var floor_slot_id: String = str(station.get("floor_slot_id", ""))
			var local_v: Variant = station.get("local_position", null)
			var owner_station_key: String = "%s\n%s" % [ship_id, station_id]
			if kind.is_empty() or station_id.is_empty() or floor_slot_id.is_empty() \
					or seen_station_ids.has(owner_station_key) \
					or not local_v is Array or (local_v as Array).size() != 3:
				return false
			for coordinate in local_v as Array:
				if (typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT) \
						or not is_finite(float(coordinate)):
					return false
			var local_key: String = "%d,%d,%d" % [
				roundi(float(local_v[0]) * 1000.0),
				roundi(float(local_v[1]) * 1000.0),
				roundi(float(local_v[2]) * 1000.0),
			]
			if seen_local_positions.has(local_key) \
					or floor_slot_id != "floor@%s" % local_key \
					or station_id != "station:%s@%s" % [kind, local_key]:
				return false
			seen_station_ids[owner_station_key] = true
			seen_local_positions[local_key] = true
	return true


static func _is_structural_v5_knowledge(summary: Dictionary) -> bool:
	for key in [
		"schema", "owner_id", "known_recipe_ids", "event_receipt_ids",
		"event_sequence", "dismantle_counts", "migration_origin",
	]:
		if not summary.has(key):
			return false
	if not (typeof(summary.schema) == TYPE_STRING \
		and str(summary.schema) == "recipe-knowledge-1" \
		and typeof(summary.owner_id) == TYPE_STRING \
		and summary.known_recipe_ids is Array \
		and summary.event_receipt_ids is Array \
		and summary.dismantle_counts is Dictionary \
		and typeof(summary.migration_origin) == TYPE_STRING \
		and ["native", "legacy_unrecorded"].has(str(summary.migration_origin)) \
		and _is_nonnegative_json_integer(summary.event_sequence)):
		return false
	if str(summary.migration_origin) == "native" and str(summary.owner_id).is_empty():
		return false
	if str(summary.migration_origin) == "legacy_unrecorded" \
			and (not (summary.event_receipt_ids as Array).is_empty() \
			or int(summary.event_sequence) != 0 \
			or not (summary.dismantle_counts as Dictionary).is_empty()):
		return false
	if not _unique_nonempty_strings(summary.known_recipe_ids) \
			or not _unique_nonempty_strings(summary.event_receipt_ids):
		return false
	for component_id_variant in summary.dismantle_counts as Dictionary:
		if typeof(component_id_variant) != TYPE_STRING or str(component_id_variant).is_empty() \
				or not _is_nonnegative_json_integer(summary.dismantle_counts[component_id_variant]):
			return false
	return true


static func _is_structural_v5_component(summary: Dictionary) -> bool:
	if not (typeof(summary.get("schema", null)) == TYPE_STRING \
		and str(summary.schema) == "component_placement_v2" \
		and _is_nonnegative_json_integer(summary.get("condition_authority_version", null)) \
		and int(summary.condition_authority_version) == 1 \
		and _is_nonnegative_json_integer(summary.get("condition_lot_sequence", null)) \
		and summary.get("placed", null) is Array \
		and summary.get("rejected_saved_components", null) is Array \
		and _is_json_integer(summary.get("seed", null)) \
		and _is_nonnegative_json_integer(summary.get("count", null)) \
		and int(summary.count) == (summary.placed as Array).size()):
		return false
	var seen: Dictionary = {}
	var seen_lots: Dictionary = {}
	for entry_variant in summary.placed as Array:
		if not entry_variant is Dictionary:
			return false
		var entry: Dictionary = entry_variant
		var instance_id: String = str(entry.get("component_instance_id", ""))
		if not entry.has("mounted") or typeof(entry.mounted) != TYPE_BOOL \
				or instance_id.is_empty() or seen.has(instance_id) \
				or not entry.get("source_lot", null) is Dictionary:
			return false
		seen[instance_id] = true
		if entry.has("source_lot") and not _is_component_source_lot(
				entry.source_lot, str(entry.get("item_form", ""))):
			return false
		var lot_id: String = str((entry.source_lot as Dictionary).get("lot_id", ""))
		# Unmounted rows retain immutable placement history. Only mounted rows own
		# the physical lot and therefore participate in uniqueness authority.
		if entry.mounted:
			if seen_lots.has(lot_id):
				return false
			seen_lots[lot_id] = true
	return true


static func _is_structural_v5_oxygen(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var summary: Dictionary = value
	# The overlap flag is accepted for compatibility with existing v5 saves, but
	# remains strictly typed before the restore comparison classifies it as a
	# scene-derived projection rather than durable oxygen authority.
	return not summary.has("player_in_breach_zone") \
		or typeof(summary.player_in_breach_zone) == TYPE_BOOL


static func _is_component_source_lot(value: Variant, expected_item: String) -> bool:
	if not value is Dictionary or (value as Dictionary).is_empty():
		return false
	var lot: Dictionary = value
	for key in ["lot_id", "item_id", "quantity", "quality_score", "quality_tier", "condition", "origin"]:
		if not lot.has(key):
			return false
	var item_id: String = str(lot.item_id)
	var score: float = float(lot.quality_score) if _is_finite_number(lot.quality_score) else -1.0
	var condition: float = float(lot.condition) if _is_finite_number(lot.condition) else -1.0
	var lot_id: String = str(lot.lot_id)
	var origin: Dictionary = lot.origin as Dictionary
	var origin_kind: String = str(origin.get("kind", ""))
	var reserved_component_namespace: bool = lot_id.begins_with("ship:") \
		and lot_id.find(":components/lot-") >= 0
	if reserved_component_namespace:
		if origin_kind not in ["generated_component", "legacy_unrecorded_component"]:
			return false
		var origin_ship_id: String = str(origin.get("ship_id", ""))
		if origin_ship_id.is_empty() or str(origin.get("slot_id", "")).is_empty() \
				or not lot_id.begins_with("ship:%s:components/lot-" % origin_ship_id):
			return false
		if origin_kind == "generated_component" \
				and not _is_json_integer(origin.get("placement_seed", null)):
			return false
	return typeof(lot.lot_id) == TYPE_STRING and not lot_id.is_empty() \
		and typeof(lot.item_id) == TYPE_STRING and not item_id.is_empty() \
		and (expected_item.is_empty() or item_id == expected_item) \
		and _is_nonnegative_json_integer(lot.quantity) and int(lot.quantity) == 1 \
		and score >= 0.0 and score <= 1.0 and condition >= 0.0 and condition <= 1.0 \
		and typeof(lot.quality_tier) == TYPE_STRING \
		and str(lot.quality_tier) == QualityTierResolverScript.tier_for_score(score) \
		and lot.origin is Dictionary


static func _unique_nonempty_strings(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if typeof(value) != TYPE_STRING or str(value).is_empty() or seen.has(str(value)):
			return false
		seen[str(value)] = true
	return true


static func _is_nonnegative_json_integer(value: Variant) -> bool:
	return _is_json_integer(value) and float(value) >= 0.0


static func _is_json_integer(value: Variant) -> bool:
	return _is_finite_number(value) and absf(float(value)) <= MAX_SAFE_JSON_INTEGER \
		and float(value) == floor(float(value))


static func _is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) \
		and is_finite(float(value))

static func _deep_copy_dict(src: Variant) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return {}
	return (src as Dictionary).duplicate(true)
