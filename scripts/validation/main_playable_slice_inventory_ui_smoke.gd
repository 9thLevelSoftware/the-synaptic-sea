extends SceneTree

## Phase 7 slice smoke: the inventory/transfer panel inside the live playable ship.
## Proves: toggle opens SELF and freezes the player; close restores control; per-item
## transfer at a hold moves a stack both ways; and storing the O2 pump in a hold reverts
## the oxygen drain multiplier to 1.0 (withdraw restores 0.5) — the tool-storage wiring.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	await _run()
	quit()

func _run() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# SELF open freezes the player; close restores.
	assert(ship.inventory_open_self_for_validation(), "toggle opened the inventory")
	assert(ship.player_frozen_for_validation(), "player frozen while panel open")
	ship.inventory_close_for_validation()
	for _j in range(2):
		await process_frame
	assert(not ship.player_frozen_for_validation(), "player control restored on close")

	# Per-item transfer at the home hold.
	var home_id: String = ship.home_ship_id_for_validation()
	ship.inventory_state.add_item("scrap_metal", 6)
	ship._open_transfer_panel_for_ship(home_id)
	assert(ship.inventory_panel_is_open_for_validation(), "transfer panel open at hold")
	var moved: int = ship.inventory_transfer_first_to_container_for_validation("scrap_metal")
	assert(moved == 6, "transferred 6 scrap into the hold (got %d)" % moved)
	assert(ship.ship_hold_quantity_for_validation(home_id, "scrap_metal") == 6, "hold has 6")
	var back: int = ship.inventory_transfer_first_from_container_for_validation("scrap_metal")
	assert(back == 6, "withdrew 6 back to the player (got %d)" % back)
	ship.inventory_close_for_validation()

	# Tool storage drives the oxygen drain multiplier live. NOTE: the effective drain
	# multiplier is breach-gated — OxygenState._compute_drain_multiplier returns 1.0
	# unless `breach_open and not breach_sealed`. Force the gate open before each read
	# so the assertion isolates the inventory-driven (pump) factor under test, instead
	# of depending on the home ship's current objective/breach state.
	ship.inventory_state.add_tool("portable_oxygen_pump")
	ship._open_transfer_panel_for_ship(home_id)
	ship._refresh_oxygen_state(false, 0.0)
	ship.oxygen_state.breach_open = true
	ship.oxygen_state.breach_sealed = false
	var with_pump: float = float(ship.oxygen_state.get_summary()["drain_multiplier"])
	assert(abs(with_pump - 0.5) < 0.001, "pump on player -> drain 0.5 (got %s)" % str(with_pump))
	var dep: int = ship.inventory_transfer_first_to_container_for_validation("portable_oxygen_pump")
	assert(dep == 1, "deposited the pump into the hold")
	ship.oxygen_state.breach_open = true
	ship.oxygen_state.breach_sealed = false
	var stored: float = float(ship.oxygen_state.get_summary()["drain_multiplier"])
	assert(abs(stored - 1.0) < 0.001, "pump stored -> drain 1.0 (got %s)" % str(stored))
	var wd: int = ship.inventory_transfer_first_from_container_for_validation("portable_oxygen_pump")
	assert(wd == 1, "withdrew the pump")
	ship.oxygen_state.breach_open = true
	ship.oxygen_state.breach_sealed = false
	var restored: float = float(ship.oxygen_state.get_summary()["drain_multiplier"])
	assert(abs(restored - 0.5) < 0.001, "pump back -> drain 0.5 (got %s)" % str(restored))
	ship.inventory_close_for_validation()

	# Scanner/inventory mutual exclusivity: toggle_scanner is SWALLOWED while the
	# inventory panel is open, so the freeze invariant cannot leak. (This path never
	# reaches set_input_as_handled — the scanner branch is guarded out and the inventory
	# block's swallow returns without it — so calling _input directly is clean.)
	assert(ship.inventory_open_self_for_validation(), "inventory open for exclusivity check")
	var tog := InputEventAction.new()
	tog.action = "toggle_scanner"
	tog.pressed = true
	ship._input(tog)
	assert(not ship.scanner_panel.is_open(), "toggle_scanner swallowed while inventory open")
	assert(ship.inventory_panel_is_open_for_validation(), "inventory stays open")
	assert(ship.player_frozen_for_validation(), "player stays frozen — invariant held")
	ship.inventory_close_for_validation()

	ship.queue_free()

	print("INVENTORY UI SLICE SMOKE PASS moved=%d stored_mult=%s" % [moved, str(stored)])
