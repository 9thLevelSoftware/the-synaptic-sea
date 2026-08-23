extends RefCounted
class_name SliceAtmosphereApplier

## Applies biome-authored atmosphere to a generated ship scene.
##
## `world_env_or_root` may be either a WorldEnvironment or any Node3D root.
## When given a root, the pass reuses the first WorldEnvironment and
## DirectionalLight3D it finds, creating slice-owned nodes when absent.
## The return value is a small validation/runtime summary for callers that
## want to record which parts of the pass were available.

const DEFAULT_AMBIENT_COLOR: Color = Color("1a2430")
const DEFAULT_AMBIENT_ENERGY: float = 0.35
const DEFAULT_FOG_COLOR: Color = Color("2a3540")
const DEFAULT_FOG_DENSITY: float = 0.02
const DEFAULT_KEY_COLOR: Color = Color("c8d4e0")
const DEFAULT_KEY_ENERGY: float = 0.55
const DEFAULT_AWAY_FOG_MULTIPLIER: float = 1.6
const DEFAULT_EMERGENCY_ACCENT_ENERGY: float = 0.16


func apply(world_env_or_root: Node, atmosphere: Dictionary, is_away: bool) -> Dictionary:
	if world_env_or_root == null:
		return {"applied": false, "reason": "null_target"}

	var environment_node: WorldEnvironment = _resolve_world_environment(world_env_or_root)
	if environment_node == null:
		return {"applied": false, "reason": "no_world_environment"}
	if environment_node.environment == null:
		environment_node.environment = Environment.new()

	var environment: Environment = environment_node.environment
	var ambient_color: Color = _color_value(atmosphere.get("ambient_color", "#1a2430"), DEFAULT_AMBIENT_COLOR)
	var ambient_energy: float = _non_negative_float(atmosphere.get("ambient_energy", DEFAULT_AMBIENT_ENERGY), DEFAULT_AMBIENT_ENERGY)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy

	var fog_enabled: bool = bool(atmosphere.get("fog_enabled", false))
	environment.fog_enabled = fog_enabled
	var fog_density: float = _non_negative_float(atmosphere.get("fog_density", DEFAULT_FOG_DENSITY), DEFAULT_FOG_DENSITY)
	if is_away:
		var away_multiplier: float = _non_negative_float(
			atmosphere.get("away_fog_density_mult", DEFAULT_AWAY_FOG_MULTIPLIER),
			DEFAULT_AWAY_FOG_MULTIPLIER)
		fog_density *= maxf(1.0, away_multiplier)
	environment.fog_density = fog_density
	environment.fog_light_color = _color_value(atmosphere.get("fog_light_color", "#2a3540"), DEFAULT_FOG_COLOR)

	var key_light: DirectionalLight3D = _resolve_key_light(world_env_or_root)
	if key_light != null:
		key_light.light_color = _color_value(atmosphere.get("key_light_color", "#c8d4e0"), DEFAULT_KEY_COLOR)
		key_light.light_energy = _non_negative_float(atmosphere.get("key_light_energy", DEFAULT_KEY_ENERGY), DEFAULT_KEY_ENERGY)
		key_light.set_meta("slice_atmosphere", true)

	var accent_light: OmniLight3D = _apply_emergency_accent(world_env_or_root, atmosphere)
	return {
		"applied": true,
		"fog_enabled": fog_enabled,
		"fog_density": fog_density,
		"ambient_energy": ambient_energy,
		"key_light_applied": key_light != null,
		"emergency_accent_applied": accent_light != null,
		"is_away": is_away,
	}


func _resolve_world_environment(target: Node) -> WorldEnvironment:
	if target is WorldEnvironment:
		return target as WorldEnvironment
	var existing: WorldEnvironment = _find_world_environment(target)
	if existing != null:
		return existing
	if not (target is Node3D):
		return null
	var created := WorldEnvironment.new()
	created.name = "SliceAtmosphereWorldEnvironment"
	(target as Node3D).add_child(created)
	return created


func _resolve_key_light(target: Node) -> DirectionalLight3D:
	var existing: DirectionalLight3D = _find_directional_light(target)
	if existing != null:
		return existing
	if not (target is Node3D):
		return null
	var created := DirectionalLight3D.new()
	created.name = "SliceAtmosphereKeyLight"
	created.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	(target as Node3D).add_child(created)
	return created


func _apply_emergency_accent(target: Node, atmosphere: Dictionary) -> OmniLight3D:
	var raw_accent: Variant = atmosphere.get("emergency_accent", null)
	if raw_accent == null or str(raw_accent).is_empty() or not (target is Node3D):
		return null
	var existing: Node = (target as Node3D).get_node_or_null("SliceAtmosphereEmergencyAccent")
	var accent: OmniLight3D = existing as OmniLight3D if existing is OmniLight3D else null
	if accent == null:
		accent = OmniLight3D.new()
		accent.name = "SliceAtmosphereEmergencyAccent"
		accent.position = Vector3(0.0, 2.5, 0.0)
		accent.omni_range = 12.0
		(target as Node3D).add_child(accent)
	accent.light_color = _color_value(raw_accent, Color("ff6a3d"))
	accent.light_energy = _non_negative_float(
		atmosphere.get("emergency_accent_energy", DEFAULT_EMERGENCY_ACCENT_ENERGY),
		DEFAULT_EMERGENCY_ACCENT_ENERGY)
	accent.set_meta("slice_atmosphere", true)
	return accent


func _find_world_environment(node: Node) -> WorldEnvironment:
	for child in node.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
		var nested: WorldEnvironment = _find_world_environment(child)
		if nested != null:
			return nested
	return null


func _find_directional_light(node: Node) -> DirectionalLight3D:
	for child in node.get_children():
		if child is DirectionalLight3D:
			return child as DirectionalLight3D
		var nested: DirectionalLight3D = _find_directional_light(child)
		if nested != null:
			return nested
	return null


func _color_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	if value is String or value is StringName:
		return Color.from_string(str(value), fallback)
	if value is Array and (value as Array).size() >= 3:
		var channels: Array = value as Array
		return Color(float(channels[0]), float(channels[1]), float(channels[2]), 1.0)
	return fallback


func _non_negative_float(value: Variant, fallback: float) -> float:
	var parsed: float = fallback
	if value is float or value is int:
		parsed = float(value)
	elif value is String:
		parsed = float(value)
	if is_nan(parsed) or is_inf(parsed):
		return fallback
	return maxf(0.0, parsed)
