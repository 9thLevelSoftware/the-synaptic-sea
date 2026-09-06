extends RefCounted
class_name StructuralRebuildCollisionQuery

## Exact candidate-only collision utility for P17 preparation. This helper does
## not inspect the live scene, bind gameplay ownership, or authorize rebuilding.
## Callers supply world-space Shape3D/Transform3D descriptors and must combine a
## clear result with their separate identity, topology, and base-world checks.

const CANDIDATE_LAYER: int = 1
const MAX_INTERSECTIONS: int = 32
const RIGID_BASIS_EPSILON: float = 0.00001

var _active_private_rid_count: int = 0


func check_overlap(
        candidate_shapes: Array[Dictionary],
        query_shapes: Array[Dictionary]) -> Dictionary:
    var validation: Dictionary = _validate_descriptor_array(candidate_shapes, "candidate")
    if not bool(validation.get("ok", false)):
        return validation
    validation = _validate_descriptor_array(query_shapes, "query")
    if not bool(validation.get("ok", false)):
        return validation
    var context: Dictionary = _create_candidate_space(candidate_shapes)
    if not bool(context.get("ok", false)):
        return context
    var state: PhysicsDirectSpaceState3D = context.get("state") as PhysicsDirectSpaceState3D
    for query_index in range(query_shapes.size()):
        var descriptor: Dictionary = query_shapes[query_index]
        var hits: Array[Dictionary] = state.intersect_shape(
            _make_query(descriptor, Vector3.ZERO), MAX_INTERSECTIONS)
        if not hits.is_empty():
            var first_hit: Dictionary = hits[0]
            return _finish(context, {
                "ok": true,
                "supported": true,
                "pending": false,
                "overlap": true,
                "query_index": query_index,
                "candidate_shape_index": int(first_hit.get("shape", -1)),
            })
    return _finish(context, {
        "ok": true,
        "supported": true,
        "pending": false,
        "overlap": false,
        "query_index": -1,
        "candidate_shape_index": -1,
    })


## Each path entry is the same exact moving Shape3D at an exact world transform.
## Every waypoint is intersected first, including both ends of zero-length paths.
## Non-zero segments then use continuous cast_motion at the unchanged basis.
func check_path_clear(
        candidate_shapes: Array[Dictionary],
        path_shapes: Array[Dictionary]) -> Dictionary:
    var validation: Dictionary = _validate_descriptor_array(candidate_shapes, "candidate")
    if not bool(validation.get("ok", false)):
        return validation
    validation = _validate_descriptor_array(path_shapes, "path")
    if not bool(validation.get("ok", false)):
        return validation
    if path_shapes.size() < 2:
        return _invalid("path_requires_start_and_final", path_shapes.size())
    var moving_shape: Shape3D = path_shapes[0].get("shape") as Shape3D
    var moving_basis: Basis = (path_shapes[0].get("transform") as Transform3D).basis
    for waypoint_index in range(1, path_shapes.size()):
        var descriptor: Dictionary = path_shapes[waypoint_index]
        if descriptor.get("shape") != moving_shape:
            return _invalid("path_shape_changed", waypoint_index)
        var transform: Transform3D = descriptor.get("transform") as Transform3D
        if moving_basis != transform.basis:
            return _unsupported("path_rotation_change_unsupported", false, waypoint_index)
        var prior_transform: Transform3D = path_shapes[waypoint_index - 1].get(
            "transform") as Transform3D
        if not (transform.origin - prior_transform.origin).is_finite():
            return _invalid("invalid_path_motion", waypoint_index - 1)
    var context: Dictionary = _create_candidate_space(candidate_shapes)
    if not bool(context.get("ok", false)):
        return context
    var state: PhysicsDirectSpaceState3D = context.get("state") as PhysicsDirectSpaceState3D
    var first_endpoint_hit: Dictionary = {}
    for waypoint_index in range(path_shapes.size()):
        var hits: Array[Dictionary] = state.intersect_shape(
            _make_query(path_shapes[waypoint_index], Vector3.ZERO), MAX_INTERSECTIONS)
        if first_endpoint_hit.is_empty() and not hits.is_empty():
            first_endpoint_hit = {
                "waypoint_index": waypoint_index,
                "candidate_shape_index": int(hits[0].get("shape", -1)),
            }
    if not first_endpoint_hit.is_empty():
        return _finish(context, {
            "ok": true,
            "supported": true,
            "pending": false,
            "clear": false,
            "phase": "endpoint",
            "waypoint_index": int(first_endpoint_hit.get("waypoint_index", -1)),
            "segment_index": -1,
            "candidate_shape_index": int(first_endpoint_hit.get("candidate_shape_index", -1)),
            "safe_fraction": 0.0,
            "unsafe_fraction": 0.0,
            "endpoint_checks": path_shapes.size(),
            "motion_casts": 0,
        })
    var motion_casts: int = 0
    for segment_index in range(path_shapes.size() - 1):
        var start_transform: Transform3D = path_shapes[segment_index].get("transform") as Transform3D
        var final_transform: Transform3D = path_shapes[segment_index + 1].get("transform") as Transform3D
        var motion: Vector3 = final_transform.origin - start_transform.origin
        if motion == Vector3.ZERO:
            continue
        motion_casts += 1
        var fractions: PackedFloat32Array = state.cast_motion(
            _make_query(path_shapes[segment_index], motion))
        if not _cast_fractions_are_valid(fractions):
            return _finish(context, _unsupported(
                "physics_query_invalid_result", true, segment_index))
        if fractions[0] < 1.0 or fractions[1] < 1.0:
            return _finish(context, {
                "ok": true,
                "supported": true,
                "pending": false,
                "clear": false,
                "phase": "motion",
                "waypoint_index": -1,
                "segment_index": segment_index,
                "candidate_shape_index": -1,
                "safe_fraction": float(fractions[0]),
                "unsafe_fraction": float(fractions[1]),
                "endpoint_checks": path_shapes.size(),
                "motion_casts": motion_casts,
            })
        # Nonzero motions below the backend's approximate-zero resolution were
        # cast, but a clear fraction cannot safely authorize sub-resolution
        # geometry. Fail closed after the real cast rather than skipping it.
        if motion.is_zero_approx():
            var unresolved: Dictionary = _unsupported(
                "motion_below_query_resolution", false, segment_index)
            unresolved["endpoint_checks"] = path_shapes.size()
            unresolved["motion_casts"] = motion_casts
            return _finish(context, unresolved)
    return _finish(context, {
        "ok": true,
        "supported": true,
        "pending": false,
        "clear": true,
        "phase": "clear",
        "waypoint_index": -1,
        "segment_index": -1,
        "candidate_shape_index": -1,
        "safe_fraction": 1.0,
        "unsafe_fraction": 1.0,
        "endpoint_checks": path_shapes.size(),
        "motion_casts": motion_casts,
    })


func active_private_rid_count_for_validation() -> int:
    return _active_private_rid_count


func _create_candidate_space(candidate_shapes: Array[Dictionary]) -> Dictionary:
    if not ClassDB.class_has_method("PhysicsServer3D", "space_get_direct_state", true) \
            or not ClassDB.class_has_method("PhysicsDirectSpaceState3D", "intersect_shape", true) \
            or not ClassDB.class_has_method("PhysicsDirectSpaceState3D", "cast_motion", true):
        return _unsupported("physics_query_unavailable", true)
    var space: RID = PhysicsServer3D.space_create()
    if not space.is_valid():
        return _unsupported("physics_query_unavailable", true)
    _active_private_rid_count += 1
    var context: Dictionary = {"space": space, "body": RID()}
    PhysicsServer3D.space_set_active(space, true)
    var body: RID = PhysicsServer3D.body_create()
    if not body.is_valid():
        _cleanup(context)
        return _unsupported("physics_query_unavailable", true)
    _active_private_rid_count += 1
    context["body"] = body
    PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
    PhysicsServer3D.body_set_collision_layer(body, CANDIDATE_LAYER)
    PhysicsServer3D.body_set_collision_mask(body, 0)
    for descriptor in candidate_shapes:
        var shape: Shape3D = descriptor.get("shape") as Shape3D
        var transform: Transform3D = descriptor.get("transform") as Transform3D
        PhysicsServer3D.body_add_shape(body, shape.get_rid(), transform)
    PhysicsServer3D.body_set_state(
        body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D.IDENTITY)
    PhysicsServer3D.body_set_space(body, space)
    var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
    if state == null:
        _cleanup(context)
        return _unsupported("physics_query_unavailable", true)
    context["ok"] = true
    context["state"] = state
    return context


func _make_query(descriptor: Dictionary, motion: Vector3) -> PhysicsShapeQueryParameters3D:
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = descriptor.get("shape") as Shape3D
    query.transform = descriptor.get("transform") as Transform3D
    query.motion = motion
    query.margin = 0.0
    query.collision_mask = CANDIDATE_LAYER
    query.collide_with_bodies = true
    query.collide_with_areas = false
    return query


func _finish(context: Dictionary, result: Dictionary) -> Dictionary:
    _cleanup(context)
    return result


func _cleanup(context: Dictionary) -> void:
    var body: RID = context.get("body", RID()) as RID
    if body.is_valid():
        PhysicsServer3D.free_rid(body)
        _active_private_rid_count -= 1
    var space: RID = context.get("space", RID()) as RID
    if space.is_valid():
        PhysicsServer3D.free_rid(space)
        _active_private_rid_count -= 1
    _active_private_rid_count = maxi(_active_private_rid_count, 0)


func _validate_descriptor_array(descriptors: Array[Dictionary], label: String) -> Dictionary:
    if descriptors.is_empty():
        return _invalid("missing_%s_shapes" % label, -1)
    for index in range(descriptors.size()):
        var descriptor: Dictionary = descriptors[index]
        if descriptor.size() != 2 or not descriptor.has("shape") or not descriptor.has("transform"):
            return _invalid("invalid_%s_descriptor" % label, index)
        var shape_variant: Variant = descriptor.get("shape")
        var transform_variant: Variant = descriptor.get("transform")
        if not shape_variant is Shape3D or not is_instance_valid(shape_variant):
            return _invalid("invalid_%s_shape" % label, index)
        var shape: Shape3D = shape_variant as Shape3D
        if not shape.get_rid().is_valid() or not _shape_is_supported_and_valid(shape):
            return _invalid("invalid_%s_shape" % label, index)
        if not transform_variant is Transform3D \
                or not _transform_is_finite_and_invertible(transform_variant as Transform3D):
            return _invalid("invalid_%s_transform" % label, index)
    return {"ok": true}


func _transform_is_finite_and_invertible(transform: Transform3D) -> bool:
    return transform.origin.is_finite() \
        and transform.basis.x.is_finite() \
        and transform.basis.y.is_finite() \
        and transform.basis.z.is_finite() \
        and _basis_is_rigid_rotation(transform.basis)


func _basis_is_rigid_rotation(basis: Basis) -> bool:
    return absf(basis.determinant() - 1.0) <= RIGID_BASIS_EPSILON \
        and absf(basis.x.length_squared() - 1.0) <= RIGID_BASIS_EPSILON \
        and absf(basis.y.length_squared() - 1.0) <= RIGID_BASIS_EPSILON \
        and absf(basis.z.length_squared() - 1.0) <= RIGID_BASIS_EPSILON \
        and absf(basis.x.dot(basis.y)) <= RIGID_BASIS_EPSILON \
        and absf(basis.x.dot(basis.z)) <= RIGID_BASIS_EPSILON \
        and absf(basis.y.dot(basis.z)) <= RIGID_BASIS_EPSILON


func _shape_is_supported_and_valid(shape: Shape3D) -> bool:
    if shape is BoxShape3D:
        var size: Vector3 = (shape as BoxShape3D).size
        return size.is_finite() and size.x > 0.0 and size.y > 0.0 and size.z > 0.0
    if shape is CapsuleShape3D:
        var capsule: CapsuleShape3D = shape as CapsuleShape3D
        return is_finite(capsule.radius) and capsule.radius > 0.0 \
            and is_finite(capsule.height) \
            and capsule.height >= capsule.radius * 2.0
    return false


func _cast_fractions_are_valid(fractions: PackedFloat32Array) -> bool:
    if fractions.size() != 2:
        return false
    var safe_fraction: float = fractions[0]
    var unsafe_fraction: float = fractions[1]
    return is_finite(safe_fraction) and is_finite(unsafe_fraction) \
        and safe_fraction >= 0.0 and safe_fraction <= unsafe_fraction \
        and unsafe_fraction <= 1.0


func _invalid(reason: String, index: int) -> Dictionary:
    return {
        "ok": false,
        "supported": false,
        "pending": false,
        "reason": reason,
        "descriptor_index": index,
    }


func _unsupported(reason: String, pending: bool, index: int = -1) -> Dictionary:
    return {
        "ok": false,
        "supported": false,
        "pending": pending,
        "reason": reason,
        "descriptor_index": index,
    }
