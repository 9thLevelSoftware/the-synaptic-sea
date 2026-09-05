extends SceneTree

const CollisionQueryScript := preload(
    "res://scripts/systems/structural_rebuild_collision_query.gd")

var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var collision_query = CollisionQueryScript.new()
    _check_rotated_overlap(collision_query)
    _check_continuous_paths(collision_query)
    await _check_live_world_isolation(collision_query)
    _check_invalid_descriptors(collision_query)
    _check_contract_boundaries(collision_query)
    _check_numeric_fail_closed(collision_query)
    if collision_query.active_private_rid_count_for_validation() != 0:
        _failures.append("private RIDs remained after all queries")
    if _failures.is_empty():
        print("STRUCTURAL REBUILD COLLISION QUERY PASS")
        quit(0)
        return
    print("STRUCTURAL REBUILD COLLISION QUERY FAIL %s" % " | ".join(_failures))
    quit(1)


func _check_rotated_overlap(collision_query) -> void:
    var candidate := BoxShape3D.new()
    candidate.size = Vector3(2.4, 2.0, 0.45)
    var candidate_transform := Transform3D(
        Basis(Vector3.UP, deg_to_rad(37.0)), Vector3(0.0, 1.0, 0.0))
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.32
    capsule.height = 1.7
    var capsule_basis := Basis(Vector3.FORWARD, deg_to_rad(-23.0))
    var overlap: Dictionary = collision_query.check_overlap(
        _typed([_descriptor(candidate, candidate_transform)]),
        _typed([_descriptor(capsule, Transform3D(
            capsule_basis, Vector3(0.25, 1.0, 0.05)))]))
    if not bool(overlap.get("ok", false)) or not bool(overlap.get("overlap", false)):
        _failures.append("tilted capsule missed rotated offset candidate")
    _expect_clean(collision_query, "rotated overlap")

    var clear: Dictionary = collision_query.check_overlap(
        _typed([_descriptor(candidate, candidate_transform)]),
        _typed([_descriptor(capsule, Transform3D(
            capsule_basis, Vector3(6.0, 1.0, 0.0)))]))
    if not bool(clear.get("ok", false)) or bool(clear.get("overlap", true)):
        _failures.append("separated rotated overlap control was blocked")
    _expect_clean(collision_query, "rotated overlap clear control")


func _check_continuous_paths(collision_query) -> void:
    var thin_wall := BoxShape3D.new()
    thin_wall.size = Vector3(0.06, 2.0, 2.0)
    var wall_basis := Basis(Vector3.UP, deg_to_rad(31.0))
    var candidate: Array[Dictionary] = [
        _descriptor(thin_wall, Transform3D(
            wall_basis, Vector3(3.0, 1.0, 0.0))),
    ]
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.28
    capsule.height = 1.65
    var capsule_basis := Basis(Vector3.FORWARD, deg_to_rad(-19.0))
    var middle_hit: Dictionary = collision_query.check_path_clear(candidate, _typed([
        _descriptor(capsule, Transform3D(
            capsule_basis, Vector3(0.0, 1.0, 0.0))),
        _descriptor(capsule, Transform3D(
            capsule_basis, Vector3(6.0, 1.0, 0.0))),
    ]))
    if not bool(middle_hit.get("ok", false)) \
            or bool(middle_hit.get("clear", true)) \
            or str(middle_hit.get("phase", "")) != "motion" \
            or int(middle_hit.get("endpoint_checks", 0)) != 2 \
            or int(middle_hit.get("motion_casts", 0)) != 1 \
            or float(middle_hit.get("safe_fraction", 1.0)) >= 1.0:
        _failures.append("continuous capsule cast missed 0.06m rotated middle wall")
    _expect_clean(collision_query, "continuous thin-wall cast")

    var clear_path: Dictionary = collision_query.check_path_clear(candidate, _typed([
        _descriptor(capsule, Transform3D(
            capsule_basis, Vector3(0.0, 1.0, 4.0))),
        _descriptor(capsule, Transform3D(
            capsule_basis, Vector3(6.0, 1.0, 4.0))),
    ]))
    if not bool(clear_path.get("ok", false)) \
            or not bool(clear_path.get("clear", false)) \
            or int(clear_path.get("endpoint_checks", 0)) != 2 \
            or int(clear_path.get("motion_casts", 0)) != 1:
        _failures.append("separated continuous path control was blocked")
    _expect_clean(collision_query, "continuous path clear control")

    var start_wall := BoxShape3D.new()
    start_wall.size = Vector3(1.0, 2.0, 1.0)
    var start_hit: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(start_wall, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))),
    ]), _typed([
        _descriptor(capsule, Transform3D(capsule_basis, Vector3(0.0, 1.0, 0.0))),
        _descriptor(capsule, Transform3D(capsule_basis, Vector3(6.0, 1.0, 0.0))),
    ]))
    if bool(start_hit.get("clear", true)) \
            or str(start_hit.get("phase", "")) != "endpoint" \
            or int(start_hit.get("waypoint_index", -1)) != 0 \
            or int(start_hit.get("endpoint_checks", 0)) != 2:
        _failures.append("exact path start overlap was not checked")
    _expect_clean(collision_query, "path start overlap")

    var end_wall := BoxShape3D.new()
    end_wall.size = Vector3(1.0, 2.0, 1.0)
    var end_hit: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(end_wall, Transform3D(Basis.IDENTITY, Vector3(6.0, 1.0, 0.0))),
    ]), _typed([
        _descriptor(capsule, Transform3D(capsule_basis, Vector3(0.0, 1.0, 0.0))),
        _descriptor(capsule, Transform3D(capsule_basis, Vector3(6.0, 1.0, 0.0))),
    ]))
    if bool(end_hit.get("clear", true)) \
            or str(end_hit.get("phase", "")) != "endpoint" \
            or int(end_hit.get("waypoint_index", -1)) != 1 \
            or int(end_hit.get("endpoint_checks", 0)) != 2:
        _failures.append("exact path final overlap was not checked before cast")
    _expect_clean(collision_query, "path final overlap")

    var zero_hit: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(start_wall, Transform3D(Basis.IDENTITY, Vector3(2.0, 1.0, 0.0))),
    ]), _typed([
        _descriptor(capsule, Transform3D(capsule_basis, Vector3(2.0, 1.0, 0.0))),
        _descriptor(capsule, Transform3D(capsule_basis, Vector3(2.0, 1.0, 0.0))),
    ]))
    if bool(zero_hit.get("clear", true)) \
            or str(zero_hit.get("phase", "")) != "endpoint" \
            or int(zero_hit.get("motion_casts", -1)) != 0:
        _failures.append("zero-length overlapping path was not checked exactly")
    _expect_clean(collision_query, "zero-length overlap")

    var zero_clear: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(start_wall, Transform3D(Basis.IDENTITY, Vector3(2.0, 1.0, 0.0))),
    ]), _typed([
        _descriptor(capsule, Transform3D(capsule_basis, Vector3(8.0, 1.0, 0.0))),
        _descriptor(capsule, Transform3D(capsule_basis, Vector3(8.0, 1.0, 0.0))),
    ]))
    if not bool(zero_clear.get("ok", false)) \
            or not bool(zero_clear.get("clear", false)) \
            or int(zero_clear.get("endpoint_checks", 0)) != 2 \
            or int(zero_clear.get("motion_casts", -1)) != 0:
        _failures.append("zero-length separated path control was not clear")
    _expect_clean(collision_query, "zero-length clear control")

    var tiny_wall := BoxShape3D.new()
    tiny_wall.size = Vector3(0.000002, 0.5, 0.5)
    var tiny_mover := BoxShape3D.new()
    tiny_mover.size = Vector3(0.000002, 0.1, 0.1)
    var tiny_start := Vector3(-0.000004, 0.0, 0.0)
    var tiny_final := Vector3(0.000004, 0.0, 0.0)
    var tiny_motion: Vector3 = tiny_final - tiny_start
    var tiny_hit: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(tiny_wall, Transform3D.IDENTITY),
    ]), _typed([
        _descriptor(tiny_mover, Transform3D(Basis.IDENTITY, tiny_start)),
        _descriptor(tiny_mover, Transform3D(Basis.IDENTITY, tiny_final)),
    ]))
    if not tiny_motion.is_zero_approx() \
            or bool(tiny_hit.get("ok", true)) \
            or bool(tiny_hit.get("pending", true)) \
            or str(tiny_hit.get("reason", "")) != "motion_below_query_resolution" \
            or int(tiny_hit.get("motion_casts", 0)) != 1:
        _failures.append("sub-resolution nonzero segment did not cast then fail closed")
    _expect_clean(collision_query, "sub-approx continuous cast")


func _check_live_world_isolation(collision_query) -> void:
    var unrelated_body := StaticBody3D.new()
    unrelated_body.collision_layer = 1
    unrelated_body.collision_mask = 0
    unrelated_body.transform = Transform3D(Basis.IDENTITY, Vector3(3.0, 1.0, 0.0))
    var unrelated_collision := CollisionShape3D.new()
    var unrelated_shape := BoxShape3D.new()
    unrelated_shape.size = Vector3(1.0, 2.0, 2.0)
    unrelated_collision.shape = unrelated_shape
    unrelated_body.add_child(unrelated_collision)
    root.add_child(unrelated_body)
    await physics_frame
    await physics_frame

    var distant_candidate := BoxShape3D.new()
    distant_candidate.size = Vector3(1.0, 2.0, 2.0)
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.28
    capsule.height = 1.65
    var isolated: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(distant_candidate, Transform3D(
            Basis.IDENTITY, Vector3(50.0, 1.0, 0.0))),
    ]), _typed([
        _descriptor(capsule, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))),
        _descriptor(capsule, Transform3D(Basis.IDENTITY, Vector3(6.0, 1.0, 0.0))),
    ]))
    if not bool(isolated.get("ok", false)) or not bool(isolated.get("clear", false)):
        _failures.append("private query included unrelated live-world collision layer")
    _expect_clean(collision_query, "live-world isolation")
    unrelated_body.queue_free()
    await process_frame


func _check_invalid_descriptors(collision_query) -> void:
    var box := BoxShape3D.new()
    box.size = Vector3.ONE
    var invalid_transform := Transform3D.IDENTITY
    invalid_transform.origin.x = INF
    var invalid: Dictionary = collision_query.check_overlap(_typed([
        _descriptor(box, invalid_transform),
    ]), _typed([
        _descriptor(box, Transform3D.IDENTITY),
    ]))
    if bool(invalid.get("ok", true)) \
            or bool(invalid.get("pending", true)) \
            or str(invalid.get("reason", "")) != "invalid_candidate_transform":
        _failures.append("non-finite candidate transform did not fail closed")
    _expect_clean(collision_query, "invalid transform")

    var malformed: Dictionary = collision_query.check_overlap(_typed([
        {"shape": box, "transform": Transform3D.IDENTITY, "extra": true},
    ]), _typed([
        _descriptor(box, Transform3D.IDENTITY),
    ]))
    if bool(malformed.get("ok", true)) \
            or str(malformed.get("reason", "")) != "invalid_candidate_descriptor":
        _failures.append("descriptor with non-contract keys did not fail closed")
    _expect_clean(collision_query, "malformed descriptor")

    var rotated_path: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(box, Transform3D(Basis.IDENTITY, Vector3(20.0, 0.0, 0.0))),
    ]), _typed([
        _descriptor(box, Transform3D(Basis.IDENTITY, Vector3.ZERO)),
        _descriptor(box, Transform3D(
            Basis(Vector3.UP, deg_to_rad(15.0)), Vector3.ONE)),
    ]))
    if bool(rotated_path.get("ok", true)) \
            or bool(rotated_path.get("pending", true)) \
            or str(rotated_path.get("reason", "")) != "path_rotation_change_unsupported":
        _failures.append("unrepresentable rotating path did not return unsupported")
    _expect_clean(collision_query, "rotating path unsupported")


func _check_contract_boundaries(collision_query) -> void:
    var box := BoxShape3D.new()
    box.size = Vector3.ONE
    var singleton: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(box, Transform3D(Basis.IDENTITY, Vector3(20.0, 0.0, 0.0))),
    ]), _typed([
        _descriptor(box, Transform3D.IDENTITY),
    ]))
    if bool(singleton.get("ok", true)) \
            or str(singleton.get("reason", "")) != "path_requires_start_and_final":
        _failures.append("singleton path did not fail its start/final contract")
    _expect_clean(collision_query, "singleton path")

    var tiny_rotation := Basis(Vector3.UP, 0.0000001)
    if tiny_rotation == Basis.IDENTITY:
        _failures.append("sub-approx rotation fixture collapsed to identity")
    var exact_basis: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(box, Transform3D(Basis.IDENTITY, Vector3(20.0, 0.0, 0.0))),
    ]), _typed([
        _descriptor(box, Transform3D.IDENTITY),
        _descriptor(box, Transform3D(tiny_rotation, Vector3.ONE)),
    ]))
    if bool(exact_basis.get("ok", true)) \
            or str(exact_basis.get("reason", "")) != "path_rotation_change_unsupported":
        _failures.append("sub-approx basis change was treated as unchanged")
    _expect_clean(collision_query, "exact path basis")

    var unsupported_shape := CylinderShape3D.new()
    var unsupported: Dictionary = collision_query.check_overlap(_typed([
        _descriptor(unsupported_shape, Transform3D.IDENTITY),
    ]), _typed([
        _descriptor(box, Transform3D.IDENTITY),
    ]))
    if bool(unsupported.get("ok", true)) \
            or str(unsupported.get("reason", "")) != "invalid_candidate_shape":
        _failures.append("unsupported shape class did not fail closed")
    _expect_clean(collision_query, "unsupported shape")

    var null_shape: Dictionary = collision_query.check_overlap(_typed([
        {"shape": null, "transform": Transform3D.IDENTITY},
    ]), _typed([
        _descriptor(box, Transform3D.IDENTITY),
    ]))
    if bool(null_shape.get("ok", true)) \
            or str(null_shape.get("reason", "")) != "invalid_candidate_shape":
        _failures.append("invalid shape resource did not fail closed")
    _expect_clean(collision_query, "invalid shape resource")

    var invalid_bases: Array[Basis] = [
        Basis.from_scale(Vector3(2.0, 1.0, 1.0)),
        Basis(
            Vector3(1.0, 0.0, 0.0),
            Vector3(0.25, 1.0, 0.0),
            Vector3(0.0, 0.0, 1.0)),
        Basis.from_scale(Vector3(-1.0, 1.0, 1.0)),
    ]
    var labels: PackedStringArray = PackedStringArray(["scaled", "sheared", "reflected"])
    for index in range(invalid_bases.size()):
        var invalid_transform: Dictionary = collision_query.check_overlap(_typed([
            _descriptor(box, Transform3D(invalid_bases[index], Vector3.ZERO)),
        ]), _typed([
            _descriptor(box, Transform3D.IDENTITY),
        ]))
        if bool(invalid_transform.get("ok", true)) \
                or str(invalid_transform.get("reason", "")) != "invalid_candidate_transform":
            _failures.append("%s transform did not fail rigid-basis contract" % labels[index])
        _expect_clean(collision_query, "%s transform" % labels[index])


func _check_numeric_fail_closed(collision_query) -> void:
    var box := BoxShape3D.new()
    box.size = Vector3.ONE
    var overflow_motion: Dictionary = collision_query.check_path_clear(_typed([
        _descriptor(box, Transform3D.IDENTITY),
    ]), _typed([
        _descriptor(box, Transform3D(Basis.IDENTITY, Vector3(3.0e38, 0.0, 0.0))),
        _descriptor(box, Transform3D(Basis.IDENTITY, Vector3(-3.0e38, 0.0, 0.0))),
    ]))
    if bool(overflow_motion.get("ok", true)) \
            or bool(overflow_motion.get("pending", true)) \
            or str(overflow_motion.get("reason", "")) != "invalid_path_motion":
        _failures.append("finite waypoint subtraction overflow did not fail closed")
    _expect_clean(collision_query, "overflow path motion")

    var invalid_fraction_sets: Array[PackedFloat32Array] = [
        PackedFloat32Array([NAN, 1.0]),
        PackedFloat32Array([0.75, 0.25]),
        PackedFloat32Array([-0.1, 0.5]),
        PackedFloat32Array([0.5, 1.1]),
        PackedFloat32Array([0.5]),
    ]
    for fractions in invalid_fraction_sets:
        if bool(collision_query.call("_cast_fractions_are_valid", fractions)):
            _failures.append("malformed backend cast fractions were accepted: %s" % str(fractions))
    if not bool(collision_query.call(
            "_cast_fractions_are_valid", PackedFloat32Array([0.25, 0.5]))):
        _failures.append("ordered finite backend cast fractions were rejected")


func _descriptor(shape: Shape3D, transform: Transform3D) -> Dictionary:
    return {"shape": shape, "transform": transform}


func _typed(descriptors: Array) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for descriptor_variant in descriptors:
        out.append(descriptor_variant as Dictionary)
    return out


func _expect_clean(collision_query, label: String) -> void:
    if collision_query.active_private_rid_count_for_validation() != 0:
        _failures.append("private RID cleanup failed after %s" % label)
