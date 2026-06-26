extends RefCounted
class_name SaveSlotState

## One row in the save index (ADR-0031).
##
## Pure data. Carries the metadata the menu / autosave policy / cloud
## adapter need without re-parsing the slot file. The authoritative
## payload lives in the slot file itself (`user://saves/<slot_id>.json`
## or `user://saves/world.json` for the world slot).
##
## Per ADR-0007/0031: a "manual" row never carries `world_summary`; a
## "world" row carries `world_summary` and `visited_ships`.

const SLOT_KIND_MANUAL: String = "manual"
const SLOT_KIND_AUTO: String = "auto"
const SLOT_KIND_QUICK: String = "quick"
const SLOT_KIND_WORLD: String = "world"
const SLOT_KINDS: Array = [SLOT_KIND_MANUAL, SLOT_KIND_AUTO, SLOT_KIND_QUICK, SLOT_KIND_WORLD]

const MANUAL_SLOT_IDS: Array = ["slot_01", "slot_02", "slot_03", "slot_04", "slot_05", "slot_06"]
const AUTOSAVE_SLOT_IDS: Array = ["autosave_a", "autosave_b", "autosave_c"]
const QUICKSAVE_SLOT_ID: String = "quicksave"
const WORLD_SLOT_ID: String = "world"

var slot_id: String = ""
var slot_kind: String = ""
var display_name: String = ""
var synaptic_sea_seed: int = 0
var player_class: String = ""
var current_location: String = ""
var objective_sequence: int = 1
var play_time_seconds: float = 0.0
var saved_at: String = ""              # ISO 8601
var saved_at_epoch: int = 0            # for sort/backup filename
var world_slot_id: String = ""         # non-empty only when this slot is embedded inside a world slot
var corrupt: bool = false
var frozen: bool = false               # permadeath freeze (ADR-0032)
var payload_size_bytes: int = 0
var schema_version: String = ""

func is_world() -> bool:
	return slot_kind == SLOT_KIND_WORLD

func is_manual() -> bool:
	return slot_kind == SLOT_KIND_MANUAL

func is_auto() -> bool:
	return slot_kind == SLOT_KIND_AUTO

func is_quick() -> bool:
	return slot_kind == SLOT_KIND_QUICK

func to_dict() -> Dictionary:
	return {
		"slot_id": slot_id,
		"slot_kind": slot_kind,
		"display_name": display_name,
		"synaptic_sea_seed": synaptic_sea_seed,
		"player_class": player_class,
		"current_location": current_location,
		"objective_sequence": objective_sequence,
		"play_time_seconds": play_time_seconds,
		"saved_at": saved_at,
		"saved_at_epoch": saved_at_epoch,
		"world_slot_id": world_slot_id,
		"corrupt": corrupt,
		"frozen": frozen,
		"payload_size_bytes": payload_size_bytes,
		"schema_version": schema_version,
	}

static func from_dict(data: Variant) -> SaveSlotState:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data
	var script: GDScript = load("res://scripts/systems/save_slot_state.gd")
	var row: SaveSlotState = script.new()
	row.slot_id = str(dict.get("slot_id", ""))
	row.slot_kind = str(dict.get("slot_kind", ""))
	row.display_name = str(dict.get("display_name", ""))
	row.synaptic_sea_seed = int(dict.get("synaptic_sea_seed", 0))
	row.player_class = str(dict.get("player_class", ""))
	row.current_location = str(dict.get("current_location", ""))
	row.objective_sequence = int(dict.get("objective_sequence", 1))
	row.play_time_seconds = float(dict.get("play_time_seconds", 0.0))
	row.saved_at = str(dict.get("saved_at", ""))
	row.saved_at_epoch = int(dict.get("saved_at_epoch", 0))
	row.world_slot_id = str(dict.get("world_slot_id", ""))
	row.corrupt = bool(dict.get("corrupt", false))
	row.frozen = bool(dict.get("frozen", false))
	row.payload_size_bytes = int(dict.get("payload_size_bytes", 0))
	row.schema_version = str(dict.get("schema_version", ""))
	return row

## Coarse validation: rejects empty slot_id or unknown slot_kind. Used by
## the index loader to filter malformed rows without crashing.
static func validate(row: SaveSlotState) -> bool:
	if row == null:
		return false
	if row.slot_id.is_empty():
		return false
	if not SLOT_KINDS.has(row.slot_kind):
		return false
	return true