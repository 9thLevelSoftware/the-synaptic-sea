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
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
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
	var reentrant_inventory = InventoryStateScript.new("p12-model-reentrant-holder")
	if reentrant_inventory.add_lot(reentrant_lot) != 1:
		_fail("reentrant lot setup")
		return false
	request["work_id"] = "model-reentrant"
	request["source_holder_id"] = reentrant_inventory.get_holder_namespace()
	request["selected_lot_ids"] = PackedStringArray(["model-reentrant-lot"])
	if not bool(tx.prepare(request, reentrant_inventory, {"console_unit": 1}).get("ok", false)) \
			or not bool(tx.start("model-reentrant", driver, start_ctx, reentrant_inventory).get("ok", false)):
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
		nested_cancels.append(tx.cancel(
			"model-reentrant", reentrant_inventory, driver, "recursive_cancel"))
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
	var retry_inventory = InventoryStateScript.new("p12-model-retry-holder")
	if retry_inventory.add_lot(retry_lot) != 1:
		_fail("commit retry lot setup")
		return false
	request["work_id"] = "model-retry"
	request["source_holder_id"] = retry_inventory.get_holder_namespace()
	request["selected_lot_ids"] = PackedStringArray(["model-retry-lot"])
	if not bool(tx.prepare(request, retry_inventory, {"console_unit": 1}).get("ok", false)) \
			or not bool(tx.start("model-retry", driver, start_ctx, retry_inventory).get("ok", false)):
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
	var component_id: String = str(fixture.get("component_id", ""))
	var instance_id: String = str(fixture.get("instance_id", slot_id))
	var panel = _playable.get_ship_modification_panel_for_validation()
	var placement = _playable.get_component_placement_state_for_validation()
	if panel == null or placement == null or not placement.is_mounted(instance_id):
		_fail("live mounted fixture")
		return
	if not _validate_pre_escrow_admission(slot_id):
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
	if not _validate_production_denial_matrix(slot_id, component_id, item_form):
		return
	if not _validate_live_occupancy_refresh(slot_id, component_id, item_form):
		return
	if not _validate_reserved_target_removal_cancel(
			panel, slot_id, item_form, returned_lot):
		return
	var selected_context = _playable._ship_work_context_for(
		_playable.get_selected_ship_id_for_validation())
	var authoritative_before: Dictionary = _authoritative_snapshot(selected_context)
	var observable_before: Dictionary = _playable.get_ship_work_observable_counts_for_validation()
	var receipts_before: int = _receipt_count(selected_context.work_transactions.get_summary())
	var training_bus = _playable.get_training_event_bus()
	var training_log_before: int = (training_bus.get_log() as Array).size()
	var delivered_xp_before: int = training_bus.get_total_xp_delivered()
	var progression_before: Dictionary = _playable.player_progression.get_summary()
	var completion_event: StringName = AudioEventSeamScript.sfx_for_work_verb("mount")
	var completion_sfx_before: int = _playable.audio_manager.sfx_router.get_routed_count(
		completion_event)
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
	var previous_event_callback: Callable = training_bus.on_event_resolved
	var reentrant_results: Array = []
	training_bus.on_event_resolved = func(event: Dictionary) -> void:
		if previous_event_callback.is_valid():
			previous_event_callback.call(event)
		reentrant_results.append(_playable.commit_last_ship_work_for_validation())
	_playable.threat_manager.player_noise = 0.0
	_playable.advance_active_ship_work_for_validation(999.0)
	training_bus.on_event_resolved = previous_event_callback
	if not placement.is_mounted(instance_id):
		_fail("timed install did not commit: %s" % str(_playable.get_last_ship_work_result_for_validation()))
		return
	var first_receipt: Dictionary = _playable.get_last_ship_work_result_for_validation()
	var observable_after: Dictionary = _playable.get_ship_work_observable_counts_for_validation()
	var progression_after: Dictionary = _playable.player_progression.get_summary()
	var training_log_after: int = (training_bus.get_log() as Array).size()
	var delivered_xp_after: int = training_bus.get_total_xp_delivered()
	var completion_sfx_after: int = _playable.audio_manager.sfx_router.get_routed_count(
		completion_event)
	var authoritative_after: Dictionary = _authoritative_snapshot(selected_context)
	var committed_noise: float = float(first_receipt.get("noise", 0.0))
	if str(first_receipt.get("commit_receipt_id", "")).is_empty() \
			or _receipt_count(selected_context.work_transactions.get_summary()) != receipts_before + 1 \
			or int(observable_after.get("commit", 0)) != int(observable_before.get("commit", 0)) + 1 \
			or int(observable_after.get("effect", 0)) != int(observable_before.get("effect", 0)) + 1 \
			or int(observable_after.get("noise_completion", 0)) != int(observable_before.get("noise_completion", 0)) + 1 \
			or int(observable_after.get("xp_award", 0)) != int(observable_before.get("xp_award", 0)) + 1:
		_fail("live commit did not produce one receipt/effect/noise/xp: receipt=%s before=%s after=%s" % [
			str(first_receipt), str(observable_before), str(observable_after)])
		return
	if reentrant_results.size() != 1 \
			or str((reentrant_results[0] as Dictionary).get("reason", "")) != "commit_in_flight" \
			or not bool((reentrant_results[0] as Dictionary).get("escrow_retained", false)):
		_fail("production consequence callback was not reentrancy-latched: %s" % str(reentrant_results))
		return
	if committed_noise <= 0.0 \
			or float(_playable.threat_manager.player_noise) + 0.0001 < committed_noise \
			or completion_sfx_after != completion_sfx_before + 1 \
			or training_log_after != training_log_before + 1 \
			or delivered_xp_after <= delivered_xp_before \
			or progression_after == progression_before:
		_fail("live consequence sinks missing: noise=%s routed=%d/%d log=%d/%d xp=%d/%d" % [
			str(_playable.threat_manager.player_noise), completion_sfx_before,
			completion_sfx_after, training_log_before, training_log_after,
			delivered_xp_before, delivered_xp_after])
		return
	if authoritative_after.get("placement", {}) == authoritative_before.get("placement", {}) \
			or authoritative_after.get("modification", {}) == authoritative_before.get("modification", {}) \
			or int(authoritative_after.get("receipt_count", 0)) \
			!= int(authoritative_before.get("receipt_count", 0)) + 1:
		_fail("authoritative production placement/modification/receipt did not commit once")
		return
	var committed_before: int = _playable.get_ship_work_commit_count_for_validation()
	var duplicate: Dictionary = _playable.commit_last_ship_work_for_validation()
	if not bool(duplicate.get("already_committed", false)) \
			or str(duplicate.get("commit_receipt_id", "")) != str(first_receipt.get("commit_receipt_id", "")) \
			or _playable.get_ship_work_commit_count_for_validation() != committed_before \
			or _playable.get_ship_work_observable_counts_for_validation() != observable_after \
			or _receipt_count(selected_context.work_transactions.get_summary()) != receipts_before + 1 \
			or _playable.audio_manager.sfx_router.get_routed_count(completion_event) != completion_sfx_after \
			or (training_bus.get_log() as Array).size() != training_log_after \
			or training_bus.get_total_xp_delivered() != delivered_xp_after \
			or _playable.player_progression.get_summary() != progression_after \
			or _authoritative_snapshot(selected_context) != authoritative_after:
		_fail("live duplicate commit")
		return
	var mounted: Dictionary = placement.get_entry(instance_id)
	if str(mounted.get("source_lot_id", "")) != str(returned_lot.get("lot_id", "")) \
			or absf(float(mounted.get("condition", 0.0)) - float(returned_lot.get("condition", 0.0))) > 0.0001:
		_fail("mounted exact lot metadata")
		return
	if not _validate_moved_owner_position_rechecks(slot_id, selected_context):
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
	if not _validate_untransactioned_component_fails_closed(slot_id):
		return

	print("FC P12 PASS")
	quit(0)


func _validate_pre_escrow_admission(slot_id: String) -> bool:
	var ship_id: String = _playable.get_selected_ship_id_for_validation()
	var work_context = _playable._ship_work_context_for(ship_id)
	var target_position: Variant = _playable._component_slot_world_position(slot_id, work_context)
	if work_context == null or work_context.work_transactions == null \
			or not (target_position is Vector3):
		_fail("pre-escrow admission fixture")
		return false
	var entry: Dictionary = work_context.component_placement.get_entry(slot_id)
	var payload: Dictionary = {
		"slot_id": slot_id,
		"component_id": str(entry.get("component_id", "")),
		"item_form": str(entry.get("item_form", "")),
	}
	var start_context: Dictionary = {
		"tool_class": "wrench",
		"skill_id": "salvage",
		"skill_level": 99,
		"inventory": _playable._inventory_qty_dict_for_work(),
	}
	var target_revision: String = _playable._component_slot_revision(slot_id, work_context)
	var protected_before: Dictionary = _authoritative_snapshot(work_context)
	var missing_owner: Dictionary = _playable._start_transactional_work(
		"dismount_component", slot_id, "component_uninstall", target_revision,
		start_context, payload, target_position, PackedStringArray(), "")
	if str(missing_owner.get("reason", "")) != "missing_ship_owner" \
			or _playable.has_active_ship_work_for_validation() \
			or _authoritative_snapshot(work_context) != protected_before:
		_fail("missing owner admitted or spent: %s" % str(missing_owner))
		return false
	var non_finite: Dictionary = _playable._start_transactional_work(
		"dismount_component", slot_id, "component_uninstall", target_revision,
		start_context, payload, Vector3(INF, 0.0, 0.0), PackedStringArray(), ship_id)
	if str(non_finite.get("reason", "")) != "invalid_target_position" \
			or _playable.has_active_ship_work_for_validation() \
			or _authoritative_snapshot(work_context) != protected_before:
		_fail("non-finite target point admitted or spent: %s" % str(non_finite))
		return false
	var stale_point: Vector3 = (target_position as Vector3) + Vector3(0.25, 0.0, 0.0)
	var stale_position: Dictionary = _playable._start_transactional_work(
		"dismount_component", slot_id, "component_uninstall", target_revision,
		start_context, payload, stale_point, PackedStringArray(), ship_id)
	if str(stale_position.get("reason", "")) != "stale_target_position" \
			or _playable.has_active_ship_work_for_validation() \
			or _authoritative_snapshot(work_context) != protected_before:
		_fail("stale target point admitted or spent: %s" % str(stale_position))
		return false
	var forged_nearby: Vector3 = (target_position as Vector3) \
		+ Vector3(_playable.WORK_ACTION_INTERACT_RANGE + 1.0, 0.0, 0.0)
	(_playable.player as Node3D).global_position = forged_nearby
	var forged_position: Dictionary = _playable._start_transactional_work(
		"dismount_component", slot_id, "component_uninstall", target_revision,
		start_context, payload, forged_nearby, PackedStringArray(), ship_id)
	if str(forged_position.get("reason", "")) != "stale_target_position" \
			or _playable.has_active_ship_work_for_validation() \
			or _authoritative_snapshot(work_context) != protected_before:
		_fail("forged nearby point admitted distant target: %s" % str(forged_position))
		return false

	(_playable.player as Node3D).global_position = (target_position as Vector3) \
		+ Vector3(_playable.WORK_ACTION_INTERACT_RANGE + 1.0, 0.0, 0.0)
	var out_of_range: Dictionary = _playable._start_transactional_work(
		"dismount_component", slot_id, "component_uninstall", target_revision,
		start_context, payload, target_position, PackedStringArray(), ship_id)
	if str(out_of_range.get("reason", "")) != "out_of_range" \
			or _playable.has_active_ship_work_for_validation() \
			or _authoritative_snapshot(work_context) != protected_before:
		_fail("out-of-range admission spent or allocated: %s" % str(out_of_range))
		return false

	(_playable.player as Node3D).global_position = target_position as Vector3
	var owner_root = work_context.ship.scene_root
	if not (owner_root is Node3D):
		_fail("moved-owner target-position fixture")
		return false
	var owner_transform_before: Transform3D = (owner_root as Node3D).global_transform
	(owner_root as Node3D).global_position += Vector3(0.5, 0.0, 0.0)
	var moved_owner: Dictionary = _playable._start_transactional_work(
		"dismount_component", slot_id, "component_uninstall", target_revision,
		start_context, payload, target_position, PackedStringArray(), ship_id)
	(owner_root as Node3D).global_transform = owner_transform_before
	if str(moved_owner.get("reason", "")) != "stale_target_position" \
			or _playable.has_active_ship_work_for_validation() \
			or _authoritative_snapshot(work_context) != protected_before:
		_fail("moved owner accepted stale start point: %s" % str(moved_owner))
		return false
	var stale_revision: Dictionary = _playable._start_transactional_work(
		"dismount_component", slot_id, "component_uninstall", "%s|stale" % target_revision,
		start_context, payload, target_position, PackedStringArray(), ship_id)
	if str(stale_revision.get("reason", "")) != "stale_target" \
			or _playable.has_active_ship_work_for_validation() \
			or _authoritative_snapshot(work_context) != protected_before:
		_fail("stale revision admitted or spent: %s" % str(stale_revision))
		return false
	return true


func _authoritative_snapshot(work_context) -> Dictionary:
	return _playable.get_ship_work_authoritative_snapshot_for_validation(
		str(work_context.ship_id))


func _validate_production_denial_matrix(
		slot_id: String, component_id: String, item_form: String) -> bool:
	var ship_id: String = _playable.get_selected_ship_id_for_validation()
	var work_context = _playable._ship_work_context_for(ship_id)
	var panel = _playable.get_ship_modification_panel_for_validation()
	if work_context == null or work_context.component_placement == null or panel == null:
		_fail("production denial context")
		return false
	var placement = work_context.component_placement
	var slot: Dictionary = work_context.component_placement.get_physical_slot(slot_id)
	var profile_id: String = str(slot.get("component_slot_profile_id", ""))
	var original_profile: Dictionary = _playable.component_catalog.get_slot_profile(profile_id)
	var target_position: Variant = _playable._component_slot_world_position(slot_id, work_context)
	if slot.is_empty() or original_profile.is_empty() \
			or not _playable._work_position_is_finite(target_position):
		_fail("production denial fixture")
		return false
	(_playable.player as Node3D).global_position = target_position as Vector3

	# Panel-side missing-item and missing/unknown-slot paths execute the real
	# signal callback. Their failure SFX is allowed UI feedback; the shared
	# authoritative snapshot deliberately tracks completion audio only.
	if not _expect_panel_install_denied(
			panel, work_context, slot_id, component_id, "review_missing_item_form",
			"missing_item", "missing item"):
		return false
	if not _expect_panel_install_denied(
			panel, work_context, "", component_id, item_form,
			"unknown_slot", "missing slot"):
		return false
	if not _expect_panel_install_denied(
			panel, work_context, "review_unknown_slot", component_id, item_form,
			"unknown_slot", "unknown slot"):
		return false

	var water_lot_id: String = "p12-denial/purified-water"
	var scrap_lot_id: String = "p12-denial/scrap-metal"
	if _playable.inventory_state.add_lot({
		"lot_id": water_lot_id, "item_id": "purified_water", "quantity": 1,
		"quality_score": 0.5, "quality_tier": "standard", "condition": 1.0,
		"origin": {"source": "p12-denial"},
	}) != 1 or _playable.inventory_state.add_lot({
		"lot_id": scrap_lot_id, "item_id": "scrap_metal", "quantity": 1,
		"quality_score": 0.5, "quality_tier": "standard", "condition": 1.0,
		"origin": {"source": "p12-denial"},
	}) != 1:
		_fail("production denial non-component lot fixture")
		return false
	if not _expect_start_install_denied(
			work_context, slot_id, "purified_water", "purified_water",
			"unknown_component", "water/non-component"):
		return false
	if not _expect_start_install_denied(
			work_context, slot_id, "review_unknown_component", "scrap_metal",
			"unknown_component", "unknown component"):
		return false
	if not _expect_start_install_denied(
			work_context, slot_id, component_id, "scrap_metal",
			"incompatible_item_form", "unknown/incompatible item form"):
		return false

	var physical_slots_before: Array = placement.physical_slots.duplicate(true)
	var slot_index: int = -1
	for index in range(placement.physical_slots.size()):
		var candidate_v: Variant = placement.physical_slots[index]
		if candidate_v is Dictionary \
				and str((candidate_v as Dictionary).get("slot_id", "")) == slot_id:
			slot_index = index
			break
	if slot_index < 0:
		_fail("production denial physical slot index")
		return false
	for profile_case in [
		{"profile_id": "", "label": "missing profile"},
		{"profile_id": "review_unknown_profile", "label": "unknown profile"},
	]:
		var changed_slot: Dictionary = slot.duplicate(true)
		changed_slot["component_slot_profile_id"] = str(profile_case.profile_id)
		placement.physical_slots[slot_index] = changed_slot
		if not _expect_start_install_denied(
				work_context, slot_id, component_id, item_form,
				"missing_fit_contract", str(profile_case.label)):
			placement.physical_slots = physical_slots_before
			return false
	placement.physical_slots = physical_slots_before.duplicate(true)

	var original_component: Dictionary = _playable.component_catalog.get_component(component_id)
	var wrong_slot_component: Dictionary = original_component.duplicate(true)
	wrong_slot_component["slot"] = "review_required_slot"
	_playable.component_catalog._components[component_id] = wrong_slot_component
	var incompatible_slot_passed: bool = _expect_start_install_denied(
			work_context, slot_id, component_id, item_form,
			"incompatible_slot", "incompatible slot")
	_playable.component_catalog._components[component_id] = original_component.duplicate(true)
	if not incompatible_slot_passed:
		return false

	var cases: Array[Dictionary] = [
		{"field": "footprint_cells", "value": [99, 99], "reason": "incompatible_footprint"},
		{"field": "socket_type", "value": "review_wrong_socket", "reason": "incompatible_socket"},
		{"field": "allowed_component_types", "value": ["review_wrong_type"], "reason": "incompatible_type"},
	]
	for case in cases:
		var changed_profile: Dictionary = original_profile.duplicate(true)
		changed_profile[str(case.field)] = case.value
		_playable.component_catalog._slot_profiles[profile_id] = changed_profile
		var passed: bool = _expect_start_install_denied(
			work_context, slot_id, component_id, item_form,
			str(case.reason), str(case.reason))
		_playable.component_catalog._slot_profiles[profile_id] = original_profile.duplicate(true)
		if not passed:
			return false

	if not placement.restore_dismounted(slot_id):
		_fail("production occupied-slot fixture")
		return false
	var occupied_passed: bool = _expect_start_install_denied(
		work_context, slot_id, component_id, item_form, "slot_occupied", "occupied slot")
	var occupied_restore: Dictionary = placement.dismount(slot_id)
	if not occupied_passed or not bool(occupied_restore.get("ok", false)):
		if occupied_passed:
			_fail("production occupied-slot fixture restore")
		return false

	var lifeboat = _playable.get_lifeboat_ship_for_validation()
	if lifeboat == null:
		_fail("production wrong-ship fixture")
		return false
	var select_other: Dictionary = _playable.select_ship_for_modification_for_validation(
		str(lifeboat.ship_id))
	if not bool(select_other.get("ok", false)):
		_fail("production wrong-ship selection: %s" % str(select_other))
		return false
	var wrong_ship_passed: bool = _expect_start_install_denied(
		work_context, slot_id, component_id, item_form, "wrong_ship", "wrong ship")
	var select_home: Dictionary = _playable.select_ship_for_modification_for_validation(ship_id)
	if not bool(select_home.get("ok", false)):
		_fail("production denial home reselection")
		return false
	if not wrong_ship_passed:
		return false
	panel = _playable.get_ship_modification_panel_for_validation()
	panel.select_slot_id(slot_id)
	panel.set_inventory(_playable.inventory_state.items)

	var removed_water: Array = _playable.inventory_state.take_lots(
		"purified_water", 1, PackedStringArray([water_lot_id]))
	var removed_scrap: Array = _playable.inventory_state.take_lots(
		"scrap_metal", 1, PackedStringArray([scrap_lot_id]))
	if removed_water.size() != 1 or removed_scrap.size() != 1:
		_fail("production denial lot cleanup")
		return false
	return true


func _expect_panel_install_denied(
		panel, work_context, slot_id: String, component_id: String, item_form: String,
		expected_reason: String, label: String) -> bool:
	var before: Dictionary = _authoritative_snapshot(work_context)
	panel.emit_install_request_for_validation(
		slot_id, component_id, item_form,
		str(work_context.ship_id), int(work_context.binding_generation))
	var after: Dictionary = _authoritative_snapshot(work_context)
	var status: String = str(panel.get("_status"))
	if not status.ends_with(expected_reason) \
			or _playable.has_active_ship_work_for_validation() or after != before:
		_fail("production %s panel denial mutated authority: %s" % [label, status])
		return false
	return true


func _expect_start_install_denied(
		work_context, slot_id: String, component_id: String, item_form: String,
		expected_reason: String, label: String) -> bool:
	var slot: Dictionary = work_context.component_placement.get_physical_slot(slot_id)
	var target_position: Variant = _playable._component_slot_world_position(slot_id, work_context)
	if slot.is_empty() or not _playable._work_position_is_finite(target_position):
		_fail("production %s target fixture" % label)
		return false
	(_playable.player as Node3D).global_position = target_position as Vector3
	var selected_ids: PackedStringArray = _playable._selected_lot_ids_for_requirements(
		{item_form: 1})
	if selected_ids.size() != 1:
		_fail("production %s selected-lot fixture" % label)
		return false
	var before: Dictionary = _authoritative_snapshot(work_context)
	var denied: Dictionary = _playable._start_transactional_work(
		"mount_component", slot_id, "component_install",
		_playable._component_slot_revision(slot_id, work_context), {
			"tool_class": "wrench", "skill_id": "salvage", "skill_level": 99,
			"inventory": _playable._inventory_qty_dict_for_work(),
		}, {
			"slot_id": slot_id, "component_id": component_id, "item_form": item_form,
			"room_id": str(slot.get("room_id", "")),
			"slot_kind": str(slot.get("slot_kind", "")),
			"slot_index": int(slot.get("slot_index", -1)),
		}, target_position, selected_ids, str(work_context.ship_id))
	var after: Dictionary = _authoritative_snapshot(work_context)
	if str(denied.get("reason", "")) != expected_reason \
			or _playable.has_active_ship_work_for_validation() or after != before:
		_fail("production %s denial mutated authority: %s" % [label, str(denied)])
		return false
	return true


func _validate_live_occupancy_refresh(
		slot_id: String, component_id: String, item_form: String) -> bool:
	var ship_id: String = _playable.get_selected_ship_id_for_validation()
	var work_context = _playable._ship_work_context_for(ship_id)
	var lifeboat = _playable.get_lifeboat_ship_for_validation()
	var target_position: Variant = _playable._component_slot_world_position(
		slot_id, work_context)
	if work_context == null or lifeboat == null or lifeboat == work_context.ship \
			or not (lifeboat.scene_root is Node3D) \
			or not _playable._work_position_is_finite(target_position):
		_fail("live occupancy-refresh fixture")
		return false
	var selected_ids: PackedStringArray = _playable._selected_lot_ids_for_requirements(
		{item_form: 1})
	if selected_ids.size() != 1:
		_fail("live occupancy-refresh selected lot")
		return false
	var slot: Dictionary = work_context.component_placement.get_physical_slot(slot_id)
	var payload: Dictionary = {
		"slot_id": slot_id, "component_id": component_id, "item_form": item_form,
		"room_id": str(slot.get("room_id", "")),
		"slot_kind": str(slot.get("slot_kind", "")),
		"slot_index": int(slot.get("slot_index", -1)),
	}
	var start_context: Dictionary = {
		"tool_class": "wrench", "skill_id": "salvage", "skill_level": 99,
		"inventory": _playable._inventory_qty_dict_for_work(),
	}
	var lifeboat_root: Node3D = lifeboat.scene_root as Node3D
	var lifeboat_transform: Transform3D = lifeboat_root.global_transform
	var target: Vector3 = target_position as Vector3
	var overlap_delta: Vector3 = target - lifeboat.interior_aabb().get_center()
	var overlap_transform: Transform3D = lifeboat_transform
	overlap_transform.origin += overlap_delta
	var far_transform: Transform3D = overlap_transform
	far_transform.origin += Vector3(10000.0, 0.0, 0.0)

	# Stale context says lifeboat while the actual player has just boarded the
	# selected home ship. Start must refresh attendance before constructing its
	# context and admit the paid work. The test deliberately does not recompute
	# between moving the lifeboat away and invoking production start.
	lifeboat_root.global_transform = overlap_transform
	(_playable.player as Node3D).global_position = target
	_playable.recompute_occupancy()
	if _playable.get_current_occupancy_for_validation() != lifeboat:
		_fail("live occupancy-refresh stale-away setup")
		return false
	lifeboat_root.global_transform = far_transform
	var board_before: Dictionary = _authoritative_snapshot(work_context)
	var board_started: Dictionary = _playable._start_transactional_work(
		"mount_component", slot_id, "component_install",
		_playable._component_slot_revision(slot_id, work_context), start_context,
		payload, target, selected_ids, ship_id)
	if not bool(board_started.get("ok", false)) \
			or _playable.get_current_occupancy_for_validation() != work_context.ship \
			or not _playable.has_active_ship_work_for_validation():
		_fail("live occupancy-refresh boarded admission: %s" % str(board_started))
		return false
	var board_record: Dictionary = _playable.get_active_ship_work_record_for_validation()
	var board_escrow: Array = (board_record.get("escrow", []) as Array).duplicate(true)
	var cancelled: Dictionary = _playable._cancel_active_ship_work("explicit_cancel")
	var board_after: Dictionary = _authoritative_snapshot(work_context)
	var cancelled_record: Dictionary = work_context.work_transactions.get_record(
		str(board_record.get("work_id", "")))
	if board_escrow.size() != 1 or cancelled.get("returned_lots", []) != board_escrow \
			or board_after.get("lots", {}) != board_before.get("lots", {}) \
			or not _same_authoritative_consequences(board_before, board_after) \
			or int(board_after.get("receipt_count", -1)) \
			!= int(board_before.get("receipt_count", -2)) \
			or str(cancelled_record.get("state", "")) != "cancelled" \
			or not (cancelled_record.get("escrow", []) as Array).is_empty():
		_fail("live occupancy-refresh boarded cancel recovery")
		return false

	# Stale context now says home while the actual player has just entered the
	# lifeboat at the same range point. The refreshed context must deny before a
	# work ID or escrow exists, with the entire authoritative snapshot unchanged.
	lifeboat_root.global_transform = far_transform
	(_playable.player as Node3D).global_position = target
	_playable.recompute_occupancy()
	if _playable.get_current_occupancy_for_validation() != work_context.ship:
		_fail("live occupancy-refresh stale-home setup")
		return false
	lifeboat_root.global_transform = overlap_transform
	var leave_before: Dictionary = _authoritative_snapshot(work_context)
	var leave_denied: Dictionary = _playable._start_transactional_work(
		"mount_component", slot_id, "component_install",
		_playable._component_slot_revision(slot_id, work_context), start_context,
		payload, target, selected_ids, ship_id)
	var leave_after: Dictionary = _authoritative_snapshot(work_context)
	if str(leave_denied.get("reason", "")) != "not_attending_target" \
			or _playable.get_current_occupancy_for_validation() != lifeboat \
			or _playable.has_active_ship_work_for_validation() \
			or leave_after != leave_before:
		_fail("live occupancy-refresh leave denial: %s" % str(leave_denied))
		return false

	lifeboat_root.global_transform = lifeboat_transform
	(_playable.player as Node3D).global_position = target
	_playable.recompute_occupancy()
	return true


func _validate_reserved_target_removal_cancel(
		panel, slot_id: String, item_form: String, exact_lot: Dictionary) -> bool:
	var ship_id: String = _playable.get_selected_ship_id_for_validation()
	var work_context = _playable._ship_work_context_for(ship_id)
	var placement = work_context.component_placement if work_context != null else null
	if work_context == null or placement == null:
		_fail("reserved target-removal context")
		return false
	var before: Dictionary = _authoritative_snapshot(work_context)
	panel.set_inventory(_playable.inventory_state.items)
	if not panel.install_from_inventory(
			_playable.component_catalog, PackedStringArray([item_form])):
		_fail("reserved target-removal start")
		return false
	var paid: Dictionary = _playable.get_active_ship_work_record_for_validation()
	var escrow: Array = (paid.get("escrow", []) as Array).duplicate(true)
	if escrow.size() != 1 or not (escrow[0] is Dictionary) \
			or str((escrow[0] as Dictionary).get("lot_id", "")) \
			!= str(exact_lot.get("lot_id", "")):
		_fail("reserved target-removal exact escrow: %s" % str(paid))
		return false
	var physical_slots_before: Array = placement.physical_slots.duplicate(true)
	var without_target: Array = []
	for slot_v in physical_slots_before:
		if slot_v is Dictionary and str((slot_v as Dictionary).get("slot_id", "")) == slot_id:
			continue
		without_target.append((slot_v as Dictionary).duplicate(true) if slot_v is Dictionary else slot_v)
	placement.physical_slots = without_target
	_playable.advance_active_ship_work_for_validation(0.5)
	placement.physical_slots = physical_slots_before
	var paused: Dictionary = _playable.get_active_ship_work_record_for_validation()
	var paused_snapshot: Dictionary = _authoritative_snapshot(work_context)
	if str(_playable.get_last_ship_work_result_for_validation().get("reason", "")) != "target_removed" \
			or str(paused.get("state", "")) != "paused" \
			or paused.get("escrow", []) != escrow \
			or not _same_authoritative_consequences(before, paused_snapshot):
		_fail("reserved removed target mutated consequence state: %s" % str(paused))
		return false
	var cancelled: Dictionary = _playable._cancel_active_ship_work("explicit_cancel")
	var after: Dictionary = _authoritative_snapshot(work_context)
	var cancelled_record: Dictionary = work_context.work_transactions.get_record(
		str(paid.get("work_id", "")))
	if not bool(cancelled.get("ok", false)) \
			or cancelled.get("returned_lots", []) != escrow \
			or after.get("lots", {}) != before.get("lots", {}) \
			or not _same_authoritative_consequences(before, after) \
			or int(after.get("receipt_count", -1)) != int(before.get("receipt_count", -2)) \
			or str(cancelled_record.get("state", "")) != "cancelled" \
			or not (cancelled_record.get("escrow", []) as Array).is_empty():
		_fail("reserved removed target did not recover exact escrow: %s" % str(cancelled))
		return false
	panel.set_inventory(_playable.inventory_state.items)
	return true


func _same_authoritative_consequences(before: Dictionary, after: Dictionary) -> bool:
	for key in [
		"placement", "integrity", "modification", "systems", "receipt_count", "effects",
		"threat_noise", "completion_audio", "training_log", "delivered_xp", "progression",
	]:
		if before.get(key) != after.get(key):
			return false
	return true


func _validate_moved_owner_position_rechecks(slot_id: String, work_context) -> bool:
	var owner_root = work_context.ship.scene_root if work_context != null else null
	if not (owner_root is Node3D):
		_fail("moved-owner active fixture")
		return false
	# Pause/resume gate: the cached point must be replaced by the live owner-space
	# point before range is evaluated.
	if not _playable.begin_p12_uninstall_for_validation(slot_id):
		_fail("moved-owner pause start")
		return false
	var active_before: Dictionary = _authoritative_snapshot(work_context)
	var target_before: Vector3 = _playable._active_ship_work_target_position
	var transform_before: Transform3D = (owner_root as Node3D).global_transform
	var movement: Vector3 = Vector3(_playable.WORK_ACTION_INTERACT_RANGE + 1.0, 0.0, 0.0)
	(owner_root as Node3D).global_position += movement
	_playable.advance_active_ship_work_for_validation(0.001)
	var moved_cached: Vector3 = _playable._active_ship_work_target_position
	(owner_root as Node3D).global_transform = transform_before
	var paused_after: Dictionary = _authoritative_snapshot(work_context)
	if str(_playable.get_last_ship_work_result_for_validation().get("reason", "")) != "out_of_range" \
			or moved_cached.distance_to(target_before + movement) > 0.01 \
			or not _same_authoritative_consequences(active_before, paused_after):
		_fail("moved-owner pause used stale target position")
		return false
	if not bool(_playable._cancel_active_ship_work("explicit_cancel").get("ok", false)):
		_fail("moved-owner pause cancel")
		return false

	# Commit gate: complete only the driver/ledger, then move the owner before the
	# production coordinator is asked to commit. No resolver or consequence may run.
	if not _playable.begin_p12_uninstall_for_validation(slot_id):
		_fail("moved-owner commit start")
		return false
	var ready_before: Dictionary = _authoritative_snapshot(work_context)
	var ready_id: String = str(_playable.get_active_ship_work_record_for_validation().get("work_id", ""))
	_playable.work_action_driver.tick(999.0, {})
	work_context.work_transactions.sync_progress(ready_id, _playable.work_action_driver)
	if not work_context.work_transactions.mark_completed(ready_id, _playable.work_action_driver):
		_fail("moved-owner ready fixture")
		return false
	transform_before = (owner_root as Node3D).global_transform
	(owner_root as Node3D).global_position += movement
	var denied_commit: Dictionary = _playable._commit_active_ship_work()
	moved_cached = _playable._active_ship_work_target_position
	(owner_root as Node3D).global_transform = transform_before
	var denied_after: Dictionary = _authoritative_snapshot(work_context)
	if str(denied_commit.get("reason", "")) != "out_of_range" \
			or moved_cached.distance_to(target_before + movement) > 0.01 \
			or not _same_authoritative_consequences(ready_before, denied_after):
		_fail("moved-owner commit used stale target position: %s" % str(denied_commit))
		return false
	if not bool(_playable._cancel_active_ship_work("explicit_cancel").get("ok", false)) \
			or not work_context.component_placement.is_mounted(slot_id):
		_fail("moved-owner commit cancel")
		return false
	return true


func _receipt_count(summary: Dictionary) -> int:
	var count: int = 0
	for record_v in summary.get("transactions", []) as Array:
		if record_v is Dictionary \
				and not str((record_v as Dictionary).get("commit_receipt_id", "")).is_empty():
			count += 1
	return count


func _validate_untransactioned_component_fails_closed(slot_id: String) -> bool:
	var ship_id: String = _playable.get_selected_ship_id_for_validation()
	var work_context = _playable._ship_work_context_for(ship_id)
	if work_context == null or _playable.has_active_ship_work_for_validation():
		_fail("untransactioned component fixture")
		return false
	var protected_before: Dictionary = {
		"inventory": _playable.inventory_state.get_summary(),
		"placement": work_context.component_placement.get_summary(),
		"ledger": work_context.work_transactions.get_summary(),
		"observables": _playable.get_ship_work_observable_counts_for_validation(),
		"training_log": _playable.get_training_event_bus().get_log(),
		"training_xp": _playable.get_training_event_bus().get_total_xp_delivered(),
		"progression": _playable.player_progression.get_summary(),
		"threat_noise": float(_playable.threat_manager.player_noise),
		"audio": _playable.audio_manager.sfx_router.get_summary(),
	}
	var started: bool = _playable.work_action_driver.start_action(
		"dismount_component", slot_id, {
			"tool_class": "wrench",
			"skill_id": "salvage",
			"skill_level": 99,
			"inventory": _playable._inventory_qty_dict_for_work(),
		})
	if not started:
		_fail("untransactioned component driver setup")
		return false
	_playable._tick_work_action(999.0)
	var denied: Dictionary = _playable.work_action_driver.last_resolve
	var protected_after: Dictionary = {
		"inventory": _playable.inventory_state.get_summary(),
		"placement": work_context.component_placement.get_summary(),
		"ledger": work_context.work_transactions.get_summary(),
		"observables": _playable.get_ship_work_observable_counts_for_validation(),
		"training_log": _playable.get_training_event_bus().get_log(),
		"training_xp": _playable.get_training_event_bus().get_total_xp_delivered(),
		"progression": _playable.player_progression.get_summary(),
		"threat_noise": float(_playable.threat_manager.player_noise),
		"audio": _playable.audio_manager.sfx_router.get_summary(),
	}
	if str(denied.get("reason", "")) != "missing_work_transaction" \
			or protected_after != protected_before \
			or _playable.has_active_ship_work_for_validation():
		_fail("untransactioned component path did not fail closed: %s" % str(denied))
		return false
	return true


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
