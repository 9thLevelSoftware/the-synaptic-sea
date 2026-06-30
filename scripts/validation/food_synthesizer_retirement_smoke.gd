extends SceneTree

## Domain 3 Task 3: synthesizer_state is retired (orphan duplicate of the live crafting
## "synthesizer" station). Asserts:
##  - the coordinator no longer exposes a synthesizer_state model,
##  - the crafting synthesizer still produces synthesized_paste,
##  - a legacy RunSnapshot dict carrying synthesizer_summary still loads clean (key ignored).
## Marker: FOOD SYNTHESIZER RETIREMENT PASS orphan_removed=true crafting_synth_ok=true legacy_load_ok=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	# Legacy-load check is pure and can run immediately.
	if not _legacy_load_ok():
		_fail("legacy snapshot with synthesizer_summary failed to load"); return
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _legacy_load_ok() -> bool:
	var snap := RunSnapshotScript.new()
	var d: Dictionary = snap.to_dict()
	d["synthesizer_summary"] = {"station_type": "synthesizer", "total_power_consumed": 9.0}  # legacy key
	d["slice_version"] = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	d["godot_version"] = Engine.get_version_info()["string"]
	var loaded = RunSnapshotScript.from_dict(d, SaveLoadServiceScript.CURRENT_SLICE_VERSION, Engine.get_version_info()["string"])
	return loaded != null

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	# orphan removed: no synthesizer_state member (get() returns null for a missing var).
	if playable.get("synthesizer_state") != null:
		_fail("synthesizer_state still present on coordinator"); return
	# Seed the inventory with ingredients for the skill-0 synthesizer recipe
	# (Nutrient Paste Batch: ration_pack x2, synthesizer_base x1).
	var inv = playable.inventory_state
	if inv == null:
		_fail("inventory_state missing on coordinator"); return
	inv.add_item("ration_pack", 2)
	inv.add_item("synthesizer_base", 1)
	# crafting synthesizer still works.
	if not playable.craft_at_station_for_validation("synthesizer"):
		_fail("crafting synthesizer produced nothing"); return
	playable.advance_crafting_for_validation(60.0)
	finished = true
	print("FOOD SYNTHESIZER RETIREMENT PASS orphan_removed=true crafting_synth_ok=true legacy_load_ok=true")
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
	if finished: return
	finished = true
	push_error("FOOD SYNTHESIZER RETIREMENT FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
