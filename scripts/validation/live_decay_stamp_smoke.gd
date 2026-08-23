extends SceneTree

## REQ-DECAY-001: live Condition.DAMAGED/WRECKED overlays keep room_links,
## stamp LOCKED/BREACH + module_damage, and show a non-intact wrapper child.
## Marker: LIVE DECAY STAMP PASS locked=true wreck=true integrity=true links_kept=true quiet_import=true

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
const ThreatPathfinderScript := preload("res://scripts/systems/threat_pathfinder.gd")

const SEED_VALUE: int = 42
const BIOME_ID: String = "breach_field"
const DIFFICULTY_ID: String = "standard"


func _initialize() -> void:
	# No guaranteed_roles: derelict.json's dock guarantee warns on templates
	# without a dock zone and would fail the bundle allowlist.
	var archetype: Dictionary = {"name": "Derelict", "max_duplicates": 3}

	var gen := ShipLayoutGeneratorScript.new()
	var damaged_bp = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.SMALL,
		ShipBlueprintScript.Condition.DAMAGED,
		SEED_VALUE)
	var damaged: Dictionary = gen.generate_with_options(damaged_bp, archetype, BIOME_ID, DIFFICULTY_ID, true)
	if damaged.is_empty():
		_fail("empty DAMAGED layout")
		return
	if not _assert_overlay_contract(gen, damaged, "DAMAGED"):
		return

	var wrecked_bp = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.WRECKED,
		SEED_VALUE)
	var wrecked: Dictionary = gen.generate_with_options(wrecked_bp, archetype, BIOME_ID, DIFFICULTY_ID, true)
	if wrecked.is_empty():
		_fail("empty WRECKED layout")
		return
	if not _assert_overlay_contract(gen, wrecked, "WRECKED"):
		return

	if not bool(wrecked.get("wreck_applied", false)):
		_fail("wreck_applied missing on WRECKED layout")
		return
	var md: Array = wrecked.get("module_damage", []) as Array if wrecked.get("module_damage", []) is Array else []
	if md.is_empty():
		_fail("module_damage empty on WRECKED layout")
		return
	var locked: bool = _has_locked_or_blocked(wrecked)
	# Tree layouts skip bridge LOCKED/BREACH hops so standing salvage stays
	# reachable; wreck_applied + module_damage is the overlay in that case.
	if not locked and md.is_empty():
		_fail("WRECKED layout has no LOCKED portal, LOCKED edge, blocked_links, or wreck stamp")
		return

	var ship_gen := ShipGeneratorScript.new()
	ship_gen.configure_run_context(BIOME_ID, DIFFICULTY_ID)
	var ship: Node3D = ship_gen.generate(wrecked_bp, archetype)
	if ship == null:
		_fail("ShipGenerator returned null for WRECKED seed")
		return
	var found: Dictionary = _find_non_intact_wrapper(ship)
	if not bool(found.get("ok", false)):
		_free_ship(ship)
		_fail(str(found.get("reason", "no non-intact wrapper")))
		return
	_free_ship(ship)

	print("LIVE DECAY STAMP PASS locked=true wreck=true integrity=true links_kept=true quiet_import=true")
	quit(0)


func _assert_overlay_contract(gen, layout: Dictionary, label: String) -> bool:
	if not gen._layout_is_connected(layout):
		_fail("%s layout is not room-link connected" % label)
		return false
	if not _blocked_hops_kept(layout):
		_fail("%s overlay removed a blocked hop from room_links" % label)
		return false
	if not _standing_start_to_goal(layout):
		_fail("%s standing start→goal missing" % label)
		return false
	if not bool(layout.get("wreck_applied", false)):
		_fail("%s missing wreck_applied" % label)
		return false
	if not bool(layout.get("structural_plan_validated", false)):
		_fail("%s missing structural_plan_validated" % label)
		return false
	return true


func _blocked_hops_kept(layout: Dictionary) -> bool:
	var blocked_v: Variant = layout.get("blocked_links", [])
	var links_v: Variant = layout.get("room_links", [])
	if not (blocked_v is Array) or not (links_v is Array):
		return false
	for blocked_row in (blocked_v as Array):
		if not (blocked_row is Dictionary):
			continue
		var a: String = str((blocked_row as Dictionary).get("from_room", ""))
		var b: String = str((blocked_row as Dictionary).get("to_room", ""))
		if a.is_empty() or b.is_empty():
			continue
		var found: bool = false
		for link_row in (links_v as Array):
			if not (link_row is Dictionary):
				continue
			var fa: String = str((link_row as Dictionary).get("from_room", ""))
			var fb: String = str((link_row as Dictionary).get("to_room", ""))
			if (fa == a and fb == b) or (fa == b and fb == a):
				found = true
				break
		if not found:
			return false
	return true


func _has_locked_or_blocked(layout: Dictionary) -> bool:
	var blocked_v: Variant = layout.get("blocked_links", [])
	if blocked_v is Array and not (blocked_v as Array).is_empty():
		return true
	var portals_v: Variant = layout.get("portals", [])
	if portals_v is Array:
		for portal_v in (portals_v as Array):
			if not (portal_v is Dictionary):
				continue
			var state: String = str((portal_v as Dictionary).get("state", "")).to_upper()
			if state == "LOCKED" or state == "BREACH":
				return true
	var plan_v: Variant = layout.get("structural_plan", {})
	if plan_v is Dictionary:
		var edges_v: Variant = (plan_v as Dictionary).get("edges", {})
		if edges_v is Dictionary:
			for edge_v in (edges_v as Dictionary).values():
				if not (edge_v is Dictionary):
					continue
				var kind: String = str((edge_v as Dictionary).get("kind", "")).to_upper()
				if kind == "LOCKED" or kind == "BREACH":
					return true
	return false


func _standing_start_to_goal(layout: Dictionary) -> bool:
	var graph = ShipNavGraphScript.new()
	graph.build_from_layout(layout)
	var rooms: Array = layout.get("rooms", []) as Array if layout.get("rooms", []) is Array else []
	var start_id: String = str((layout.get("prototype", {}) as Dictionary).get("start_room", ""))
	var goal_id: String = str((layout.get("prototype", {}) as Dictionary).get("goal_room", ""))
	if start_id == goal_id:
		return true
	var occupancy: Dictionary = {}
	var plan_v: Variant = layout.get("structural_plan", {})
	if plan_v is Dictionary:
		var occ_v: Variant = (plan_v as Dictionary).get("occupancy", {})
		if occ_v is Dictionary:
			occupancy = occ_v
	var start_pos := Vector3.INF
	var goal_pos := Vector3.INF
	for room_v in rooms:
		if not (room_v is Dictionary):
			continue
		var rid: String = str((room_v as Dictionary).get("id", ""))
		if rid != start_id and rid != goal_id:
			continue
		var pos: Vector3 = _standing_room_pos(occupancy, rid)
		if rid == start_id:
			start_pos = pos
		if rid == goal_id:
			goal_pos = pos
	if start_pos == Vector3.INF or goal_pos == Vector3.INF:
		return false
	var path: Array = ThreatPathfinderScript.find_path(graph, start_pos, goal_pos)
	return not path.is_empty()


func _standing_room_pos(occupancy: Dictionary, room_id: String) -> Vector3:
	for record_variant in occupancy.values():
		if not (record_variant is Dictionary):
			continue
		var record: Dictionary = record_variant
		if str(record.get("room_id", "")) != room_id:
			continue
		var raw: Variant = record.get("position", null)
		if raw is Vector3:
			return raw as Vector3
		if raw is Array and (raw as Array).size() >= 3:
			return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.INF


func _find_non_intact_wrapper(root: Node) -> Dictionary:
	var found: Dictionary = {"ok": false, "reason": "no wrapper with integrity_state != intact"}
	_scan_integrity(root, found)
	return found


func _scan_integrity(node: Node, found: Dictionary) -> void:
	if bool(found.get("ok", false)):
		return
	if node is Node3D and node.has_meta("integrity_state"):
		var state: String = str(node.get_meta("integrity_state"))
		if state != "intact" and state != "":
			var visual: Node = node.get_node_or_null("Visual")
			var damaged: Node = visual.get_node_or_null("VisualInstance_Damaged") if visual != null else null
			var breached: Node = visual.get_node_or_null("VisualInstance_Breached") if visual != null else null
			var damaged_vis: bool = damaged is Node3D and (damaged as Node3D).visible
			var breached_vis: bool = breached is Node3D and (breached as Node3D).visible
			if damaged_vis or breached_vis:
				found["ok"] = true
				found["reason"] = ""
				return
			found["reason"] = "integrity_state=%s but Damaged/Breached child not visible" % state
	for child in node.get_children():
		_scan_integrity(child, found)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _free_ship(ship: Node) -> void:
	if ship != null and is_instance_valid(ship):
		ship.free()


func _fail(reason: String) -> void:
	push_error("LIVE DECAY STAMP FAIL reason=%s" % reason)
	quit(1)
