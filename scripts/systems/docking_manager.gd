extends RefCounted
class_name DockingManager

const DockEndpointAuthoringScript := preload("res://scripts/procgen/dock_endpoint_authoring.gd")
const DEFAULT_KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const PLAYER_CAPSULE_RADIUS: float = 0.35
const PLAYER_CAPSULE_HEIGHT: float = 1.6
const PLAYER_FLOOR_SNAP: float = 0.5

## Pure docking math + relationship bookkeeping. Aligns a mobile ship's dock
## port to a host ship's dock port (coincident position, opposing facing,
## yaw-only) and writes the parent/child fields already declared on ShipInstance.
## No scene-tree ownership: callers own add_child/remove_child of ship_roots.
##
## PORT-SPACE CONTRACT (important for the 5b integration):
##   - host_port is WORLD-space (the host is already placed in the world).
##   - mobile_port is MOBILE-LOCAL (relative to the mobile ship's own root); dock()
##     computes the mobile root's transform that brings it onto the host port.
## DockPorts.for_*() return SHIP-LOCAL descriptors. A caller docking a real, non-origin
## host must therefore lift the host's local port to world FIRST, e.g.
##   var hx := host_inst.scene_root.global_transform
##   var host_world := {"position": hx * local.position,
##                      "facing": (hx.basis * local.facing).normalized()}
## (host_inst.scene_root must be in the scene tree for global_transform to be valid).
## dock() deliberately stays scene-tree-free so it is pure/unit-testable; the lift is the
## integration layer's job. Passing a local host port for a non-origin host mis-places the
## mobile — that is a contract violation, not a dock() bug.

## Yaw (radians) that rotates `from` onto `to` in the X-Z plane.
static func _yaw_between(from: Vector3, to: Vector3) -> float:
	var a := atan2(from.x, from.z)
	var b := atan2(to.x, to.z)
	return b - a

static func compute_mobile_transform(host_port: Dictionary, mobile_port: Dictionary) -> Transform3D:
	var host_pos: Vector3 = host_port.get("position", Vector3.ZERO)
	var host_facing: Vector3 = (host_port.get("facing", Vector3.FORWARD) as Vector3).normalized()
	var local_pos: Vector3 = mobile_port.get("position", Vector3.ZERO)
	var local_facing: Vector3 = (mobile_port.get("facing", Vector3.FORWARD) as Vector3).normalized()
	# Rotate the mobile so its local port facing becomes the OPPOSITE of the host facing.
	var target_facing: Vector3 = -host_facing
	var yaw: float = _yaw_between(local_facing, target_facing)
	var basis := _exact_cardinal_basis(local_facing, target_facing)
	# Translate so the (rotated) local port position lands on the host port position.
	var origin: Vector3 = host_pos - (basis * local_pos)
	return Transform3D(basis, origin)

static func _exact_cardinal_basis(from: Vector3, to: Vector3) -> Basis:
	var from_cardinal: Vector3 = _cardinal(from)
	var to_cardinal: Vector3 = _cardinal(to)
	var from_index: int = _cardinal_index(from_cardinal)
	var to_index: int = _cardinal_index(to_cardinal)
	if from_index < 0 or to_index < 0:
		return Basis(Vector3.UP, _yaw_between(from, to))
	var quarter_turns: int = posmod(to_index - from_index, 4)
	match quarter_turns:
		1:
			return Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3(1.0, 0.0, 0.0))
		2:
			return Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, -1.0))
		3:
			return Basis(Vector3(0.0, 0.0, 1.0), Vector3.UP, Vector3(-1.0, 0.0, 0.0))
		_:
			return Basis.IDENTITY

static func _cardinal_index(value: Vector3) -> int:
	if value == Vector3(0.0, 0.0, 1.0):
		return 0
	if value == Vector3(1.0, 0.0, 0.0):
		return 1
	if value == Vector3(0.0, 0.0, -1.0):
		return 2
	if value == Vector3(-1.0, 0.0, 0.0):
		return 3
	return -1

static func _port_valid(p: Dictionary) -> bool:
	return p.has("position") and p.has("facing") \
		and typeof(p["position"]) == TYPE_VECTOR3 and typeof(p["facing"]) == TYPE_VECTOR3 \
		and (p["facing"] as Vector3).length() > 0.0001

static func dock(host_inst, mobile_inst, host_port: Dictionary, mobile_port: Dictionary) -> Dictionary:
	# Reject null insts and self-docking (a ship docking to itself would create a
	# self-referential parent_ship/docked_ships cycle).
	if host_inst == null or mobile_inst == null or host_inst == mobile_inst:
		return {"success": false, "reason": "dock_failed"}
	if not _port_valid(host_port) or not _port_valid(mobile_port):
		return {"success": false, "reason": "dock_failed"}
	if not ("scene_root" in mobile_inst):
		return {"success": false, "reason": "dock_failed"}
	var root = mobile_inst.scene_root
	if not is_instance_valid(root) or not (root is Node3D):
		return {"success": false, "reason": "dock_failed"}
	# Registered production endpoints are a pre-mutation transaction. Legacy
	# hand-built pure-model fixtures remain supported only when neither descriptor
	# claims a registered endpoint.
	if host_port.has("endpoint_id") or mobile_port.has("endpoint_id"):
		if not host_port.has("endpoint_id") or not mobile_port.has("endpoint_id") \
				or not ("built_layout" in host_inst) or not ("built_layout" in mobile_inst):
			return {"success": false, "reason": "dock_endpoint_missing"}
		var host_root = host_inst.scene_root
		if not is_instance_valid(host_root) or not (host_root is Node3D):
			return {"success": false, "reason": "dock_host_missing"}
		var host_transform: Transform3D = (host_root as Node3D).global_transform \
			if (host_root as Node3D).is_inside_tree() else (host_root as Node3D).transform
		var preflight: Dictionary = preflight_registered_pair(
			host_inst.built_layout, mobile_inst.built_layout,
			host_transform, host_port, mobile_port)
		if not bool(preflight.get("ok", false)):
			var failure: Dictionary = preflight.duplicate(true)
			failure["success"] = false
			failure["reason"] = str(preflight.get("reason", "dock_preflight_failed"))
			return failure
	# Sever any existing dock relationship first so the previous host's
	# docked_ships list does not retain a stale reference to this mobile ship.
	if mobile_inst.parent_ship != null:
		undock(mobile_inst)
	# host_port is WORLD-space per the port-space contract (see class docstring);
	# mobile_port is mobile-local. compute_mobile_transform yields the mobile root transform.
	(root as Node3D).transform = compute_mobile_transform(host_port, mobile_port)
	mobile_inst.parent_ship = host_inst
	if not host_inst.docked_ships.has(mobile_inst):
		host_inst.docked_ships.append(mobile_inst)
	mobile_inst.docking_ports = [{"host_port": host_port, "mobile_port": mobile_port}]
	return {"success": true, "reason": "ok"}

## Lifts a ship-LOCAL dock port to WORLD space via the host's placed transform.
## host_inst.scene_root must be in the scene tree for global_transform to be valid.
## Returns {} when the host has no valid in-tree scene_root or local_port is empty.
static func host_port_to_world(host_inst, local_port: Dictionary) -> Dictionary:
	if host_inst == null or local_port.is_empty():
		return {}
	if not ("scene_root" in host_inst):
		return {}
	var root = host_inst.scene_root
	if not is_instance_valid(root) or not (root is Node3D) or not (root as Node3D).is_inside_tree():
		return {}
	var x: Transform3D = (root as Node3D).global_transform
	var world_port: Dictionary = local_port.duplicate(true)
	world_port["position"] = x * (local_port.get("position", Vector3.ZERO) as Vector3)
	world_port["facing"] = (x.basis * (local_port.get("facing", Vector3.FORWARD) as Vector3)).normalized()
	return world_port


## Validates the complete registered pair before a mobile root is moved. Every
## positive-volume cross-hull collision must be between the two explicitly named
## join pieces and contained by the exact 0.2 m doorway seam slab.
static func preflight_registered_pair(
		host_layout: Dictionary, mobile_layout: Dictionary,
		host_transform: Transform3D, host_port: Dictionary,
		mobile_port: Dictionary) -> Dictionary:
	var catalog: Dictionary = _collision_catalog()
	if not bool(catalog.get("ok", false)):
		return {"ok": false, "reason": str(catalog.get("reason", "collision_projection_invalid"))}
	var projection: Dictionary = catalog.get("projection", {}) as Dictionary
	var host_verdict: Dictionary = DockEndpointAuthoringScript.validate_layout(
		host_layout, projection)
	var mobile_verdict: Dictionary = DockEndpointAuthoringScript.validate_layout(
		mobile_layout, projection)
	if not bool(host_verdict.get("ok", false)) or not bool(mobile_verdict.get("ok", false)):
		return {"ok": false, "reason": "invalid_registered_endpoint"}
	if str(host_port.get("endpoint_id", "")) != str((host_verdict.endpoint as Dictionary).get("endpoint_id", "")) \
			or str(mobile_port.get("endpoint_id", "")) != str((mobile_verdict.endpoint as Dictionary).get("endpoint_id", "")):
		return {"ok": false, "reason": "endpoint_identity_mismatch"}
	if not _port_valid(host_port) or not _port_valid(mobile_port):
		return {"ok": false, "reason": "invalid_port_transform"}
	var mobile_transform: Transform3D = compute_mobile_transform(host_port, mobile_port)
	var host_facing: Vector3 = _cardinal(host_port.get("facing", Vector3.ZERO) as Vector3)
	var mobile_facing: Vector3 = _cardinal(
		mobile_transform.basis * (mobile_port.get("facing", Vector3.ZERO) as Vector3))
	if host_facing == Vector3.ZERO or mobile_facing != -host_facing:
		return {"ok": false, "reason": "normals_not_opposed"}
	var host_boxes: Dictionary = _layout_collision_boxes(host_layout, host_transform, projection)
	var mobile_boxes: Dictionary = _layout_collision_boxes(mobile_layout, mobile_transform, projection)
	if not bool(host_boxes.get("ok", false)) or not bool(mobile_boxes.get("ok", false)):
		return host_boxes if not bool(host_boxes.get("ok", false)) else mobile_boxes
	var collision_verdict: Dictionary = DockEndpointAuthoringScript \
		.validate_projected_cross_hull_boxes(host_boxes.boxes, mobile_boxes.boxes,
			host_port.get("position", Vector3.ZERO) as Vector3)
	if not bool(collision_verdict.get("ok", false)):
		return collision_verdict
	var seam: AABB = collision_verdict.get("seam_envelope", AABB()) as AABB
	var join_overlap_count: int = int(collision_verdict.get("join_overlap_count", 0))
	var capsule_clear: bool = _registered_capsule_path_clear(
		host_verdict.endpoint, mobile_verdict.endpoint, host_transform,
		mobile_transform, host_facing, host_boxes.boxes, mobile_boxes.boxes)
	if not capsule_clear:
		return {"ok": false, "reason": "open_capsule_blocked"}
	return {
		"ok": true,
		"reason": "ok",
		"mobile_transform": mobile_transform,
		"non_join_overlap_count": 0,
		"join_overlap_count": join_overlap_count,
		"open_capsule_clear": true,
		"seam_envelope": seam,
		"host_collision_boxes": host_boxes.boxes,
		"mobile_collision_boxes": mobile_boxes.boxes,
	}


## Validates the authored player capsule at a ship-local fresh-spawn pose using
## the same live-checked collision projection as registered docking. The capsule
## must have no positive-volume hull intersection and must have floor support.
static func validate_registered_spawn_clear(
		layout: Dictionary, root_transform: Transform3D,
		local_position: Vector3) -> Dictionary:
	if not local_position.is_finite() or not root_transform.is_finite():
		return {"ok": false, "reason": "spawn_transform_invalid"}
	var catalog: Dictionary = _collision_catalog()
	if not bool(catalog.get("ok", false)):
		return catalog
	var projection: Dictionary = catalog.get("projection", {}) as Dictionary
	var endpoint_verdict: Dictionary = DockEndpointAuthoringScript.validate_layout(
		layout, projection)
	if not bool(endpoint_verdict.get("ok", false)):
		return {"ok": false, "reason": "spawn_layout_invalid",
			"detail": str(endpoint_verdict.get("reason", ""))}
	var collision_boxes: Dictionary = _layout_collision_boxes(
		layout, root_transform, projection)
	if not bool(collision_boxes.get("ok", false)):
		return collision_boxes
	var world_position: Vector3 = root_transform * local_position
	var capsule_bounds := AABB(
		world_position + Vector3(-PLAYER_CAPSULE_RADIUS, 0.0,
			-PLAYER_CAPSULE_RADIUS),
		Vector3(PLAYER_CAPSULE_RADIUS * 2.0, PLAYER_CAPSULE_HEIGHT,
			PLAYER_CAPSULE_RADIUS * 2.0))
	for box_variant in collision_boxes.get("boxes", []):
		var box: Dictionary = box_variant
		var intersection: AABB = _positive_intersection(
			capsule_bounds, box.get("aabb", AABB()) as AABB)
		if intersection.size != Vector3.ZERO:
			return {"ok": false, "reason": "spawn_capsule_blocked",
				"placement_id": str(box.get("placement_id", "")),
				"shape_name": str(box.get("shape_name", "")),
				"intersection_position": intersection.position,
				"intersection_size": intersection.size}
	if not _capsule_has_floor_support(
			world_position, collision_boxes.get("boxes", [])):
		return {"ok": false, "reason": "spawn_floor_unsupported"}
	return {"ok": true, "reason": "ok", "world_position": world_position}


static func _layout_collision_boxes(
		layout: Dictionary, root_transform: Transform3D,
		projection: Dictionary) -> Dictionary:
	var endpoint: Dictionary = DockEndpointAuthoringScript.endpoint(layout, projection)
	var join_ids: Array = endpoint.get("join_piece_placement_ids", []) as Array
	var plan: Dictionary = layout.get("structural_plan", {}) as Dictionary
	var boxes: Array[Dictionary] = []
	var validated_modules: Dictionary = {}
	for group in ["floor_placements", "placements", "ceiling_placements"]:
		for record_variant in plan.get(group, []):
			if not record_variant is Dictionary:
				return {"ok": false, "reason": "malformed_collision_record"}
			var record: Dictionary = record_variant
			var module_id: String = str(record.get("module_id", ""))
			if module_id.is_empty():
				continue
			var module: Dictionary = _projection_module(projection, module_id)
			if module.is_empty():
				return {"ok": false, "reason": "collision_projection_module_missing"}
			if not validated_modules.has(module_id):
				var live_verdict: Dictionary = validate_materialized_wrapper(
					str(module.get("wrapper_scene", "")), module)
				if not bool(live_verdict.get("ok", false)):
					return live_verdict
				validated_modules[module_id] = true
			var placement_id: String = str(record.get("placement_id", record.get("id", "")))
			var placement_basis_variant: Variant = _exact_cardinal_yaw_basis(
				float(record.get("yaw_degrees", 0.0)))
			if not placement_basis_variant is Basis:
				return {"ok": false, "reason": "non_cardinal_hull_transform"}
			var placement_transform := Transform3D(
				placement_basis_variant as Basis,
				_as_vector3(record.get("position", Vector3.ZERO)))
			var append_result: Dictionary = _append_projected_collision_boxes(
				module, root_transform * placement_transform, boxes, placement_id,
				join_ids.has(placement_id))
			if not bool(append_result.get("ok", false)):
				return append_result
	return {"ok": true, "boxes": boxes}


static func _exact_cardinal_yaw_basis(yaw_degrees: float) -> Variant:
	var normalized: float = fposmod(yaw_degrees, 360.0)
	if normalized == 0.0:
		return Basis.IDENTITY
	if normalized == 90.0:
		return Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3(1.0, 0.0, 0.0))
	if normalized == 180.0:
		return Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, -1.0))
	if normalized == 270.0:
		return Basis(Vector3(0.0, 0.0, 1.0), Vector3.UP, Vector3(-1.0, 0.0, 0.0))
	return null


static func _append_projected_collision_boxes(
		module: Dictionary, parent_transform: Transform3D,
		boxes: Array[Dictionary], placement_id: String,
		join_piece: bool) -> Dictionary:
	for box_variant in module.get("boxes", []):
		if not box_variant is Dictionary:
			return {"ok": false, "reason": "collision_projection_box_invalid"}
		var box: Dictionary = box_variant
		var local_transform: Transform3D = _projection_box_transform(box)
		var size: Vector3 = _as_vector3(box.get("dimensions", []))
		if not local_transform.is_finite() or not size.is_finite():
			return {"ok": false, "reason": "collision_projection_box_invalid"}
		boxes.append({
			"placement_id": placement_id,
			"shape_name": str(box.get("shape_path", "")),
			"join": join_piece,
			"aabb": parent_transform * local_transform * AABB(-size * 0.5, size),
		})
	return {"ok": true}


static func _collision_catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_KIT_PATH))
	if not parsed is Dictionary:
		return {"ok": false, "reason": "collision_wrapper_catalog_missing"}
	var kit: Dictionary = parsed
	var projection_variant: Variant = kit.get("dock_collision_projection_v1", null)
	if not projection_variant is Dictionary:
		return {"ok": false, "reason": "collision_projection_missing"}
	var projection: Dictionary = projection_variant
	var projection_verdict: Dictionary = DockEndpointAuthoringScript.validate_collision_projection(
		projection)
	if not bool(projection_verdict.get("ok", false)):
		return projection_verdict
	var selected: Dictionary = {}
	for module_variant in kit.get("modules", []):
		if not module_variant is Dictionary:
			return {"ok": false, "reason": "collision_wrapper_catalog_invalid"}
		var module: Dictionary = module_variant
		var module_id: String = str(module.get("module_id", ""))
		var wrapper_scene: String = str(module.get("godot_wrapper_scene", ""))
		if module_id.is_empty() or wrapper_scene.is_empty() or selected.has(module_id):
			return {"ok": false, "reason": "collision_wrapper_catalog_invalid"}
		selected[module_id] = wrapper_scene
	var projected_modules: Dictionary = projection.get("modules", {}) as Dictionary
	if selected.size() != projected_modules.size():
		return {"ok": false, "reason": "collision_projection_catalog_mismatch"}
	for module_id in selected:
		var projected: Dictionary = _projection_module(projection, str(module_id))
		if projected.is_empty() or str(projected.get("wrapper_scene", "")) \
				!= str(selected[module_id]):
			return {"ok": false, "reason": "collision_projection_catalog_mismatch"}
	return {"ok": true, "reason": "ok", "projection": projection}


static func _projection_module(projection: Dictionary, module_id: String) -> Dictionary:
	var modules_variant: Variant = projection.get("modules", null)
	if not modules_variant is Dictionary:
		return {}
	var module_variant: Variant = (modules_variant as Dictionary).get(module_id, null)
	return module_variant as Dictionary if module_variant is Dictionary else {}


static func validate_materialized_wrapper(
		scene_path: String, projected_module: Dictionary) -> Dictionary:
	if scene_path.is_empty() or scene_path != str(projected_module.get("wrapper_scene", "")) \
			or not ResourceLoader.exists(scene_path):
		return {"ok": false, "reason": "collision_wrapper_missing"}
	var resource: Resource = ResourceLoader.load(scene_path)
	if not resource is PackedScene:
		return {"ok": false, "reason": "collision_wrapper_invalid"}
	var wrapper: Node = (resource as PackedScene).instantiate()
	var live_boxes: Array[Dictionary] = []
	var collect: Dictionary = _collect_live_collision_boxes(
		wrapper, Transform3D.IDENTITY, "", live_boxes)
	wrapper.free()
	if not bool(collect.get("ok", false)):
		return collect
	live_boxes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("shape_path", "")) < str(b.get("shape_path", "")))
	var expected_variant: Variant = projected_module.get("boxes", null)
	if not expected_variant is Array or (expected_variant as Array).size() != live_boxes.size():
		return {"ok": false, "reason": "collision_projection_live_shape_count"}
	for index in range(live_boxes.size()):
		var live: Dictionary = live_boxes[index]
		var expected_variant_box: Variant = (expected_variant as Array)[index]
		if not expected_variant_box is Dictionary:
			return {"ok": false, "reason": "collision_projection_box_invalid"}
		var expected: Dictionary = expected_variant_box
		if str(live.get("shape_path", "")) != str(expected.get("shape_path", "")):
			return {"ok": false, "reason": "collision_projection_live_path"}
		for field in ["basis_f32_bits", "origin_f32_bits", "dimensions_f32_bits"]:
			if live.get(field, null) != expected.get(field, null):
				return {"ok": false, "reason": "collision_projection_live_%s" % field,
					"shape_path": str(live.get("shape_path", "")),
					"live": live.get(field, null), "expected": expected.get(field, null)}
	var content: String = _collision_content_string(live_boxes)
	if content.is_empty() or content.sha256_text() != str(
			projected_module.get("content_sha256", "")):
		return {"ok": false, "reason": "collision_projection_live_fingerprint"}
	return {"ok": true, "reason": "ok", "boxes": live_boxes,
		"content_sha256": content.sha256_text()}


static func _collect_live_collision_boxes(
		node: Node, parent_transform: Transform3D, path: String,
		boxes: Array[Dictionary]) -> Dictionary:
	var current_transform: Transform3D = parent_transform
	# The PackedScene root defines wrapper-local space; its transform is not part
	# of a shape path. Every descendant Node3D transform is composed exactly.
	if not path.is_empty() and node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is CollisionShape3D and not (node as CollisionShape3D).disabled:
		var shape: Shape3D = (node as CollisionShape3D).shape
		if not shape is BoxShape3D:
			return {"ok": false, "reason": "non_box_hull_collision"}
		var size: Vector3 = (shape as BoxShape3D).size
		boxes.append({
			"shape_path": path,
			"basis_f32_bits": _basis_f32_bits(current_transform.basis),
			"origin_f32_bits": _vector_f32_bits(current_transform.origin),
			"dimensions_f32_bits": _vector_f32_bits(size),
		})
	for child in node.get_children():
		var child_path: String = str(child.name) if path.is_empty() \
			else "%s/%s" % [path, str(child.name)]
		var child_result: Dictionary = _collect_live_collision_boxes(
			child, current_transform, child_path, boxes)
		if not bool(child_result.get("ok", false)):
			return child_result
	return {"ok": true}


static func _projection_box_transform(box: Dictionary) -> Transform3D:
	var values_variant: Variant = box.get("basis", null)
	if not values_variant is Array or (values_variant as Array).size() != 9:
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var values: Array = values_variant
	return Transform3D(Basis(
		Vector3(float(values[0]), float(values[1]), float(values[2])),
		Vector3(float(values[3]), float(values[4]), float(values[5])),
		Vector3(float(values[6]), float(values[7]), float(values[8]))),
		_as_vector3(box.get("origin", [])))


static func _basis_f32_bits(value: Basis) -> Array[String]:
	var result: Array[String] = []
	for component in [
		value.x.x, value.x.y, value.x.z,
		value.y.x, value.y.y, value.y.z,
		value.z.x, value.z.y, value.z.z,
	]:
		result.append(_f32_bits(float(component)))
	return result


static func _vector_f32_bits(value: Vector3) -> Array[String]:
	return [_f32_bits(value.x), _f32_bits(value.y), _f32_bits(value.z)]


static func _f32_bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return "%08x" % bytes.decode_u32(0)


static func _collision_content_string(boxes: Array[Dictionary]) -> String:
	var result: String = "dock-collision-content-v1\n"
	for box in boxes:
		var shape_path: String = str(box.get("shape_path", ""))
		if shape_path.is_empty() or shape_path.contains("\n") \
				or shape_path.contains("\r") or shape_path.contains("="):
			return ""
		result += "path=%s\n" % shape_path
		for field in ["basis_f32_bits", "origin_f32_bits", "dimensions_f32_bits"]:
			var values_variant: Variant = box.get(field, null)
			if not values_variant is Array:
				return ""
			var label: String = str(field).trim_suffix("_f32_bits")
			result += "%s=%s\n" % [label, ",".join(values_variant as Array)]
	return result


static func _seam_envelope(
		host_port: Dictionary, host_boxes: Array,
		mobile_boxes: Array) -> AABB:
	var center: Vector3 = host_port.get("position", Vector3.ZERO) as Vector3
	var result := AABB(center, Vector3.ZERO)
	var has_overlap: bool = false
	for host_variant in host_boxes:
		var host: Dictionary = host_variant
		if not bool(host.get("join", false)):
			continue
		for mobile_variant in mobile_boxes:
			var mobile: Dictionary = mobile_variant
			if not bool(mobile.get("join", false)):
				continue
			var overlap: AABB = _positive_intersection(host.aabb, mobile.aabb)
			if overlap.size == Vector3.ZERO:
				continue
			result = overlap if not has_overlap else result.merge(overlap)
			has_overlap = true
	return result


static func _positive_intersection(a: AABB, b: AABB) -> AABB:
	var minimum := Vector3(maxf(a.position.x, b.position.x),
		maxf(a.position.y, b.position.y), maxf(a.position.z, b.position.z))
	var maximum := Vector3(minf(a.end.x, b.end.x),
		minf(a.end.y, b.end.y), minf(a.end.z, b.end.z))
	if maximum.x <= minimum.x or maximum.y <= minimum.y or maximum.z <= minimum.z:
		return AABB()
	return AABB(minimum, maximum - minimum)


static func _contains_aabb(outer: AABB, inner: AABB) -> bool:
	return inner.position.x >= outer.position.x and inner.position.y >= outer.position.y \
		and inner.position.z >= outer.position.z and inner.end.x <= outer.end.x \
		and inner.end.y <= outer.end.y and inner.end.z <= outer.end.z


static func _registered_capsule_path_clear(
		host_endpoint: Dictionary, mobile_endpoint: Dictionary,
		host_transform: Transform3D, mobile_transform: Transform3D,
		host_facing: Vector3, host_boxes: Array, mobile_boxes: Array) -> bool:
	var host_position: Vector3 = host_transform * _as_vector3(
		host_endpoint.get("local_position", []))
	var host_interior: Vector3 = host_transform * _as_vector3(
		host_endpoint.get("interior_clearance_point_local", []))
	var mobile_interior: Vector3 = mobile_transform * _as_vector3(
		mobile_endpoint.get("interior_clearance_point_local", []))
	if not (host_interior != host_position and mobile_interior != host_position \
		and (host_interior - host_position).dot(host_facing) < 0.0 \
		and (mobile_interior - host_position).dot(host_facing) > 0.0):
		return false
	var minimum := Vector3(
		minf(host_interior.x, mobile_interior.x) - PLAYER_CAPSULE_RADIUS,
		minf(host_interior.y, mobile_interior.y),
		minf(host_interior.z, mobile_interior.z) - PLAYER_CAPSULE_RADIUS)
	var maximum := Vector3(
		maxf(host_interior.x, mobile_interior.x) + PLAYER_CAPSULE_RADIUS,
		maxf(host_interior.y, mobile_interior.y) + PLAYER_CAPSULE_HEIGHT,
		maxf(host_interior.z, mobile_interior.z) + PLAYER_CAPSULE_RADIUS)
	var swept_bounds := AABB(minimum, maximum - minimum)
	var all_boxes: Array = host_boxes + mobile_boxes
	for box_variant in all_boxes:
		var box: Dictionary = box_variant
		if _positive_intersection(swept_bounds, box.aabb).size != Vector3.ZERO:
			return false
	# Floor support is checked across the complete seam in both directions. The
	# capsule footprint, rather than a center ray, may bridge a narrow authored sill.
	for direction_index in range(2):
		var start: Vector3 = host_interior if direction_index == 0 else mobile_interior
		var finish: Vector3 = mobile_interior if direction_index == 0 else host_interior
		for step in range(17):
			var point: Vector3 = start.lerp(finish, float(step) / 16.0)
			if not _capsule_has_floor_support(point, all_boxes):
				return false
	return true


static func _capsule_has_floor_support(point: Vector3, boxes: Array) -> bool:
	for box_variant in boxes:
		var bounds: AABB = (box_variant as Dictionary).aabb
		if bounds.end.y > point.y or point.y - bounds.end.y > PLAYER_FLOOR_SNAP:
			continue
		var closest_x: float = clampf(point.x, bounds.position.x, bounds.end.x)
		var closest_z: float = clampf(point.z, bounds.position.z, bounds.end.z)
		var offset := Vector2(point.x - closest_x, point.z - closest_z)
		if offset.length_squared() <= PLAYER_CAPSULE_RADIUS * PLAYER_CAPSULE_RADIUS:
			return true
	return false


static func _cardinal(value: Vector3) -> Vector3:
	if absf(value.x) > absf(value.z):
		return Vector3(signf(value.x), 0.0, 0.0) if value.x != 0.0 else Vector3.ZERO
	return Vector3(0.0, 0.0, signf(value.z)) if value.z != 0.0 else Vector3.ZERO


static func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() == 3:
		return Vector3(float((value as Array)[0]), float((value as Array)[1]),
			float((value as Array)[2]))
	return Vector3.INF

static func undock(mobile_inst) -> Dictionary:
	if mobile_inst == null:
		return {"success": false, "reason": "dock_failed"}
	var host = mobile_inst.parent_ship
	if host == null:
		return {"success": true, "reason": "not_docked"}
	if host.docked_ships.has(mobile_inst):
		host.docked_ships.erase(mobile_inst)
	mobile_inst.parent_ship = null
	mobile_inst.docking_ports = []
	return {"success": true, "reason": "ok"}
