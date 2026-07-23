extends SceneTree

## Save/load slot rows render ADR-0046 metadata (location, play time, seed).
## Marker: SAVE SLOT METADATA UI PASS location=true play_time=true seed=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
const SETTLE_FRAMES: int = 20

var main_node: Node
var playable
var frame_count: int = 0
var settle_count: int = 0
var finished: bool = false


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if frame_count > TIMEOUT_FRAMES:
		_fail("timeout")
		return
	if playable == null:
		playable = _find_playable(main_node)
		return
	if not playable.playable_started:
		return
	settle_count += 1
	if settle_count < SETTLE_FRAMES:
		return
	_validate()


func _validate() -> void:
	finished = true
	if playable.menu_coordinator == null:
		_fail("menu_coordinator null"); return
	var coord = playable.menu_coordinator
	var result: Dictionary = playable.force_autosave_for_validation()
	var slot_id: String = str(result.get("slot_id", ""))
	if slot_id.is_empty():
		_fail("autosave produced no slot_id result=%s" % str(result)); return

	var rows: Array = coord._save_load_rows()
	var row = null
	var row_index: int = -1
	for i in range(rows.size()):
		if rows[i] != null and str(rows[i].slot_id) == slot_id:
			row = rows[i]
			row_index = i
			break
	if row == null:
		_fail("row for %s not found" % slot_id); return

	var line: String = coord._save_load_row_line(row, row_index)
	var loc: String = str(row.current_location)
	if loc.is_empty():
		loc = "?"
	if not line.contains(loc):
		_fail("line missing location '%s': %s" % [loc, line]); return
	if float(row.play_time_seconds) <= 0.0:
		_fail("row play_time_seconds not accumulated: %s" % str(row.play_time_seconds)); return
	var time_txt: String = coord._format_play_time_seconds(float(row.play_time_seconds))
	if not line.contains(time_txt):
		_fail("line missing play time '%s': %s" % [time_txt, line]); return
	var seed_token: String = "seed=%d" % int(row.synaptic_sea_seed)
	if not line.contains(seed_token):
		_fail("line missing %s: %s" % [seed_token, line]); return
	# Pure formatter unit checks.
	if coord._format_play_time_seconds(65.0) != "1m05s":
		_fail("format 65s expected 1m05s got %s" % coord._format_play_time_seconds(65.0)); return
	if coord._format_play_time_seconds(3661.0) != "1h01m":
		_fail("format 3661s expected 1h01m got %s" % coord._format_play_time_seconds(3661.0)); return

	print("SAVE SLOT METADATA UI PASS location=true play_time=true seed=true")
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
	print("SAVE SLOT METADATA UI FAIL: %s" % msg)
	finished = true
	quit(1)
