extends RefCounted
class_name ThreatAIState

const STATE_IDLE: String = "idle"
const STATE_INVESTIGATE: String = "investigate"
const STATE_HUNT: String = "hunt"
const STATE_ATTACK: String = "attack"
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
	awareness_score = clampf(
		float(context.get("noise_level", 0.0)) * noise_sensitivity +
		float(context.get("light_level", 0.0)) * light_sensitivity +
		float(context.get("sight_level", 0.0)) * sight_sensitivity,
		0.0,
		3.0
	)
	var crouch_mult: float = 0.65 if bool(context.get("crouching", false)) else 1.0
	awareness_score *= crouch_mult
	var same_room: bool = bool(context.get("same_room", true))
	var detection_threshold: float = float(context.get("detect_threshold", 0.85))
	if awareness_score >= detection_threshold:
		memory_remaining = memory_seconds
		last_known_room = str(context.get("room_id", room_id))
		var ppos: Variant = context.get("player_position", null)
		if ppos is Vector3:
			last_known_position = [(ppos as Vector3).x, (ppos as Vector3).y, (ppos as Vector3).z]
		elif ppos is Array and (ppos as Array).size() >= 3:
			last_known_position = [float(ppos[0]), float(ppos[1]), float(ppos[2])]
		if same_room:
			_change_state(STATE_ATTACK)
		else:
			_change_state(STATE_HUNT)
	elif memory_remaining > 0.0:
		memory_remaining = maxf(0.0, memory_remaining - delta)
		_change_state(STATE_HUNT if memory_remaining > memory_seconds * 0.4 else STATE_INVESTIGATE)
	elif awareness_score > 0.35:
		_change_state(STATE_INVESTIGATE)
	else:
		_change_state(STATE_IDLE)
	if health / max_health <= flee_threshold and health > 0.0:
		_change_state(STATE_FLEE)
	return true

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
	elif health / max_health <= flee_threshold:
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
	}

func effective_move_speed() -> float:
	match state:
		STATE_FLEE:
			return move_speed * flee_speed_mult
		STATE_INVESTIGATE:
			return move_speed * investigate_speed_mult
		STATE_HUNT, STATE_ATTACK:
			return move_speed * hunt_speed_mult
		_:
			return 0.0

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
