extends SceneTree

## Node-level smoke for BridgeTerminal: strict in-range gate + login_requested signal.
## Mirrors dock_breach_smoke's structure (real Area3D in a real tree).

const BridgeTerminalScript := preload("res://scripts/tools/bridge_terminal.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

var _fired_id: String = ""
var _done: bool = false

func _on_login(ship_id: String) -> void:
	_fired_id = ship_id

func _initialize() -> void:
	process_frame.connect(_run)

func _run() -> void:
	if _done:
		return
	_done = true

	var term = BridgeTerminalScript.new()
	root.add_child(term)
	term.configure("ship_test", Vector3.ZERO, 1.8)
	term.login_requested.connect(_on_login)

	var player = PlayerControllerScript.new()
	root.add_child(player)

	# Out of range -> refused, no signal.
	player.teleport_to(Vector3(10.0, 0.0, 0.0))
	assert(term.try_login(player) == false, "out-of-range login refused")
	assert(_fired_id == "", "no signal out of range")

	# In range -> consumed + signal carries the ship id.
	player.teleport_to(Vector3.ZERO)
	assert(term.try_login(player) == true, "in-range login consumed")
	assert(_fired_id == "ship_test", "login_requested fired with ship id")

	print("BRIDGE TERMINAL SMOKE PASS ship=%s" % _fired_id)
	quit()
