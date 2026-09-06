extends SceneTree

## FC-07..08 / P07: paid, independent, persistent station jobs.
## Marker: FC P07 PASS

const CraftJobSchedulerScript := preload("res://scripts/systems/craft_job_scheduler.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const PendingOutputStoreScript := preload("res://scripts/systems/pending_output_store.gd")
const RecipeKnowledgeStateScript := preload("res://scripts/systems/recipe_knowledge_state.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const ShipRuntimeScript := preload("res://scripts/systems/ship_runtime.gd")
const StationStateScript := preload("res://scripts/systems/station_state.gd")
const CraftingStationScript := preload("res://scripts/tools/crafting_station.gd")
const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

class SkillFixture extends RefCounted:
	func get_skill_level(_skill_id: String) -> int:
		return 6

class TierCatalogFixture extends RefCounted:
	func get_component(component_id: String) -> Dictionary:
		if component_id == "fabricator_upgrade":
			return {"station_tier_bonus": 2, "station_affinity": "fabricator"}
		return {}

const RECIPE_ID: String = "craft_power_cell"
const CRAFT_SECONDS: float = 30.0


func _initialize() -> void:
	var crafting = CraftingStateScript.new()
	if not _test_one_payment_one_receipt(crafting):
		return
	if not _test_independent_stations_and_round_trip(crafting):
		return
	if not _test_owner_boundaries(crafting):
		return
	if not _test_targeted_tier_refresh():
		return
	if not _test_revalidation_and_cancellation(crafting):
		return
	if not _test_capacity(crafting):
		return
	if not _test_escrow_mass_accounting(crafting):
		return
	if not _test_ship_runtime_catch_up(crafting):
		return
	if not _test_shared_scheduler_ship_snapshots(crafting):
		return
	if not _test_physical_station_nodes():
		return
	if not _test_production_runtime_binding():
		return
	if not _test_legacy_single_craft_uses_scheduler():
		return
	if not _test_strict_crafting_envelope():
		return
	print("FC P07 PASS")
	quit(0)


func _test_escrow_mass_accounting(crafting: RefCounted) -> bool:
	var scheduler = CraftJobSchedulerScript.new()
	var cargo = ShipInventoryScript.create(500.0, "ship:p07-mass:cargo")
	_add_standard_inputs(cargo, 2)
	var exact_full_mass: float = cargo.get_total_weight()
	cargo.max_weight = exact_full_mass
	var station_a = _station("ship-mass", "fabricator-mass-a", 0, true)
	var station_b = _station("ship-mass", "fabricator-mass-b", 0, true)
	var context: Dictionary = _context(
		crafting, cargo, {"a": station_a, "b": station_b}, 2)
	var a: Dictionary = scheduler.enqueue(
		_request("ship-mass", "fabricator-mass-a", cargo), context)
	var b: Dictionary = scheduler.enqueue(
		_request("ship-mass", "fabricator-mass-b", cargo), context)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return _fail_bool("mass fixtures could not reserve two jobs")
	if absf(cargo.get_total_weight() - exact_full_mass) > 0.0001 \
			or cargo.get_acceptable_quantity("scrap_metal", 1) != 0:
		return _fail_bool("escrow mass left its source cargo capacity")
	var cancel_a: Dictionary = scheduler.cancel(str(a.job_id), context)
	if not bool(cancel_a.get("ok", false)) \
			or absf(cargo.get_total_weight() - exact_full_mass) > 0.0001:
		return _fail_bool("own-reservation refund did not fit exactly-full cargo")
	var other_reserved: Array = scheduler.get_reservation_lots(
		str(b.job_id), cargo.get_holder_namespace())
	if other_reserved.is_empty() or cargo.get_acceptable_quantity("scrap_metal", 1) != 0:
		return _fail_bool("refund credit excluded another job's reserved mass")
	scheduler.advance(0.0, context)
	if cargo.get_total_weight() >= exact_full_mass:
		return _fail_bool("starting the remaining job did not consume reserved mass")
	return true


func _test_one_payment_one_receipt(crafting: RefCounted) -> bool:
	var scheduler = CraftJobSchedulerScript.new()
	var inventory = InventoryStateScript.new("player:p07-once")
	var selected: Dictionary = _add_exact_inputs(inventory, "once", 0.8)
	var station = _station("ship-once", "fabricator-a", 0, true)
	var context: Dictionary = _context(crafting, inventory, {"fabricator-a": station}, 2)
	var request: Dictionary = _request("ship-once", "fabricator-a", inventory, selected)
	var first: Dictionary = scheduler.enqueue(request, context)
	if not bool(first.get("ok", false)):
		return _fail_bool("first paid enqueue failed: %s" % str(first))
	var job_id: String = str(first.get("job_id", ""))
	if job_id != "ship-once/fabricator-a/job-000001":
		return _fail_bool("job id was not stable and owner-namespaced: %s" % job_id)
	if inventory.get_quantity("scrap_metal") != 0 \
			or inventory.get_quantity("wiring_bundle") != 0 \
			or inventory.get_quantity("reactive_gel") != 0:
		return _fail_bool("enqueue did not reserve exact inputs")
	var queued: Dictionary = scheduler.get_job(job_id)
	if str(queued.get("state", "")) != "queued" \
			or _lot_ids(queued.get("ingredient_escrow", [])) != _flatten_selected_ids(selected):
		return _fail_bool("queued escrow lost selected lots: %s" % str(queued))
	var denied: Dictionary = scheduler.enqueue(request, context)
	if bool(denied.get("ok", true)) or str(denied.get("reason", "")) != "missing_materials":
		return _fail_bool("one payment admitted a second job: %s" % str(denied))

	var events: Array = scheduler.advance(CRAFT_SECONDS, context)
	if events.size() != 1 or str((events[0] as Dictionary).get("job_id", "")) != job_id:
		return _fail_bool("first completion did not emit one owned receipt: %s" % str(events))
	var receipt_id: String = str((events[0] as Dictionary).get("receipt_id", ""))
	if receipt_id != "%s/output" % job_id:
		return _fail_bool("completion receipt was not stable: %s" % receipt_id)
	if not scheduler.advance(CRAFT_SECONDS, context).is_empty():
		return _fail_bool("repeated tick emitted a second completion receipt")
	var claimed: Dictionary = scheduler.claim_output(job_id)
	var replay: Dictionary = scheduler.claim_output(job_id)
	if not bool(claimed.get("ok", false)) \
			or str(claimed.get("receipt_id", "")) != receipt_id \
			or bool(replay.get("ok", true)) \
			or str(replay.get("reason", "")) != "already_collected":
		return _fail_bool("output claim was not exactly once: %s / %s" % [str(claimed), str(replay)])
	var output_lots: Array = claimed.get("output_lots", [])
	if output_lots.size() != 1 \
			or str((output_lots[0] as Dictionary).get("item_id", "")) != "power_cell" \
			or int((output_lots[0] as Dictionary).get("quantity", 0)) != 1 \
			or float((output_lots[0] as Dictionary).get("quality_score", 0.0)) <= 0.0:
		return _fail_bool("completion did not retain immutable output lot metadata")
	var origin: Dictionary = (output_lots[0] as Dictionary).get("origin", {}) as Dictionary
	if absf(float(origin.get("input_quality_score", -1.0)) - 0.8) > 0.0001 \
			or (origin.get("input_lot_ids", []) as Array) != _flatten_selected_ids(selected):
		return _fail_bool("output quality did not derive from the exact escrow lots")
	return true


func _test_independent_stations_and_round_trip(crafting: RefCounted) -> bool:
	var scheduler = CraftJobSchedulerScript.new()
	var inventory = InventoryStateScript.new("player:p07-parallel")
	_add_standard_inputs(inventory, 2)
	var station_a = _station("ship-parallel", "fabricator-a", 0, true)
	var station_b = _station("ship-parallel", "fabricator-b", 0, true)
	var stations: Dictionary = {"fabricator-a": station_a, "fabricator-b": station_b}
	var context: Dictionary = _context(crafting, inventory, stations, 2)
	var a: Dictionary = scheduler.enqueue(
		_request("ship-parallel", "fabricator-a", inventory), context)
	var b: Dictionary = scheduler.enqueue(
		_request("ship-parallel", "fabricator-b", inventory), context)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return _fail_bool("same-kind stations could not reserve independent jobs")
	var a_id: String = str(a.get("job_id", ""))
	var b_id: String = str(b.get("job_id", ""))
	if a_id == b_id or not a_id.contains("fabricator-a") or not b_id.contains("fabricator-b"):
		return _fail_bool("same-kind station job identities collided")
	scheduler.advance(10.0, context)
	if not _progress_is(scheduler, a_id, 10.0) or not _progress_is(scheduler, b_id, 10.0):
		return _fail_bool("different stations did not advance independently")

	# Strict current summaries round-trip exactly. A malformed present payload is
	# rejected atomically instead of partially replacing restored station queues.
	var summary: Dictionary = scheduler.get_summary()
	var restored = CraftJobSchedulerScript.new()
	restored.configure_recipe_authority(crafting)
	if not restored.apply_summary(summary) or restored.get_summary() != summary:
		return _fail_bool("scheduler summary did not round-trip exactly")
	var before_bad: Dictionary = restored.get_summary()
	var malformed: Dictionary = summary.duplicate(true)
	var malformed_jobs: Array = malformed.get("jobs", [])
	malformed_jobs.append((malformed_jobs[0] as Dictionary).duplicate(true))
	malformed["jobs"] = malformed_jobs
	if restored.apply_summary(malformed) or restored.get_summary() != before_bad:
		return _fail_bool("malformed present job summary mutated scheduler state")

	station_a.set_power(false)
	restored.advance(10.0, context)
	var paused_a: Dictionary = restored.get_job(a_id)
	if str(paused_a.get("state", "")) != "paused_power" \
			or not _progress_is(restored, a_id, 10.0) \
			or not _progress_is(restored, b_id, 20.0):
		return _fail_bool("power pause leaked across same-kind stations")
	station_a.set_power(true)
	var finish_events: Array = restored.advance(10.0, context)
	if not _progress_is(restored, a_id, 20.0) \
			or str(restored.get_job(b_id).get("state", "")) != "output_ready" \
			or finish_events.size() != 1:
		return _fail_bool("resumed station or independent completion was incorrect")
	return true


func _test_owner_boundaries(crafting: RefCounted) -> bool:
	var scheduler = CraftJobSchedulerScript.new()
	var inventory_a = InventoryStateScript.new("player:p07-owner-a")
	var inventory_b = InventoryStateScript.new("player:p07-owner-b")
	_add_standard_inputs(inventory_a, 1)
	_add_standard_inputs(inventory_b, 1)
	var station_a = _station("ship-a", "shared", 0, true)
	var station_b = _station("ship-b", "shared", 0, true)
	var forged_context: Dictionary = _context(
		crafting, inventory_a, {"real": station_a}, 2)
	forged_context.stations[_owner_key("ship-forged", "shared")] = station_a
	var forged: Dictionary = scheduler.enqueue(
		_request("ship-forged", "shared", inventory_a), forged_context)
	if bool(forged.get("ok", true)) or str(forged.get("reason", "")) != "owner_mismatch" \
			or inventory_a.get_quantity("scrap_metal") != 1:
		return _fail_bool("forged station owner was accepted or mutated inventory")
	var context_a: Dictionary = _context(crafting, inventory_a, {"a": station_a}, 2)
	var admitted: Dictionary = scheduler.enqueue(_request("ship-a", "shared", inventory_a), context_a)
	if not bool(admitted.get("ok", false)):
		return _fail_bool("real owner fixture enqueue failed")
	var wrong_holder_context: Dictionary = context_a.duplicate(false)
	wrong_holder_context["source_inventory"] = inventory_b
	var before_wrong_holder: Dictionary = scheduler.get_job(str(admitted.get("job_id", "")))
	var wrong_holder_cancel: Dictionary = scheduler.cancel(
		str(admitted.get("job_id", "")), wrong_holder_context)
	if bool(wrong_holder_cancel.get("ok", true)) \
			or str(wrong_holder_cancel.get("reason", "")) != "source_holder_mismatch" \
			or scheduler.get_job(str(admitted.get("job_id", ""))) != before_wrong_holder:
		return _fail_bool("refund accepted a foreign holder namespace")
	var context_b: Dictionary = _context(crafting, inventory_b, {"b": station_b}, 2)
	context_b["ship_id"] = "ship-b"
	var job_id: String = str(admitted.get("job_id", ""))
	var before_job: Dictionary = scheduler.get_job(job_id)
	var cross_cancel: Dictionary = scheduler.cancel(job_id, context_b)
	if bool(cross_cancel.get("ok", true)) or str(cross_cancel.get("reason", "")) != "wrong_ship" \
			or scheduler.get_job(job_id) != before_job:
		return _fail_bool("cross-ship cancellation mutated another ship's job")
	# The same local station ID on another ship remains an independent owner.
	var admitted_b: Dictionary = scheduler.enqueue(_request("ship-b", "shared", inventory_b), context_b)
	if not bool(admitted_b.get("ok", false)) \
			or str(admitted_b.get("job_id", "")) == job_id:
		return _fail_bool("same-local-ID station owners collided across ships")
	return true


func _test_targeted_tier_refresh() -> bool:
	var crafting = CraftingStateScript.new()
	var home = crafting.get_or_create_station_instance(
		"ship-tier-home", "shared", "fabricator")
	var away = crafting.get_or_create_station_instance(
		"ship-tier-away", "shared", "fabricator")
	var placed: Array = [{"component_id": "fabricator_upgrade", "mounted": true}]
	if crafting.refresh_station_tier(
			"fabricator", placed, TierCatalogFixture.new(),
			"ship-tier-home", "shared") != 2 \
			or int(home.call("effective_tier")) != 2 \
			or int(away.call("effective_tier")) != 0:
		return _fail_bool("targeted tier refresh leaked across physical ship owners")
	return true


func _test_revalidation_and_cancellation(crafting: RefCounted) -> bool:
	var scheduler = CraftJobSchedulerScript.new()
	var inventory = InventoryStateScript.new("player:p07-revalidate")
	inventory.add_item("titanium_ingot", 2)
	inventory.add_item("ceramic_plate", 2)
	inventory.add_item("coolant_fluid", 1)
	var station = _station("ship-revalidate", "fabricator-tier2", 2, true)
	var knowledge = RecipeKnowledgeStateScript.new()
	knowledge.configure("player:p07", crafting.get_recipe_catalog())
	knowledge.learn("craft_thruster_nozzle")
	var context: Dictionary = _context(
		crafting, inventory, {"fabricator-tier2": station}, 4, knowledge)
	var request: Dictionary = _request(
		"ship-revalidate", "fabricator-tier2", inventory, {}, "craft_thruster_nozzle")
	var admitted: Dictionary = scheduler.enqueue(request, context)
	if not bool(admitted.get("ok", false)):
		return _fail_bool("revalidation fixture enqueue failed: %s" % str(admitted))
	var job_id: String = str(admitted.get("job_id", ""))
	knowledge.apply_summary({"owner_id": "player:p07", "known_recipe_ids": []})
	scheduler.advance(0.0, context)
	if str(scheduler.get_job(job_id).get("blocked_reason", "")) != "missing_recipe_knowledge":
		return _fail_bool("knowledge was not revalidated at start")
	knowledge.learn("craft_thruster_nozzle")
	context["player_skill_level"] = 3
	scheduler.advance(0.0, context)
	if str(scheduler.get_job(job_id).get("blocked_reason", "")) != "insufficient_skill":
		return _fail_bool("skill was not revalidated at start")
	context["player_skill_level"] = 4
	station.level = 0
	station.tier = 0
	scheduler.advance(0.0, context)
	if str(scheduler.get_job(job_id).get("blocked_reason", "")) != "insufficient_tier":
		return _fail_bool("effective station tier was not revalidated at start")
	station.tier = 2
	scheduler.advance(0.0, context)
	var running: Dictionary = scheduler.get_job(job_id)
	if str(running.get("state", "")) != "running" \
			or not (running.get("ingredient_escrow", []) as Array).is_empty() \
			or (running.get("consumed_lots", []) as Array).is_empty() \
			or int(running.get("input_skill_level", -1)) != 4 \
			or int(running.get("station_effective_tier", -1)) != 2:
		return _fail_bool("start did not consume escrow once and freeze input context")
	var forfeited: Dictionary = scheduler.cancel(job_id, context)
	if not bool(forfeited.get("ok", false)) \
			or str(forfeited.get("warning", "")) != "inputs_forfeited" \
			or str(scheduler.get_job(job_id).get("state", "")) != "cancelled":
		return _fail_bool("started cancellation did not report forfeited inputs")

	# Unstarted cancellation returns the exact stable lot identities.
	var refund_scheduler = CraftJobSchedulerScript.new()
	var refund_inventory = InventoryStateScript.new("player:p07-refund")
	var selected: Dictionary = _add_exact_inputs(refund_inventory, "refund", 0.6)
	var refund_station = _station("ship-refund", "fabricator-refund", 0, true)
	var refund_context: Dictionary = _context(
		crafting, refund_inventory, {"fabricator-refund": refund_station}, 2)
	var refund_enqueue: Dictionary = refund_scheduler.enqueue(
		_request("ship-refund", "fabricator-refund", refund_inventory, selected), refund_context)
	var refund: Dictionary = refund_scheduler.cancel(str(refund_enqueue.get("job_id", "")), refund_context)
	if not bool(refund.get("ok", false)) \
			or str(refund.get("result", "")) != "refunded" \
			or _inventory_lot_ids(refund_inventory) != _flatten_selected_ids(selected):
		return _fail_bool("unstarted cancel did not refund exact lots: %s" % str(refund))

	# A full destination returns the still-owned escrow as a recoverable refund;
	# no partial restore or lot loss is allowed.
	var full_scheduler = CraftJobSchedulerScript.new()
	var full_inventory = InventoryStateScript.new("player:p07-refund-full")
	var full_selected: Dictionary = _add_exact_inputs(full_inventory, "full", 0.7)
	var full_station = _station("ship-refund", "fabricator-full", 0, true)
	var full_context: Dictionary = _context(
		crafting, full_inventory, {"fabricator-full": full_station}, 2)
	var full_enqueue: Dictionary = full_scheduler.enqueue(
		_request("ship-refund", "fabricator-full", full_inventory, full_selected), full_context)
	full_inventory.add_item("scrap_metal", 99)
	var full_job_id: String = str(full_enqueue.get("job_id", ""))
	var blocked_refund: Dictionary = full_scheduler.cancel(full_job_id, full_context)
	if bool(blocked_refund.get("ok", true)) \
			or str(blocked_refund.get("reason", "")) != "refund_destination_full" \
			or _lot_ids(blocked_refund.get("recoverable_refund", [])) != _flatten_selected_ids(full_selected) \
			or _lot_ids(full_scheduler.get_job(full_job_id).get("ingredient_escrow", [])) != _flatten_selected_ids(full_selected):
		return _fail_bool("full-holder refund was not recoverable without loss")
	return true


func _test_capacity(crafting: RefCounted) -> bool:
	var scheduler = CraftJobSchedulerScript.new()
	var inventory = InventoryStateScript.new("player:p07-capacity")
	_add_standard_inputs(inventory, 9)
	var station = _station("ship-capacity", "fabricator-capacity", 0, true)
	var context: Dictionary = _context(
		crafting, inventory, {"fabricator-capacity": station}, 2)
	var request: Dictionary = _request("ship-capacity", "fabricator-capacity", inventory)
	for index in range(8):
		var result: Dictionary = scheduler.enqueue(request, context)
		if not bool(result.get("ok", false)):
			return _fail_bool("capacity rejected paid job %d: %s" % [index + 1, str(result)])
	var ninth: Dictionary = scheduler.enqueue(request, context)
	if bool(ninth.get("ok", true)) or str(ninth.get("reason", "")) != "queue_full":
		return _fail_bool("ninth queued job did not receive queue_full: %s" % str(ninth))
	var serial_events: Array = scheduler.advance(45.0, context)
	var first_id: String = "ship-capacity/fabricator-capacity/job-000001"
	var second_id: String = "ship-capacity/fabricator-capacity/job-000002"
	if serial_events.size() != 1 \
			or str(scheduler.get_job(first_id).get("state", "")) != "output_ready" \
			or not _progress_is(scheduler, second_id, 15.0):
		return _fail_bool("same-station jobs did not execute serially")
	return true


func _test_ship_runtime_catch_up(crafting: RefCounted) -> bool:
	var scheduler = CraftJobSchedulerScript.new()
	var inventory = InventoryStateScript.new("player:p07-runtime")
	_add_standard_inputs(inventory, 1)
	var station = _station("ship-runtime", "fabricator-runtime", 0, false)
	var context: Dictionary = _context(
		crafting, inventory, {"fabricator-runtime": station}, 2)
	context["ship_id"] = "ship-runtime"
	var enqueue_result: Dictionary = scheduler.enqueue(
		_request("ship-runtime", "fabricator-runtime", inventory), context)
	var job_id: String = str(enqueue_result.get("job_id", ""))
	var ship = ShipInstanceScript.create("ship-runtime", "marker:p07", null, null, null)
	ship.last_sim_time = 0.0
	var runtime = ShipRuntimeScript.new()
	runtime.configure(ship, {
		"is_home": false,
		"craft_job_scheduler": scheduler,
		"craft_job_context_provider": func() -> Dictionary: return context,
	})
	runtime.catch_up(15.0)
	if str(scheduler.get_job(job_id).get("state", "")) != "paused_power" \
			or not _progress_is(scheduler, job_id, 0.0):
		return _fail_bool("unpowered catch-up advanced the job")
	station.set_power(true)
	runtime.catch_up(30.0)
	if not _progress_is(scheduler, job_id, 15.0):
		return _fail_bool("resumed catch-up did not advance exactly the elapsed gap")
	var before_repeat: Dictionary = scheduler.get_job(job_id)
	runtime.catch_up(30.0)
	if scheduler.get_job(job_id) != before_repeat:
		return _fail_bool("same-world-time catch-up double-ticked the job")
	runtime.catch_up(45.0)
	if str(scheduler.get_job(job_id).get("state", "")) != "output_ready":
		return _fail_bool("interrupted catch-up did not finish after powered time")
	var snapshot: Dictionary = runtime.to_snapshot()
	if not snapshot.get("craft_jobs_v1", null) is Dictionary:
		return _fail_bool("ShipRuntime did not retain the scheduler summary")
	var restored_scheduler = CraftJobSchedulerScript.new()
	restored_scheduler.configure_recipe_authority(crafting)
	var restored_ship = ShipInstanceScript.create("ship-runtime", "marker:p07", null, null, null)
	var restored_runtime = ShipRuntimeScript.new()
	restored_runtime.configure(restored_ship, {"craft_job_scheduler": restored_scheduler})
	if not restored_runtime.from_snapshot(snapshot):
		return _fail_bool("ShipRuntime rejected a valid craft-job snapshot")
	if restored_scheduler.get_summary() != snapshot.craft_jobs_v1:
		return _fail_bool("ShipRuntime craft-job snapshot did not round-trip")
	var before_bad: Dictionary = restored_scheduler.get_summary()
	var before_time: float = float(restored_ship.last_sim_time)
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed["craft_jobs_v1"] = {"schema": "craft-jobs-2", "jobs": "bad", "owners": []}
	malformed["last_sim_time"] = 999.0
	if restored_runtime.from_snapshot(malformed) \
			or restored_scheduler.get_summary() != before_bad \
			or absf(float(restored_ship.last_sim_time) - before_time) > 0.0001:
		return _fail_bool("ShipRuntime malformed-present job restore was not fail-closed")
	return true


func _test_shared_scheduler_ship_snapshots(crafting: RefCounted) -> bool:
	var scheduler = CraftJobSchedulerScript.new()
	var inventory_a = InventoryStateScript.new("player:p07-snapshot-a")
	var inventory_b = InventoryStateScript.new("player:p07-snapshot-b")
	_add_standard_inputs(inventory_a, 1)
	_add_standard_inputs(inventory_b, 1)
	var station_a = _station("ship-snapshot-a", "shared", 0, true)
	var station_b = _station("ship-snapshot-b", "shared", 0, true)
	var context_a: Dictionary = _context(crafting, inventory_a, {"a": station_a}, 2)
	context_a["ship_id"] = "ship-snapshot-a"
	var context_b: Dictionary = _context(crafting, inventory_b, {"b": station_b}, 2)
	context_b["ship_id"] = "ship-snapshot-b"
	var enqueue_a: Dictionary = scheduler.enqueue(
		_request("ship-snapshot-a", "shared", inventory_a), context_a)
	var enqueue_b: Dictionary = scheduler.enqueue(
		_request("ship-snapshot-b", "shared", inventory_b), context_b)
	if not bool(enqueue_a.get("ok", false)) or not bool(enqueue_b.get("ok", false)):
		return _fail_bool("two-ship snapshot fixture enqueue failed")
	var ship_a = ShipInstanceScript.create("ship-snapshot-a", "marker:a", null, null, null)
	var ship_b = ShipInstanceScript.create("ship-snapshot-b", "marker:b", null, null, null)
	var runtime_a = ShipRuntimeScript.new()
	var runtime_b = ShipRuntimeScript.new()
	runtime_a.configure(ship_a, {
		"craft_job_scheduler": scheduler,
		"craft_job_context_provider": func() -> Dictionary: return context_a,
	})
	runtime_b.configure(ship_b, {
		"craft_job_scheduler": scheduler,
		"craft_job_context_provider": func() -> Dictionary: return context_b,
	})
	var snapshot_a: Dictionary = runtime_a.to_snapshot()
	var snapshot_b: Dictionary = runtime_b.to_snapshot()
	var jobs_a: Array = (snapshot_a.craft_jobs_v1 as Dictionary).jobs
	var jobs_b: Array = (snapshot_b.craft_jobs_v1 as Dictionary).jobs
	if jobs_a.size() != 1 or jobs_b.size() != 1 \
			or str((jobs_a[0] as Dictionary).get("ship_id", "")) != "ship-snapshot-a" \
			or str((jobs_b[0] as Dictionary).get("ship_id", "")) != "ship-snapshot-b":
		return _fail_bool("per-ship runtime snapshot leaked another ship's job")
	var a_id: String = str(enqueue_a.job_id)
	var b_id: String = str(enqueue_b.job_id)
	var before_a: Dictionary = scheduler.get_job(a_id)
	var before_b: Dictionary = scheduler.get_job(b_id)
	var wrong_outer_owner: Dictionary = snapshot_b.duplicate(true)
	wrong_outer_owner["ship_id"] = "ship-snapshot-a"
	if runtime_b.from_snapshot(wrong_outer_owner) \
			or scheduler.get_job(a_id) != before_a \
			or scheduler.get_job(b_id) != before_b:
		return _fail_bool("ShipRuntime accepted a cross-owner outer snapshot")
	runtime_b.advance(10.0, 10.0)
	if not _progress_is(scheduler, b_id, 10.0):
		return _fail_bool("ship-B mutation fixture did not advance")
	if not runtime_b.from_snapshot(snapshot_b) \
			or scheduler.get_job(a_id) != before_a \
			or not _progress_is(scheduler, b_id, 0.0):
		return _fail_bool("ship-scoped restore replaced another owner or failed to reset B")
	return true


func _test_physical_station_nodes() -> bool:
	var coordinator = PlayableGeneratedShipScript.new()
	var station_a_id: String = str(coordinator.call(
		"_crafting_station_instance_id", "fabricator", Vector3(1.0, 0.6, 2.0)))
	var station_b_id: String = str(coordinator.call(
		"_crafting_station_instance_id", "fabricator", Vector3(3.0, 0.6, 2.0)))
	var station_a_repeat: String = str(coordinator.call(
		"_crafting_station_instance_id", "fabricator", Vector3(1.0, 0.6, 2.0)))
	coordinator.free()
	if station_a_id.is_empty() or station_a_id == station_b_id or station_a_id != station_a_repeat:
		return _fail_bool("canonical physical station IDs were unstable or collided")
	var crafting = CraftingStateScript.new()
	var inventory = InventoryStateScript.new("player:p07-physical")
	_add_standard_inputs(inventory, 2)
	var material = MaterialStateScript.new()
	var skill = SkillFixture.new()
	var station_a = CraftingStationScript.new()
	var station_b = CraftingStationScript.new()
	var pending_store = PendingOutputStoreScript.new()
	pending_store.configure("ship-home")
	station_a.configure("fabricator", crafting, material, inventory, RefCounted.new(), skill,
		Vector3(1.0, 0.6, 2.0), 1.8, null, "ship-home", station_a_id, pending_store)
	station_b.configure("fabricator", crafting, material, inventory, RefCounted.new(), skill,
		Vector3(3.0, 0.6, 2.0), 1.8, null, "ship-home", station_b_id, pending_store)
	if not station_a.try_craft_recipe(RECIPE_ID) or not station_b.try_craft_recipe(RECIPE_ID):
		station_a.free()
		station_b.free()
		return _fail_bool("real same-kind CraftingStation nodes did not start independently")
	var owners: Array = (crafting.get_summary().craft_jobs_v1 as Dictionary).get("owners", [])
	var both_ready: bool = crafting.tick(CRAFT_SECONDS)
	var first_output: Dictionary = crafting.finish_craft()
	var second_still_pending: bool = crafting.tick(0.0)
	var second_output: Dictionary = crafting.finish_craft()
	var no_third: bool = crafting.finish_craft().is_empty()
	station_a.free()
	station_b.free()
	if owners.size() != 2 or not both_ready or not second_still_pending \
			or str(first_output.get("item_id", "")) != "power_cell" \
			or str(second_output.get("item_id", "")) != "power_cell" or not no_third:
		return _fail_bool("real station owners or simultaneous receipt drain were incorrect")
	return true


func _test_production_runtime_binding() -> bool:
	var playable = PlayableGeneratedShipScript.new()
	var crafting = CraftingStateScript.new()
	var inventory = InventoryStateScript.new("player:p07-production")
	_add_standard_inputs(inventory, 1)
	var ship = ShipInstanceScript.create("ship-production", "marker:p07-production", null, null, null)
	var station_id: String = str(playable.call(
		"_crafting_station_instance_id", "fabricator", Vector3(2.0, 0.6, 4.0)))
	crafting.bind_station_runtime_context(
		ship.ship_id, station_id, "fabricator", inventory, null, SkillFixture.new(),
		ship.get_pending_output_store())
	if not crafting.begin_craft(
			RECIPE_ID, inventory, MaterialStateScript.new(), 6, null, ship.ship_id, station_id):
		playable.free()
		return _fail_bool("production runtime fixture could not start its physical job")
	var job_id: String = str(crafting.get_summary().active_craft.get("job_id", ""))
	playable.crafting_state = crafting
	playable.home_ship = ship
	playable.world_time = CRAFT_SECONDS
	playable.call("_advance_ship", ship, CRAFT_SECONDS)
	var ready: bool = str(crafting.get_craft_job_scheduler().call(
		"get_job", job_id).get("state", "")) == "output_ready"
	var receipt_ready: bool = crafting.has_completion_receipts()
	playable.call("_advance_ship", ship, CRAFT_SECONDS)
	var once: bool = crafting.has_completion_receipts()
	var output: Dictionary = crafting.finish_craft()
	playable.free()
	if not ready or not receipt_ready or not once \
			or str(output.get("item_id", "")) != "power_cell" \
			or not crafting.finish_craft().is_empty():
		return _fail_bool("coordinator ShipRuntime binding did not tick/receipt exactly once")
	return true


func _test_legacy_single_craft_uses_scheduler() -> bool:
	# A denied legacy attempt may create its synthetic physical projection before
	# callers upgrade the established generic station API. Retry must see that
	# generic tier without collapsing real physical station tiers.
	var compatibility = CraftingStateScript.new()
	var compatibility_inventory = InventoryStateScript.new("player:p07-legacy-tier")
	compatibility_inventory.add_item("titanium_ingot", 2)
	compatibility_inventory.add_item("ceramic_plate", 2)
	compatibility_inventory.add_item("coolant_fluid", 1)
	var compatibility_knowledge = RecipeKnowledgeStateScript.new()
	compatibility_knowledge.configure(
		"player:p07-legacy-tier", compatibility.get_recipe_catalog())
	if compatibility.begin_craft(
			"craft_thruster_nozzle", compatibility_inventory,
			MaterialStateScript.new(), 6, compatibility_knowledge):
		return _fail_bool("legacy compatibility fixture bypassed knowledge")
	compatibility.get_or_create_station("fabricator").level = 2
	compatibility_knowledge.learn("craft_thruster_nozzle")
	if not compatibility.begin_craft(
			"craft_thruster_nozzle", compatibility_inventory,
			MaterialStateScript.new(), 6, compatibility_knowledge):
		return _fail_bool("legacy synthetic station did not observe generic tier retry")

	var crafting = CraftingStateScript.new()
	var inventory = InventoryStateScript.new("player:p07-legacy")
	_add_standard_inputs(inventory, 1)
	var material = MaterialStateScript.new()
	material.set_quality("scrap_metal", 0.0)
	material.set_quality("wiring_bundle", 0.0)
	material.set_quality("reactive_gel", 0.0)
	if not crafting.begin_craft(RECIPE_ID, inventory, material, 2):
		return _fail_bool("legacy begin_craft did not route through paid scheduler")
	var summary: Dictionary = crafting.get_summary()
	if not summary.get("craft_jobs_v1", null) is Dictionary \
			or str(summary.get("active_craft", {}).get("job_id", "")).is_empty():
		return _fail_bool("legacy active craft has no scheduler authority")
	var restored = CraftingStateScript.new()
	if not restored.apply_summary(summary) \
			or not restored.bind_station_runtime_context(
				"legacy-crafting", "legacy:fabricator", "fabricator", inventory):
		return _fail_bool("restored station job did not rebind its live dependencies")
	if not restored.tick(CRAFT_SECONDS):
		return _fail_bool("restored legacy scheduler craft did not complete")
	var output: Dictionary = restored.finish_craft()
	if str(output.get("item_id", "")) != "power_cell" \
			or int(output.get("quantity", 0)) != 1 \
			or not restored.finish_craft().is_empty():
		return _fail_bool("legacy finish produced zero or duplicate outputs")
	return true


func _test_strict_crafting_envelope() -> bool:
	var crafting = CraftingStateScript.new()
	var inventory = InventoryStateScript.new("player:p07-strict")
	_add_standard_inputs(inventory, 1)
	if not crafting.begin_craft(
			RECIPE_ID, inventory, MaterialStateScript.new(), 2, null,
			"ship-strict", "fabricator-strict"):
		return _fail_bool("strict envelope fixture could not start")
	var before: Dictionary = crafting.get_summary()
	var job_id: String = str((before.active_craft as Dictionary).get("job_id", ""))
	var missing_owner_cancel: Dictionary = crafting.cancel_job(job_id)
	var wrong_ship_cancel: Dictionary = crafting.cancel_job(
		job_id, "ship-foreign", "fabricator-strict")
	if str(missing_owner_cancel.get("reason", "")) != "missing_owner" \
			or str(wrong_ship_cancel.get("reason", "")) != "wrong_ship" \
			or crafting.get_summary() != before:
		return _fail_bool("CraftingState cross-owner cancellation was not fail-closed")
	var malformed_rows: Dictionary = before.duplicate(true)
	malformed_rows["physical_station_summaries"] = {
		(malformed_rows.physical_station_summaries as Dictionary).keys()[0]: "bad",
	}
	if crafting.apply_summary(malformed_rows) or crafting.get_summary() != before:
		return _fail_bool("malformed physical row partially restored current state")
	var wrong_key: Dictionary = before.duplicate(true)
	var physical_row: Dictionary = (wrong_key.physical_station_summaries as Dictionary).values()[0]
	wrong_key["physical_station_summaries"] = {"wrong-owner-key": physical_row}
	if crafting.apply_summary(wrong_key) or crafting.get_summary() != before:
		return _fail_bool("mismatched physical owner key mutated current state")
	var ghost: Dictionary = before.duplicate(true)
	ghost["active_craft"] = {
		"job_id": "ghost/job-000001",
		"ship_id": "ghost",
		"station_instance_id": "ghost",
		"recipe_id": RECIPE_ID,
		"station_kind": "fabricator",
	}
	if crafting.apply_summary(ghost) or crafting.get_summary() != before:
		return _fail_bool("ghost active projection was accepted")
	var numeric: Dictionary = before.duplicate(true)
	var numeric_jobs: Array = (numeric.craft_jobs_v1 as Dictionary).jobs
	(numeric_jobs[0] as Dictionary)["ship_id"] = 7
	if crafting.apply_summary(numeric) or crafting.get_summary() != before:
		return _fail_bool("numeric current identity was coerced or mutated state")
	var numeric_lot: Dictionary = before.duplicate(true)
	var current_jobs: Array = (numeric_lot.craft_jobs_v1 as Dictionary).jobs
	var consumed: Array = (current_jobs[0] as Dictionary).consumed_lots
	(consumed[0] as Dictionary)["lot_id"] = 7
	if crafting.apply_summary(numeric_lot) or crafting.get_summary() != before:
		return _fail_bool("numeric nested lot identity was coerced or mutated state")
	var forged_output: Dictionary = before.duplicate(true)
	var forged_jobs: Array = (forged_output.craft_jobs_v1 as Dictionary).jobs
	var forged_lots: Array = (forged_jobs[0] as Dictionary).output_lots
	(forged_lots[0] as Dictionary)["item_id"] = "forged_relic"
	(forged_lots[0] as Dictionary)["quantity"] = 999
	if crafting.apply_summary(forged_output) or crafting.get_summary() != before:
		return _fail_bool("forged output semantics were accepted or mutated state")

	var queued_crafting = CraftingStateScript.new()
	var queued_inventory = InventoryStateScript.new("player:p07-semantic-escrow")
	_add_standard_inputs(queued_inventory, 1)
	if queued_crafting.enqueue_craft(
			RECIPE_ID, 1, null, queued_inventory, MaterialStateScript.new(), 2,
			"ship-semantic", "fabricator-semantic") != 1:
		return _fail_bool("semantic escrow fixture could not enqueue")
	var queued_before: Dictionary = queued_crafting.get_summary()
	var forged_escrow: Dictionary = queued_before.duplicate(true)
	var queued_jobs: Array = (forged_escrow.craft_jobs_v1 as Dictionary).jobs
	(queued_jobs[0] as Dictionary)["ingredient_escrow"] = [{
		"lot_id": "player:p07-semantic-escrow/forged-junk",
		"item_id": "junk_chunk",
		"quantity": 1,
		"quality_score": 0.5,
		"quality_tier": "standard",
		"condition": 1.0,
		"origin": {"fixture": "forged"},
	}]
	if queued_crafting.apply_summary(forged_escrow) \
			or queued_crafting.get_summary() != queued_before:
		return _fail_bool("forged escrow semantics were accepted or mutated state")
	return true


func _station(ship_id: String, station_id: String, tier: int, powered: bool) -> RefCounted:
	var station = StationStateScript.new()
	station.configure({
		"ship_id": ship_id,
		"station_instance_id": station_id,
		"station_kind": "fabricator",
		"level": tier,
		"tier": tier,
		"powered": powered,
	})
	return station


func _context(
		crafting: RefCounted,
		inventory: RefCounted,
		stations: Dictionary,
		skill: int,
		knowledge: RefCounted = null) -> Dictionary:
	var owner_stations: Dictionary = {}
	for station_variant in stations.values():
		if station_variant is RefCounted:
			var station: RefCounted = station_variant
			owner_stations[_owner_key(
				str(station.get("ship_id")), str(station.get("station_instance_id")))] = station
	return {
		"crafting_state": crafting,
		"source_inventory": inventory,
		"stations": owner_stations,
		"player_skill_level": skill,
		"knowledge": knowledge,
	}


func _owner_key(ship_id: String, station_instance_id: String) -> String:
	return JSON.stringify([ship_id, station_instance_id], "", true)


func _request(
		ship_id: String,
		station_id: String,
		inventory: RefCounted,
		selected_lot_ids: Dictionary = {},
		recipe_id: String = RECIPE_ID) -> Dictionary:
	return {
		"ship_id": ship_id,
		"station_instance_id": station_id,
		"station_kind": "fabricator",
		"recipe_id": recipe_id,
		"source_holder_id": str(inventory.call("get_holder_namespace")),
		"selected_lot_ids": selected_lot_ids.duplicate(true),
	}


func _add_standard_inputs(inventory: RefCounted, count: int) -> void:
	inventory.call("add_item", "scrap_metal", count)
	inventory.call("add_item", "wiring_bundle", count * 2)
	inventory.call("add_item", "reactive_gel", count)


func _add_exact_inputs(inventory: RefCounted, prefix: String, score: float) -> Dictionary:
	var tier: String = "masterwork" if score >= 0.9 else "excellent" if score >= 0.75 else "good" if score >= 0.55 else "standard"
	var selected: Dictionary = {}
	for row in [
		["scrap_metal", 1],
		["wiring_bundle", 2],
		["reactive_gel", 1],
	]:
		var item_id: String = str(row[0])
		var lot_id: String = "%s/%s-%s" % [inventory.call("get_holder_namespace"), prefix, item_id]
		var accepted: int = int(inventory.call("add_lot", {
			"lot_id": lot_id,
			"item_id": item_id,
			"quantity": int(row[1]),
			"quality_score": score,
			"quality_tier": tier,
			"condition": 0.9,
			"origin": {"fixture": "p07", "prefix": prefix},
		}))
		if accepted != int(row[1]):
			_fail("could not seed exact lot %s" % lot_id)
			return {}
		selected[item_id] = [lot_id]
	return selected


func _flatten_selected_ids(selected: Dictionary) -> Array:
	var out: Array = []
	var keys: Array = selected.keys()
	keys.sort()
	for key in keys:
		for lot_id in selected[key]:
			out.append(str(lot_id))
	out.sort()
	return out


func _lot_ids(lots_variant: Variant) -> Array:
	var out: Array = []
	if lots_variant is Array:
		for lot_variant in lots_variant:
			if lot_variant is Dictionary:
				out.append(str((lot_variant as Dictionary).get("lot_id", "")))
	out.sort()
	return out


func _inventory_lot_ids(inventory: RefCounted) -> Array:
	return _lot_ids((inventory.call("get_lot_summary") as Dictionary).get("lots", []))


func _progress_is(scheduler: RefCounted, job_id: String, expected: float) -> bool:
	return absf(float((scheduler.call("get_job", job_id) as Dictionary).get("progress_seconds", -1.0)) - expected) < 0.001


func _fail_bool(reason: String) -> bool:
	_fail(reason)
	return false


func _fail(reason: String) -> void:
	print("FC P07 FAIL: %s" % reason)
	quit(1)
