extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const RarityTierScript := preload("res://scripts/systems/rarity_tier.gd")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
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
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = playable.get_ship_systems_manager().get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				playable.get_ship_systems_manager().force_repair(sid, sub.subcomponent_id)
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var marker_id: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("travel to derelict failed")
		return
	if playable.loot_containers.is_empty():
		_fail("no loot containers built on board")
		return
	var first_container = playable.loot_containers[0]
	var container_id: String = String(first_container.container_id)
	if not playable.search_loot_container_for_validation(container_id):
		_fail("validation loot search failed")
		return
	if not first_container.searched:
		_fail("container did not mark searched")
		return
	if not String(playable._last_loot_feedback_line).begins_with("Loot:"):
		_fail("loot feedback line missing")
		return
	if playable.audio_manager == null or not playable.audio_manager.has_method("drain_captions"):
		_fail("audio manager missing caption seam")
		return
	var captions: Array = playable.audio_manager.drain_captions()
	if captions.is_empty():
		_fail("loot pickup produced no caption fallback")
		return
	playable._open_inventory_self()
	if playable.inventory_panel == null or not playable.inventory_panel.visible:
		_fail("inventory panel did not open")
		return
	var rows: Array = playable.inventory_panel._rows.get("self", [])
	if rows.is_empty():
		_fail("inventory panel rendered no carry rows")
		return
	var row = rows[0]
	if row == null or not is_instance_valid(row):
		_fail("inventory row instance invalid")
		return
	var defs: Dictionary = ItemDefsScript.load_definitions()
	var expected_color: Color = RarityTierScript.color(ItemDefsScript.rarity(defs, String(row.item_id)))
	var style_box: StyleBox = row.get_theme_stylebox("panel")
	if not (style_box is StyleBoxFlat):
		_fail("inventory row missing rarity border style")
		return
	var actual_color: Color = (style_box as StyleBoxFlat).border_color
	if actual_color != expected_color:
		_fail("inventory row border color did not match rarity tier")
		return
	var sfx_player = playable.audio_manager.get_bus_player(AudioEventSeamScript.BUS_SFX)
	if sfx_player == null:
		_fail("audio manager missing sfx bus player")
		return
	if not playable.request_save() or not playable.request_load():
		_fail("save/load round-trip failed")
		return
	if not first_container.searched and playable.current_ship != null and not playable.current_ship.looted_container_ids.has(container_id):
		_fail("searched container did not persist after save/load")
		return
	finished = true
	print("MAIN PLAYABLE LOOT ECOSYSTEM PASS marker=%s searched=true feedback=true captions=%d" % [marker_id, captions.size()])
	_teardown_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE LOOT ECOSYSTEM FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
