extends SceneTree

## P12 / FC-14: physical work reserves exact lots, remains reversible until a
## timed action commits, and every work ID has one receipt/effect application.
## Marker: FC P12 PASS

const ShipWorkTransactionScript := preload("res://scripts/systems/ship_work_transaction.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const WorkActionDriverScript := preload("res://scripts/systems/work_action_driver.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

const TIMEOUT_FRAMES: int = 300

var _model_commits: int = 0
var _main: Node = null
var _playable = null
var _frames: int = 0
var _finished: bool = false


func _initialize() -> void:
	if not _verify_transaction_model():
		return
	_main = MAIN_SCENE.instantiate()
	get_root().add_child(_main)
	process_frame.connect(_on_frame)


func _verify_transaction_model() -> bool:
	var inventory = InventoryStateScript.new("p12-model-holder")
	var exact_lot: Dictionary = {
		"lot_id": "p12-model-holder/component:1",
		"item_id": "console_unit",
		"quantity": 1,
		"quality_score": 0.8,
		"quality_tier": "excellent",
		"condition": 0.73,
		"origin": {"source": "p12-smoke"},
	}
	if inventory.add_lot(exact_lot) != 1:
		_fail("model lot setup")
		return false
	var tx = ShipWorkTransactionScript.new()
	tx.configure("ship-model")
	var driver = WorkActionDriverScript.new()
	driver.configure({})
	var request: Dictionary = {
		"work_id": "model-cancel",
		"ship_id": "ship-model",
		"target_id": "slot-a",
		"target_revision": "slot-a:empty",
		"action_id": "mount_component",
		"source_holder_id": inventory.get_holder_namespace(),
		"selected_lot_ids": PackedStringArray([str(exact_lot.lot_id)]),
		"replacement_catalog_id": "console_generic",
	}
	var prepared: Dictionary = tx.prepare(request, inventory, {"console_unit": 1})
	if not bool(prepared.get("ok", false)) or inventory.get_quantity("console_unit") != 0:
		_fail("exact lot was not reserved")
		return false
	var escrow: Array = tx.get_escrow("model-cancel")
	if escrow.size() != 1 or str((escrow[0] as Dictionary).get("lot_id", "")) != str(exact_lot.lot_id):
		_fail("escrow identity")
		return false
	var start_ctx: Dictionary = {
		"tool_class": "wrench",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {"console_unit": 1},
	}
	if not bool(tx.start("model-cancel", driver, start_ctx, inventory).get("ok", false)):
		_fail("model action start")
		return false
	driver.tick(1.0, {})
	var before_pause: float = driver.progress_ratio()
	if not tx.pause("model-cancel", driver) or not tx.resume("model-cancel", driver, start_ctx):
		_fail("pause/resume")
		return false
	if absf(driver.progress_ratio() - before_pause) > 0.0001:
		_fail("pause changed progress")
		return false
	var cancelled: Dictionary = tx.cancel("model-cancel", inventory, driver, "explicit_cancel")
	if not bool(cancelled.get("ok", false)) or inventory.get_quantity("console_unit") != 1:
		_fail("cancel did not refund")
		return false
	var restored_lots: Array = inventory.get_lot_summary().get("lots", []) as Array
	if restored_lots.size() != 1 or str((restored_lots[0] as Dictionary).get("lot_id", "")) != str(exact_lot.lot_id):
		_fail("cancel changed exact lot")
		return false

	# A conflicting destination lot blocks the whole refund without partially
	# depositing escrow. Once the conflict is removed, the same escrow recovers.
	request["work_id"] = "model-refund-blocked"
	if not bool(tx.prepare(request, inventory, {"console_unit": 1}).get("ok", false)):
		_fail("refund-blocked prepare")
		return false
	if inventory.add_lot(exact_lot) != 1:
		_fail("refund conflict setup")
		return false
	var blocked_refund: Dictionary = tx.cancel("model-refund-blocked", inventory, driver, "explicit_cancel")
	if bool(blocked_refund.get("ok", false)) or str(blocked_refund.get("reason", "")) != "refund_blocked" \
			or inventory.get_quantity("console_unit") != 1 or tx.get_escrow("model-refund-blocked").size() != 1:
		_fail("blocked refund was partial or lost escrow")
		return false
	inventory.remove_item("console_unit", 1)
	if not bool(tx.cancel("model-refund-blocked", inventory, driver, "explicit_cancel").get("ok", false)) \
			or inventory.get_quantity("console_unit") != 1:
		_fail("blocked refund recovery")
		return false

	# A missing tool after reservation rolls staging back into the same holder.
	request["work_id"] = "model-missing-tool"
	if not bool(tx.prepare(request, inventory, {"console_unit": 1}).get("ok", false)):
		_fail("missing-tool prepare")
		return false
	var bad_start: Dictionary = tx.start("model-missing-tool", driver, {
		"tool_class": "",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {"console_unit": 1},
	}, inventory)
	if bool(bad_start.get("ok", false)) or inventory.get_quantity("console_unit") != 1:
		_fail("missing tool charged escrow")
		return false

	# A completed work ID calls the mutation closure exactly once. Repeating commit
	# returns the stored receipt and cannot repeat target/noise/XP effects.
	request["work_id"] = "model-commit"
	if not bool(tx.prepare(request, inventory, {"console_unit": 1}).get("ok", false)):
		_fail("commit prepare")
		return false
	if not bool(tx.start("model-commit", driver, start_ctx, inventory).get("ok", false)):
		_fail("commit start")
		return false
	driver.tick(999.0, {})
	if not tx.mark_completed("model-commit", driver):
		_fail("mark completed")
		return false
	var stage_calls: Array[int] = [0]
	var stage: Callable = func(_record: Dictionary) -> Dictionary:
		stage_calls[0] += 1
		return {"ok": true}
	var commit_once: Callable = func(_record: Dictionary) -> Dictionary:
		_model_commits += 1
		return {
			"ok": true,
			"committed_target_revision": "slot-a:occupied",
			"awarded_event_ids": ["repair"],
			"noise": 0.2,
		}
	var commit_context: Dictionary = {
		"ship_id": "ship-model",
		"target_id": "slot-a",
		"target_exists": true,
		"target_revision": "slot-a:empty",
		"in_range": true,
		"has_required_tool": true,
		"damaged": false,
		"stage": stage,
		"commit": commit_once,
	}
	var first: Dictionary = tx.commit("model-commit", commit_context)
	var second: Dictionary = tx.commit("model-commit", commit_context)
	if not bool(first.get("ok", false)) or not bool(second.get("already_committed", false)) \
			or _model_commits != 1 or stage_calls[0] != 1:
		_fail("commit was not exactly once")
		return false

	# The captured revision is mandatory authority. Stale/removed targets retain
	# recoverable escrow until the caller explicitly cancels.
	inventory.add_lot(exact_lot)
	request["work_id"] = "model-stale"
	if not bool(tx.prepare(request, inventory, {"console_unit": 1}).get("ok", false)):
		_fail("stale prepare")
		return false
	if not bool(tx.start("model-stale", driver, start_ctx, inventory).get("ok", false)):
		_fail("stale start")
		return false
	driver.tick(999.0, {})
	tx.mark_completed("model-stale", driver)
	var stale_context: Dictionary = commit_context.duplicate(true)
	stale_context["target_revision"] = "slot-a:changed"
	var stale: Dictionary = tx.commit("model-stale", stale_context)
	if bool(stale.get("ok", false)) or str(stale.get("reason", "")) != "stale_target" \
			or tx.get_escrow("model-stale").size() != 1:
		_fail("stale target")
		return false
	tx.cancel("model-stale", inventory, driver, "stale_target")

	# A late staging failure (for example, a changed power budget) never charges
	# the paid lot and never invokes the physical mutation closure.
	request["work_id"] = "model-stage-fail"
	if not bool(tx.prepare(request, inventory, {"console_unit": 1}).get("ok", false)) \
			or not bool(tx.start("model-stage-fail", driver, start_ctx, inventory).get("ok", false)):
		_fail("stage-fail setup")
		return false
	driver.tick(999.0, {})
	tx.mark_completed("model-stage-fail", driver)
	var stage_fail_context: Dictionary = commit_context.duplicate(true)
	stage_fail_context["source_inventory"] = inventory
	stage_fail_context["stage"] = func(_record: Dictionary) -> Dictionary:
		return {"ok": false, "reason": "power_budget"}
	var stage_failed: Dictionary = tx.commit("model-stage-fail", stage_fail_context)
	if bool(stage_failed.get("ok", false)) or str(stage_failed.get("reason", "")) != "power_budget" \
			or not bool(stage_failed.get("refunded", false)) or inventory.get_quantity("console_unit") != 1 \
			or not tx.get_escrow("model-stage-fail").is_empty() or _model_commits != 1:
		_fail("staging failure charged or mutated")
		return false

	# A physical commit callback may synchronously signal code that retries the
	# same work ID. The process-local latch must deny that nested call before it
	# can invoke staging or mutation a second time, refund escrow, or export and
	# restore a falsely stable READY snapshot.
	var reentrant_lot: Dictionary = exact_lot.duplicate(true)
	reentrant_lot["lot_id"] = "model-reentrant-lot"
	inventory.add_lot(reentrant_lot)
	request["work_id"] = "model-reentrant"
	request["selected_lot_ids"] = PackedStringArray(["model-reentrant-lot"])
	if not bool(tx.prepare(request, inventory, {"console_unit": 1}).get("ok", false)) \
			or not bool(tx.start("model-reentrant", driver, start_ctx, inventory).get("ok", false)):
		_fail("reentrant setup")
		return false
	driver.tick(999.0, {})
	tx.mark_completed("model-reentrant", driver)
	var reentrant_calls: Array[int] = [0]
	var reentrant_noise_events: Array[int] = [0]
	var reentrant_xp_events: Array[int] = [0]
	var nested_results: Array[Dictionary] = []
	var nested_cancels: Array[Dictionary] = []
	var unstable_summaries: Array[Dictionary] = []
	var restore_attempts: Array[bool] = []
	var configure_attempts: Array[bool] = []
	var summary_before_reentrant: Dictionary = tx.get_summary()
	var reentrant_context: Dictionary = commit_context.duplicate(true)
	reentrant_context["commit"] = func(_record: Dictionary) -> Dictionary:
		reentrant_calls[0] += 1
		reentrant_noise_events[0] += 1
		reentrant_xp_events[0] += 1
		nested_results.append(tx.commit("model-reentrant", reentrant_context))
		nested_cancels.append(tx.cancel("model-reentrant", inventory, driver, "recursive_cancel"))
		unstable_summaries.append(tx.get_summary())
		restore_attempts.append(tx.apply_summary(summary_before_reentrant))
		configure_attempts.append(tx.configure("ship-model"))
		return {
			"ok": true,
			"committed_target_revision": "slot-a:occupied",
			"awarded_event_ids": ["repair"],
			"noise": 0.2,
		}
	var reentrant: Dictionary = tx.commit("model-reentrant", reentrant_context)
	# Break the intentional self-reference used by the recursive probe before the
	# headless scene exits; the transaction receipt never retains this callable.
	reentrant_context["commit"] = Callable()
	var reentrant_duplicate: Dictionary = tx.commit("model-reentrant", reentrant_context)
	if not bool(reentrant.get("ok", false)) or not bool(reentrant_duplicate.get("already_committed", false)) \
			or reentrant_calls[0] != 1 or reentrant_noise_events[0] != 1 or reentrant_xp_events[0] != 1 \
			or nested_results.size() != 1 or str(nested_results[0].get("reason", "")) != "commit_in_flight" \
			or nested_cancels.size() != 1 or str(nested_cancels[0].get("reason", "")) != "commit_in_flight" \
			or not unstable_summaries[0].is_empty() or restore_attempts[0] or configure_attempts[0] \
			or inventory.get_quantity("console_unit") != 1:
		_fail("reentrant commit was not exactly once")
		return false

	# A failed callback clears the transient latch so the same READY record can be
	# safely retried and committed once after its recoverable denial.
	var retry_lot: Dictionary = exact_lot.duplicate(true)
	retry_lot["lot_id"] = "model-retry-lot"
	inventory.add_lot(retry_lot)
	request["work_id"] = "model-retry"
	request["selected_lot_ids"] = PackedStringArray(["model-retry-lot"])
	if not bool(tx.prepare(request, inventory, {"console_unit": 1}).get("ok", false)) \
			or not bool(tx.start("model-retry", driver, start_ctx, inventory).get("ok", false)):
		_fail("commit retry setup")
		return false
	driver.tick(999.0, {})
	tx.mark_completed("model-retry", driver)
	var denied_calls: Array[int] = [0]
	var denied_context: Dictionary = commit_context.duplicate(true)
	denied_context["commit"] = func(_record: Dictionary) -> Dictionary:
		denied_calls[0] += 1
		return {"ok": false, "reason": "recoverable_commit_denial"}
	var denied_commit: Dictionary = tx.commit("model-retry", denied_context)
	var successful_retry: Dictionary = tx.commit("model-retry", commit_context)
	if str(denied_commit.get("reason", "")) != "recoverable_commit_denial" \
			or not bool(successful_retry.get("ok", false)) or denied_calls[0] != 1:
		_fail("commit latch did not clear after denial")
		return false

	# Locked summaries reject foreign owners, malformed lots, and forged receipts,
	# while a valid restore continues the per-ship sequence without reusing an ID.
	var valid_summary: Dictionary = tx.get_summary()
	var restored = ShipWorkTransactionScript.new()
	if not restored.apply_summary(valid_summary):
		_fail("valid transaction summary restore: %s" % str(valid_summary))
		return false
	var next_id: String = restored.create_work_id("mount_component")
	if next_id == "model-stage-fail" or not next_id.begins_with("ship-model/"):
		_fail("restored work id sequence")
		return false
	var configured_before: Dictionary = restored.get_summary()
	if restored.configure("ship-other") or restored.get_summary() != configured_before:
		_fail("configured ledger owner reassigned or mutated")
		return false
	var bound_other = ShipWorkTransactionScript.new()
	bound_other.configure("ship-other")
	var bound_before: Dictionary = bound_other.get_summary()
	if bound_other.apply_summary(valid_summary) or bound_other.get_summary() != bound_before:
		_fail("bound ledger owner reassigned or mutated")
		return false
	var wrong_owner: Dictionary = valid_summary.duplicate(true)
	(wrong_owner["transactions"][0] as Dictionary)["ship_id"] = "ship-other"
	if ShipWorkTransactionScript.new().apply_summary(wrong_owner):
		_fail("foreign transaction owner accepted")
		return false
	var malformed_lot: Dictionary = valid_summary.duplicate(true)
	for record_v in malformed_lot.get("transactions", []) as Array:
		if record_v is Dictionary and not ((record_v as Dictionary).get("escrow", []) as Array).is_empty():
			(((record_v as Dictionary)["escrow"] as Array)[0] as Dictionary)["quality_score"] = 2.0
			break
	if ShipWorkTransactionScript.new().apply_summary(malformed_lot):
		_fail("malformed escrow accepted")
		return false
	var forged_receipt: Dictionary = valid_summary.duplicate(true)
	for record_v in forged_receipt.get("transactions", []) as Array:
		if record_v is Dictionary and str((record_v as Dictionary).get("state", "")) == "committed":
			(record_v as Dictionary)["commit_receipt_id"] = "forged"
			break
	if ShipWorkTransactionScript.new().apply_summary(forged_receipt):
		_fail("forged receipt accepted")
		return false
	var forged_requirements: Dictionary = valid_summary.duplicate(true)
	for record_v in forged_requirements.get("transactions", []) as Array:
		if record_v is Dictionary and not ((record_v as Dictionary).get("escrow", []) as Array).is_empty():
			(record_v as Dictionary)["requirements"] = {"forged_relic": 99}
			break
	var reject_target = ShipWorkTransactionScript.new()
	var reject_before: Dictionary = reject_target.get_summary()
	if reject_target.apply_summary(forged_requirements) or reject_target.get_summary() != reject_before:
		_fail("forged requirements accepted or mutated restore target")
		return false
	return _verify_component_quality_preflight() and _verify_paid_repair_quality()


func _verify_component_quality_preflight() -> bool:
	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		_fail("component catalog")
		return false
	var placement = ComponentPlacementStateScript.new()
	placement.populate({"rooms": [{
		"id": "engineering",
		"room_role": "engineering",
		"center_slots": [{"cell": [0, 0], "component_slot_profile_id": "deck_machinery_mount_v1"}],
	}]}, catalog, 12)
	for entry_v in placement.placed.duplicate(true):
		placement.dismount(str((entry_v as Dictionary).get("component_instance_id", "")))
	var mod = ShipModificationStateScript.new()
	mod.configure({"power_supply": 10.0, "power_demand_baseline": 0.0})
	mod.power_supply = 10.0
	mod.power_demand_baseline = 0.0
	if not mod.bind_physical_slots("quality-ship", placement.get_physical_slot_descriptors("quality-ship"), catalog, placement):
		_fail("quality slot binding")
		return false
	var slot_id: String = ""
	for descriptor_v in placement.get_physical_slot_descriptors("quality-ship"):
		if descriptor_v is Dictionary and bool(catalog.validate_component_fit("machinery_block", descriptor_v as Dictionary).get("ok", false)):
			slot_id = str((descriptor_v as Dictionary).get("slot_id", ""))
			break
	if slot_id.is_empty():
		_fail("quality machinery slot")
		return false
	var poor_lot: Dictionary = {
		"lot_id": "quality-poor", "item_id": "machinery_block", "quantity": 1,
		"quality_score": 0.1, "quality_tier": "poor", "condition": 0.4, "origin": {},
	}
	var master_lot: Dictionary = poor_lot.duplicate(true)
	master_lot["lot_id"] = "quality-master"
	master_lot["quality_score"] = 0.95
	master_lot["quality_tier"] = "masterwork"
	var inventory: Dictionary = {"machinery_block": 1}
	var poor: Dictionary = mod.preflight_install(
		slot_id, "machinery_block", "machinery_block", inventory, "quality-ship", poor_lot)
	var master: Dictionary = mod.preflight_install(
		slot_id, "machinery_block", "machinery_block", inventory, "quality-ship", master_lot)
	var poor_draw: float = mod.effective_power_draw("machinery_block", poor_lot)
	var master_draw: float = mod.effective_power_draw("machinery_block", master_lot)
	if str(poor.get("reason", "")) != "power_budget" or not bool(master.get("ok", false)) \
			or poor_draw <= 10.0 or master_draw > 10.0 \
			or absf(float(master.get("effective_power_draw", 99.0)) - master_draw) > 0.0001:
		_fail("exact lot quality power preflight poor=%s master=%s" % [str(poor), str(master)])
		return false
	var wrong_lot: Dictionary = master_lot.duplicate(true)
	wrong_lot["item_id"] = "console_unit"
	if str(mod.preflight_install(slot_id, "machinery_block", "machinery_block", inventory, "quality-ship", wrong_lot).get("reason", "")) != "invalid_source_lot":
		_fail("wrong selected quality lot")
		return false
	return true


func _verify_paid_repair_quality() -> bool:
	var driver = WorkActionDriverScript.new()
	driver.configure({})
	var module_map = ModuleIntegrityMapScript.new()
	var module = module_map.ensure_module("engineering/wall-quality", "wall_straight_1x1")
	module_map.apply_damage("engineering/wall-quality", 0.9, "wall_straight_1x1")
	var before: float = float(module.get("integrity"))
	if not driver.start_action("weld_patch", "engineering/wall-quality", {
		"tool_class": "welding_lance",
		"skill_id": "repair",
		"skill_level": 99,
		"inventory": {"hull_plate": 1},
	}):
		_fail("paid repair action start")
		return false
	driver.tick(999.0, {})
	var paid_lot: Dictionary = {
		"lot_id": "repair-master", "item_id": "hull_plate", "quantity": 1,
		"quality_score": 0.95, "quality_tier": "masterwork", "condition": 0.2, "origin": {"source": "escrow"},
	}
	var result: Dictionary = driver.complete(module_map, {}, {
		"materials_prepaid": true,
		"repair_material_lots": [paid_lot],
	})
	var repaired = module_map.get_module("engineering/wall-quality")
	if not bool(result.get("ok", false)) or absf(float(result.get("repair_quality_multiplier", 0.0)) - 2.0) > 0.0001 \
			or str(((result.get("repair_material_lots", []) as Array)[0] as Dictionary).get("lot_id", "")) != "repair-master" \
			or absf(float(repaired.get("integrity")) - before - 0.7) > 0.0001:
		_fail("paid repair lot snapshot: %s" % str(result))
		return false
	return true


func _on_frame() -> void:
	if _finished:
		return
	_frames += 1
	if _playable == null:
		_playable = _find_playable(_main)
	if _playable == null or not bool(_playable.get("playable_started")):
		if _frames > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate_live_panel_transaction()


func _validate_live_panel_transaction() -> void:
	_finished = true
	var fixture: Dictionary = _playable.prepare_p12_component_work_fixture_for_validation()
	if not bool(fixture.get("ok", false)):
		_fail("live fixture: %s" % str(fixture.get("reason", "")))
		return
	var slot_id: String = str(fixture.get("slot_id", ""))
	var item_form: String = str(fixture.get("item_form", ""))
	var instance_id: String = str(fixture.get("instance_id", slot_id))
	var panel = _playable.get_ship_modification_panel_for_validation()
	var placement = _playable.get_component_placement_state_for_validation()
	if panel == null or placement == null or not placement.is_mounted(instance_id):
		_fail("live mounted fixture")
		return
	if not panel.uninstall_selected():
		_fail("uninstall request")
		return
	if not placement.is_mounted(instance_id) or not _playable.has_active_ship_work_for_validation():
		_fail("panel mutated before timed commit")
		return
	_playable.advance_active_ship_work_for_validation(1.0)
	if not placement.is_mounted(instance_id):
		_fail("partial progress mutated target")
		return
	if not _playable.cancel_active_ship_work_for_validation("explicit_cancel") or not placement.is_mounted(instance_id):
		_fail("live cancel")
		return

	# Concurrent removal changes the real slot revision; the queued request cannot
	# produce a second item or commit its effect.
	if not panel.uninstall_selected():
		_fail("stale uninstall request")
		return
	var concurrent: Dictionary = placement.dismount(instance_id)
	if not bool(concurrent.get("ok", false)):
		_fail("concurrent target removal")
		return
	_playable.advance_active_ship_work_for_validation(999.0)
	var stale_result: Dictionary = _playable.get_last_ship_work_result_for_validation()
	if str(stale_result.get("reason", "")) != "stale_target":
		_fail("live stale revision: %s" % str(stale_result))
		return
	if not _playable.cancel_active_ship_work_for_validation("stale_target"):
		_fail("stale escrow cancel")
		return

	# Put the concurrently removed exact component into inventory, then request a
	# real panel install. Reservation is visible immediately; occupancy waits for time.
	var returned_lot: Dictionary = concurrent.get("item_lot", {}) as Dictionary
	if returned_lot.is_empty():
		returned_lot = {
			"lot_id": "p12-live/%s" % item_form,
			"item_id": item_form,
			"quantity": 1,
			"quality_score": 0.8,
			"quality_tier": "excellent",
			"condition": 0.73,
			"origin": {"source": "p12-live"},
		}
	if _playable.inventory_state.add_lot(returned_lot) != 1:
		_fail("live returned lot setup")
		return
	_playable.vitals_state.stamina = _playable.vitals_state.max_stamina
	panel.set_inventory(_playable.inventory_state.items)
	if not panel.install_from_inventory(_playable.component_catalog, PackedStringArray([item_form])):
		_fail("install request")
		return
	if placement.is_mounted(instance_id) or _playable.inventory_state.get_quantity(item_form) != 0:
		_fail("install did not reserve without mutation")
		return
	_playable.advance_active_ship_work_for_validation(1.0)
	if placement.is_mounted(instance_id):
		_fail("install completed early")
		return
	if not _playable.has_active_ship_work_for_validation():
		_fail("install interrupted during partial progress: %s stamina=%s" % [
			str(_playable.get_last_ship_work_result_for_validation()),
			str(_playable.vitals_state.stamina),
		])
		return
	_playable.advance_active_ship_work_for_validation(999.0)
	if not placement.is_mounted(instance_id):
		_fail("timed install did not commit: %s" % str(_playable.get_last_ship_work_result_for_validation()))
		return
	var committed_before: int = _playable.get_ship_work_commit_count_for_validation()
	var duplicate: Dictionary = _playable.commit_last_ship_work_for_validation()
	if not bool(duplicate.get("already_committed", false)) \
			or _playable.get_ship_work_commit_count_for_validation() != committed_before:
		_fail("live duplicate commit")
		return
	var mounted: Dictionary = placement.get_entry(instance_id)
	if str(mounted.get("source_lot_id", "")) != str(returned_lot.get("lot_id", "")) \
			or absf(float(mounted.get("condition", 0.0)) - float(returned_lot.get("condition", 0.0))) > 0.0001:
		_fail("mounted exact lot metadata")
		return

	# Lost tool, leaving range, and damage pause without removing the target or
	# refunding reserved escrow. Only explicit cancel closes the work ID.
	for cause in ["missing_tool", "out_of_range", "damaged"]:
		if not _playable.begin_p12_uninstall_for_validation(slot_id):
			_fail("%s begin" % cause)
			return
		_playable.advance_active_ship_work_for_validation(1.0)
		var before_interrupt: Dictionary = _playable.get_active_ship_work_record_for_validation()
		if not _playable.interrupt_active_ship_work_for_validation(cause):
			_fail("%s pause request" % cause)
			return
		var paused_record: Dictionary = _playable.get_active_ship_work_record_for_validation()
		if not _playable.has_active_ship_work_for_validation() or not placement.is_mounted(instance_id) \
				or str(paused_record.get("state", "")) != "paused" \
				or absf(float(paused_record.get("progress", 0.0)) - float(before_interrupt.get("progress", 0.0))) > 0.0001 \
				or (paused_record.get("escrow", []) as Array).size() != (before_interrupt.get("escrow", []) as Array).size():
			_fail("%s interruption" % cause)
			return
		if not _playable.cancel_active_ship_work_for_validation("explicit_cancel") \
				or _playable.has_active_ship_work_for_validation() or not placement.is_mounted(instance_id):
			_fail("%s explicit cancel" % cause)
			return

	print("FC P12 PASS")
	quit(0)


func _find_playable(node: Node):
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	if _finished and _playable == null:
		return
	_finished = true
	print("FC P12 FAIL: %s" % message)
	quit(1)
