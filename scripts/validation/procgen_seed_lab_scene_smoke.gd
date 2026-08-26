extends SceneTree

const LabScene := preload("res://scenes/debug/procgen_seed_lab.tscn")
const DOMAINS: Array[String] = ["world", "mission", "topology", "navigation", "encounter", "item", "creature"]
var failures: Array[String] = []

func _init() -> void:
	_run()

func _run() -> void:
	var lab: Control = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	if lab == null or lab.controller == null: _fail("controller_not_configured")
	if lab.get_child_count() == 0 or not lab.get_child(0) is ScrollContainer: _fail("scroll_container_missing")
	if lab.graph_view == null: _fail("graph_view_missing")
	if lab.controls.size() < 10: _fail("request_controls_missing")
	if not lab.toggle_lock("world_seed", true): _fail("lock_toggle")
	if not lab.toggle_lock("world_seed", false): _fail("unlock_toggle")
	for lock_field: String in lab.LOCK_FIELDS:
		var lock_control: Variant = lab.controls.get("lock_%s" % lock_field, null)
		if not lock_control is CheckButton: _fail("lock_control:%s" % lock_field); continue
		(lock_control as CheckButton).button_pressed = true
		if not lab.controller.get_model().is_locked(lock_field): _fail("lock_wiring:%s" % lock_field)
		(lock_control as CheckButton).button_pressed = false
	var unique_seed: int = int(Time.get_ticks_usec() % 1000000000) + 1000
	(lab.controls.seed_0 as LineEdit).text = str(unique_seed)
	(lab.controls.seed_1 as LineEdit).text = str(unique_seed + 1)
	(lab.controls.site_0 as LineEdit).text = "lab-site-%d" % unique_seed
	(lab.controls.site_1 as LineEdit).text = "lab-site-%d" % (unique_seed + 1)
	for domain: String in ["world", "site", "gameplay", "presentation"]:
		lab.requested_domains[domain] = domain != "presentation"
	var request_a: Dictionary = lab.request_for_slot(0)
	var request_b: Dictionary = lab.request_for_slot(1)
	if request_a.is_empty() or request_b.is_empty(): _fail("request_build")
	if not lab.controller.generate(0, request_a): _fail("slot_a_generation:%s" % lab.controller.last_error)
	if not lab.controller.generate(1, request_b): _fail("slot_b_generation:%s" % lab.controller.last_error)
	lab.active_slot = 0
	lab.select_graph("world")
	await process_frame
	var world_graph: Dictionary = lab.controller.get_model().get_slot(0).graphs.world
	if not world_graph.nodes.is_empty():
		if not lab.graph_view.select_node(str(world_graph.nodes[0].id)) or not lab.inspector_label.text.begins_with("Selected world"): _fail("graph_inspector_wiring")
	var comparison: Dictionary = lab.compare_slots()
	if not bool(comparison.get("valid", false)): _fail("compare")
	for domain: String in DOMAINS:
		if not lab.select_graph(domain): _fail("graph_tab:%s" % domain)
		await process_frame
	var selected_domains: Array[String] = ["world", "site"]
	if not lab.controller.regenerate(0, request_a, selected_domains): _fail("selective_regeneration:%s:%s" % [lab.controller.last_error, JSON.stringify(lab.controller.last_result)])
	var diagnostic: Dictionary = lab.save_diagnostic()
	if not bool(diagnostic.get("saved", false)): _fail("diagnostic_save:%s" % lab.diagnostic_store.last_error)
	var promotion: Dictionary = lab.save_pending_promotion("approved_candidate")
	if not bool(promotion.get("saved", false)): _fail("promotion_save:%s" % lab.promotion_store.last_error)
	var path: String = str(promotion.get("path", ""))
	if not path.begins_with("user://procgen/promotions/") or path.begins_with("res://"): _fail("promotion_path")
	var active: Dictionary = lab.controller.get_model().get_slot(lab.active_slot)
	var candidate: Dictionary = lab.controller.get_model().build_promotion_candidate("approved_candidate", lab._diagnostic_for_active_slot(), active.get("request", {}))
	if lab.promotion_store.read_pending(str(candidate.get("candidate_id", ""))).is_empty(): _fail("promotion_readback")
	for cleanup_path: String in [str(diagnostic.get("path", "")), path]:
		if cleanup_path.begins_with("user://procgen/") and FileAccess.file_exists(cleanup_path):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(cleanup_path)) != OK: _fail("cleanup")
	if failures.is_empty():
		print("PROCGEN SEED LAB SCENE PASS live_generation=true slots=2 compare=true graphs=7 locks=13 selective=true diagnostic=true promotion=true frame=true")
		quit(0)
	else:
		for failure: String in failures: print("PROCGEN SEED LAB SCENE FAIL %s" % failure)
		quit(1)

func _fail(message: String) -> void:
	failures.append(message)
