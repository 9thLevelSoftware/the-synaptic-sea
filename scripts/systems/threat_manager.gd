extends Node3D
class_name ThreatManager

const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const DetectionStateScript := preload("res://scripts/systems/detection_state.gd")
const DamagePipelineScript := preload("res://scripts/systems/damage_pipeline.gd")
const THREAT_ARCHETYPE_PATH: String = "res://data/combat/threat_archetypes.json"
const WEAPON_DEFINITIONS_PATH: String = "res://data/combat/weapon_definitions.json"
const AMMO_DEFINITIONS_PATH: String = "res://data/combat/ammo_definitions.json"
const SIGHT_RANGE: float = 12.0

var threat_archetypes: Dictionary = {}
var weapon_definitions: Dictionary = {}
var ammo_definitions: Dictionary = {}
var encounter_markers: Array = []
var threats: Array = []
var detection_state = DetectionStateScript.new()
var damage_pipeline = DamagePipelineScript.new()
var player_noise: float = 0.1
var player_light: float = 0.35
var player_sight: float = 0.5
var player_crouching: bool = false
var player_room_id: String = ""
var fallback_anchor: Vector3 = Vector3.ZERO
var awareness_indicator: float = 0.0
var combat_engaged: bool = false
var last_attack_result: Dictionary = {}
var placeholder_nodes: Dictionary = {}

func _ready() -> void:
	threat_archetypes = _load_json_dict(THREAT_ARCHETYPE_PATH)
	weapon_definitions = _load_json_dict(WEAPON_DEFINITIONS_PATH)
	ammo_definitions = _load_json_dict(AMMO_DEFINITIONS_PATH)
	damage_pipeline.configure({})
	detection_state.configure({})

func configure_for_layout(layout: Dictionary, markers: Array = [], anchor: Vector3 = Vector3.ZERO) -> void:
	fallback_anchor = anchor
	encounter_markers = markers.duplicate(true)
	if encounter_markers.is_empty():
		encounter_markers = _fallback_markers_from_layout(layout)
	_spawn_from_markers(encounter_markers, fallback_anchor)

func inject_validation_encounter(archetype_ids: Array, anchor: Vector3 = Vector3.ZERO) -> void:
	var markers: Array = []
	var idx: int = 0
	for archetype_id in archetype_ids:
		markers.append({
			"id": "validation_%d" % idx,
			"room_id": "validation_room_%d" % idx,
			"cell": [idx, 0],
			"encounter_kind": str(archetype_id),
			"count": 1,
		})
		idx += 1
	encounter_markers = markers
	_spawn_from_markers(markers, anchor)

func set_player_signals(noise: float, light: float, sight: float, crouching: bool, room_id: String = "") -> void:
	player_noise = clampf(noise, 0.0, 2.0)
	player_light = clampf(light, 0.0, 2.0)
	player_sight = clampf(sight, 0.0, 2.0)
	player_crouching = crouching
	player_room_id = room_id

func tick_threats(delta: float, vitals_state = null, status_effects_state = null, player_armor_profile: Dictionary = {}, player_position: Vector3 = Vector3.ZERO) -> void:
	detection_state.update_inputs(player_noise, player_light, player_sight, player_crouching, player_room_id)
	detection_state.tick(delta)
	awareness_indicator = 0.0
	combat_engaged = false
	# The emitted profile is constant for the whole tick (detection ticked above) —
	# fetch once, not per threat.
	var profile: Dictionary = detection_state.get_emitted_profile()
	for threat in threats:
		if threat == null:
			continue
		var same_room: bool = player_room_id.is_empty() or threat.room_id == player_room_id
		var prox: float = _proximity_factor(threat, player_position)
		threat.tick(delta, {
			"noise_level": float(profile["noise"]),
			"light_level": float(profile["light"]),
			"sight_level": float(profile["visibility"]) * prox,
			"crouching": false,  # crouch already applied in the emitted profile (no double-count)
			"room_id": player_room_id,
			"same_room": same_room,
			"detect_threshold": detection_state.detect_threshold,
		})
		awareness_indicator = maxf(awareness_indicator, float(threat.awareness_score))
		if same_room and threat.can_attack() and vitals_state != null:
			last_attack_result = damage_pipeline.apply_to_vitals(vitals_state, status_effects_state, player_armor_profile, {
				"damage_type": threat.attack_type,
				"amount": threat.attack_damage,
				"noise": threat.attack_noise,
				"status_effect_id": threat.status_on_hit,
				"source_id": threat.instance_id,
			})
			threat.consume_attack()
			combat_engaged = true
		_update_placeholder(threat, player_position)

func attack_with_weapon(weapon_id: String, inventory_state, equipment_state, target_id: String = "") -> Dictionary:
	var weapon: Dictionary = weapon_definitions.get(weapon_id, {}) if weapon_definitions.get(weapon_id, {}) is Dictionary else {}
	if weapon.is_empty():
		return {"ok": false, "reason": "unknown_weapon"}
	if equipment_state != null:
		var primary: String = str(equipment_state.get_equipped("primary_hand"))
		var secondary: String = str(equipment_state.get_equipped("secondary_hand"))
		if primary != weapon_id and secondary != weapon_id:
			return {"ok": false, "reason": "weapon_not_equipped"}
	var ammo_item_id: String = str(weapon.get("ammo_item_id", ""))
	if not ammo_item_id.is_empty():
		if inventory_state == null or int(inventory_state.get_quantity(ammo_item_id)) <= 0:
			return {"ok": false, "reason": "no_ammo", "ammo_item_id": ammo_item_id}
		inventory_state.remove_item(ammo_item_id, 1)
	var target = _pick_target(target_id)
	if target == null:
		return {"ok": false, "reason": "no_target"}
	var result: Dictionary = damage_pipeline.apply_to_threat(target, {
		"damage_type": str(weapon.get("damage_type", "physical")),
		"amount": float(weapon.get("damage", 0.0)),
		"noise": float(weapon.get("noise", 0.0)),
		"stun_seconds": float(weapon.get("stun_seconds", 0.0)),
		"status_effect_id": str(weapon.get("status_effect_id", "")),
		"source_id": weapon_id,
	})
	player_noise = maxf(player_noise, float(weapon.get("noise", 0.0)))
	awareness_indicator = maxf(awareness_indicator, player_noise)
	result["ok"] = true
	result["weapon_id"] = weapon_id
	result["target_id"] = target.instance_id
	result["ammo_item_id"] = ammo_item_id
	result["ammo_remaining"] = int(inventory_state.get_quantity(ammo_item_id)) if inventory_state != null and not ammo_item_id.is_empty() else -1
	last_attack_result = result.duplicate(true)
	return result

func get_summary() -> Dictionary:
	var threat_summaries: Array = []
	for threat in threats:
		threat_summaries.append(threat.get_summary())
	return {
		"encounter_markers": encounter_markers.duplicate(true),
		"threats": threat_summaries,
		"detection": detection_state.get_summary(),
		"awareness_indicator": awareness_indicator,
		"combat_engaged": combat_engaged,
		"last_attack_result": last_attack_result.duplicate(true),
		"damage_pipeline": damage_pipeline.get_summary(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	encounter_markers = (summary.get("encounter_markers", []) as Array).duplicate(true) if summary.get("encounter_markers", []) is Array else []
	if summary.get("detection", null) is Dictionary:
		detection_state.apply_summary(summary.get("detection", {}))
	if summary.get("damage_pipeline", null) is Dictionary:
		damage_pipeline.apply_summary(summary.get("damage_pipeline", {}))
	awareness_indicator = float(summary.get("awareness_indicator", 0.0))
	combat_engaged = bool(summary.get("combat_engaged", false))
	last_attack_result = summary.get("last_attack_result", {}) if summary.get("last_attack_result", {}) is Dictionary else {}
	_clear_runtime_nodes()
	var idx: int = 0
	var raw_threats: Variant = summary.get("threats", [])
	if raw_threats is Array:
		for entry in raw_threats:
			if not (entry is Dictionary):
				continue
			var threat = ThreatAIStateScript.new()
			threat.configure(entry)
			threats.append(threat)
			_spawn_placeholder(threat, idx, fallback_anchor)
			idx += 1
	return true

func get_status_lines() -> PackedStringArray:
	var alive: int = 0
	var attacking: int = 0
	for threat in threats:
		if threat.health > 0.0:
			alive += 1
		if threat.state == ThreatAIStateScript.STATE_ATTACK:
			attacking += 1
			combat_engaged = true
	return PackedStringArray([
		"Threats: alive=%d archetypes=%d attacking=%d" % [alive, _unique_archetype_count(), attacking],
		"Threat Indicator: %.2f detected=%s" % [awareness_indicator, str(detection_state.detected).to_lower()],
	])

func has_combat_engagement() -> bool:
	return combat_engaged

func get_active_threat_count() -> int:
	return threats.size()

func get_detected_threat_count() -> int:
	var count: int = 0
	for threat in threats:
		if threat.state in [ThreatAIStateScript.STATE_INVESTIGATE, ThreatAIStateScript.STATE_HUNT, ThreatAIStateScript.STATE_ATTACK]:
			count += 1
	return count

func _spawn_from_markers(markers: Array, anchor: Vector3) -> void:
	_clear_runtime_nodes()
	var idx: int = 0
	for marker in markers:
		if not (marker is Dictionary):
			continue
		var encounter_kind: String = _normalize_encounter_kind(str((marker as Dictionary).get("encounter_kind", "biomatter_swarm")))
		var count: int = max(1, int((marker as Dictionary).get("count", 1)))
		for i in range(count):
			var def: Dictionary = threat_archetypes.get(encounter_kind, {}) if threat_archetypes.get(encounter_kind, {}) is Dictionary else {}
			if def.is_empty():
				continue
			var threat = ThreatAIStateScript.new()
			var merged: Dictionary = def.duplicate(true)
			merged["instance_id"] = "%s_%d" % [str((marker as Dictionary).get("id", encounter_kind)), i]
			merged["archetype_id"] = encounter_kind
			merged["room_id"] = str((marker as Dictionary).get("room_id", ""))
			merged["cell"] = (marker as Dictionary).get("cell", [0, 0])
			merged["world_position"] = [anchor.x + cos(float(idx)) * 4.0, anchor.y, anchor.z + sin(float(idx)) * 4.0]
			threat.configure(merged)
			threats.append(threat)
			_spawn_placeholder(threat, idx, anchor)
			idx += 1

func _fallback_markers_from_layout(layout: Dictionary) -> Array:
	var markers: Array = []
	var room_ids: Array = []
	var rooms_variant: Variant = layout.get("rooms", [])
	if rooms_variant is Array:
		for room in rooms_variant:
			if room is Dictionary:
				var rid: String = str((room as Dictionary).get("id", ""))
				if not rid.is_empty():
					room_ids.append(rid)
	var fallback_archetypes: Array = ["biomatter_swarm", "puppet_corpse", "stalker", "mimic", "hull_tendril"]
	for i in range(fallback_archetypes.size()):
		markers.append({
			"id": "fallback_%d" % i,
			"room_id": room_ids[i % max(1, room_ids.size())] if not room_ids.is_empty() else "fallback_room_%d" % i,
			"cell": [i, 0],
			"encounter_kind": fallback_archetypes[i],
			"count": 1,
		})
	return markers

func _normalize_encounter_kind(kind: String) -> String:
	match kind:
		"biomatter_lurker":
			return "biomatter_swarm"
		"breach_lurker":
			return "mimic"
		"drone_scout":
			return "stalker"
		"derelict_pirate":
			return "puppet_corpse"
		_:
			return kind

func _pick_target(target_id: String = ""):
	for threat in threats:
		if threat.health <= 0.0:
			continue
		if target_id.is_empty() or threat.instance_id == target_id:
			return threat
	return null

func _spawn_placeholder(threat, index: int, anchor: Vector3) -> void:
	var ThreatPlaceholderRendererScript := preload("res://scripts/tools/threat_placeholder_renderer.gd")
	var pos := Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
	var node := ThreatPlaceholderRendererScript.build_placeholder(threat.archetype_id, threat.tags, pos)
	node.name = "Threat_%s" % threat.instance_id
	add_child(node)
	placeholder_nodes[threat.instance_id] = node

## Domain 2 (BP1): visibility falls off with world distance, so a closer threat
## perceives more of the player's emitted visibility than a far one.
func _proximity_factor(threat, player_position: Vector3) -> float:
	var tp: Vector3 = Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
	return clampf(1.0 - tp.distance_to(player_position) / SIGHT_RANGE, 0.0, 1.0)

func _update_placeholder(threat, player_position: Vector3) -> void:
	var node = placeholder_nodes.get(threat.instance_id, null)
	if node == null or not is_instance_valid(node):
		return
	var y_bob: float = 0.2 if threat.state == ThreatAIStateScript.STATE_ATTACK else 0.0
	node.position = Vector3(float(threat.world_position[0]), float(threat.world_position[1]) + y_bob, float(threat.world_position[2]))
	if threat.state == ThreatAIStateScript.STATE_HUNT or threat.state == ThreatAIStateScript.STATE_ATTACK:
		threat.world_position = [
			lerpf(float(threat.world_position[0]), player_position.x, 0.02),
			float(threat.world_position[1]),
			lerpf(float(threat.world_position[2]), player_position.z, 0.02),
		]

func _clear_runtime_nodes() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	placeholder_nodes.clear()
	threats.clear()
	combat_engaged = false
	awareness_indicator = 0.0

func _unique_archetype_count() -> int:
	var seen: Dictionary = {}
	for threat in threats:
		seen[threat.archetype_id] = true
	return seen.size()

func _color_for_archetype(archetype_id: String) -> Color:
	var ThreatPlaceholderRendererScript := preload("res://scripts/tools/threat_placeholder_renderer.gd")
	return ThreatPlaceholderRendererScript.color_for_archetype(archetype_id)

func _load_json_dict(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
