extends RefCounted
class_name HangarBay

## Per-ship hangar bay: fixed slots that store other ships. Pure data (no scene
## tree). Slot occupancy is the source of truth for what a carrier holds; the
## coordinator owns the physical placement and the dock-graph edges. Persisted as
## a ship-summary sub-dict under "hangar". class_name is declared for tooling;
## headless callers preload + create().

var slot_count: int = 0
var slot_size_class: int = 0
var slots: Array[String] = []   # length == slot_count; "" = empty, else a bayed ship_id

static func create(p_slot_count: int, p_slot_size_class: int) -> HangarBay:
	var script: GDScript = load("res://scripts/systems/hangar_bay.gd")
	var b = script.new()
	b.slot_count = max(0, p_slot_count)
	b.slot_size_class = max(0, p_slot_size_class)
	b.slots.clear()
	for _i in range(b.slot_count):
		b.slots.append("")
	return b

## First empty slot index for a ship of `size_class`, or -1 (too large / bay full).
func free_slot_for(size_class: int) -> int:
	if size_class > slot_size_class:
		return -1
	for i in range(slots.size()):
		if slots[i] == "":
			return i
	return -1

## Bays `ship_id` in the first fitting free slot. Returns the slot index, or -1
## if the ship is already bayed here, the id is empty, or nothing fits.
func dock(ship_id: String, size_class: int) -> int:
	if ship_id == "" or slot_of(ship_id) != -1:
		return -1
	var idx := free_slot_for(size_class)
	if idx == -1:
		return -1
	slots[idx] = ship_id
	return idx

## Empties `slot_index`, returning the ship_id it held (or "" if empty / out of range).
func launch(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= slots.size():
		return ""
	var id: String = slots[slot_index]
	slots[slot_index] = ""
	return id

func slot_of(ship_id: String) -> int:
	if ship_id == "":
		return -1
	return slots.find(ship_id)

func is_full() -> bool:
	return not slots.has("")

func get_summary() -> Dictionary:
	return {"slot_count": slot_count, "slot_size_class": slot_size_class, "slots": slots.duplicate()}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = summary
	slot_count = int(d.get("slot_count", 0))
	slot_size_class = int(d.get("slot_size_class", 0))
	slots.clear()   # preserve the Array[String] static type (vs. reassigning to untyped [])
	var raw: Variant = d.get("slots", [])
	if typeof(raw) == TYPE_ARRAY:
		for s in (raw as Array):
			slots.append(String(s))
	# Normalize length to slot_count so a corrupted/short array cannot desync.
	while slots.size() < slot_count:
		slots.append("")
	if slots.size() > slot_count:
		slots.resize(slot_count)
	return true
