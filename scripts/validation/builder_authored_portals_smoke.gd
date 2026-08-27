extends SceneTree

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")

func _initialize() -> void:
	var layout := _json("res://data/procgen/golden/coherent_ship_001/layout.json")
	var kit := _json("res://data/kits/ship_structural_v0.json")
	var gameplay := _json("res://data/procgen/golden/coherent_ship_001/gameplay_slice.json")
	if not _stamp_exterior_portal(layout):
		_fail("fixture has no exterior structural edge for portal coverage")
		return
	if not _stamp_locked_portal(layout):
		_fail("fixture has no structural door for locked portal coverage")
		return
	if not _stamp_hatch_portal(layout):
		_fail("fixture has no structural edge for hatch portal coverage")
		return
	var loader := LoaderScript.new()
	get_root().add_child(loader)
	if not loader.load_from_documents(layout, kit, gameplay, false):
		_fail("loader rejected augmented coherent document")
		return
	var nodes := loader.get_authored_portal_nodes()
	var expected_portals := _structural_portal_count(layout)
	if nodes.size() != expected_portals:
		_fail("loader did not materialize every authored portal")
		return
	var actual_exterior = null
	var door = null
	var actual_locked = null
	var actual_hatch = null
	for node in nodes:
		if node.get_blocker_collision_shape() == null:
			_fail("portal missing blocker collision")
			return
		if bool(node.is_exterior):
			actual_exterior = node
		elif str(node.portal_kind) == "LOCKED":
			actual_locked = node
		elif str(node.portal_kind) == "HATCH":
			actual_hatch = node
		elif str(node.portal_kind) == "DOOR":
			door = node
	if actual_exterior == null:
		_fail("structural-plan exterior portal was not materialized")
		return
	actual_exterior.set_validation_player_in_range(true)
	var exterior_flags := {}
	if str(actual_exterior.portal_kind) == "LOCKED":
		exterior_flags[str(actual_exterior.required_flag())] = true
	if not bool(actual_exterior.try_interact(exterior_flags).get("exterior", false)):
		_fail("materialized exterior portal was not observable")
		return
	if actual_locked == null:
		_fail("fixture materialized no locked structural portal")
		return
	if actual_hatch == null:
		_fail("fixture materialized no hatch structural portal")
		return
	actual_hatch.set_validation_player_in_range(true)
	var hatch_visual := actual_hatch.get_node_or_null("PortalVisual") as MeshInstance3D
	var hatch_collision_before: int = int(actual_hatch.get_structural_blocker_collision_enabled_count())
	var hatch_open: Dictionary = actual_hatch.try_interact({})
	var hatch_collision_open: int = int(actual_hatch.get_structural_blocker_collision_enabled_count())
	var hatch_visible_open: bool = actual_hatch.is_structural_blocker_visible()
	var hatch_visual_open: bool = hatch_visual != null and hatch_visual.visible
	var hatch_closed: Dictionary = actual_hatch.try_interact({})
	var hatch_collision_closed: int = int(actual_hatch.get_structural_blocker_collision_enabled_count())
	var hatch_visible_closed: bool = actual_hatch.is_structural_blocker_visible()
	if hatch_collision_before <= 0 or not bool(hatch_open.get("open", false)) \
			or hatch_collision_open != 0 \
			or hatch_visible_open \
			or hatch_visual == null or hatch_visual_open \
			or bool(hatch_closed.get("open", true)) \
			or hatch_collision_closed <= 0 \
			or not hatch_visible_closed:
		_fail("hatch interaction did not disable and re-seal structural collision")
		return
	actual_locked.set_validation_player_in_range(true)
	var locked_visual := actual_locked.get_node_or_null("PortalVisual") as MeshInstance3D
	var structural_collision_before: int = int(actual_locked.get_structural_blocker_collision_enabled_count())
	var locked_flags := {str(actual_locked.required_flag()): true}
	var unlocked: Dictionary = actual_locked.try_interact(locked_flags)
	if structural_collision_before <= 0 or not bool(unlocked.get("open", false)) \
			or actual_locked.get_structural_blocker_collision_enabled_count() != 0 \
			or actual_locked.is_structural_blocker_visible() \
			or locked_visual == null or locked_visual.visible:
		_fail("unlocking did not disable structural collision and hide the portal visual")
		return
	if door == null:
		door = _standalone("door", "door", loader)
	door.set_validation_player_in_range(true)
	var door_shape: CollisionShape3D = door.get_blocker_collision_shape()
	var door_visual := door.get_node_or_null("PortalVisual") as MeshInstance3D
	if door_shape.disabled or not bool(door.try_interact({}).get("open", false)) or not door_shape.disabled \
			or door_visual == null or door_visual.visible:
		_fail("door did not toggle collision state")
		return
	var locked = _standalone("locked", "locked", loader)
	locked.set_validation_player_in_range(true)
	if bool(locked.try_interact({}).get("ok", true)) or not bool(locked.try_interact({"lockpick": true}).get("ok", false)):
		_fail("locked portal accepted/rejected wrong flags")
		return
	var hatch = _standalone("hatch", "hatch", loader)
	hatch.set_validation_player_in_range(true)
	var hatch_visual_standalone := hatch.get_node_or_null("PortalVisual") as MeshInstance3D
	var hatch_open_standalone: Dictionary = hatch.try_interact({})
	var hatch_closed_standalone: Dictionary = hatch.try_interact({})
	if not bool(hatch_open_standalone.get("open", false)) or bool(hatch_closed_standalone.get("open", true)) \
			or hatch_visual_standalone == null or not hatch_visual_standalone.visible:
		_fail("hatch did not open and reseal")
		return
	var breach = _standalone("breach", "breach", loader)
	breach.set_validation_player_in_range(true)
	if not bool(breach.try_interact({}).get("unsafe", false)):
		_fail("breach was not observable unsafe trigger")
		return
	var exit = _standalone("exit", "exterior", loader)
	exit.set_validation_player_in_range(true)
	if not bool(exit.try_interact({}).get("exterior", false)):
		_fail("exterior exit was not observable")
	var oriented = _standalone("east_west", "door", loader, {
		"from_position": Vector3.ZERO,
		"to_position": Vector3(4.0, 0.0, 0.0),
	})
	if not is_equal_approx(absf(oriented.rotation_degrees.y), 90.0):
		_fail("east-west portal blocker was not rotated to its authored edge")
	var structural_count_before_overlay: int = loader.count_collision_shapes()
	var overlay := Area3D.new()
	var overlay_shape := CollisionShape3D.new()
	overlay_shape.shape = BoxShape3D.new()
	overlay.add_child(overlay_shape)
	loader.structural_root.add_child(overlay)
	if loader.count_collision_shapes() != structural_count_before_overlay:
		_fail("structural collision readiness counted a runtime overlay shape")
	loader.structural_root.remove_child(overlay)
	overlay.free()
	print("BUILDER AUTHORED PORTALS PASS authored=%d door=true locked=true structural_unlock=true hatch=true breach=true exterior=true orientation=true" % nodes.size())
	quit(0)

func _standalone(id: String, kind: String, parent: Node, extra: Dictionary = {}) -> Node:
	var script := preload("res://scripts/interaction/authored_portal_runtime.gd")
	var portal = script.new()
	var spec := {"id": id, "type": kind, "exterior": kind == "exterior"}
	spec.merge(extra, true)
	portal.configure(spec, Vector3.ZERO)
	parent.add_child(portal)
	return portal

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _structural_portal_count(layout: Dictionary) -> int:
	var count := 0
	var edges: Variant = (layout.get("structural_plan", {}) as Dictionary).get("edges", {})
	for raw in (edges as Dictionary).values():
		if raw is Dictionary and bool((raw as Dictionary).get("portal", false)):
			count += 1
	return count

func _stamp_exterior_portal(layout: Dictionary) -> bool:
	var plan: Dictionary = layout.get("structural_plan", {}) as Dictionary
	var edges: Dictionary = plan.get("edges", {}) as Dictionary
	var selected_key := ""
	for key in edges:
		var edge: Dictionary = edges[key] as Dictionary
		if bool(edge.get("exterior", false)) and str(edge.get("kind", "")) == "SOLID":
			selected_key = str(key)
			edge["kind"] = "DOOR"
			edge["state"] = "DOOR"
			edge["module_id"] = "doorway_frame_open_1x1"
			edge["portal"] = true
			edge["wrapper_required"] = true
			edge["placement_required"] = true
			break
	if selected_key.is_empty():
		return false
	var placements: Array = plan.get("placements", []) as Array
	for raw in placements:
		if raw is Dictionary and str((raw as Dictionary).get("edge_key", (raw as Dictionary).get("key", ""))) == selected_key:
			(raw as Dictionary)["kind"] = "DOOR"
			(raw as Dictionary)["state"] = "DOOR"
			(raw as Dictionary)["module_id"] = "doorway_frame_open_1x1"
			(raw as Dictionary)["portal"] = true
			(raw as Dictionary)["wrapper_required"] = true
			(raw as Dictionary)["placement_required"] = true
			return true
	return false


func _stamp_locked_portal(layout: Dictionary) -> bool:
	var plan: Dictionary = layout.get("structural_plan", {}) as Dictionary
	var edges: Dictionary = plan.get("edges", {}) as Dictionary
	var selected_key := ""
	for key in edges:
		var edge: Dictionary = edges[key] as Dictionary
		if str(edge.get("kind", "")) == "DOOR" and not bool(edge.get("exterior", false)):
			selected_key = str(key)
			edge["kind"] = "LOCKED"
			edge["state"] = "LOCKED"
			edge["module_id"] = "doorway_frame_blocked_1x1"
			break
	if selected_key.is_empty():
		return false
	var placements: Array = plan.get("placements", []) as Array
	for raw in placements:
		if raw is Dictionary and str((raw as Dictionary).get("edge_key", (raw as Dictionary).get("key", ""))) == selected_key:
			(raw as Dictionary)["kind"] = "LOCKED"
			(raw as Dictionary)["state"] = "LOCKED"
			(raw as Dictionary)["module_id"] = "doorway_frame_blocked_1x1"
			return true
	return false


func _stamp_hatch_portal(layout: Dictionary) -> bool:
	var plan: Dictionary = layout.get("structural_plan", {}) as Dictionary
	var edges: Dictionary = plan.get("edges", {}) as Dictionary
	var selected_key := ""
	for key in edges:
		var edge: Dictionary = edges[key] as Dictionary
		if str(edge.get("kind", "")) == "SOLID" and not bool(edge.get("exterior", false)):
			selected_key = str(key)
			edge["kind"] = "HATCH"
			edge["state"] = "HATCH"
			edge["module_id"] = "bulkhead_portal_2x1"
			edge["portal"] = true
			edge["wrapper_required"] = true
			edge["placement_required"] = true
			break
	if selected_key.is_empty():
		return false
	var placements: Array = plan.get("placements", []) as Array
	for raw in placements:
		if raw is Dictionary and str((raw as Dictionary).get("edge_key", (raw as Dictionary).get("key", ""))) == selected_key:
			(raw as Dictionary)["kind"] = "HATCH"
			(raw as Dictionary)["state"] = "HATCH"
			(raw as Dictionary)["module_id"] = "bulkhead_portal_2x1"
			(raw as Dictionary)["portal"] = true
			(raw as Dictionary)["wrapper_required"] = true
			(raw as Dictionary)["placement_required"] = true
			return true
	return false


func _fail(reason: String) -> void:
	push_error("BUILDER AUTHORED PORTALS FAIL %s" % reason)
	quit(1)
