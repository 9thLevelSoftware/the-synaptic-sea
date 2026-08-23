extends SceneTree

## Task 2.2: results/death epitaph panel contract.
## Builds the real panel, feeds a death summary, then an extraction summary.
## Marker: RUN RESULTS PASS

const RunResultsPanelScript: GDScript = preload("res://scripts/ui/run_results_panel.gd")

var panel: Control

func _initialize() -> void:
	panel = RunResultsPanelScript.new()
	get_root().add_child(panel)
	panel.set_run_summary({
		"reason": "death",
		"cause": "oxygen",
		"play_time_seconds": 125.0,
		"rooms_discovered": 4,
		"threats_killed": 2,
	})
	var death_text: String = _visible_text(panel)
	if not panel.visible:
		_fail("death results panel is not visible")
		return
	if death_text.findn("death") < 0 or death_text.findn("oxygen") < 0:
		_fail("death summary text missing outcome/cause: %s" % death_text)
		return

	panel.set_run_summary({
		"reason": "extraction",
		"play_time_seconds": 300.0,
		"objectives_completed": 3,
	})
	var extraction_text: String = _visible_text(panel)
	if extraction_text.findn("extraction") < 0:
		_fail("extraction summary text missing outcome: %s" % extraction_text)
		return
	if extraction_text.findn("Objectives completed") < 0:
		_fail("available extraction stat missing: %s" % extraction_text)
		return

	print("RUN RESULTS PASS death=true extraction=true visible_text=true")
	panel.queue_free()
	quit(0)

func _visible_text(root: Node) -> String:
	var text: String = ""
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label:
			text += (node as Label).text + "\n"
		elif node is Button:
			text += (node as Button).text + "\n"
		for child in node.get_children():
			stack.append(child)
	return text

func _fail(reason: String) -> void:
	push_error("RUN RESULTS FAIL reason=%s" % reason)
	quit(1)
