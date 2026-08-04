extends SceneTree

const WRAPPER_PATH: String = "res://scenes/wrappers/structural/ship_structural_v0/pressure_door_1x1.tscn"
const PASS_MARKER: String = "FOCUSED_NINE_PRESSURE_DOOR_PASS variants=3 anchors=4 collision=true"
const EXPECTED_ANCHORS: Array[String] = [
    "Anchor_FloorCenter",
    "Anchor_SOCK_portal_edge_west_01",
    "Anchor_SOCK_portal_edge_east_01",
    "Anchor_SOCK_portal_center_internal_01",
]
const EXPECTED_VARIANTS: Array[String] = [
    "VisualInstance_Intact",
    "VisualInstance_Damaged",
    "VisualInstance_Breached",
]


func _initialize() -> void:
    var wrapper_scene: PackedScene = load(WRAPPER_PATH) as PackedScene
    if wrapper_scene == null:
        _fail("pressure-door wrapper could not be loaded")
        return

    var wrapper: Node = wrapper_scene.instantiate()
    if wrapper == null or wrapper.name != "Pressure_Door_1x1":
        _fail("pressure-door wrapper root mismatch")
        return

    var anchors: Array[String] = []
    for child: Node in wrapper.get_children():
        if child is Marker3D:
            anchors.append(child.name)
    anchors.sort()
    var expected_anchors: Array[String] = EXPECTED_ANCHORS.duplicate()
    expected_anchors.sort()
    if anchors != expected_anchors:
        _fail("pressure-door anchor contract mismatch")
        return

    var visual: Node = wrapper.get_node_or_null("Visual")
    if visual == null:
        _fail("pressure-door visual root missing")
        return
    var variants: Array[String] = []
    for child: Node in visual.get_children():
        variants.append(child.name)
    variants.sort()
    var expected_variants: Array[String] = EXPECTED_VARIANTS.duplicate()
    expected_variants.sort()
    if variants != expected_variants:
        _fail("pressure-door visual variant set mismatch")
        return

    var intact: Node3D = visual.get_node_or_null("VisualInstance_Intact") as Node3D
    var damaged: Node3D = visual.get_node_or_null("VisualInstance_Damaged") as Node3D
    var breached: Node3D = visual.get_node_or_null("VisualInstance_Breached") as Node3D
    if intact == null or damaged == null or breached == null:
        _fail("pressure-door visual variant nodes missing")
        return
    if not intact.visible or damaged.visible or breached.visible:
        _fail("pressure-door visual default visibility mismatch")
        return

    var collision_count: int = 0
    for child: Node in wrapper.get_children():
        if child is CollisionObject3D:
            collision_count += 1
    if collision_count != 1:
        _fail("pressure-door collision root count mismatch")
        return

    var collision_root: Node = wrapper.get_node_or_null("CollisionRoot")
    var collision_shape_count: int = 0
    if collision_root != null:
        for child: Node in collision_root.get_children():
            if child is CollisionShape3D:
                collision_shape_count += 1
    var collision_shape: CollisionShape3D = wrapper.get_node_or_null(
        "CollisionRoot/CollisionShape3D"
    ) as CollisionShape3D
    if collision_root == null or collision_shape_count != 1 or collision_shape == null or collision_shape.shape == null:
        _fail("pressure-door collision contract missing")
        return

    print(PASS_MARKER)
    wrapper.free()
    quit(0)


func _fail(message: String) -> void:
    print("FOCUSED_NINE_PRESSURE_DOOR_FAIL: %s" % message)
    quit(1)
