extends Node3D
class_name ThreatManager

const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const DetectionStateScript := preload("res://scripts/systems/detection_state.gd")
const DamagePipelineScript := preload("res://scripts/systems/damage_pipeline.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
const ThreatPathfinderScript := preload("res://scripts/systems/threat_pathfinder.gd")
const THREAT_ARCHETYPE_PATH: String = "res://data/combat/threat_archetypes.json"
const WEAPON_DEFINITIONS_PATH: String = "res://data/combat/weapon_definitions.json"
const AMMO_DEFINITIONS_PATH: String = "res://data/combat/ammo_definitions.json"
const SIGHT_RANGE: float = 12.0
const REPATH_INTERVAL: float = 0.35
const REPATH_TARGET_MOVE: float = 1.25

signal threat_killed(record: Dictionary)

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
var _rewarded_kills: Dictionary = {}  # instance_id -> true (reward/remove once)
var _last_attack_weapon_id: String = ""  # Stream F: melee intimidate on kill
## ADR-0049: pure nav graph for pathfollowing (null = legacy hold still).
var nav_graph = null
## instance_id -> {waypoints, index, target, repath_cooldown}
var _path_runtime: Dictionary = {}

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
	configure_nav_graph(layout)
	_spawn_from_markers(encounter_markers, fallback_anchor)

## ADR-0049: (re)build the pure nav graph for the active ship layout.
func configure_nav_graph(layout: Dictionary) -> int:
	nav_graph = ShipNavGraphScript.new()
	var n: int = nav_graph.build_from_layout(layout if layout is Dictionary else {})
	_path_runtime.clear()
	return n

## Optional dynamic costs each frame / on dirty events.
## fire_rooms: room_id -> intensity; blocked_bulkheads: Array of [a,b] pairs.
func update_nav_dynamic_costs(fire_rooms: Dictionary = {}, blocked_bulkheads: Array = []) -> void:
	if nav_graph == null:
		return
	nav_graph.reset_dynamic_costs()
	if not fire_rooms.is_empty():
		nav_graph.apply_fire_costs(fire_rooms)
	for pair in blocked_bulkheads:
		if pair is Array and (pair as Array).size() >= 2:
			nav_graph.block_bulkhead(str(pair[0]), str(pair[1]))
		elif pair is Dictionary:
			nav_graph.block_bulkhead(str(pair.get("a", "")), str(pair.get("b", "")))

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
			"player_position": player_position,
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
		_advance_threat_motion(threat, delta, player_position)
		_update_placeholder(threat, player_position)
	_sweep_dead_threats()

func attack_with_weapon(weapon_id: String, inventory_state, equipment_state, ammo_state = null, target_id: String = "") -> Dictionary:
	assert(inventory_state != null, "inventory_state dependency cannot be null")
	assert(equipment_state != null, "equipment_state dependency cannot be null")
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
		# Domain 5: fire from the per-weapon magazine, not raw inventory.
		if ammo_state == null:
			return {"ok": false, "reason": "no_ammo", "ammo_item_id": ammo_item_id}
		if ammo_state.is_reloading():
			return {"ok": false, "reason": "reloading", "ammo_item_id": ammo_item_id}
		if not ammo_state.spend(weapon_id):
			return {"ok": false, "reason": "empty_magazine", "ammo_item_id": ammo_item_id}
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
	result["ammo_remaining"] = ammo_state.loaded(weapon_id) if ammo_state != null and not ammo_item_id.is_empty() else -1
	last_attack_result = result.duplicate(true)
	# Stream F: stamp last weapon so threat_killed can train intimidate on melee.
	_last_attack_weapon_id = weapon_id
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
		var local_pos: Variant = (marker as Dictionary).get("local_position", null)
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
			if local_pos is Array and (local_pos as Array).size() >= 3:
				# EncounterInjector markers carry the rolled room's floor-cell
				# offset — spawn the threat IN its room. Multiple threats on
				# one marker fan out by half a cell so they don't stack.
				merged["world_position"] = [
					anchor.x + float((local_pos as Array)[0]) + float(i) * 0.5,
					anchor.y + float((local_pos as Array)[1]),
					anchor.z + float((local_pos as Array)[2]),
				]
			else:
				# Legacy markers (hand-authored gameplay slices, older saves)
				# have no local_position: keep the anchor-circle fallback.
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

## Domain 2 (BP3): reward + remove threats that died this frame, exactly once.
func _sweep_dead_threats() -> void:
	var dead: Array = []
	for threat in threats:
		if is_instance_valid(threat) and threat.health <= 0.0 and not _rewarded_kills.has(threat.instance_id):
			_rewarded_kills[threat.instance_id] = true
			dead.append(threat)
	for threat in dead:
		emit_signal("threat_killed", {
			"instance_id": threat.instance_id,
			"archetype_id": threat.archetype_id,
			"position": Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2])),
			"loot_table": str((threat_archetypes.get(threat.archetype_id, {}) as Dictionary).get("loot_table", "combat_drop_common")),
			"weapon_id": _last_attack_weapon_id,
		})
		_remove_threat(threat)

func _remove_threat(threat) -> void:
	var node = placeholder_nodes.get(threat.instance_id, null)
	if node != null and is_instance_valid(node):
		if node.get_parent() == self:
			remove_child(node)
		node.queue_free()
	placeholder_nodes.erase(threat.instance_id)
	threats.erase(threat)

## Domain 2 (BP1): visibility falls off with world distance, so a closer threat
## perceives more of the player's emitted visibility than a far one.
func _proximity_factor(threat, player_position: Vector3) -> float:
	var tp: Vector3 = Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
	return clampf(1.0 - tp.distance_to(player_position) / SIGHT_RANGE, 0.0, 1.0)

## ADR-0049: pathfollow toward a state-specific target (no wall-tunneling lerp).
func _advance_threat_motion(threat, delta: float, player_position: Vector3) -> void:
	if threat == null or delta <= 0.0:
		return
	if threat.state in [ThreatAIStateScript.STATE_IDLE, ThreatAIStateScript.STATE_STUN, ThreatAIStateScript.STATE_DEAD]:
		_path_runtime.erase(threat.instance_id)
		return
	var speed: float = threat.effective_move_speed() if threat.has_method("effective_move_speed") else 2.5
	if speed <= 0.0:
		return
	var current := Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
	var target: Vector3 = _motion_target_for(threat, player_position)
	if target == Vector3.INF:
		return
	# Attack range: stop advancing once close enough to strike.
	if threat.state == ThreatAIStateScript.STATE_ATTACK:
		var ar: float = float(threat.attack_range) if "attack_range" in threat else 1.4
		if current.distance_to(player_position) <= ar:
			return
	if nav_graph == null or nav_graph.node_count() == 0:
		# Fallback: slow direct step (still no lerp-through-fraction) — only when
		# no graph (e.g. empty layout). Prefer staying put over tunneling far.
		var step: Vector3 = current.move_toward(target, speed * delta)
		threat.world_position = [step.x, step.y, step.z]
		return
	var rt: Dictionary = _path_runtime.get(threat.instance_id, {}) as Dictionary
	if rt.is_empty():
		rt = {"waypoints": [], "index": 0, "target": Vector3.INF, "repath_cooldown": 0.0}
	rt["repath_cooldown"] = maxf(0.0, float(rt.get("repath_cooldown", 0.0)) - delta)
	var need_repath: bool = false
	var waypoints: Array = rt.get("waypoints", []) as Array
	var prev_target: Vector3 = rt.get("target", Vector3.INF) as Vector3
	if waypoints.is_empty() or int(rt.get("index", 0)) >= waypoints.size():
		need_repath = true
	elif prev_target != Vector3.INF and prev_target.distance_to(target) > REPATH_TARGET_MOVE:
		need_repath = true
	elif float(rt.get("repath_cooldown", 0.0)) <= 0.0:
		need_repath = true
	if need_repath:
		var path: Array = []
		if threat.state == ThreatAIStateScript.STATE_FLEE:
			var flee_goal: Vector3 = ThreatPathfinderScript.farthest_point(nav_graph, current, player_position)
			path = ThreatPathfinderScript.find_path(nav_graph, current, flee_goal)
		else:
			path = ThreatPathfinderScript.find_path(nav_graph, current, target)
		rt["waypoints"] = path
		rt["index"] = 0
		rt["target"] = target
		rt["repath_cooldown"] = REPATH_INTERVAL
		waypoints = path
	var step_result: Dictionary = ThreatPathfinderScript.step_along_path(
		waypoints, int(rt.get("index", 0)), current, speed, delta
	)
	var new_pos: Vector3 = step_result.get("position", current) as Vector3
	rt["index"] = int(step_result.get("path_index", 0))
	_path_runtime[threat.instance_id] = rt
	threat.world_position = [new_pos.x, new_pos.y, new_pos.z]
	# Best-effort room_id from nearest graph node.
	var nid: String = nav_graph.nearest_node(new_pos)
	if not nid.is_empty():
		var rid: String = nav_graph.get_node_room(nid)
		if not rid.is_empty():
			threat.room_id = rid

func _motion_target_for(threat, player_position: Vector3) -> Vector3:
	match threat.state:
		ThreatAIStateScript.STATE_HUNT, ThreatAIStateScript.STATE_ATTACK:
			return player_position
		ThreatAIStateScript.STATE_INVESTIGATE:
			if threat.has_method("last_known_world_position"):
				var lkp: Vector3 = threat.last_known_world_position()
				if lkp != Vector3.INF:
					return lkp
			return player_position
		ThreatAIStateScript.STATE_FLEE:
			return player_position  # used as avoid point; pathfinder picks farthest
		_:
			return Vector3.INF

func _update_placeholder(threat, _player_position: Vector3) -> void:
	var node = placeholder_nodes.get(threat.instance_id, null)
	if node == null or not is_instance_valid(node):
		return
	var y_bob: float = 0.2 if threat.state == ThreatAIStateScript.STATE_ATTACK else 0.0
	node.position = Vector3(float(threat.world_position[0]), float(threat.world_position[1]) + y_bob, float(threat.world_position[2]))

func _clear_runtime_nodes() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	placeholder_nodes.clear()
	_rewarded_kills.clear()
	threats.clear()
	_path_runtime.clear()
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
