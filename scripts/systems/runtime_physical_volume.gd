extends Node3D
class_name RuntimePhysicalVolume

## Scene-owned physical primitive for one canonical occupancy profile. The
## exact catalog script is the authority; a duck-typed RefCounted cannot create
## a runtime volume by supplying forged geometry.

const CatalogScript := preload("res://scripts/systems/runtime_physical_volume_catalog.gd")
const STATE_EPSILON: float = 0.0001
const RIGID_BASIS_EPSILON: float = 0.00001

var _profile_id: String = ""
var _shape_kind: String = ""
var _dimensions: PackedFloat32Array = PackedFloat32Array()
var _mount_anchor: Transform3D = Transform3D.IDENTITY
var _profile_local: Transform3D = Transform3D.IDENTITY
var _expected_local_transform: Transform3D = Transform3D.IDENTITY
var _shape: Shape3D
var _body: StaticBody3D
var _collision: CollisionShape3D


func configure(catalog: RefCounted, profile_id: String, mount_anchor: Transform3D) -> bool:
    _clear_configuration()
    if not _is_canonical_catalog(catalog) or not _is_rigid_transform(mount_anchor):
        return false
    var profile: Dictionary = catalog.resolve_profile(profile_id)
    if profile.is_empty() or not _is_defensive_profile(profile, profile_id):
        return false
    var shape: Shape3D = _create_shape(profile)
    if shape == null:
        return false
    _profile_id = profile_id
    _shape_kind = str(profile["shape_kind"])
    _dimensions = PackedFloat32Array(profile["dimensions"] as Array)
    _mount_anchor = mount_anchor
    _profile_local = _profile_transform(profile)
    _expected_local_transform = _mount_anchor * _profile_local
    if not _is_rigid_transform(_profile_local) or not _is_rigid_transform(_expected_local_transform):
        _clear_configuration()
        return false
    _shape = shape
    transform = _expected_local_transform
    _body = StaticBody3D.new()
    _body.collision_layer = 2
    _body.collision_mask = 0
    add_child(_body)
    _collision = CollisionShape3D.new()
    _collision.shape = _shape
    _body.add_child(_collision)
    return is_configured()


func is_configured() -> bool:
    if _shape == null or _body == null or _collision == null:
        return false
    if not is_instance_valid(_body) or not is_instance_valid(_collision) \
            or _body.get_parent() != self or _collision.get_parent() != _body \
            or _body.collision_layer != 2 or _body.collision_mask != 0 \
            or _collision.disabled or _collision.shape != _shape:
        return false
    if not _same_transform(transform, _expected_local_transform) \
            or not _same_transform(_body.transform, Transform3D.IDENTITY) \
            or not _same_transform(_collision.transform, Transform3D.IDENTITY):
        return false
    return _shape_matches_dimensions()


## Returns exact query DTOs only. The Shape3D is cloned once for the caller;
## callers with multi-waypoint paths must reuse that same descriptor shape.
func get_shape_descriptors(ship_world_transform: Transform3D) -> Array[Dictionary]:
    if not is_configured() or not _is_rigid_transform(ship_world_transform):
        return []
    var copied_shape: Shape3D = _shape.duplicate(true) as Shape3D
    if copied_shape == null:
        return []
    return [{
        "shape": copied_shape,
        "transform": ship_world_transform * transform * _body.transform * _collision.transform,
    }]


func _is_canonical_catalog(catalog: RefCounted) -> bool:
    return catalog != null and catalog.get_script() == CatalogScript and catalog.is_loaded()


func _clear_configuration() -> void:
    if _body != null and is_instance_valid(_body):
        _body.collision_layer = 0
        _body.collision_mask = 0
        if _collision != null and is_instance_valid(_collision):
            _collision.disabled = true
        if _body.get_parent() != null:
            _body.get_parent().remove_child(_body)
        if _body.is_inside_tree():
            _body.queue_free()
        else:
            _body.free()
    _profile_id = ""
    _shape_kind = ""
    _dimensions = PackedFloat32Array()
    _mount_anchor = Transform3D.IDENTITY
    _profile_local = Transform3D.IDENTITY
    _expected_local_transform = Transform3D.IDENTITY
    _shape = null
    _body = null
    _collision = null
    transform = Transform3D.IDENTITY


func _is_defensive_profile(profile: Dictionary, expected_profile_id: String) -> bool:
    if str(profile.get("profile_id", "")) != expected_profile_id \
            or str(profile.get("shape_kind", "")) not in ["box", "capsule"] \
            or not _is_exact_numeric(profile.get("collision_layer", null), 2.0) \
            or not _is_exact_numeric(profile.get("collision_mask", null), 0.0) \
            or not _is_finite_vector(profile.get("local_position", null), 3) \
            or not _is_finite_number(profile.get("local_yaw_degrees", null)):
        return false
    var purpose: Variant = profile.get("blocking_purposes", null)
    if not purpose is Array or (purpose as Array).size() != 1 \
            or (purpose as Array)[0] != "structural_rebuild":
        return false
    var shape_kind: String = str(profile.get("shape_kind", ""))
    var dimensions: Variant = profile.get("dimensions", null)
    if shape_kind == "box":
        return _is_positive_vector(dimensions, 3)
    if _is_positive_vector(dimensions, 2):
        var capsule_dimensions: Array = dimensions as Array
        return float(capsule_dimensions[1]) >= float(capsule_dimensions[0]) * 2.0
    return false


func _create_shape(profile: Dictionary) -> Shape3D:
    var dimensions: Array = profile["dimensions"] as Array
    if str(profile["shape_kind"]) == "box":
        var box: BoxShape3D = BoxShape3D.new()
        box.size = Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2]))
        return box
    var capsule: CapsuleShape3D = CapsuleShape3D.new()
    capsule.radius = float(dimensions[0])
    capsule.height = float(dimensions[1])
    return capsule


func _shape_matches_dimensions() -> bool:
    if _shape_kind == "box" and _shape is BoxShape3D and _dimensions.size() == 3:
        var size: Vector3 = (_shape as BoxShape3D).size
        return _close(size.x, _dimensions[0]) and _close(size.y, _dimensions[1]) \
            and _close(size.z, _dimensions[2])
    if _shape_kind == "capsule" and _shape is CapsuleShape3D and _dimensions.size() == 2:
        var capsule: CapsuleShape3D = _shape as CapsuleShape3D
        return _close(capsule.radius, _dimensions[0]) and _close(capsule.height, _dimensions[1])
    return false


func _profile_transform(profile: Dictionary) -> Transform3D:
    var position: Array = profile["local_position"] as Array
    var yaw_radians: float = deg_to_rad(float(profile["local_yaw_degrees"]))
    return Transform3D(Basis(Vector3.UP, yaw_radians), Vector3(
        float(position[0]), float(position[1]), float(position[2])
    ))


func _is_rigid_transform(value: Transform3D) -> bool:
    if not _is_finite_vector3(value.origin) or not _is_finite_vector3(value.basis.x) \
            or not _is_finite_vector3(value.basis.y) or not _is_finite_vector3(value.basis.z):
        return false
    var basis: Basis = value.basis
    return _rigid_close(basis.x.length_squared(), 1.0) and _rigid_close(basis.y.length_squared(), 1.0) \
        and _rigid_close(basis.z.length_squared(), 1.0) and _rigid_close(basis.x.dot(basis.y), 0.0) \
        and _rigid_close(basis.x.dot(basis.z), 0.0) and _rigid_close(basis.y.dot(basis.z), 0.0) \
        and _rigid_close(basis.determinant(), 1.0)


func _same_transform(left: Transform3D, right: Transform3D) -> bool:
    return _same_vector3(left.origin, right.origin) and _same_vector3(left.basis.x, right.basis.x) \
        and _same_vector3(left.basis.y, right.basis.y) and _same_vector3(left.basis.z, right.basis.z)


func _same_vector3(left: Vector3, right: Vector3) -> bool:
    return _close(left.x, right.x) and _close(left.y, right.y) and _close(left.z, right.z)


func _is_finite_vector3(value: Vector3) -> bool:
    return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_finite_vector(value: Variant, expected_size: int) -> bool:
    if not value is Array or (value as Array).size() != expected_size:
        return false
    for coordinate in value as Array:
        if not _is_finite_number(coordinate):
            return false
    return true


func _is_positive_vector(value: Variant, expected_size: int) -> bool:
    if not _is_finite_vector(value, expected_size):
        return false
    for coordinate in value as Array:
        if float(coordinate) <= 0.0:
            return false
    return true


func _is_finite_number(value: Variant) -> bool:
    return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _is_exact_numeric(value: Variant, expected: float) -> bool:
    return _is_finite_number(value) and float(value) == expected


func _close(left: float, right: float) -> bool:
    return absf(left - right) <= STATE_EPSILON


func _rigid_close(left: float, right: float) -> bool:
    return absf(left - right) <= RIGID_BASIS_EPSILON
