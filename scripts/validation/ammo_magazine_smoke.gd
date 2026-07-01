extends SceneTree

## Domain 5 Task 3: combat fires from the per-weapon magazine, empty magazine is a
## dry-fire click (no shot), reload refills from inventory reserve over 1.5s, and the
## reload timer advances on the AWAY (derelict) branch. Drives away_from_start = true.
## Marker: AMMO MAGAZINE PASS away_ticks=<n> spent=true dry_fire=true reloaded=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
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
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _validate() -> void:
	finished = true
	var wid := "flare_pistol"
	# Seed a loaded magazine of 1 and reserve stock in inventory.
	playable.ammo_state.configure({"magazines": {wid: 1}})
	playable.inventory_state.add_item("flare_round", 5)
	# Fire once from the magazine (spend), then dry-fire on empty.
	var spent: bool = playable.ammo_state.spend(wid) and playable.ammo_state.loaded(wid) == 0
	var dry_fire: bool = not playable.ammo_state.spend(wid)
	# Begin a reload and advance it on the AWAY branch.
	playable.away_from_start = true
	var mag_size := 2
	var reserve := playable.inventory_state.get_quantity("flare_round")
	var began: bool = playable.ammo_state.begin_reload(wid, mag_size, reserve)
	playable.inventory_state.remove_item("flare_round", playable.ammo_state.reload_target)
	var n: int = 0
	for i in range(30):
		playable._process(0.1)  # 3.0s total > 1.5s reload
		n += 1
	var reloaded: bool = began and playable.ammo_state.loaded(wid) == mag_size and not playable.ammo_state.is_reloading()
	if spent and dry_fire and reloaded:
		print("AMMO MAGAZINE PASS away_ticks=%d spent=true dry_fire=true reloaded=true" % n)
		_cleanup(0)
	else:
		_fail("spent=%s dry_fire=%s reloaded=%s loaded=%d" % [str(spent), str(dry_fire), str(reloaded), playable.ammo_state.loaded(wid)])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("AMMO MAGAZINE FAIL reason=%s" % reason)
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
