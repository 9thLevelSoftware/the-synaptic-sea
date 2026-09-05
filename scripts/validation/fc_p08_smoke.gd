extends SceneTree

## FC-08..09 / P08: lossless physical pending output and refund receipts.
## Marker: FC P08 PASS

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const PendingOutputStoreScript := preload("res://scripts/systems/pending_output_store.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const FieldCraftingStateScript := preload("res://scripts/systems/field_crafting_state.gd")
const DeconstructionResolverScript := preload("res://scripts/systems/deconstruction_resolver.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

class SkillFixture extends RefCounted:
	func get_skill_level(_skill_id: String) -> int:
		return 4


func _initialize() -> void:
	if not _test_store_collection_and_restore():
		return
	if not _test_store_before_scheduler_ack():
		return
	if not _test_recoverable_refund_and_full_salvage():
		return
	if not _test_field_restore_atomicity():
		return
	if not _test_world_preflight_and_station_orphan():
		return
	if not await _test_live_field_attendance():
		return
	print("FC P08 DETAIL deposit_once=true interruption=true refund=true salvage_full=true partial=true strict_restore=true orphan_revisit=true field_attendance=true")
	print("FC P08 PASS")
	quit(0)


func _test_store_collection_and_restore() -> bool:
	var store = PendingOutputStoreScript.new()
	if not store.configure("ship-p08"):
		return _fail("store owner configuration failed")
	var lot: Dictionary = _lot("pending-source", "scrap_metal", 3, 0.8)
	var metadata: Dictionary = _metadata("station-a", "job-a")
	if not store.deposit_once("job-a/output", [lot], metadata):
		return _fail("first deposit was rejected")
	if store.deposit_once("job-a/output", [lot], metadata) \
			or not store.receipt_matches("job-a/output", [lot], metadata):
		return _fail("duplicate receipt was not idempotent")
	var destination = InventoryStateScript.new("player:p08-partial")
	if destination.add_item("scrap_metal", 19) != 19:
		return _fail("partial destination fixture failed")
	var first: Dictionary = store.collect_receipt("job-a/output", destination)
	if int(first.get("transferred", 0)) != 1 \
			or int((store.peek_remaining_lots("job-a/output")[0] as Dictionary).quantity) != 2:
		return _fail("partial collection did not retain exact remainder: %s" % str(first))
	var blocked: Dictionary = store.collect_receipt("job-a/output", destination)
	if int(blocked.get("transferred", -1)) != 0 \
			or str(blocked.get("reason", "")) != "destination_full":
		return _fail("full destination mutated pending output")
	destination.remove_item("scrap_metal", 2)
	var final: Dictionary = store.collect_receipt("job-a/output", destination)
	if int(final.get("transferred", 0)) != 2 \
			or not store.peek_remaining_lots("job-a/output").is_empty() \
			or destination.get_quantity("scrap_metal") != 20:
		return _fail("remainder did not collect exactly once")
	var summary: Dictionary = store.get_summary()
	var restored = PendingOutputStoreScript.new()
	if not restored.apply_summary(summary) or restored.get_summary() != summary:
		return _fail("pending store did not round-trip exactly")
	var before_bad: Dictionary = restored.get_summary()
	var json_round_trip_v: Variant = JSON.parse_string(JSON.stringify(summary))
	if not json_round_trip_v is Dictionary \
			or not restored.apply_summary(json_round_trip_v as Dictionary) \
			or JSON.stringify(restored.get_summary()) != JSON.stringify(summary):
		return _fail("pending store rejected or changed an actual JSON save round trip")
	var malformed: Dictionary = summary.duplicate(true)
	(malformed.records[0] as Dictionary)["remaining_lots"] = ["forged"]
	if restored.apply_summary(malformed) or restored.get_summary() != before_bad:
		return _fail("malformed present pending data mutated store")
	var foreign_record: Dictionary = summary.duplicate(true)
	(foreign_record.records[0] as Dictionary)["ship_id"] = "ship-foreign"
	if restored.apply_summary(foreign_record) or restored.get_summary() != before_bad:
		return _fail("foreign pending record owner was normalized or mutated store")
	var coerced_id: Dictionary = summary.duplicate(true)
	(coerced_id.records[0] as Dictionary)["receipt_id"] = 42
	if restored.apply_summary(coerced_id) or restored.get_summary() != before_bad:
		return _fail("non-string pending receipt identity was normalized")
	var fractional_quantity: Dictionary = summary.duplicate(true)
	var original_lots: Array = (fractional_quantity.records[0] as Dictionary).original_lots
	(original_lots[0] as Dictionary)["quantity"] = float(
		(original_lots[0] as Dictionary).quantity) + 0.25
	if restored.apply_summary(fractional_quantity) or restored.get_summary() != before_bad:
		return _fail("fractional pending lot quantity was normalized")
	var unbounded_quantity: Dictionary = summary.duplicate(true)
	var huge_lots: Array = (unbounded_quantity.records[0] as Dictionary).original_lots
	(huge_lots[0] as Dictionary)["quantity"] = 9007199254740992.0
	if restored.apply_summary(unbounded_quantity) or restored.get_summary() != before_bad:
		return _fail("out-of-bound pending lot quantity was normalized")
	var unknown_collected: Dictionary = summary.duplicate(true)
	var unknown_record: Dictionary = unknown_collected.records[0] as Dictionary
	unknown_record["state"] = "pending"
	unknown_record["remaining_lots"] = (unknown_record.original_lots as Array).duplicate(true)
	unknown_record["collected_quantities"] = {"forged-lot": 1}
	if restored.apply_summary(unknown_collected) or restored.get_summary() != before_bad:
		return _fail("unknown collected lot key bypassed strict atomic restore")
	var ship = ShipInstanceScript.create("ship-p08", "", null, null, null)
	ship.pending_outputs = store
	var ship_summary: Dictionary = ship.get_summary()
	var loaded = ShipInstanceScript.create("ship-p08", "", null, null, null)
	if not loaded.apply_summary(ship_summary) \
			or loaded.get_pending_output_store().get_summary() != store.get_summary():
		return _fail("ship-owned pending store did not restore")
	return true


func _test_store_before_scheduler_ack() -> bool:
	var crafting = CraftingStateScript.new()
	var inventory = InventoryStateScript.new("player:p08-interrupt")
	inventory.add_item("scrap_metal", 1)
	inventory.add_item("wiring_bundle", 2)
	inventory.add_item("reactive_gel", 1)
	var store = PendingOutputStoreScript.new()
	store.configure("ship-p08-interrupt")
	if not crafting.bind_station_runtime_context(
			"ship-p08-interrupt", "fabricator-a", "fabricator",
			inventory, null, SkillFixture.new(), store):
		return _fail("physical station context did not bind")
	var weight_before: float = inventory.get_total_weight()
	if crafting.enqueue_craft(
			"craft_power_cell", 1, null, inventory, MaterialStateScript.new(), 4,
			"ship-p08-interrupt", "fabricator-a") != 1:
		return _fail("paid job did not enqueue")
	if absf(inventory.get_total_weight() - weight_before) > 0.0001 \
			or not inventory.get_quantity("scrap_metal") == 0:
		return _fail("queued exact escrow stopped counting at its source holder")
	var scheduler: RefCounted = crafting.get_craft_job_scheduler()
	var context: Dictionary = crafting.get_scheduler_context_for_ship("ship-p08-interrupt")
	scheduler.advance(30.0, context)
	if inventory.get_total_weight() >= weight_before:
		return _fail("started consumption did not release reservation mass")
	var ready: Array = scheduler.get_ready_receipts()
	if ready.size() != 1:
		return _fail("completion receipt missing")
	var receipt: Dictionary = ready[0]
	# A restored physical job has no live dependency bindings until its owning
	# ShipInstance/station is rebuilt. It must remain output_ready rather than
	# falling through to the destructive legacy claim path.
	var restored_crafting = CraftingStateScript.new()
	if not restored_crafting.apply_summary(crafting.get_summary()):
		return _fail("physical completed job did not restore for binding check")
	var restored_scheduler: RefCounted = restored_crafting.get_craft_job_scheduler()
	if not restored_crafting.finish_craft().is_empty() \
			or str(restored_scheduler.get_job(str(receipt.job_id)).get("state", "")) != "output_ready":
		return _fail("missing restored store binding destructively claimed physical output")
	var restored_store = PendingOutputStoreScript.new()
	restored_store.configure("ship-p08-interrupt")
	if not restored_crafting.bind_station_runtime_context(
			"ship-p08-interrupt", "fabricator-a", "fabricator",
			inventory, null, SkillFixture.new(), restored_store):
		return _fail("restored physical store context did not bind")
	var rebound: Dictionary = restored_crafting.finish_craft()
	if not bool(rebound.get("pending", false)) \
			or str(restored_scheduler.get_job(str(receipt.job_id)).get("state", "")) != "collected" \
			or restored_store.list_records_for_station("fabricator-a", true).size() != 1:
		return _fail("restored physical output did not settle after store rebind")
	var metadata: Dictionary = _metadata("fabricator-a", str(receipt.job_id))
	if not store.deposit_once(str(receipt.receipt_id), receipt.output_lots as Array, metadata):
		return _fail("interruption fixture could not publish store receipt")
	# Simulated interruption: producer remains output_ready while the store has
	# the exact receipt. finish_craft must match then acknowledge, never redeposit.
	crafting.receive_completion_receipts(ready)
	var settled: Dictionary = crafting.finish_craft()
	if not bool(settled.get("pending", false)) \
			or str(scheduler.get_job(str(receipt.job_id)).get("state", "")) != "collected" \
			or store.list_records_for_station("fabricator-a", true).size() != 1:
		return _fail("store-before-ack replay did not settle exactly once: %s" % str(settled))
	return true


func _test_recoverable_refund_and_full_salvage() -> bool:
	var crafting = CraftingStateScript.new()
	var inventory = InventoryStateScript.new("player:p08-refund")
	inventory.add_item("scrap_metal", 1)
	inventory.add_item("wiring_bundle", 2)
	inventory.add_item("reactive_gel", 1)
	inventory.add_item("power_cell", 10)
	var store = PendingOutputStoreScript.new()
	store.configure("ship-p08-refund")
	if not crafting.bind_station_runtime_context(
			"ship-p08-refund", "fabricator-refund", "fabricator",
			inventory, null, SkillFixture.new(), store):
		return _fail("refund station context did not bind")
	if _entry_status(crafting.list_recipe_entries(
			"fabricator", inventory, 4), "craft_power_cell") != "output_full" \
			or _entry_status(crafting.list_recipe_entries(
				"fabricator", inventory, 4, 0, null, 4, true, true),
				"craft_power_cell") != "ready":
		return _fail("physical pending store did not remove only the craft output gate")
	if crafting.enqueue_craft(
			"craft_power_cell", 1, null, inventory, MaterialStateScript.new(), 4,
			"ship-p08-refund", "fabricator-refund") != 1:
		return _fail("refund job did not enqueue")
	var scheduler: RefCounted = crafting.get_craft_job_scheduler()
	var jobs: Array = (scheduler.get_summary().get("jobs", []) as Array)
	if jobs.size() != 1:
		return _fail("refund job identity missing")
	var job_id: String = str((jobs[0] as Dictionary).get("job_id", ""))
	var refund_lot_ids: Array = _lot_ids(
		(jobs[0] as Dictionary).get("ingredient_escrow", []) as Array)
	# Fill the original source stack after reservation. A direct refund cannot
	# fit, so the exact escrow must become station-owned pending mass.
	if inventory.add_item("scrap_metal", 20) != 20:
		return _fail("refund full-stack fixture failed")
	var cancelled: Dictionary = crafting.cancel_job(
		job_id, "ship-p08-refund", "fabricator-refund")
	var refund_receipt: String = "%s/refund" % job_id
	var refund_record: Dictionary = store.get_record(refund_receipt)
	if not bool(cancelled.get("ok", false)) \
			or str(cancelled.get("result", "")) != "recoverable_refund" \
			or str(scheduler.get_job(job_id).get("state", "")) != "cancelled" \
			or not (scheduler.get_job(job_id).get("ingredient_escrow", []) as Array).is_empty() \
			or _lot_ids(refund_record.get("original_lots", []) as Array) != refund_lot_ids \
			or str(refund_record.get("purpose", "")) != "refund" \
			or store.get_pending_mass_for_station("fabricator-refund", inventory) <= 0.0:
		return _fail("full-holder refund was not transferred exactly once: %s" % str(cancelled))
	if inventory.remove_item("scrap_metal", 20) != 20:
		return _fail("refund collection fixture could not free source stack")
	var refund_collection: Dictionary = store.collect_receipt(refund_receipt, inventory)
	if int(refund_collection.get("transferred", 0)) != 4 \
			or not store.peek_remaining_lots(refund_receipt).is_empty() \
			or inventory.get_quantity("scrap_metal") != 1 \
			or inventory.get_quantity("wiring_bundle") != 2 \
			or inventory.get_quantity("reactive_gel") != 1:
		return _fail("pending refund did not return exact ingredients")
	if not crafting.begin_craft(
			"craft_power_cell", inventory, MaterialStateScript.new(), 4, null,
			"ship-p08-refund", "fabricator-refund"):
		return _fail("running-destruction fixture did not begin")
	var busy_destruction: Dictionary = crafting.settle_station_pending(
		"ship-p08-refund", "fabricator-refund")
	if bool(busy_destruction.get("ok", true)) \
			or str(busy_destruction.get("reason", "")) != "station_busy":
		return _fail("station destruction abandoned a started paid job")

	var salvage_inventory = InventoryStateScript.new("player:p08-salvage")
	var source: Dictionary = _lot("salvage-source-exact", "scrap_metal", 1, 0.82)
	if salvage_inventory.add_lot(source) != 1 \
			or salvage_inventory.add_item("ferrous_shard", 99) != 99:
		return _fail("full salvage fixture failed")
	var resolver = DeconstructionResolverScript.new()
	var blocked_rows: Array = resolver.list_salvage_entries(salvage_inventory)
	var pending_rows: Array = resolver.list_salvage_entries(salvage_inventory, true)
	if _entry_status(blocked_rows, "deconstruct_scrap") != "output_full" \
			or _entry_status(pending_rows, "deconstruct_scrap") != "ready":
		return _fail("physical pending store did not remove only the direct-output gate")
	var salvage_store = PendingOutputStoreScript.new()
	salvage_store.configure("ship-p08-salvage")
	var produced: Dictionary = resolver.execute_salvage_target(
		"deconstruct_scrap", salvage_inventory, MaterialStateScript.new(), {
			"ship_id": "ship-p08-salvage",
			"station_instance_id": "salvage-a",
			"pending_output_store": salvage_store,
		})
	var salvage_records: Array = salvage_store.list_records_for_station("salvage-a")
	if not bool(produced.get("pending", false)) \
			or salvage_inventory.get_quantity("scrap_metal") != 0 \
			or salvage_inventory.get_quantity("ferrous_shard") != 99 \
			or salvage_records.size() != 1:
		return _fail("full salvage did not atomically move source to pending output")
	var salvage_receipt: String = str((salvage_records[0] as Dictionary).get("receipt_id", ""))
	var blocked_collect: Dictionary = salvage_store.collect_receipt(
		salvage_receipt, salvage_inventory)
	if int(blocked_collect.get("transferred", -1)) != 0 \
			or int((salvage_store.peek_remaining_lots(salvage_receipt)[0] as Dictionary).quantity) != 2:
		return _fail("full salvage collection lost pending remainder")
	salvage_inventory.remove_item("ferrous_shard", 2)
	var salvage_collect: Dictionary = salvage_store.collect_receipt(
		salvage_receipt, salvage_inventory)
	var salvaged_lots: Array = salvage_collect.get("lots", []) as Array
	if int(salvage_collect.get("transferred", 0)) != 2 \
			or salvage_inventory.get_quantity("ferrous_shard") != 99 \
			or salvaged_lots.size() != 1 \
			or str(((salvaged_lots[0] as Dictionary).get("origin", {}) as Dictionary).get(
				"source_lot_id", "")) != "salvage-source-exact":
		return _fail("salvage exact provenance did not survive pending collection")
	return true


func _test_field_restore_atomicity() -> bool:
	var field = FieldCraftingStateScript.new()
	var store = PendingOutputStoreScript.new()
	store.configure("ship-p08-field")
	var pinned_position := Vector3(1.25, 0.5, -2.0)
	if not field.bind_pending_output_store(
			"ship-p08-field", store, pinned_position):
		return _fail("field pending owner did not bind")
	var inventory = InventoryStateScript.new("player:p08-field")
	inventory.add_item("synth_fiber", 2)
	inventory.add_item("medical_gauze", 1)
	if not field.begin_craft(
			"field_bandage", inventory, MaterialStateScript.new(), 3) \
			or not field.tick(8.0):
		return _fail("field interruption fixture did not complete")
	var unpinned_v: Variant = JSON.parse_string(JSON.stringify(field.get_summary()))
	var no_owner_field = FieldCraftingStateScript.new()
	var no_owner_coordinator = PlayableGeneratedShipScript.new()
	if not unpinned_v is Dictionary \
			or not no_owner_field.apply_summary(unpinned_v as Dictionary):
		no_owner_coordinator.free()
		return _fail("completed unpinned field job did not survive JSON reload")
	no_owner_coordinator.field_crafting_state = no_owner_field
	no_owner_coordinator._on_field_craft_completed()
	no_owner_coordinator._on_field_craft_completed()
	if not no_owner_field.is_crafting() \
			or not no_owner_field.get_pinned_destination_ship_id().is_empty():
		no_owner_coordinator.free()
		return _fail("field completion without attached occupancy published or cleared value")
	no_owner_coordinator.free()
	if not field.pin_pending_destination("ship-p08-field", pinned_position):
		return _fail("field completion could not pin its first physical destination")
	var receipt_id: String = str(field._active_receipt_id)
	var completed_summary: Dictionary = field.get_summary()
	var json_completed_v: Variant = JSON.parse_string(JSON.stringify(completed_summary))
	var missing_binding = FieldCraftingStateScript.new()
	if not json_completed_v is Dictionary \
			or not missing_binding.apply_summary(json_completed_v as Dictionary) \
			or not missing_binding.finish_craft().is_empty() \
			or not missing_binding.is_crafting():
		return _fail("JSON-restored field output cleared without its physical store binding")
	var foreign_store = PendingOutputStoreScript.new()
	foreign_store.configure("ship-p08-foreign")
	if missing_binding.bind_pending_output_store(
			"ship-p08-foreign", foreign_store, pinned_position):
		return _fail("restored field output rebound to a foreign destination owner")
	var preview: Dictionary = missing_binding._peek_completed_field_output()
	var rebound_store = PendingOutputStoreScript.new()
	rebound_store.configure("ship-p08-field")
	var lot: Dictionary = {
		"lot_id": "%s/output-1" % receipt_id,
		"item_id": str(preview.get("item_id", "")),
		"quantity": int(preview.get("quantity", 0)),
		"quality_score": float(preview.get("quality_score", 0.5)),
		"quality_tier": str(preview.get("quality_tier", "standard")),
		"condition": 1.0,
		"origin": {"field_receipt_id": receipt_id},
	}
	var metadata: Dictionary = {
		"station_instance_id": "field_crafting",
		"producer_kind": "field_craft",
		"producer_id": receipt_id.trim_suffix("/output"),
		"purpose": "output",
		"source_holder_id": "",
	}
	# Simulate interruption after the destination store committed but before the
	# portable producer acknowledged publication. Rebinding/retry must match the
	# receipt, clear the producer once, and never expose duplicate value.
	if not rebound_store.deposit_once(receipt_id, [lot], metadata) \
			or not missing_binding.bind_pending_output_store(
				"ship-p08-field", rebound_store, pinned_position):
		return _fail("field interruption could not publish before producer clear")
	var replay: Dictionary = missing_binding.finish_craft()
	if not bool(replay.get("pending", false)) or missing_binding.is_crafting() \
			or not missing_binding.finish_craft().is_empty() \
			or rebound_store.list_records_for_station("field_crafting", true).size() != 1:
		return _fail("field store-before-clear replay did not settle exactly once")
	var summary: Dictionary = missing_binding.get_summary()
	var restored = FieldCraftingStateScript.new()
	if not restored.apply_summary(summary):
		return _fail("field summary did not restore")
	var before_bad: Dictionary = restored.get_summary()
	var malformed: Dictionary = summary.duplicate(true)
	var inner: Dictionary = malformed.get("field_crafting", {}) as Dictionary
	var jobs: Dictionary = inner.get("craft_jobs_v1", {}) as Dictionary
	jobs["schema"] = "forged"
	inner["craft_jobs_v1"] = jobs
	malformed["field_crafting"] = inner
	if restored.apply_summary(malformed) or restored.get_summary() != before_bad:
		return _fail("malformed field inner state partially mutated receipt metadata")
	return true


func _test_world_preflight_and_station_orphan() -> bool:
	var coordinator = PlayableGeneratedShipScript.new()
	var live_home = ShipInstanceScript.create("ship_start", "", null, null, null)
	coordinator.home_ship = live_home
	var live_before: Dictionary = live_home.get_summary()
	var malformed_world = WorldSnapshotScript.new()
	malformed_world.home_pending_outputs_v1 = {
		"schema": "pending-outputs-1", "ship_id": "ship_start",
		"records": [{"forged": true}],
	}
	var prepared: Dictionary = coordinator._prepare_world_holder_restore(malformed_world)
	if bool(prepared.get("ok", false)) or live_home.get_summary() != live_before:
		coordinator.free()
		return _fail("malformed world pending payload bypassed atomic holder preflight")

	var owner = ShipInstanceScript.create("ship-p08-orphan", "", null, null, null)
	var owner_root := Node3D.new()
	get_root().add_child(owner_root)
	owner.scene_root = owner_root
	var pending = owner.get_pending_output_store()
	var orphan_lot: Dictionary = _lot("orphan-exact", "power_cell", 1, 0.81)
	if not pending.deposit_once(
			"orphan-job/output", [orphan_lot], _metadata("station-orphan", "orphan-job")):
		coordinator.free()
		owner_root.queue_free()
		return _fail("orphan fixture could not publish pending receipt")
	coordinator.inventory_state = InventoryStateScript.new("player:p08-orphan")
	coordinator.home_ship = owner
	if not coordinator._orphan_pending_output_records(
			owner, "station-orphan", Vector3(1.0, 0.0, 2.0)) \
			or owner.floor_drop_descriptors.size() != 1 \
			or str(pending.get_record("orphan-job/output").get("state", "")) != "orphaned":
		coordinator.free()
		owner_root.queue_free()
		return _fail("station destruction did not atomically create a floor holder")
	var persisted: Dictionary = owner.get_summary()
	for old_drop in coordinator.work_yield_drops:
		if is_instance_valid(old_drop):
			old_drop.queue_free()
	coordinator.work_yield_drops.clear()
	coordinator.free()
	owner_root.queue_free()

	var restored = ShipInstanceScript.create("ship-p08-orphan", "", null, null, null)
	if not restored.apply_summary(persisted):
		return _fail("orphan ship holder did not restore")
	var restored_root := Node3D.new()
	get_root().add_child(restored_root)
	restored.scene_root = restored_root
	var destination = InventoryStateScript.new("player:p08-orphan-restored")
	var revisit = PlayableGeneratedShipScript.new()
	revisit.inventory_state = destination
	revisit.home_ship = restored
	if not revisit._restore_floor_drops_for_ship(restored) \
			or revisit.work_yield_drops.size() != 1:
		revisit.free()
		restored_root.queue_free()
		return _fail("revisit did not materialize the persistent orphan holder")
	var player := Node3D.new()
	get_root().add_child(player)
	var drop = revisit.work_yield_drops[0]
	drop.set_validation_player_in_range(player)
	if not drop.try_interact(player) \
			or destination.get_quantity("power_cell") != 1 \
			or not restored.floor_drop_descriptors.is_empty():
		revisit.free()
		player.queue_free()
		restored_root.queue_free()
		return _fail("reconstructed orphan did not collect and clear exactly once")
	var after_collect: Dictionary = restored.get_summary()
	var second_restore = ShipInstanceScript.create("ship-p08-orphan", "", null, null, null)
	if not second_restore.apply_summary(after_collect) \
			or not second_restore.floor_drop_descriptors.is_empty() \
			or str(second_restore.get_pending_output_store().get_record(
				"orphan-job/output").get("state", "")) != "orphaned":
		revisit.free()
		player.queue_free()
		restored_root.queue_free()
		return _fail("collected orphan reappeared after save/revisit")
	revisit.free()
	player.queue_free()
	restored_root.queue_free()
	return true


func _test_live_field_attendance() -> bool:
	var main = MAIN_SCENE.instantiate()
	if main == null:
		return _fail("field attendance could not instantiate main scene")
	get_root().add_child(main)
	var playable = null
	for _frame in range(600):
		await process_frame
		playable = _find_playable(main)
		if playable != null and playable.playable_started:
			break
	if playable == null or not playable.playable_started \
			or playable.field_crafting_state == null or playable.vitals_state == null:
		main.queue_free()
		return _fail("field attendance runtime did not become playable")
	# Remove natural frame advancement so every assertion below drives the real
	# coordinator _process path with a deterministic delta.
	playable.set_process(false)
	var inventory = playable.inventory_state
	inventory.add_item("synth_fiber", 2)
	inventory.add_item("medical_gauze", 1)
	inventory.add_item("field_bandage", 99)
	playable.vitals_state.health = 100.0
	playable.vitals_state.stamina = 100.0
	if not playable.begin_field_craft_recipe("field_bandage"):
		main.queue_free()
		return _fail("live field attendance job did not begin")
	var paid_synth: int = inventory.get_quantity("synth_fiber")
	var paid_gauze: int = inventory.get_quantity("medical_gauze")
	var home_drop_count_before: int = playable.home_ship.floor_drop_descriptors.size()
	var p0: float = _field_progress(playable.field_crafting_state)
	playable._process(1.0)
	var home_progress: float = _field_progress(playable.field_crafting_state)
	if home_progress <= p0:
		main.queue_free()
		return _fail("attended home process did not advance field craft")

	playable.vitals_state.stamina = 0.0
	playable._process(1.0)
	if not is_equal_approx(_field_progress(playable.field_crafting_state), home_progress):
		main.queue_free()
		return _fail("exhausted home process advanced field craft")
	# Move the same paid job into a real attached away ShipInstance. Portable work
	# follows the player until first publication; it does not inherit home ownership.
	var away_root := Node3D.new()
	away_root.name = "P08AwayShip"
	playable.add_child(away_root)
	away_root.global_position = (playable.player as Node3D).global_position \
		+ Vector3(500.0, 0.0, 0.0)
	var away_structure := Node3D.new()
	away_structure.name = "ShipStructure"
	away_root.add_child(away_structure)
	var away_room := Node3D.new()
	away_room.name = "RoomP08"
	away_structure.add_child(away_room)
	var away = ShipInstanceScript.create(
		"ship-p08-away", "marker-p08-away", null, null, away_root)
	playable.current_ship = away
	playable.visited_ships["marker-p08-away"] = away
	(playable.player as Node3D).global_position = away_root.global_position
	playable.recompute_occupancy()
	if playable.current_occupancy != away or not playable.away_from_start:
		main.queue_free()
		return _fail("field attendance fixture did not enter the attached away ship")
	playable.vitals_state.stamina = 0.0
	playable._process(1.0)
	if not is_equal_approx(_field_progress(playable.field_crafting_state), home_progress):
		main.queue_free()
		return _fail("exhausted away process advanced field craft")

	playable.vitals_state.stamina = 100.0
	if is_instance_valid(playable.recipe_picker_panel):
		playable.recipe_picker_panel.open_for_station("field_crafting")
	playable._process(1.0)
	var away_resumed: float = _field_progress(playable.field_crafting_state)
	if away_resumed <= home_progress:
		main.queue_free()
		return _fail("able away process did not resume the same field craft with UI open")
	if inventory.get_quantity("synth_fiber") != paid_synth \
			or inventory.get_quantity("medical_gauze") != paid_gauze:
		main.queue_free()
		return _fail("attendance pause/resume spent field ingredients again")
	# Finish while the output stack is full. The portable output must pass
	# through its receipt and become a persistent holder on the occupied away ship.
	playable._process(6.0)
	if playable.field_crafting_state.is_crafting() \
			or away.floor_drop_descriptors.is_empty() \
			or playable.home_ship.floor_drop_descriptors.size() != home_drop_count_before:
		main.queue_free()
		return _fail("full attended away output was not retained by its physical ship")
	var away_pending = away.get_pending_output_store()
	var field_records: Array = away_pending.list_records_for_station("field_crafting", true)
	if field_records.size() != 1 \
			or str((field_records[0] as Dictionary).get("state", "")) != "orphaned":
		main.queue_free()
		return _fail("away field publication did not leave one durable orphan receipt")
	var field_receipt_id: String = str((field_records[0] as Dictionary).receipt_id)
	var expected_field_lot_ids: Array = _lot_ids(
		((field_records[0] as Dictionary).get("original_lots", []) as Array))
	var descriptor_count: int = away.floor_drop_descriptors.size()
	playable._on_field_craft_completed()
	playable._on_field_craft_completed()
	if away.floor_drop_descriptors.size() != descriptor_count \
			or away_pending.list_records_for_station("field_crafting", true).size() != 1:
		main.queue_free()
		return _fail("field completion retry duplicated the pinned away receipt")

	# Cross the actual JSON boundary, rebuild the owning ship on revisit, collect
	# all exact lots once, then save/reload again to prove the holder stays gone.
	var away_json_v: Variant = JSON.parse_string(JSON.stringify(away.get_summary()))
	var restored_away = ShipInstanceScript.create(
		"ship-p08-away", "marker-p08-away", null, null, null)
	if not away_json_v is Dictionary \
			or not restored_away.apply_summary(away_json_v as Dictionary):
		main.queue_free()
		return _fail("away pending field holder did not survive JSON reload")
	var restored_root := Node3D.new()
	get_root().add_child(restored_root)
	restored_away.scene_root = restored_root
	var revisit = PlayableGeneratedShipScript.new()
	revisit.inventory_state = InventoryStateScript.new("player:p08-field-revisit")
	revisit.home_ship = restored_away
	if not revisit._restore_floor_drops_for_ship(restored_away) \
			or revisit.work_yield_drops.size() != 1:
		revisit.free()
		restored_root.queue_free()
		main.queue_free()
		return _fail("away field holder did not materialize on revisit")
	var scoop_player := Node3D.new()
	get_root().add_child(scoop_player)
	var field_drop = revisit.work_yield_drops[0]
	field_drop.set_validation_player_in_range(scoop_player)
	if not field_drop.try_interact(scoop_player) \
			or revisit.inventory_state.get_quantity("field_bandage") != 1 \
			or not restored_away.floor_drop_descriptors.is_empty():
		revisit.free()
		scoop_player.queue_free()
		restored_root.queue_free()
		main.queue_free()
		return _fail("away field holder did not collect exactly once")
	var restored_record: Dictionary = restored_away.get_pending_output_store().get_record(
		field_receipt_id)
	if not (restored_record.get("remaining_lots", []) as Array).is_empty() \
			or _lot_ids(restored_record.get("original_lots", []) as Array) != expected_field_lot_ids:
		revisit.free()
		scoop_player.queue_free()
		restored_root.queue_free()
		main.queue_free()
		return _fail("away field collection changed exact receipt lot identity")
	var collected_json_v: Variant = JSON.parse_string(JSON.stringify(restored_away.get_summary()))
	var collected_reload = ShipInstanceScript.create(
		"ship-p08-away", "marker-p08-away", null, null, null)
	if not collected_json_v is Dictionary \
			or not collected_reload.apply_summary(collected_json_v as Dictionary) \
			or not collected_reload.floor_drop_descriptors.is_empty():
		revisit.free()
		scoop_player.queue_free()
		restored_root.queue_free()
		main.queue_free()
		return _fail("collected away field holder reappeared after reload")
	revisit.free()
	scoop_player.queue_free()
	restored_root.queue_free()
	inventory.add_item("scrap_metal", 2)
	inventory.add_item("adhesive_paste", 1)
	if not playable.begin_field_craft_recipe("field_patch"):
		main.queue_free()
		return _fail("terminal-attendance field job did not begin")
	var end_progress: float = _field_progress(playable.field_crafting_state)

	# Keep the terminal-state proof hermetic: end_run still executes its real
	# transition, while no profile/save/audio service can write or emit unrelated
	# content diagnostics from this validation process.
	playable.meta_progression_state = null
	playable.save_load_service = null
	playable.audio_manager = null
	playable.menu_coordinator = null
	playable.vitals_state.health = 0.0
	playable._process(30.0)
	if not is_equal_approx(_field_progress(playable.field_crafting_state), end_progress) \
			or not playable.field_crafting_state.is_crafting() \
			or not playable.slice_complete:
		main.queue_free()
		return _fail("incapacitation/end-run advanced or discarded the paid field job")
	playable._process(30.0)
	if not is_equal_approx(_field_progress(playable.field_crafting_state), end_progress):
		main.queue_free()
		return _fail("ended run advanced field craft on a later frame")
	main.queue_free()
	await process_frame
	return true


func _field_progress(field_state: RefCounted) -> float:
	var inner: Dictionary = field_state.get_summary().get("field_crafting", {}) as Dictionary
	var stations: Dictionary = inner.get("station_summaries", {}) as Dictionary
	var station: Dictionary = stations.get("field_crafting", {}) as Dictionary
	return float(station.get("progress_seconds", -1.0))


func _find_playable(node: Node):
	if not is_instance_valid(node):
		return null
	if node.get_script() == PlayableGeneratedShipScript:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null


func _entry_status(entries: Array, entry_id: String) -> String:
	for entry_variant in entries:
		if entry_variant is Dictionary \
				and str((entry_variant as Dictionary).get("recipe_id", "")) == entry_id:
			return str((entry_variant as Dictionary).get("status", ""))
	return ""


func _lot_ids(lots: Array) -> Array:
	var ids: Array = []
	for lot_variant in lots:
		if lot_variant is Dictionary:
			ids.append(str((lot_variant as Dictionary).get("lot_id", "")))
	ids.sort()
	return ids


func _metadata(station_id: String, producer_id: String) -> Dictionary:
	return {
		"station_instance_id": station_id,
		"producer_kind": "craft_job",
		"producer_id": producer_id,
		"purpose": "output",
		"source_holder_id": "",
	}


func _lot(lot_id: String, item_id: String, quantity: int, score: float) -> Dictionary:
	return {
		"lot_id": lot_id,
		"item_id": item_id,
		"quantity": quantity,
		"quality_score": score,
		"quality_tier": "excellent" if score >= 0.75 else "standard",
		"condition": 0.9,
		"origin": {"fixture": "p08"},
	}


func _fail(message: String) -> bool:
	push_error("FC P08 FAIL: %s" % message)
	quit(1)
	return false
