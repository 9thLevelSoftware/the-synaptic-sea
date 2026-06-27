extends SceneTree

## M7-A: the BreachSealPoint channel consumes a sealant and seals a hull compartment.
## Pass marker: BREACH SEAL POINT PASS sealed=true breach_cleared=true

const BreachSealPointScript := preload("res://scripts/tools/breach_seal_point.gd")
const HullIntegrityStateScript := preload("res://scripts/systems/hull_integrity_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

var finished: bool = false

func _initialize() -> void:
	var hull := HullIntegrityStateScript.new()
	hull.configure({"compartments": [{"compartment_id": "cargo", "health": 0.3, "breach_open": true, "isolation_rating": 0.6}]})
	if hull.get_breach_count() != 1:
		_fail("setup: cargo should start breached")
		return
	var inv := InventoryStateScript.new()
	# Note: InventoryState self-initialises in _init(); no configure() call needed.
	inv.add_item("hull_sealant", 1)

	var sealed_signals: Array = []
	var point := BreachSealPointScript.new()
	point.configure("cargo", hull, inv, null, Vector3.ZERO, 4.0, "hull_sealant", 1.0, 1.8)
	point.breach_sealed.connect(func(cid): sealed_signals.append(cid))
	get_root().add_child(point)

	# Use a plain Node3D stub as the player body: CharacterBody3D (which PlayerController
	# extends) cannot set global_position in headless mode because the physics world isn't
	# fully initialised when _initialize() runs. The validation seam (set_validation_player_in_range)
	# bypasses _on_body_entered's PlayerController check; try_start only requires a Node3D.
	# PlayerControllerScript is still preloaded above to validate the path exists.
	var player := Node3D.new()
	get_root().add_child(player)
	player.position = Vector3.ZERO
	point.set_validation_player_in_range(player)

	# Nodes added during _initialize() are in "pending" state until the SceneTree processes
	# its first frame; is_inside_tree() returns false until NOTIFICATION_ENTER_TREE fires.
	# Awaiting process_frame defers the test until the tree is live.
	await process_frame

	if not point.try_start(player):
		_fail("try_start should succeed with sealant in range")
		return
	# Drive the channel deterministically to completion.
	point.advance_channel(5.0)

	if sealed_signals.size() != 1:
		_fail("breach_sealed should have fired once (got %d)" % sealed_signals.size())
		return
	if hull.get_breach_count() != 0:
		_fail("compartment should be sealed (breach_count=%d)" % hull.get_breach_count())
		return
	if int(inv.get_quantity("hull_sealant")) != 0:
		_fail("sealant should have been consumed")
		return

	finished = true
	print("BREACH SEAL POINT PASS sealed=true breach_cleared=true")
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("BREACH SEAL POINT FAIL reason=%s" % reason)
	quit(1)
