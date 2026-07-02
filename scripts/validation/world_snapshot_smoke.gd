extends SceneTree

## Unit smoke for WorldSnapshot: round-trip + version-mismatch rejection.

const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

func _initialize() -> void:
	var godot_version: String = Engine.get_version_info()["string"]

	var ws = WorldSnapshotScript.new()
	ws.world_summary = {"world_seed": 99, "player_position": [1.0, 0.0, 2.0], "generated_marker_ids": ["3:1:0"]}
	ws.home_ship = {"slice_version": "gate2-current-run-1", "player_position": [5.0, 1.0, 5.0]}
	ws.visited_ships = {
		"3:1:0": {"ship_id": "ship_3:1:0", "marker_id": "3:1:0", "blueprint": {"size": 1, "condition": 2, "seed": 7}, "systems": {"k": "v"}},
	}
	ws.current_location = "3:1:0"
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
	if String(rebuilt.current_location) != "3:1:0":
		_fail("current_location not restored")
		return
	if not rebuilt.visited_ships.has("3:1:0"):
		_fail("visited_ships key not restored")
		return
	if String(rebuilt.home_ship.get("slice_version", "")) != "gate2-current-run-1":
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
	var ws_cargo = WorldSnapshotScript.new()
	ws_cargo.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws_cargo.godot_version = godot_version
	ws_cargo.home_ship_inventory = {"items": {"scrap_metal": 5}, "max_weight": 500.0}
	var rt = WorldSnapshotScript.from_dict(ws_cargo.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt != null, "home-cargo snapshot round-trips")
	assert(int(rt.home_ship_inventory.get("items", {}).get("scrap_metal", 0)) == 5, "home_ship_inventory survived round-trip")

	# --- player_equipment round-trip (slice 2, additive, no version bump) ---
	var ws_eq = WorldSnapshotScript.new()
	ws_eq.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws_eq.godot_version = godot_version
	ws_eq.player_equipment = {"slots": {"back": "eva_backpack", "suit": "hardsuit"}}
	var rt_eq = WorldSnapshotScript.from_dict(ws_eq.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_eq != null, "equipment snapshot round-trips")
	assert(str(rt_eq.player_equipment.get("slots", {}).get("back", "")) == "eva_backpack", "player_equipment survived round-trip")

	# --- home_ship_carts round-trip (slice 2, additive, no version bump) ---
	var ws_hc = WorldSnapshotScript.new()
	ws_hc.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws_hc.godot_version = godot_version
	ws_hc.home_ship_carts = [{"cart_id": "cart_home", "hold": {"items": {"scrap_metal": 4}, "max_weight": 200.0}}]
	var rt_hc = WorldSnapshotScript.from_dict(ws_hc.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_hc != null, "home_ship_carts snapshot round-trips")
	assert((rt_hc.home_ship_carts as Array).size() == 1, "home_ship_carts survived round-trip")
	assert(str(rt_hc.home_ship_carts[0].get("cart_id", "")) == "cart_home", "cart entry intact")

	# --- manual_slots_written round-trip (PR #57 Codex round 2 finding C,
	# additive, no version bump) ---
	var ws_msw = WorldSnapshotScript.new()
	ws_msw.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws_msw.godot_version = godot_version
	ws_msw.manual_slots_written = ["slot_01", "slot_03"]
	var rt_msw = WorldSnapshotScript.from_dict(ws_msw.to_dict(), WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_msw != null, "manual_slots_written snapshot round-trips")
	assert((rt_msw.manual_slots_written as Array).size() == 2, "manual_slots_written survived round-trip")
	assert((rt_msw.manual_slots_written as Array).has("slot_01"), "manual_slots_written contains slot_01")
	# Older saves (field absent) must default to an empty array, not null/error.
	var legacy_dict: Dictionary = ws_msw.to_dict()
	legacy_dict.erase("manual_slots_written")
	var rt_legacy = WorldSnapshotScript.from_dict(legacy_dict, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	assert(rt_legacy != null, "legacy dict without manual_slots_written still round-trips")
	assert((rt_legacy.manual_slots_written as Array).is_empty(), "manual_slots_written defaults to [] for older saves")

	print("WORLD SNAPSHOT PASS round_trip=true version_gated=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("WORLD SNAPSHOT FAIL reason=%s" % reason)
	quit(1)
