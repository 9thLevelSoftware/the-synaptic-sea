extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 900
const REQUIRED_ARCHETYPES: int = 5
const REQUIRED_AMMO: int = 2

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false
var baseline_target: Dictionary = {}
var saved_attack: Dictionary = {}
var saved_target_summary: Dictionary = {}
var ammo_before: int = 0

func _initialize() -> void:
	var bootstrap := SaveLoadService.new()
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
	phase_frames += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_validate_ready_state()
		"attack":
			_drive_attack()
		"settle_detection":
			_wait_for_detection()
		"save_load":
			_round_trip_save_load()
		"verify_restore":
			_verify_restore()

func _validate_ready_state() -> void:
	if playable.threat_manager == null:
		_fail("threat_manager missing")
		return
	var summary: Dictionary = playable.threat_manager.get_summary()
	var threats: Array = summary.get("threats", []) as Array
	var archetypes: Dictionary = {}
	for threat_variant in threats:
		if threat_variant is Dictionary:
			archetypes[str((threat_variant as Dictionary).get("archetype_id", ""))] = true
	if threats.size() < REQUIRED_ARCHETYPES:
		_fail("expected at least %d threats, got %d" % [REQUIRED_ARCHETYPES, threats.size()])
		return
	if archetypes.size() < REQUIRED_ARCHETYPES:
		_fail("expected at least %d archetypes, got %d" % [REQUIRED_ARCHETYPES, archetypes.size()])
		return
	baseline_target = threats[0] if not threats.is_empty() and threats[0] is Dictionary else {}
	if baseline_target.is_empty():
		_fail("could not capture baseline target summary")
		return
	if not playable.equip_for_validation("flare_pistol"):
		_fail("equip_for_validation(flare_pistol) failed")
		return
	ammo_before = playable.inventory_state.get_quantity("flare_round")
	playable.inventory_state.add_item("flare_round", REQUIRED_AMMO)
	if playable.inventory_state.get_quantity("flare_round") < ammo_before + REQUIRED_AMMO:
		_fail("could not seed flare ammo")
		return
	phase = "attack"
	phase_frames = 0

func _drive_attack() -> void:
	var result: Dictionary = playable._attack_with_equipped_weapon()
	if not bool(result.get("ok", false)):
		_fail("weapon attack failed: %s" % str(result))
		return
	if str(result.get("weapon_id", "")) != "flare_pistol":
		_fail("expected flare_pistol attack, got %s" % str(result.get("weapon_id", "")))
		return
	if int(result.get("ammo_remaining", -1)) != ammo_before + REQUIRED_AMMO - 1:
		_fail("ammo did not decrement after attack: %s" % str(result))
		return
	if str(result.get("target_id", "")).is_empty():
		_fail("attack returned empty target_id")
		return
	phase = "settle_detection"
	phase_frames = 0

func _wait_for_detection() -> void:
	var summary: Dictionary = playable.threat_manager.get_summary()
	if not (summary.get("last_attack_result", {}) is Dictionary):
		if phase_frames > 120:
			_fail("threat_manager never recorded attack result")
		return
	var last_attack: Dictionary = summary.get("last_attack_result", {})
	var target_id: String = str(last_attack.get("target_id", ""))
	var target_summary: Dictionary = _find_target_summary(summary, target_id)
	if target_summary.is_empty():
		if phase_frames > 120:
			_fail("could not find attacked target in threat summary")
		return
	var detected_count: int = int(playable.threat_manager.get_detected_threat_count())
	var awareness: float = float(summary.get("awareness_indicator", 0.0))
	var target_health: float = float(target_summary.get("health", 0.0))
	var baseline_health: float = float(baseline_target.get("health", target_health))
	if awareness >= 0.95 and detected_count > 0 and target_health < baseline_health:
		saved_attack = last_attack.duplicate(true)
		saved_target_summary = target_summary.duplicate(true)
		phase = "save_load"
		phase_frames = 0
		return
	if phase_frames > 180:
		_fail("combat never elevated awareness/detection enough: awareness=%.2f detected=%d target_health=%.2f baseline=%.2f" % [awareness, detected_count, target_health, baseline_health])

func _round_trip_save_load() -> void:
	if not playable.save_world_for_validation():
		_fail("save_world_for_validation failed")
		return
	if not playable.load_world_for_validation():
		_fail("load_world_for_validation failed")
		return
	phase = "verify_restore"
	phase_frames = 0

func _verify_restore() -> void:
	var summary: Dictionary = playable.threat_manager.get_summary()
	var restored_attack: Dictionary = summary.get("last_attack_result", {}) if summary.get("last_attack_result", {}) is Dictionary else {}
	if restored_attack.is_empty():
		_fail("restored attack summary missing")
		return
	if str(restored_attack.get("weapon_id", "")) != "flare_pistol":
		_fail("restored attack weapon mismatch: %s" % str(restored_attack))
		return
	if str(restored_attack.get("target_id", "")) != str(saved_attack.get("target_id", "")):
		_fail("restored target_id mismatch: %s vs %s" % [str(restored_attack.get("target_id", "")), str(saved_attack.get("target_id", ""))])
		return
	var target_summary: Dictionary = _find_target_summary(summary, str(saved_attack.get("target_id", "")))
	if target_summary.is_empty():
		_fail("restored target summary missing")
		return
	if absf(float(target_summary.get("health", 0.0)) - float(saved_target_summary.get("health", 0.0))) > 0.01:
		_fail("restored target health mismatch: %.2f vs %.2f" % [float(target_summary.get("health", 0.0)), float(saved_target_summary.get("health", 0.0))])
		return
	if absf(float(target_summary.get("memory_remaining", 0.0)) - float(saved_target_summary.get("memory_remaining", 0.0))) > 0.25:
		_fail("restored threat memory drift too large: %.2f vs %.2f" % [float(target_summary.get("memory_remaining", 0.0)), float(saved_target_summary.get("memory_remaining", 0.0))])
		return
	if target_summary.get("world_position", []) != saved_target_summary.get("world_position", []):
		_fail("restored world_position mismatch: %s vs %s" % [str(target_summary.get("world_position", [])), str(saved_target_summary.get("world_position", []))])
		return
	finished = true
	print("MAIN PLAYABLE COMBAT ENCOUNTER PASS archetypes=%d awareness=%.2f ammo_spent=1 memory_restored=true" % [
		_unique_archetype_count(summary),
		float(summary.get("awareness_indicator", 0.0)),
	])
	_cleanup_and_quit(0)

func _find_target_summary(summary: Dictionary, target_id: String) -> Dictionary:
	var threats: Array = summary.get("threats", []) as Array
	for threat_variant in threats:
		if threat_variant is Dictionary and str((threat_variant as Dictionary).get("instance_id", "")) == target_id:
			return (threat_variant as Dictionary).duplicate(true)
	return {}

func _unique_archetype_count(summary: Dictionary) -> int:
	var seen: Dictionary = {}
	var threats: Array = summary.get("threats", []) as Array
	for threat_variant in threats:
		if threat_variant is Dictionary:
			seen[str((threat_variant as Dictionary).get("archetype_id", ""))] = true
	return seen.size()

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
	push_error("MAIN PLAYABLE COMBAT ENCOUNTER FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	var cleanup := SaveLoadService.new()
	cleanup.delete_current_run()
	quit(code)
