extends RefCounted
class_name SaveIndexState

## On-disk save index (ADR-0031).
##
## Pure data. Lives at `user://saves/index.json`. Lists every slot the
## service has ever written so the menu can render without re-scanning
## disk every refresh. Slot files are the source of truth; the index is
## a cache and a corruption sentinel.

const INDEX_VERSION: String = "save-index-1"

var version: String = INDEX_VERSION
var godot_version: String = ""
var updated_at: String = ""
var slots: Array = []  # Array[SaveSlotState]

# Preloaded script references used by the static methods below. The
# `--headless --script` mode does not always repopulate the class
# registry for cross-file references, so we explicitly preload and
# instantiate via load() to avoid `Nonexistent function 'new' in base
# 'GDScript'` errors on cold caches (CI / fresh checkout).
const _SLOT_STATE_SCRIPT: GDScript = preload("res://scripts/systems/save_slot_state.gd")

func to_dict() -> Dictionary:
	var slot_dicts: Array = []
	for row in slots:
		if row != null and row.has_method("to_dict"):
			slot_dicts.append(row.to_dict())
		elif typeof(row) == TYPE_DICTIONARY:
			slot_dicts.append((row as Dictionary).duplicate(true))
	return {
		"version": version,
		"godot_version": godot_version,
		"updated_at": updated_at,
		"slots": slot_dicts,
	}

static func from_dict(data: Variant) -> SaveIndexState:
	var idx = _SLOT_STATE_SCRIPT.new()  # placeholder; replaced below
	idx = load("res://scripts/systems/save_index_state.gd").new()
	if typeof(data) != TYPE_DICTIONARY:
		return idx
	var dict: Dictionary = data
	idx.version = str(dict.get("version", INDEX_VERSION))
	idx.godot_version = str(dict.get("godot_version", ""))
	idx.updated_at = str(dict.get("updated_at", ""))
	idx.slots = []
	var raw_slots: Variant = dict.get("slots", [])
	if typeof(raw_slots) == TYPE_ARRAY:
		for raw in (raw_slots as Array):
			var row = _SLOT_STATE_SCRIPT.from_dict(raw)
			if _SLOT_STATE_SCRIPT.validate(row):
				idx.slots.append(row)
	return idx

func add_or_replace(row) -> void:
	for i in range(slots.size()):
		var existing = slots[i]
		if existing != null and existing.slot_id == row.slot_id:
			slots[i] = row
			return
	slots.append(row)

func remove(slot_id: String) -> bool:
	for i in range(slots.size()):
		var existing = slots[i]
		if existing != null and existing.slot_id == slot_id:
			slots.remove_at(i)
			return true
	return false

func find(slot_id: String):
	for row in slots:
		if row != null and row.slot_id == slot_id:
			return row
	return null

func sorted_by_saved_at_desc() -> Array:
	var copy_arr: Array = slots.duplicate()
	copy_arr.sort_custom(func(a, b):
		var ea: int = a.saved_at_epoch if a != null else 0
		var eb: int = b.saved_at_epoch if b != null else 0
		return ea > eb
	)
	return copy_arr

## Discards rows whose slot file is no longer present on disk, marks
## them `corrupt=true`. Returns the number of slots reclassified.
func reclassify_corrupt(slot_id_present: Array) -> int:
	var present_set: Dictionary = {}
	for sid in slot_id_present:
		present_set[String(sid)] = true
	var reclassified: int = 0
	for row in slots:
		if row == null:
			continue
		if not present_set.has(row.slot_id) and not row.corrupt:
			row.corrupt = true
			reclassified += 1
	return reclassified