extends Control
class_name ShipModificationPanel

## PKG-D9b: hub ship-modification slot manifest + power budget display.
## Presentation only; coordinator binds ShipModificationState and supplies
## inventory for install/uninstall. Headless-queryable.

signal panel_closed
signal install_requested(slot_id: String, component_id: String, item_form: String)
signal uninstall_requested(slot_id: String, component_id: String, item_form: String)

var _mod_state                    # ShipModificationState
var _inventory: Dictionary = {}   # item_form -> qty (presentation bag for panel actions)
var _open: bool = false
var _selected: int = 0
var _status: String = ""
## Candidate empty slots the panel can install into (coordinator may set).
var candidate_slots: PackedStringArray = PackedStringArray(["hub_slot_0", "hub_slot_1", "hub_slot_2"])

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


func bind(mod_state, inventory: Dictionary = {}) -> void:
	_mod_state = mod_state
	_inventory = inventory.duplicate(true)
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


func move_selection(delta: int) -> void:
	var n: int = _slot_rows().size()
	if n <= 0:
		_selected = 0
		_render()
		return
	_selected = clampi(_selected + delta, 0, n - 1)
	_render()


## Uninstall currently selected occupied slot into panel inventory bag.
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
	if not _mod_state.has_method("uninstall"):
		return false
	var res: Dictionary = _mod_state.call("uninstall", slot_id, _inventory)
	if not bool(res.get("ok", false)):
		_status = "uninstall failed: %s" % str(res.get("reason", ""))
		_render()
		return false
	if item_form.is_empty():
		item_form = str(res.get("item_form", ""))
	_status = "uninstalled %s" % slot_id
	uninstall_requested.emit(slot_id, component_id, item_form)
	_render()
	return true


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
	if bool(row.get("occupied", false)):
		# Prefer first empty candidate.
		slot_id = _first_empty_slot()
	if slot_id.is_empty():
		_status = "no empty slot"
		_render()
		return false
	if not _mod_state.has_method("install"):
		return false
	var res: Dictionary = _mod_state.call(
		"install", slot_id, component_id, item_form, _inventory, power_draw, mass, "hub", plating
	)
	if not bool(res.get("ok", false)):
		_status = "install failed: %s" % str(res.get("reason", ""))
		_render()
		return false
	_status = "installed %s -> %s" % [component_id, slot_id]
	install_requested.emit(slot_id, component_id, item_form)
	_render()
	return true


## Install using the first inventory bag item that matches a known component form.
## catalog: ComponentCatalog with get_component / components dict optional.
func install_from_inventory(
		catalog = null,
		preferred_forms: PackedStringArray = PackedStringArray([
			"console_unit", "reactor_console", "nav_console", "pump_assembly",
			"conduit_segment", "plating_plate", "air_recycler_unit", "thruster_control", "sensor_rack",
		])) -> bool:
	if _inventory.is_empty():
		_status = "empty inventory"
		_render()
		return false
	var form: String = ""
	for f in preferred_forms:
		if int(_inventory.get(str(f), 0)) > 0:
			form = str(f)
			break
	if form.is_empty():
		# Any stackable item as last resort
		for k in _inventory.keys():
			if int(_inventory[k]) > 0:
				form = str(k)
				break
	if form.is_empty():
		_status = "no installable item"
		_render()
		return false
	var component_id: String = form
	var power_draw: float = 5.0
	var mass: float = 10.0
	var plating: bool = form.find("plating") >= 0 or form.find("plate") >= 0
	if catalog != null:
		if catalog.has_method("component_id_for_item_form"):
			var cid: String = str(catalog.call("component_id_for_item_form", form))
			if not cid.is_empty():
				component_id = cid
		if catalog.has_method("get_component"):
			var def: Dictionary = catalog.call("get_component", component_id)
			if not def.is_empty():
				power_draw = float(def.get("power_draw", power_draw))
				mass = float(def.get("mass", mass))
	return install_into_selected(component_id, form, power_draw, mass, plating)


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


func _slot_rows() -> Array:
	var rows: Array = []
	var seen: Dictionary = {}
	if _mod_state != null:
		var installed: Array = _mod_state.get("installed") as Array if typeof(_mod_state.get("installed")) == TYPE_ARRAY else []
		for e in installed:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = (e as Dictionary).duplicate(true)
			row["occupied"] = true
			var sid: String = str(row.get("slot_id", ""))
			if sid.is_empty():
				continue
			seen[sid] = true
			rows.append(row)
	for sid in candidate_slots:
		var s: String = str(sid)
		if seen.has(s):
			continue
		rows.append({"slot_id": s, "occupied": false})
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


func _render() -> void:
	if _list_label == null:
		return
	var lines: PackedStringArray = get_status_lines()
	_list_label.text = "\n".join(lines)
	if _status_label != null:
		_status_label.text = _status
	if _title_label != null:
		_title_label.text = "SHIP MODIFICATION" if _open else "SHIP MODIFICATION (closed)"
