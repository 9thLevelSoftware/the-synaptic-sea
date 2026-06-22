extends SceneTree

## DockPortBarrier breach interactable (pure node test — no main scene).
## Interaction runs inside a process_frame callback (NOT _initialize): nodes added
## via get_root().add_child() are only is_inside_tree()==true once the main loop is
## iterating, which the barrier's strict range gate (matching repair_point.gd) requires.

const DockPortBarrierScript := preload("res://scripts/tools/dock_port_barrier.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

var _done: bool = false

func _initialize() -> void:
	process_frame.connect(_run)

func _run() -> void:
	if _done:
		return
	_done = true

	var ok := true
	var msg := ""

	# Intact barrier: one try_start opens immediately.
	var intact = DockPortBarrierScript.new()
	get_root().add_child(intact)
	intact.configure("m1", "intact", null, Vector3.ZERO, 6.0, 1.8)
	var player := PlayerControllerScript.new()
	get_root().add_child(player)
	player.teleport_to(Vector3.ZERO)
	if not intact.try_start(player) or not intact.opened:
		ok = false; msg = "intact barrier did not open on one interact"

	# Broken barrier: try_start begins a channel (not yet open); channel completes to open.
	if ok:
		var broken = DockPortBarrierScript.new()
		get_root().add_child(broken)
		broken.configure("m2", "broken", null, Vector3.ZERO, 6.0, 1.8)
		if not broken.try_start(player):
			ok = false; msg = "broken barrier did not start channel"
		elif broken.opened:
			ok = false; msg = "broken barrier opened without channel"
		else:
			broken.advance_channel(10.0)   # exceed breach_seconds
			if not broken.opened:
				ok = false; msg = "broken barrier did not open after channel"
		broken.free()

	intact.free()
	player.free()

	if ok:
		print("DOCK BREACH PASS intact_instant=true broken_channel=true")
		quit(0)
	else:
		push_error("DOCK BREACH FAIL reason=%s" % msg)
		quit(1)
