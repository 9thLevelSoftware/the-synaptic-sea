extends RefCounted
class_name ThreatAIState

const SimKeysScript := preload("res://scripts/systems/sim_keys.gd")

const STATE_IDLE: String = "idle"
const STATE_INVESTIGATE: String = "investigate"
const STATE_HUNT: String = "hunt"
const STATE_ATTACK: String = "attack"
const STATE_TELEGRAPH: String = "telegraph"  # PKG-C4.2 windup before strike
const STATE_FLEE: String = "flee"
const STATE_STUN: String = "stun"
const STATE_DEAD: String = "dead"

var instance_id: String = ""
var archetype_id: String = ""
var display_name: String = "Threat"
var room_id: String = ""
var cell: Array = [0, 0]
var world_position: Array = [0.0, 0.0, 0.0]
var state: String = STATE_IDLE
var previous_state: String = STATE_IDLE
var max_health: float = 20.0
var health: float = 20.0
var attack_damage: float = 5.0
## REQ-MI-004: optional structure damage applied to ModuleIntegrityMap (hull tendril).
var structure_damage: float = 0.0
var attack_type: String = "physical"
var attack_noise: float = 0.4
var attack_interval: float = 1.4
var attack_cooldown: float = 0.0
var noise_sensitivity: float = 1.0
var light_sensitivity: float = 1.0
var sight_sensitivity: float = 1.0
var memory_seconds: float = 5.0
var memory_remaining: float = 0.0
var flee_threshold: float = 0.15
var stunned_remaining: float = 0.0
var awareness_score: float = 0.0
var last_known_room: String = ""
var status_on_hit: String = ""
var armor_profile: Dictionary = {}
var tags: Array = []
## ADR-0049: metres per second (base). Multipliers scale by AI state.
var move_speed: float = 2.5
var hunt_speed_mult: float = 1.0
var flee_speed_mult: float = 1.35
var investigate_speed_mult: float = 0.7
var attack_range: float = 1.4
## Last known player world position for INVESTIGATE (optional; room_id still used).
var last_known_position: Array = []
## PKG-C4.2 data-driven FSM modifiers (one FSM, per-archetype behavior).
var ambush_hold: bool = false
var stalk_range: float = 0.0          # metres; 0 = attack immediately when same room
var swarm_split: bool = false
var anchored: bool = false
var telegraph_seconds: float = 0.0
var telegraph_remaining: float = 0.0
var player_verb: String = "fight"     # distinct player response verb

func configure(config: Dictionary = {}) -> void:
	instance_id = str(config.get("instance_id", instance_id))
	archetype_id = str(config.get("archetype_id", archetype_id))
	display_name = str(config.get("display_name", display_name))
	room_id = str(config.get("room_id", room_id))
	var raw_cell: Variant = config.get("cell", cell)
	if raw_cell is Array:
		cell = (raw_cell as Array).duplicate(true)
	var raw_pos: Variant = config.get("world_position", world_position)
	if raw_pos is Array and (raw_pos as Array).size() >= 3:
		world_position = [float(raw_pos[0]), float(raw_pos[1]), float(raw_pos[2])]
	state = str(config.get("state", state))
	previous_state = str(config.get("previous_state", previous_state))
	max_health = maxf(1.0, float(config.get("max_health", max_health)))
	health = clampf(float(config.get("health", max_health)), 0.0, max_health)
	attack_damage = maxf(0.0, float(config.get("attack_damage", attack_damage)))
	structure_damage = maxf(0.0, float(config.get("structure_damage", structure_damage)))
	attack_type = str(config.get("attack_type", attack_type))
	attack_noise = maxf(0.0, float(config.get("attack_noise", attack_noise)))
	attack_interval = maxf(0.1, float(config.get("attack_interval", attack_interval)))
	attack_cooldown = maxf(0.0, float(config.get("attack_cooldown", attack_cooldown)))
	noise_sensitivity = maxf(0.0, float(config.get("noise_sensitivity", noise_sensitivity)))
	light_sensitivity = maxf(0.0, float(config.get("light_sensitivity", light_sensitivity)))
	sight_sensitivity = maxf(0.0, float(config.get("sight_sensitivity", sight_sensitivity)))
	memory_seconds = maxf(0.0, float(config.get("memory_seconds", memory_seconds)))
	memory_remaining = maxf(0.0, float(config.get("memory_remaining", memory_remaining)))
	flee_threshold = clampf(float(config.get("flee_threshold", flee_threshold)), 0.0, 0.95)
	stunned_remaining = maxf(0.0, float(config.get("stunned_remaining", stunned_remaining)))
	awareness_score = clampf(float(config.get("awareness_score", awareness_score)), 0.0, 3.0)
	last_known_room = str(config.get("last_known_room", last_known_room))
	status_on_hit = str(config.get("status_on_hit", status_on_hit))
	armor_profile = (config.get("armor", config.get("armor_profile", armor_profile)) as Dictionary).duplicate(true) if (config.get("armor", config.get("armor_profile", armor_profile)) is Dictionary) else {}
	var raw_tags: Variant = config.get("tags", tags)
	if raw_tags is Array:
		tags = (raw_tags as Array).duplicate(true)
	move_speed = maxf(0.1, float(config.get("move_speed", move_speed)))
	hunt_speed_mult = maxf(0.1, float(config.get("hunt_speed_mult", hunt_speed_mult)))
	flee_speed_mult = maxf(0.1, float(config.get("flee_speed_mult", flee_speed_mult)))
	investigate_speed_mult = maxf(0.1, float(config.get("investigate_speed_mult", investigate_speed_mult)))
	attack_range = maxf(0.3, float(config.get("attack_range", attack_range)))
	var lkp: Variant = config.get("last_known_position", last_known_position)
	if lkp is Array and (lkp as Array).size() >= 3:
		last_known_position = [float(lkp[0]), float(lkp[1]), float(lkp[2])]
	# PKG-C4.2 behavior modifiers (top-level or nested "behavior")
	var beh: Dictionary = {}
	var beh_raw: Variant = config.get("behavior", {})
	if beh_raw is Dictionary:
		beh = beh_raw as Dictionary
	ambush_hold = bool(config.get("ambush_hold", beh.get("ambush_hold", ambush_hold)))
	stalk_range = maxf(0.0, float(config.get("stalk_range", beh.get("stalk_range", stalk_range))))
	swarm_split = bool(config.get("swarm_split", beh.get("swarm_split", swarm_split)))
	anchored = bool(config.get("anchored", beh.get("anchored", anchored)))
	telegraph_seconds = maxf(0.0, float(config.get("telegraph_seconds", beh.get("telegraph_seconds", telegraph_seconds))))
	telegraph_remaining = maxf(0.0, float(config.get("telegraph_remaining", telegraph_remaining)))
	player_verb = str(config.get("player_verb", beh.get("player_verb", player_verb)))
	if player_verb.is_empty():
		player_verb = "fight"

func tick(delta: float, context: Dictionary = {}) -> bool:
	if delta < 0.0:
		return false
	if attack_cooldown > 0.0:
		attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if health <= 0.0:
		_change_state(STATE_DEAD)
		return true
	if stunned_remaining > 0.0:
		stunned_remaining = maxf(0.0, stunned_remaining - delta)
		memory_remaining = maxf(memory_remaining, delta)
		_change_state(STATE_STUN)
		return true
	# Telegraph windup resolves into attack
	if state == STATE_TELEGRAPH:
		telegraph_remaining = maxf(0.0, telegraph_remaining - delta)
		if telegraph_remaining <= 0.0:
			_change_state(STATE_ATTACK)
		return true
	awareness_score = clampf(
		float(context.get(SimKeysScript.NOISE_LEVEL, 0.0)) * noise_sensitivity +
		float(context.get(SimKeysScript.LIGHT_LEVEL, 0.0)) * light_sensitivity +
		float(context.get(SimKeysScript.SIGHT_LEVEL, 0.0)) * sight_sensitivity,
		0.0,
		3.0
	)
	var crouch_mult: float = 0.65 if bool(context.get(SimKeysScript.CROUCHING, false)) else 1.0
	awareness_score *= crouch_mult
	# Swarm split: low HP spikes awareness / commitment
	if swarm_split and health / max_health <= 0.55:
		awareness_score = minf(3.0, awareness_score + 0.35)
	var same_room: bool = bool(context.get(SimKeysScript.SAME_ROOM, true))
	var detection_threshold: float = float(context.get(SimKeysScript.DETECT_THRESHOLD, 0.85))
	var player_distance: float = float(context.get("player_distance", 0.0))
	if awareness_score >= detection_threshold:
		memory_remaining = memory_seconds
		last_known_room = str(context.get(SimKeysScript.ROOM_ID, room_id))
		var ppos: Variant = context.get(SimKeysScript.PLAYER_POSITION, null)
		if ppos is Vector3:
			last_known_position = [(ppos as Vector3).x, (ppos as Vector3).y, (ppos as Vector3).z]
		elif ppos is Array and (ppos as Array).size() >= 3:
			last_known_position = [float(ppos[0]), float(ppos[1]), float(ppos[2])]
		if same_room:
			_resolve_engagement(player_distance)
		else:
			_change_state(STATE_HUNT)
	elif ambush_hold and state == STATE_IDLE and awareness_score < detection_threshold:
		# Stay hidden until committed detection
		_change_state(STATE_IDLE)
	elif memory_remaining > 0.0:
		memory_remaining = maxf(0.0, memory_remaining - delta)
		_change_state(STATE_HUNT if memory_remaining > memory_seconds * 0.4 else STATE_INVESTIGATE)
	elif awareness_score > 0.35:
		if ambush_hold:
			_change_state(STATE_IDLE)  # hold until full detect
		else:
			_change_state(STATE_INVESTIGATE)
	else:
		_change_state(STATE_IDLE)
	if health / max_health <= flee_threshold and health > 0.0 and not anchored:
		_change_state(STATE_FLEE)
	return true


func _resolve_engagement(player_distance: float) -> void:
	# Stalk: keep hunting until within stalk_range (or attack_range if stalk unset).
	if stalk_range > 0.0 and player_distance > stalk_range:
		_change_state(STATE_HUNT)
		return
	_enter_attack_pipeline()


func _enter_attack_pipeline() -> void:
	if telegraph_seconds > 0.0 and state != STATE_ATTACK and state != STATE_TELEGRAPH:
		telegraph_remaining = telegraph_seconds
		_change_state(STATE_TELEGRAPH)
	else:
		_change_state(STATE_ATTACK)

func can_attack() -> bool:
	return state == STATE_ATTACK and attack_cooldown <= 0.0 and health > 0.0

func consume_attack() -> void:
	attack_cooldown = attack_interval

func apply_damage(payload: Dictionary) -> Dictionary:
	var damage: float = maxf(0.0, float(payload.get("final_damage", payload.get("amount", 0.0))))
	health = maxf(0.0, health - damage)
	if payload.has("armor_profile") and payload.get("armor_profile") is Dictionary:
		armor_profile = (payload.get("armor_profile") as Dictionary).duplicate(true)
	var stun_seconds: float = maxf(0.0, float(payload.get("stun_seconds", 0.0)))
	if stun_seconds > 0.0:
		stunned_remaining = maxf(stunned_remaining, stun_seconds)
	if health <= 0.0:
		_change_state(STATE_DEAD)
	elif stun_seconds > 0.0:
		_change_state(STATE_STUN)
	elif health / max_health <= flee_threshold and not anchored:
		_change_state(STATE_FLEE)
	elif swarm_split and health > 0.0 and health / max_health <= 0.55:
		# Swarm under pressure disperses (flee) unless anchored
		if not anchored:
			_change_state(STATE_FLEE)
	return get_summary()

func get_summary() -> Dictionary:
	return {
		"instance_id": instance_id,
		"archetype_id": archetype_id,
		"display_name": display_name,
		"room_id": room_id,
		"cell": cell.duplicate(true),
		"world_position": world_position.duplicate(true),
		"state": state,
		"previous_state": previous_state,
		"max_health": max_health,
		"health": health,
		"attack_damage": attack_damage,
		"attack_type": attack_type,
		"attack_noise": attack_noise,
		"attack_interval": attack_interval,
		"attack_cooldown": attack_cooldown,
		"noise_sensitivity": noise_sensitivity,
		"light_sensitivity": light_sensitivity,
		"sight_sensitivity": sight_sensitivity,
		"memory_seconds": memory_seconds,
		"memory_remaining": memory_remaining,
		"flee_threshold": flee_threshold,
		"stunned_remaining": stunned_remaining,
		"awareness_score": awareness_score,
		"last_known_room": last_known_room,
		"status_on_hit": status_on_hit,
		"armor_profile": armor_profile.duplicate(true),
		"tags": tags.duplicate(true),
		"move_speed": move_speed,
		"hunt_speed_mult": hunt_speed_mult,
		"flee_speed_mult": flee_speed_mult,
		"investigate_speed_mult": investigate_speed_mult,
		"attack_range": attack_range,
		"last_known_position": last_known_position.duplicate(true),
		"ambush_hold": ambush_hold,
		"stalk_range": stalk_range,
		"swarm_split": swarm_split,
		"anchored": anchored,
		"telegraph_seconds": telegraph_seconds,
		"telegraph_remaining": telegraph_remaining,
		"player_verb": player_verb,
	}

func effective_move_speed() -> float:
	if anchored and state != STATE_ATTACK and state != STATE_TELEGRAPH:
		return 0.0
	match state:
		STATE_FLEE:
			return move_speed * flee_speed_mult
		STATE_INVESTIGATE:
			return move_speed * investigate_speed_mult
		STATE_HUNT, STATE_ATTACK, STATE_TELEGRAPH:
			return move_speed * hunt_speed_mult
		_:
			return 0.0


## PKG-C4.2: player-facing response verb for this archetype (distinct per role).
func get_player_verb() -> String:
	return player_verb

func last_known_world_position() -> Vector3:
	if last_known_position.size() >= 3:
		return Vector3(float(last_known_position[0]), float(last_known_position[1]), float(last_known_position[2]))
	return Vector3.INF

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var before: String = JSON.stringify(get_summary())
	configure(summary)
	return before != JSON.stringify(get_summary())

func get_status_lines() -> PackedStringArray:
	return PackedStringArray([
		"%s: %s hp=%.1f/%.1f" % [display_name, state, health, max_health],
		"%s awareness=%.2f room=%s memory=%.1f" % [display_name, awareness_score, room_id, memory_remaining],
	])

func _change_state(next_state: String) -> void:
	if state == next_state:
		return
	previous_state = state
	state = next_state
