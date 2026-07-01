extends SceneTree

## Domain 5 Task 5: SealedHatch checks proximity + the matching utility flag, opens
## (disables its passage collision) and emits hatch_bypassed exactly once.
## Marker: SEALED HATCH NODE PASS locked=true opened=true collision_off=true signalled=true

const SealedHatchScript := preload("res://scripts/interaction/sealed_hatch.gd")

var _signalled: int = 0

func _initialize() -> void:
	var hatch = SealedHatchScript.new()
	get_root().add_child(hatch)
	hatch.configure("hatch_a", "mechanical", Vector3.ZERO, 1.8)
	hatch.hatch_bypassed.connect(func(_id, _k): _signalled += 1)
	hatch.set_validation_player_in_range(true)
	# Wrong flag -> locked.
	var locked_res: Dictionary = hatch.try_bypass(null, {"hack_chip": {"count": 1}})
	var locked: bool = not bool(locked_res.get("ok", false)) and str(locked_res.get("reason", "")) == "locked"
	# Right flag -> opens.
	var open_res: Dictionary = hatch.try_bypass(null, {"lockpick": {"count": 1}})
	var opened: bool = bool(open_res.get("ok", false)) and hatch.bypassed
	var collision_off: bool = _blocker_collision_disabled(hatch)
	# Second attempt -> already_open, no second signal.
	hatch.try_bypass(null, {"lockpick": {"count": 1}})
	var signalled: bool = _signalled == 1
	hatch.queue_free()
	if locked and opened and collision_off and signalled:
		print("SEALED HATCH NODE PASS locked=true opened=true collision_off=true signalled=true")
		quit(0)
	else:
		push_error("SEALED HATCH NODE FAIL locked=%s opened=%s collision_off=%s signalled=%s" % [str(locked), str(opened), str(collision_off), str(signalled)])
		quit(1)

func _blocker_collision_disabled(hatch: Node) -> bool:
	for child in hatch.get_children():
		if child is StaticBody3D:
			for gc in child.get_children():
				if gc is CollisionShape3D:
					return (gc as CollisionShape3D).disabled
	return false
