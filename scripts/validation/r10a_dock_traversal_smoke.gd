extends SceneTree

const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const DockPortBarrierScript := preload("res://scripts/tools/dock_port_barrier.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    if not _check_nested_fractional_projection():
        return
    var home: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/procgen/golden/coherent_ship_001/layout.json"))
    var lifeboat: Dictionary = LifeBoatBuilderScript.build_layout()
    if not home is Dictionary:
        _fail("home layout missing")
        return
    var host_port: Dictionary = DockPortsScript.for_derelict(home as Dictionary)
    var mobile_port: Dictionary = DockPortsScript.for_lifeboat(lifeboat)
    var preflight: Dictionary = DockingManagerScript.preflight_registered_pair(
        home as Dictionary, lifeboat, Transform3D.IDENTITY, host_port, mobile_port)
    if not bool(preflight.get("ok", false)):
        _fail("registered pair preflight failed: %s" % JSON.stringify(preflight))
        return
    if int(preflight.get("non_join_overlap_count", -1)) != 0 \
            or not bool(preflight.get("open_capsule_clear", false)):
        _fail("pair is not collision/traversal clear")
        return
    var collision_root := Node3D.new()
    get_root().add_child(collision_root)
    for box_variant in (preflight.get("host_collision_boxes", []) as Array) \
            + (preflight.get("mobile_collision_boxes", []) as Array):
        _add_static_box(collision_root, (box_variant as Dictionary).aabb)
    await physics_frame
    var host_endpoint: Dictionary = (home as Dictionary).boarding_endpoints_v1[0]
    var mobile_endpoint: Dictionary = lifeboat.boarding_endpoints_v1[0]
    var host_interior: Vector3 = _as_vector3(
        host_endpoint.interior_clearance_point_local)
    var mobile_interior: Vector3 = (preflight.mobile_transform as Transform3D) \
        * _as_vector3(mobile_endpoint.interior_clearance_point_local)
    if not _capsule_sweep_clear(host_interior, mobile_interior) \
            or not _capsule_sweep_clear(mobile_interior, host_interior):
        collision_root.free()
        _fail("actual bidirectional capsule shape cast is blocked")
        return

    var barrier: Area3D = DockPortBarrierScript.new()
    get_root().add_child(barrier)
    barrier.configure_endpoint("home/lifeboat", "intact", null, host_port, 6.0)
    await physics_frame
    var shape_node: CollisionShape3D = barrier.get_node_or_null(
        "DockPortBarrierCollisionShape3D") as CollisionShape3D
    if shape_node == null or not shape_node.shape is BoxShape3D:
        barrier.free()
        _fail("closed barrier is not an aperture box")
        return
    if shape_node.disabled:
        collision_root.free()
        barrier.free()
        _fail("closed barrier collision disabled")
        return
    var closed_walk: Dictionary = await _walk_character(host_interior, mobile_interior, 90)
    if bool(closed_walk.get("reached", false)):
        collision_root.free()
        barrier.free()
        _fail("closed barrier allowed ordinary traversal")
        return
    barrier.set_opened(true)
    if not shape_node.disabled:
        collision_root.free()
        barrier.free()
        _fail("open barrier collision remained enabled")
        return
    await physics_frame
    var outward_walk: Dictionary = await _walk_character(host_interior, mobile_interior, 240)
    var return_walk: Dictionary = await _walk_character(mobile_interior, host_interior, 240)
    if not bool(outward_walk.get("reached", false)) \
            or not bool(return_walk.get("reached", false)) \
            or not bool(outward_walk.get("grounded", false)) \
            or not bool(return_walk.get("grounded", false)):
        collision_root.free()
        barrier.free()
        _fail("ordinary bidirectional grounded CharacterBody traversal failed: %s/%s" % [
            JSON.stringify(outward_walk), JSON.stringify(return_walk)])
        return
    collision_root.free()
    barrier.free()
    print("R10A DOCK TRAVERSAL PASS")
    quit(0)

func _check_nested_fractional_projection() -> bool:
    var scene_path: String = "user://r10a_nested_fractional_wrapper.tscn"
    var file := FileAccess.open(scene_path, FileAccess.WRITE)
    if file == null:
        _fail("could not create nested fractional wrapper fixture")
        return false
    file.store_string("""[gd_scene load_steps=2 format=3]

[sub_resource type="BoxShape3D" id="S"]
size = Vector3(1.25, 2.5, 0.625)

[node name="Root" type="Node3D"]

[node name="Carrier" type="Node3D" parent="."]
transform = Transform3D(0.7071067811865476, 0, 0.7071067811865475, 0, 1, 0, -0.7071067811865475, 0, 0.7071067811865476, 0.125, 0.25, -0.375)

[node name="Shape" type="CollisionShape3D" parent="Carrier"]
transform = Transform3D(0.7071067811865476, 0, -0.7071067811865475, 0, 1, 0, 0.7071067811865475, 0, 0.7071067811865476, 0.2, 0.3, 0.4)
shape = SubResource("S")
""")
    file.close()
    var projected_module: Dictionary = {
        "wrapper_scene": scene_path,
        "content_sha256": "3c12acd22cb6a29b4a2897ee67eafbb5946658b2884f8bf8b5cd2d30b18d6abf",
        "boxes": [{
            "shape_path": "Carrier/Shape",
            "basis_f32_bits": [
                "3f7fffff", "00000000", "00000000",
                "00000000", "3f800000", "00000000",
                "00000000", "00000000", "3f7fffff"],
            "origin_f32_bits": ["3f0c9c92", "3f0ccccd", "be6f2f3d"],
            "dimensions_f32_bits": ["3fa00000", "40200000", "3f200000"],
        }],
    }
    var verdict: Dictionary = DockingManagerScript.validate_materialized_wrapper(
        scene_path, projected_module)
    if not bool(verdict.get("ok", false)):
        _fail("nested fractional live projection mismatch: %s" % JSON.stringify(verdict))
        return false
    return true

func _add_static_box(parent: Node3D, bounds: AABB) -> void:
    var body := StaticBody3D.new()
    body.collision_layer = 1
    body.collision_mask = 1
    body.position = bounds.get_center()
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = bounds.size
    collision.shape = shape
    body.add_child(collision)
    parent.add_child(body)

func _capsule_sweep_clear(start: Vector3, finish: Vector3) -> bool:
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.6
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = capsule
    query.transform = Transform3D(Basis.IDENTITY, start + Vector3.UP * 0.8)
    query.motion = finish - start
    query.collision_mask = 1
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var fractions: PackedFloat32Array = get_root().get_world_3d().direct_space_state.cast_motion(query)
    return fractions.size() == 2 and fractions[0] == 1.0 and fractions[1] == 1.0

func _walk_character(start: Vector3, finish: Vector3, max_frames: int) -> Dictionary:
    var body := CharacterBody3D.new()
    body.collision_layer = 2
    body.collision_mask = 1
    body.floor_snap_length = 0.5
    body.floor_max_angle = deg_to_rad(60.0)
    var collision := CollisionShape3D.new()
    collision.position = Vector3.UP * 0.8
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.6
    collision.shape = capsule
    body.add_child(collision)
    get_root().add_child(body)
    body.global_position = start
    for settle_frame in range(90):
        body.velocity = Vector3(0.0, body.velocity.y - 9.8 / 60.0, 0.0)
        body.move_and_slide()
        await physics_frame
        if body.is_on_floor():
            break
    var grounded: bool = body.is_on_floor()
    var reached: bool = false
    for frame in range(max_frames):
        var offset: Vector3 = finish - body.global_position
        var horizontal := Vector3(offset.x, 0.0, offset.z)
        if horizontal.length() <= 0.12:
            reached = true
            break
        var vertical_velocity: float = -0.2 if body.is_on_floor() \
            else body.velocity.y - 9.8 / 60.0
        body.velocity = horizontal.normalized() * 2.0
        body.velocity.y = vertical_velocity
        body.move_and_slide()
        await physics_frame
        grounded = grounded and body.is_on_floor()
    var result: Dictionary = {
        "reached": reached,
        "grounded": grounded,
        "final_position": body.global_position,
    }
    body.free()
    return result

func _as_vector3(value: Variant) -> Vector3:
    return Vector3(float(value[0]), float(value[1]), float(value[2])) \
        if value is Array and (value as Array).size() == 3 else Vector3.INF

func _fail(reason: String) -> void:
    push_error("R10A DOCK TRAVERSAL FAIL reason=%s" % reason)
    quit(1)
