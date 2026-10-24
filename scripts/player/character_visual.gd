extends Node3D
class_name CharacterVisual

## Scene-side consumer of a `CharacterVisualCatalog` entry (ADR-0070).
##
## Mounts the imported GLB scene (Skeleton3D + skinned meshes + AnimationPlayer
## + bone sockets) under the owning body, toggles equipment meshes from the
## live equipment slots, faces the model along its movement direction and
## selects locomotion clips. It owns NO gameplay state: collision stays on the
## CharacterBody3D capsule (ADR-0052 §3 / ADR-0058), equipment truth stays in
## EquipmentState, and the owner pushes velocity/crouch/working each physics
## frame, so this node works identically on the home and away branches of the
## coordinator's `_process` (CLAUDE.md dual-branch rule) because it never
## depends on that tick at all.

const DEFAULT_TURN_RATE: float = 14.0
const DEFAULT_MOVING_THRESHOLD: float = 0.05
const DEFAULT_EQUIPMENT_PREFIX: String = "Equip_"
const DEFAULT_LOOPING_LOGICALS: Array = ["idle", "walk", "crouch_idle", "crouch_walk", "work"]
const CLASS_ACCENT_DEFAULT: Color = Color(0.95, 0.45, 0.10, 1.0)

var entry: Dictionary = {}
var model_root: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var mounted: bool = false
var visual_source: String = "fallback"

var _mesh_nodes: Dictionary = {}       # node name -> MeshInstance3D
var _equipment_slots: Dictionary = {}  # slot -> item_id (last applied)
var _visible_equipment_nodes: Array[String] = []
var _logical_to_clip: Dictionary = {}
var _current_logical: String = ""
var _action_logical: String = ""
var _working: bool = false
var _downed: bool = false
var _moving: bool = false
var _crouching: bool = false
var _turn_rate: float = DEFAULT_TURN_RATE
var _moving_threshold: float = DEFAULT_MOVING_THRESHOLD
var _equipment_prefix: String = DEFAULT_EQUIPMENT_PREFIX


## Factory used by PlayerController: resolves the catalog entry, loads the GLB
## PackedScene and returns a mounted CharacterVisual, or null so the caller
## keeps its capsule marker. Loading failures are reported as data (null),
## never as push_warning/push_error, so a missing art drop never turns the
## regression bundle red.
static func mount_from_catalog(character_id: String, catalog_path: String = CharacterVisualCatalog.DEFAULT_CATALOG_PATH) -> CharacterVisual:
	var catalog := CharacterVisualCatalog.new()
	catalog.load_from_path(catalog_path)
	var catalog_entry: Dictionary = catalog.get_entry(character_id)
	if catalog_entry.is_empty():
		return null
	var scene_path: String = str(catalog_entry.get("scene_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return null
	var packed: Resource = load(scene_path)
	if not (packed is PackedScene):
		return null
	var visual := CharacterVisual.new()
	visual.name = "CharacterVisual"
	if not visual.mount(packed as PackedScene, catalog_entry):
		visual.free()
		return null
	return visual


func mount(packed: PackedScene, catalog_entry: Dictionary) -> bool:
	if packed == null:
		return false
	var instance: Node = packed.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.free()
		return false
	entry = catalog_entry.duplicate(true)
	_turn_rate = float(entry.get("turn_rate_rad_per_s", DEFAULT_TURN_RATE))
	_moving_threshold = float(entry.get("moving_speed_threshold", DEFAULT_MOVING_THRESHOLD))
	_equipment_prefix = str(entry.get("equipment_node_prefix", DEFAULT_EQUIPMENT_PREFIX))
	_logical_to_clip = (entry.get("animations", {}) as Dictionary).duplicate(true)
	model_root = instance as Node3D
	model_root.name = "Model"
	add_child(model_root)
	skeleton = _find_first(model_root, "Skeleton3D") as Skeleton3D
	animation_player = _find_first(model_root, "AnimationPlayer") as AnimationPlayer
	_mesh_nodes.clear()
	for mesh in model_root.find_children("*", "MeshInstance3D", true, false):
		_mesh_nodes[mesh.name] = mesh
	if skeleton == null or animation_player == null or _mesh_nodes.is_empty():
		model_root.queue_free()
		model_root = null
		return false
	_configure_loops()
	set_equipment_slots({})
	mounted = true
	visual_source = "catalog"
	_play_logical("idle", true)
	return true


## Equipment truth comes from EquipmentState.slots ({slot -> item_id}). Any
## `Equip_*` node whose prefix is listed for an equipped item becomes visible;
## everything else under the equipment prefix is hidden.
func set_equipment_slots(slots: Dictionary) -> void:
	_equipment_slots = slots.duplicate(true)
	var visuals: Dictionary = entry.get("equipment_visuals", {}) as Dictionary
	var active_prefixes: Array[String] = []
	for slot in slots.keys():
		var item_id: String = str(slots[slot])
		if item_id.is_empty() or not visuals.has(item_id):
			continue
		var prefixes: Variant = visuals[item_id]
		if prefixes is Array:
			for p in prefixes:
				active_prefixes.append(str(p))
	_visible_equipment_nodes.clear()
	for node_name in _mesh_nodes.keys():
		var name_str: String = str(node_name)
		if not name_str.begins_with(_equipment_prefix):
			continue
		var visible: bool = false
		for prefix in active_prefixes:
			if name_str.begins_with(prefix):
				visible = true
				break
		(_mesh_nodes[node_name] as MeshInstance3D).visible = visible
		if visible:
			_visible_equipment_nodes.append(name_str)
	_visible_equipment_nodes.sort()


func get_visible_equipment_nodes() -> Array[String]:
	return _visible_equipment_nodes.duplicate()


func is_equipment_node_visible(node_name: String) -> bool:
	var mesh: MeshInstance3D = _mesh_nodes.get(node_name, null) as MeshInstance3D
	return mesh != null and mesh.visible


## Per-physics-frame locomotion feed from the owning CharacterBody3D.
func update_locomotion(velocity: Vector3, crouching: bool, delta: float) -> void:
	if not mounted:
		return
	var planar: Vector2 = Vector2(velocity.x, velocity.z)
	_moving = planar.length() > _moving_threshold
	_crouching = crouching
	if _moving:
		var target_yaw: float = atan2(planar.x, planar.y)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * _turn_rate, 0.0, 1.0))
	_refresh_locomotion_clip()


func set_working(working: bool) -> void:
	if _working == working:
		return
	_working = working
	_refresh_locomotion_clip()


func set_downed(downed: bool) -> void:
	if _downed == downed:
		return
	_downed = downed
	if _downed:
		_action_logical = ""
		_play_logical("downed", false)
	else:
		_refresh_locomotion_clip()


## One-shot actions (melee / aim). They override locomotion until the clip
## finishes, then locomotion resumes automatically.
func play_action(logical: String) -> bool:
	if not mounted or _downed:
		return false
	if not _logical_to_clip.has(logical):
		return false
	_action_logical = logical
	return _play_logical(logical, false)


func get_current_animation() -> String:
	if animation_player == null:
		return ""
	return animation_player.current_animation


func get_current_logical() -> String:
	return _current_logical


func get_socket(socket_key: String) -> Node3D:
	if model_root == null:
		return null
	var sockets: Dictionary = entry.get("sockets", {}) as Dictionary
	var node_name: String = str(sockets.get(socket_key, socket_key))
	var found: Node = model_root.find_child(node_name, true, false)
	return found as Node3D


func set_class_accent(color: Color) -> void:
	var accent_name: String = str(entry.get("class_accent_node", "Body_ClassAccent"))
	var mesh: MeshInstance3D = _mesh_nodes.get(accent_name, null) as MeshInstance3D
	if mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	mesh.material_override = material


func get_bone_names() -> Array[String]:
	var names: Array[String] = []
	if skeleton == null:
		return names
	for i in range(skeleton.get_bone_count()):
		names.append(skeleton.get_bone_name(i))
	return names


func get_animation_names() -> Array[String]:
	var names: Array[String] = []
	if animation_player == null:
		return names
	for n in animation_player.get_animation_list():
		names.append(str(n))
	return names


func get_facing_yaw() -> float:
	return rotation.y


# --- internals ---------------------------------------------------------------

func _refresh_locomotion_clip() -> void:
	if not mounted or _downed:
		return
	if not _action_logical.is_empty() and animation_player.is_playing() \
			and animation_player.current_animation == str(_logical_to_clip.get(_action_logical, "")):
		return
	_action_logical = ""
	var logical: String
	if _working and not _moving:
		logical = "work"
	elif _crouching:
		logical = "crouch_walk" if _moving else "crouch_idle"
	else:
		logical = "walk" if _moving else "idle"
	_play_logical(logical, true)


func _play_logical(logical: String, keep_if_playing: bool) -> bool:
	var clip: String = str(_logical_to_clip.get(logical, ""))
	if clip.is_empty() or animation_player == null or not animation_player.has_animation(clip):
		return false
	if keep_if_playing and animation_player.current_animation == clip and animation_player.is_playing():
		_current_logical = logical
		return true
	animation_player.play(clip, 0.12)
	_current_logical = logical
	return true


func _configure_loops() -> void:
	# Godot's scene importer strips a glTF "-loop" suffix and marks the clip
	# looping. The catalog restates which LOGICAL clips loop so a hand-edited
	# catalog or a re-exported kit cannot silently lose the loop flags.
	var looping: Array = entry.get("looping_animations", DEFAULT_LOOPING_LOGICALS) as Array
	var loop_clips: Dictionary = {}
	for logical in looping:
		loop_clips[str(_logical_to_clip.get(str(logical), ""))] = true
	for clip_name in animation_player.get_animation_list():
		var anim: Animation = animation_player.get_animation(clip_name)
		if anim == null:
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if loop_clips.has(str(clip_name)) else Animation.LOOP_NONE


func is_looping_clip(clip_name: String) -> bool:
	if animation_player == null or not animation_player.has_animation(clip_name):
		return false
	return animation_player.get_animation(clip_name).loop_mode == Animation.LOOP_LINEAR


static func _find_first(root: Node, type_name: String) -> Node:
	if root == null:
		return null
	if root.is_class(type_name):
		return root
	for child in root.get_children():
		var found: Node = _find_first(child, type_name)
		if found != null:
			return found
	return null
