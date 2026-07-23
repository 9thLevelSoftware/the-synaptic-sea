extends SceneTree

## Hydroponics harvest emits cook_meal training + harvest SFX is catalogued.
## Marker: PRODUCTION HARVEST XP PASS emit=true catalog=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()


func _validate() -> void:
	finished = true
	var bus = playable.get_training_event_bus()
	if bus == null:
		_fail("bus"); return
	if not SfxEventRouterScript.EVENT_CATALOG.has(String(AudioEventSeamScript.SFX_WORK_HARVEST)):
		_fail("harvest sfx missing"); return
	playable._on_production_harvested("hydroponics", "fresh_greens", 2)
	var found := false
	if bus.has_method("get_log"):
		for entry in bus.get_log():
			if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("event_id", "")) == "cook_meal":
				found = true
				break
	if not found:
		_fail("cook_meal not logged"); return
	# Water recycler should not grant cook XP
	var before: int = bus.get_log().size() if bus.has_method("get_log") else 0
	playable._on_production_harvested("water_recycler", "clean_water", 1)
	var after: int = bus.get_log().size() if bus.has_method("get_log") else 0
	if after != before:
		# allow only if not cook_meal
		var new_cook := false
		for entry2 in bus.get_log().slice(before):
			if typeof(entry2) == TYPE_DICTIONARY and str((entry2 as Dictionary).get("event_id", "")) == "cook_meal":
				new_cook = true
		if new_cook:
			_fail("recycler should not train cook_meal"); return
	print("PRODUCTION HARVEST XP PASS emit=true catalog=true")
	quit(0)


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("PRODUCTION HARVEST XP FAIL: %s" % msg)
	finished = true
	quit(1)
