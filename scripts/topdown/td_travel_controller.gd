extends Node
class_name TopDownTravelController
## Manages travel between hub and derelict in the 2D top-down path.
## Bridges the existing TravelController (RefCounted, projection-agnostic)
## with the TopDownPlayableShip scene management.

const TravelControllerScript = preload("res://scripts/systems/travel_controller.gd")
const SeaGraphScript = preload("res://scripts/systems/sea_graph.gd")

signal travel_started(destination: String)
signal travel_completed(destination: String)
signal returned_to_hub()

var travel_controller  # TravelController RefCounted
var sea_graph          # SeaGraph RefCounted
var coordinator        # TopDownPlayableShip reference

var is_traveling: bool = false
var current_location: String = "hub"


func setup(p_coordinator) -> void:
	coordinator = p_coordinator
	travel_controller = TravelControllerScript.new()
	sea_graph = SeaGraphScript.new()
	# Build sea graph from a world seed
	sea_graph.build_from_world_seed(42) if sea_graph.has_method("build_from_world_seed") else null


func travel_to_derelict(seed_value: int = 777, biome_id: String = "breach_field") -> void:
	if is_traveling:
		return
	travel_started.emit("derelict")
	if coordinator:
		coordinator.generate_derelict(seed_value, biome_id)
	current_location = "derelict"
	travel_completed.emit("derelict")


func travel_to_hub(seed_value: int = 42) -> void:
	if is_traveling:
		return
	travel_started.emit("hub")

	if coordinator:
		coordinator.generate_hub(seed_value)

	current_location = "hub"
	travel_completed.emit("hub")
	returned_to_hub.emit()


func get_current_location() -> String:
	return current_location


func get_travel_summary() -> Dictionary:
	return {
		"location": current_location,
		"is_traveling": is_traveling,
	}
