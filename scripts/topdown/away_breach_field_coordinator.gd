extends Node2D
## Away breach field scene — derelict exploration with threats.
## Production scene for the top-down vertical slice.

const TopDownThreatManagerScript = preload("res://scripts/threats/topdown_threat_manager.gd")

var tilemap: TileMapLayer
var camera_rig: Node2D
var player: CharacterBody2D
var threat_manager


func _ready() -> void:
	camera_rig = get_node_or_null("TopDownCameraRig")
	player = get_node_or_null("Player")

	# Create threat manager
	threat_manager = TopDownThreatManagerScript.new()
	threat_manager.name = "ThreatManager"
	add_child(threat_manager)

	# Wire camera
	if camera_rig and player and camera_rig.has_method("set_follow_target"):
		camera_rig.set_follow_target(player)

	# Spawn threats for the derelict
	_spawn_derelict_threats()


func _spawn_derelict_threats() -> void:
	# 3 threats as per vertical slice contract
	threat_manager.spawn_threat("biomatter_swarm", Vector2(200, 100), "swarm_01")
	threat_manager.spawn_threat("stalker", Vector2(350, 250), "stalker_01")
	threat_manager.spawn_threat("hull_tendril", Vector2(150, 300), "tendril_01")


func _physics_process(delta: float) -> void:
	if threat_manager == null or player == null:
		return
	# Tick threats with player position
	var ctx := {
		"noise_level": 0.5,
		"light_level": 0.6,
		"sight_level": 0.8,
		"crouching": player.is_crouching() if player.has_method("is_crouching") else false,
	}
	threat_manager.tick_threats(delta, player.position, ctx)
