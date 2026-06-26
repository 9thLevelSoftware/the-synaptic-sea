extends Panel
class_name AudioSettingsPanel
## AudioSettingsPanel — HUD panel that exposes per-bus volume sliders, mute
## toggles, and global caption / voice-log toggles (REQ-AU-008, ADR-0029).
##
## Pure data + Control layout. The panel reads from the AudioManager
## passed in via set_audio_manager() and writes back through the manager's
## setter API. Labels cascade through accessibility_settings so the A11Y-
## P1-001 text-scale seam applies automatically.
##
## Smoke-friendly: every setter goes through AudioManager.set_bus_volume
## / set_bus_muted so the smoke can assert the volume/mute was applied.

const BUS_LIST: Array[StringName] = [
	AudioEventSeamScript.BUS_MASTER,
	AudioEventSeamScript.BUS_SFX,
	AudioEventSeamScript.BUS_MUSIC,
	AudioEventSeamScript.BUS_VOICE,
	AudioEventSeamScript.BUS_UI,
	AudioEventSeamScript.BUS_AMBIENT,
	AudioEventSeamScript.BUS_META,
]
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")

var audio_manager: Node
var accessibility_settings: RefCounted

# Volume sliders indexed by bus id (StringName).
var _volume_sliders: Dictionary = {}
# Mute checkboxes indexed by bus id.
var _mute_toggles: Dictionary = {}
# Caption toggle (one for all buses).
var _caption_toggle: CheckBox
# Voice-log toggle.
var _voice_log_toggle: CheckBox

func _ready() -> void:
	_build_layout()
	_refresh_from_manager()

func set_audio_manager(mgr: Node) -> void:
	audio_manager = mgr
	if is_inside_tree():
		_refresh_from_manager()

func set_accessibility_settings(settings: RefCounted) -> void:
	accessibility_settings = settings
	_apply_text_scale()

func _build_layout() -> void:
	# Title label.
	var title: Label = Label.new()
	title.name = "TitleLabel"
	title.text = "Audio Settings"
	add_child(title)

	var base_font_size: int = 16
	if accessibility_settings != null and accessibility_settings.has_method("scaled_hud_font_size"):
		base_font_size = accessibility_settings.scaled_hud_font_size(base_font_size)
	title.add_theme_font_size_override("font_size", base_font_size)

	# Build one HBox per bus with a label, a volume slider, and a mute toggle.
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "BusList"
	add_child(vbox)
	for bus_id in BUS_LIST:
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Row_%s" % String(bus_id)
		vbox.add_child(row)
		var label: Label = Label.new()
		label.name = "Label"
		label.text = String(bus_id)
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.name = "VolumeSlider"
		slider.min_value = -60.0
		slider.max_value = 0.0
		slider.step = 1.0
		slider.custom_minimum_size = Vector2(160, 24)
		slider.value_changed.connect(_on_volume_changed.bind(bus_id))
		row.add_child(slider)
		_volume_sliders[bus_id] = slider
		var toggle: CheckBox = CheckBox.new()
		toggle.name = "MuteToggle"
		toggle.text = "mute"
		toggle.toggled.connect(_on_mute_changed.bind(bus_id))
		row.add_child(toggle)
		_mute_toggles[bus_id] = toggle
	# Caption toggle.
	var caption_row: HBoxContainer = HBoxContainer.new()
	caption_row.name = "CaptionRow"
	vbox.add_child(caption_row)
	_caption_toggle = CheckBox.new()
	_caption_toggle.name = "CaptionToggle"
	_caption_toggle.text = "Closed captions"
	_caption_toggle.toggled.connect(_on_caption_toggled)
	caption_row.add_child(_caption_toggle)
	# Voice-log toggle.
	var voice_row: HBoxContainer = HBoxContainer.new()
	voice_row.name = "VoiceLogRow"
	vbox.add_child(voice_row)
	_voice_log_toggle = CheckBox.new()
	_voice_log_toggle.name = "VoiceLogToggle"
	_voice_log_toggle.text = "Voice log"
	_voice_log_toggle.toggled.connect(_on_voice_log_toggled)
	voice_row.add_child(_voice_log_toggle)

func _apply_text_scale() -> void:
	if accessibility_settings == null or not accessibility_settings.has_method("scaled_hud_font_size"):
		return
	var font_size: int = accessibility_settings.scaled_hud_font_size(16)
	var title: Node = get_node_or_null("TitleLabel")
	if title != null and title is Label:
		(title as Label).add_theme_font_size_override("font_size", font_size)
	for bus_id in BUS_LIST:
		var row: Node = get_node_or_null("BusList/Row_%s" % String(bus_id))
		if row != null:
			var lbl: Node = row.get_node_or_null("Label")
			if lbl != null and lbl is Label:
				(lbl as Label).add_theme_font_size_override("font_size", font_size)

func _refresh_from_manager() -> void:
	if audio_manager == null:
		return
	for bus_id in BUS_LIST:
		var slider: HSlider = _volume_sliders.get(bus_id, null)
		if slider != null:
			slider.value = audio_manager.get_bus_volume(bus_id)
		var toggle: CheckBox = _mute_toggles.get(bus_id, null)
		if toggle != null:
			toggle.button_pressed = audio_manager.is_bus_muted(bus_id)
	# Caption toggle reflects the router's captions_enabled flag.
	if _caption_toggle != null and audio_manager.has_method("sfx_router"):
		_caption_toggle.button_pressed = bool(audio_manager.sfx_router.captions_enabled)
	if _voice_log_toggle != null and audio_manager.has_method("audio_log"):
		_voice_log_toggle.button_pressed = true

func _on_volume_changed(value: float, bus_id: StringName) -> void:
	if audio_manager == null:
		return
	audio_manager.set_bus_volume(bus_id, value)

func _on_mute_changed(pressed: bool, bus_id: StringName) -> void:
	if audio_manager == null:
		return
	audio_manager.set_bus_muted(bus_id, pressed)

func _on_caption_toggled(pressed: bool) -> void:
	if audio_manager == null or not audio_manager.has_method("sfx_router"):
		return
	audio_manager.sfx_router.captions_enabled = pressed

func _on_voice_log_toggled(pressed: bool) -> void:
	# Voice-log enable/disable is a UI flag — audio_log entries are
	# always available; the panel just decides whether to show them.
	# No model change needed here.
	pass
