extends SceneTree

## Pass marker: FIRE SUPPRESSION POINT PASS extinguished=true charge_spent=true gated=true

const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
const ExtinguisherStateScript := preload("res://scripts/systems/extinguisher_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const FireSuppressionPointScript := preload("res://scripts/tools/fire_suppression_point.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var fire = FireSuppressionStateScript.new()
	fire.configure({"compartments": ["engineering"], "adjacency": {}})
	var ext = ExtinguisherStateScript.new()
	ext.configure({"charge": 100.0, "max_charge": 100.0, "charge_cost_per_use": 34.0})
	var inv = InventoryStateScript.new()
	inv.add_item("fire_extinguisher", 1)

	var player := Node3D.new()
	get_root().add_child(player)
	player.position = Vector3.ZERO

	var point = FireSuppressionPointScript.new()
	point.configure("engineering", fire, ext, inv, null, Vector3.ZERO, 4.0, "fire_extinguisher", 1.8)
	get_root().add_child(point)
	await process_frame

	# gated: not burning yet -> soft-block consume (true) but no channel.
	if not point.try_start(player):
		_fail("try_start should consume when not burning"); return
	if point.channeling:
		_fail("try_start must not channel when compartment is not burning"); return

	fire.ignite("engineering", 1.0)
	var charge_before: float = ext.charge
	if not point.try_start(player):
		_fail("try_start should succeed: burning, in range, tool + charge present"); return
	if not point.channeling:
		_fail("try_start should channel when burning with tool + charge"); return
	point.advance_channel(10.0)
	if fire.is_burning("engineering"):
		_fail("fire should be extinguished after the channel completes"); return
	if ext.charge >= charge_before:
		_fail("extinguisher charge should be spent on completion"); return

	print("FIRE SUPPRESSION POINT PASS extinguished=true charge_spent=true gated=true")
	_cleanup(0)

func _cleanup(code: int) -> void:
	quit(code)

func _fail(reason: String) -> void:
	push_error("FIRE SUPPRESSION POINT FAIL reason=%s" % reason)
	quit(1)
