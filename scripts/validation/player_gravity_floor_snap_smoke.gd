extends SceneTree

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

var player: PlayerController
var frame_count: int = 0

func _initialize() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "TestFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	var floor_shape_node: CollisionShape3D = CollisionShape3D.new()
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(20.0, 0.25, 20.0)
	floor_shape_node.shape = floor_shape
	floor_body.add_child(floor_shape_node)
	get_root().add_child(floor_body)

	player = PlayerControllerScript.new()
	get_root().add_child(player)
	player.teleport_to(Vector3(0.0, 4.0, 0.0))
	physics_frame.connect(_on_physics_frame)

func _on_physics_frame() -> void:
	frame_count += 1
	if frame_count < 120:
		return
	var expected_floor_top: float = 0.125
	var max_expected_player_y: float = expected_floor_top + 0.2
	if player.global_position.y > max_expected_player_y:
		push_error(
			"PLAYER GRAVITY FLOOR SNAP FAIL reason=player did not settle onto floor player_y=%.3f max_expected=%.3f"
			% [player.global_position.y, max_expected_player_y]
		)
		quit(1)
		return
	if player.global_position.y < expected_floor_top - 0.05:
		push_error(
			"PLAYER GRAVITY FLOOR SNAP FAIL reason=player sank through floor player_y=%.3f floor_top=%.3f"
			% [player.global_position.y, expected_floor_top]
		)
		quit(1)
		return
	print("PLAYER GRAVITY FLOOR SNAP PASS player_y=%.3f frames=%d" % [player.global_position.y, frame_count])
	quit(0)
