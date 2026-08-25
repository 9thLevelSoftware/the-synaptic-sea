extends SceneTree
## Differential probe for the worldgen v2 Rust port of the structural
## compiler: compiles a fixed hand-authored topology through the GDScript
## StructuralEdgeCompiler and prints canonical edge/floor/ceiling records in
## a normalized sortable format. The Rust side prints the same format for
## the same fixture; outputs must match line-for-line (module ids excluded
## for corner-upgrade tie-break differences; kinds/keys/poses are the
## contract).
##
## Run: godot --headless --path . --script res://scripts/validation/worldgen_diff_probe.gd

func _initialize() -> void:
	var layout := {
		"rooms": [
			{"id": "room_1", "deck": 0, "room_role": "airlock",
				"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
			{"id": "room_2", "deck": 0, "room_role": "bridge",
				"cells": [Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)]},
			{"id": "room_3", "deck": 1, "room_role": "crew_quarters",
				"cells": [Vector2i(0, 0), Vector2i(1, 0)]},
		],
		"portals": [
			{"from_room": "room_1", "to_room": "room_2",
				"from_cell": Vector2i(1, 0), "to_cell": Vector2i(2, 0), "state": "DOOR"},
		],
		"vertical_connections": [
			{"from_room": "room_1", "to_room": "room_3",
				"from_cell": Vector2i(0, 0), "to_cell": Vector2i(0, 0),
				"from_deck": 0, "to_deck": 1},
		],
	}
	var compiler = load("res://scripts/procgen/structural_edge_compiler.gd").new()
	var plan: Dictionary = compiler.compile(layout)
	var lines: Array[String] = []
	for err in plan.get("errors", []):
		lines.append("ERROR %s" % err)
	var edges: Dictionary = plan.get("edges", {})
	for key in edges:
		var e: Dictionary = edges[key]
		lines.append("EDGE %s kind=%s portal=%s" % [key, e.get("kind", "?"), e.get("portal", false)])
	for f in plan.get("floor_placements", []):
		lines.append("FLOOR %s pos=%s yaw=%s" % [f.get("cell_key", "?"), _fmt_pos(f.get("position")), int(f.get("yaw_degrees", -1))])
	for c in plan.get("ceiling_placements", []):
		lines.append("CEIL %s" % c.get("cell_key", "?"))
	lines.sort()
	for l in lines:
		print(l)
	print("DIFF_PROBE_DONE edges=%d floors=%d ceilings=%d errors=%d" % [
		edges.size(), plan.get("floor_placements", []).size(),
		plan.get("ceiling_placements", []).size(), plan.get("errors", []).size()])
	quit(0)

func _fmt_pos(p) -> String:
	if p is Vector3:
		return "%.1f,%.1f,%.1f" % [p.x, p.y, p.z]
	return str(p)
