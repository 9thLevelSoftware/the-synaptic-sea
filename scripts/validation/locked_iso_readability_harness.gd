extends Node3D

const SAMPLE_LAYOUT := [
	{
		"scene": preload("res://scenes/validation/samples/structural_web_bulkhead_brace_a.tscn"),
		"position": Vector3(-7.0, 0.0, -5.0),
		"rotation_y_degrees": 0.0,
	},
	{
		"scene": preload("res://scenes/validation/samples/gameplay_prop_maintenance_workbench_b.tscn"),
		"position": Vector3(7.0, 0.0, -5.0),
		"rotation_y_degrees": 90.0,
	},
	{
		"scene": preload("res://scenes/validation/samples/dressing_web_tendril_strip_c.tscn"),
		"position": Vector3(-7.0, 0.0, 5.0),
		"rotation_y_degrees": -25.0,
	},
	{
		"scene": preload("res://scenes/validation/samples/character_survivor_eva_suit_d.tscn"),
		"position": Vector3(7.0, 0.0, 5.0),
		"rotation_y_degrees": 45.0,
	},
]

func _ready() -> void:
	_spawn_preview_instances()


func _spawn_preview_instances() -> void:
	for spec: Dictionary in SAMPLE_LAYOUT:
		var scene: PackedScene = spec["scene"]
		var instance: Node3D = scene.instantiate() as Node3D
		instance.position = spec["position"]
		instance.rotation_degrees = Vector3(0.0, float(spec["rotation_y_degrees"]), 0.0)
		add_child(instance)
