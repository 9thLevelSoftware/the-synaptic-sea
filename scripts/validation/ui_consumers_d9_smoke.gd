extends SceneTree

## PKG-D9a/c/d: WorkAction HUD, chart routes, wounds panel.
## Marker: UI CONSUMERS D9 PASS work_hud=true wounds=true chart_route=true

const WorkActionHudPanelScript := preload("res://scripts/ui/work_action_hud_panel.gd")
const WoundsPanelScript := preload("res://scripts/ui/wounds_panel.gd")
const ChartPanelScript := preload("res://scripts/ui/chart_panel.gd")
const WoundStateScript := preload("res://scripts/systems/wound_state.gd")
const WebChartStateScript := preload("res://scripts/systems/web_chart_state.gd")
const SeaGraphScript := preload("res://scripts/systems/sea_graph.gd")


func _initialize() -> void:
	# --- WorkAction HUD ---
	var hud = WorkActionHudPanelScript.new()
	get_root().add_child(hud)
	await process_frame
	hud.set_work_state({
		"action_id": "cut_wall",
		"target_id": "eng/wall_a",
		"verb": "cut",
		"progress": 0.45,
		"status": "active",
		"noise": 0.85,
	})
	if not hud.is_open():
		_fail("work hud should open when active"); return
	if absf(hud.get_progress() - 0.45) > 0.001:
		_fail("progress"); return
	var lines: PackedStringArray = hud.get_status_lines()
	var joined: String = "\n".join(lines)
	if not joined.contains("cut") and not joined.contains("CUT"):
		_fail("verb missing in hud lines"); return
	if not joined.contains("45") and not joined.contains("Progress"):
		_fail("progress missing"); return
	if not joined.contains("eng/wall_a"):
		_fail("target missing"); return
	hud.set_work_state({"status": "idle", "progress": 0.0})
	if hud.is_open():
		_fail("idle should close hud"); return

	# --- Wounds panel ---
	var ws = WoundStateScript.new()
	ws.apply_wound({
		"kind": WoundStateScript.KIND_LACERATION,
		"body_part": WoundStateScript.BODY_ARM,
		"severity": 0.6,
	})
	ws.apply_wound({
		"kind": WoundStateScript.KIND_FRACTURE,
		"body_part": WoundStateScript.BODY_LEG,
		"severity": 0.5,
	})
	var wounds_ui = WoundsPanelScript.new()
	get_root().add_child(wounds_ui)
	await process_frame
	wounds_ui.bind(ws)
	wounds_ui.open()
	if wounds_ui.get_selected_wound_id().is_empty():
		_fail("should select first wound"); return
	if not wounds_ui.bandage_selected():
		_fail("bandage"); return
	var wid: String = wounds_ui.get_selected_wound_id()
	var entry: Dictionary = ws.get_wound(wid)
	if not bool(entry.get("bandaged", false)):
		_fail("bandaged flag"); return
	wounds_ui.move_selection(1)
	if not wounds_ui.treat_selected(0.4):
		_fail("treat"); return
	var wlines: PackedStringArray = wounds_ui.get_status_lines()
	if "\n".join(wlines).find("Work speed") < 0:
		_fail("work speed line"); return

	# --- Chart + SeaGraph route ---
	var chart_state = WebChartStateScript.new()
	chart_state.record_views([
		{"marker_id": "m1", "position": [10.0, 0.0, 0.0], "size_class": 1, "ship_type": "freighter"},
		{"marker_id": "m2", "position": [80.0, 0.0, 40.0], "size_class": 2},
	], 2)
	var graph = SeaGraphScript.new()
	graph.configure({"fuel_per_unit": 0.1, "food_per_unit": 0.05})
	graph.build_from_markers([
		{"marker_id": "m1", "position": [30.0, 0.0, 0.0]},
		{"marker_id": "m2", "position": [100.0, 0.0, 50.0]},
	], Vector3.ZERO, Vector3(180, 0, 180))
	var chart_ui = ChartPanelScript.new()
	get_root().add_child(chart_ui)
	await process_frame
	chart_ui.bind(chart_state)
	chart_ui.bind_sea_graph(graph)
	chart_ui.open()
	chart_ui.refresh_extraction_route()
	var rlines: PackedStringArray = chart_ui.get_route_lines()
	if rlines.is_empty():
		_fail("route lines expected"); return
	var rjoin: String = "\n".join(rlines)
	if not rjoin.contains("extraction") and not rjoin.contains("fuel"):
		_fail("route should mention extraction/fuel: %s" % rjoin); return
	if not chart_ui.get_status().contains("route ready"):
		_fail("status should note route ready"); return
	var rows: Array = chart_ui.get_row_texts()
	if rows.size() < 2:
		_fail("chart rows"); return

	print("UI CONSUMERS D9 PASS work_hud=true wounds=true chart_route=true")
	quit(0)


func _fail(msg: String) -> void:
	print("UI CONSUMERS D9 FAIL: %s" % msg)
	quit(1)
