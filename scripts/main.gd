extends Node3D

const DEFAULT_PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")

@export var playable_ship_scene: PackedScene = DEFAULT_PLAYABLE_SHIP_SCENE

var playable_instance: PlayableGeneratedShip

func _ready() -> void:
	print("The Synapse Sea coherent proof ship bootstrap loaded.")
	if playable_ship_scene == null:
		push_error("MAIN BOOT FAIL reason=missing playable_ship_scene")
		return
	playable_instance = playable_ship_scene.instantiate() as PlayableGeneratedShip
	if playable_instance == null:
		push_error("MAIN BOOT FAIL reason=playable scene is not PlayableGeneratedShip")
		return
	playable_instance.name = "PlayableCoherentShip"
	add_child(playable_instance)
