extends SceneTree

## P04 contract fixture. This starts RED until cargo holders and transfers retain
## the exact P03 lots rather than reducing them to aggregate quantities.

const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")
const CartStateScript := preload("res://scripts/systems/cart_state.gd")
const WorkYieldDropScript := preload("res://scripts/tools/work_yield_drop.gd")
const LootContainerScript := preload("res://scripts/tools/loot_container.gd")
const DeconstructionResolverScript := preload("res://scripts/systems/deconstruction_resolver.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const CraftingStationScript := preload("res://scripts/tools/crafting_station.gd")
const RecipeKnowledgeStateScript := preload("res://scripts/systems/recipe_knowledge_state.gd")

func _lot(holder, id: String) -> Dictionary:
	for entry in (holder.get_lot_summary().get("lots", []) as Array):
		if entry is Dictionary and str((entry as Dictionary).get("lot_id", "")) == id:
			return entry as Dictionary
	return {}

func _first_lot(holder, item_id: String) -> Dictionary:
	for entry in (holder.get_lot_summary().get("lots", []) as Array):
		if entry is Dictionary and str((entry as Dictionary).get("item_id", "")) == item_id:
			return entry as Dictionary
	return {}

func _init() -> void:
	var player = InventoryStateScript.new()
	assert(player.add_lot({"lot_id":"salvage-a", "item_id":"scrap_metal", "quantity":4, "quality_score":0.82, "quality_tier":"excellent", "condition":0.63, "origin":{"corpse":"c1"}}) == 4)
	var cart = ShipInventoryScript.create(10.0)
	assert(CargoTransferScript.move_item(player, cart, "scrap_metal", 1) == 1)
	var moved: Dictionary = _first_lot(cart, "scrap_metal")
	assert(not moved.is_empty(), "partial move retained exact outgoing lot")
	assert(float(moved.quality_score) == 0.82 and float(moved.condition) == 0.63 and moved.origin == {"corpse":"c1"})
	assert(_lot(player, "salvage-a").quantity == 3, "source preserves original id on split")
	var full = ShipInventoryScript.create(0.0)
	assert(CargoTransferScript.move_item(player, full, "scrap_metal", 2) == 0, "hard-cap rejection keeps source")
	assert(_lot(player, "salvage-a").quantity == 3, "rejected quantity was not removed")
	assert(cart.apply_summary(cart.get_summary()), "intermediate holder save restores lots")
	assert(_first_lot(cart, "scrap_metal").origin == {"corpse":"c1"}, "save preserves origin")
	assert(player.add_lot({"lot_id":"suit-a", "item_id":"eva_backpack", "quantity":1, "quality_score":0.82, "quality_tier":"excellent", "condition":0.44, "origin":{"corpse":"c2"}}) == 1)
	var worn: Array = player.take_lots("eva_backpack", 1)
	var equipment = EquipmentStateScript.create()
	assert(bool(equipment.equip_lot(worn[0] as Dictionary).get("ok", false)), "equipment accepts exact lot")
	assert(equipment.apply_summary(equipment.get_summary()), "equipment save restores lot")
	var returned: Dictionary = equipment.unequip_lot("back")
	assert(returned.origin == {"corpse":"c2"} and float(returned.condition) == 0.44, "equipment preserves metadata")
	# Real holder chain: player -> cart -> cargo -> floor -> player -> equipment.
	var route_player = InventoryStateScript.new("player:p04-route")
	assert(route_player.add_lot({"lot_id":"route-a", "item_id":"scrap_metal", "quantity":2, "quality_score":0.82, "quality_tier":"excellent", "condition":0.41, "origin":{"salvage":"route"}}) == 2)
	var route_cart = CartStateScript.create("p04-cart", 100.0)
	var route_cargo = ShipInventoryScript.create(100.0, "ship:p04-cargo")
	assert(CargoTransferScript.move_item(route_player, route_cart.get_hold(), "scrap_metal", 1) == 1)
	assert(CargoTransferScript.move_item(route_cart.get_hold(), route_cargo, "scrap_metal", 1) == 1)
	var floor = WorkYieldDropScript.new()
	floor.configure("p04-floor", {}, route_player, Vector3.ZERO)
	assert(CargoTransferScript.move_item(route_cargo, floor, "scrap_metal", 1) == 1)
	var floor_player := Node.new()
	floor.set_validation_player_in_range(floor_player)
	assert(floor.try_interact(floor_player), "floor scoops a preserved lot")
	var route_lot: Dictionary = _first_lot(route_player, "scrap_metal")
	assert(not route_lot.is_empty() and route_lot.origin == {"salvage":"route"} and float(route_lot.condition) == 0.41, "route metadata survives every holder")
	assert(route_cart.apply_summary(route_cart.get_summary()), "cart intermediate save restores lots")
	var anonymous_source = InventoryStateScript.new()
	assert(anonymous_source.add_item("scrap_metal", 1) == 1)
	var foreign_cart = CartStateScript.create("p04-foreign-cart", 100.0)
	assert(CargoTransferScript.move_item(anonymous_source, foreign_cart.get_hold(), "scrap_metal", 1) == 1)
	assert(foreign_cart.apply_summary(foreign_cart.get_summary()), "cart restores a native foreign-holder lot")
	var json_round_trip: Variant = JSON.parse_string(JSON.stringify(foreign_cart.get_summary()))
	assert(json_round_trip is Dictionary and foreign_cart.apply_summary(json_round_trip as Dictionary), "cart restores JSON round-trip lots")
	# Actual loot interaction: local container IDs repeat across ships but their
	# full seed source keeps lots distinct; authored metadata survives deposit.
	var looter = InventoryStateScript.new("player:p04-loot")
	var loot_player := Node3D.new()
	var crate_a = LootContainerScript.new()
	var crate_b = LootContainerScript.new()
	for crate in [crate_a, crate_b]:
		crate.configure("shared_crate", "", ("ship-A:" if crate == crate_a else "ship-B:") + "shared_crate", looter, {}, Vector3.ZERO, 1.0, {"contents":[{"item_id":"ration_pack","quantity":1,"quality_score":0.82,"condition_score":0.41,"origin":{"authored":true}}]})
		crate.set_validation_player_in_range(loot_player)
		assert(crate.try_interact(loot_player), "distinct shared-id crate grants")
	assert(looter.get_quantity("ration_pack") == 2, "both ship crates grant")
	var loot_lot: Dictionary = _first_lot(looter, "ration_pack")
	assert(float(loot_lot.quality_score) == 0.82 and float(loot_lot.condition) == 0.41 and loot_lot.origin == {"authored":true}, "authored metadata preserved")
	looter.add_item("scrap_metal", 19)
	var blocked = LootContainerScript.new()
	blocked.configure("blocked", "", "ship-C:blocked", looter, {}, Vector3.ZERO, 1.0, {"contents":[{"item_id":"scrap_metal","quantity":1},{"item_id":"scrap_metal","quantity":1}]})
	blocked.set_validation_player_in_range(loot_player)
	assert(not blocked.try_interact(loot_player) and not blocked.searched and looter.get_quantity("scrap_metal") == 19, "all rejected loot remains reachable")
	looter.remove_item("scrap_metal", 2)
	assert(blocked.try_interact(loot_player) and looter.get_quantity("scrap_metal") == 19, "rejected multi-stack remainder grants after room restored")
	# Junk salvage creates material lots rather than a scalar quality aggregate.
	var salvage_inventory = InventoryStateScript.new("player:p04-salvage")
	assert(salvage_inventory.add_lot({"lot_id":"junk-source", "item_id":"frayed_cable_coil", "quantity":1, "quality_score":0.82, "quality_tier":"excellent", "condition":0.37, "origin":{"corpse":"salvage"}}) == 1)
	var resolver = DeconstructionResolverScript.new()
	var salvage_result: Dictionary = resolver.salvage_junk_item("frayed_cable_coil", salvage_inventory, null)
	assert(not salvage_result.is_empty(), "junk salvage succeeds")
	var salvage_lot: Dictionary = _first_lot(salvage_inventory, "wiring_bundle")
	assert(not salvage_lot.is_empty() and str(salvage_lot.origin.get("junk_source", "")) == "frayed_cable_coil" and not str(salvage_lot.origin.get("source_lot_id", "")).is_empty() and is_equal_approx(float(salvage_lot.quality_score), 0.656) and float(salvage_lot.condition) == 1.0, "salvage yield keeps exact lot metadata")
	# Resolver recreation/reload cannot reuse output identities because every
	# yield ID derives from the exact consumed source lot, not resolver memory.
	var repeated = InventoryStateScript.new("player:p04-salvage-repeat")
	assert(repeated.add_lot({"lot_id":"junk-source-a", "item_id":"frayed_cable_coil", "quantity":1, "quality_score":0.82, "quality_tier":"excellent", "condition":0.37, "origin":{"corpse":"a"}}) == 1)
	assert(repeated.add_lot({"lot_id":"junk-source-b", "item_id":"frayed_cable_coil", "quantity":1, "quality_score":0.60, "quality_tier":"good", "condition":0.51, "origin":{"corpse":"b"}}) == 1)
	assert(not DeconstructionResolverScript.new().salvage_junk_item("frayed_cable_coil", repeated, null).is_empty())
	var reloaded = InventoryStateScript.new("player:p04-salvage-repeat")
	assert(reloaded.apply_summary(JSON.parse_string(JSON.stringify(repeated.get_summary())) as Dictionary), "salvage intermediate reload")
	assert(not DeconstructionResolverScript.new().salvage_junk_item("frayed_cable_coil", reloaded, null).is_empty(), "fresh resolver salvages distinct second lot")
	assert(reloaded.get_quantity("frayed_cable_coil") == 0 and reloaded.get_quantity("wiring_bundle") == 4 and reloaded.get_quantity("polymer_pellet") == 2, "fresh resolver conserves all quantities")
	var repeat_lots: Array = reloaded.get_lot_summary().lots as Array
	var saw_source_a: bool = false
	var saw_source_b: bool = false
	for raw_repeat in repeat_lots:
		var repeat_lot: Dictionary = raw_repeat as Dictionary
		var output_source: String = str((repeat_lot.get("origin", {}) as Dictionary).get("source_lot_id", ""))
		if output_source == "junk-source-a":
			saw_source_a = true
			assert(float(repeat_lot.quality_score) == 0.656, "first output inherits exact source quality")
		elif output_source == "junk-source-b":
			saw_source_b = true
			assert(float(repeat_lot.quality_score) == 0.48, "second output inherits exact source quality")
	assert(saw_source_a and saw_source_b, "both exact source identities survive resolver recreation")
	# Full output capacity rejects the detached candidate, leaving source and all
	# existing lots byte-for-byte unchanged.
	var full_salvage = InventoryStateScript.new("player:p04-salvage-full")
	assert(full_salvage.add_lot({"lot_id":"junk-full-source", "item_id":"frayed_cable_coil", "quantity":1, "quality_score":0.82, "quality_tier":"excellent", "condition":0.37, "origin":{"corpse":"full"}}) == 1)
	var wiring_cap: int = int(full_salvage.get_definition("wiring_bundle").get("max_stack", 99))
	assert(full_salvage.add_item("wiring_bundle", wiring_cap) == wiring_cap)
	var full_before: Dictionary = full_salvage.get_summary()
	assert(DeconstructionResolverScript.new().salvage_junk_item("frayed_cable_coil", full_salvage, null).is_empty(), "full yield capacity rejects")
	assert(full_salvage.get_summary() == full_before, "capacity rejection rolls back exact source and all outputs")
	# The production station delegates deposit ownership to the resolver. Recreating
	# both after a JSON reload must consume a second exact source, create a distinct
	# output lot, and emit one completion per committed transaction.
	var station_inventory = InventoryStateScript.new("player:p04-station-salvage")
	assert(station_inventory.add_lot({"lot_id":"thruster-source-a", "item_id":"thruster_nozzle", "quantity":1, "quality_score":0.82, "quality_tier":"excellent", "condition":0.37, "origin":{"wreck":"a"}}) == 1)
	var crafting = CraftingStateScript.new()
	var materials = MaterialStateScript.new()
	var station_knowledge = RecipeKnowledgeStateScript.new()
	station_knowledge.configure("player:p04-station-receipts", {
		"p04_reverse": {"knowledge_source":"reverse_engineer", "reverse_engineer_component":"thruster_nozzle", "reverse_engineer_count":1},
	})
	var station_a = CraftingStationScript.new()
	var station_a_events: Array = []
	station_a.salvage_completed.connect(func(item_id: String, produced: Dictionary) -> void:
		station_a_events.append({"item_id":item_id, "produced":produced.duplicate(true)}))
	station_a.reverse_engineered.connect(func(component_id: String, receipt_id: String) -> void:
		station_knowledge.receive_reverse_engineer(component_id, receipt_id))
	station_a.configure("salvage", crafting, materials, station_inventory, DeconstructionResolverScript.new(), null, Vector3.ZERO, 0.0, station_knowledge)
	assert(station_a.try_salvage_target("deconstruct_thruster"), "real station commits first deconstruction")
	assert(station_inventory.get_quantity("thruster_nozzle") == 0 and station_inventory.get_quantity("titanium_ingot") == 1 and station_a_events.size() == 1, "station deposits and emits exactly once")
	assert(station_knowledge.is_known("p04_reverse") and (station_knowledge.get_summary().event_receipt_ids as Array).size() == 1, "committed station salvage emits one durable reverse receipt")
	assert(not station_a.try_salvage_target("deconstruct_thruster") and station_a_events.size() == 1 and (station_knowledge.get_summary().event_receipt_ids as Array).size() == 1, "rejected replay emits neither completion nor receipt")
	var station_reloaded = InventoryStateScript.new("player:p04-station-salvage")
	assert(station_reloaded.apply_summary(JSON.parse_string(JSON.stringify(station_inventory.get_summary())) as Dictionary), "station salvage inventory reloads")
	assert(station_reloaded.add_lot({"lot_id":"thruster-source-b", "item_id":"thruster_nozzle", "quantity":1, "quality_score":0.20, "quality_tier":"poor", "condition":0.51, "origin":{"wreck":"b"}}) == 1)
	var station_b = CraftingStationScript.new()
	var station_b_events: Array = []
	station_b.salvage_completed.connect(func(item_id: String, produced: Dictionary) -> void:
		station_b_events.append({"item_id":item_id, "produced":produced.duplicate(true)}))
	station_b.reverse_engineered.connect(func(component_id: String, receipt_id: String) -> void:
		station_knowledge.receive_reverse_engineer(component_id, receipt_id))
	station_b.configure("salvage", CraftingStateScript.new(), MaterialStateScript.new(), station_reloaded, DeconstructionResolverScript.new(), null, Vector3.ZERO, 0.0, station_knowledge)
	assert(station_b.try_salvage_target("deconstruct_thruster"), "fresh station and resolver commit second deconstruction")
	assert(station_reloaded.get_quantity("thruster_nozzle") == 0 and station_reloaded.get_quantity("titanium_ingot") == 2 and station_b_events.size() == 1 and (station_knowledge.get_summary().event_receipt_ids as Array).size() == 2, "fresh station conserves quantities and emits one distinct receipt")
	var station_sources: Dictionary = {}
	var station_qualities: Dictionary = {}
	for raw_station_lot in (station_reloaded.get_lot_summary().get("lots", []) as Array):
		var station_lot: Dictionary = raw_station_lot as Dictionary
		if str(station_lot.get("item_id", "")) != "titanium_ingot":
			continue
		var station_origin: Dictionary = station_lot.get("origin", {}) as Dictionary
		var station_source_id: String = str(station_origin.get("source_lot_id", ""))
		station_sources[station_source_id] = str(station_lot.get("lot_id", ""))
		station_qualities[station_source_id] = float(station_lot.get("quality_score", -1.0))
	assert(station_sources.has("thruster-source-a") and station_sources.has("thruster-source-b") and station_sources["thruster-source-a"] != station_sources["thruster-source-b"], "station output IDs derive from distinct consumed sources")
	assert(is_equal_approx(float(station_qualities.get("thruster-source-a", -1.0)), 0.656) and is_equal_approx(float(station_qualities.get("thruster-source-b", -1.0)), 0.16), "station outputs preserve distinct selected source qualities")
	assert(is_equal_approx(float(station_a_events[0].produced.get("quality", -1.0)), 0.656) and is_equal_approx(float(station_b_events[0].produced.get("quality", -1.0)), 0.16), "completion events report exact committed output qualities")
	var full_station_inventory = InventoryStateScript.new("player:p04-station-full")
	assert(full_station_inventory.add_lot({"lot_id":"thruster-full-source", "item_id":"thruster_nozzle", "quantity":1, "quality_score":0.82, "quality_tier":"excellent", "condition":0.37, "origin":{"wreck":"full"}}) == 1)
	var titanium_cap: int = int(full_station_inventory.get_definition("titanium_ingot").get("max_stack", 99))
	assert(full_station_inventory.add_item("titanium_ingot", titanium_cap) == titanium_cap)
	var full_station_before: Dictionary = full_station_inventory.get_summary()
	var full_station = CraftingStationScript.new()
	var full_station_events: Array = []
	full_station.salvage_completed.connect(func(item_id: String, produced: Dictionary) -> void:
		full_station_events.append({"item_id":item_id, "produced":produced.duplicate(true)}))
	full_station.configure("salvage", CraftingStateScript.new(), MaterialStateScript.new(), full_station_inventory, DeconstructionResolverScript.new(), null, Vector3.ZERO, 0.0, station_knowledge)
	var receipts_before_full: int = (station_knowledge.get_summary().event_receipt_ids as Array).size()
	assert(not full_station.try_salvage_target("deconstruct_thruster"), "full station output capacity rejects")
	assert(full_station_inventory.get_summary() == full_station_before and full_station_events.is_empty() and (station_knowledge.get_summary().event_receipt_ids as Array).size() == receipts_before_full, "rejected station deconstruction preserves source and emits no receipt")
	station_a.free()
	station_b.free()
	full_station.free()
	floor_player.free()
	if is_instance_valid(floor):
		floor.free()
	crate_a.free()
	crate_b.free()
	blocked.free()
	loot_player.free()
	print("P04 detail lots=true rollback=true intermediate_save=true equipment=true route=true resolver_recreation=true station_salvage=true")
	print("FC P04 PASS")
	quit()
