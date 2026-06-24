extends Control
class_name InventoryPanel

## Thin view over the System 6 models. Hand-built dark-teal panel matching the HUD.
## Every decision delegates to InventorySelectionModel + CargoTransfer, and a
## headless-queryable logical API lets smokes drive the same code paths without input.
## The panel builds a real widget tree of InventoryRow + InventoryDropZone controls so
## mouse drag/select is driven by real per-row mouse input as well as the logical API.

signal panel_closed         # emitted on every close() so the coordinator restores control
signal transfer_completed   # emitted after any state mutation so the coordinator recomputes

const InventorySelectionModelScript := preload("res://scripts/systems/inventory_selection_model.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")  # used by TRANSFER mode
const EncumbranceScript := preload("res://scripts/systems/encumbrance.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const InventoryRowScript := preload("res://scripts/ui/inventory_row.gd")
const InventoryDropZoneScript := preload("res://scripts/ui/inventory_drop_zone.gd")

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

var _content: VBoxContainer
var _rows: Dictionary = {"self": [], "container": []}   # pane -> Array[InventoryRow]
var _zones: Dictionary = {}                             # target -> InventoryDropZone

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_defs = ItemDefsScript.load_definitions()
	if not is_instance_valid(_content):
		var bg := PanelContainer.new()
		bg.position = Vector2(200, 120)
		bg.custom_minimum_size = Vector2(700, 440)
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = PANEL_BORDER_COLOR
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		bg.add_theme_stylebox_override("panel", style)
		add_child(bg)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 12)
		bg.add_child(margin)
		_content = VBoxContainer.new()
		margin.add_child(_content)
	visible = false

# --- lifecycle ---

func open_self(inv, equip) -> void:
	assert(inv != null, "InventoryState dependency must not be null")
	assert(equip != null, "EquipmentState dependency must not be null")
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

func open_transfer(player_inv, container_hold, container_label: String, equip) -> void:
	assert(player_inv != null, "Player inventory dependency must not be null")
	assert(container_hold != null, "Container hold dependency must not be null")
	_player_inv = player_inv
	_container = container_hold
	_container_label = container_label
	_equip = equip
	_mode = "transfer"
	visible = true
	_rebuild_models()
	_render()

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
	# Emit BEFORE rendering: the coordinator updates inventory_state.bonus_capacity from
	# worn gear inside the transfer_completed handler, so the weight line / Heavy-Load badge
	# must render with the post-recompute capacity (equipping a capacity bag changes it).
	_rebuild_models()
	transfer_completed.emit()
	_render()

# --- interactive-widget coordinator callbacks (rows/zones forward here) ---

const _ACT_TRANSFER := 0
const _ACT_TRANSFER_ALL := 1
const _ACT_SPLIT := 2
const _ACT_EQUIP := 3
const _ACT_UNEQUIP := 4

func row_clicked(pane: String, index: int, additive: bool, range_sel: bool) -> void:
	select_row(pane, index, additive, range_sel)

func row_drag_payload(pane: String, index: int) -> Variant:
	var m = _model_for_pane(pane)
	if not m.is_selected(index):
		m.select_single(index)
	var data: Dictionary = _build_drag_payload(pane)
	return null if (data["ids"] as Array).is_empty() else data

func row_context(pane: String, index: int, global_pos: Vector2) -> void:
	var m = _model_for_pane(pane)
	if not m.is_selected(index):
		m.select_single(index)
		_render()
	var menu: PopupMenu = _build_context_menu(pane, index)
	add_child(menu)
	menu.position = global_pos
	menu.id_pressed.connect(_on_context_id.bind(pane, index, menu))
	menu.popup()

## True iff `data` can drop on `target` ("self"/"container" pane, or "slot:<id>").
func zone_can_accept(target: String, data) -> bool:
	if not (data is Dictionary):
		return false
	var from_pane: String = String((data as Dictionary).get("from_pane", ""))
	if target.begins_with("slot:"):
		if from_pane != "self":
			return false   # equip only from your own inventory
		var slot: String = target.substr(5)
		for id in ((data as Dictionary).get("ids", []) as Array):
			if _equip != null and ItemDefsScript.equip_slot(_defs, String(id)) == slot:
				return true
		return false
	return _mode == "transfer" and target != from_pane

func zone_drop(target: String, data) -> void:
	if not (data is Dictionary):
		return
	var from_pane: String = String((data as Dictionary).get("from_pane", ""))
	if target.begins_with("slot:"):
		if from_pane != "self":
			return
		var slot: String = target.substr(5)
		for id in ((data as Dictionary).get("ids", []) as Array):
			if _equip != null and ItemDefsScript.equip_slot(_defs, String(id)) == slot:
				_sel_self.select_single(_ids_for_pane("self").find(String(id)))
				equip_selected()
				return
		return
	if _mode == "transfer" and target != from_pane and (from_pane == "self" or from_pane == "container"):
		transfer_selected(from_pane)

## Move every id in `pane` to the other pane (manual — includes tools). Distinct from the
## Deposit All button, which uses deposit_all (parts/supplies only). Returns total moved.
func transfer_all_from(pane: String) -> int:
	var src = _inv_for_pane(pane)
	var dst = _inv_for_pane(_other_pane(pane))
	if src == null or dst == null:
		return 0
	var id_to_qty: Dictionary = {}
	for id in _ids_for_pane(pane):
		id_to_qty[String(id)] = int(src.get_quantity(String(id)))
	var moved: int = CargoTransferScript.move_items(src, dst, id_to_qty)
	if moved > 0:
		_after_mutation()
	return moved

func slot_context(slot_id: String, global_pos: Vector2) -> void:
	if _equip == null or not _equip.is_slot_occupied(slot_id):
		return
	var menu := PopupMenu.new()
	menu.add_item("Unequip", _ACT_UNEQUIP)
	add_child(menu)
	menu.position = global_pos
	menu.id_pressed.connect(func(_id): unequip_slot(slot_id); menu.queue_free())
	menu.popup()

func pane_quantity(pane: String, id: String) -> int:
	var inv = _inv_for_pane(pane)
	return int(inv.get_quantity(id)) if inv != null else 0

## Builds (does NOT pop) the right-click menu for a row, from context_actions.
func _build_context_menu(pane: String, index: int) -> PopupMenu:
	var menu := PopupMenu.new()
	var ids: Array = _ids_for_pane(pane)
	if index < 0 or index >= ids.size():
		return menu
	var item_id: String = String(ids[index])
	var actions: PackedStringArray = InventorySelectionModelScript.context_actions(
		item_id, _defs, _mode == "transfer", pane == "container", false)
	for a in actions:
		match String(a):
			"transfer": menu.add_item("Transfer", _ACT_TRANSFER)
			"transfer_all": menu.add_item("Transfer all", _ACT_TRANSFER_ALL)
			"split": menu.add_item("Split…", _ACT_SPLIT)
			"equip": menu.add_item("Equip", _ACT_EQUIP)
			"unequip": menu.add_item("Unequip", _ACT_UNEQUIP)
	return menu

func _on_context_id(id: int, pane: String, index: int, menu) -> void:
	if id == _ACT_TRANSFER:
		transfer_selected(pane)
	elif id == _ACT_TRANSFER_ALL:
		transfer_all_from(pane)
	elif id == _ACT_SPLIT:
		var ids: Array = _ids_for_pane(pane)
		var item_id: String = String(ids[index]) if index >= 0 and index < ids.size() else ""
		_open_split_picker(pane, item_id)
	elif id == _ACT_EQUIP:
		_model_for_pane(pane).select_single(index)
		equip_selected()
	if is_instance_valid(menu):
		menu.queue_free()

## Interaction-only (popup); split amount picker -> transfer_quantity.
func _open_split_picker(pane: String, item_id: String) -> void:
	var src = _inv_for_pane(pane)
	if src == null or item_id == "":
		return
	var maxq: int = int(src.get_quantity(item_id))
	if maxq <= 0:
		return
	var dlg := AcceptDialog.new()
	dlg.title = "Split %s" % _name(item_id)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = maxq
	spin.value = max(1, int(maxq / 2.0))
	dlg.add_child(spin)
	add_child(dlg)
	dlg.confirmed.connect(func(): transfer_quantity(pane, item_id, int(spin.value)); dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()

# --- transfer (TRANSFER mode) ---

func _other_pane(pane: String) -> String:
	return "container" if pane == "self" or pane == "you" else "self"

func _inv_for_pane(pane: String):
	return _container if pane == "container" else _player_inv

## Move every selected whole stack from from_pane to the other pane. Returns total moved.
func transfer_selected(from_pane: String) -> int:
	if _mode != "transfer":
		return 0
	var src = _inv_for_pane(from_pane)
	var dst = _inv_for_pane(_other_pane(from_pane))
	if src == null or dst == null:
		return 0
	var id_to_qty: Dictionary = {}
	for id in _model_for_pane(from_pane).get_selected_ids():
		id_to_qty[String(id)] = int(src.get_quantity(String(id)))
	var moved: int = CargoTransferScript.move_items(src, dst, id_to_qty)
	if moved > 0:
		_after_mutation()
	return moved

## Split: move exactly qty of one id from from_pane to the other pane.
func transfer_quantity(from_pane: String, item_id: String, qty: int) -> int:
	if _mode != "transfer":
		return 0
	var src = _inv_for_pane(from_pane)
	var dst = _inv_for_pane(_other_pane(from_pane))
	if src == null or dst == null:
		return 0
	var moved: int = CargoTransferScript.move_item(src, dst, item_id, qty)
	if moved > 0:
		_after_mutation()
	return moved

## "A" convenience: bulk deposit part+supply (tools excluded) into the container.
func deposit_all_to_container() -> int:
	if _mode != "transfer" or _player_inv == null or _container == null:
		return 0
	var moved: int = int(CargoTransferScript.deposit_all(_player_inv, _container).get("total_moved", 0))
	if moved > 0:
		_after_mutation()
	return moved

# --- drag payload (kept: smokes call this directly) ---

## The drag payload the mouse path and the smokes both use.
func _build_drag_payload(pane: String) -> Dictionary:
	return {"from_pane": pane, "ids": _model_for_pane(pane).get_selected_ids()}

# --- rendering (widget-tree rebuild) ---

func _render() -> void:
	if not is_instance_valid(_content):
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_rows = {"self": [], "container": []}
	_zones = {}
	if _mode == "self":
		_content.add_child(_make_header())
		_content.add_child(_make_equipment_section())
		_content.add_child(_make_pane_section("self", "-- Carrying --"))
	elif _mode == "transfer":
		_content.add_child(_make_header())
		_content.add_child(_make_equipment_section())
		var body := HBoxContainer.new()
		body.add_child(_make_pane_section("self", "YOU"))
		body.add_child(_make_pane_section("container", _container_label))
		_content.add_child(body)
		_content.add_child(_make_footer())

func _make_header() -> Control:
	var l := Label.new()
	var title: String = "INVENTORY + GEAR" if _mode == "self" else "TRANSFER  |  %s" % _container_label
	l.text = "%s\n%s" % [title, _weight_line()]
	return l

func _make_equipment_section() -> Control:
	var box := VBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "-- Equipment --"
	box.add_child(hdr)
	for slot in (_equip.SLOTS if _equip != null else []):
		var zone = InventoryDropZoneScript.create(self, "slot:%s" % String(slot))
		zone.custom_minimum_size = Vector2(300, 0)
		var worn: String = _equip.get_equipped(String(slot)) if _equip != null else ""
		var lbl := Label.new()
		lbl.text = "%s  [%s]" % [String(slot), ("(empty)" if worn == "" else _name(worn))]
		zone.add_child(lbl)
		_zones["slot:%s" % String(slot)] = zone
		box.add_child(zone)
	return box

func _make_pane_section(pane: String, title: String) -> Control:
	var box := VBoxContainer.new()
	var t := Label.new()
	var cap: String = ""
	if pane == "container" and _container != null:
		cap = "  %d/%d" % [int(_container.get_total_weight()), int(_container.get_max_weight())]
	t.text = "%s%s" % [title, cap]
	box.add_child(t)
	var zone = InventoryDropZoneScript.create(self, pane)
	zone.custom_minimum_size = Vector2(320, 200)
	var rows_vbox := VBoxContainer.new()
	zone.add_child(rows_vbox)
	var ids: Array = _ids_for_pane(pane)
	for i in range(ids.size()):
		var row = InventoryRowScript.create(self, pane, i, String(ids[i]), _defs)
		rows_vbox.add_child(row)
		(_rows[pane] as Array).append(row)
		row.set_selected(_model_for_pane(pane).is_selected(i))
	_zones[pane] = zone
	box.add_child(zone)
	return box

func _make_footer() -> Control:
	var h := HBoxContainer.new()
	var dep := Button.new()
	dep.text = "Deposit All"
	dep.pressed.connect(deposit_all_to_container)
	h.add_child(dep)
	var cl := Button.new()
	cl.text = "Close"
	cl.pressed.connect(close)
	h.add_child(cl)
	return h

## Test/inspection seams: fetch a built row / drop zone after a render.
func row_at(pane: String, index: int) -> Control:
	var arr: Array = _rows.get(pane, []) as Array
	return arr[index] if index >= 0 and index < arr.size() else null

func zone_for(target: String) -> Control:
	return _zones.get(target, null)

func _weight_line() -> String:
	if _player_inv == null:
		return ""
	return "Wt %.1f/%.1f [%s] x%.2f" % [
		_player_inv.get_total_weight(), _player_inv.get_capacity(),
		get_load_badge(), _move_speed_mult(),
	]

func _name(id: String) -> String:
	return ItemDefsScript.display_name(_defs, id)
