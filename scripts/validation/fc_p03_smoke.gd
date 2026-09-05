extends SceneTree

const ItemLotLedgerScript := preload("res://scripts/systems/item_lot_ledger.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

func _initialize() -> void:
	if not _test_exact_lots_and_atomic_selection():
		return
	if not _test_compatibility_removal_order():
		return
	if not _test_round_trip_and_migration():
		return
	if not _test_inventory_compatibility_view():
		return
	if not _test_holder_namespaces():
		return
	print("FC P03 DETAIL lots=true aggregate_cap=true atomic_take=true migration=true inventory_compat=true")
	print("FC P03 PASS")
	quit(0)

func _test_exact_lots_and_atomic_selection() -> bool:
	# A fixture-specific definition proves lot splitting does not multiply the
	# aggregate stack ceiling. The live scrap_metal ceiling remains unchanged.
	var ledger = ItemLotLedgerScript.new({"scrap_metal": {"max_stack": 99}}, "fixture:exact")
	var poor_origin: Dictionary = {"ship_id": "wreck-7", "salvage": {"room": "aft"}}
	if ledger.add_lot({
		"lot_id": "a", "item_id": "scrap_metal", "quantity": 2,
		"quality_score": 0.2, "quality_tier": "poor", "condition": 1.0,
		"origin": poor_origin,
	}) != 2:
		return _fail("first quality lot was not accepted")
	if ledger.add_lot({
		"lot_id": "b", "item_id": "scrap_metal", "quantity": 3,
		"quality_score": 0.8, "quality_tier": "excellent", "condition": 0.75,
		"origin": {"job_id": "job-3"},
	}) != 3:
		return _fail("second quality lot was not accepted")
	poor_origin["ship_id"] = "mutated-outside"
	if ledger.get_quantity("scrap_metal") != 5:
		return _fail("aggregate quantity should be five")

	# Explicit selection is a hard constraint and take is all-or-none.
	if not ledger.take_lots("scrap_metal", 4, PackedStringArray(["b"])).is_empty():
		return _fail("preferred lot shortage must not fall back or partially remove")
	if ledger.get_quantity("scrap_metal") != 5:
		return _fail("failed atomic take changed quantity")
	var taken: Array = ledger.take_lots("scrap_metal", 1, PackedStringArray(["b"]))
	if taken.size() != 1:
		return _fail("explicit take should return one split")
	var picked: Dictionary = taken[0]
	if str(picked.get("lot_id", "")) != "fixture:exact/split-000001" or int(picked.get("quantity", 0)) != 1:
		return _fail("outgoing split identity is not deterministic")
	if absf(float(picked.get("quality_score", -1.0)) - 0.8) > 0.0001 \
			or absf(float(picked.get("condition", -1.0)) - 0.75) > 0.0001 \
			or picked.get("origin", {}) != {"job_id": "job-3"}:
		return _fail("split did not preserve exact metadata")
	if ledger.get_quantity("scrap_metal") != 4:
		return _fail("split take aggregate mismatch")
	var remaining: Array = (ledger.get_summary().get("lots", []) as Array)
	if remaining.size() != 2:
		return _fail("partial take should leave two source lots")
	if str((remaining[1] as Dictionary).get("lot_id", "")) != "b" \
			or int((remaining[1] as Dictionary).get("quantity", 0)) != 2:
		return _fail("partial take did not keep the source holder lot identity")
	if (remaining[0] as Dictionary).get("origin", {}).get("ship_id", "") != "wreck-7":
		return _fail("ledger retained a caller-owned origin reference")
	var before_over_cap_add: Dictionary = ledger.get_summary()
	if ledger.add_lot({
		"lot_id": "overflow", "item_id": "scrap_metal", "quantity": 96,
		"quality_score": 0.5, "quality_tier": "standard", "condition": 1.0,
		"origin": {},
	}) != 0 or ledger.get_summary() != before_over_cap_add:
		return _fail("metadata-aware over-cap deposit must reject atomically")
	if ledger.add_lot({
		"lot_id": "fits", "item_id": "scrap_metal", "quantity": 95,
		"quality_score": 0.5, "quality_tier": "standard", "condition": 1.0,
		"origin": {},
	}) != 95:
		return _fail("metadata-aware deposit fitting aggregate cap was rejected")
	if ledger.get_quantity("scrap_metal") != 99:
		return _fail("quality lots multiplied aggregate stack cap")
	var full_sequence: int = int(ledger.get_summary().get("sequence", -1))
	if ledger.add_standard("scrap_metal", 1) != 0 \
			or int(ledger.get_summary().get("sequence", -1)) != full_sequence:
		return _fail("rejected full-stack deposit consumed a lot identity")
	var legacy_partial = ItemLotLedgerScript.new({"part": {"max_stack": 5}}, "fixture:partial")
	if legacy_partial.add_standard("part", 4) != 4 \
			or legacy_partial.add_standard("part", 3) != 1 \
			or legacy_partial.get_quantity("part") != 5:
		return _fail("legacy aggregate add did not preserve partial acceptance")
	return true

func _test_compatibility_removal_order() -> bool:
	var ledger = ItemLotLedgerScript.new({"part": {"max_stack": 99}}, "fixture:removal")
	for lot: Dictionary in [
		{"lot_id": "z-excellent", "item_id": "part", "quantity": 2, "quality_score": 0.8, "quality_tier": "excellent", "condition": 1.0, "origin": {}},
		{"lot_id": "m-standard", "item_id": "part", "quantity": 1, "quality_score": 0.5, "quality_tier": "standard", "condition": 1.0, "origin": {}},
		{"lot_id": "a-poor", "item_id": "part", "quantity": 2, "quality_score": 0.2, "quality_tier": "poor", "condition": 1.0, "origin": {}},
	]:
		if ledger.add_lot(lot) != int(lot.quantity):
			return _fail("removal-order fixture rejected lot")
	var removed: Array = ledger.take_lots("part", 2)
	if removed.size() != 2 \
			or str((removed[0] as Dictionary).lot_id) != "m-standard" \
			or str((removed[1] as Dictionary).lot_id) != "fixture:removal/split-000001":
		return _fail("legacy removal must choose standard quality then stable lot ID")
	return true

func _test_round_trip_and_migration() -> bool:
	var source = ItemLotLedgerScript.new({"wire": {"max_stack": 99}}, "fixture:roundtrip")
	source.add_lot({
		"lot_id": "wire-origin", "item_id": "wire", "quantity": 3,
		"quality_score": 0.61, "quality_tier": "good", "condition": 0.42,
		"origin": {"ship_id": "ship-2", "nested": {"receipt": "r-9"}},
	})
	var exact_summary: Dictionary = source.get_summary()
	var restored = ItemLotLedgerScript.new({"wire": {"max_stack": 99}})
	if not restored.apply_summary(exact_summary) or restored.get_summary() != exact_summary:
		return _fail("valid lot summary did not round-trip exactly")
	var before_future: Dictionary = restored.get_summary()
	if restored.apply_summary({"schema": "item-lots-2", "holder_namespace": "fixture:roundtrip", "sequence": 0, "lots": []}) \
			or restored.get_summary() != before_future:
		return _fail("unsupported future lot schema was not rejected atomically")

	# Valid duplicate IDs are repaired deterministically without stealing literal
	# suffixes already present elsewhere in the current payload.
	var duplicates: Dictionary = {
		"schema": "item-lots-1", "holder_namespace": "fixture:duplicate", "sequence": 0,
		"lots": [
			{"lot_id": "dup", "item_id": "wire", "quantity": 2, "quality_score": 0.2, "quality_tier": "poor", "condition": 0.9, "origin": {"source": "one"}},
			{"lot_id": "dup", "item_id": "wire", "quantity": 3, "quality_score": 0.8, "quality_tier": "excellent", "condition": 0.7, "origin": {"source": "two"}},
			{"lot_id": "dup#2", "item_id": "wire", "quantity": 1, "quality_score": 0.5, "quality_tier": "standard", "condition": 1.0, "origin": {"source": "literal"}},
		],
	}
	var migrated_a = ItemLotLedgerScript.new({"wire": {"max_stack": 99}})
	var migrated_b = ItemLotLedgerScript.new({"wire": {"max_stack": 99}})
	if not migrated_a.apply_summary(duplicates) or not migrated_b.apply_summary(duplicates):
		return _fail("valid duplicate summary should migrate")
	if migrated_a.get_summary() != migrated_b.get_summary():
		return _fail("duplicate migration was not deterministic")
	var migrated_lots: Array = migrated_a.get_summary().get("lots", [])
	if migrated_a.get_quantity("wire") != 6 or migrated_lots.size() != 3:
		return _fail("duplicate migration changed valid quantity")
	if str((migrated_lots[0] as Dictionary).lot_id) != "dup" \
			or str((migrated_lots[1] as Dictionary).lot_id) != "dup#3" \
			or (migrated_lots[1] as Dictionary).origin != {"source": "two"} \
			or str((migrated_lots[2] as Dictionary).lot_id) != "dup#2":
		return _fail("duplicate repair changed identity order or metadata")
	if migrated_a.add_standard("wire", 1) != 1 \
			or str((migrated_a.get_summary().lots as Array)[3].lot_id) != "fixture:duplicate/lot-000001":
		return _fail("post-migration generated identity was not deterministic")

	# Current-format envelopes and every current row are strict. One bad row must
	# reject the complete load and retain the prior state byte-for-byte.
	var before_bad_current: Dictionary = migrated_b.get_summary()
	var valid_plus_bad: Dictionary = duplicates.duplicate(true)
	(valid_plus_bad.lots as Array).append({"lot_id": "bad", "item_id": "wire",
		"quantity": -1, "quality_score": 0.5, "quality_tier": "standard",
		"condition": 1.0, "origin": {}})
	if migrated_b.apply_summary(valid_plus_bad) or migrated_b.get_summary() != before_bad_current:
		return _fail("valid plus malformed current rows did not reject atomically")
	if migrated_b.apply_summary({"schema": "item-lots-1", "holder_namespace": "fixture:duplicate", "sequence": -1, "lots": []}) \
			or migrated_b.get_summary() != before_bad_current:
		return _fail("malformed current envelope did not reject atomically")

	# Aggregate cap overflow is an explicit atomic rejection. The prior state
	# survives unchanged, so callers can surface the rejected load.
	var before_overflow: Dictionary = migrated_b.get_summary()
	if migrated_b.apply_summary({
		"schema": "item-lots-1", "holder_namespace": "fixture:duplicate", "sequence": 99,
		"lots": [{"lot_id": "too-many", "item_id": "wire", "quantity": 100,
			"quality_score": 0.5, "quality_tier": "standard", "condition": 1.0, "origin": {}}],
	}):
		return _fail("cap-overflow lot summary should be rejected")
	if migrated_b.get_summary() != before_overflow:
		return _fail("rejected cap-overflow summary partially reset the ledger")

	# A split sequence survives round-trip even after the outgoing lot has left,
	# preventing a later split from reusing an already-issued identity.
	var split_source = ItemLotLedgerScript.new({"wire": {"max_stack": 99}}, "fixture:split")
	split_source.add_lot({"lot_id": "stable", "item_id": "wire", "quantity": 4,
		"quality_score": 0.5, "quality_tier": "standard", "condition": 1.0, "origin": {}})
	var first_split: Array = split_source.take_lots("wire", 1, PackedStringArray(["stable"]))
	var split_restored = ItemLotLedgerScript.new({"wire": {"max_stack": 99}})
	if str((first_split[0] as Dictionary).lot_id) != "fixture:split/split-000001" \
			or not split_restored.apply_summary(split_source.get_summary()):
		return _fail("first split or split round-trip failed")
	var second_split: Array = split_restored.take_lots("wire", 1, PackedStringArray(["stable"]))
	if str((second_split[0] as Dictionary).lot_id) != "fixture:split/split-000002":
		return _fail("split identity sequence was reused after reload")

	# Aggregate-only saves become full-condition lots. A legacy material-quality
	# summary supplies a better score/tier without inventing provenance.
	var legacy = ItemLotLedgerScript.new({"scrap_metal": {"max_stack": 99}, "wire": {"max_stack": 99}})
	if not legacy.apply_summary({
		"items": {"wire": 2, "scrap_metal": 3, "negative": -1, "bad": "nope"},
		"material_quality": {"scrap_metal": 0.8},
	}, "fixture:legacy"):
		return _fail("legacy aggregate summary should migrate")
	var legacy_lots: Array = legacy.get_summary().get("lots", [])
	if legacy.get_quantity("scrap_metal") != 3 or legacy.get_quantity("wire") != 2 \
			or legacy.get_quantity("negative") != 0 or legacy.get_quantity("bad") != 0:
		return _fail("legacy malformed quantities were not normalized")
	if str((legacy_lots[0] as Dictionary).item_id) != "scrap_metal" \
			or str((legacy_lots[0] as Dictionary).lot_id) != "fixture:legacy/legacy:scrap_metal" \
			or absf(float((legacy_lots[0] as Dictionary).quality_score) - 0.8) > 0.0001 \
			or str((legacy_lots[0] as Dictionary).quality_tier) != "excellent" \
			or float((legacy_lots[0] as Dictionary).condition) != 1.0 \
			or not ((legacy_lots[0] as Dictionary).origin as Dictionary).is_empty():
		return _fail("material-aware legacy migration metadata mismatch")
	if str((legacy_lots[1] as Dictionary).quality_tier) != "standard" \
			or absf(float((legacy_lots[1] as Dictionary).quality_score) - 0.5) > 0.0001:
		return _fail("quantity-only legacy item did not become standard quality")
	return true

func _test_inventory_compatibility_view() -> bool:
	var inventory = InventoryStateScript.new("fixture:player")
	if inventory.add_lot({
		"lot_id": "poor", "item_id": "scrap_metal", "quantity": 2,
		"quality_score": 0.2, "quality_tier": "poor", "condition": 1.0, "origin": {},
	}) != 2:
		return _fail("InventoryState.add_lot failed")
	if inventory.add_item("scrap_metal", 3) != 3 or inventory.get_quantity("scrap_metal") != 5:
		return _fail("legacy add_item did not synchronize the ledger")
	var view: Dictionary = inventory.items
	view["scrap_metal"] = 99
	if inventory.get_quantity("scrap_metal") != 5:
		return _fail("external aggregate view mutation corrupted ledger authority")
	var summary: Dictionary = inventory.get_summary()
	if int((summary.get("items", {}) as Dictionary).get("scrap_metal", 0)) != 5 \
			or not summary.has("item_lots_v1"):
		return _fail("inventory summary views are not synchronized")
	var before_corrupt_envelope: Dictionary = inventory.get_summary()
	if inventory.apply_summary({"items": {"scrap_metal": 5}, "item_lots_v1": "corrupt"}) \
			or inventory.get_summary() != before_corrupt_envelope:
		return _fail("present malformed lot envelope downgraded to legacy inventory")
	for invalid_lot: Dictionary in [
		{"lot_id": "unknown-tier", "item_id": "scrap_metal", "quantity": 1,
			"quality_score": 0.5, "quality_tier": "legendary", "condition": 1.0, "origin": {}},
		{"lot_id": "contradictory", "item_id": "scrap_metal", "quantity": 1,
			"quality_score": 0.1, "quality_tier": "masterwork", "condition": 1.0, "origin": {}},
	]:
		if inventory.add_lot(invalid_lot) != 0 or inventory.get_summary() != before_corrupt_envelope:
			return _fail("invalid quality tier/score metadata changed inventory")
	var inconsistent: Dictionary = summary.duplicate(true)
	(inconsistent["items"] as Dictionary)["scrap_metal"] = 4
	var rejected = InventoryStateScript.new()
	if rejected.apply_summary(inconsistent):
		return _fail("inconsistent aggregate and lot dual state was accepted")
	if rejected.get_quantity("scrap_metal") != 0:
		return _fail("rejected summary partially mutated inventory")
	var restored = InventoryStateScript.new()
	if not restored.apply_summary(summary) or restored.get_summary().get("item_lots_v1", {}) != summary.item_lots_v1:
		return _fail("inventory lot summary did not round-trip")
	if restored.remove_item("scrap_metal", 3) != 3 or restored.get_quantity("scrap_metal") != 2:
		return _fail("legacy remove_item did not consume standard quality first")
	if absf(restored.get_total_weight() - 10.0) > 0.0001 or not restored.can_accept("scrap_metal", 18):
		return _fail("weight/stack compatibility changed")
	return true

func _test_holder_namespaces() -> bool:
	var defs: Dictionary = {"wire": {"max_stack": 99}}
	var anonymous_a = ItemLotLedgerScript.new(defs)
	var anonymous_b = ItemLotLedgerScript.new(defs)
	if anonymous_a.get_holder_namespace().is_empty() \
			or anonymous_b.get_holder_namespace().is_empty() \
			or anonymous_a.get_holder_namespace() == anonymous_b.get_holder_namespace():
		return _fail("independent anonymous ledgers did not receive unique namespaces")
	anonymous_a.add_standard("wire", 1)
	anonymous_b.add_standard("wire", 1)
	var anonymous_a_id: String = str((anonymous_a.get_summary().lots as Array)[0].lot_id)
	var anonymous_b_id: String = str((anonymous_b.get_summary().lots as Array)[0].lot_id)
	if anonymous_a_id == anonymous_b_id:
		return _fail("same-counter anonymous ledgers generated colliding lot IDs")

	var explicit = ItemLotLedgerScript.new(defs, "holder:ship-7:cargo")
	if explicit.add_standard("wire", 1) != 1 \
			or str((explicit.get_summary().lots as Array)[0].lot_id) != "holder:ship-7:cargo/lot-000001":
		return _fail("explicit namespace did not deterministically scope generated ID")
	var explicit_summary: Dictionary = explicit.get_summary()
	var bound_before_mismatch: Dictionary = explicit.get_summary()
	var mismatched_summary: Dictionary = explicit_summary.duplicate(true)
	mismatched_summary.holder_namespace = "holder:foreign"
	if explicit.apply_summary(mismatched_summary) or explicit.get_summary() != bound_before_mismatch:
		return _fail("bound ledger accepted a mismatched modern holder namespace")
	var reloaded = ItemLotLedgerScript.new(defs)
	if not reloaded.apply_summary(explicit_summary) \
			or reloaded.get_holder_namespace() != "holder:ship-7:cargo" \
			or reloaded.add_standard("wire", 1) != 1 \
			or str((reloaded.get_summary().lots as Array)[1].lot_id) != "holder:ship-7:cargo/lot-000002":
		return _fail("persisted namespace/sequence did not survive reload")
	reloaded.clear()
	if reloaded.get_holder_namespace() != "holder:ship-7:cargo" \
			or reloaded.add_standard("wire", 1) != 1 \
			or str((reloaded.get_summary().lots as Array)[0].lot_id) != "holder:ship-7:cargo/lot-000003":
		return _fail("clear reused holder namespace sequence")

	var legacy_a = ItemLotLedgerScript.new(defs)
	var legacy_b = ItemLotLedgerScript.new(defs)
	if not legacy_a.apply_summary({"items": {"wire": 1}}, "holder:cart-a") \
			or not legacy_b.apply_summary({"items": {"wire": 1}}, "holder:cart-b"):
		return _fail("explicit legacy source namespace was not accepted")
	var legacy_a_id: String = str((legacy_a.get_summary().lots as Array)[0].lot_id)
	var legacy_b_id: String = str((legacy_b.get_summary().lots as Array)[0].lot_id)
	if legacy_a_id != "holder:cart-a/legacy:wire" \
			or legacy_b_id != "holder:cart-b/legacy:wire" or legacy_a_id == legacy_b_id:
		return _fail("same-item legacy holders received colliding/non-deterministic IDs")

	var overflow = ItemLotLedgerScript.new(defs)
	var overflow_before: Dictionary = overflow.get_summary()
	if overflow.apply_summary({"items": {"wire": 100}}, "holder:overflow") \
			or overflow.get_summary() != overflow_before:
		return _fail("rejected legacy overflow changed holder namespace/state")

	# A stable parent can move between holders after an earlier split leaves it.
	# New split identities use the current issuing holder namespace, so another
	# holder can never recreate the former holder's globally issued identity.
	var moving = ItemLotLedgerScript.new(defs, "holder:source")
	moving.add_lot({"lot_id": "stable-parent", "item_id": "wire", "quantity": 3,
		"quality_score": 0.5, "quality_tier": "standard", "condition": 1.0, "origin": {}})
	var issued_at_source: Array = moving.take_lots("wire", 1, PackedStringArray(["stable-parent"]))
	var remainder: Array = moving.take_lots("wire", 2, PackedStringArray(["stable-parent"]))
	var destination = ItemLotLedgerScript.new(defs, "holder:destination")
	if destination.add_lot(remainder[0] as Dictionary) != 2:
		return _fail("whole remainder transfer setup failed")
	var destination_reloaded = ItemLotLedgerScript.new(defs)
	if not destination_reloaded.apply_summary(destination.get_summary()) \
			or str((destination_reloaded.get_summary().lots as Array)[0].lot_id) != "stable-parent":
		return _fail("destination rejected/re-IDed a foreign-native lot during restore")
	var issued_at_destination: Array = destination_reloaded.take_lots("wire", 1, PackedStringArray(["stable-parent"]))
	if str((issued_at_source[0] as Dictionary).lot_id) != "holder:source/split-000001" \
			or str((issued_at_destination[0] as Dictionary).lot_id) != "holder:destination/split-000001":
		return _fail("moved parent recreated a split identity from its former holder")

	var bound_inventory = InventoryStateScript.new("holder:player")
	bound_inventory.add_item("scrap_metal", 1)
	var inventory_before_mismatch: Dictionary = bound_inventory.get_summary()
	var foreign_inventory_summary: Dictionary = inventory_before_mismatch.duplicate(true)
	(foreign_inventory_summary.item_lots_v1 as Dictionary).holder_namespace = "holder:foreign"
	if bound_inventory.apply_summary(foreign_inventory_summary) \
			or bound_inventory.get_summary() != inventory_before_mismatch:
		return _fail("bound InventoryState accepted/mutated on modern namespace mismatch")
	var used_anonymous_inventory = InventoryStateScript.new()
	used_anonymous_inventory.add_item("scrap_metal", 1)
	var used_anonymous_before: Dictionary = used_anonymous_inventory.get_summary()
	var anonymous_foreign: Dictionary = used_anonymous_before.duplicate(true)
	(anonymous_foreign.item_lots_v1 as Dictionary).holder_namespace = "holder:foreign"
	if used_anonymous_inventory.apply_summary(anonymous_foreign) \
			or used_anonymous_inventory.get_summary() != used_anonymous_before:
		return _fail("used anonymous InventoryState changed its permanent namespace")
	return true

func _fail(reason: String) -> bool:
	push_error("FC P03 FAIL reason=%s" % reason)
	quit(1)
	return false
