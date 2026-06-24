extends RefCounted
class_name InventorySelectionModel

## Pure per-list selection state for the inventory UI + a static context-action
## resolver. No scene-tree access. The view (inventory_panel.gd) owns one of these per
## visible list and asks it what is selected and which menu actions apply.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

var ids: Array[String] = []        # ordered item ids currently shown in this list
var _selected: Dictionary = {}     # index:int -> true
var _anchor: int = -1

## Replace the ordered id list; drop any selection/anchor now out of range.
func set_ids(p_ids: Array) -> void:
	ids = []
	for v in p_ids:
		ids.append(String(v))
	var keep: Dictionary = {}
	for idx in _selected:
		if int(idx) >= 0 and int(idx) < ids.size():
			keep[int(idx)] = true
	_selected = keep
	if _anchor >= ids.size():
		_anchor = -1

func clear() -> void:
	_selected.clear()
	_anchor = -1

## Plain click: select exactly one and set the range anchor.
func select_single(index: int) -> void:
	_selected.clear()
	if index >= 0 and index < ids.size():
		_selected[index] = true
		_anchor = index

## Ctrl-click: add/remove one; the anchor follows the click.
func toggle(index: int) -> void:
	if index < 0 or index >= ids.size():
		return
	if _selected.has(index):
		_selected.erase(index)
	else:
		_selected[index] = true
	_anchor = index

## Shift-click: select the contiguous block from the anchor to index.
func select_range_to(index: int) -> void:
	if index < 0 or index >= ids.size():
		return
	if _anchor < 0:
		select_single(index)
		return
	_selected.clear()
	var lo: int = min(_anchor, index)
	var hi: int = max(_anchor, index)
	for i in range(lo, hi + 1):
		_selected[i] = true

func is_selected(index: int) -> bool:
	return _selected.has(index)

func get_selected_indices() -> Array[int]:
	var out: Array[int] = []
	for k in _selected:
		out.append(int(k))
	out.sort()
	return out

func get_selected_ids() -> Array:
	var out: Array = []
	for i in get_selected_indices():
		out.append(ids[int(i)])
	return out

## Resolve the right-click menu action set for one row. `dest_is_container` is accepted
## for forward-compat (deposit vs withdraw labelling) but does not branch behaviour yet.
static func context_actions(item_id: String, defs: Dictionary, in_transfer_mode: bool, dest_is_container: bool, is_equipped_slot: bool) -> PackedStringArray:
	var actions: PackedStringArray = PackedStringArray()
	if is_equipped_slot:
		actions.append("unequip")
		return actions
	var equippable: bool = not ItemDefsScript.equip_slot(defs, item_id).is_empty()
	if in_transfer_mode:
		actions.append("transfer")
		actions.append("transfer_all")
		actions.append("split")
		if equippable:
			actions.append("equip")
	elif equippable:
		actions.append("equip")
	return actions
