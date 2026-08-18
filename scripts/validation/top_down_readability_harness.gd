extends Node2D
## Validation harness for the top-down readability pipeline.
## Renders 4 placeholder colored rectangles at 16:9 aspect ratio.
## Used by CI to verify the 2D harness builds and renders correctly.

const HARNESS_WIDTH := 768   # 16 tiles × 48px
const HARNESS_HEIGHT := 432  # 9 tiles × 48px

var _frame_count := 0


func _ready() -> void:
	# Position placeholders at tile-grid centers
	var player := get_node_or_null("PlayerPlaceholder")
	if player:
		player.position = Vector2(0, 0)

	var wall_n := get_node_or_null("WallNorth")
	if wall_n:
		wall_n.position = Vector2(0, 0)
	var wall_s := get_node_or_null("WallSouth")
	if wall_s:
		wall_s.position = Vector2(0, 0)
	var wall_e := get_node_or_null("WallEast")
	if wall_e:
		wall_e.position = Vector2(0, 0)
	var wall_w := get_node_or_null("WallWest")
	if wall_w:
		wall_w.position = Vector2(0, 0)


func _process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count == 2:
		# After 2 frames the scene is stable — quit for headless CI
		if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
			get_tree().quit()
