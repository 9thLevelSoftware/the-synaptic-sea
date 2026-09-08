extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene_path := "res://scenes/validation/room_kit_v2_pilot.tscn"
	if not ResourceLoader.exists(scene_path):
		print("ROOM_KIT_PILOT_TEST_FAIL missing preview scene")
		quit(1)
		return
	var scene: PackedScene = load(scene_path)
	var pilot: Node3D = scene.instantiate()
	pilot.set("auto_capture", false)
	root.add_child(pilot)
	await process_frame
	var camera: Camera3D = pilot.get_node_or_null("Camera3D")
	if camera == null or camera.projection != Camera3D.PROJECTION_ORTHOGONAL or camera.size != 22.0 or camera.position != Vector3(16,18,16):
		_fail(pilot, "production camera contract")
		return
	if not pilot.has_method("selected_paths"):
		_fail(pilot, "explicit baseline-shell selection missing")
		return
	var mixed_paths: Dictionary = pilot.call("selected_paths", "res://candidate-stage", false, true)
	if mixed_paths["floor_1x1"] != "res://assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb" or mixed_paths["coolant_pump_skid_derelict_v1"] != "res://candidate-stage/props/coolant_pump_skid_derelict_v1.glb":
		_fail(pilot, "baseline shell must never substitute candidate props")
		return
	# Valid GLB container with an empty node is not visual evidence.
	var empty_path := "user://room_kit_v2_empty_payload_test.glb"
	var document := JSON.stringify({"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{}]}).to_utf8_buffer()
	while document.size() % 4 != 0:
		document.append(32)
	var fixture := FileAccess.open(empty_path, FileAccess.WRITE)
	fixture.store_buffer("glTF".to_utf8_buffer())
	fixture.store_32(2)
	fixture.store_32(20 + document.size())
	fixture.store_32(document.size())
	fixture.store_buffer("JSON".to_utf8_buffer())
	fixture.store_buffer(document)
	fixture.close()
	var empty_visual: Node3D = pilot.call("_load_visual",empty_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(empty_path))
	if empty_visual != null:
		empty_visual.free()
		_fail(pilot,"semantically empty GLB accepted")
		return
	# Missing input must not create substitute geometry or partial composition.
	var missing: Dictionary = {}
	for asset_id in pilot.get("ASSET_IDS"):
		missing[asset_id] = "res://assets/_staging/room_kit_v2/absent-"+str(asset_id)+".glb"
	if pilot.call("build_preview", missing) or pilot.get_node("Models").get_child_count() != 0:
		_fail(pilot, "missing input accepted or partial geometry leaked")
		return
	# Characterization fixture uses existing real GLBs, never candidate approval.
	var paths: Dictionary = {}
	for asset_id in pilot.get("STRUCTURAL_IDS"):
		paths[asset_id] = "res://assets/imported/structural/ship_structural_v0/%s/%s.glb" % [asset_id, asset_id]
	for asset_id in pilot.get("PROP_IDS"):
		paths[asset_id] = "res://assets/imported/props/dressing/fabrication_station_derelict_v1.glb"
	if not pilot.call("build_preview", paths):
		_fail(pilot, "real GLB characterization composition rejected")
		return
	var models: Node3D = pilot.get_node("Models")
	if models.get_child_count() != 18:
		_fail(pilot, "expected eighteen real GLB instances")
		return
	var counts: Dictionary = {}
	for child in models.get_children():
		var asset_id := str(child.get_meta("pilot_asset_id", ""))
		counts[asset_id] = int(counts.get(asset_id,0))+1
	if counts.get("floor_1x1",0) != 9 or counts.get("wall_straight_1x1",0) != 4 or counts.get("pillar_support_1x1",0) != 1:
		_fail(pilot, "composition inventory")
		return
	for asset_id in pilot.get("PROP_IDS"):
		if counts.get(asset_id,0) != 1:
			_fail(pilot, "missing prop instance")
			return
	# The live floor has node transforms; Godot measures top Y=0.3395m,
	# unlike raw accessor-local max Y=0.125m. Keep that distinction explicit.
	for node in pilot.get_node("Models").get_children():
		var asset_id := str(node.get_meta("pilot_asset_id", ""))
		if asset_id in pilot.PROP_IDS and absf(node.position.y - 0.3395) > 0.0001:
			_fail(pilot, "prop not placed on measured baseline floor top: %s" % str(node.position))
			return
	# Rebuilding replaces only this preview's owned models, without duplicates.
	if not pilot.call("build_preview", paths) or models.get_child_count() != 18:
		_fail(pilot, "repeat build leaked instances")
		return
	pilot.free()
	print("ROOM_KIT_PILOT_TEST_PASS real_instances=18 missing_rejected=true repeat_stable=true characterization_only=true")
	quit(0)

func _fail(pilot: Node, message: String) -> void:
	pilot.free()
	print("ROOM_KIT_PILOT_TEST_FAIL "+message)
	quit(1)
