extends SceneTree
## Captures a screenshot of the running debug viewer (windowed):
##   godot --path godot -s tests/screenshot.gd -- out.png

var _frames := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/Main.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 90:  # let generation + spawning + a few draws settle
		var img := root.get_viewport().get_texture().get_image()
		var args := OS.get_cmdline_user_args()
		var path := "res://../screenshot.png" if args.is_empty() else args[0]
		img.save_png(path)
		print("SCREENSHOT: saved %s" % path)
		quit(0)
		return true
	return false
