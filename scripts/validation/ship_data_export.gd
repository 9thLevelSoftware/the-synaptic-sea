extends SceneTree
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")
const RoomGraphGeneratorScript := preload("res://scripts/procgen/room_graph_generator.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const StartSceneBuilderScript := preload("res://scripts/procgen/start_scene_builder.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")

func _initialize() -> void:
    var all_data := {}
    
    # Derelict + life boat start scenes
    for seed_val in [42, 999, 7777]:
        var scene: Node3D = StartSceneBuilderScript.build(seed_val)
        if scene == null: continue
        var derelict: Node = scene.get_child(0)
        var life_boat: Node = scene.get_child(1)
        var d_struct: Node = derelict.get_child(0)
        var lb_struct: Node = life_boat.get_child(0)
        
        var rooms := []
        for r in d_struct.get_children():
            rooms.append({"name": str(r.name), "x": r.position.x, "z": r.position.z, "modules": r.get_child_count(), "ship": "derelict"})
        for r in lb_struct.get_children():
            rooms.append({"name": str(r.name), "x": r.position.x + life_boat.position.x, "z": r.position.z + life_boat.position.z, "modules": r.get_child_count(), "ship": "life_boat"})
        all_data["start_seed_%d" % seed_val] = rooms
        scene.queue_free()
    
    # Standalone life boat
    var lb := LifeBoatBuilderScript.build()
    var lb_s := lb.get_child(0)
    var lb_rooms := []
    for r in lb_s.get_children():
        lb_rooms.append({"name": str(r.name), "x": r.position.x, "z": r.position.z, "modules": r.get_child_count(), "ship": "life_boat"})
    all_data["life_boat_standalone"] = lb_rooms
    
    var file := FileAccess.open("res://scenes/generated/ship_data.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(all_data, "  "))
    file.close()
    print("SHIP DATA SAVED")
    quit(0)
