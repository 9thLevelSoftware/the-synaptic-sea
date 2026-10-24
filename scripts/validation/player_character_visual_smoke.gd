extends SceneTree

## ADR-0070 pure-ish smoke for the player character visual seam:
## catalog loads, the survivor_v1 GLB mounts on a bare PlayerController
## (capsule marker hidden, collision untouched), the Skeleton3D carries the
## manifest bones, the AnimationPlayer carries every clip with -loop clips
## looping, equipment slots toggle Equip_* nodes, locomotion selects clips and
## faces the model along +Z of travel, one-shot actions override locomotion,
## and an unknown catalog entry keeps the capsule fallback.
##
## Pass marker:
##   PLAYER CHARACTER VISUAL PASS mounted=true bones=20 clips=8 loops=true equipment=true facing=true locomotion=true action=true downed=true fallback=true

const CatalogScript := preload("res://scripts/systems/character_visual_catalog.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const CharacterVisualScript := preload("res://scripts/player/character_visual.gd")
const MANIFEST_PATH: String = "res://assets/imported/characters/survivor_v1/survivor_v1.manifest.json"

var _failures: Array[String] = []
var _started: bool = false


func _initialize() -> void:
	# Node _ready() callbacks are only guaranteed once the tree is processing;
	# run the whole smoke on the first process frame like the main-scene smokes.
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	if _started:
		return
	_started = true
	_run()


func _run() -> void:
	var catalog = CatalogScript.new()
	_expect(catalog.load_from_path(), "catalog loads: %s" % str(catalog.get_errors()))
	var entry: Dictionary = catalog.get_entry("player_survivor")
	_expect(not entry.is_empty(), "player_survivor entry present")
	_expect(catalog.get_entry("no_such_character").is_empty(), "unknown entry is empty")
	var bad_entry: Dictionary = entry.duplicate(true)
	bad_entry.erase("animations")
	_expect(not CatalogScript.validate_entry(bad_entry).is_empty(), "entry without animations is rejected")

	var manifest: Dictionary = _load_json(MANIFEST_PATH)
	_expect(not manifest.is_empty(), "kit manifest readable")
	var manifest_bones: Array = manifest.get("bones", []) as Array
	# Godot's importer strips the glTF "-loop" suffix (and flags the clip as
	# looping), so the runtime clip names are the manifest names without it.
	var manifest_clips: Array = []
	var manifest_loop_clips: Dictionary = {}
	for raw_clip in manifest.get("animations", []) as Array:
		var clip_name: String = str(raw_clip)
		if clip_name.ends_with("-loop"):
			clip_name = clip_name.trim_suffix("-loop")
			manifest_loop_clips[clip_name] = true
		manifest_clips.append(clip_name)

	# Mount on a bare player (no ship) — the seam must not need the coordinator.
	var player: PlayerController = PlayerControllerScript.new()
	get_root().add_child(player)
	# This bare player has no floor; the engine must not tick it while the
	# smoke drives the provider sync with one explicit tick below.
	player.set_physics_process(false)
	var mounted: bool = player.has_character_visual()
	_expect(mounted, "character visual mounted from catalog")
	_expect(player.marker != null and not player.marker.visible, "capsule marker hidden when mounted")
	_expect(player.collision_shape != null and player.collision_shape.shape is CapsuleShape3D, "collision capsule untouched")
	_expect(player.get_visual_source() == "catalog", "visual_source=catalog")

	var bones_ok: bool = false
	var clips_ok: bool = false
	var loops_ok: bool = false
	var equipment_ok: bool = false
	var facing_ok: bool = false
	var locomotion_ok: bool = false
	var action_ok: bool = false
	var downed_ok: bool = false
	var bone_count: int = 0
	var clip_count: int = 0
	if mounted:
		var visual: CharacterVisualScript = player.character_visual
		var bones: Array[String] = visual.get_bone_names()
		bone_count = bones.size()
		bones_ok = bones.size() == manifest_bones.size()
		for b in manifest_bones:
			if not bones.has(str(b)):
				bones_ok = false
		_expect(bones_ok, "skeleton bones match manifest (%d)" % bones.size())

		var clips: Array[String] = visual.get_animation_names()
		clip_count = clips.size()
		clips_ok = clips.size() == manifest_clips.size()
		for c in manifest_clips:
			if not clips.has(str(c)):
				clips_ok = false
		_expect(clips_ok, "animation clips match manifest (%d)" % clips.size())

		loops_ok = true
		for c in clips:
			var should_loop: bool = manifest_loop_clips.has(c)
			if visual.is_looping_clip(c) != should_loop:
				loops_ok = false
		_expect(loops_ok, "manifest -loop clips loop, others do not")

		# Equipment: nothing visible by default; hardsuit shows plates + helmet.
		var default_visible: Array[String] = visual.get_visible_equipment_nodes()
		_expect(default_visible.is_empty(), "no equipment visible by default")
		visual.set_equipment_slots({"suit": "hardsuit", "back": "eva_backpack"})
		var hardsuit_visible: bool = visual.is_equipment_node_visible("Equip_Hardsuit_Chest") \
			and visual.is_equipment_node_visible("Equip_Helmet") \
			and visual.is_equipment_node_visible("Equip_EVABackpack") \
			and not visual.is_equipment_node_visible("Equip_FieldPack") \
			and not visual.is_equipment_node_visible("Equip_ToolBelt")
		visual.set_equipment_slots({"back": "field_pack", "waist": "tool_belt"})
		var pack_visible: bool = visual.is_equipment_node_visible("Equip_FieldPack") \
			and visual.is_equipment_node_visible("Equip_ToolBelt") \
			and not visual.is_equipment_node_visible("Equip_Hardsuit_Chest") \
			and not visual.is_equipment_node_visible("Equip_Helmet")
		visual.set_equipment_slots({})
		equipment_ok = hardsuit_visible and pack_visible and visual.get_visible_equipment_nodes().is_empty()
		_expect(equipment_ok, "equipment slots toggle Equip_* nodes")

		# Provider path through the player (what the coordinator uses).
		var provided: Dictionary = {"suit": "hardsuit"}
		player.bind_visual_providers(func() -> Dictionary: return provided, func() -> bool: return false)
		player.set_scripted_move_direction(Vector3.ZERO)
		player._physics_process(1.0 / 60.0)
		_expect(visual.is_equipment_node_visible("Equip_Helmet"), "provider-driven equipment sync")

		# Locomotion + facing: walking along +Z keeps yaw 0; along +X turns to +90 deg.
		visual.rotation.y = 0.0
		visual.update_locomotion(Vector3(0.0, 0.0, 3.0), false, 1.0)
		var walk_clip_ok: bool = visual.get_current_logical() == "walk"
		var yaw_z: float = visual.get_facing_yaw()
		visual.update_locomotion(Vector3(3.0, 0.0, 0.0), false, 1.0)
		var yaw_x: float = visual.get_facing_yaw()
		facing_ok = absf(yaw_z) < 0.01 and absf(yaw_x - PI * 0.5) < 0.01
		_expect(facing_ok, "faces +Z of travel (yaw_z=%.3f yaw_x=%.3f)" % [yaw_z, yaw_x])
		visual.update_locomotion(Vector3(3.0, 0.0, 0.0), true, 1.0)
		var crouch_walk_ok: bool = visual.get_current_logical() == "crouch_walk"
		visual.update_locomotion(Vector3.ZERO, true, 1.0)
		var crouch_idle_ok: bool = visual.get_current_logical() == "crouch_idle"
		visual.update_locomotion(Vector3.ZERO, false, 1.0)
		var idle_ok: bool = visual.get_current_logical() == "idle"
		visual.set_working(true)
		var work_ok: bool = visual.get_current_logical() == "work"
		visual.set_working(false)
		locomotion_ok = walk_clip_ok and crouch_walk_ok and crouch_idle_ok and idle_ok and work_ok \
			and visual.get_current_logical() == "idle"
		_expect(locomotion_ok, "locomotion clip selection (walk/crouch/idle/work)")

		# One-shot action overrides locomotion while playing.
		action_ok = player.play_visual_action("melee") and visual.get_current_animation() == "melee_swing"
		visual.update_locomotion(Vector3(0.0, 0.0, 3.0), false, 1.0 / 60.0)
		action_ok = action_ok and visual.get_current_animation() == "melee_swing"
		_expect(action_ok, "melee action overrides locomotion while playing")

		player.set_visual_downed(true)
		downed_ok = visual.get_current_animation() == "downed"
		visual.update_locomotion(Vector3(0.0, 0.0, 3.0), false, 1.0)
		downed_ok = downed_ok and visual.get_current_animation() == "downed"
		player.set_visual_downed(false)
		downed_ok = downed_ok and visual.get_current_logical() != "downed"
		_expect(downed_ok, "downed holds until cleared")

		# Sockets exist as bone-attached nodes for handheld tools.
		_expect(visual.get_socket("primary_hand") != null, "primary_hand socket present")

	# Fallback: an unknown catalog id refuses to mount (capsule marker stays).
	var fallback_visual: CharacterVisualScript = CharacterVisualScript.new()
	var fallback_ok: bool = not fallback_visual.mount_catalog_entry("no_such_character") and not fallback_visual.mounted
	fallback_visual.free()
	_expect(fallback_ok, "unknown catalog id does not mount (capsule fallback)")

	player.queue_free()
	if not _failures.is_empty():
		for f in _failures:
			print("  FAIL: %s" % f)
		print("PLAYER CHARACTER VISUAL FAIL failures=%d" % _failures.size())
		quit(1)
		return
	print("PLAYER CHARACTER VISUAL PASS mounted=%s bones=%d clips=%d loops=%s equipment=%s facing=%s locomotion=%s action=%s downed=%s fallback=%s" % [
		str(mounted).to_lower(), bone_count, clip_count, str(loops_ok).to_lower(), str(equipment_ok).to_lower(),
		str(facing_ok).to_lower(), str(locomotion_ok).to_lower(), str(action_ok).to_lower(), str(downed_ok).to_lower(),
		str(fallback_ok).to_lower(),
	])
	quit(0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
