extends SceneTree

## Node-level smoke for HangarBayControl: in-range fires the dock/launch request
## signals; out-of-range does not.

const HangarBayControlScript := preload("res://scripts/tools/hangar_bay_control.gd")

var dock_fires: int = 0
var launch_fires: int = 0
var last_carrier: String = ""
var last_slot: int = -99

func _on_dock(carrier_id: String, slot_index: int) -> void:
	dock_fires += 1
	last_carrier = carrier_id
	last_slot = slot_index

func _on_launch(carrier_id: String, slot_index: int) -> void:
	launch_fires += 1

func _init() -> void:
	var control = HangarBayControlScript.new()
	root.add_child(control)
	control.configure("carrier_x", Vector3.ZERO, 1.8)
	control.bay_dock_requested.connect(_on_dock)
	control.bay_launch_requested.connect(_on_launch)
	await process_frame

	# A player body in range fires the dock request.
	var near := CharacterBody3D.new()
	near.set_script(load("res://scripts/player/player_controller.gd"))
	root.add_child(near)
	near.global_position = Vector3(0.5, 0.0, 0.0)
	await process_frame
	assert(control.try_dock(near, -1) == true, "in-range dock fires")
	assert(dock_fires == 1 and last_carrier == "carrier_x" and last_slot == -1, "dock signal payload")
	assert(control.try_launch(near, -1) == true, "in-range launch fires")
	assert(launch_fires == 1, "launch signal fired")

	# A player body out of range does not fire.
	near.global_position = Vector3(50.0, 0.0, 0.0)
	await process_frame
	assert(control.try_dock(near, -1) == false, "out-of-range dock no-op")
	assert(dock_fires == 1, "no extra dock fire out of range")

	# Off-tree gate: a control NOT inside the tree refuses even an in-range body
	# (the strict safety property — must not fire when off-tree).
	near.global_position = Vector3.ZERO   # coincident = in distance range
	root.remove_child(control)
	await process_frame
	assert(control.try_dock(near, -1) == false, "off-tree control refuses (strict gate)")
	assert(control.try_launch(near, -1) == false, "off-tree control refuses launch")
	assert(dock_fires == 1 and launch_fires == 1, "no signal fired while control off-tree")
	root.add_child(control)

	print("HANGAR CONTROL SMOKE PASS dock=%d launch=%d" % [dock_fires, launch_fires])
	quit()
