extends SceneTree

## ADR-0070 main-scene smoke: on the live playable ship the player wears the
## survivor_v1 visual (capsule hidden), equipping a hardsuit through the real
## EquipmentState shows the suit plates on the model, and — on the AWAY branch
## (boarded derelict, away_from_start=true) — scripted movement still animates
## and faces the model, because the seam is fed from PlayerController's
## physics tick rather than the coordinator's branched _process.
##
## Pass marker:
##   MAIN PLAYABLE PLAYER VISUAL PASS mounted=true equip_sync=true away_ticks=true walk=true facing=true attack_swing=true unarmed_no_swing=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const CharacterVisualScript := preload("res://scripts/player/character_visual.gd")
## Budgets are PHYSICS frames: movement, the walk logical and the facing lerp
## all advance in PlayerController._physics_process, so counting process
## frames would make the gate host-speed dependent.
const TIMEOUT_FRAMES: int = 600
const WALK_BUDGET_FRAMES: int = 180

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var _stage: int = 0
var _facing_before: float = 0.0
var _move_direction: Vector3 = Vector3(1.0, 0.0, 0.0)
var _expected_yaw: float = PI * 0.5


func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	if frame_count > TIMEOUT_FRAMES * 3:
		_fail("smoke timed out at stage %d" % _stage)
		return
	match _stage:
		0:
			_stage_mounted()
		1:
			_stage_drive_away()
		2:
			_stage_check_walk()


func _stage_mounted() -> void:
	var player: PlayerController = playable.player
	if player == null or not player.has_character_visual():
		_fail("player visual not mounted on the live ship")
		return
	if player.marker == null or player.marker.visible:
		_fail("capsule marker still visible with a mounted visual")
		return
	if playable.equipment_state == null or playable.threat_manager == null:
		_fail("equipment_state / threat_manager missing")
		return
	# Real equipment path: EquipmentState.equip() through the coordinator's
	# provider; the visual must pick it up on the next physics tick.
	playable.threat_manager.threats.clear()
	var res: Dictionary = playable.equipment_state.equip("hardsuit")
	if not bool(res.get("ok", false)):
		_fail("could not equip hardsuit through EquipmentState: %s" % str(res))
		return
	_stage = 1


func _stage_drive_away() -> void:
	var player: PlayerController = playable.player
	if not player.character_visual.is_equipment_node_visible("Equip_Hardsuit_Chest") \
			or not player.character_visual.is_equipment_node_visible("Equip_Helmet"):
		# One more physics frame may be needed; give it a bounded number of tries.
		if frame_count > TIMEOUT_FRAMES * 2:
			_fail("hardsuit equip did not sync to the visual")
		return
	# Board a derelict: the coordinator's away branch early-returns before the
	# home branch; the visual must keep animating regardless.
	playable.away_from_start = true
	player.character_visual.rotation.y = 0.0
	_facing_before = player.character_visual.get_facing_yaw()
	# Pick the cardinal direction with the most clearance so the body walks
	# long enough for the facing lerp to converge (layout-independent).
	_move_direction = _clearest_cardinal_direction(player)
	_expected_yaw = atan2(_move_direction.x, _move_direction.z)
	player.set_scripted_move_direction(_move_direction)
	_stage = 2
	frame_count = 0


func _stage_check_walk() -> void:
	# The start room is small: scripted +X travel reaches a wall within a few
	# physics ticks, so sample every frame and accept the first frame in which
	# the body is actually moving and the visual reflects it.
	var player: PlayerController = playable.player
	var visual: CharacterVisualScript = player.character_visual
	var moving: bool = player.is_moving()
	var walk_ok: bool = moving and visual.get_current_logical() == "walk" and visual.get_current_animation() == "walk"
	var facing_ok: bool = absf(angle_difference(visual.get_facing_yaw(), _expected_yaw)) < 0.05
	if not (walk_ok and facing_ok):
		if frame_count > WALK_BUDGET_FRAMES:
			player.clear_scripted_move_direction()
			_fail("walk/facing not observed on the away branch within %d physics frames (dir=%s moving=%s logical=%s anim=%s yaw=%.3f expected=%.3f before=%.3f)" % [
				WALK_BUDGET_FRAMES,
				str(_move_direction), str(moving), visual.get_current_logical(), visual.get_current_animation(), visual.get_facing_yaw(), _expected_yaw, _facing_before])
		return
	player.clear_scripted_move_direction()
	# Attack through the real coordinator path. Unarmed (the live start has no
	# hand-slot item) the attack is rejected with weapon_not_equipped and the
	# body must NOT swing a weapon it is not holding; with a crowbar equipped
	# through the real EquipmentState the swing clip plays.
	var unarmed: Dictionary = playable._attack_with_equipped_weapon()
	var unarmed_anim: String = visual.get_current_animation()
	var unarmed_no_swing: bool = str(unarmed.get("reason", "")) == "weapon_not_equipped" \
		and unarmed_anim != "melee_swing" and unarmed_anim != "aim_ranged"
	if not unarmed_no_swing:
		_fail("unarmed attack should be rejected without a swing (anim=%s result=%s)" % [unarmed_anim, str(unarmed)])
		return
	var equip_res: Dictionary = playable.equipment_state.equip("crowbar")
	if not bool(equip_res.get("ok", false)):
		_fail("could not equip crowbar through EquipmentState: %s" % str(equip_res))
		return
	var attack: Dictionary = playable._attack_with_equipped_weapon()
	var attack_swing: bool = visual.get_current_animation() == "melee_swing" or visual.get_current_animation() == "aim_ranged"
	if not attack_swing:
		_fail("attack did not play a swing/aim clip (anim=%s result=%s)" % [visual.get_current_animation(), str(attack)])
		return
	finished = true
	print("MAIN PLAYABLE PLAYER VISUAL PASS mounted=true equip_sync=true away_ticks=true walk=true facing=true attack_swing=true unarmed_no_swing=true")
	_cleanup_and_quit(0)


func _clearest_cardinal_direction(player: PlayerController) -> Vector3:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var origin: Vector3 = player.global_position + Vector3(0.0, 0.8, 0.0)
	var best: Vector3 = Vector3(1.0, 0.0, 0.0)
	var best_distance: float = -1.0
	for direction in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 6.0)
		query.exclude = [player.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		var distance: float = 6.0 if hit.is_empty() else origin.distance_to(hit.get("position", origin))
		if distance > best_distance:
			best_distance = distance
			best = direction
	return best


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
	push_error("MAIN PLAYABLE PLAYER VISUAL FAIL reason=%s" % reason)
	_cleanup_and_quit(1)


func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
