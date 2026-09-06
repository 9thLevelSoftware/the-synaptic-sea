extends Control
class_name RecipePickerPanel

## REQ-CS-016 station recipe picker. Lists CraftingState.list_recipe_entries for a
## station_kind, moves a selection, and confirms via the coordinator begin path.
## Unstyled text list (scanner / hub-upgrade pattern). Headless-queryable for smokes.

signal panel_closed

var _coordinator                 # PlayableGeneratedShip or stub with list + begin APIs
var _station_kind: String = ""
var _ship_id: String = ""
var _station_instance_id: String = ""
var _binding_generation: int = -1
var _entries: Array = []         # Array of entry Dictionaries from list_recipe_entries
var _rows: Array = []            # recipe rows plus exact physical actions
var _station_projection: Dictionary = {}
var _selected: int = 0
var _status: String = ""
var _open: bool = false

var _title_label: Label
var _list_label: Label
var _status_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _title_label == null:
		_title_label = Label.new()
		_title_label.position = Vector2(24, 24)
		_title_label.text = "CRAFT"
		add_child(_title_label)
		_list_label = Label.new()
		_list_label.position = Vector2(24, 56)
		add_child(_list_label)
		_status_label = Label.new()
		_status_label.position = Vector2(24, 360)
		add_child(_status_label)
	visible = _open
	_render()

func bind(coord) -> void:
	_coordinator = coord

func is_open() -> bool:
	return _open

func get_station_kind() -> String:
	return _station_kind

func get_ship_id() -> String:
	return _ship_id

func get_station_instance_id() -> String:
	return _station_instance_id

func get_binding_generation() -> int:
	return _binding_generation

func get_station_projection() -> Dictionary:
	return _station_projection.duplicate(true)

func get_selected_index() -> int:
	return _selected

func get_status() -> String:
	return _status

func get_entry_count() -> int:
	return _rows.size()

func get_selected_id() -> String:
	if _selected < 0 or _selected >= _rows.size():
		return ""
	var row: Dictionary = _rows[_selected] as Dictionary
	return str(row.get("action_id", row.get("recipe_id", "")))

func get_row_texts() -> Array:
	var out: Array = []
	for row in _rows:
		out.append(_format_row(row as Dictionary))
	return out

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Craft: %s  (%d recipes)" % [_station_kind if not _station_kind.is_empty() else "?", _entries.size()])
	if not _station_projection.is_empty():
		lines.append("Owner: %s / %s" % [_ship_id, _station_instance_id])
		lines.append("Queue: %d/%d  powered=%s  pending=%.2f kg" % [
			int(_station_projection.get("queue_depth", 0)),
			int(_station_projection.get("max_queue", 8)),
			str(bool(_station_projection.get("powered", false))).to_lower(),
			float(_station_projection.get("pending_mass", 0.0)),
		])
		for job_v in _station_projection.get("jobs", []) as Array:
			var job: Dictionary = job_v as Dictionary
			lines.append("Job %s: %s %.0f%% — %s" % [
				str(job.get("job_id", "?")), str(job.get("state", "?")),
				float(job.get("progress_ratio", 0.0)) * 100.0,
				str(job.get("cancel_policy", "unknown")),
			])
		if bool(_station_projection.get("power_paused", false)):
			lines.append("Paused: station power unavailable")
		if int(_station_projection.get("pending_record_count", 0)) > 0:
			lines.append("Output waiting: collect from this station")
	var rows: Array = get_row_texts()
	for i in range(rows.size()):
		var prefix: String = "> " if i == _selected else "  "
		lines.append(prefix + String(rows[i]))
	if not _status.is_empty():
		lines.append(_status)
	if not _ship_id.is_empty():
		lines.append("Arrows select • Enter confirm • I inventory")
	return lines

func open_for_station(
		station_kind: String, ship_id: String = "", station_instance_id: String = "",
		binding_generation: int = -1) -> bool:
	_station_kind = station_kind
	_ship_id = ship_id
	_station_instance_id = station_instance_id
	_binding_generation = binding_generation
	var has_ship: bool = not _ship_id.is_empty()
	var has_station: bool = not _station_instance_id.is_empty()
	if has_ship != has_station:
		_stale_close("incomplete station owner")
		return false
	if has_ship and _binding_generation < 0:
		_stale_close("stale station binding")
		return false
	_open = true
	visible = true
	_status = ""
	if not _refresh_entries():
		return false
	_selected = _first_ready_index()
	_render()
	return true

func close() -> void:
	_open = false
	visible = false
	_station_kind = ""
	_ship_id = ""
	_station_instance_id = ""
	_binding_generation = -1
	_entries.clear()
	_rows.clear()
	_station_projection.clear()
	panel_closed.emit()

func refresh() -> void:
	if not _open:
		return
	var prev_id: String = get_selected_id()
	if not _refresh_entries():
		return
	# Prefer keeping the same recipe or exact action under the cursor if it still exists.
	var kept: int = -1
	if not prev_id.is_empty():
		for i in range(_rows.size()):
			var row: Dictionary = _rows[i] as Dictionary
			if str(row.get("action_id", row.get("recipe_id", ""))) == prev_id:
				kept = i
				break
	if kept >= 0:
		_selected = kept
	else:
		_selected = _first_ready_index()
	_render()

func move_selection(dir: int) -> void:
	if _rows.is_empty():
		return
	_selected = wrapi(_selected + dir, 0, _rows.size())
	_render()

func confirm_selection() -> Dictionary:
	if _rows.is_empty():
		_status = "no recipes"
		_render()
		_play_deny_sfx()
		return {"ok": false, "reason": "no_recipes", "recipe_id": ""}
	var entry: Dictionary = _rows[_selected] as Dictionary
	var row_kind: String = str(entry.get("row_kind", "recipe"))
	if row_kind == "collect":
		return collect_pending_output()
	if row_kind == "cancel":
		return cancel_station_job(str(entry.get("job_id", "")))
	var rid: String = str(entry.get("recipe_id", ""))
	if not bool(entry.get("craftable", false)):
		_status = "blocked: %s" % str(entry.get("status", "unknown"))
		_render()
		_play_deny_sfx()
		return {"ok": false, "reason": str(entry.get("status", "blocked")), "recipe_id": rid}
	if _coordinator == null or not _coordinator.has_method("begin_craft_from_picker"):
		_status = "no craft handler"
		_render()
		_play_deny_sfx()
		return {"ok": false, "reason": "not_ready", "recipe_id": rid}
	var result: Dictionary
	if not _ship_id.is_empty() and not _station_instance_id.is_empty():
		result = _coordinator.begin_craft_from_picker(
			_station_kind, rid, _ship_id, _station_instance_id, _binding_generation)
	else:
		result = _coordinator.begin_craft_from_picker(_station_kind, rid)
	if bool(result.get("ok", false)):
		if str(result.get("reason", "")) == "queued":
			_status = "queued: %s" % rid
			refresh()
		else:
			close()
		return result
	_status = str(result.get("reason", "rejected"))
	_render()
	_play_deny_sfx()
	# Refresh so ingredient state after a partial failure is accurate.
	refresh()
	return result


func _play_deny_sfx() -> void:
	if _coordinator == null or _coordinator.get("audio_manager") == null:
		return
	var am = _coordinator.audio_manager
	if is_instance_valid(am) and am.has_method("play_sfx"):
		var AudioEventSeamScript = load("res://scripts/audio/audio_event_seam.gd")
		am.play_sfx(AudioEventSeamScript.UI_PANEL_CLOSE)

func _refresh_entries() -> bool:
	_entries = []
	_rows = []
	_station_projection.clear()
	if _coordinator == null or not _coordinator.has_method("list_station_recipe_entries"):
		return false
	var listed: Variant
	if not _ship_id.is_empty() and not _station_instance_id.is_empty():
		listed = _coordinator.list_station_recipe_entries(
			_station_kind, _ship_id, _station_instance_id, _binding_generation)
	else:
		listed = _coordinator.list_station_recipe_entries(_station_kind)
	if listed is Array:
		_entries = listed as Array
	if not _ship_id.is_empty() and not _station_instance_id.is_empty() \
			and _coordinator.has_method("get_station_crafting_projection"):
		var projection_v: Variant = _coordinator.get_station_crafting_projection(
			_station_kind, _ship_id, _station_instance_id, _binding_generation)
		if projection_v is Dictionary:
			_station_projection = (projection_v as Dictionary).duplicate(true)
			if not bool(_station_projection.get("ok", false)):
				_stale_close(str(_station_projection.get("reason", "stale station binding")))
				return false
	_build_rows()
	return true

func collect_pending_output() -> Dictionary:
	if _coordinator == null or _ship_id.is_empty() or _station_instance_id.is_empty() \
			or not _coordinator.has_method("collect_station_pending_output"):
		return {"ok": false, "reason": "missing_station_owner"}
	var result: Dictionary = _coordinator.collect_station_pending_output(
		_station_kind, _ship_id, _station_instance_id, _binding_generation)
	var transferred: int = int(result.get("transferred", 0))
	_status = "collected %d" % transferred \
		if bool(result.get("ok", false)) and transferred > 0 \
		else "collect blocked: %s" % str(result.get("reason", "unknown"))
	refresh()
	return result

func cancel_station_job(job_id: String) -> Dictionary:
	if _coordinator == null or _ship_id.is_empty() or _station_instance_id.is_empty() \
			or not _coordinator.has_method("cancel_station_craft_from_picker"):
		return {"ok": false, "reason": "missing_station_owner"}
	if job_id.is_empty():
		return {"ok": false, "reason": "missing_job_id"}
	var result: Dictionary = _coordinator.cancel_station_craft_from_picker(
		_station_kind, _ship_id, _station_instance_id, job_id, _binding_generation)
	_status = "cancelled: %s" % str(result.get("result", "")) \
		if bool(result.get("ok", false)) else "cancel blocked: %s" % str(result.get("reason", "unknown"))
	refresh()
	return result

func _first_ready_index() -> int:
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i] as Dictionary
		if str(row.get("row_kind", "recipe")) != "recipe" \
				or bool(row.get("craftable", false)):
			return i
	return 0


func _build_rows() -> void:
	if not _ship_id.is_empty() and int(_station_projection.get("pending_record_count", 0)) > 0:
		_rows.append({"row_kind": "collect", "action_id": "collect_pending"})
	for job_v in _station_projection.get("jobs", []) as Array:
		if job_v is Dictionary and bool((job_v as Dictionary).get("cancellable", false)):
			_rows.append({
				"row_kind": "cancel",
				"action_id": "cancel:%s" % str((job_v as Dictionary).get("job_id", "")),
				"job_id": str((job_v as Dictionary).get("job_id", "")),
				"cancel_policy": str((job_v as Dictionary).get("cancel_policy", "unavailable")),
			})
	for entry in _entries:
		if entry is Dictionary:
			var recipe_row: Dictionary = (entry as Dictionary).duplicate(true)
			recipe_row["row_kind"] = "recipe"
			_rows.append(recipe_row)


func _stale_close(reason: String) -> void:
	var was_open: bool = _open
	_status = reason
	_open = false
	visible = false
	_station_projection.clear()
	_rows.clear()
	_entries.clear()
	if was_open:
		panel_closed.emit()

func _format_row(entry: Dictionary) -> String:
	if str(entry.get("row_kind", "recipe")) == "collect":
		return "[action] Collect pending output"
	if str(entry.get("row_kind", "recipe")) == "cancel":
		return "[action] Cancel %s (%s)" % [
			str(entry.get("job_id", "?")), str(entry.get("cancel_policy", "unavailable"))]
	var status: String = str(entry.get("status", "?"))
	var name: String = str(entry.get("display_name", entry.get("recipe_id", "?")))
	var skill: int = int(entry.get("required_skill_level", 0))
	var produces: Dictionary = entry.get("produces", {}) as Dictionary if entry.get("produces", {}) is Dictionary else {}
	var out_id: String = str(produces.get("item_id", ""))
	var out_qty: int = int(produces.get("quantity", 0))
	var ing_parts: Array = []
	var ingredients: Variant = entry.get("ingredients", {})
	if ingredients is Dictionary:
		for mat_id in (ingredients as Dictionary):
			ing_parts.append("%s×%d" % [str(mat_id), int((ingredients as Dictionary)[mat_id])])
	var ing_str: String = " ".join(ing_parts) if not ing_parts.is_empty() else "-"
	var hint: String = str(entry.get("knowledge_hint", ""))
	var hint_suffix: String = "  hint=%s" % hint if status == "missing_recipe_knowledge" and not hint.is_empty() else ""
	var quality_suffix: String = ""
	if entry.has("quality_preview"):
		var preview_v: Variant = entry.get("quality_preview", {})
		if preview_v is Dictionary and not (preview_v as Dictionary).is_empty():
			quality_suffix = "  predicted=%s — %s" % [
				str((preview_v as Dictionary).get("tier", "standard")).capitalize(),
				str((preview_v as Dictionary).get("effect_text", "")),
			]
			var input_ids: Array = (preview_v as Dictionary).get("input_lot_ids", []) as Array
			if not input_ids.is_empty():
				quality_suffix += "  lots=%s" % ",".join(input_ids)
		else:
			quality_suffix = "  predicted=unavailable (exact inputs missing)"
	return "[%s] %s  skill=%d  %s → %s×%d%s%s" % [
		status, name, skill, ing_str, out_id, out_qty, quality_suffix, hint_suffix]

func _render() -> void:
	if _title_label != null:
		if _station_kind == "salvage":
			_title_label.text = "SALVAGE"
		elif _station_kind == "field_crafting":
			_title_label.text = "FIELD CRAFT"
		elif _station_kind == "hydroponics":
			_title_label.text = "HYDROPONICS"
		else:
			_title_label.text = "CRAFT — %s" % (_station_kind if not _station_kind.is_empty() else "?")
	if _list_label == null:
		return
	var lines: PackedStringArray = get_status_lines()
	_list_label.text = "\n".join(lines) if not lines.is_empty() else "(no recipes)"
	if _status_label != null:
		_status_label.text = _status
