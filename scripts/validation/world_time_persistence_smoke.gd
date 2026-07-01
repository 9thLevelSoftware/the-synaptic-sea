extends SceneTree

## Live Persistent Ships Phase 1: verifies world_time accumulates and round-trips
## through both WorldSnapshot and ShipInstance summaries.
##
## Assertions:
##   1. advances            – world_time grows by > 4.0 across five _process(1.0) calls.
##   2. world_snapshot_roundtrip – WorldSnapshot.world_time = 123.5 survives to_dict/from_dict.
##   3. ship_timestamp_roundtrip – ShipInstance.last_sim_time = 77.0 survives get/apply_summary.
##
## Marker: WORLD TIME PASS advances=true world_snapshot_roundtrip=true ship_timestamp_roundtrip=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable  # PlayableGeneratedShip — typed as Variant to avoid class_name headless issue
var frame_count: int = 0
var finished: bool = false

# Results accumulate; all three must be true before we print PASS.
var result_advances: bool = false
var result_ws_roundtrip: bool = false
var result_ship_roundtrip: bool = false

func _initialize() -> void:
	# --- Assertion 2: WorldSnapshot round-trip (pure data, no scene required) ---
	var godot_ver: String = Engine.get_version_info()["string"]
	var ws = WorldSnapshotScript.new()
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = godot_ver
	ws.world_time = 123.5
	var ws_dict: Dictionary = ws.to_dict()
	var ws_rebuilt = WorldSnapshotScript.from_dict(ws_dict, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_ver)
	if ws_rebuilt == null:
		_fail("world_snapshot_roundtrip: from_dict returned null")
		return
	if abs(float(ws_rebuilt.world_time) - 123.5) > 0.001:
		_fail("world_snapshot_roundtrip: world_time not restored (got %s)" % str(ws_rebuilt.world_time))
		return
	result_ws_roundtrip = true

	# --- Assertion 3: ShipInstance.last_sim_time round-trip (pure data) ---
	var bp = ShipBlueprintScript.new(ShipBlueprintScript.Size.SMALL, ShipBlueprintScript.Condition.DAMAGED, 1337)
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), bp.condition, bp.seed_value)
	var inst = ShipInstanceScript.create("ship_smoke", "3:1:9", bp, mgr, null)
	if inst == null:
		_fail("ship_timestamp_roundtrip: create returned null")
		return
	inst.last_sim_time = 77.0
	var summary: Dictionary = inst.get_summary()
	if not summary.has("last_sim_time"):
		_fail("ship_timestamp_roundtrip: last_sim_time absent from summary when nonzero")
		return
	var fresh = ShipInstanceScript.create("", "", ShipBlueprintScript.new(), ShipSystemsManagerScript.new(), null)
	if not fresh.apply_summary(summary):
		_fail("ship_timestamp_roundtrip: apply_summary returned false")
		return
	if abs(float(fresh.last_sim_time) - 77.0) > 0.001:
		_fail("ship_timestamp_roundtrip: last_sim_time not restored (got %s)" % str(fresh.last_sim_time))
		return
	result_ship_roundtrip = true

	# Also verify zero last_sim_time is omitted from summary (additive discipline).
	var zero_inst = ShipInstanceScript.create("ship_zero", "0:0:0", ShipBlueprintScript.new(), null, null)
	if zero_inst.get_summary().has("last_sim_time"):
		_fail("ship_timestamp_roundtrip: last_sim_time=0.0 should be omitted from summary")
		return

	# --- Assertion 1: advances — boot main scene, wait for playable_started ---
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("advances: could not instantiate main scene")
		return
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
			_fail("advances: playable not ready after %d frames" % frame_count)
		return
	_validate_advances()

func _validate_advances() -> void:
	finished = true  # prevent re-entry
	var before: float = playable.world_time
	for _i: int in range(5):
		playable._process(1.0)
	var after: float = playable.world_time
	var grew_by: float = after - before
	if grew_by <= 4.0:
		_fail("advances: world_time grew by %.4f (expected > 4.0)" % grew_by)
		return
	result_advances = true

	if result_advances and result_ws_roundtrip and result_ship_roundtrip:
		print("WORLD TIME PASS advances=true world_snapshot_roundtrip=true ship_timestamp_roundtrip=true")
		_cleanup_and_quit(0)
	else:
		_fail("one or more assertions failed: advances=%s ws_roundtrip=%s ship_roundtrip=%s" % [
			str(result_advances), str(result_ws_roundtrip), str(result_ship_roundtrip)])

func _find_playable(node: Node) -> Object:
	if node.get_script() != null and node.has_method("_process") and node.has_method("_build_world_snapshot"):
		return node
	for child: Node in node.get_children():
		var found: Object = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("WORLD TIME FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
