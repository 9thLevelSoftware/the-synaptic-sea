extends SceneTree

## Pass marker: EXTINGUISHER RECHARGE PORT PASS powered_refills=true unpowered_noop=true

const ExtinguisherStateScript := preload("res://scripts/systems/extinguisher_state.gd")
const PortScript := preload("res://scripts/tools/extinguisher_recharge_port.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var ext = ExtinguisherStateScript.new()
	ext.configure({"charge": 10.0, "max_charge": 100.0, "recharge_per_second": 20.0})
	var player := Node3D.new(); get_root().add_child(player); player.position = Vector3.ZERO
	var port = PortScript.new()
	port.configure(ext, Vector3.ZERO, 1.8)
	get_root().add_child(port)
	await process_frame
	port.set_validation_player_in_range(player)

	# unpowered: no refill.
	port.set_powered(false)
	var before: float = ext.charge
	port._process(1.0)
	if absf(ext.charge - before) > 0.001:
		_fail("unpowered port must not recharge"); return

	# powered: refills.
	port.set_powered(true)
	port._process(1.0)
	if ext.charge <= before:
		_fail("powered port should refill charge"); return

	print("EXTINGUISHER RECHARGE PORT PASS powered_refills=true unpowered_noop=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("EXTINGUISHER RECHARGE PORT FAIL reason=%s" % reason)
	quit(1)
