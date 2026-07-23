extends SceneTree

## Repair / breach / fire channels: re-interact while channeling is consumed.
## Marker: HAZARD CHANNEL CONSUME PASS repair=true breach=true fire=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const RepairPointScript := preload("res://scripts/tools/repair_point.gd")
const BreachSealPointScript := preload("res://scripts/tools/breach_seal_point.gd")
const FireSuppressionPointScript := preload("res://scripts/tools/fire_suppression_point.gd")
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
	if playable.player == null:
		_fail("player"); return

	# --- Repair point: force channeling then re-interact ---
	var rp = RepairPointScript.new()
	playable.add_child(rp)
	rp.channeling = true
	if not rp.try_start(playable.player):
		_fail("repair channeling re-interact not consumed"); return
	if not bool(rp.channeling):
		_fail("repair channeling cleared on re-interact"); return

	# --- Breach seal ---
	var sp = BreachSealPointScript.new()
	playable.add_child(sp)
	sp.channeling = true
	if not sp.try_start(playable.player):
		_fail("breach channeling re-interact not consumed"); return
	if not bool(sp.channeling):
		_fail("breach channeling cleared on re-interact"); return

	# --- Fire suppression ---
	var fp = FireSuppressionPointScript.new()
	playable.add_child(fp)
	fp.channeling = true
	if not fp.try_start(playable.player):
		_fail("fire channeling re-interact not consumed"); return
	if not bool(fp.channeling):
		_fail("fire channeling cleared on re-interact"); return

	print("HAZARD CHANNEL CONSUME PASS repair=true breach=true fire=true")
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
	print("HAZARD CHANNEL CONSUME FAIL: %s" % msg)
	finished = true
	quit(1)
