extends SceneTree

## Cargo hold smoke. Section A (this task): CargoHoldControl strict in-range gate —
## off-tree / out-of-range refuses, in-range emits. Section B (Task 7) extends this
## file with the coordinator deposit/withdraw + save/load persistence flow.

const CargoHoldControlScript := preload("res://scripts/tools/cargo_hold_control.gd")

var _deposit_emits: int = 0
var _withdraw_cat: String = ""

func _init() -> void:
	await _run_section_a()
	# Section B is appended in Task 7; for now Section A alone prints the marker.
	print("CARGO HOLD SMOKE PASS section_a=true deposited=0 withdrew=0 persisted=false")
	quit()

func _run_section_a() -> void:
	var control = CargoHoldControlScript.new()
	control.cargo_deposit_requested.connect(func(_cid): _deposit_emits += 1)
	control.cargo_withdraw_requested.connect(func(_cid, cat): _withdraw_cat = cat)
	# Off-tree: strict gate refuses (no crash, returns false, no emit).
	assert(control.try_deposit(null) == false, "off-tree/no-player deposit refused")
	assert(_deposit_emits == 0, "no emit while refused")

	root.add_child(control)
	control.configure("test_carrier", Vector3.ZERO, 1.8)
	await process_frame
	# A player body in range.
	var player := CharacterBody3D.new()
	root.add_child(player)
	player.global_position = Vector3(0.5, 0.0, 0.0)   # within radius 1.8
	await process_frame
	assert(control.try_deposit(player) == true, "in-range deposit emits")
	assert(_deposit_emits == 1, "deposit emitted once")
	assert(control.try_withdraw(player, "part") == true, "in-range withdraw emits")
	assert(_withdraw_cat == "part", "withdraw carried the category")
	# Out of range.
	player.global_position = Vector3(100.0, 0.0, 0.0)
	await process_frame
	assert(control.try_deposit(player) == false, "out-of-range deposit refused")
	assert(_deposit_emits == 1, "no extra emit out of range")
