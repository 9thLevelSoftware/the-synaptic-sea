extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const DRAIN_WAIT_FRAMES: int = 90

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false

var oxygen_before_drain: float = 0.0
var oxygen_after_drain: float = 0.0

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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_validate_initial_state()
		"acquire_tool":
			_acquire_tool()
		"teleport_to_breach":
			_teleport_to_breach()
		"draining":
			_wait_for_drain()
		"check_drain":
			_check_drain_consequence()
		"verify_route_unchanged":
			_verify_route_unchanged()

func _validate_initial_state() -> void:
	if not playable.has_method("get_inventory_summary"):
		_fail("get_inventory_summary missing")
		return
	if not playable.has_method("acquire_tool_for_validation"):
		_fail("acquire_tool_for_validation missing")
		return
	if not playable.has_method("get_tool_pickup_node"):
		_fail("get_tool_pickup_node missing")
		return
	if not playable.has_method("teleport_player_to_breach_zone_for_validation"):
		_fail("teleport_player_to_breach_zone_for_validation missing")
		return
	var initial_inventory: Dictionary = playable.get_inventory_summary()
	if (initial_inventory.get("tool_ids") as Array).size() != 0:
		_fail("initial inventory should be empty, got %s" % str(initial_inventory))
		return
	var pickup: Node = playable.get_tool_pickup_node()
	if pickup == null:
		_fail("tool pickup node missing")
		return
	# Marker must exist on the pickup and be visible before acquisition.
	var marker: Variant = pickup.get("marker")
	if marker == null or not (marker is Node3D) or not (marker as Node3D).visible:
		_fail("tool pickup marker should be visible before acquisition, marker=%s" % str(marker))
		return
	# Before acquisition the status output must not advertise the pump.
	var initial_lines: PackedStringArray = playable.get_combined_system_status_lines()
	for initial_line in initial_lines:
		var initial_text: String = String(initial_line)
		if initial_text == "tool=portable_oxygen_pump" or initial_text.begins_with("drain_multiplier="):
			_fail("status output must not advertise pump markers before acquisition, got %s" % str(initial_lines))
			return
	phase = "acquire_tool"

func _acquire_tool() -> void:
	if not playable.acquire_tool_for_validation("portable_oxygen_pump"):
		_fail("acquire_tool_for_validation failed")
		return
	var inventory: Dictionary = playable.get_inventory_summary()
	var tool_ids: Array = inventory.get("tool_ids", []) as Array
	if tool_ids.size() != 1 or str(tool_ids[0]) != "portable_oxygen_pump":
		_fail("inventory should contain portable_oxygen_pump after acquisition, got %s" % str(inventory))
		return
	# Pickup marker should now be hidden.
	var pickup: Node = playable.get_tool_pickup_node()
	var marker: Variant = pickup.get("marker")
	if marker != null and (marker is Node3D) and (marker as Node3D).visible:
		_fail("tool pickup marker should be hidden after acquisition, marker.visible=true")
		return
	# HUD should include the carried tool status line.
	var lines: PackedStringArray = playable.get_combined_system_status_lines()
	var found_tool_line: bool = false
	var found_tool_marker: bool = false
	var found_drain_multiplier_marker: bool = false
	for line in lines:
		var line_text: String = String(line)
		if line_text == "Tool: Portable Oxygen Pump":
			found_tool_line = true
		elif line_text == "tool=portable_oxygen_pump":
			found_tool_marker = true
		elif line_text == "drain_multiplier=0.5":
			found_drain_multiplier_marker = true
	if not found_tool_line:
		_fail("HUD missing 'Tool: Portable Oxygen Pump' line, got %s" % str(lines))
		return
	if not found_tool_marker:
		_fail("HUD missing 'tool=portable_oxygen_pump' line, got %s" % str(lines))
		return
	if not found_drain_multiplier_marker:
		_fail("HUD missing 'drain_multiplier=0.5' line, got %s" % str(lines))
		return
	# Double pickup must be idempotent.
	if not playable.acquire_tool_for_validation("portable_oxygen_pump"):
		# Second acquire should be a no-op (return value indicates a fresh
		# acquisition; returning false on the second call is the contract).
		pass
	var inventory_after_second: Dictionary = playable.get_inventory_summary()
	var tool_ids_after_second: Array = inventory_after_second.get("tool_ids", []) as Array
	if tool_ids_after_second.size() != 1:
		_fail("inventory should still contain exactly one tool after double acquisition, got %s" % str(tool_ids_after_second))
		return
	phase = "teleport_to_breach"

func _teleport_to_breach() -> void:
	oxygen_before_drain = float(playable.get_oxygen_summary().get("oxygen", -1.0))
	if not playable.teleport_player_to_breach_zone_for_validation():
		_fail("could not teleport player into breach zone")
		return
	if not playable.is_player_in_breach_zone_for_validation():
		_fail("runtime proximity check did not see player inside breach zone after teleport")
		return
	phase = "draining"
	phase_frames = 0

func _wait_for_drain() -> void:
	phase_frames += 1
	if phase_frames >= DRAIN_WAIT_FRAMES:
		phase = "check_drain"

func _check_drain_consequence() -> void:
	oxygen_after_drain = float(playable.get_oxygen_summary().get("oxygen", -1.0))
	if oxygen_after_drain >= oxygen_before_drain:
		_fail("oxygen did not drain after teleport into breach (before=%s after=%s)" % [str(oxygen_before_drain), str(oxygen_after_drain)])
		return
	var oxygen_summary: Dictionary = playable.get_oxygen_summary()
	var drain_multiplier: float = float(oxygen_summary.get("drain_multiplier", -1.0))
	if absf(drain_multiplier - 0.5) > 0.001:
		_fail("drain_multiplier should be 0.5 with pump, got %s" % str(drain_multiplier))
		return
	var effective_drain_rate: float = float(oxygen_summary.get("effective_drain_rate", -1.0))
	if absf(effective_drain_rate - 3.0) > 0.001:
		_fail("effective_drain_rate should be 3.0 with pump (drain_rate=6, multiplier=0.5), got %s" % str(effective_drain_rate))
		return
	# The tool must not alter route/extraction state.
	var route_summary: Dictionary = playable.get_route_control_summary()
	if bool(route_summary.get("extraction_unlocked", true)):
		_fail("tool must not unlock extraction")
		return
	phase = "verify_route_unchanged"

func _verify_route_unchanged() -> void:
	var route_summary: Dictionary = playable.get_route_control_summary()
	if bool(route_summary.get("extraction_unlocked", true)):
		_fail("tool must not unlock extraction")
		return
	finished = true
	var inventory: Dictionary = playable.get_inventory_summary()
	var tool_ids: Array = inventory.get("tool_ids", []) as Array
	var drain_multiplier: float = float(playable.get_oxygen_summary().get("drain_multiplier", -1.0))
	print("MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=%s drain_multiplier=%s" % [
		str(tool_ids.size() == 1 and str(tool_ids[0]) == "portable_oxygen_pump").to_lower(),
		str(drain_multiplier),
	])
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
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE INVENTORY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)