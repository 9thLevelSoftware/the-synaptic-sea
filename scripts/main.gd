extends Node3D

const DEFAULT_PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")

@export var playable_ship_scene: PackedScene = DEFAULT_PLAYABLE_SHIP_SCENE

var playable_instance: PlayableGeneratedShip
var _procgen_start_enabled: bool = false
var _procgen_start_seed: int = 17
var _procgen_start_size: int = 2
var _procgen_start_condition: int = 1
var _procgen_replay_request: Dictionary = {}
var _procgen_replay_semantic_hash: String = ""


## Project production boot calls this before Main enters the tree. Direct
## main-scene regression fixtures remain on the explicit authored path.
func configure_procgen_start(seed_value: int, size: int = 2, condition: int = 1) -> void:
	_procgen_start_enabled = true
	_procgen_start_seed = seed_value
	_procgen_start_size = size
	_procgen_start_condition = condition
	_procgen_replay_request = {}
	_procgen_replay_semantic_hash = ""


func configure_procgen_replay(request: Dictionary, semantic_hash: String) -> void:
	_procgen_start_enabled = true
	_procgen_replay_request = request.duplicate(true)
	_procgen_replay_semantic_hash = semantic_hash

func _ready() -> void:
	print("The Synaptic Sea coherent proof ship bootstrap loaded.")
	if playable_ship_scene == null:
		push_error("MAIN BOOT FAIL reason=missing playable_ship_scene")
		return
	playable_instance = playable_ship_scene.instantiate() as PlayableGeneratedShip
	if playable_instance == null:
		push_error("MAIN BOOT FAIL reason=playable scene is not PlayableGeneratedShip")
		return
	if not _procgen_replay_request.is_empty():
		playable_instance.configure_procgen_replay(
			_procgen_replay_request, _procgen_replay_semantic_hash)
	elif _procgen_start_enabled:
		playable_instance.configure_procgen_start(
			_procgen_start_seed, _procgen_start_size, _procgen_start_condition)
	playable_instance.name = "PlayableCoherentShip"
	add_child(playable_instance)
