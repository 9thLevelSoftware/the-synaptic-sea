extends Node
class_name TopDownSceneManager
## Manages scene transitions between hub and derelict in the top-down path.
## Handles travel animation, scene loading, and player position handoff.

signal scene_changed(scene_name: String)
signal travel_started(destination: String)
signal travel_completed(destination: String)

var current_scene_name: String = ""
var _scene_root: Node2D
var _player: CharacterBody2D
var _camera: Node2D


func setup(root: Node2D, player: CharacterBody2D, camera: Node2D) -> void:
	_scene_root = root
	_player = player
	_camera = camera


func travel_to(scene_name: String, spawn_position: Vector2 = Vector2.ZERO) -> void:
	travel_started.emit(scene_name)

	# Unload current scene children (except player and camera)
	for child in _scene_root.get_children():
		if child != _player and child != _camera:
			child.queue_free()

	# Load new scene
	var scene_path := _get_scene_path(scene_name)
	var scene_res: PackedScene = load(scene_path) as PackedScene
	if scene_res == null:
		push_warning("TopDownSceneManager: could not load " + scene_path)
		return

	var instance := scene_res.instantiate()
	_scene_root.add_child(instance)

	# Move player to spawn position
	if _player:
		_player.position = spawn_position
		_player.velocity = Vector2.ZERO

	current_scene_name = scene_name
	scene_changed.emit(scene_name)
	travel_completed.emit(scene_name)


func _get_scene_path(scene_name: String) -> String:
	match scene_name:
		"hub":
			return "res://scenes/topdown/hub_coherent_ship.tscn"
		"derelict":
			return "res://scenes/topdown/away_breach_field.tscn"
		_:
			return "res://scenes/topdown/hub_coherent_ship.tscn"
