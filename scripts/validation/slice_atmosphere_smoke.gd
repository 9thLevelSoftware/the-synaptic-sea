extends SceneTree

## Task 1.4: biome atmosphere/lighting is applied to a generated-scene root.
## Marker: SLICE ATMOSPHERE PASS

const AtmosphereApplierScript := preload("res://scripts/procgen/slice_atmosphere_applier.gd")
const BREACH_BIOME_PATH: String = "res://data/procgen/biomes/breach_field.json"


func _initialize() -> void:
	var biome_data: Dictionary = _load_json_dict(BREACH_BIOME_PATH)
	var atmosphere_variant: Variant = biome_data.get("atmosphere", {})
	if not (atmosphere_variant is Dictionary) or (atmosphere_variant as Dictionary).is_empty():
		_fail("breach_field atmosphere block missing")
		return
	var atmosphere: Dictionary = atmosphere_variant

	var root := Node3D.new()
	root.name = "AtmosphereSmokeRoot"
	get_root().add_child(root)

	var environment_node := WorldEnvironment.new()
	environment_node.name = "DefaultWorldEnvironment"
	var default_environment := Environment.new()
	default_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	default_environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	default_environment.ambient_light_energy = 1.0
	environment_node.environment = default_environment
	root.add_child(environment_node)

	var default_key_light := DirectionalLight3D.new()
	default_key_light.name = "DefaultKeyLight"
	default_key_light.light_color = Color.WHITE
	default_key_light.light_energy = 1.0
	root.add_child(default_key_light)

	var applier = AtmosphereApplierScript.new()
	var applied: Dictionary = applier.apply(root, atmosphere, false)
	if not bool(applied.get("applied", false)):
		_fail("atmosphere applier did not apply")
		return
	if default_environment.ambient_light_color == Color(0.8, 0.8, 0.8):
		_fail("ambient color remained at default")
		return
	if not default_environment.fog_enabled:
		_fail("fog was not enabled")
		return
	if is_zero_approx(default_environment.fog_density):
		_fail("fog density remained at default")
		return

	var key_light: DirectionalLight3D = root.get_node_or_null("DefaultKeyLight") as DirectionalLight3D
	if key_light == null:
		_fail("slice key light missing")
		return
	if not is_zero_approx(key_light.light_energy - 0.55):
		_fail("key light energy was not applied")
		return

	var away_root := Node3D.new()
	away_root.name = "AwayAtmosphereSmokeRoot"
	get_root().add_child(away_root)
	var away_environment_node := WorldEnvironment.new()
	away_environment_node.name = "DefaultWorldEnvironment"
	var away_environment := Environment.new()
	away_environment_node.environment = away_environment
	away_root.add_child(away_environment_node)
	applier.apply(away_root, atmosphere, true)
	if away_environment.fog_density <= default_environment.fog_density:
		_fail("away fog was not denser than aboard fog")
		return

	print("SLICE ATMOSPHERE PASS ambient=true fog=true away_fog=true key_light=true")
	quit(0)


func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _fail(reason: String) -> void:
	push_error("SLICE ATMOSPHERE FAIL %s" % reason)
	quit(1)
