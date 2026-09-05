extends SceneTree

## P04 holder restore contract: stable namespaces, atomic current/legacy
## equipment restore, and exact ship-owned floor-drop summaries.
## Marker: FC P04 HOLDER ATOMICITY PASS

const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const CartStateScript := preload("res://scripts/systems/cart_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ItemLotLedgerScript := preload("res://scripts/systems/item_lot_ledger.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	_test_inventory_namespace_atomicity()
	_test_cart_and_ship_holder_atomicity()
	_test_equipment_current_and_legacy_atomicity()
	_test_floor_drop_round_trip()
	_test_coordinator_preflight_rejects_corrupt_equipment()
	print("FC P04 HOLDER ATOMICITY PASS")
	quit(0)

func _test_inventory_namespace_atomicity() -> void:
	var source = ShipInventoryScript.create(100.0, "ship:source:cargo")
	assert(source.add_item("scrap_metal", 2) == 2)
	var source_summary: Dictionary = source.get_summary()
	var target = ShipInventoryScript.create(100.0, "ship:target:cargo")
	var before: Dictionary = target.get_summary()
	assert(not target.apply_summary(source_summary), "bound cargo rejects another holder namespace")
	assert(target.get_summary() == before, "rejected cargo restore is atomic")
	var explicit_anonymous = ShipInventoryScript.create(100.0, "anonymous:explicit-holder")
	assert(not explicit_anonymous.apply_summary(source_summary), "explicit empty anonymous holder remains bound")
	assert(explicit_anonymous.get_holder_namespace() == "anonymous:explicit-holder")
	var fresh_unnamed = ShipInventoryScript.create(100.0)
	assert(fresh_unnamed.apply_summary(source_summary), "only a pristine unnamed holder may adopt saved identity")
	var nan_summary: Dictionary = source_summary.duplicate(true)
	nan_summary["max_weight"] = NAN
	before = source.get_summary()
	assert(not source.apply_summary(nan_summary), "non-finite current capacity is rejected")
	assert(source.get_summary() == before)

func _test_cart_and_ship_holder_atomicity() -> void:
	var cart_a = CartStateScript.create("cart-a")
	assert(cart_a.get_hold().add_item("scrap_metal", 1) == 1)
	var cart_b = CartStateScript.create("cart-b")
	var before_cart: Dictionary = cart_b.get_summary()
	assert(not cart_b.apply_summary(cart_a.get_summary()), "cart identity cannot be rebound")
	assert(cart_b.get_summary() == before_cart)
	var ship_a = ShipInstanceScript.create("ship-a", "marker-a", null, null, null)
	assert(ship_a.get_inventory().add_item("scrap_metal", 1) == 1)
	var ship_b = ShipInstanceScript.create("ship-b", "marker-b", null, null, null)
	assert(ship_b.get_inventory().add_item("wiring_bundle", 1) == 1)
	var before_ship: Dictionary = ship_b.get_summary()
	var foreign_summary: Dictionary = ship_a.get_summary()
	foreign_summary["ship_id"] = "ship-b"
	foreign_summary["marker_id"] = "marker-b"
	assert(not ship_b.apply_summary(foreign_summary), "ship cargo namespace must match its ship owner")
	assert(ship_b.get_summary() == before_ship, "cross-holder ship restore changes nothing")

func _test_equipment_current_and_legacy_atomicity() -> void:
	var equipment = EquipmentStateScript.create()
	var valid: Dictionary = {
		"slots": {"back": "eva_backpack"},
		"slot_lots_v1": {"back": {
			"lot_id": "equipment:test:001",
			"item_id": "eva_backpack",
			"quantity": 1,
			"quality_score": 0.82,
			"quality_tier": "excellent",
			"condition": 0.43,
			"origin": {"source": "p04"},
		}},
	}
	assert(equipment.apply_summary(valid))
	var before: Dictionary = equipment.get_summary()
	var corrupt: Dictionary = valid.duplicate(true)
	corrupt.slot_lots_v1.back["quality_tier"] = "poor"
	assert(not equipment.apply_summary(corrupt), "tier/score mismatch rejects current equipment")
	assert(equipment.get_summary() == before, "corrupt current equipment is atomic")
	corrupt = valid.duplicate(true)
	corrupt.slot_lots_v1.clear()
	assert(not equipment.apply_summary(corrupt), "current equipment requires an exact lot per occupied slot")
	assert(equipment.get_summary() == before)
	assert(equipment.apply_summary({"slots": {"back": "eva_backpack"}}), "legacy scalar equipment migrates")
	var legacy_lot: Dictionary = equipment.slot_lots.back
	assert(str(legacy_lot.lot_id) == "equipment:legacy:back:eva_backpack")
	assert(float(legacy_lot.condition) == 1.0 and legacy_lot.origin.source == "legacy_equipment")

func _test_floor_drop_round_trip() -> void:
	var ship = ShipInstanceScript.create("ship-floor", "marker-floor", null, null, null)
	var drop_id: String = ship.allocate_floor_drop_id()
	var ledger = ItemLotLedgerScript.new({}, "floor:%s" % drop_id)
	assert(ledger.add_lot({
		"lot_id": "yield:nonstandard",
		"item_id": "scrap_metal",
		"quantity": 5,
		"quality_score": 0.82,
		"quality_tier": "excellent",
		"condition": 0.43,
		"origin": {"source": "partially_scooped_fixture"},
	}) == 5)
	assert(ledger.add_standard("ration_pack", 1) == 1, "exercise persisted ledger sequence")
	var local_transform := Transform3D(Basis.from_euler(Vector3(0.0, 0.37, 0.0)), Vector3(4.25, 0.4, -2.75))
	assert(ship.upsert_floor_drop_descriptor({
		"drop_id": drop_id,
		"ship_id": ship.ship_id,
		"transform": ShipInstanceScript.transform_to_summary(local_transform),
		"item_lots_v1": ledger.get_summary(),
	}))
	var restored = ShipInstanceScript.create("ship-floor", "marker-floor", null, null, null)
	assert(restored.apply_summary(ship.get_summary()))
	assert(restored.floor_drop_sequence == 1)
	var restored_drop: Dictionary = restored.floor_drop_descriptors[drop_id]
	assert((restored_drop.item_lots_v1 as Dictionary).sequence == 1)
	assert(ShipInstanceScript.transform_from_summary(restored_drop.transform).is_equal_approx(local_transform))
	var restored_lot: Dictionary = (restored_drop.item_lots_v1.lots as Array)[0]
	assert(float(restored_lot.quality_score) == 0.82 and float(restored_lot.condition) == 0.43)
	var corrupt: Dictionary = ship.get_summary()
	corrupt.floor_drops_v1.ship_id = "ship-other"
	var before: Dictionary = restored.get_summary()
	assert(not restored.apply_summary(corrupt), "cross-ship floor holder rejects")
	assert(restored.get_summary() == before)

func _test_coordinator_preflight_rejects_corrupt_equipment() -> void:
	var playable = PlayableGeneratedShipScript.new()
	var ws = WorldSnapshotScript.new()
	ws.home_ship_carts = []
	ws.player_equipment = {"slots": {"back": "eva_backpack"}, "slot_lots_v1": {}}
	assert(not bool(playable._prepare_world_holder_restore(ws).get("ok", true)))
	playable.free()
