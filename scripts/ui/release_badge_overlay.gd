extends Control
class_name ReleaseBadgeOverlay

## REQ-RL-002 / REQ-RL-006 release badge overlay.
##
## Reads `BuildMetadataState.get_build_kind()` and shows a small badge
## in the HUD indicating whether the running build is `DEMO` (orange),
## `RELEASE` (green), or `DEV` (gray). Pure UI; the script parses the
## `BuildMetadataState` summary and applies scene-tree consequences
## (label text + modulate color).
##
## Wired as a child of the main HUD; refreshes on `_ready` and on
## `metadata_changed`. No gameplay state.

const BuildMetadataStateScript := preload("res://scripts/systems/build_metadata_state.gd")

@export var dev_color: Color = Color(0.6, 0.6, 0.6, 1.0)
@export var demo_color: Color = Color(1.0, 0.55, 0.0, 1.0)
@export var release_color: Color = Color(0.2, 0.85, 0.3, 1.0)

var _badge_label: Label = null
var _metadata: BuildMetadataState = null

signal metadata_changed

func _ready() -> void:
	_badge_label = Label.new()
	_badge_label.name = "ReleaseBadge"
	_badge_label.text = "..."
	_badge_label.add_theme_color_override("font_color", dev_color)
	add_child(_badge_label)

func set_metadata(metadata: BuildMetadataState) -> void:
	_metadata = metadata
	_refresh_badge()
	metadata_changed.emit()

func get_metadata() -> BuildMetadataState:
	return _metadata

func get_badge_text() -> String:
	if _metadata == null:
		return "DEV"
	var kind: String = _metadata.get_build_kind()
	if kind == "demo":
		return "DEMO"
	if kind == "release":
		return "RELEASE"
	return "DEV"

func get_badge_color() -> Color:
	if _metadata == null:
		return dev_color
	var kind: String = _metadata.get_build_kind()
	if kind == "demo":
		return demo_color
	if kind == "release":
		return release_color
	return dev_color

func _refresh_badge() -> void:
	if _badge_label == null:
		return
	_badge_label.text = get_badge_text()
	_badge_label.add_theme_color_override("font_color", get_badge_color())

func apply_to_scene() -> void:
	_refresh_badge()