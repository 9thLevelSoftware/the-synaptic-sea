extends Control
class_name InventoryPanel

## Thin view over the System 6 models. Hand-built dark-teal panel matching the HUD.
## Mouse interaction (drag-drop, multi-select, context menus) is layered on top in
## Task 4; every decision delegates to InventorySelectionModel + CargoTransfer, and a
## headless-queryable logical API lets smokes drive the same code paths without input.

signal panel_closed         # emitted on every close() so the coordinator restores control
signal transfer_completed   # emitted after any state mutation so the coordinator recomputes

const InventorySelectionModelScript := preload("res://scripts/systems/inventory_selection_model.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")  # used by TRANSFER mode (next task)
const EncumbranceScript := preload("res://scripts/systems/encumbrance.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const PANEL_COLOR: Color = Color(0.03, 0.05, 0.07, 0.92)
const PANEL_BORDER_COLOR: Color = Color(0.22, 0.72, 1.0, 0.65)

var _mode: String = "closed"        # "closed" | "self" | "transfer"
var _player_inv = null              # InventoryState
var _equip = null                   # EquipmentState
var _container = null               # ShipInventory (TRANSFER mode), else null
var _container_label: String = ""

# Selection models, one per visible list. "self"/"you" share the player list model.
var _sel_self := InventorySelectionModelScript.new()
var _sel_container := InventorySelectionModelScript.new()

var _defs: Dictionary = {}
var _root_label: Label              # single text mirror of the panel for headless query + display

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_defs = ItemDefsScript.load_definitions()
	if _root_label == null:
		var bg := PanelContainer.new()
		bg.position = Vector2(200, 120)
		bg.custom_minimum_size = Vector2(680, 420)
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = PANEL_BORDER_COLOR
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		bg.add_theme_stylebox_override("panel", style)
		add_child(bg)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_top", 14)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_bottom", 14)
		bg.add_child(margin)
		_root_label = Label.new()
		_root_label.add_theme_color_override("font_color", Color.WHITE)
		margin.add_child(_root_label)
	visible = false

# --- lifecycle ---

func open_self(inv, equip) -> void:
	_player_inv = inv
	_equip = equip
	_container = null
	_container_label = ""
	_mode = "self"
	visible = true
	_rebuild_models()
	_render()

func close() -> void:
	_mode = "closed"
	visible = false
	panel_closed.emit()

func is_open() -> bool:
	return _mode != "closed"

func get_mode() -> String:
	return _mode

# --- list/pane access ---

## Ordered item ids in a pane. pane: "self"/"you" = player carry list; "container" = hold.
func _ids_for_pane(pane: String) -> Array:
	if pane == "container":
		return _sorted_ids(_container)
	return _sorted_ids(_player_inv)

func _sorted_ids(inv) -> Array:
	if inv == null:
		return []
	var ids: Array = (inv.items as Dictionary).keys()
	ids.sort()
	var out: Array = []
	for v in ids:
		out.append(String(v))
	return out

func get_pane_ids(pane: String) -> Array:
	return _ids_for_pane(pane)

func _model_for_pane(pane: String):
	return _sel_container if pane == "container" else _sel_self

func _rebuild_models() -> void:
	_sel_self.set_ids(_ids_for_pane("self"))
	_sel_container.set_ids(_ids_for_pane("container"))

func select_row(pane: String, index: int, additive: bool, range_sel: bool) -> void:
	var m = _model_for_pane(pane)
	if range_sel:
		m.select_range_to(index)
	elif additive:
		m.toggle(index)
	else:
		m.select_single(index)
	_render()

func get_selected_ids(pane: String) -> Array:
	return _model_for_pane(pane).get_selected_ids()

# --- equip / unequip (SELF) ---

## Equips the single selected carry-list item into its slot. The item leaves the carry
## list (worn != carried); any displaced occupant returns to the carry list.
func equip_selected() -> bool:
	if _player_inv == null or _equip == null:
		return false
	var sel: Array = _sel_self.get_selected_ids()
	if sel.size() != 1:
		return false
	var item_id: String = String(sel[0])
	if _player_inv.get_quantity(item_id) <= 0 or not _equip.can_equip(item_id):
		return false
	var res: Dictionary = _equip.equip(item_id)
	if not bool(res.get("ok", false)):
		return false
	var displaced: String = str(res.get("displaced", ""))
	if displaced != "":
		if int(_player_inv.add_item(displaced, 1)) < 1:
			# No carry room for the displaced item — abort atomically so nothing is lost.
			# item_id was NOT removed from inventory yet; restore the slot to displaced.
			_equip.equip(displaced)
			return false
	_player_inv.remove_item(item_id, 1)
	_after_mutation()
	return true

func unequip_slot(slot_id: String) -> bool:
	if _player_inv == null or _equip == null:
		return false
	var item_id: String = _equip.unequip(slot_id)
	if item_id == "":
		return false
	if int(_player_inv.add_item(item_id, 1)) < 1:
		# No carry room — restore the worn item rather than destroy it.
		_equip.equip(item_id)
		return false
	_after_mutation()
	return true

# --- encumbrance badge ---

func get_load_badge() -> String:
	if _player_inv == null:
		return "OK"
	var r: float = _player_inv.get_load_ratio()
	if r <= 1.0:
		return "OK"
	if r <= 1.25:
		return "HEAVY"
	return "OVERLOADED"

func _move_speed_mult() -> float:
	if _player_inv == null:
		return 1.0
	return EncumbranceScript.move_speed_multiplier(_player_inv.get_load_ratio())

# --- shared post-mutation hook ---

func _after_mutation() -> void:
	_rebuild_models()
	_render()
	transfer_completed.emit()

# --- rendering (text mirror; the visual pass is the hand-built panel above) ---

func _render() -> void:
	if _root_label == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	if _mode == "self":
		lines.append("INVENTORY + GEAR")
		lines.append(_weight_line())
		lines.append("-- Equipment --")
		for slot in _equip.SLOTS if _equip != null else []:
			var worn: String = _equip.get_equipped(slot) if _equip != null else ""
			lines.append("  %s: %s" % [slot, ("(empty)" if worn == "" else _name(worn))])
		lines.append("-- Carrying --")
		for id in _ids_for_pane("self"):
			lines.append("  %s" % _row_text(_player_inv, id))
	elif _mode == "transfer":
		lines.append("TRANSFER  |  %s" % _container_label)
		lines.append("YOU  %s" % _weight_line())
		for id in _ids_for_pane("self"):
			lines.append("  Y %s" % _row_text(_player_inv, id))
		for id in _ids_for_pane("container"):
			lines.append("  C %s" % _row_text(_container, id))
	_root_label.text = "\n".join(lines)

func _weight_line() -> String:
	if _player_inv == null:
		return ""
	return "Wt %.1f/%.1f [%s] x%.2f" % [
		_player_inv.get_total_weight(), _player_inv.get_capacity(),
		get_load_badge(), _move_speed_mult(),
	]

func _row_text(inv, id: String) -> String:
	return "%s x%d" % [_name(id), int(inv.get_quantity(id))]

func _name(id: String) -> String:
	return ItemDefsScript.display_name(_defs, id)
