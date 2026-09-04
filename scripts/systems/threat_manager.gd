extends Node3D
class_name ThreatManager

const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")
const DetectionStateScript := preload("res://scripts/systems/detection_state.gd")
const DamagePipelineScript := preload("res://scripts/systems/damage_pipeline.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
const ThreatPathfinderScript := preload("res://scripts/systems/threat_pathfinder.gd")
const SpatialPerceptionStateScript := preload("res://scripts/systems/spatial_perception_state.gd")
const BiomassPartCatalogScript := preload("res://scripts/systems/biomass_part_catalog.gd")
const BiomassRecipeLibraryScript := preload("res://scripts/systems/biomass_recipe_library.gd")
const BiomassRecipeGeneratorScript := preload("res://scripts/systems/biomass_recipe_generator.gd")
const BiomassRecipeScript := preload("res://scripts/systems/biomass_recipe.gd")
const BiomassAssemblerScript := preload("res://scripts/threats/biomass_assembler.gd")
const BiomassThreatVisualScript := preload("res://scripts/threats/biomass_threat_visual.gd")
const BiomassGaitControllerScript := preload("res://scripts/threats/biomass_gait_controller.gd")
const THREAT_ARCHETYPE_PATH: String = "res://data/combat/threat_archetypes.json"
const WEAPON_DEFINITIONS_PATH: String = "res://data/combat/weapon_definitions.json"
const AMMO_DEFINITIONS_PATH: String = "res://data/combat/ammo_definitions.json"
const BIOMASS_PART_CATALOG_PATH: String = "res://data/combat/biomass_part_catalog.json"
const BIOMASS_RECIPE_CATALOG_PATH: String = "res://data/combat/biomass_recipe_catalog.json"
const BIOMASS_VISUAL_CATALOG_PATH: String = "res://data/combat/threat_visual_catalog.json"
const BIOMASS_ARCHETYPES: Array[String] = [
	"biomatter_swarm",
	"drone_swarm",
	"hull_tendril",
	"mimic",
	"puppet_corpse",
	"stalker",
]
const BIOMASS_WEIGHT: float = 0.35
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
## PKG-C4.1b: room-graph perception (LOS + noise muffling). Null = legacy same-room only.
var spatial_perception = null
## Optional engaged LOS flags: threat.instance_id -> bool (physics raycast result from scene).
var engaged_los: Dictionary = {}
## REQ-MI-004: Callable(threat, amount) when threat applies structure_damage (hull tendril).
var on_structure_attack: Callable = Callable()
## Task 7: biomass sources (PartCatalog / RecipeLibrary / visual catalog) and the
## single RefCounted assembler.  configure_biomass_sources() must be called
## PRE-tree and at most once.  After _ready(), any subsequent call is refused.
var _biomass_parts: Variant = null
var _biomass_library: Variant = null
var _biomass_visual_catalog: Dictionary = {}
var _biomass_assembler: Variant = null
var _biomass_source_configured: bool = false
var _biomass_source_locked: bool = false
## Task 7: per-threat biomass visual lookup (instance_id -> BiomassThreatVisual)
## so the manager can call step_gait() each tick and forward velocity.  The
## visual is parented under the placeholder root (same lifecycle).
var _biomass_visuals: Dictionary = {}
## Task 7: per-threat prior world position so _update_placeholder derives the
## horizontal velocity from world-space diff (NOT from authoritative state).
var _biomass_prior_world_position: Dictionary = {}
## Task 7: defensive sorted/dedup restore diagnostics.
var _biomass_restore_diagnostics: Array[String] = []
var _biomass_fallback_used_valid: int = 0

func _ready() -> void:
	threat_archetypes = _load_json_dict(THREAT_ARCHETYPE_PATH)
	weapon_definitions = _load_json_dict(WEAPON_DEFINITIONS_PATH)
	ammo_definitions = _load_json_dict(AMMO_DEFINITIONS_PATH)
	damage_pipeline.configure({})
	detection_state.configure({})
	# Task 7: if pre-tree source configuration was missed, fall back to a
	# single lazy load so the playable coordinator can construct the manager
	# without explicit configure_biomass_sources().  Both paths land at the
	# same _biomass_assembler / _biomass_visual_catalog state.
	if not _biomass_source_configured:
		var parts: Variant = BiomassPartCatalogScript.new()
		var parts_loaded: bool = false
		if parts is Object and parts != null and parts.has_method("load_path"):
			parts_loaded = parts.load_path(BIOMASS_PART_CATALOG_PATH)
		var library: Variant = BiomassRecipeLibraryScript.new()
		var library_loaded: bool = false
		if library is Object and library != null and parts_loaded and parts != null:
			library_loaded = library.load_path(BIOMASS_RECIPE_CATALOG_PATH, parts)
		var catalog: Dictionary = _load_biomass_visual_catalog()
		_apply_biomass_sources(parts if parts_loaded else null, library if library_loaded else null, catalog)
	_biomass_source_locked = true

func configure_for_layout(layout: Dictionary, markers: Array = [], anchor: Vector3 = Vector3.ZERO) -> void:
	fallback_anchor = anchor
	encounter_markers = markers.duplicate(true)
	if encounter_markers.is_empty():
		encounter_markers = _fallback_markers_from_layout(layout)
	configure_nav_graph(layout)
	configure_spatial_perception(layout)
	_spawn_from_markers(encounter_markers, fallback_anchor)


## PKG-C4.1b: build SpatialPerceptionState from layout room_links / blocked_links.
func configure_spatial_perception(layout: Dictionary) -> int:
	spatial_perception = SpatialPerceptionStateScript.new()
	var n: int = spatial_perception.configure_from_layout(layout if layout is Dictionary else {})
	engaged_los.clear()
	return n


## Scene injects one raycast result per engaged threat (FRAME). Missing keys mean "unknown".
func set_engaged_los(instance_id: String, has_los: bool) -> void:
	if instance_id.is_empty():
		return
	engaged_los[instance_id] = has_los


func clear_engaged_los() -> void:
	engaged_los.clear()

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
		var player_distance: float = 0.0
		if threat.world_position.size() >= 3:
			var tp: Vector3 = Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
			player_distance = player_position.distance_to(tp)
		# PKG-C4.1b: room-graph LOS + optional physics raycast for engaged set.
		var sight_mult: float = prox
		var noise_at: float = float(profile["noise"])
		var can_see: bool = same_room
		if spatial_perception != null and not player_room_id.is_empty() and not str(threat.room_id).is_empty():
			can_see = bool(spatial_perception.can_see(player_room_id, str(threat.room_id)))
			noise_at = float(spatial_perception.attenuate_noise(player_room_id, str(threat.room_id), float(profile["noise"])))
			if not can_see:
				sight_mult = 0.0
		# Engaged raycast overrides room LOS when provided (breaking LOS mid-room).
		if engaged_los.has(threat.instance_id):
			if not bool(engaged_los[threat.instance_id]):
				can_see = false
				sight_mult = 0.0
			else:
				can_see = true
		var engage_same: bool = same_room and can_see
		threat.tick(delta, {
			"noise_level": noise_at,
			"light_level": float(profile["light"]) * (1.0 if can_see else 0.35),
			"sight_level": float(profile["visibility"]) * sight_mult,
			"crouching": false,  # crouch already applied in the emitted profile (no double-count)
			"room_id": player_room_id,
			"same_room": engage_same,
			"detect_threshold": detection_state.detect_threshold,
			"player_position": player_position,
			"player_distance": player_distance,
		})
		awareness_indicator = maxf(awareness_indicator, float(threat.awareness_score))
		if engage_same and threat.can_attack() and vitals_state != null:
			last_attack_result = damage_pipeline.apply_to_vitals(vitals_state, status_effects_state, player_armor_profile, {
				"damage_type": threat.attack_type,
				"amount": threat.attack_damage,
				"noise": threat.attack_noise,
				"status_effect_id": threat.status_on_hit,
				"source_id": threat.instance_id,
			})
			# Hull tendril / structure-breaker archetypes also damage modules.
			var struct_amt: float = 0.0
			if "structure_damage" in threat:
				struct_amt = float(threat.structure_damage)
			if struct_amt > 0.0 and on_structure_attack.is_valid():
				on_structure_attack.call(threat, struct_amt)
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
			# Task 7: deterministically OMIT biomass records whose stored
			# recipe is missing/invalid BEFORE we register the threat — the
			# contract is "malformed restored records deterministically
			# omitted", so the threat must never appear in the live set.
			if is_biomass_archetype(String(entry.get("archetype_id", ""))) and not _stored_biomass_recipe_is_admissible(entry):
				_record_restore_diagnostic("malformed_recipe_omitted:%s" % String(entry.get("instance_id", "")))
				continue
			var threat = ThreatAIStateScript.new()
			threat.configure(entry)
			threats.append(threat)
			_spawn_placeholder(threat, idx, fallback_anchor)
			# Task 7: after the threat is registered + placeholder spawned,
			# rebuild its biomass visual from the stored recipe/seed.  The
			# _restore_biomass_threat helper handles dead-no-visual and
			# fallback-flag cases (omitted threats never reach here).
			if is_biomass_archetype(String(threat.archetype_id)):
				_restore_biomass_threat(entry)
			idx += 1
	return true

## Task 7: True iff the entry's stored biomass recipe would survive
## Recipe.from_dict against the loaded parts catalog.  Used by apply_summary
## to deterministically omit malformed records.
func _stored_biomass_recipe_is_admissible(entry: Dictionary) -> bool:
	var stored_recipe_value: Variant = entry.get("biomass_recipe", null)
	if not (stored_recipe_value is Dictionary) or (stored_recipe_value as Dictionary).is_empty():
		return false
	var stored_recipe: Dictionary = stored_recipe_value
	var validated_recipe: Variant = BiomassRecipeScript.from_dict(stored_recipe, _biomass_parts)
	if validated_recipe == null:
		return false
	return bool(validated_recipe.is_valid())

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
		# Task 7: biomass markers route through the dedicated biomass pipeline
		# so they get a built visual + gait + restore metadata.  All other
		# markers keep the legacy primitive-placeholder path.
		if is_biomass_archetype(encounter_kind):
			var count: int = max(1, int((marker as Dictionary).get("count", 1)))
			var local_pos: Variant = (marker as Dictionary).get("local_position", null)
			for i in range(count):
				var world_pos: Vector3 = anchor
				if local_pos is Array and (local_pos as Array).size() >= 3:
					world_pos = Vector3(
						anchor.x + float((local_pos as Array)[0]) + float(i) * 0.5,
						anchor.y + float((local_pos as Array)[1]),
						anchor.z + float((local_pos as Array)[2]),
					)
				else:
					world_pos = Vector3(anchor.x + cos(float(idx)) * 4.0, anchor.y, anchor.z + sin(float(idx)) * 4.0)
				var marker_id: String = str((marker as Dictionary).get("id", encounter_kind))
				var spawn_seed: int = hash(String(marker_id) + ":" + str(i))
				_spawn_biomass_threat(encounter_kind, world_pos, spawn_seed)
				idx += 1
			continue
		var count_legacy: int = max(1, int((marker as Dictionary).get("count", 1)))
		var local_pos_legacy: Variant = (marker as Dictionary).get("local_position", null)
		for i in range(count_legacy):
			var def: Dictionary = threat_archetypes.get(encounter_kind, {}) if threat_archetypes.get(encounter_kind, {}) is Dictionary else {}
			if def.is_empty():
				continue
			var threat = ThreatAIStateScript.new()
			var merged: Dictionary = def.duplicate(true)
			merged["instance_id"] = "%s_%d" % [str((marker as Dictionary).get("id", encounter_kind)), i]
			merged["archetype_id"] = encounter_kind
			merged["room_id"] = str((marker as Dictionary).get("room_id", ""))
			merged["cell"] = (marker as Dictionary).get("cell", [0, 0])
			if local_pos_legacy is Array and (local_pos_legacy as Array).size() >= 3:
				# EncounterInjector markers carry the rolled room's floor-cell
				# offset — spawn the threat IN its room. Multiple threats on
				# one marker fan out by half a cell so they don't stack.
				merged["world_position"] = [
					anchor.x + float((local_pos_legacy as Array)[0]) + float(i) * 0.5,
					anchor.y + float((local_pos_legacy as Array)[1]),
					anchor.z + float((local_pos_legacy as Array)[2]),
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
	# Task 7: forward biomass gait step.  Derive horizontal velocity from the
	# diff between the threat's prior world position and the current one
	# (NOT from authoritative state — the AI state never owns velocity).
	var visual = _biomass_visuals.get(threat.instance_id, null)
	if visual != null and is_instance_valid(visual) and visual.has_method("step_gait"):
		var current_pos: Vector3 = Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
		var prior_pos: Vector3 = _biomass_prior_world_position.get(threat.instance_id, current_pos) as Vector3
		var velocity: Vector3 = (current_pos - prior_pos) / maxf(get_process_delta_time(), 0.0001)
		visual.call("step_gait", get_process_delta_time(), velocity, String(threat.state))
		_biomass_prior_world_position[threat.instance_id] = current_pos

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
	# Task 7: free biomass visuals (these may live as children of placeholders
	# that are about to be freed, but the manager-owned reference must also
	# clear so a fresh apply_summary doesn't double-free).
	for instance_id in _biomass_visuals.keys():
		var visual: Variant = _biomass_visuals[instance_id]
		if visual is Object and is_instance_valid(visual):
			visual.queue_free()
	_biomass_visuals.clear()
	_biomass_prior_world_position.clear()

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

# ---------------------------------------------------------------------------
# Task 7: biomass integration
# ---------------------------------------------------------------------------

## Pre-tree source configuration: own one RefCounted assembler + the loaded
## PartCatalog / RecipeLibrary / visual catalog.  Idempotent after _ready()
## so a second call is a hard no-op (the dispatcher only ever configures
## once before add_child).
func configure_biomass_sources(parts: Variant, library: Variant, visual_catalog: Dictionary = {}) -> void:
	if _biomass_source_locked:
		_record_restore_diagnostic("configure_biomass_sources refused after _ready")
		return
	if _biomass_source_configured:
		_record_restore_diagnostic("configure_biomass_sources called twice")
		return
	_apply_biomass_sources(parts, library, visual_catalog)

func _apply_biomass_sources(parts: Variant, library: Variant, visual_catalog: Dictionary) -> void:
	_biomass_parts = parts if parts is Object else null
	_biomass_library = library if library is Object else null
	_biomass_visual_catalog = _filter_biomass_visual_catalog(visual_catalog if visual_catalog is Dictionary else _load_biomass_visual_catalog())
	if _biomass_parts != null and _biomass_library != null:
		_biomass_assembler = BiomassAssemblerScript.new()
	else:
		_biomass_assembler = null
	_biomass_source_configured = true

func _load_biomass_visual_catalog() -> Dictionary:
	if not FileAccess.file_exists(BIOMASS_VISUAL_CATALOG_PATH):
		return {}
	var text: String = FileAccess.get_file_as_string(BIOMASS_VISUAL_CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var doc: Dictionary = parsed
	var archetypes_value: Variant = doc.get("archetypes", {})
	return archetypes_value if archetypes_value is Dictionary else {}

func _filter_biomass_visual_catalog(catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for archetype_id in BIOMASS_ARCHETYPES:
		if catalog.has(archetype_id):
			result[archetype_id] = catalog[archetype_id]
		else:
			result[archetype_id] = {
				"primitive": "sphere",
				"y_offset": 0.0,
				"scale": 1.0,
				"albedo": "#ffffff",
				"visual_mode": "biomass",
				"generated_recipe_weight": BIOMASS_WEIGHT,
				"allowed_locomotion_hints": [],
			}
	return result

## Validation / public seam: spawn a biomass threat using the exact signature
## the contract demands. Returns the assembled visual, the existing primitive
## fallback visual, or null when the threat could not be admitted.
func inject_biomass_validation_encounter(archetype_id: String, recipe_id: String = "", seed: int = 0, world_position: Vector3 = Vector3.ZERO) -> Variant:
	var threat: Variant = _spawn_biomass_threat(archetype_id, world_position, seed, recipe_id)
	if threat == null:
		return null
	return _biomass_visuals.get(threat.instance_id, placeholder_nodes.get(threat.instance_id, null))

## Compatibility seam for validation callers that only specify an archetype
## and position. The curated library pool remains the sole recipe authority.
func spawn_biomass_validation_encounter(archetype_id: String, world_position: Vector3 = Vector3.ZERO) -> Variant:
	return inject_biomass_validation_encounter(archetype_id, "", 0, world_position)

## Validation / public seam: stable, sorted, deduplicated restore diagnostics.
## Returns PackedStringArray so callers iterating get a defensive read.
func get_restore_diagnostics() -> PackedStringArray:
	var sorted: Array = _biomass_restore_diagnostics.duplicate()
	sorted.sort()
	var seen: Dictionary = {}
	var result: PackedStringArray = PackedStringArray()
	for entry in sorted:
		var key: String = String(entry)
		if seen.has(key):
			continue
		seen[key] = true
		result.append(key)
	return result

func _record_restore_diagnostic(message: String) -> void:
	if message.is_empty():
		return
	_biomass_restore_diagnostics.append(message)

func is_biomass_archetype(archetype_id: String) -> bool:
	return BIOMASS_ARCHETYPES.has(archetype_id)

## Deterministic, nonzero seed for a new biomass threat.  The manager owns
## normalization so a smoke can call with seed=0 and still observe nonzero.
func _derive_biomass_seed(instance_id: String, archetype_id: String, requested_seed: int) -> int:
	if requested_seed != 0:
		return requested_seed
	var combined: int = hash(String(instance_id) + ":" + String(archetype_id))
	if combined == 0:
		combined = 1
	# Fold to int32 range so downstream code never sees a value > 2^31-1.
	return combined & 0x7fffffff

## Spawn a biomass threat end-to-end:
##   1. Pick curated recipe from library pool_for (sole authority).
##   2. Compute deterministic nonzero seed.
##   3. Store biomass_recipe + biomass_seed on the threat.
##   4. assembler.build(recipe, parts) -> visual.
##   5. configure_gait BEFORE scene registration; failure → free + fallback.
##   6. Register visual under the threat's placeholder parent.
##   7. If anything fails, stamp biomass_whole_threat_fallback=true + stable
##      biomass_fallback_reason and skip the visual.
func _spawn_biomass_threat(archetype_id: String, world_position: Vector3, requested_seed: int = 0, recipe_id_override: String = "") -> Variant:
	if not is_biomass_archetype(archetype_id):
		return null
	if _biomass_library == null or _biomass_parts == null:
		return null
	var pool: PackedStringArray = _biomass_library.pool_for(archetype_id)
	if pool.is_empty():
		_record_restore_diagnostic("pool_empty:%s" % archetype_id)
		return null
	var pool_index: int = absi(hash(String(archetype_id) + ":" + str(requested_seed))) % pool.size()
	var recipe_id: String = recipe_id_override if not recipe_id_override.is_empty() else String(pool[pool_index])
	var recipe_obj: Variant = _biomass_library.get_recipe(recipe_id)
	if recipe_obj == null or not recipe_obj.is_valid():
		_record_restore_diagnostic("invalid_recipe:%s" % recipe_id)
		return null
	var threat: Variant = ThreatAIStateScript.new()
	var instance_id: String = "%s_bio_%d" % [archetype_id, _biomass_threat_id_counter]
	_biomass_threat_id_counter += 1
	var archetype_def: Variant = threat_archetypes.get(archetype_id, {})
	var threat_config: Dictionary = archetype_def.duplicate(true) if archetype_def is Dictionary else {}
	var seed_value: int = _derive_biomass_seed(instance_id, archetype_id, requested_seed)
	threat_config.merge({
		"instance_id": instance_id,
		"archetype_id": archetype_id,
		"display_name": str(threat_archetypes.get(archetype_id, {}).get("display_name", archetype_id)) if threat_archetypes.get(archetype_id, {}) is Dictionary else archetype_id,
		"world_position": [world_position.x, world_position.y, world_position.z],
		"cell": [0, 0],
		"state": ThreatAIStateScript.STATE_IDLE,
		"biomass_recipe": recipe_obj.to_dict(),
		"biomass_seed": seed_value,
	}, true)
	threat.configure(threat_config)
	# Build → configure_gait BEFORE scene registration.  Failure synchronously
	# frees the visual and applies the whole-threat primitive fallback
	# metadata so the placeholder remains in use.
	var visual: Variant = _biomass_assembler.build(recipe_obj, _biomass_parts)
	var fallback_reason: String = ""
	if visual == null:
		var diags: PackedStringArray = _biomass_assembler.last_diagnostics()
		fallback_reason = "assembler_failed:%s" % String(diags[0]) if diags.size() >= 1 else "assembler_failed"
		threat.biomass_whole_threat_fallback = true
		threat.biomass_fallback_reason = fallback_reason
		_biomass_fallback_used_valid += 1
		_record_restore_diagnostic(fallback_reason)
		# Still register the threat as a normal placeholder (no visual).
	else:
		if not (visual is Object) or visual == null or not visual.has_method("configure_gait"):
			threat.biomass_whole_threat_fallback = true
			threat.biomass_fallback_reason = "visual_wrong_script"
			if visual is Object:
				visual.free()
			visual = null
			_record_restore_diagnostic("visual_wrong_script")
		else:
			var gait_ok: bool = bool(visual.call("configure_gait", _biomass_parts, recipe_obj, seed_value))
			if not gait_ok:
				visual.free()
				visual = null
				threat.biomass_whole_threat_fallback = true
				threat.biomass_fallback_reason = "gait_configure_failed"
				_biomass_fallback_used_valid += 1
				_record_restore_diagnostic("gait_configure_failed:%s" % recipe_id)
	threats.append(threat)
	_spawn_placeholder(threat, threats.size() - 1, world_position)
	if visual != null and visual is Object:
		_biomass_visuals[instance_id] = visual
		_attach_biomass_visual(instance_id, visual)
		_biomass_prior_world_position[instance_id] = Vector3(world_position.x, world_position.y, world_position.z)
	return threat

## Testable whole-threat fallback seam. It preserves a valid curated recipe and
## threat state, but deliberately skips the assembled visual so the existing
## primitive placeholder remains the only renderable representation.
func _spawn_biomass_fallback_threat(archetype_id: String, reason: String, world_position: Vector3 = Vector3.ZERO, requested_seed: int = 0) -> Variant:
	if not is_biomass_archetype(archetype_id) or _biomass_library == null:
		return null
	var pool: PackedStringArray = _biomass_library.pool_for(archetype_id)
	if pool.is_empty():
		return null
	var recipe: Variant = _biomass_library.get_recipe(String(pool[0]))
	if recipe == null or not recipe.is_valid():
		return null
	var threat: Variant = ThreatAIStateScript.new()
	var instance_id: String = "%s_bio_%d" % [archetype_id, _biomass_threat_id_counter]
	_biomass_threat_id_counter += 1
	var archetype_def: Variant = threat_archetypes.get(archetype_id, {})
	var threat_config: Dictionary = archetype_def.duplicate(true) if archetype_def is Dictionary else {}
	threat_config.merge({
		"instance_id": instance_id,
		"archetype_id": archetype_id,
		"display_name": str(threat_archetypes.get(archetype_id, {}).get("display_name", archetype_id)) if threat_archetypes.get(archetype_id, {}) is Dictionary else archetype_id,
		"world_position": [world_position.x, world_position.y, world_position.z],
		"cell": [0, 0],
		"state": ThreatAIStateScript.STATE_IDLE,
		"biomass_recipe": recipe.to_dict(),
		"biomass_seed": _derive_biomass_seed(instance_id, archetype_id, requested_seed),
	}, true)
	threat.configure(threat_config)
	threat.biomass_whole_threat_fallback = true
	threat.biomass_fallback_reason = reason if not reason.is_empty() else "forced_fallback"
	threats.append(threat)
	_spawn_placeholder(threat, threats.size() - 1, world_position)
	_record_restore_diagnostic("fallback:%s" % threat.biomass_fallback_reason)
	return threat

var _biomass_threat_id_counter: int = 1

## Restored threat (came in via apply_summary / save-load round-trip):
## use stored recipe/seed unchanged.  Malformed → omit.  Dead → keep dead,
## no visual/fallback.  Failed build → fallback.
func _restore_biomass_threat(entry: Dictionary) -> void:
	var instance_id: String = String(entry.get("instance_id", ""))
	var archetype_id: String = String(entry.get("archetype_id", ""))
	if instance_id.is_empty() or not is_biomass_archetype(archetype_id):
		return
	var stored_recipe_value: Variant = entry.get("biomass_recipe", null)
	var stored_seed: int = int(entry.get("biomass_seed", 0))
	# Malformed: no recipe at all OR a non-dict recipe → omit.
	if not (stored_recipe_value is Dictionary) or (stored_recipe_value as Dictionary).is_empty():
		_record_restore_diagnostic("malformed_recipe:%s" % instance_id)
		return
	var stored_recipe: Dictionary = stored_recipe_value
	# Validate the stored recipe survives Recipe.from_dict against the loaded
	# parts catalog.  An invalid recipe is a malformed record.
	var validated_recipe: Variant = BiomassRecipeScript.from_dict(stored_recipe, _biomass_parts)
	if validated_recipe == null or not validated_recipe.is_valid():
		_record_restore_diagnostic("invalid_recipe_after_round_trip:%s" % instance_id)
		return
	# Dead records stay dead, no visual, no fallback metadata.
	if String(entry.get("state", "")) == ThreatAIStateScript.STATE_DEAD or float(entry.get("health", 1.0)) <= 0.0:
		# The state is registered via apply_summary's normal path with no
		# biomass visual + no fallback metadata.  Nothing more to do here.
		return
	# Build the visual from the validated recipe + the stored seed.
	var visual: Variant = _biomass_assembler.build(validated_recipe, _biomass_parts)
	var threat_index: int = threats.size() - 1
	var threat = null
	for candidate in threats:
		if candidate != null and candidate.instance_id == instance_id:
			threat = candidate
			break
	if threat == null:
		_record_restore_diagnostic("restored_threat_missing:%s" % instance_id)
		return
	if visual == null:
		threat.biomass_whole_threat_fallback = true
		threat.biomass_fallback_reason = "restore_assembler_failed:%s" % instance_id
		_biomass_fallback_used_valid += 1
		_record_restore_diagnostic("restore_assembler_failed:%s" % instance_id)
		return
	if not (visual is Object) or not visual.has_method("configure_gait"):
		threat.biomass_whole_threat_fallback = true
		threat.biomass_fallback_reason = "restore_visual_wrong_script"
		if visual is Object:
			visual.free()
		visual = null
		_record_restore_diagnostic("restore_visual_wrong_script:%s" % instance_id)
		return
	var gait_ok: bool = bool(visual.call("configure_gait", _biomass_parts, validated_recipe, stored_seed))
	if not gait_ok:
		visual.free()
		threat.biomass_whole_threat_fallback = true
		threat.biomass_fallback_reason = "restore_gait_failed"
		_biomass_fallback_used_valid += 1
		_record_restore_diagnostic("restore_gait_failed:%s" % instance_id)
		return
	_biomass_visuals[instance_id] = visual
	_attach_biomass_visual(instance_id, visual)
	var wp: Array = entry.get("world_position", [0.0, 0.0, 0.0])
	if wp is Array and (wp as Array).size() >= 3:
		_biomass_prior_world_position[instance_id] = Vector3(float(wp[0]), float(wp[1]), float(wp[2]))

## Replace the primitive child under the stable placeholder root with the
## assembled visual. Keeping the root preserves existing manager lifecycle and
## movement code while ensuring successful biomass builds do not render a
## second primitive over the real threat.
func _attach_biomass_visual(instance_id: String, visual: Variant) -> void:
	var placeholder: Variant = placeholder_nodes.get(instance_id, null)
	if placeholder == null or not is_instance_valid(placeholder) or visual == null or not is_instance_valid(visual):
		return
	if visual.get_parent() != null:
		visual.get_parent().remove_child(visual)
	for child in placeholder.get_children():
		placeholder.remove_child(child)
		child.queue_free()
	placeholder.add_child(visual)
