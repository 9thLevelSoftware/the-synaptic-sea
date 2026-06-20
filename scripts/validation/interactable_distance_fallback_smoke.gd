extends SceneTree

const InteractableScript := preload("res://scripts/interaction/interactable.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

var completed_count: int = 0

func _initialize() -> void:
	var interactable = InteractableScript.new()
	interactable.interaction_completed.connect(_on_interaction_completed)
	get_root().add_child(interactable)
	interactable.configure_from_objective(
		{
			"id": "test_objective",
			"sequence": 1,
			"type": "test_interaction",
			"room_id": "test_room",
		},
		Vector3.ZERO,
		1.8
	)

	var player = PlayerControllerScript.new()
	get_root().add_child(player)
	player.teleport_to(Vector3(0.0, 0.55, 0.0))

	if not interactable.try_interact(player):
		push_error("INTERACTABLE DISTANCE FALLBACK FAIL reason=nearby player could not interact without Area3D candidate cache")
		quit(1)
		return
	if completed_count != 1:
		push_error("INTERACTABLE DISTANCE FALLBACK FAIL reason=completion signal count=%d" % completed_count)
		quit(1)
		return
	print("INTERACTABLE DISTANCE FALLBACK PASS completed_count=%d" % completed_count)
	quit(0)

func _on_interaction_completed(_interaction_id: String, _objective_id: String, _sequence: int, _objective_type: String, _room_id: String, _step_id: String) -> void:
	completed_count += 1
