extends SceneTree

## Pure-node smoke: PlayerController exposes a vitals-driven movement-speed
## multiplier seam (Domain 1 action-gating). No physics/input needed.
##
## Pass marker:
##   PLAYER MOVEMENT GATING PASS full=%.1f half=%.1f locked=%.1f

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

func _initialize() -> void:
	var p = PlayerControllerScript.new()
	var base: float = p.get_effective_move_speed()
	if base <= 0.0:
		_fail("base effective move speed should be > 0 (got %.3f)" % base)
		return
	p.set_movement_speed_multiplier(0.5)
	var half: float = p.get_effective_move_speed()
	if absf(half - base * 0.5) > 0.001:
		_fail("0.5 multiplier should halve effective speed (%.3f vs %.3f)" % [half, base * 0.5])
		return
	p.set_movement_speed_multiplier(0.0)
	var locked: float = p.get_effective_move_speed()
	if absf(locked) > 0.001:
		_fail("0.0 multiplier should lock movement (got %.3f)" % locked)
		return
	# clamp guard: out-of-range inputs are clamped, never amplify speed
	p.set_movement_speed_multiplier(5.0)
	if p.get_effective_move_speed() > base + 0.001:
		_fail("multiplier should clamp to <= 1.0")
		return
	p.free()
	print("PLAYER MOVEMENT GATING PASS full=%.1f half=%.1f locked=%.1f" % [base, half, locked])
	quit(0)

func _fail(reason: String) -> void:
	push_error("PLAYER MOVEMENT GATING FAIL reason=%s" % reason)
	quit(1)
