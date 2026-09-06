extends SceneTree

const CatalogScript := preload("res://scripts/systems/runtime_physical_volume_catalog.gd")
const VolumeScript := preload("res://scripts/systems/runtime_physical_volume.gd")
const EPSILON: float = 0.0001
const EXPECTED: Dictionary = {
    "cart": [[0.75, 0.56, 0.50], [0.0, 0.28, 0.0], "floor"],
    "floor_drop": [[0.35, 0.25, 0.35], [0.0, 0.20, 0.0], "floor"],
    "air_recycler": [[0.80, 0.56, 0.60], [0.0, 0.28, 0.0], "deck"],
    "conduit": [[0.30, 1.00, 0.22], [0.0, 0.50, 0.11], "wall"],
    "console_generic_wall": [[0.60, 0.54, 0.34], [0.0, 0.27, 0.17], "wall"],
    "console_generic_deck": [[0.60, 0.54, 0.34], [0.0, 0.27, 0.0], "deck"],
    "hull_plating": [[1.00, 1.00, 0.08], [0.0, 0.50, 0.04], "wall"],
    "locker_wall": [[0.60, 0.75, 0.34], [0.0, 0.375, 0.17], "wall"],
    "machinery_block": [[0.80, 0.90, 0.60], [0.0, 0.45, 0.0], "deck"],
    "nav_console": [[0.90, 0.71, 0.36], [0.0, 0.355, 0.18], "wall"],
    "pump": [[0.40, 0.52, 0.40], [0.0, 0.26, 0.0], "deck"],
    "reactor_console": [[0.60, 0.75, 0.35], [0.0, 0.375, 0.175], "wall"],
    "sensor_rack": [[0.40, 0.78, 0.28], [0.0, 0.39, 0.14], "wall"],
    "thruster_control": [[0.68, 0.48, 0.37], [0.0, 0.24, 0.185], "wall"],
}

class ForgedCatalog extends RefCounted:
    func is_loaded() -> bool:
        return true

    func resolve_profile(_profile_id: String) -> Dictionary:
        return {
            "profile_id": "conduit", "shape_kind": "box", "dimensions": [99.0, 99.0, 99.0],
            "local_position": [0.0, 0.0, 0.0], "local_yaw_degrees": 0.0,
            "mount_kind": "wall", "collision_layer": 2.0, "collision_mask": 0.0,
            "blocking_purposes": ["structural_rebuild"],
        }

var _failures: Array[String] = []


func _init() -> void:
    var catalog := CatalogScript.new()
    _expect(catalog.load_canonical(), "canonical catalog did not load")
    _expect(catalog.profile_count() == EXPECTED.size(), "canonical profile count drifted")
    for profile_id in EXPECTED.keys():
        _expect_profile(catalog, str(profile_id))

    var forged_volume := VolumeScript.new()
    _expect(not forged_volume.configure(ForgedCatalog.new(), "conduit", Transform3D.IDENTITY),
        "duck-typed catalog must not supply volume geometry")
    forged_volume.free()

    var volume := VolumeScript.new()
    var mount_anchor := Transform3D(Basis(Vector3.UP, deg_to_rad(71.0)), Vector3(2.0, 0.0, 3.0))
    _expect(volume.configure(catalog, "conduit", mount_anchor), "wall primitive configuration failed")
    _expect(volume.is_configured(), "configured primitive was not retained")
    var body: StaticBody3D = volume.get_child(0) as StaticBody3D if volume.is_configured() else null
    var collision: CollisionShape3D = body.get_child(0) as CollisionShape3D if body != null else null
    _expect(body != null and body.collision_layer == 2 and body.collision_mask == 0, "primitive layer/mask drifted")
    _expect(collision != null and collision.shape is BoxShape3D, "conduit must create BoxShape3D")
    if collision != null and collision.shape is BoxShape3D:
        _expect(_same_vector3((collision.shape as BoxShape3D).size, Vector3(0.30, 1.00, 0.22)),
            "conduit XYZ dimensions drifted")

    var ship_world := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(23.0)), Vector3(10.0, 4.0, -4.0))
    var profile_local := Transform3D.IDENTITY.translated(Vector3(0.0, 0.50, 0.11))
    var expected: Transform3D = ship_world * mount_anchor * profile_local
    var wrong_order: Transform3D = mount_anchor * ship_world * profile_local
    var descriptors: Array[Dictionary] = volume.get_shape_descriptors(ship_world)
    _expect(descriptors.size() == 1, "exactly one query descriptor expected")
    if descriptors.size() == 1:
        var descriptor: Dictionary = descriptors[0]
        _expect(descriptor.keys().size() == 2 and descriptor.has("shape") and descriptor.has("transform"),
            "query descriptor must contain only copied shape and world transform")
        _expect(descriptor["shape"] is BoxShape3D, "descriptor shape must be copied BoxShape3D")
        var actual: Transform3D = descriptor["transform"] as Transform3D
        _expect(_same_transform(actual, expected), "descriptor must equal ship * mount * profile in full basis and origin")
        _expect(not _same_transform(actual, wrong_order), "noncommutative order discriminator was not exercised")
        if descriptor["shape"] is BoxShape3D and collision != null and collision.shape is BoxShape3D:
            (descriptor["shape"] as BoxShape3D).size = Vector3(9.0, 9.0, 9.0)
            _expect(_same_vector3((collision.shape as BoxShape3D).size, Vector3(0.30, 1.00, 0.22)),
                "descriptor copy mutated live collision")

    if collision != null:
        (collision.shape as BoxShape3D).size.x = 1.0
        _expect(not volume.is_configured() and volume.get_shape_descriptors(ship_world).is_empty(),
            "live shape drift must fail closed")
    _expect(volume.configure(catalog, "conduit", mount_anchor), "reconfigure after shape drift failed")
    body = volume.get_child(0) as StaticBody3D
    collision = body.get_child(0) as CollisionShape3D
    volume.transform.origin.x += 1.0
    _expect(not volume.is_configured() and volume.get_shape_descriptors(ship_world).is_empty(),
        "live transform drift must fail closed")
    _expect(volume.configure(catalog, "conduit", mount_anchor), "reconfigure after transform drift failed")
    body = volume.get_child(0) as StaticBody3D
    collision = body.get_child(0) as CollisionShape3D
    volume.transform.origin.x += EPSILON * 0.5
    _expect(volume.is_configured(), "sub-epsilon transform drift should remain inside invariant tolerance")
    descriptors = volume.get_shape_descriptors(ship_world)
    if descriptors.size() == 1:
        var small_drift_actual: Transform3D = descriptors[0]["transform"] as Transform3D
        var small_drift_expected: Transform3D = ship_world * volume.transform * body.transform * collision.transform
        _expect(_same_transform(small_drift_actual, small_drift_expected),
            "descriptor must compose actual scene transforms")
        _expect(small_drift_actual.origin.x != expected.origin.x,
            "descriptor must report tolerated live transform drift rather than cached geometry")
    else:
        _expect(false, "sub-epsilon drift should still yield descriptor")
    _expect(volume.configure(catalog, "conduit", mount_anchor), "reconfigure after sub-epsilon drift failed")
    var old_body: StaticBody3D = volume.get_child(0) as StaticBody3D
    _expect(volume.configure(catalog, "cart", Transform3D.IDENTITY), "replacement configuration failed")
    _expect(not is_instance_valid(old_body) or old_body.get_parent() == null,
        "replacement body must detach before deferred destruction")
    _expect(not volume.configure(catalog, "missing", Transform3D.IDENTITY), "missing profile must reject")
    _expect(not volume.configure(catalog, "cart", Transform3D(Basis.IDENTITY.scaled(Vector3(2.0, 1.0, 1.0)), Vector3.ZERO)),
        "non-rigid mount transform must reject")
    _expect(not volume.configure(catalog, "cart", Transform3D(Basis.IDENTITY, Vector3(INF, 0.0, 0.0))),
        "nonfinite mount transform must reject")

    volume.free()
    if _failures.is_empty():
        print("RUNTIME PHYSICAL VOLUME PASS")
        quit(0)
        return
    for failure in _failures:
        push_error(failure)
    print("RUNTIME PHYSICAL VOLUME FAIL: %s" % "; ".join(_failures))
    quit(1)


func _expect_profile(catalog: RefCounted, profile_id: String) -> void:
    var expected: Array = EXPECTED[profile_id] as Array
    var profile: Dictionary = catalog.resolve_profile(profile_id)
    _expect(profile.is_read_only() and str(profile.get("shape_kind", "")) == "box", "%s must be canonical box" % profile_id)
    _expect(profile.get("dimensions", []) == expected[0] and profile.get("local_position", []) == expected[1],
        "%s dimensions or local position drifted" % profile_id)
    _expect(float(profile.get("local_yaw_degrees", -1.0)) == 0.0 and profile.get("mount_kind", "") == expected[2],
        "%s yaw or mount kind drifted" % profile_id)
    _expect(float(profile.get("collision_layer", -1.0)) == 2.0 and float(profile.get("collision_mask", -1.0)) == 0.0,
        "%s collision bits drifted" % profile_id)
    _expect(profile.get("blocking_purposes", []) == ["structural_rebuild"], "%s purpose drifted" % profile_id)


func _same_transform(left: Transform3D, right: Transform3D) -> bool:
    return _same_vector3(left.origin, right.origin) and _same_vector3(left.basis.x, right.basis.x) \
        and _same_vector3(left.basis.y, right.basis.y) and _same_vector3(left.basis.z, right.basis.z)


func _same_vector3(left: Vector3, right: Vector3) -> bool:
    return _close(left.x, right.x) and _close(left.y, right.y) and _close(left.z, right.z)


func _close(left: float, right: float) -> bool:
    return absf(left - right) <= EPSILON


func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)
