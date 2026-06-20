extends SceneTree

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const IsoCameraRigScript := preload("res://scripts/camera/iso_camera_rig.gd")
const InteractableScript := preload("res://scripts/interaction/interactable.gd")

var interaction_count: int = 0
var finished: bool = false


func _initialize() -> void:
	var root_node: Node3D = Node3D.new()
	root_node.name = "PlayableComponentSmokeRoot"
	get_root().add_child(root_node)

	var player = PlayerControllerScript.new()
	player.name = "SmokePlayer"
	root_node.add_child(player)
	player.teleport_to(Vector3(1.0, 0.0, 2.0))

	var camera_rig = IsoCameraRigScript.new()
	camera_rig.name = "SmokeCameraRig"
	root_node.add_child(camera_rig)
	camera_rig.set_follow_target(player)
	camera_rig.make_current()

	var interactable = InteractableScript.new()
	interactable.name = "SmokeInteractable"
	interactable.interaction_completed.connect(_on_interaction_completed)
	root_node.add_child(interactable)
	interactable.configure_from_objective(
		{
			"id": "smoke_objective",
			"sequence": 1,
			"type": "smoke_interaction",
			"room_id": "smoke_room",
		},
		Vector3(1.0, 0.0, 2.0),
		1.8
	)
	interactable.set_validation_player_in_range(player)
	var completed: bool = interactable.try_interact(player)

	if not completed or interaction_count != 1:
		push_error("component smoke failed: immediate interaction did not complete")
		quit(1)
		return

	physics_frame.connect(_on_first_physics_frame, CONNECT_ONE_SHOT)


func _on_first_physics_frame() -> void:
	if finished:
		return
	finished = true

	var player: Node = get_root().get_node_or_null("PlayableComponentSmokeRoot/SmokePlayer")
	var camera_rig: Node = get_root().get_node_or_null("PlayableComponentSmokeRoot/SmokeCameraRig")

	if player == null or player.marker == null:
		push_error("component smoke failed: player marker missing")
		quit(1)
		return
	if player.collision_shape == null or player.collision_shape.shape == null:
		push_error("component smoke failed: player collision missing")
		quit(1)
		return
	if camera_rig == null or camera_rig.camera == null or not camera_rig.camera.current:
		push_error("component smoke failed: camera not current")
		quit(1)
		return

	print("PLAYABLE COMPONENT SMOKE PASS player=true camera=true interaction=true")
	quit(0)


func _on_interaction_completed(_interaction_id: String, _objective_id: String, _sequence: int, _objective_type: String, _room_id: String) -> void:
	interaction_count += 1
