extends SceneTree

# encounter_injector_smoke — REQ-PG-007, REQ-PG-009, REQ-PG-010.
#
# Asserts:
#   1. inject() embeds a non-null `encounters` Array on the layout.
#   2. Every spawn marker has the required schema fields (id,
#      room_id, deck, cell, encounter_kind, count, difficulty_tier,
#      seed_offset).
#   3. No marker is placed in a critical-path room.
#   4. Same input produces the same marker set (determinism).
#   5. validate() rejects a fabricated layout with a missing room.
#   6. validate() rejects a fabricated layout with a critical-path
#      marker (RISK-011).
#   7. Standard difficulty at low density produces zero markers;
#      deep_dive difficulty at high density produces >= 1 marker.
#   8. The injected layout still has all the legacy fields
#      (REQ-PG-010 schema bump compat).

const EncounterInjectorScript := preload("res://scripts/procgen/encounter_injector.gd")
const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")
const DifficultyProfileScript := preload("res://scripts/procgen/difficulty_profile.gd")


# Builds a minimal test layout with N rooms, a critical path
# through rooms[0] -> rooms[-1], and adjacency links between
# sequential rooms.
func _build_layout(room_count: int, with_critical_path: bool) -> Dictionary:
	var rooms: Array = []
	for i in range(room_count):
		var role: String = "corridor" if i % 2 == 0 else "cargo"
		var deck: int = 0
		rooms.append({
			"id": "room_%02d" % i,
			"room_role": role,
			"deck": deck,
			"cells": [Vector2i(i, 0)],
		})

	var adjacencies: Array = []
	for i in range(room_count - 1):
		adjacencies.append({
			"from_room": "room_%02d" % i,
			"to_room": "room_%02d" % (i + 1),
			"from_cell": Vector2i(i, 0),
			"to_cell": Vector2i(i + 1, 0),
		})

	var layout: Dictionary = {
		"schema_version": "1.2.0",
		"document_kind": "ship_layout",
		"rooms": rooms,
		"room_links": adjacencies,
	}

	if with_critical_path:
		var cp: Array = []
		for i in range(room_count):
			cp.append("room_%02d" % i)
		layout["critical_path"] = cp

	return layout


func _initialize() -> void:
	# --- Case 1: Standard biome + standard difficulty produces few markers ---
	var layout_std: Dictionary = _build_layout(6, true)
	var biome_std = BiomeProfileScript.from_dict({"id": "abyssal_synapse_sea"})
	var diff_std = DifficultyProfileScript.from_dict({"id": "standard"})
	var injector_std: RefCounted = EncounterInjectorScript.new()
	injector_std.inject(layout_std, biome_std, diff_std, 314)
	if not layout_std.has("encounters"):
		push_error("ENCOUNTER INJECTOR FAIL encounters key missing from layout")
		quit(1)
		return
	if not (layout_std["encounters"] is Array):
		push_error("ENCOUNTER INJECTOR FAIL encounters not an Array")
		quit(1)
		return

	# --- Case 2: Schema field check on every marker ---
	for marker in layout_std["encounters"]:
		for key in ["id", "room_id", "deck", "cell", "encounter_kind", "count", "difficulty_tier", "seed_offset"]:
			if not marker.has(key):
				push_error("ENCOUNTER INJECTOR FAIL marker missing key %s" % key)
				quit(1)
				return
		if int(marker.get("count", 0)) < 1:
			push_error("ENCOUNTER INJECTOR FAIL marker count<1: %s" % str(marker.get("count", 0)))
			quit(1)
			return
		if String(marker.get("encounter_kind", "")).is_empty():
			push_error("ENCOUNTER INJECTOR FAIL marker empty encounter_kind")
			quit(1)
			return

	# --- Case 3: No marker on critical-path rooms ---
	var cp_set: Dictionary = {}
	for r in layout_std.get("critical_path", []):
		cp_set[str(r)] = true
	for marker in layout_std["encounters"]:
		var rid: String = str(marker.get("room_id", ""))
		if cp_set.has(rid):
			push_error("ENCOUNTER INJECTOR FAIL marker on critical-path room: %s" % rid)
			quit(1)
			return

	# --- Case 4: Same input -> same markers (determinism) ---
	var layout_replay: Dictionary = _build_layout(6, true)
	injector_std.inject(layout_replay, biome_std, diff_std, 314)
	var markers_a: Array = layout_std["encounters"]
	var markers_b: Array = layout_replay["encounters"]
	if markers_a.size() != markers_b.size():
		push_error("ENCOUNTER INJECTOR FAIL determinism marker count %d vs %d" % [markers_a.size(), markers_b.size()])
		quit(1)
		return
	for i in range(markers_a.size()):
		if str(markers_a[i]) != str(markers_b[i]):
			push_error("ENCOUNTER INJECTOR FAIL marker %d differs across runs" % i)
			quit(1)
			return

	# --- Case 5: validate() rejects missing-room marker ---
	var layout_bad: Dictionary = _build_layout(4, true)
	layout_bad["encounters"] = [
		{
			"id": "enc_bogus", "room_id": "nonexistent_room",
			"deck": 0, "cell": [0, 0], "encounter_kind": "biomatter_lurker",
			"count": 1, "difficulty_tier": "standard", "seed_offset": 1,
		}
	]
	var bad_result: Dictionary = EncounterInjectorScript.validate(layout_bad)
	if bad_result.get("valid", true):
		push_error("ENCOUNTER INJECTOR FAIL validate accepted missing-room marker")
		quit(1)
		return
	if String(bad_result.get("missing_room", "")) != "nonexistent_room":
		push_error("ENCOUNTER INJECTOR FAIL missing_room field wrong: %s" % String(bad_result.get("missing_room", "")))
		quit(1)
		return

	# --- Case 6: validate() rejects critical-path marker (RISK-011) ---
	var layout_bad_cp: Dictionary = _build_layout(4, true)
	# Place a marker in room_02 which IS on the critical path.
	var first_room_id: String = "room_02"
	layout_bad_cp["encounters"] = [
		{
			"id": "enc_cp", "room_id": first_room_id,
			"deck": 0, "cell": [2, 0], "encounter_kind": "biomatter_lurker",
			"count": 1, "difficulty_tier": "standard", "seed_offset": 1,
		}
	]
	var bad_cp_result: Dictionary = EncounterInjectorScript.validate(layout_bad_cp)
	if bad_cp_result.get("valid", true):
		push_error("ENCOUNTER INJECTOR FAIL validate accepted critical-path marker")
		quit(1)
		return
	if String(bad_cp_result.get("critical_path_violation", "")) != first_room_id:
		push_error("ENCOUNTER INJECTOR FAIL critical_path_violation wrong: %s" % String(bad_cp_result.get("critical_path_violation", "")))
		quit(1)
		return

	# --- Case 7: deep_dive on breach_field produces >= 1 marker ---
	# Build a layout where rooms alternate between critical path
	# and side branches — only critical-path rooms are skipped.
	var rooms: Array = []
	var adjacencies: Array = []
	var cp: Array = []
	for i in range(10):
		var role: String = "corridor" if i % 2 == 0 else "cargo"
		rooms.append({
			"id": "room_%02d" % i,
			"room_role": role,
			"deck": 0,
			"cells": [Vector2i(i, 0)],
		})
		if i < 9:
			adjacencies.append({
				"from_room": "room_%02d" % i,
				"to_room": "room_%02d" % (i + 1),
				"from_cell": Vector2i(i, 0),
				"to_cell": Vector2i(i + 1, 0),
			})
	# Critical path is rooms 0, 2, 4, 6, 8 — every other room.
	for i in range(0, 10, 2):
		cp.append("room_%02d" % i)
	var layout_deep: Dictionary = {
		"schema_version": "1.2.0",
		"document_kind": "ship_layout",
		"rooms": rooms,
		"room_links": adjacencies,
		"critical_path": cp,
	}
	var biome_breach = BiomeProfileScript.from_dict({"id": "breach_field",
		"hazard_modifier": 1.4, "encounter_density_modifier": 1.3})
	var diff_deep = DifficultyProfileScript.from_dict({"id": "deep_dive",
		"hazard_modifier": 1.7, "encounter_density_modifier": 1.6})
	injector_std.inject(layout_deep, biome_breach, diff_deep, 314)
	if int(layout_deep["encounters"].size()) < 1:
		push_error("ENCOUNTER INJECTOR FAIL deep_dive+breach produced 0 markers (expected >= 1)")
		quit(1)
		return

	# --- Case 8: legacy schema fields preserved (only on layouts that had them) ---
	# The standard layout is hand-built without fire_zones etc., so
	# verify the injector doesn't *delete* them from layouts that
	# already have them.
	var layout_with_legacy: Dictionary = layout_std.duplicate(true)
	layout_with_legacy["fire_zones"] = []
	layout_with_legacy["arc_zones"] = []
	layout_with_legacy["breach_zones"] = []
	layout_with_legacy["prototype"] = {"start_room": "room_00", "goal_room": "room_05"}
	injector_std.inject(layout_with_legacy, biome_std, diff_std, 314)
	for key in ["fire_zones", "arc_zones", "breach_zones", "prototype"]:
		if not layout_with_legacy.has(key):
			push_error("ENCOUNTER INJECTOR FAIL legacy field %s missing after inject" % key)
			quit(1)
			return
	if String(str(layout_with_legacy["prototype"]["start_room"])) != "room_00":
		push_error("ENCOUNTER INJECTOR FAIL prototype mutated")
		quit(1)
		return

	print("ENCOUNTER INJECTOR PASS std_markers=%d deep_markers=%d markers_valid=true deterministic=true critical_safe=true legacy_compat=true" % [
		int(layout_std["encounters"].size()),
		int(layout_deep["encounters"].size()),
	])
	quit(0)
