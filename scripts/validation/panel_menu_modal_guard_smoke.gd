extends SceneTree
# Tranche 4 (2026-07-06 audit HIGH): scanner / chart / inventory panel toggles
# in playable_generated_ship._input (:8053/:8078/:8096) had NO menu-modal
# guard — pressing toggle_scanner / ui_open_map / toggle_inventory while the
# pause (or any) menu was open stacked a gameplay overlay on top of the menu
# modal. The chart/scanner-vs-inventory mutual-exclusion guard (commit
# 849b2d5) existed, but nothing gated on menu_state.is_in_play().
#
# Production seams (proven by main_playable_slice_inventory_ui_smoke):
#   - open the menu synchronously via ui.menu_state.open_menu("pause_menu")
#   - inject InputEventAction directly into ship._input()
#
# Asserts:
#   1. With pause_menu open: each of the three toggle actions leaves its
#      panel closed AND the menu still open.
#   2. After menu_state.close_all(): each toggle opens its panel again
#      (the guard must not over-block), closed again between probes.
#
# Pass marker: PANEL MENU MODAL GUARD PASS scanner_blocked=true chart_blocked=true inventory_blocked=true reopens=true

const PlayableShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_002/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_SLICE_PATH: String = "res://data/procgen/golden/coherent_ship_002/gameplay_slice.json"
const READY_TIMEOUT_FRAMES: int = 300

var playable: Node3D
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	playable = PlayableShipScript.new()
	playable.name = "PanelMenuModalGuardSmoke"
	playable.layout_path = LAYOUT_PATH
	playable.kit_path = KIT_PATH
	playable.gameplay_slice_path = GAMEPLAY_SLICE_PATH
	get_root().add_child(playable)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null or not is_instance_valid(playable):
		_fail("playable freed unexpectedly")
		return
	if not playable.playable_started:
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _send(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	playable._input(e)

func _validate() -> void:
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null or not is_instance_valid(ui):
		_fail("menu_coordinator missing")
		return
	if playable.scanner_panel == null or not is_instance_valid(playable.chart_panel) \
			or not is_instance_valid(playable.inventory_panel):
		_fail("expected scanner/chart/inventory panels on the playable ship")
		return
	# Chart gate needs a possessed web_chart so the BLOCKED path is the menu
	# guard, not the no-chart feedback line.
	playable.inventory_state.add_item("web_chart", 1)

	# --- 1. pause_menu open: every toggle must be rejected ---
	ui.menu_state.open_menu("pause_menu")
	if ui.menu_state.is_in_play():
		_fail("pause_menu did not open")
		return

	_send("toggle_scanner")
	if playable.scanner_panel.is_open():
		_fail("scanner panel opened over the pause menu (no menu-modal guard)")
		return
	var scanner_blocked: bool = true

	_send("ui_open_map")
	if playable.chart_panel.is_open():
		_fail("chart panel opened over the pause menu (no menu-modal guard)")
		return
	var chart_blocked: bool = true

	_send("toggle_inventory")
	if playable.inventory_panel.is_open():
		_fail("inventory panel opened over the pause menu (no menu-modal guard)")
		return
	var inventory_blocked: bool = true

	if ui.menu_state.is_in_play():
		_fail("pause menu was closed by a blocked panel toggle")
		return

	# --- 2. menu closed: the guard must not over-block ---
	ui.menu_state.close_all()
	if not ui.menu_state.is_in_play():
		_fail("close_all did not return to in-play")
		return

	_send("toggle_scanner")
	if not playable.scanner_panel.is_open():
		_fail("scanner did not open after the menu closed (guard over-blocks)")
		return
	_send("toggle_scanner")  # toggle back closed
	if playable.scanner_panel.is_open():
		_fail("scanner did not close on second toggle")
		return

	_send("ui_open_map")
	if not playable.chart_panel.is_open():
		_fail("chart did not open after the menu closed (guard over-blocks)")
		return
	_send("ui_open_map")  # close via the chart-open branch
	if playable.chart_panel.is_open():
		_fail("chart did not close on second ui_open_map")
		return

	_send("toggle_inventory")
	if not playable.inventory_panel.is_open():
		_fail("inventory did not open after the menu closed (guard over-blocks)")
		return
	_send("toggle_inventory")
	if playable.inventory_panel.is_open():
		_fail("inventory did not close on second toggle")
		return

	finished = true
	print("PANEL MENU MODAL GUARD PASS scanner_blocked=%s chart_blocked=%s inventory_blocked=%s reopens=true" % [
		str(scanner_blocked).to_lower(), str(chart_blocked).to_lower(), str(inventory_blocked).to_lower()])
	playable.queue_free()
	quit(0)

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("PANEL MENU MODAL GUARD FAIL reason=%s" % reason)
	if playable != null and is_instance_valid(playable):
		playable.queue_free()
	quit(1)
