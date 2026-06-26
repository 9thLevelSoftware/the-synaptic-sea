extends SceneTree
## Headless gameplay interaction smoke for generated ship layouts.
##
## Usage:
##   /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless \
##     --path /Users/christopherwilloughby/the-synapse-sea-of-stars \
##     --script res://scripts/validation/procgen_ship_gameplay_smoke.gd -- \
##     --layout /abs/path/to/layout.json --kit /abs/path/to/ship_structural_v0.json \
##     --gameplay-slice /abs/path/to/gameplay_slice.json [--timeout-frames 1200]
##
## The script:
##   1. Loads the solved layout, kit, and gameplay slice JSON.
##   2. Instantiates every structural placement wrapper scene.
##   3. Bakes a simple navigation mesh from floor/corridor floor placements.
##   4. Spawns debug interaction volumes at each objective approach cell.
##   5. Drives a NavigationAgent3D through the objective sequence and to the goal room.
##   6. Exits 0 only when every objective was triggered in order and the goal was reached.

const CELL_SIZE: float = 4.0
const FLOOR_Y_OFFSET: float = 0.12
const WALK_SPEED: float = 4.5
const DEFAULT_TIMEOUT_FRAMES: int = 1200
const OBJECTIVE_TRIGGER_RADIUS: float = 1.5
const FLOOR_MODULES: Array[String] = ["floor_1x1", "corridor_floor_1x1"]


class GameplayWalker:
    extends Node3D

    var agent: NavigationAgent3D
    var objective_specs: Array = []
    var goal_position: Vector3 = Vector3.ZERO
    var timeout_frames: int = DEFAULT_TIMEOUT_FRAMES
    var target_distance: float = 0.8
    var walk_speed: float = WALK_SPEED
    var frame_count: int = 0
    var interaction_count: int = 0
    var current_objective_index: int = 0
    var finished: bool = false
    var last_distance: float = 0.0
    var active_target_position: Vector3 = Vector3.INF

    func _ready() -> void:
        set_physics_process(true)

    func configure(objectives: Array, goal: Vector3, timeout: int) -> void:
        objective_specs = objectives
        goal_position = goal
        timeout_frames = timeout

    func _physics_process(delta: float) -> void:
        if finished:
            return

        frame_count += 1
        if frame_count < 2:
            return

        if agent == null:
            _fail("no-agent")
            return

        if current_objective_index < objective_specs.size():
            var objective_variant: Variant = objective_specs[current_objective_index]
            if typeof(objective_variant) != TYPE_DICTIONARY:
                _fail("objective-not-a-dictionary")
                return
            var objective: Dictionary = objective_variant
            var target_variant: Variant = objective.get("position", Vector3.INF)
            if typeof(target_variant) != TYPE_VECTOR3:
                _fail("objective-target-missing")
                return
            var target_position: Vector3 = target_variant
            _set_agent_target(target_position)
            _advance_toward_target(delta)

            var current_distance: float = global_position.distance_to(target_position)
            last_distance = current_distance
            var trigger_radius: float = float(objective.get("radius", OBJECTIVE_TRIGGER_RADIUS))
            if current_distance <= trigger_radius:
                _trigger_objective(objective, current_distance)
                current_objective_index += 1
                if current_objective_index >= objective_specs.size():
                    _set_agent_target(goal_position)
                return
        else:
            _set_agent_target(goal_position)
            _advance_toward_target(delta)
            var goal_distance: float = global_position.distance_to(goal_position)
            last_distance = goal_distance
            if goal_distance <= target_distance:
                finished = true
                print("GAMEPLAY SMOKE PASS objectives=%d interactions=%d frames=%d final_distance=%.3f" % [objective_specs.size(), interaction_count, frame_count, goal_distance])
                get_tree().quit(0)
                return

        if frame_count >= timeout_frames:
            _fail("timeout")

    func _set_agent_target(target_position: Vector3) -> void:
        if active_target_position == target_position:
            return
        active_target_position = target_position
        agent.target_position = target_position

    func _advance_toward_target(delta: float) -> void:
        var next_position: Vector3 = agent.get_next_path_position()
        var step: Vector3 = next_position - global_position
        if step.length_squared() > 0.000001:
            global_position = global_position.move_toward(next_position, walk_speed * delta)

    func _trigger_objective(objective: Dictionary, distance: float) -> void:
        interaction_count += 1
        print(
            "INTERACTION objective=%s sequence=%d type=%s room=%s distance=%.3f"
            % [
                str(objective.get("id", "<objective>")),
                int(objective.get("sequence", interaction_count)),
                str(objective.get("type", "unknown")),
                str(objective.get("room_id", "<room>")),
                distance,
            ]
        )

    func _fail(reason: String) -> void:
        finished = true
        push_error(
            "GAMEPLAY SMOKE FAIL frames=%d interactions=%d objective_index=%d distance=%.3f reason=%s"
            % [frame_count, interaction_count, current_objective_index, last_distance, reason]
        )
        get_tree().quit(1)


func _initialize() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    if args.is_empty():
        _usage_and_quit()
        return

    var parsed: Dictionary = _parse_args(args)
    if parsed.is_empty():
        _usage_and_quit()
        return

    var layout_path: String = str(parsed["layout"])
    var kit_path: String = str(parsed["kit"])
    var gameplay_slice_path: String = str(parsed["gameplay_slice"])
    var timeout_frames: int = int(parsed.get("timeout_frames", DEFAULT_TIMEOUT_FRAMES))
    if timeout_frames <= 0:
        push_error("timeout_frames must be greater than zero")
        quit(1)
        return

    var layout_abs: String = _resolve_path(layout_path)
    var kit_abs: String = _resolve_path(kit_path)
    var gameplay_slice_abs: String = _resolve_path(gameplay_slice_path)
    if not FileAccess.file_exists(layout_abs):
        push_error("layout not found: %s" % layout_abs)
        quit(2)
        return
    if not FileAccess.file_exists(kit_abs):
        push_error("kit not found: %s" % kit_abs)
        quit(2)
        return
    if not FileAccess.file_exists(gameplay_slice_abs):
        push_error("gameplay slice not found: %s" % gameplay_slice_abs)
        quit(2)
        return

    var layout_doc: Dictionary = _load_json_dict(layout_abs, "layout")
    if layout_doc.is_empty():
        quit(3)
        return
    var kit_doc: Dictionary = _load_json_dict(kit_abs, "kit")
    if kit_doc.is_empty():
        quit(3)
        return
    var gameplay_doc: Dictionary = _load_json_dict(gameplay_slice_abs, "gameplay slice")
    if gameplay_doc.is_empty():
        quit(3)
        return

    var rooms_variant: Variant = layout_doc.get("rooms", [])
    if typeof(rooms_variant) != TYPE_ARRAY:
        push_error("layout missing rooms array: %s" % layout_abs)
        quit(3)
        return
    var rooms: Array = rooms_variant

    var prototype_variant: Variant = layout_doc.get("prototype", {})
    if typeof(prototype_variant) != TYPE_DICTIONARY:
        push_error("layout missing prototype object: %s" % layout_abs)
        quit(3)
        return
    var prototype: Dictionary = prototype_variant

    var start_room_id: String = str(gameplay_doc.get("start_room", prototype.get("start_room", "")))
    var goal_room_id: String = str(gameplay_doc.get("goal_room", prototype.get("goal_room", "")))
    if start_room_id.is_empty():
        push_error("gameplay slice missing start_room: %s" % gameplay_slice_abs)
        quit(3)
        return
    if goal_room_id.is_empty():
        push_error("gameplay slice missing goal_room: %s" % gameplay_slice_abs)
        quit(3)
        return

    var module_to_scene: Dictionary = _build_module_scene_map(kit_doc, kit_abs)
    if module_to_scene.is_empty():
        push_error("kit contains no usable module wrapper scenes: %s" % kit_abs)
        quit(3)
        return

    var objective_specs: Array = _build_objective_specs(layout_doc, gameplay_doc, gameplay_slice_abs)
    if objective_specs.is_empty():
        quit(3)
        return

    var tree_root: Node = get_root()
    var ship_root: Node3D = Node3D.new()
    ship_root.name = "GeneratedShipPrototype"
    tree_root.add_child(ship_root)

    var instantiated_count: int = _instance_structural_wrappers(layout_doc, module_to_scene, ship_root)
    print("Instantiated %d structural wrapper(s)." % instantiated_count)

    var start_center: Vector3 = _room_center(rooms, start_room_id)
    var goal_center: Vector3 = _room_center(rooms, goal_room_id)
    if goal_center == Vector3.INF:
        push_error("goal room not found in layout: %s" % goal_room_id)
        quit(3)
        return
    if start_center == Vector3.INF:
        push_error("start room not found in layout: %s" % start_room_id)
        quit(3)
        return

    var nav_region: NavigationRegion3D = _build_navigation_region(rooms, ship_root)
    if nav_region == null:
        quit(4)
        return
    print("Baked gameplay navigation mesh from floor cells.")

    var vertical_link_count: int = _add_vertical_links(layout_doc, ship_root)
    if vertical_link_count > 0:
        print("Added %d vertical navigation link(s)." % vertical_link_count)

    var objective_volumes: Array = []
    for objective_variant in objective_specs:
        if typeof(objective_variant) != TYPE_DICTIONARY:
            continue
        var objective: Dictionary = objective_variant
        objective_volumes.append(_spawn_objective_volume(ship_root, objective))

    var walker: GameplayWalker = GameplayWalker.new()
    walker.name = "GameplayWalker"
    walker.position = start_center
    walker.configure(objective_specs, goal_center, timeout_frames)
    walker.target_distance = 0.8
    walker.walk_speed = WALK_SPEED
    ship_root.add_child(walker)

    var agent: NavigationAgent3D = NavigationAgent3D.new()
    agent.name = "NavigationAgent3D"
    agent.path_desired_distance = 0.35
    agent.target_desired_distance = 0.8
    agent.target_position = start_center
    walker.agent = agent
    walker.add_child(agent)

    print(
        "Gameplay smoke start_room=%s goal_room=%s objectives=%d timeout_frames=%d"
        % [start_room_id, goal_room_id, objective_specs.size(), timeout_frames]
    )


func _usage_and_quit() -> void:
    push_error(
        "Usage: godot --headless --path <project> --script res://scripts/validation/procgen_ship_gameplay_smoke.gd -- --layout <layout.json> --kit <ship_structural_v0.json> --gameplay-slice <gameplay_slice.json> [--timeout-frames <n>]"
    )
    quit(1)


func _parse_args(args: PackedStringArray) -> Dictionary:
    var layout_path: String = ""
    var kit_path: String = ""
    var gameplay_slice_path: String = ""
    var timeout_frames: int = DEFAULT_TIMEOUT_FRAMES
    var index: int = 0
    while index < args.size():
        var token: String = args[index]
        if token == "--":
            index += 1
            continue
        if token == "--layout":
            if index + 1 >= args.size():
                return {}
            layout_path = args[index + 1]
            index += 2
            continue
        if token == "--kit":
            if index + 1 >= args.size():
                return {}
            kit_path = args[index + 1]
            index += 2
            continue
        if token == "--gameplay-slice":
            if index + 1 >= args.size():
                return {}
            gameplay_slice_path = args[index + 1]
            index += 2
            continue
        if token == "--timeout-frames":
            if index + 1 >= args.size():
                return {}
            var timeout_text: String = args[index + 1]
            if not timeout_text.is_valid_int():
                return {}
            timeout_frames = int(timeout_text)
            index += 2
            continue
        return {}

    if layout_path.is_empty() or kit_path.is_empty() or gameplay_slice_path.is_empty():
        return {}
    return {
        "layout": layout_path,
        "kit": kit_path,
        "gameplay_slice": gameplay_slice_path,
        "timeout_frames": timeout_frames,
    }


func _resolve_path(raw_path: String) -> String:
    if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
        return ProjectSettings.globalize_path(raw_path)
    if raw_path.is_absolute_path():
        return raw_path
    if FileAccess.file_exists(raw_path) or DirAccess.open(raw_path) != null:
        return raw_path
    var cwd: String = OS.get_environment("PWD")
    if not cwd.is_empty():
        var cwd_path: String = cwd.path_join(raw_path)
        if FileAccess.file_exists(cwd_path) or DirAccess.open(cwd_path) != null:
            return cwd_path
    return ProjectSettings.globalize_path("res://%s" % raw_path)


func _load_json_dict(path: String, label: String) -> Dictionary:
    var text: String = FileAccess.get_file_as_string(path)
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("%s JSON is not an object: %s" % [label, path])
        return {}
    return parsed


func _build_module_scene_map(kit_doc: Dictionary, kit_path: String) -> Dictionary:
    var modules_variant: Variant = kit_doc.get("modules", [])
    if typeof(modules_variant) != TYPE_ARRAY:
        push_error("kit missing modules array: %s" % kit_path)
        return {}

    var module_to_scene: Dictionary = {}
    for module_variant in modules_variant:
        if typeof(module_variant) != TYPE_DICTIONARY:
            continue
        var module: Dictionary = module_variant
        var module_id: String = str(module.get("module_id", ""))
        var scene_path: String = str(module.get("godot_wrapper_scene", ""))
        if module_id.is_empty() or scene_path.is_empty():
            continue
        module_to_scene[module_id] = scene_path
    return module_to_scene


func _build_objective_specs(layout_doc: Dictionary, gameplay_doc: Dictionary, gameplay_slice_path: String) -> Array:
    var rooms_variant: Variant = layout_doc.get("rooms", [])
    if typeof(rooms_variant) != TYPE_ARRAY:
        push_error("layout missing rooms array: %s" % gameplay_slice_path)
        return []
    var rooms: Array = rooms_variant

    var objectives_variant: Variant = gameplay_doc.get("objectives", [])
    if typeof(objectives_variant) != TYPE_ARRAY:
        push_error("gameplay slice missing objectives array: %s" % gameplay_slice_path)
        return []
    var objectives: Array = objectives_variant
    if objectives.is_empty():
        push_error("gameplay slice contains no objectives: %s" % gameplay_slice_path)
        return []

    var expected_sequence: int = 1
    var objective_specs: Array = []
    for objective_variant in objectives:
        if typeof(objective_variant) != TYPE_DICTIONARY:
            push_error("gameplay slice objective is not an object: %s" % gameplay_slice_path)
            return []
        var objective: Dictionary = objective_variant
        var objective_id: String = str(objective.get("id", ""))
        if objective_id.is_empty():
            push_error("gameplay slice objective missing id: %s" % gameplay_slice_path)
            return []
        var sequence: int = int(objective.get("sequence", 0))
        if sequence != expected_sequence:
            push_error(
                "gameplay slice objective sequence mismatch: expected=%d got=%d objective=%s"
                % [expected_sequence, sequence, objective_id]
            )
            return []
        expected_sequence += 1

        var room_id: String = str(objective.get("room_id", ""))
        if room_id.is_empty():
            push_error("gameplay slice objective missing room_id: %s" % objective_id)
            return []
        var room: Dictionary = _find_room(rooms, room_id)
        if room.is_empty():
            push_error("objective room not found in layout: %s" % room_id)
            return []

        var approach_variant: Variant = objective.get("approach_cell", [])
        if typeof(approach_variant) != TYPE_ARRAY:
            push_error("objective missing approach_cell: %s" % objective_id)
            return []
        var approach_cell: Array = approach_variant
        if approach_cell.size() < 3:
            push_error("objective approach_cell is incomplete: %s" % objective_id)
            return []

        var target_position: Vector3 = _room_cell_world(room, approach_cell)
        if target_position == Vector3.INF:
            push_error(
                "no floor position for approach cell objective=%s room=%s cell=%s"
                % [objective_id, room_id, str(approach_cell)]
            )
            return []

        objective_specs.append(
            {
                "id": objective_id,
                "sequence": sequence,
                "type": str(objective.get("type", "unknown")),
                "room_id": room_id,
                "position": target_position,
                "radius": OBJECTIVE_TRIGGER_RADIUS,
            }
        )

    return objective_specs


func _spawn_objective_volume(ship_root: Node3D, objective: Dictionary) -> Area3D:
    var volume: Area3D = Area3D.new()
    var sequence: int = int(objective.get("sequence", 0))
    var objective_type: String = str(objective.get("type", "objective"))
    var objective_id: String = str(objective.get("id", "objective"))
    volume.name = "ObjectiveVolume_seq%d_%s_%s" % [sequence, objective_type, objective_id]
    volume.position = objective.get("position", Vector3.ZERO)
    volume.monitoring = true
    volume.monitorable = true
    volume.collision_layer = 0
    volume.collision_mask = 0
    volume.set_meta("objective_id", objective_id)
    volume.set_meta("objective_sequence", sequence)
    volume.set_meta("objective_type", objective_type)
    volume.set_meta("room_id", str(objective.get("room_id", "")))

    var sphere: SphereShape3D = SphereShape3D.new()
    sphere.radius = float(objective.get("radius", OBJECTIVE_TRIGGER_RADIUS))

    var collision: CollisionShape3D = CollisionShape3D.new()
    collision.shape = sphere
    volume.add_child(collision)
    ship_root.add_child(volume)
    return volume


func _find_room(rooms: Array, room_id: String) -> Dictionary:
    for room_variant in rooms:
        if typeof(room_variant) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_variant
        if str(room.get("id", "")) == room_id:
            return room
    return {}


func _cell_name_candidates(cell: Array) -> Array:
    if cell.size() < 3:
        return []
    var x: int = int(cell[0])
    var z: int = int(cell[1])
    var deck: int = int(cell[2])
    var candidates: Array = []
    if deck == 0:
        candidates.append("floor_cell_x%d_z%d" % [x, z])
        candidates.append("floor_cell_d0_x%d_z%d" % [x, z])
    else:
        candidates.append("floor_cell_d%d_x%d_z%d" % [deck, x, z])
    return candidates


func _room_cell_world(room: Dictionary, cell: Array) -> Vector3:
    var candidates: Array = _cell_name_candidates(cell)
    if candidates.is_empty():
        return Vector3.INF

    var placements_variant: Variant = room.get("structural_placements", [])
    if typeof(placements_variant) != TYPE_ARRAY:
        return Vector3.INF
    var placements: Array = placements_variant
    for placement_variant in placements:
        if typeof(placement_variant) != TYPE_DICTIONARY:
            continue
        var placement: Dictionary = placement_variant
        var name: String = str(placement.get("name", ""))
        if not candidates.has(name):
            continue
        var pos_variant: Variant = placement.get("position", [])
        if typeof(pos_variant) != TYPE_ARRAY:
            return Vector3.INF
        var pos: Array = pos_variant
        if pos.size() < 3:
            return Vector3.INF
        return Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
    return Vector3.INF


func _instance_structural_wrappers(layout_doc: Dictionary, module_to_scene: Dictionary, ship_root: Node3D) -> int:
    var rooms_variant: Variant = layout_doc.get("rooms", [])
    if typeof(rooms_variant) != TYPE_ARRAY:
        return 0
    var rooms: Array = rooms_variant
    var count: int = 0
    for room_variant in rooms:
        if typeof(room_variant) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_variant
        var room_id: String = str(room.get("id", ""))
        var placements_variant: Variant = room.get("structural_placements", [])
        if typeof(placements_variant) != TYPE_ARRAY:
            continue
        for placement_variant in placements_variant:
            if typeof(placement_variant) != TYPE_DICTIONARY:
                continue
            var placement: Dictionary = placement_variant
            var module_id: String = str(placement.get("module_id", placement.get("module", "")))
            var scene_path: String = str(module_to_scene.get(module_id, ""))
            if scene_path.is_empty():
                continue
            if not ResourceLoader.exists(scene_path):
                push_error("wrapper scene missing for module %s: %s" % [module_id, scene_path])
                quit(1)
                return count
            var scene: Resource = load(scene_path)
            if scene == null:
                push_error("could not load wrapper scene for module %s: %s" % [module_id, scene_path])
                quit(1)
                return count
            if not (scene is PackedScene):
                push_error("wrapper scene is not PackedScene for module %s: %s" % [module_id, scene_path])
                quit(1)
                return count
            var instance: Node = (scene as PackedScene).instantiate()
            if not (instance is Node3D):
                push_error("wrapper instance is not Node3D for module %s: %s" % [module_id, scene_path])
                quit(1)
                return count
            var placement_pos_variant: Variant = placement.get("position", [])
            if typeof(placement_pos_variant) != TYPE_ARRAY:
                continue
            var placement_pos: Array = placement_pos_variant
            if placement_pos.size() < 3:
                continue
            var wrapper: Node3D = instance as Node3D
            wrapper.position = Vector3(float(placement_pos[0]), float(placement_pos[1]), float(placement_pos[2]))
            wrapper.rotation_degrees.y = float(placement.get("yaw_degrees", 0.0))
            wrapper.name = "%s_%s" % [room_id, str(placement.get("name", module_id))]
            ship_root.add_child(wrapper)
            count += 1
    return count


func _parse_prefixed_int(value: String, prefix: String) -> int:
    if not value.begins_with(prefix):
        return -2147483648
    var number_text: String = value.substr(prefix.length())
    if not number_text.is_valid_int():
        return -2147483648
    return int(number_text)


func _cell_signature_from_placement_name(placement_name: String) -> Array:
    var parts: PackedStringArray = placement_name.split("_")
    if parts.size() < 4:
        return []
    if parts[0] != "floor":
        return []
    var index: int = 2
    var deck: int = 0
    if index < parts.size() and String(parts[index]).begins_with("d"):
        deck = _parse_prefixed_int(String(parts[index]), "d")
        if deck == -2147483648:
            return []
        index += 1
    if index + 1 >= parts.size():
        return []
    var x: int = _parse_prefixed_int(String(parts[index]), "x")
    var z: int = _parse_prefixed_int(String(parts[index + 1]), "z")
    if x == -2147483648 or z == -2147483648:
        return []
    return [x, z, deck]


func _placement_matches_endpoint_cell(placement: Dictionary, endpoint: Array) -> bool:
    if endpoint.size() < 2:
        return false
    var module_id: String = str(placement.get("module_id", placement.get("module", "")))
    if not FLOOR_MODULES.has(module_id):
        return false
    var signature: Array = _cell_signature_from_placement_name(str(placement.get("name", "")))
    if signature.size() != 3:
        return false
    var endpoint_deck: int = 0
    if endpoint.size() >= 3:
        endpoint_deck = int(endpoint[2])
    return int(signature[0]) == int(endpoint[0]) and int(signature[1]) == int(endpoint[1]) and int(signature[2]) == endpoint_deck


func _cell_world_from_link_endpoint(link_doc: Dictionary, cell_key: String, room_key: String, layout_doc: Dictionary) -> Vector3:
    var endpoint_variant: Variant = link_doc.get(cell_key, [])
    if typeof(endpoint_variant) != TYPE_ARRAY:
        return Vector3.INF
    var endpoint: Array = endpoint_variant
    var room_id: String = str(link_doc.get(room_key, ""))
    if room_id.is_empty():
        return Vector3.INF
    var rooms_variant: Variant = layout_doc.get("rooms", [])
    if typeof(rooms_variant) != TYPE_ARRAY:
        return Vector3.INF
    for room_variant in rooms_variant:
        if typeof(room_variant) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_variant
        if str(room.get("id", "")) != room_id:
            continue
        var placements_variant: Variant = room.get("structural_placements", [])
        if typeof(placements_variant) != TYPE_ARRAY:
            return Vector3.INF
        for placement_variant in placements_variant:
            if typeof(placement_variant) != TYPE_DICTIONARY:
                continue
            var placement: Dictionary = placement_variant
            if not _placement_matches_endpoint_cell(placement, endpoint):
                continue
            var pos_variant: Variant = placement.get("position", [])
            if typeof(pos_variant) != TYPE_ARRAY:
                return Vector3.INF
            var pos: Array = pos_variant
            if pos.size() < 3:
                return Vector3.INF
            return Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
    return Vector3.INF


func _add_vertical_links(layout_doc: Dictionary, ship_root: Node3D) -> int:
    var links_variant: Variant = layout_doc.get("vertical_connections", [])
    if typeof(links_variant) != TYPE_ARRAY:
        return 0
    var count: int = 0
    for link_variant in links_variant:
        if typeof(link_variant) != TYPE_DICTIONARY:
            continue
        var link_doc: Dictionary = link_variant
        var from_pos: Vector3 = _cell_world_from_link_endpoint(link_doc, "from_cell", "from_room", layout_doc)
        var to_pos: Vector3 = _cell_world_from_link_endpoint(link_doc, "to_cell", "to_room", layout_doc)
        if from_pos == Vector3.INF or to_pos == Vector3.INF:
            push_warning("Skipping unresolved vertical link %s" % str(link_doc.get("id", count)))
            continue
        var nav_link: NavigationLink3D = NavigationLink3D.new()
        nav_link.name = "VerticalLink_%s" % str(link_doc.get("id", count))
        nav_link.bidirectional = true
        nav_link.start_position = from_pos
        nav_link.end_position = to_pos
        ship_root.add_child(nav_link)
        count += 1
    return count


func _build_navigation_region(rooms: Array, ship_root: Node3D) -> NavigationRegion3D:
    var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
    var floor_cell_count: int = 0
    for room_variant in rooms:
        if typeof(room_variant) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_variant
        var placements_variant: Variant = room.get("structural_placements", [])
        if typeof(placements_variant) != TYPE_ARRAY:
            continue
        for placement_variant in placements_variant:
            if typeof(placement_variant) != TYPE_DICTIONARY:
                continue
            var placement: Dictionary = placement_variant
            var module_id: String = str(placement.get("module_id", placement.get("module", "")))
            if not FLOOR_MODULES.has(module_id):
                continue
            var pos_variant: Variant = placement.get("position", [])
            if typeof(pos_variant) != TYPE_ARRAY:
                continue
            var pos: Array = pos_variant
            if pos.size() < 3:
                continue
            var cell_center: Vector3 = Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
            var half: float = CELL_SIZE * 0.5
            var faces: PackedVector3Array = PackedVector3Array([
                cell_center + Vector3(-half, 0.0, -half),
                cell_center + Vector3(half, 0.0, -half),
                cell_center + Vector3(half, 0.0, half),
                cell_center + Vector3(-half, 0.0, -half),
                cell_center + Vector3(half, 0.0, half),
                cell_center + Vector3(-half, 0.0, half),
            ])
            source.add_faces(faces, Transform3D())
            floor_cell_count += 1

    if floor_cell_count == 0:
        push_error("no floor/corridor floor placements found for navigation mesh")
        return null

    var nav_mesh: NavigationMesh = NavigationMesh.new()
    NavigationMeshGenerator.bake_from_source_geometry_data(nav_mesh, source)

    var nav_region: NavigationRegion3D = NavigationRegion3D.new()
    nav_region.name = "GameplayNavigationRegion"
    nav_region.navigation_mesh = nav_mesh
    ship_root.add_child(nav_region)
    return nav_region


func _room_center(rooms: Array, room_id: String) -> Vector3:
    for room_variant in rooms:
        if typeof(room_variant) != TYPE_DICTIONARY:
            continue
        var room: Dictionary = room_variant
        if str(room.get("id", "")) != room_id:
            continue
        var placements_variant: Variant = room.get("structural_placements", [])
        if typeof(placements_variant) != TYPE_ARRAY:
            break
        var placements: Array = placements_variant
        var total: Vector3 = Vector3.ZERO
        var count: int = 0
        for placement_variant in placements:
            if typeof(placement_variant) != TYPE_DICTIONARY:
                continue
            var placement: Dictionary = placement_variant
            var module_id: String = str(placement.get("module_id", placement.get("module", "")))
            if not FLOOR_MODULES.has(module_id):
                continue
            var pos_variant: Variant = placement.get("position", [])
            if typeof(pos_variant) != TYPE_ARRAY:
                continue
            var pos: Array = pos_variant
            if pos.size() < 3:
                continue
            total += Vector3(float(pos[0]), float(pos[1]) + FLOOR_Y_OFFSET, float(pos[2]))
            count += 1
        if count == 0:
            var origin_variant: Variant = room.get("origin", [0.0, 0.0, 0.0])
            if typeof(origin_variant) == TYPE_ARRAY:
                var origin: Array = origin_variant
                if origin.size() >= 3:
                    return Vector3(float(origin[0]), float(origin[1]) + FLOOR_Y_OFFSET, float(origin[2]))
            return Vector3.INF
        return total / float(count)
    return Vector3.INF
