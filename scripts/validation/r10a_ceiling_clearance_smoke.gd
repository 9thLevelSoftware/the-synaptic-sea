extends SceneTree

const CONTRACT_PATH := "res://data/placement/contracts/structural/ship_structural_v0/ceiling_cap_1x1_contract.json"
const WRAPPER := preload("res://scenes/wrappers/structural/ship_structural_v0/ceiling_cap_1x1.tscn")

func _initialize() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if not parsed is Dictionary:
        _fail("ceiling contract is not an object")
        return
    var contract: Dictionary = parsed
    var physical: Variant = contract.get("physical_bounds", null)
    if not physical is Dictionary:
        _fail("physical_bounds missing")
        return
    if not _array_exact((physical as Dictionary).get("min", null), [-2.0, 3.8, -2.0]) \
            or not _array_exact((physical as Dictionary).get("max", null), [2.0, 4.0, 2.0]):
        _fail("physical bounds do not describe the overhead slab")
        return
    var visual: Variant = contract.get("visual_bounds", null)
    if not visual is Dictionary or float((visual as Dictionary).get("min", [0.0, 0.0, 0.0])[1]) >= 3.8:
        _fail("visual underside extent was collapsed into physical bounds")
        return

    var instance: Node = WRAPPER.instantiate()
    var shape_node: CollisionShape3D = instance.get_node_or_null("CollisionRoot/CollisionShape3D") as CollisionShape3D
    if shape_node == null or not shape_node.shape is BoxShape3D:
        instance.free()
        _fail("ceiling wrapper has no box collision")
        return
    var box: BoxShape3D = shape_node.shape as BoxShape3D
    if box.size != Vector3(4.0, 0.2, 4.0) or shape_node.position != Vector3(0.0, 3.9, 0.0):
        instance.free()
        _fail("ceiling wrapper proxy is not the canonical slab")
        return
    instance.free()
    print("R10A CEILING CLEARANCE PASS")
    quit(0)

func _array_exact(value: Variant, expected: Array) -> bool:
    if not value is Array or (value as Array).size() != expected.size():
        return false
    for index in range(expected.size()):
        if float((value as Array)[index]) != float(expected[index]):
            return false
    return true

func _fail(reason: String) -> void:
    push_error("R10A CEILING CLEARANCE FAIL reason=%s" % reason)
    quit(1)
