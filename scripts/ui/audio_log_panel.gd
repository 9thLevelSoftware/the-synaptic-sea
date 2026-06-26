extends Panel
class_name AudioLogPanel
## AudioLogPanel — HUD panel that lists voice-log entries and lets the
## player play / pause / jump-to-entry (REQ-AU-006, ADR-0029).
##
## Pure data + Control layout. The panel reads entries from the
## AudioManager's audio_log registry and triggers playback through
## audio_manager.play_voice_log(entry_id). The "currently playing"
## label reflects audio_manager.current_voice_log_id.

const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")

var audio_manager: Node
var accessibility_settings: RefCounted

var _entry_list: ItemList
var _play_button: Button
var _stop_button: Button
var _status_label: Label

func _ready() -> void:
	_build_layout()
	_populate_entries()

func set_audio_manager(mgr: Node) -> void:
	audio_manager = mgr
	if is_inside_tree():
		_populate_entries()

func _build_layout() -> void:
	var title: Label = Label.new()
	title.name = "TitleLabel"
	title.text = "Audio Log"
	add_child(title)
	var base_font_size: int = 16
	if accessibility_settings != null and accessibility_settings.has_method("scaled_hud_font_size"):
		base_font_size = accessibility_settings.scaled_hud_font_size(base_font_size)
	title.add_theme_font_size_override("font_size", base_font_size)

	_entry_list = ItemList.new()
	_entry_list.name = "EntryList"
	_entry_list.custom_minimum_size = Vector2(320, 200)
	_entry_list.item_selected.connect(_on_entry_selected)
	add_child(_entry_list)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.name = "ButtonRow"
	add_child(button_row)
	_play_button = Button.new()
	_play_button.name = "PlayButton"
	_play_button.text = "Play"
	_play_button.pressed.connect(_on_play_pressed)
	button_row.add_child(_play_button)
	_stop_button = Button.new()
	_stop_button.name = "StopButton"
	_stop_button.text = "Stop"
	_stop_button.pressed.connect(_on_stop_pressed)
	button_row.add_child(_stop_button)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "(no entry playing)"
	add_child(_status_label)

func _populate_entries() -> void:
	if _entry_list == null:
		return
	_entry_list.clear()
	if audio_manager == null or not audio_manager.has_method("audio_log"):
		return
	var ids: Array = audio_manager.audio_log.list_entry_ids()
	for entry_id in ids:
		var entry: Dictionary = audio_manager.audio_log.get_entry(StringName(entry_id))
		_entry_list.add_item(String(entry.get("label", entry_id)))
		_entry_list.set_item_metadata(_entry_list.item_count - 1, entry_id)
	_refresh_status()

func _refresh_status() -> void:
	if _status_label == null or audio_manager == null:
		return
	var current: String = String(audio_manager.current_voice_log_id)
	if current.is_empty():
		_status_label.text = "(no entry playing)"
	else:
		var entry: Dictionary = audio_manager.audio_log.get_entry(StringName(current))
		_status_label.text = "Playing: %s" % String(entry.get("label", current))

func _on_entry_selected(idx: int) -> void:
	if _entry_list == null:
		return
	var entry_id: Variant = _entry_list.get_item_metadata(idx)
	if entry_id == null:
		return
	if audio_manager != null:
		audio_manager.play_voice_log(StringName(String(entry_id)))
		_refresh_status()

func _on_play_pressed() -> void:
	if _entry_list == null or audio_manager == null:
		return
	var selected: PackedInt32Array = _entry_list.get_selected_items()
	if selected.is_empty():
		return
	var idx: int = selected[0]
	var entry_id: Variant = _entry_list.get_item_metadata(idx)
	if entry_id == null:
		return
	audio_manager.play_voice_log(StringName(String(entry_id)))
	_refresh_status()

func _on_stop_pressed() -> void:
	if audio_manager == null:
		return
	audio_manager.current_voice_log_id = ""
	_refresh_status()
