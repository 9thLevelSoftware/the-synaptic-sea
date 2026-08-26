extends SceneTree
## Drives the debug viewer through several ships and screenshots each:
##   godot --path godot -s tests/gallery.gd

const SHOTS := [
	{"seed": 12, "arch": 3, "intact": 3000, "name": "frigate_fractured"},
	{"seed": 42, "arch": 2, "intact": 8500, "name": "freighter_intact"},
	{"seed": 7, "arch": 1, "intact": 5500, "name": "corvette_damaged"},
	{"seed": 3, "arch": 0, "intact": 1200, "name": "shuttle_wreck"},
]

var _frames := 0
var _shot := 0
var _settle := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/Main.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	var viewer: DerelictDebugViewer = current_scene as DerelictDebugViewer
	if viewer == null:
		return false

	if _settle == 0:
		if _shot >= SHOTS.size():
			print("GALLERY: done")
			quit(0)
			return true
		var s: Dictionary = SHOTS[_shot]
		viewer.seed_spin.value = s["seed"]
		viewer.arch_option.select(s["arch"])
		viewer.intact_check.button_pressed = true
		viewer.intact_slider.value = s["intact"]
		viewer._regenerate()
		_settle = 1
		return false

	_settle += 1
	if _settle == 50:
		# Fit camera to ship footprint.
		var site := viewer.site
		if site.ship_node and not site.ship_node.ship.is_empty():
			var deck0: Dictionary = site.ship_node.ship["decks"][0]
			var px: float = (int(deck0["width"]) + int(deck0["height"])) * 32.0
			var z: float = clampf(1500.0 / px, 0.25, 1.2)
			viewer.camera.zoom = Vector2(z, z)
	if _settle >= 70:
		var img := root.get_viewport().get_texture().get_image()
		var s2: Dictionary = SHOTS[_shot]
		var path: String = "res://../gallery_%s.png" % s2["name"]
		img.save_png(path)
		print("GALLERY: saved %s" % path)
		_shot += 1
		_settle = 0
	return false
