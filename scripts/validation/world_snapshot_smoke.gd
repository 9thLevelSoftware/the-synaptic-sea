extends SceneTree

## Unit smoke for WorldSnapshot: round-trip + version-mismatch rejection.

const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const SaveMigrationServiceScript := preload("res://scripts/systems/save_migration_service.gd")
const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")

func _initialize() -> void:
	var godot_version: String = Engine.get_version_info()["string"]

	var base_dict: Dictionary = _base_world_dict(godot_version)
	var ws = WorldSnapshotScript.from_dict(
		base_dict, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	if ws == null:
		_fail("current baseline fixture did not decode")
		return
	ws.world_summary = {"world_seed": 99, "player_position": [1.0, 0.0, 2.0], "generated_marker_ids": ["3:1:0"]}
	ws.current_location = ""
	ws.player_position_in_ship = [10.0, 2.0, 3.0]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = godot_version
	ws.saved_at = "2026-06-21T00:00:00"

	var dict: Dictionary = ws.to_dict()
	var rebuilt = WorldSnapshotScript.from_dict(dict, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	if rebuilt == null:
		_fail("from_dict returned null on a valid dict")
		return
	if int(rebuilt.world_summary.get("world_seed", -1)) != 99:
		_fail("world_summary not restored")
		return
	if String(rebuilt.current_location) != "":
		_fail("current_location not restored")
		return
	if not rebuilt.visited_ships.has("marker-away"):
		_fail("visited_ships key not restored")
		return
	if String(rebuilt.home_ship.get("slice_version", "")) != "gate2-current-run-6":
		_fail("home_ship dict not restored")
		return
	if rebuilt.player_position_in_ship.size() != 3 or float(rebuilt.player_position_in_ship[0]) != 10.0:
		_fail("player_position_in_ship not restored")
		return

	# Version mismatch → null.
	if WorldSnapshotScript.from_dict(dict, "world-999", godot_version) != null:
		_fail("from_dict should reject mismatched world version")
		return
	if WorldSnapshotScript.from_dict(dict, WorldSnapshotScript.WORLD_SLICE_VERSION, "0.0.0") != null:
		_fail("from_dict should reject mismatched godot version")
		return
	# Non-dict / empty → null.
	if WorldSnapshotScript.from_dict(null, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version) != null:
		_fail("from_dict should reject null")
		return
	if WorldSnapshotScript.from_dict({}, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version) != null:
		_fail("from_dict should reject empty dict")
		return

	# --- home_ship_inventory round-trip (sub-project #6, additive, no version bump) ---
	var ws_cargo = WorldSnapshotScript.from_dict(
		base_dict.duplicate(true), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	ws_cargo.home_ship_inventory = {"items": {"scrap_metal": 5}, "max_weight": 500.0}
	var rt = WorldSnapshotScript.from_dict(ws_cargo.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt != null, "home-cargo snapshot round-trips")
	assert(int(rt.home_ship_inventory.get("items", {}).get("scrap_metal", 0)) == 5, "home_ship_inventory survived round-trip")

	# --- player_equipment round-trip (slice 2, additive, no version bump) ---
	var ws_eq = WorldSnapshotScript.from_dict(
		base_dict.duplicate(true), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	ws_eq.player_equipment = {"slots": {"back": "eva_backpack", "suit": "hardsuit"}}
	var rt_eq = WorldSnapshotScript.from_dict(ws_eq.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_eq != null, "equipment snapshot round-trips")
	assert(str(rt_eq.player_equipment.get("slots", {}).get("back", "")) == "eva_backpack", "player_equipment survived round-trip")

	# --- home_ship_carts round-trip (slice 2, additive, no version bump) ---
	var ws_hc = WorldSnapshotScript.from_dict(
		base_dict.duplicate(true), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	ws_hc.home_ship_carts = [{"cart_id": "cart_home", "hold": {"items": {"scrap_metal": 4}, "max_weight": 200.0}}]
	var rt_hc = WorldSnapshotScript.from_dict(ws_hc.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_hc != null, "home_ship_carts snapshot round-trips")
	assert((rt_hc.home_ship_carts as Array).size() == 1, "home_ship_carts survived round-trip")
	assert(str(rt_hc.home_ship_carts[0].get("cart_id", "")) == "cart_home", "cart entry intact")

	# --- home breach environment round-trip (additive, no version bump) ---
	var ws_breach = WorldSnapshotScript.from_dict(
		base_dict.duplicate(true), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	ws_breach.home_breach_environment = {
		"hazard_kind": "oxygen", "breach_open": false, "breach_sealed": true,
		"breach_zone_ids": ["home_breach"],
	}
	var rt_breach = WorldSnapshotScript.from_dict(
		ws_breach.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_breach != null, "home breach environment snapshot round-trips")
	assert(bool(rt_breach.home_breach_environment.get("breach_sealed", false)),
		"home breach environment survived round-trip")

	# --- run_id round-trip (slot-ownership rework, additive, no version bump) ---
	var ws_rid = WorldSnapshotScript.from_dict(
		base_dict.duplicate(true), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	var rt_rid = WorldSnapshotScript.from_dict(ws_rid.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_rid != null, "run_id snapshot round-trips")
	assert(String(rt_rid.run_id) == "fixture-world", "run_id survived round-trip")
	# Older saves (field absent) must default to "", not null/error.
	var legacy_dict: Dictionary = ws_rid.to_dict()
	legacy_dict.erase("run_id")
	var rt_legacy = WorldSnapshotScript.from_dict(legacy_dict, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_legacy != null, "legacy dict without run_id still round-trips")
	assert(String(rt_legacy.run_id) == "", "run_id defaults to \"\" for older saves")

	# P04 additive floor holders keep world-4: absence is legacy-empty, while a
	# present malformed current payload fails closed instead of disappearing.
	var ws_floor = WorldSnapshotScript.from_dict(
		base_dict.duplicate(true), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	ws_floor.home_floor_drops_v1 = {
		"schema": "ship-floor-drops-1", "ship_id": "ship_start", "sequence": 0, "drops": [],
	}
	var rt_floor = WorldSnapshotScript.from_dict(
		ws_floor.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_floor != null and str(rt_floor.home_floor_drops_v1.ship_id) == "ship_start",
		"home floor-holder payload survives without an outer version change")
	var malformed_floor: Dictionary = ws_floor.to_dict()
	malformed_floor["home_floor_drops_v1"] = {}
	assert(WorldSnapshotScript.from_dict(
		malformed_floor, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version) == null,
		"present empty floor payload rejects")
	var absent_floor: Dictionary = ws_floor.to_dict()
	absent_floor.erase("home_floor_drops_v1")
	var rt_absent_floor = WorldSnapshotScript.from_dict(
		absent_floor, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_absent_floor != null and rt_absent_floor.home_floor_drops_v1.is_empty(),
		"absent floor payload migrates as legacy empty")

	print("WORLD SNAPSHOT PASS round_trip=true version_gated=true")
	call_deferred("_finish_success")


func _finish_success() -> void:
	quit(0)

func _fail(reason: String) -> void:
	push_error("WORLD SNAPSHOT FAIL reason=%s" % reason)
	quit(1)


func _base_world_dict(godot_version: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/feature_completion/p10_world_v5_transactional.json"))
	if not parsed is Dictionary:
		return {}
	var source: Dictionary = (parsed as Dictionary).duplicate(true)
	source["godot_version"] = godot_version
	source.home_ship["godot_version"] = godot_version
	var migrated: Dictionary = SaveMigrationServiceScript.new().migrate_world(source)
	if not migrated.get("dict", null) is Dictionary:
		return {}
	var result: Dictionary = (migrated.dict as Dictionary).duplicate(true)
	var manager = ThreatManagerScript.new()
	result.home_ship.inventory_summary["threat_summary"] = manager.get_summary()
	manager.free()
	return result
