extends SceneTree

## Scanner panel unit smoke against a stub coordinator. Proves the panel
## populates rows from scan(), moves selection, and confirms travel via
## travel_to_marker_id() with the selected marker's id.

const ScannerPanelScript := preload("res://scripts/ui/scanner_panel.gd")

# Minimal stub exposing the two coordinator methods the panel calls.
class StubCoordinator extends RefCounted:
	var last_travel_id: String = ""
	func scan() -> Dictionary:
		return {
			"detail_level": 2,
			"markers": [
				{"marker_id": "0:0:0", "distance": 12.0, "size_class": 1, "ship_type": "shuttle"},
				{"marker_id": "0:0:1", "distance": 48.0, "size_class": 2, "ship_type": "freighter"},
			],
		}
	func travel_to_marker_id(marker_id: String) -> Dictionary:
		last_travel_id = marker_id
		return {"success": true, "reason": "ok", "ship": null}

func _initialize() -> void:
	var stub := StubCoordinator.new()
	var panel = ScannerPanelScript.new()
	get_root().add_child(panel)
	panel.bind(stub)

	# Track panel_closed emissions so we can assert close() always signals.
	var closed_count: Array = [0]
	panel.panel_closed.connect(func() -> void: closed_count[0] += 1)

	# Closed by default; open() shows + populates.
	if panel.is_open():
		_fail("panel should start closed")
		return
	panel.open()
	if not panel.is_open():
		_fail("open() did not show the panel")
		return
	var rows: Array = panel.get_row_texts()
	if rows.size() != 2:
		_fail("expected 2 rows, got %d" % rows.size())
		return
	if not String(rows[0]).contains("0:0:0"):
		_fail("row 0 missing marker id")
		return

	# Selection starts at 0, moves down with wrap.
	if panel.get_selected_index() != 0:
		_fail("initial selection should be 0")
		return
	panel.move_selection(1)
	if panel.get_selected_index() != 1:
		_fail("selection did not move to 1")
		return
	panel.move_selection(1)  # wraps back to 0
	if panel.get_selected_index() != 0:
		_fail("selection did not wrap to 0")
		return

	# Confirm travels to the selected marker id and closes on success.
	panel.move_selection(1)  # select 0:0:1
	var result: Dictionary = panel.confirm_selection()
	if not bool(result.get("success", false)):
		_fail("confirm did not report success")
		return
	if stub.last_travel_id != "0:0:1":
		_fail("travel invoked with wrong id: %s" % stub.last_travel_id)
		return
	if panel.is_open():
		_fail("panel should close after a successful travel")
		return
	# close() (via confirm-success) must emit panel_closed so the coordinator
	# restores player control on every close path.
	if closed_count[0] != 1:
		_fail("panel_closed not emitted on close, count=%d" % closed_count[0])
		return

	# Reopening must reset selection to the top contact, not a stale index.
	panel.move_selection(1)  # nudge selection off 0 while closed is irrelevant
	panel.open()
	if panel.get_selected_index() != 0:
		_fail("reopen did not reset selection to 0, got %d" % panel.get_selected_index())
		return
	panel.close()

	panel.queue_free()
	print("SCANNER PANEL PASS populated=true selection_moves=true travel_invoked=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SCANNER PANEL FAIL reason=%s" % reason)
	quit(1)
