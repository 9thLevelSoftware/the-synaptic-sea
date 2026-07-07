extends SceneTree

## Tranche 3 (audit critic gap): every bundled interaction smoke bypasses
## physics via set_validation_player_in_range(), so the REAL Area3D path —
## body_entered -> candidate_player -> try_interact — had zero automated
## coverage. This smoke never touches the seam: a real PlayerController is
## warped into the interactable's r=1.8 sphere and the physics engine must
## set candidate_player through the body_entered SIGNAL alone.
##
## Assertion note: try_interact() has a distance fallback
## (_is_player_in_direct_range), so success there proves nothing about the
## signal — the proof is candidate_player itself, which ONLY
## _on_body_entered / _on_body_exited (and the seam, unused here) write.
##
## Pass marker:
## INTERACTABLE BODY ENTERED PASS far_null=true entered=true interact=true exited_cleared=true

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const InteractableScript := preload("res://scripts/interaction/interactable.gd")

const FAR_POSITION := Vector3(10.0, 0.5, 10.0)
const SETTLE_FRAMES: int = 30
const OVERLAP_FRAMES: int = 10

var player: PlayerController
var interactable: Interactable
var phase: String = "settle_far"
var frame_count: int = 0
var phase_frame: int = 0
var finished: bool = false
var completed_args: Array = []

func _initialize() -> void:
	# Floor so the capsule settles instead of falling forever (pattern from
	# player_gravity_floor_snap_smoke).
	var floor_body := StaticBody3D.new()
	floor_body.name = "TestFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	var floor_shape_node := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40.0, 0.25, 40.0)
	floor_shape_node.shape = floor_shape
	floor_body.add_child(floor_shape_node)
	get_root().add_child(floor_body)

	interactable = InteractableScript.new()
	interactable.configure_from_objective(
		{"id": "smoke_obj", "sequence": 1, "type": "restore_systems", "room_id": "room_a"},
		Vector3(0.0, 0.5, 0.0))
	interactable.interaction_completed.connect(_on_interaction_completed)
	get_root().add_child(interactable)

	player = PlayerControllerScript.new()
	get_root().add_child(player)
	player.teleport_to(FAR_POSITION + Vector3(0.0, 3.5, 0.0))
	physics_frame.connect(_on_physics_frame)

func _on_interaction_completed(interaction_id: String, _objective_id: String, sequence: int, _objective_type: String, _room_id: String, _step_id: String) -> void:
	completed_args = [interaction_id, sequence]

func _on_physics_frame() -> void:
	if finished:
		return
	frame_count += 1
	phase_frame += 1
	if frame_count > 600:
		_fail("timeout in phase %s" % phase)
		return
	match phase:
		"settle_far":
			if phase_frame < SETTLE_FRAMES:
				return
			# Far from the sphere: the signal path must NOT have fired.
			if interactable.candidate_player != null:
				_fail("candidate_player set while player is %.1fm away" % FAR_POSITION.length())
				return
			# Warp INTO the r=1.8 sphere; overlap detection is engine-driven.
			player.teleport_to(Vector3(0.0, 0.5, 0.0))
			_enter_phase("await_entered")
		"await_entered":
			if interactable.candidate_player == null:
				if phase_frame > OVERLAP_FRAMES * 6:
					_fail("body_entered never fired after %d physics frames inside the sphere" % phase_frame)
				return
			if interactable.candidate_player != player:
				_fail("candidate_player is not the player (got %s)" % str(interactable.candidate_player))
				return
			# Signal path proven. Interact through the production entry point.
			if not interactable.try_interact(player):
				_fail("try_interact failed with candidate_player set")
				return
			if completed_args.is_empty() or str(completed_args[0]) != "objective:01:smoke_obj":
				_fail("interaction_completed did not fire with the expected id (got %s)" % str(completed_args))
				return
			# Warp far away; body_exited must clear the candidate.
			player.teleport_to(FAR_POSITION)
			_enter_phase("await_exited")
		"await_exited":
			if interactable.candidate_player != null:
				if phase_frame > OVERLAP_FRAMES * 6:
					_fail("body_exited never cleared candidate_player after %d frames" % phase_frame)
				return
			finished = true
			print("INTERACTABLE BODY ENTERED PASS far_null=true entered=true interact=true exited_cleared=true")
			quit(0)

func _enter_phase(next_phase: String) -> void:
	phase = next_phase
	phase_frame = 0

func _fail(reason: String) -> void:
	finished = true
	push_error("INTERACTABLE BODY ENTERED FAIL reason=%s" % reason)
	quit(1)
