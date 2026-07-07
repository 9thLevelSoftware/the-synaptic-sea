extends SceneTree

## Session 3 B4 (audit): SaveSlotState rows carried placeholder metadata
## because RunSnapshot had no real fields to index from
## (save_load_service.gd::_index_run_slot):
##   - synaptic_sea_seed  = int(player_position.x * 1000)   # placeholder
##   - current_location   = str(player_position.x)          # an X coordinate
##   - play_time_seconds  = float(saved_at_epoch)           # a Unix timestamp
##
## Fix (ADR-0046): RunSnapshot gains play_time_seconds / current_location /
## world_seed (schema gate2-current-run-4); the coordinator accumulates play
## time each _process frame (before the home/away branch split, so BOTH
## branches count) and stamps location + the real Synaptic Sea seed at
## snapshot build; _index_run_slot reads the real fields.
##
## Production path: main scene boots, frames tick, then
## force_autosave_for_validation() drives _build_run_snapshot ->
## save_to_slot -> _index_run_slot. Asserts on the indexed row AND on the
## reloaded snapshot round-trip.
##
## Pass marker: SLOT METADATA PASS location=home play_time_real=true seed_real=true roundtrip=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
const SETTLE_FRAMES: int = 30

var main_node: Node
var frame_count: int = 0
var settle_count: int = 0
var finished: bool = false
var playable: PlayableGeneratedShip = null

func _initialize() -> void:
	var bootstrap := SaveLoadService.new()
	_cleanup_slots(bootstrap)
	bootstrap.delete_current_run()
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if frame_count > TIMEOUT_FRAMES:
		_fail("timeout waiting for playable slice")
		return
	if playable == null:
		playable = _find_playable(main_node)
		return
	if not playable.playable_started:
		return
	# Let real frames tick past playable_started so play time accumulates
	# through the production _process path before the save.
	settle_count += 1
	if settle_count < SETTLE_FRAMES:
		return
	_validate()

func _validate() -> void:
	finished = true
	var service: SaveLoadService = playable.get_save_load_service()
	if service == null:
		_fail("save_load_service null")
		return
	var world = playable.get_synaptic_sea_world()
	if world == null:
		_fail("synaptic_sea_world null")
		return
	var expected_seed: int = int(world.world_seed)

	# --- Save through the real coordinator path (autosave slot). -----------
	var result: Dictionary = playable.force_autosave_for_validation()
	var slot_id: String = str(result.get("slot_id", ""))
	if slot_id.is_empty():
		_fail("force_autosave_for_validation produced no slot_id (result=%s)" % str(result))
		return

	# --- 1..3: the indexed SaveSlotState row carries REAL metadata. --------
	var row = null
	for r in service.list_slots():
		if str(r.slot_id) == slot_id:
			row = r
			break
	if row == null:
		_fail("no index row for slot %s" % slot_id)
		return
	if str(row.current_location) != "home":
		_fail("row.current_location='%s' expected 'home' (placeholder was player X)" % str(row.current_location))
		return
	var play_time: float = float(row.play_time_seconds)
	if play_time <= 0.0 or play_time >= 100000.0:
		_fail("row.play_time_seconds=%f not a real accumulated play time (placeholder was the Unix epoch)" % play_time)
		return
	if int(row.synaptic_sea_seed) != expected_seed:
		_fail("row.synaptic_sea_seed=%d expected world_seed=%d (placeholder was pos.x*1000)" % [int(row.synaptic_sea_seed), expected_seed])
		return

	# --- 4: the RunSnapshot round-trips the three new fields. --------------
	var reloaded = service.load_from_slot(slot_id)
	if reloaded == null:
		_fail("load_from_slot %s returned null" % slot_id)
		return
	var rt_play: Variant = reloaded.get("play_time_seconds")
	var rt_loc: Variant = reloaded.get("current_location")
	var rt_seed: Variant = reloaded.get("world_seed")
	if rt_play == null or rt_loc == null or rt_seed == null:
		_fail("RunSnapshot missing new fields (play=%s loc=%s seed=%s)" % [str(rt_play), str(rt_loc), str(rt_seed)])
		return
	if float(rt_play) <= 0.0:
		_fail("reloaded play_time_seconds=%s did not round-trip" % str(rt_play))
		return
	if str(rt_loc) != "home":
		_fail("reloaded current_location='%s' expected 'home'" % str(rt_loc))
		return
	if int(rt_seed) != expected_seed:
		_fail("reloaded world_seed=%d expected %d" % [int(rt_seed), expected_seed])
		return

	print("SLOT METADATA PASS location=home play_time_real=true seed_real=true roundtrip=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	finished = true
	push_error("SLOT METADATA FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	var service := SaveLoadService.new()
	_cleanup_slots(service)
	service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)

func _cleanup_slots(service: SaveLoadService) -> void:
	for slot_id in ["autosave_a", "autosave_b", "autosave_c", "autosave_active", "quicksave", "world"]:
		service.delete_slot(slot_id)
