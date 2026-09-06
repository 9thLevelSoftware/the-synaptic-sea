extends SceneTree

## FC-15: explicit selected-ship work context and per-ship restoration owners.
## Marker: FC P13 PASS

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipWorkContextScript := preload("res://scripts/systems/ship_work_context.gd")
const ShipModificationPanelScript := preload("res://scripts/ui/ship_modification_panel.gd")
const ShipWorkTransactionScript := preload("res://scripts/systems/ship_work_transaction.gd")
const ShipRuntimeScript := preload("res://scripts/systems/ship_runtime.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const CraftJobSchedulerScript := preload("res://scripts/systems/craft_job_scheduler.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const StationStateScript := preload("res://scripts/systems/station_state.gd")
const ShipAccessStateScript := preload("res://scripts/systems/ship_access_state.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 400


class TierProjectionFixture extends RefCounted:
	var installed: Array = []


class TierContextFixture extends RefCounted:
	var ship_id: String = ""
	var ship_modification: RefCounted = null
	var component_placement: RefCounted = null


class StationNodeFixture extends Node:
	var ship_id: String = ""
	var station_instance_id: String = ""
	var station_kind: String = "fabricator"

var main_node: Node
var playable
var frames: int = 0
var finished: bool = false


func _initialize() -> void:
	if not _validate_pure_contract():
		return
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)


func _validate_pure_contract() -> bool:
	var ship_a = ShipInstanceScript.create("ship-a", "", null, null, Node3D.new())
	var ship_b = ShipInstanceScript.create("ship-b", "b", null, null, Node3D.new())
	ship_a.get_access().claim("player_local")
	var foreign = ShipInstanceScript.create("foreign-home", "", null, null, null)
	foreign.get_access().claim("remote_owner")
	if foreign.claim_home_access_for_bootstrap("player_local", true) \
			or str(foreign.get_access().owner_id) != "remote_owner":
		_fail("modern foreign home owner overwritten"); return false
	var legacy = ShipInstanceScript.create("legacy-home", "", null, null, null)
	if not legacy.claim_home_access_for_bootstrap("player_local", false, true):
		_fail("verified legacy absent home not claimed"); return false
	var placement_a = RefCounted.new()
	var placement_b = RefCounted.new()
	var module_a = RefCounted.new()
	var module_b = RefCounted.new()
	var mod_a = RefCounted.new()
	var mod_b = RefCounted.new()
	var tx_a = ShipWorkTransactionScript.new()
	var tx_b = ShipWorkTransactionScript.new()
	tx_a.configure("ship-a")
	tx_b.configure("ship-b")
	var foreign_tx = ShipWorkTransactionScript.new()
	foreign_tx.configure("ship-b")
	if bool(ship_a.bind_live_restoration_owners(
			module_a, placement_a, mod_a, foreign_tx).get("ok", false)):
		_fail("cross-owner transaction bind accepted"); return false
	if not bool(ship_a.bind_live_restoration_owners(module_a, placement_a, mod_a, tx_a).get("ok", false)):
		_fail("ship-a owner bind"); return false
	if not bool(ship_b.bind_live_restoration_owners(module_b, placement_b, mod_b, tx_b).get("ok", false)):
		_fail("ship-b owner bind"); return false
	var generation_a: int = ship_a.get_live_binding_generation()
	if generation_a <= 0 or ship_a.get_live_component_placement() != placement_a:
		_fail("ship-a live owner identity"); return false
	if not bool(ship_a.bind_live_restoration_owners(module_a, placement_a, mod_a, tx_a).get("ok", false)) \
			or ship_a.get_live_binding_generation() != generation_a:
		_fail("idempotent bind changed generation"); return false
	var replacement = RefCounted.new()
	ship_a.bind_live_restoration_owners(module_a, replacement, mod_a, tx_a)
	if ship_a.get_live_binding_generation() != generation_a + 1:
		_fail("replacement did not invalidate generation"); return false
	var runtime_a = ShipRuntimeScript.new()
	var runtime_b = ShipRuntimeScript.new()
	runtime_a.configure(ship_a)
	runtime_b.configure(ship_b)
	if runtime_a.module_integrity != module_a or runtime_a.component_placement != replacement \
			or runtime_b.module_integrity != module_b or runtime_b.component_placement != placement_b:
		_fail("ShipRuntime did not resolve per-ship restoration owners"); return false
	if not _validate_station_tier_owner_isolation():
		return false
	if not _validate_owned_away_catch_up():
		return false

	var context = ShipWorkContextScript.new()
	var configured: Dictionary = context.configure(ship_a, {
		"module_integrity": module_a,
		"component_placement": replacement,
		"ship_modification": mod_a,
		"work_transactions": tx_a,
		"binding_generation": ship_a.get_live_binding_generation(),
		"is_attached": true,
		"is_occupied": true,
		"is_piloted": false,
		"has_access": true,
	})
	if not bool(configured.get("ok", false)):
		_fail("context configure"); return false
	if not bool(context.preflight_physical_mutation("ship-a", true).get("ok", false)):
		_fail("authorized mutation denied"); return false
	ship_a.live_work_transactions = null
	if str(context.preflight_physical_mutation("ship-a", true).get("reason", "")) \
			!= "missing_work_authority":
		_fail("missing exact transaction authority not denied"); return false
	ship_a.live_work_transactions = tx_a
	var wrong_owner_tx = ShipWorkTransactionScript.new()
	wrong_owner_tx.configure("ship-b")
	ship_a.live_work_transactions = wrong_owner_tx
	var wrong_context = ShipWorkContextScript.new()
	wrong_context.configure(ship_a, {
		"module_integrity": module_a,
		"component_placement": replacement,
		"ship_modification": mod_a,
		"work_transactions": wrong_owner_tx,
		"binding_generation": ship_a.get_live_binding_generation(),
		"is_attached": true,
		"is_occupied": true,
		"has_access": true,
	})
	if str(wrong_context.preflight_physical_mutation("ship-a", true).get("reason", "")) \
			!= "missing_work_authority":
		_fail("foreign transaction authority not denied"); return false
	ship_a.live_work_transactions = tx_a
	if str(context.preflight_physical_mutation("ship-b", true).get("reason", "")) != "wrong_ship":
		_fail("wrong ship not denied"); return false
	context.has_access = false
	if str(context.preflight_physical_mutation("ship-a", true).get("reason", "")) != "no_access":
		_fail("permanent action access denial"); return false
	if not bool(context.preflight_physical_mutation("ship-a", false).get("ok", false)):
		_fail("ordinary attended work globally access gated"); return false
	context.is_occupied = false
	if str(context.preflight_physical_mutation("ship-a", false).get("reason", "")) != "not_attending_target":
		_fail("remote physical work not denied"); return false
	var old_revision: String = context.target_revision("slot|mounted")
	ship_a.bind_live_restoration_owners(module_b, replacement, mod_a, tx_a)
	if context.matches_binding(ship_a) or old_revision == ShipWorkContextScript.revision_for(ship_a, "slot|mounted"):
		_fail("stale binding remained valid"); return false

	var panel = ShipModificationPanelScript.new()
	get_root().add_child(panel)
	var request: Array = []
	panel.install_requested.connect(func(ship_id: String, binding_generation: int, slot_id: String, component_id: String, item_form: String) -> void:
		request.append([ship_id, binding_generation, slot_id, component_id, item_form]))
	panel.bind(null, {}, null, [], "ship-b", null, 7)
	if panel.get_bound_ship_id() != "ship-b":
		_fail("panel did not retain explicit owner"); return false
	panel.emit_install_request_for_validation("slot-b", "component-b", "item-b")
	if request != [["ship-b", 7, "slot-b", "component-b", "item-b"]]:
		_fail("panel request missing bound owner"); return false
	get_root().remove_child(panel)
	panel.free()
	ship_a.scene_root.free()
	ship_b.scene_root.free()
	return true


func _validate_station_tier_owner_isolation() -> bool:
	var coordinator = PlayableGeneratedShipScript.new()
	coordinator.crafting_state = CraftingStateScript.new()
	var station_a = StationNodeFixture.new()
	station_a.ship_id = "ship-a"
	station_a.station_instance_id = "station-a"
	var station_b = StationNodeFixture.new()
	station_b.ship_id = "ship-b"
	station_b.station_instance_id = "station-b"
	coordinator.crafting_stations = [station_a, station_b]
	var projection = TierProjectionFixture.new()
	projection.installed = [{
		"component_id": "fixture-tier",
		"mounted": true,
		"station_tier_bonus": 2,
		"station_affinity": "fabricator",
	}]
	var tier_context = TierContextFixture.new()
	tier_context.ship_id = "ship-a"
	tier_context.ship_modification = projection
	coordinator.call("_refresh_station_tiers_from_ship_mod", tier_context)
	var tier_a: int = int(coordinator.crafting_state.get_or_create_station_instance(
		"ship-a", "station-a", "fabricator").effective_tier())
	var tier_b: int = int(coordinator.crafting_state.get_or_create_station_instance(
		"ship-b", "station-b", "fabricator").effective_tier())
	station_a.free()
	station_b.free()
	coordinator.free()
	if tier_a != 2 or tier_b != 0:
		_fail("station tier crossed ship owners: a=%d b=%d" % [tier_a, tier_b])
		return false
	return true


func _validate_owned_away_catch_up() -> bool:
	var crafting = CraftingStateScript.new()
	var scheduler = CraftJobSchedulerScript.new()
	var inventory_home = InventoryStateScript.new("player:p13-home-craft")
	var inventory_away = InventoryStateScript.new("player:p13-away-craft")
	_add_craft_inputs(inventory_home)
	_add_craft_inputs(inventory_away)
	# Deliberately reuse the same local station ID. The ship owner must remain
	# part of every scheduler/runtime lookup, and only the away station is powered.
	var station_home = _craft_station("ship-home", "shared", false)
	var station_away = _craft_station("ship-away", "shared", true)
	var home_context: Dictionary = _craft_context(crafting, inventory_home, station_home)
	var away_context: Dictionary = _craft_context(crafting, inventory_away, station_away)
	var home_enqueue: Dictionary = scheduler.enqueue(
		_craft_request("ship-home", "shared", inventory_home), home_context)
	var away_enqueue: Dictionary = scheduler.enqueue(
		_craft_request("ship-away", "shared", inventory_away), away_context)
	if not bool(home_enqueue.get("ok", false)) or not bool(away_enqueue.get("ok", false)):
		_fail("two-owner craft fixture admission"); return false
	var home_job: String = str(home_enqueue.get("job_id", ""))
	var away_job: String = str(away_enqueue.get("job_id", ""))
	var home_owner = ShipInstanceScript.create("ship-home", "", null, null, null)
	var away_owner = ShipInstanceScript.create("ship-away", "marker-away", null, null, null)
	away_owner.last_sim_time = 0.0
	var home_runtime = ShipRuntimeScript.new()
	var away_runtime = ShipRuntimeScript.new()
	home_runtime.configure(home_owner, {
		"is_home": true,
		"craft_job_scheduler": scheduler,
		"craft_job_context_provider": func() -> Dictionary: return home_context,
	})
	away_runtime.configure(away_owner, {
		"is_home": false,
		"craft_job_scheduler": scheduler,
		"craft_job_context_provider": func() -> Dictionary: return away_context,
	})
	away_runtime.catch_up(15.0)
	var home_after_away: Dictionary = scheduler.get_job(home_job)
	var away_after_catchup: Dictionary = scheduler.get_job(away_job)
	if absf(float(home_after_away.get("progress", 0.0))) > 0.0001 \
			or str(home_after_away.get("state", "")) != "queued" \
			or absf(float(away_after_catchup.get("progress", 0.0)) - 15.0) > 0.0001:
		_fail("away catch-up used home owner or home power: home=%s away=%s" % [
			str(home_after_away), str(away_after_catchup)]); return false
	# Advancing the unpowered home runtime pauses only the home job. The away
	# record and its elapsed progress remain byte-for-byte unchanged.
	var away_before_home: Dictionary = away_after_catchup.duplicate(true)
	home_runtime.advance(10.0, 10.0)
	if str(scheduler.get_job(home_job).get("state", "")) != "paused_power" \
			or scheduler.get_job(away_job) != away_before_home:
		_fail("home power/tick crossed into owned away job"); return false
	# A missing, malformed, or foreign provider is never equivalent to an empty
	# scheduler filter. Every invalid provider must leave every owner unchanged.
	var invalid_runtime = ShipRuntimeScript.new()
	var all_before_invalid: Dictionary = scheduler.get_summary().duplicate(true)
	invalid_runtime.configure(away_owner, {"craft_job_scheduler": scheduler})
	invalid_runtime.advance(3.0, 18.0)
	if scheduler.get_summary() != all_before_invalid:
		_fail("missing craft context advanced shared scheduler"); return false
	invalid_runtime.configure(away_owner, {
		"craft_job_scheduler": scheduler,
		"craft_job_context_provider": func(): return 7,
	})
	invalid_runtime.advance(3.0, 21.0)
	if scheduler.get_summary() != all_before_invalid:
		_fail("non-dictionary craft context advanced shared scheduler"); return false
	invalid_runtime.configure(away_owner, {
		"craft_job_scheduler": scheduler,
		"craft_job_context_provider": func() -> Dictionary: return {},
	})
	invalid_runtime.advance(3.0, 22.0)
	if scheduler.get_summary() != all_before_invalid \
			or not invalid_runtime.craft_job_receipts.is_empty():
		_fail("empty craft context advanced shared scheduler or emitted receipts"); return false
	invalid_runtime.configure(away_owner, {
		"craft_job_scheduler": scheduler,
		"craft_job_context_provider": func() -> Dictionary: return home_context,
	})
	invalid_runtime.advance(3.0, 24.0)
	if scheduler.get_summary() != all_before_invalid \
			or not invalid_runtime.craft_job_receipts.is_empty():
		_fail("foreign craft context advanced shared scheduler or emitted receipts"); return false
	return true


func _craft_station(ship_id: String, station_id: String, powered: bool):
	var station = StationStateScript.new()
	station.configure({
		"ship_id": ship_id,
		"station_instance_id": station_id,
		"station_kind": "fabricator",
		"level": 0,
		"tier": 0,
		"powered": powered,
	})
	return station


func _craft_context(crafting, inventory, station) -> Dictionary:
	return {
		"ship_id": str(station.ship_id),
		"crafting_state": crafting,
		"source_inventory": inventory,
		"stations": {
			JSON.stringify([str(station.ship_id), str(station.station_instance_id)], "", true): station,
		},
		"player_skill_level": 2,
		"knowledge": null,
	}


func _craft_request(ship_id: String, station_id: String, inventory) -> Dictionary:
	return {
		"ship_id": ship_id,
		"station_instance_id": station_id,
		"station_kind": "fabricator",
		"recipe_id": "craft_power_cell",
		"source_holder_id": str(inventory.get_holder_namespace()),
		"selected_lot_ids": {},
	}


func _add_craft_inputs(inventory) -> void:
	inventory.add_item("scrap_metal", 1)
	inventory.add_item("wiring_bundle", 2)
	inventory.add_item("reactive_gel", 1)


func _on_frame() -> void:
	if finished:
		return
	frames += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or not playable.playable_started:
		if frames > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	finished = true
	_validate_live_contexts()


func _validate_live_contexts() -> void:
	var home = playable.get_home_ship_for_validation()
	if home == null or playable.get_selected_ship_id_for_validation() != str(home.ship_id):
		_fail("home selection bootstrap"); return
	if not home.get_access().has_access("player_local"):
		_fail("new-run home claim missing"); return
	if home.get_live_component_placement() != playable.component_placement_state \
			or home.get_live_ship_modification() != playable.ship_modification_state \
			or home.get_live_binding_generation() <= 0:
		_fail("home restoration owners not bound"); return
	if playable.ship_modification_state.installed_count() != _managed_mounted_count(playable.component_placement_state):
		_fail("ship modification is not a derived placement projection"); return

	playable.force_repair_all_for_validation()
	playable.board_piloted_ship_for_validation()
	playable.recompute_occupancy()
	var marker_ids: Array = playable.scannable_marker_ids_for_validation()
	if marker_ids.is_empty() or not bool(playable.travel_to_marker_id(str(marker_ids[0])).get("success", false)):
		_fail("real two-ship travel"); return
	var derelict = playable.get_current_ship()
	if derelict == null or playable.get_selected_ship_id_for_validation() != str(derelict.ship_id) \
			or derelict.get_live_component_placement() == null:
		_fail("derelict context bind"); return
	if not playable.open_active_dock_barrier_for_validation() or not playable.board_host_for_validation():
		_fail("board derelict host"); return
	playable.recompute_occupancy()
	var ordinary_gate: Dictionary = playable._physical_work_preflight(str(derelict.ship_id), false)
	if not bool(ordinary_gate.get("ok", false)):
		_fail("unclaimed attended repair denied: %s" % str(ordinary_gate)); return
	var permanent_gate: Dictionary = playable._physical_work_preflight(str(derelict.ship_id), true)
	if str(permanent_gate.get("reason", "")) != "no_access":
		_fail("unclaimed permanent mutation not denied"); return
	if not _validate_unclaimed_paid_repair(home, derelict):
		return
	if not playable.open_ship_modification_panel_for_validation():
		_fail("unclaimed inspection panel denied"); return
	if playable.ship_modification_panel.get_bound_ship_id() != str(derelict.ship_id):
		_fail("panel bound wrong ship"); return

	derelict.get_access().claim("player_local")
	var home_before: Dictionary = home.get_live_component_placement().get_summary().duplicate(true)
	var fixture: Dictionary = _prepare_host_component_fixture(derelict)
	if not bool(fixture.get("ok", false)):
		_fail("derelict component fixture: %s" % str(fixture)); return
	var slot_id: String = str(fixture.get("slot_id", ""))
	if not playable.ship_modification_panel.uninstall_selected():
		_fail("derelict panel request"); return
	if not _complete_active_work():
		_fail("derelict timed commit: last=%s record=%s status=%s selected=%s occupancy=%s" % [
			str(playable.get_last_ship_work_result_for_validation()),
			str(playable.get_active_ship_work_record_for_validation()),
			str(playable.work_action_driver.get_status()),
			playable.get_selected_ship_id_for_validation(),
			str(playable.get_current_occupancy_for_validation().ship_id if playable.get_current_occupancy_for_validation() != null else "")]); return
	if derelict.get_live_component_placement().is_mounted(slot_id):
		_fail("derelict placement did not mutate"); return
	if home.get_live_component_placement().get_summary() != home_before:
		_fail("derelict work mutated home placement"); return
	if not _validate_transaction_authority_fail_closed(derelict, fixture, slot_id):
		return
	# A selected owner with a linked component but no systems authority must deny
	# before reserving the returned lot or changing the now-empty physical slot.
	var denied_component_id: String = str(fixture.get("component_id", ""))
	var denied_item_form: String = str(fixture.get("item_form", ""))
	var denied_quantity: int = playable.inventory_state.get_quantity(denied_item_form)
	var missing_systems_before: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(str(derelict.ship_id))
	var derelict_manager = derelict.systems_manager
	derelict.systems_manager = null
	playable.ship_modification_panel.emit_install_request_for_validation(
		slot_id, denied_component_id, denied_item_form)
	derelict.systems_manager = derelict_manager
	if playable.has_active_ship_work_for_validation() \
			or playable.inventory_state.get_quantity(denied_item_form) != denied_quantity \
			or derelict.get_live_component_placement().is_mounted(slot_id) \
			or playable.get_ship_work_authoritative_snapshot_for_validation(
				str(derelict.ship_id)) != missing_systems_before:
		_fail("missing selected systems authority fell through to current/global owner"); return
	if not _validate_selected_noncurrent_module_route(home, derelict, slot_id):
		return

	var old_home_generation: int = home.get_live_binding_generation()
	if not playable.travel_home():
		_fail("return home"); return
	if home.get_live_binding_generation() <= old_home_generation:
		_fail("revisit did not invalidate old home binding"); return
	var home_fixture: Dictionary = playable.prepare_p12_component_work_fixture_for_validation()
	if not bool(home_fixture.get("ok", false)):
		_fail("home fixture after revisit"); return
	var home_slot: String = str(home_fixture.get("slot_id", ""))
	var lifeboat = playable.get_lifeboat_ship_for_validation()
	if lifeboat == null or not playable.ship_modification_panel.uninstall_selected():
		_fail("home timed request before same-owner rebind"); return
	playable.advance_active_ship_work_for_validation(0.25)
	var paid_before_rebind: Dictionary = playable.get_active_ship_work_record_for_validation()
	var stamina_before_rebind: float = float(playable.vitals_state.stamina)
	var placement_before_rebind: Dictionary = home.get_live_component_placement().get_summary().duplicate(true)
	var generation_before_rebind: int = home.get_live_binding_generation()
	if not playable._bind_current_ship_restoration_owners() \
			or home.get_live_binding_generation() <= generation_before_rebind:
		_fail("same-owner live rebind did not change generation"); return
	playable.advance_active_ship_work_for_validation(0.5)
	var paused_after_rebind: Dictionary = playable.get_active_ship_work_record_for_validation()
	var pause_result: Dictionary = playable.get_last_ship_work_result_for_validation()
	if not playable.has_active_ship_work_for_validation() \
			or playable.work_action_driver.get_status() != "paused" \
			or str(pause_result.get("reason", "")) != "stale_binding" \
			or str(paused_after_rebind.get("state", "")) != "paused" \
			or str(paused_after_rebind.get("last_reason", "")) != "stale_binding" \
			or float(paused_after_rebind.get("progress", -1.0)) \
				!= float(paid_before_rebind.get("progress", -2.0)) \
			or paused_after_rebind.get("escrow", []) != paid_before_rebind.get("escrow", []) \
			or absf(float(playable.vitals_state.stamina) - stamina_before_rebind) > 0.0001 \
			or home.get_live_component_placement().get_summary() != placement_before_rebind:
		_fail("stale same-owner work resumed or spent after rebind"); return
	if not playable.cancel_active_ship_work_for_validation("explicit_cancel") \
			or not home.get_live_component_placement().is_mounted(home_slot):
		_fail("stale paid work lacked explicit cancel recovery"); return
	# Complete a fresh dismount so the stable same-ID slot is vacant and the exact
	# returned component lot is available. An old-generation install would now be
	# fully admissible except for its stale binding.
	if not playable.ship_modification_panel.uninstall_selected() \
			or not _complete_active_work() \
			or home.get_live_component_placement().is_mounted(home_slot):
		_fail("stale-generation vacant-slot fixture"); return
	var home_entry: Dictionary = home.get_live_component_placement().get_entry(home_slot)
	var stale_component_id: String = str(home_entry.get("component_id", ""))
	var stale_item_form: String = str(home_entry.get("item_form", ""))
	var stale_inventory_before: Dictionary = playable.inventory_state.get_lot_summary().duplicate(true)
	var stale_ledger = home.get_live_work_transactions()
	var stale_ledger_before: Dictionary = stale_ledger.get_summary().duplicate(true)
	var away_ledger = derelict.get_live_work_transactions()
	var away_ledger_before: Dictionary = away_ledger.get_summary().duplicate(true)
	var stale_placement_before: Dictionary = home.get_live_component_placement().get_summary().duplicate(true)
	var away_placement_before: Dictionary = derelict.get_live_component_placement().get_summary().duplicate(true)
	var stale_authority_before: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(str(home.ship_id))
	var away_authority_before: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(str(derelict.ship_id))
	var current_preflight: Dictionary = playable._ship_mod_install_preflight(
		str(home.ship_id), home.get_live_binding_generation(),
		home_slot, stale_component_id, stale_item_form)
	if not bool(current_preflight.get("ok", false)):
		_fail("stale callback fixture was not otherwise admissible: %s" % str(current_preflight)); return
	var stale_preflight: Dictionary = playable._ship_mod_install_preflight(
		str(home.ship_id), old_home_generation,
		home_slot, stale_component_id, stale_item_form)
	if str(stale_preflight.get("reason", "")) != "stale_binding":
		_fail("old generation did not report stale_binding: %s" % str(stale_preflight)); return
	playable.ship_modification_panel.emit_install_request_for_validation(
		home_slot, stale_component_id, stale_item_form,
		str(home.ship_id), old_home_generation)
	if playable.has_active_ship_work_for_validation() \
			or playable.inventory_state.get_lot_summary() != stale_inventory_before \
			or home.get_live_component_placement().get_summary() != stale_placement_before \
			or derelict.get_live_component_placement().get_summary() != away_placement_before \
			or stale_ledger.get_summary() != stale_ledger_before \
			or away_ledger.get_summary() != away_ledger_before \
			or playable.get_ship_work_authoritative_snapshot_for_validation(
				str(home.ship_id)) != stale_authority_before \
			or playable.get_ship_work_authoritative_snapshot_for_validation(
				str(derelict.ship_id)) != away_authority_before:
		_fail("stale panel callback mutated home"); return
	if not bool(playable.select_ship_for_modification_for_validation(
			str(lifeboat.ship_id)).get("ok", false)):
		_fail("attached lifeboat inspection selection"); return
	if not _validate_home_access_disk_round_trip():
		return

	print("FC P13 PASS")
	main_node.queue_free()
	quit(0)


func _complete_active_work() -> bool:
	if not playable.has_active_ship_work_for_validation():
		return false
	playable.vitals_state.stamina = playable.vitals_state.max_stamina
	playable.move_player_to_active_ship_work_target_for_validation()
	for _step in range(200):
		playable.advance_active_ship_work_for_validation(0.5)
		if not playable.has_active_ship_work_for_validation():
			return bool(playable.get_last_ship_work_result_for_validation().get("ok", false))
	return false


func _validate_unclaimed_paid_repair(home, derelict) -> bool:
	var context = playable._ship_work_context_for(str(derelict.ship_id))
	if context == null or context.module_integrity == null:
		_fail("unclaimed repair context missing"); return false
	var layout: Dictionary = playable._layout_for_ship(derelict)
	var nearest: Dictionary = playable._nearest_workable_wall_module(
		layout, (derelict.scene_root as Node3D).global_position, 1000.0,
		context.module_integrity, derelict)
	var module_id: String = str(nearest.get("module_id", ""))
	var module_kind: String = str(nearest.get("kind", "wall_straight_1x1"))
	var target_position: Variant = playable._compiled_wrapper_world_position(module_id, derelict)
	if module_id.is_empty() or not (target_position is Vector3):
		_fail("unclaimed repair target missing"); return false
	context.module_integrity.apply_damage(module_id, 0.35, module_kind)
	var damaged_module = context.module_integrity.get_module(module_id)
	var integrity_before: float = float(damaged_module.integrity)
	var home_before: Dictionary = home.get_live_module_integrity().get_summary().duplicate(true)
	if playable.inventory_state.get_quantity("welding_lance") <= 0:
		playable.inventory_state.add_item("welding_lance", 1)
	if playable.inventory_state.get_quantity("hull_plate") <= 0:
		playable.inventory_state.add_item("hull_plate", 1)
	var plate_before: int = playable.inventory_state.get_quantity("hull_plate")
	var module_authority_before: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(str(derelict.ship_id))
	var forged_nearby: Vector3 = (target_position as Vector3) \
		+ Vector3(playable.WORK_ACTION_INTERACT_RANGE + 1.0, 0.0, 0.0)
	playable.player.global_position = forged_nearby
	var forged_module_start: Dictionary = playable._start_transactional_work(
		"weld_patch", module_id, "module",
		playable._module_target_revision(module_id, context), {
			"tool_class": "welding_lance",
			"skill_id": "repair",
			"skill_level": 99,
			"inventory": playable._inventory_qty_dict_for_work(),
		}, {}, forged_nearby, PackedStringArray(), str(derelict.ship_id))
	if str(forged_module_start.get("reason", "")) != "stale_target_position" \
			or playable.has_active_ship_work_for_validation() \
			or playable.get_ship_work_authoritative_snapshot_for_validation(
				str(derelict.ship_id)) != module_authority_before:
		_fail("forged nearby module point admitted distant authenticated target: %s" % [
			str(forged_module_start)]); return false
	playable.player.global_position = target_position as Vector3
	playable.recompute_occupancy()
	if playable.get_current_occupancy_for_validation() != derelict \
			or not playable.try_work_action_interact_for_validation():
		_fail("unclaimed paid repair did not start"); return false
	var record: Dictionary = playable.get_active_ship_work_record_for_validation()
	if str(record.get("ship_id", "")) != str(derelict.ship_id) \
			or str(record.get("target_id", "")) != module_id \
			or str(record.get("target_kind", "")) != "module":
		_fail("unclaimed repair targeted wrong owner: %s" % str(record)); return false
	if not _complete_active_work():
		_fail("unclaimed paid repair did not commit"); return false
	if float(context.module_integrity.get_module(module_id).integrity) <= integrity_before \
			or playable.inventory_state.get_quantity("hull_plate") != plate_before - 1 \
			or home.get_live_module_integrity().get_summary() != home_before:
		_fail("unclaimed paid repair was not isolated/economic"); return false
	if not _validate_same_generation_stale_target(
			derelict, context, module_id, module_kind, target_position as Vector3):
		return false
	return true


func _validate_same_generation_stale_target(
		derelict, context, module_id: String, module_kind: String,
		target_position: Vector3) -> bool:
	context.module_integrity.apply_damage(module_id, 0.45, module_kind)
	if playable.inventory_state.get_quantity("hull_plate") <= 0:
		playable.inventory_state.add_item("hull_plate", 1)
	playable.player.global_position = target_position
	playable.recompute_occupancy()
	var authoritative_before: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(str(derelict.ship_id))
	if not playable.try_work_action_interact_for_validation():
		_fail("same-generation stale target work did not start"); return false
	var paid_before_change: Dictionary = playable.get_active_ship_work_record_for_validation()
	var exact_escrow: Array = (paid_before_change.get("escrow", []) as Array).duplicate(true)
	if str(paid_before_change.get("ship_id", "")) != str(derelict.ship_id) \
			or str(paid_before_change.get("target_id", "")) != module_id \
			or exact_escrow.size() != 1 or not (exact_escrow[0] is Dictionary):
		_fail("same-generation stale target chose wrong module: %s" % str(paid_before_change)); return false
	var stamina_before_change: float = float(playable.vitals_state.stamina)
	context.module_integrity.apply_damage(module_id, 0.05, module_kind)
	var changed_target: Dictionary = context.module_integrity.get_module(module_id).get_summary().duplicate(true)
	var authoritative_changed: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(str(derelict.ship_id))
	playable.advance_active_ship_work_for_validation(0.5)
	var paused: Dictionary = playable.get_active_ship_work_record_for_validation()
	var authoritative_paused: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(str(derelict.ship_id))
	if str(playable.get_last_ship_work_result_for_validation().get("reason", "")) != "stale_target" \
			or str(paused.get("state", "")) != "paused" \
			or str(paused.get("last_reason", "")) != "stale_target" \
			or float(paused.get("progress", -1.0)) != float(paid_before_change.get("progress", -2.0)) \
			or paused.get("escrow", []) != paid_before_change.get("escrow", []) \
			or absf(float(playable.vitals_state.stamina) - stamina_before_change) > 0.0001 \
			or context.module_integrity.get_module(module_id).get_summary() != changed_target \
			or not _same_authoritative_consequences(
				authoritative_changed, authoritative_paused):
		_fail("same-generation stale target spent or resumed"); return false
	var cancelled: Dictionary = playable._cancel_active_ship_work("explicit_cancel")
	var authoritative_after: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(str(derelict.ship_id))
	var cancelled_record: Dictionary = context.work_transactions.get_record(
		str(paid_before_change.get("work_id", "")))
	if not bool(cancelled.get("ok", false)) \
			or cancelled.get("returned_lots", []) != exact_escrow \
			or authoritative_after.get("lots", {}) != authoritative_before.get("lots", {}) \
			or not _same_authoritative_consequences(
				authoritative_changed, authoritative_after) \
			or int(authoritative_after.get("receipt_count", -1)) \
			!= int(authoritative_before.get("receipt_count", -2)) \
			or str(cancelled_record.get("state", "")) != "cancelled" \
			or not (cancelled_record.get("escrow", []) as Array).is_empty():
		_fail("same-generation stale target lacked cancel recovery"); return false
	return true


func _same_authoritative_consequences(before: Dictionary, after: Dictionary) -> bool:
	for key in [
		"placement", "integrity", "modification", "systems", "receipt_count", "effects",
		"threat_noise", "completion_audio", "training_log", "delivered_xp", "progression",
	]:
		if before.get(key) != after.get(key):
			return false
	return true


func _validate_transaction_authority_fail_closed(
		derelict, fixture: Dictionary, slot_id: String) -> bool:
	var real_ledger = derelict.get_live_work_transactions()
	var owner_id: String = str(derelict.ship_id)
	if real_ledger == null or not playable._ship_work_transactions_by_ship.has(owner_id) \
			or playable._ship_work_transactions_by_ship[owner_id] != real_ledger:
		_fail("transaction fallback fixture missing populated owner map"); return false
	var component_id: String = str(fixture.get("component_id", ""))
	var item_form: String = str(fixture.get("item_form", ""))
	var inventory_before: Dictionary = playable.inventory_state.get_lot_summary().duplicate(true)
	var placement_before: Dictionary = derelict.get_live_component_placement().get_summary().duplicate(true)
	var ledger_before: Dictionary = real_ledger.get_summary().duplicate(true)
	var authority_before: Dictionary = \
		playable.get_ship_work_authoritative_snapshot_for_validation(owner_id)
	var ledger_keys_before: Array = playable._ship_work_transactions_by_ship.keys()
	ledger_keys_before.sort()
	derelict.live_work_transactions = null
	var null_preflight: Dictionary = playable._ship_mod_install_preflight(
		owner_id, derelict.get_live_binding_generation(), slot_id, component_id, item_form)
	playable.ship_modification_panel.emit_install_request_for_validation(
		slot_id, component_id, item_form, owner_id, derelict.get_live_binding_generation())
	derelict.live_work_transactions = real_ledger
	if str(null_preflight.get("reason", "")) != "missing_work_authority" \
			or playable.has_active_ship_work_for_validation() \
			or playable.inventory_state.get_lot_summary() != inventory_before \
			or derelict.get_live_component_placement().get_summary() != placement_before \
			or real_ledger.get_summary() != ledger_before \
			or playable._ship_work_transactions_by_ship.get(owner_id) != real_ledger \
			or _sorted_keys(playable._ship_work_transactions_by_ship) != ledger_keys_before \
			or playable.get_ship_work_authoritative_snapshot_for_validation(owner_id) \
			!= authority_before:
		_fail("null selected ledger fell through to coordinator map"); return false
	var foreign_ledger = ShipWorkTransactionScript.new()
	foreign_ledger.configure("foreign-ship")
	derelict.live_work_transactions = foreign_ledger
	var foreign_before: Dictionary = foreign_ledger.get_summary().duplicate(true)
	var foreign_preflight: Dictionary = playable._ship_mod_install_preflight(
		owner_id, derelict.get_live_binding_generation(), slot_id, component_id, item_form)
	playable.ship_modification_panel.emit_install_request_for_validation(
		slot_id, component_id, item_form, owner_id, derelict.get_live_binding_generation())
	derelict.live_work_transactions = real_ledger
	if str(foreign_preflight.get("reason", "")) != "missing_work_authority" \
			or playable.has_active_ship_work_for_validation() \
			or playable.inventory_state.get_lot_summary() != inventory_before \
			or derelict.get_live_component_placement().get_summary() != placement_before \
			or real_ledger.get_summary() != ledger_before \
			or foreign_ledger.get_summary() != foreign_before \
			or playable.get_ship_work_authoritative_snapshot_for_validation(owner_id) \
			!= authority_before:
		_fail("foreign selected ledger fell through to coordinator map"); return false
	return true


func _sorted_keys(source: Dictionary) -> Array:
	var keys: Array = source.keys()
	keys.sort()
	return keys


func _prepare_host_component_fixture(owner) -> Dictionary:
	if playable.inventory_state.get_quantity("wrench") <= 0:
		playable.inventory_state.add_item("wrench", 1)
	var context = playable._ship_work_context_for(str(owner.ship_id))
	for entry_v in owner.get_live_component_placement().placed:
		if not (entry_v is Dictionary) or not bool((entry_v as Dictionary).get("mounted", false)):
			continue
		var entry: Dictionary = entry_v as Dictionary
		var component_id: String = str(entry.get("component_id", ""))
		var component_def: Dictionary = playable.component_catalog.get_component(component_id)
		if str(component_def.get("linked_system", "")).is_empty():
			continue
		var slot_id: String = str(entry.get("component_instance_id", ""))
		var position_v: Variant = playable._component_slot_world_position(slot_id, context)
		if not (position_v is Vector3):
			continue
		playable.player.global_position = position_v as Vector3
		playable.recompute_occupancy()
		if playable.get_current_occupancy_for_validation() != owner:
			continue
		if not playable.ship_modification_panel.select_slot_id(slot_id):
			continue
		playable.ship_modification_panel.set_inventory(playable._inventory_qty_dict_for_work())
		return {
			"ok": true,
			"slot_id": slot_id,
			"component_id": component_id,
			"item_form": str(entry.get("item_form", "")),
		}
	return {"ok": false, "reason": "no_host_component_outside_docked_ship"}


func _validate_selected_noncurrent_module_route(home, derelict, derelict_slot_id: String) -> bool:
	var home_context = playable._ship_work_context_for(str(home.ship_id))
	var home_layout: Dictionary = playable._layout_for_ship(home)
	var nearest: Dictionary = playable._nearest_workable_wall_module(
		home_layout, (home.scene_root as Node3D).global_position, 1000.0,
		home_context.module_integrity, home)
	var module_id: String = str(nearest.get("module_id", ""))
	var target_position: Variant = playable._compiled_wrapper_world_position(module_id, home)
	if module_id.is_empty() or not (target_position is Vector3):
		_fail("no explicit home module target while derelict current"); return false
	_remove_all("wrench")
	_remove_all("tool_wrench")
	if playable.inventory_state.get_quantity("prybar") <= 0:
		playable.inventory_state.add_item("prybar", 1)
	playable.player.global_position = target_position as Vector3
	playable.recompute_occupancy()
	if playable.get_current_ship() != derelict \
			or playable.get_current_occupancy_for_validation() != home \
			or not bool(playable.select_ship_for_modification_for_validation(
				str(home.ship_id)).get("ok", false)):
		_fail("co-present home selection/occupancy setup"); return false
	var home_before: Dictionary = home_context.module_integrity.get_summary().duplicate(true)
	var derelict_before: Dictionary = derelict.get_live_module_integrity().get_summary().duplicate(true)
	if not playable.try_work_action_interact_for_validation():
		_fail("selected non-current home work route denied"); return false
	var record: Dictionary = playable.get_active_ship_work_record_for_validation()
	if str(record.get("ship_id", "")) != str(home.ship_id) \
			or str(record.get("target_id", "")) != module_id:
		_fail("work target discovery did not retain selected owner: %s" % str(record)); return false
	if not playable.cancel_active_ship_work_for_validation("explicit_cancel") \
			or home_context.module_integrity.get_summary() != home_before \
			or derelict.get_live_module_integrity().get_summary() != derelict_before:
		_fail("selected non-current cancellation crossed integrity owners"); return false
	var derelict_context = playable._ship_work_context_for(str(derelict.ship_id))
	var derelict_position: Variant = playable._component_slot_world_position(
		derelict_slot_id, derelict_context)
	if not (derelict_position is Vector3):
		_fail("could not restore derelict attendance after context probe"); return false
	playable.player.global_position = derelict_position as Vector3
	playable.recompute_occupancy()
	if playable.get_current_occupancy_for_validation() != derelict \
			or not bool(playable.select_ship_for_modification_for_validation(
				str(derelict.ship_id)).get("ok", false)):
		_fail("derelict context restore after selected-home work"); return false
	if playable.inventory_state.get_quantity("wrench") <= 0:
		playable.inventory_state.add_item("wrench", 1)
	return true


func _validate_home_access_disk_round_trip() -> bool:
	var home = playable.get_home_ship_for_validation()
	var foreign = ShipAccessStateScript.create()
	foreign.claim("remote_owner")
	home.access = foreign
	if not playable.save_world_for_validation():
		_fail("foreign home access world save"); return false
	# Destroy the only process-local copy before loading. Successful restoration
	# must therefore come from WorldSnapshot.home_access_v1 after JSON parsing.
	var local = ShipAccessStateScript.create()
	local.claim("player_local")
	home.access = local
	if not playable.load_world_for_validation():
		_fail("foreign home access world load"); return false
	playable = main_node.playable_instance
	if playable == null:
		_fail("foreign home access load did not publish the replacement"); return false
	var restored_home = playable.get_home_ship_for_validation()
	if restored_home == null or str(restored_home.get_access().owner_id) != "remote_owner" \
			or restored_home.get_access().has_access("player_local"):
		_fail("modern foreign home owner did not survive disk JSON"); return false
	var valid_world: Dictionary = _read_world_json()
	if valid_world.is_empty():
		_fail("read valid foreign home world JSON"); return false
	var save_service = playable.get_save_load_service()
	if save_service == null:
		_fail("save service missing for access rejection"); return false

	# A present malformed owner is modern data, never a legacy bootstrap hint.
	# Detached preparation must reject it before replacing the live foreign owner.
	var malformed_world: Dictionary = valid_world.duplicate(true)
	malformed_world["home_access_v1"] = {
		"owner_id": "remote_owner",
		"access_ids": [],
	}
	if not _write_world_json(malformed_world, save_service):
		_fail("write malformed home access JSON"); return false
	var foreign_before: Dictionary = restored_home.get_access().get_summary().duplicate(true)
	var malformed_prepare: Dictionary = save_service.prepare_world_load()
	if bool(malformed_prepare.get("ok", false)):
		save_service.discard_prepared_load(str(malformed_prepare.get("token", "")))
		_fail("malformed present home access accepted"); return false
	if playable.get_home_ship_for_validation() != restored_home \
			or restored_home.get_access().get_summary() != foreign_before:
		_fail("malformed present home access mutated live owner"); return false

	# Downgrade an otherwise valid disk payload to the recognized v4 pair and
	# remove only the field old worlds never carried. The real request-load path
	# may claim this verified absence locally after detached migration succeeds.
	var legacy_world: Dictionary = valid_world.duplicate(true)
	legacy_world["slice_version"] = "world-4"
	var legacy_home_v: Variant = legacy_world.get("home_ship", null)
	if not (legacy_home_v is Dictionary):
		_fail("legacy home slice missing"); return false
	(legacy_home_v as Dictionary)["slice_version"] = "gate2-current-run-4"
	# The current capture carries the v6 combat schema. A real v4 home either
	# omitted combat for deterministic bootstrap or carried the schema-less
	# historical shape; it never carried threat-manager-2 under a v4 marker.
	(legacy_home_v as Dictionary).erase("threat_summary")
	# The source world was captured by the current component contract. A genuine
	# v4 payload predates immutable source lots and mounted-history rows, so remove
	# those v5-only fields before exercising the recognized outer-version adapter.
	# Keeping them while changing only the version marker creates a downgrade
	# forgery which the strict migration correctly rejects.
	_downgrade_component_placement_to_v4(
		(legacy_home_v as Dictionary).get("component_placement_summary", {}) as Dictionary)
	if not _remove_v5_component_inventory_lots(legacy_home_v as Dictionary):
		_fail("could not normalize current component inventory to v4 fixture"); return false
	for visited_v in (legacy_world.get("visited_ships", {}) as Dictionary).values():
		if visited_v is Dictionary:
			(visited_v as Dictionary).erase("combat")
			_downgrade_component_placement_to_v4(
				(visited_v as Dictionary).get("component_placement", {}) as Dictionary)
	legacy_world.erase("home_access_v1")
	if not _write_world_json(legacy_world, save_service):
		_fail("write legacy absent-access JSON"); return false
	var legacy_source_bytes: String = FileAccess.get_file_as_string(
		SaveLoadServiceScript.WORLD_SLOT_FILE)
	var legacy_prepare: Dictionary = save_service.prepare_world_load()
	if not bool(legacy_prepare.get("ok", false)) \
			or not bool(legacy_prepare.get("migrated", false)) \
			or FileAccess.get_file_as_string(SaveLoadServiceScript.WORLD_SLOT_FILE) \
				!= legacy_source_bytes:
		_fail("recognized legacy access omission rejected: %s" % str(legacy_prepare)); return false
	var prepared_world: Dictionary = save_service.inspect_prepared_world_for_validation(
		str(legacy_prepare.get("token", "")), str(legacy_prepare.get("seal", "")))
	if prepared_world.is_empty() \
			or prepared_world.get("home_access_v1", {}) != {
				"owner_id": "player_local", "access_ids": ["player_local"]} \
			or str(prepared_world.get("home_ship", {}).get(
				"inventory_summary", {}).get("combat_hotbar_text", "missing")) != "":
		_fail("legacy omission did not materialize exact local access authority"); return false
	save_service.discard_prepared_load(str(legacy_prepare.get("token", "")))
	# Historical sources that already carried the optional display projection
	# retain it byte-for-byte; absence alone receives the empty runtime default.
	var legacy_hotbar_text: String = "Legacy hotbar | Threat 0.375 | exact"
	var legacy_present: Dictionary = legacy_world.duplicate(true)
	legacy_present.home_ship.inventory_summary["combat_hotbar_text"] = legacy_hotbar_text
	if not _write_world_json(legacy_present, save_service):
		_fail("write legacy present-hotbar JSON"); return false
	var present_prepare: Dictionary = save_service.prepare_world_load()
	var present_world: Dictionary = save_service.inspect_prepared_world_for_validation(
		str(present_prepare.get("token", "")), str(present_prepare.get("seal", "")))
	if not bool(present_prepare.get("ok", false)) \
			or str(present_world.get("home_ship", {}).get(
				"inventory_summary", {}).get("combat_hotbar_text", "")) != legacy_hotbar_text:
		_fail("legacy present hotbar text changed: %s" % str(present_prepare)); return false
	save_service.discard_prepared_load(str(present_prepare.get("token", "")))
	if not _write_world_json(legacy_world, save_service):
		_fail("restore legacy absent-hotbar JSON"); return false
	if not playable.request_load():
		_fail("legacy absent-access world apply: %s" % str(
			main_node.get_last_restore_failure_reason_for_validation())); return false
	playable = main_node.playable_instance
	if playable == null:
		_fail("legacy absent-access load did not publish the replacement"); return false
	var legacy_home = playable.get_home_ship_for_validation()
	if legacy_home == null or str(legacy_home.get_access().owner_id) != "player_local" \
			or not legacy_home.get_access().has_access("player_local"):
		_fail("recognized legacy home omission did not claim locally"); return false
	return true


func _downgrade_component_placement_to_v4(summary: Dictionary) -> void:
	var retained: Array = []
	for entry_v in summary.get("placed", []) as Array:
		if entry_v is Dictionary:
			# Pre-v5 saves had no dismount-history rows or component lot
			# inventory. The fixture projects every authored slot back to its v4
			# mounted state while the companion inventory helper removes the
			# current-only extracted lots.
			var entry: Dictionary = (entry_v as Dictionary).duplicate(true)
			entry.erase("source_lot")
			entry.erase("source_lot_id")
			entry.erase("mounted")
			retained.append(entry)
	summary["placed"] = retained
	summary["count"] = retained.size()


func _remove_v5_component_inventory_lots(run_summary: Dictionary) -> bool:
	var inventory_summary_v: Variant = run_summary.get("inventory_summary", null)
	if not (inventory_summary_v is Dictionary):
		return false
	var lots_v: Variant = (inventory_summary_v as Dictionary).get("item_lots_v1", null)
	if not (lots_v is Dictionary) or not (lots_v as Dictionary).get("lots", null) is Array:
		return false
	var component_lots: Array = []
	for lot_v in (lots_v as Dictionary).lots as Array:
		if lot_v is Dictionary and str((lot_v as Dictionary).get("lot_id", "")).find(
				":components/") >= 0:
			component_lots.append((lot_v as Dictionary).duplicate(true))
	var inventory = InventoryStateScript.new(str((lots_v as Dictionary).get(
		"holder_namespace", "")))
	if not inventory.apply_summary(inventory_summary_v as Dictionary):
		return false
	for lot in component_lots:
		var quantity: int = int(lot.get("quantity", 0))
		var removed: Array = inventory.take_lots(
			str(lot.get("item_id", "")), quantity,
			PackedStringArray([str(lot.get("lot_id", ""))]))
		var removed_quantity: int = 0
		for removed_lot_v in removed:
			if removed_lot_v is Dictionary:
				removed_quantity += int((removed_lot_v as Dictionary).get("quantity", 0))
		if removed_quantity != quantity:
			return false
	run_summary["inventory_summary"] = inventory.get_summary()
	return true


func _read_world_json() -> Dictionary:
	var file := FileAccess.open(SaveLoadServiceScript.WORLD_SLOT_FILE, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_world_json(payload: Dictionary, save_service = null) -> bool:
	var file := FileAccess.open(SaveLoadServiceScript.WORLD_SLOT_FILE, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t", true, true))
	file.close()
	if save_service != null:
		save_service.call(
			"_write_cloud_manifest", "world", SaveLoadServiceScript.WORLD_SLOT_FILE,
			str(payload.get("slice_version", "")))
	return true


func _remove_all(item_id: String) -> void:
	var quantity: int = playable.inventory_state.get_quantity(item_id)
	if quantity > 0:
		playable.inventory_state.remove_item(item_id, quantity)


func _managed_mounted_count(placement) -> int:
	var count: int = 0
	for entry_v in placement.placed:
		if entry_v is Dictionary and bool((entry_v as Dictionary).get("mounted", false)) \
				and bool((entry_v as Dictionary).get("ship_mod_managed", false)):
			count += 1
	return count


func _find_playable(node: Node):
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	print("FC P13 FAIL: %s" % message)
	finished = true
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
