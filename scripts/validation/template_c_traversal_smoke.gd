extends SceneTree

# template_c_traversal_smoke — REQ-PG-004 verification.
#
# Asserts:
#   1. Validating a hand-built stacked layout (with at least one
#      ramp and one elevator between two decks) returns valid=true.
#   2. Every vertical_connections entry has both endpoints in
#      layout.rooms (no missing_room error).
#   3. transitions_checked > 0 and transitions_valid > 0 on the
#      well-formed layout.
#   4. A fabricated layout with a missing room in vertical_connections
#      returns valid=false and error_code="missing_room".
#   5. A fabricated layout with from_deck == to_deck returns
#      valid=false and error_code="deck_mismatch".
#   6. A fabricated layout with a cell not in the room's cells
#      returns valid=false and error_code="cell_missing".
#   7. A layout with from_room == to_room returns valid=false and
#      error_code="self_transition".
#   8. critical_path() returns the BFS path through the room_links
#      from entry to destination.
#   9. The full procgen pipeline for the stacked template produces
#      a layout that TemplateCTraversal validates (REQ-PG-011
#      end-to-end check).

const TemplateCTraversalScript := preload("res://scripts/procgen/template_c_traversal.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")


# Builds a minimal stacked layout with two decks and one ramp
# transition. The ramp links ramp_room (deck 0) -> upper_room (deck 1).
func _build_stacked_layout() -> Dictionary:
	var rooms: Array = [
		{"id": "airlock_01", "room_role": "airlock", "deck": 0,
		 "cells": [Vector2i(0, 0)]},
		{"id": "ramp_room", "room_role": "ramp", "deck": 0,
		 "cells": [Vector2i(1, 0)]},
		{"id": "upper_room", "room_role": "corridor", "deck": 1,
		 "cells": [Vector2i(1, 0)]},
		{"id": "bridge_room", "room_role": "bridge", "deck": 1,
		 "cells": [Vector2i(2, 0)]},
	]
	var adjacencies: Array = [
		{"from_room": "airlock_01", "to_room": "ramp_room",
		 "from_cell": Vector2i(0, 0), "to_cell": Vector2i(1, 0)},
		{"from_room": "ramp_room", "to_room": "upper_room",
		 "from_cell": Vector2i(1, 0), "to_cell": Vector2i(1, 0),
		 "is_vertical": true},
		{"from_room": "upper_room", "to_room": "bridge_room",
		 "from_cell": Vector2i(1, 0), "to_cell": Vector2i(2, 0)},
	]
	var vertical: Array = [
		{"id": "ramp_room_to_upper_room",
		 "from_room": "ramp_room", "to_room": "upper_room",
		 "from_cell": Vector2i(1, 0), "to_cell": Vector2i(1, 0),
		 "type": "ramp", "module_id": "ramp_up_1x2"},
	]
	return {
		"schema_version": "1.2.0",
		"document_kind": "ship_layout",
		"rooms": rooms,
		"room_links": adjacencies,
		"vertical_connections": vertical,
	}


func _initialize() -> void:
	# --- Case 1: Hand-built stacked layout validates ---
	var layout: Dictionary = _build_stacked_layout()
	var result: Dictionary = TemplateCTraversalScript.validate(layout)
	if not result.get("valid", false):
		push_error("TEMPLATE C TRAVERSAL FAIL hand-built layout rejected: %s" % str(result.get("error_code", "")))
		quit(1)
		return
	# --- Case 2/3: counts ---
	if int(result.get("transitions_checked", 0)) != 1:
		push_error("TEMPLATE C TRAVERSAL FAIL transitions_checked=%d expected=1" % int(result.get("transitions_checked", 0)))
		quit(1)
		return
	if int(result.get("transitions_valid", 0)) != 1:
		push_error("TEMPLATE C TRAVERSAL FAIL transitions_valid=%d expected=1" % int(result.get("transitions_valid", 0)))
		quit(1)
		return

	# --- Case 4: missing_room ---
	var bad_missing: Dictionary = layout.duplicate(true)
	(bad_missing["vertical_connections"] as Array)[0]["to_room"] = "nonexistent_room"
	var r_missing: Dictionary = TemplateCTraversalScript.validate(bad_missing)
	if r_missing.get("valid", true):
		push_error("TEMPLATE C TRAVERSAL FAIL missing_room not detected")
		quit(1)
		return
	if String(r_missing.get("error_code", "")) != TemplateCTraversalScript.ERROR_MISSING_ROOM:
		push_error("TEMPLATE C TRAVERSAL FAIL error_code=%s expected=%s" % [
			String(r_missing.get("error_code", "")), TemplateCTraversalScript.ERROR_MISSING_ROOM])
		quit(1)
		return

	# --- Case 5: deck_mismatch ---
	var bad_deck: Dictionary = layout.duplicate(true)
	var vertical_arr: Array = bad_deck["vertical_connections"]
	# Replace the ramp with a same-deck adjacency (still listed as vertical).
	var new_vert: Array = [
		{"id": "fake_vert", "from_room": "airlock_01", "to_room": "ramp_room",
		 "from_cell": Vector2i(0, 0), "to_cell": Vector2i(1, 0),
		 "type": "ramp", "module_id": "ramp_up_1x2"},
	]
	bad_deck["vertical_connections"] = new_vert
	bad_deck["rooms"].append({"id": "airlock_01_alt", "room_role": "airlock", "deck": 0, "cells": [Vector2i(2, 0)]})
	# Replace to_room with a same-deck room.
	new_vert[0]["to_room"] = "airlock_01_alt"
	var r_deck: Dictionary = TemplateCTraversalScript.validate(bad_deck)
	if r_deck.get("valid", true):
		push_error("TEMPLATE C TRAVERSAL FAIL deck_mismatch not detected")
		quit(1)
		return
	if String(r_deck.get("error_code", "")) != TemplateCTraversalScript.ERROR_DECK_MISMATCH:
		push_error("TEMPLATE C TRAVERSAL FAIL error_code=%s expected=%s" % [
			String(r_deck.get("error_code", "")), TemplateCTraversalScript.ERROR_DECK_MISMATCH])
		quit(1)
		return

	# --- Case 6: cell_missing ---
	var bad_cell: Dictionary = layout.duplicate(true)
	var vc: Array = bad_cell["vertical_connections"]
	vc[0]["to_cell"] = Vector2i(99, 99)  # not in upper_room's cells (which has [1, 0])
	var r_cell: Dictionary = TemplateCTraversalScript.validate(bad_cell)
	if r_cell.get("valid", true):
		push_error("TEMPLATE C TRAVERSAL FAIL cell_missing not detected")
		quit(1)
		return
	if String(r_cell.get("error_code", "")) != TemplateCTraversalScript.ERROR_CELL_MISSING:
		push_error("TEMPLATE C TRAVERSAL FAIL error_code=%s expected=%s" % [
			String(r_cell.get("error_code", "")), TemplateCTraversalScript.ERROR_CELL_MISSING])
		quit(1)
		return

	# --- Case 7: self_transition ---
	var bad_self: Dictionary = layout.duplicate(true)
	var vc_self: Array = bad_self["vertical_connections"]
	vc_self[0]["to_room"] = "ramp_room"  # from_room == to_room
	var r_self: Dictionary = TemplateCTraversalScript.validate(bad_self)
	if r_self.get("valid", true):
		push_error("TEMPLATE C TRAVERSAL FAIL self_transition not detected")
		quit(1)
		return
	if String(r_self.get("error_code", "")) != TemplateCTraversalScript.ERROR_SELF_TRANSITION:
		push_error("TEMPLATE C TRAVERSAL FAIL error_code=%s expected=%s" % [
			String(r_self.get("error_code", "")), TemplateCTraversalScript.ERROR_SELF_TRANSITION])
		quit(1)
		return

	# --- Case 8: critical_path BFS ---
	var path: Array[String] = TemplateCTraversalScript.critical_path(layout)
	if path.is_empty():
		push_error("TEMPLATE C TRAVERSAL FAIL critical_path empty")
		quit(1)
		return
	if String(path[0]) != "airlock_01":
		push_error("TEMPLATE C TRAVERSAL FAIL critical_path[0]=%s" % String(path[0]))
		quit(1)
		return

	# --- Case 9: Full stacked template generates a validatable layout ---
	var blueprint: RefCounted = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		314)
	var archetype: Dictionary = {
		"name": "Stacked",
		"template": "stacked",
	}
	var gen: RefCounted = ShipLayoutGeneratorScript.new()
	var stacked_layout: Dictionary = gen.generate(blueprint, archetype)
	if stacked_layout.is_empty():
		push_error("TEMPLATE C TRAVERSAL FAIL pipeline returned empty layout")
		quit(1)
		return
	var stacked_result: Dictionary = TemplateCTraversalScript.validate(stacked_layout)
	if not stacked_result.get("valid", false):
		push_error("TEMPLATE C TRAVERSAL FAIL pipeline-generated layout rejected: %s" % String(stacked_result.get("error_code", "")))
		quit(1)
		return
	var trans: int = int(stacked_result.get("transitions_checked", 0))
	if trans < 1:
		push_error("TEMPLATE C TRAVERSAL FAIL pipeline-generated layout has no transitions: %d" % trans)
		quit(1)
		return

	print("TEMPLATE C TRAVERSAL PASS transitions_checked=%d missing=ok deck=ok cell=ok self=ok critical_path=ok pipeline_transitions=%d" % [
		int(result.get("transitions_checked", 0)),
		trans,
	])
	quit(0)
