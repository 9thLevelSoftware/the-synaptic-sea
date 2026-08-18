extends Node2D
## Validation harness for the top-down readability pipeline.
## Renders 4 placeholder colored rectangles at 16:9 aspect ratio.
## Used by CI to verify the 2D harness builds and renders correctly.

const HARNESS_WIDTH := 768   # 16 tiles x 48px
const HARNESS_HEIGHT := 432  # 9 tiles x 48px

var _frame_count := 0


func _ready() -> void:
	pass  # Positions are set in the .tscn


func _process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count == 2:
		# After 2 frames the scene is stable — quit for headless CI
		if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
			get_tree().quit()
