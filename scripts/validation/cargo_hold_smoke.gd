extends SceneTree

## Cargo hold smoke. Section A (this task): CargoHoldControl strict in-range gate —
## off-tree / out-of-range refuses, in-range emits. Section B (Task 7) extends this
## file with the coordinator deposit/withdraw + save/load persistence flow.

const CargoHoldControlScript := preload("res://scripts/tools/cargo_hold_control.gd")
const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

var _deposit_emits: int = 0
var _withdraw_cat: String = ""

func _init() -> void:
	await _run_section_a()
	await _run_section_b()

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

func _run_section_b() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	var home_id: String = ship.home_ship_id_for_validation()
	assert(ship.ship_has_cargo_hold_for_validation(home_id), "home cargo hold control spawned")

	# Seed the player inventory with a haulable part, then deposit-all into the home hold
	# by driving the REAL player-interact dispatch (walk up + interact), not the direct
	# transfer seam. This is the regression guard for the cargo control being wired into
	# _on_player_interact_requested — a return of 0 means it is NOT wired.
	ship.inventory_state.add_item("scrap_metal", 6)   # scrap_metal: part, weight 5.0, max_stack 20
	var deposited: int = ship.cargo_interact_deposit_for_validation(home_id)
	assert(deposited == 6, "interact at hold deposited 6 (got %d) — control wired into interact path" % deposited)
	assert(ship.ship_hold_quantity_for_validation(home_id, "scrap_metal") == 6, "hold holds 6")
	assert(ship.inventory_state.get_quantity("scrap_metal") == 0, "player emptied of part")

	# Withdraw the category back out.
	var withdrew: int = ship.cargo_withdraw_for_validation(home_id, "part")
	assert(withdrew == 6, "withdrew all 6 under player soft-cap (got %d)" % withdrew)

	# Re-deposit so the hold is non-empty, then assert the home hold persists via
	# WorldSnapshot.home_ship_inventory across an in-process save->load round-trip.
	# Uses the SAME seams as hangar_persistence_smoke.gd: save_world_for_validation()
	# writes to disk, load_world_for_validation() reloads into the same instance.
	ship.cargo_deposit_for_validation(home_id)
	var qty_before: int = ship.ship_hold_quantity_for_validation(home_id, "scrap_metal")
	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _j in range(3):
		await process_frame
	var home2: String = ship.home_ship_id_for_validation()
	var qty_after: int = ship.ship_hold_quantity_for_validation(home2, "scrap_metal")
	var persisted: bool = qty_after == qty_before and qty_after > 0
	assert(persisted, "home hold persisted across save/load (before=%d after=%d)" % [qty_before, qty_after])
	ship.queue_free()

	print("CARGO HOLD SMOKE PASS section_a=true deposited=%d withdrew=%d persisted=%s" % [deposited, withdrew, str(persisted)])
	quit()
