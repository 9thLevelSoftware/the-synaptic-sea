extends Control
class_name ShipModificationPanel

## PKG-D9b: hub ship-modification slot manifest + power budget display.
## Presentation only; coordinator binds ShipModificationState and supplies
## inventory for install/uninstall. Headless-queryable.

signal panel_closed
signal install_requested(ship_id: String, binding_generation: int, slot_id: String, component_id: String, item_form: String)
signal uninstall_requested(ship_id: String, binding_generation: int, slot_id: String, component_id: String, item_form: String)

var _mod_state                    # ShipModificationState
var _inventory: Dictionary = {}   # item_form -> qty (presentation bag for panel actions)
var _catalog                       # ComponentCatalog for real-form selection
var _install_preflight_query: Callable = Callable()
var _bound_ship_id: String = ""
var _bound_binding_generation: int = 0
var _open: bool = false
var _selected: int = 0
var _status: String = ""
## Deprecated compatibility surface.  P11 intentionally never reads it: rows are
## supplied by selected-ship physical descriptors, never synthetic hub slots.
var candidate_slots: PackedStringArray = PackedStringArray()

var _title_label: Label
var _list_label: Label
var _status_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _title_label == null:
		_title_label = Label.new()
		_title_label.position = Vector2(24, 24)
		_title_label.text = "SHIP MODIFICATION"
		add_child(_title_label)
		_list_label = Label.new()
		_list_label.position = Vector2(24, 56)
		add_child(_list_label)
		_status_label = Label.new()
		_status_label.position = Vector2(24, 340)
		add_child(_status_label)
	visible = _open
	_render()


func bind(mod_state, inventory: Dictionary = {}, catalog = null, physical_slots: Array = [], ship_id: String = "", placement_owner = null, binding_generation: int = 0) -> void:
	_mod_state = mod_state
	_inventory = inventory.duplicate(true)
	_catalog = catalog
	_bound_ship_id = ship_id
	_bound_binding_generation = maxi(0, binding_generation)
	if _mod_state != null and catalog != null and not physical_slots.is_empty() and _mod_state.has_method("bind_physical_slots"):
		_mod_state.call("bind_physical_slots", ship_id, physical_slots, catalog, placement_owner)
	_render()


func set_inventory(inventory: Dictionary) -> void:
	_inventory = inventory.duplicate(true)
	_render()


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	visible = true
	_selected = 0
	_status = ""
	_render()


func close() -> void:
	_open = false
	visible = false
	panel_closed.emit()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func refresh() -> void:
	_render()


func get_selected_index() -> int:
	return _selected


func get_selected_slot_id() -> String:
	var rows: Array = _slot_rows()
	if _selected < 0 or _selected >= rows.size():
		return ""
	return str((rows[_selected] as Dictionary).get("slot_id", ""))


func select_slot_id(slot_id: String) -> bool:
	var rows: Array = _slot_rows()
	for index in range(rows.size()):
		if rows[index] is Dictionary and str((rows[index] as Dictionary).get("slot_id", "")) == slot_id:
			_selected = index
			_render()
			return true
	return false


func move_selection(delta: int) -> void:
	var n: int = _slot_rows().size()
	if n <= 0:
		_selected = 0
		_render()
		return
	_selected = clampi(_selected + delta, 0, n - 1)
	_render()


## Request timed uninstall of the selected occupied slot. The coordinator owns
## escrow, WorkAction progress, physical mutation, and the final inventory lot.
func uninstall_selected() -> bool:
	var slot_id: String = get_selected_slot_id()
	if slot_id.is_empty() or _mod_state == null:
		_status = "no slot"
		_render()
		return false
	var row: Dictionary = _row_for_slot(slot_id)
	if not bool(row.get("occupied", false)):
		_status = "empty slot"
		_render()
		return false
	var component_id: String = str(row.get("component_id", ""))
	var item_form: String = str(row.get("item_form", ""))
	_status = "uninstall requested %s" % slot_id
	uninstall_requested.emit(_bound_ship_id, _bound_binding_generation, slot_id, component_id, item_form)
	_render()
	return true


## Production injects an exact-lot-aware read-only query. Legacy isolated panel
## fixtures may omit it and continue through ShipModificationState directly.
func set_install_preflight_query(query: Callable) -> void:
	_install_preflight_query = query


## Install a component into the selected empty slot (or first empty candidate).
func install_into_selected(
		component_id: String,
		item_form: String,
		power_draw: float = 5.0,
		mass: float = 10.0,
		plating: bool = false) -> bool:
	if _mod_state == null:
		_status = "no mod state"
		_render()
		return false
	var slot_id: String = get_selected_slot_id()
	var row: Dictionary = _row_for_slot(slot_id)
	if bool(row.get("occupied", false)) or not _preflight_ok(slot_id, component_id, item_form):
		slot_id = _first_compatible_empty_slot(component_id, item_form)
	if slot_id.is_empty():
		_status = "no empty slot"
		_render()
		return false
	_status = "install requested %s -> %s" % [component_id, slot_id]
	install_requested.emit(_bound_ship_id, _bound_binding_generation, slot_id, component_id, item_form)
	_render()
	return true


## Coordinator feedback after request admission, interruption, or commit.
func set_request_status(message: String) -> void:
	_status = message
	_render()


## Install using the first inventory bag item that matches a known component form.
## catalog: ComponentCatalog with get_component / components dict optional.
func install_from_inventory(
		catalog = null,
		_preferred_forms: PackedStringArray = PackedStringArray()) -> bool:
	if _inventory.is_empty():
		_status = "empty inventory"
		_render()
		return false
	if catalog != null:
		_catalog = catalog
	if _catalog == null or not _catalog.has_method("catalogued_inventory_components"):
		_status = "no catalogued component"
		_render()
		return false
	var candidates: Array = _catalog.call("catalogued_inventory_components", _inventory)
	for candidate_v in candidates:
		if not (candidate_v is Dictionary):
			continue
		var candidate: Dictionary = candidate_v as Dictionary
		var component_id: String = str(candidate.get("component_id", ""))
		var item_form: String = str(candidate.get("item_form", ""))
		if _first_compatible_empty_slot(component_id, item_form).is_empty():
			continue
		return install_into_selected(component_id, item_form)
	_status = "no compatible physical slot"
	_render()
	return false


func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if _mod_state == null:
		lines.append("Ship Mod: (unbound)")
		return lines
	var supply: float = float(_mod_state.get("power_supply"))
	var draw: float = 0.0
	if _mod_state.has_method("total_power_draw"):
		draw = float(_mod_state.call("total_power_draw"))
	var ok: bool = true
	if _mod_state.has_method("is_power_budget_ok"):
		ok = bool(_mod_state.call("is_power_budget_ok"))
	var plating: float = float(_mod_state.get("hull_plating_bonus"))
	lines.append(
		"Ship Mod: power %.0f/%.0f %s  plating=%.2f  installed=%d" % [
			draw, supply, "OK" if ok else "OVER", plating, int(_mod_state.call("installed_count")) if _mod_state.has_method("installed_count") else 0
		]
	)
	var rows: Array = _slot_rows()
	var idx: int = 0
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = r
		var cursor: String = ">" if idx == _selected else " "
		var occ: bool = bool(row.get("occupied", false))
		if occ:
			lines.append("%s[%s] %s  draw=%.1f  item=%s" % [
				cursor,
				str(row.get("slot_id", "")),
				str(row.get("component_id", "")),
				float(row.get("power_draw", 0.0)),
				str(row.get("item_form", "")),
			])
		else:
			lines.append("%s[%s] (empty)" % [cursor, str(row.get("slot_id", ""))])
		idx += 1
	if not _status.is_empty():
		lines.append("Status: %s" % _status)
	return lines


func get_inventory_bag() -> Dictionary:
	return _inventory.duplicate(true)


func get_bound_ship_id() -> String:
	return _bound_ship_id


func get_bound_binding_generation() -> int:
	return _bound_binding_generation


func emit_install_request_for_validation(
		slot_id: String, component_id: String, item_form: String,
		ship_id_override: String = "", binding_generation_override: int = -1) -> void:
	var request_ship_id: String = ship_id_override if not ship_id_override.is_empty() else _bound_ship_id
	var request_generation: int = binding_generation_override \
		if binding_generation_override >= 0 else _bound_binding_generation
	install_requested.emit(request_ship_id, request_generation, slot_id, component_id, item_form)


func emit_uninstall_request_for_validation(
		slot_id: String, component_id: String, item_form: String,
		ship_id_override: String = "", binding_generation_override: int = -1) -> void:
	var request_ship_id: String = ship_id_override if not ship_id_override.is_empty() else _bound_ship_id
	var request_generation: int = binding_generation_override \
		if binding_generation_override >= 0 else _bound_binding_generation
	uninstall_requested.emit(request_ship_id, request_generation, slot_id, component_id, item_form)


func _slot_rows() -> Array:
	var rows: Array = []
	if _mod_state == null or not _mod_state.has_method("get_physical_slots"):
		return rows
	var installed_by_slot: Dictionary = {}
	var installed: Array = _mod_state.get("installed") as Array if typeof(_mod_state.get("installed")) == TYPE_ARRAY else []
	for installed_v in installed:
		if typeof(installed_v) == TYPE_DICTIONARY:
			var installed_row: Dictionary = installed_v as Dictionary
			installed_by_slot[str(installed_row.get("slot_id", ""))] = installed_row
	for descriptor_v in _mod_state.call("get_physical_slots"):
		if typeof(descriptor_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = (descriptor_v as Dictionary).duplicate(true)
		var slot_id: String = str(row.get("slot_id", ""))
		if slot_id.is_empty():
			continue
		if installed_by_slot.has(slot_id):
			var installed_row: Dictionary = (installed_by_slot[slot_id] as Dictionary).duplicate(true)
			for key in row.keys():
				if not installed_row.has(key):
					installed_row[key] = row[key]
			installed_row["occupied"] = true
			rows.append(installed_row)
		else:
			row["occupied"] = bool(row.get("occupied", false))
			rows.append(row)
	return rows


func _row_for_slot(slot_id: String) -> Dictionary:
	for r in _slot_rows():
		if typeof(r) == TYPE_DICTIONARY and str((r as Dictionary).get("slot_id", "")) == slot_id:
			return r as Dictionary
	return {}


func _first_empty_slot() -> String:
	for r in _slot_rows():
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = r
		if not bool(row.get("occupied", true)):
			return str(row.get("slot_id", ""))
	return ""


func _first_compatible_empty_slot(component_id: String, item_form: String) -> String:
	for row_v in _slot_rows():
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v as Dictionary
		var slot_id: String = str(row.get("slot_id", ""))
		var preflight: Dictionary = _preflight_result(slot_id, component_id, item_form)
		if not bool(row.get("occupied", false)) and bool(preflight.get("ok", false)):
			return slot_id
	return ""


func _preflight_ok(slot_id: String, component_id: String, item_form: String) -> bool:
	return bool(_preflight_result(slot_id, component_id, item_form).get("ok", false))


func _preflight_result(slot_id: String, component_id: String, item_form: String) -> Dictionary:
	if _install_preflight_query.is_valid():
		var queried: Variant = _install_preflight_query.call(
			_bound_ship_id, _bound_binding_generation, slot_id, component_id, item_form)
		return queried as Dictionary if queried is Dictionary else {"ok": false, "reason": "missing_preflight"}
	if _mod_state == null or not _mod_state.has_method("preflight_install"):
		return {"ok": false, "reason": "missing_preflight"}
	return _mod_state.call("preflight_install", slot_id, component_id, item_form, _inventory)


func _render() -> void:
	if _list_label == null:
		return
	var lines: PackedStringArray = get_status_lines()
	_list_label.text = "\n".join(lines)
	if _status_label != null:
		_status_label.text = _status
	if _title_label != null:
		_title_label.text = "SHIP MODIFICATION" if _open else "SHIP MODIFICATION (closed)"
