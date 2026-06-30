extends SceneTree

## Pure-node smoke: crouch reduces effective move speed and COMPOSES with the
## Domain 1 vitals movement multiplier (both apply multiplicatively).
##
## Pass marker:
##   PLAYER CROUCH PASS stand=%.2f crouch=%.2f composed=%.2f

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")

func _initialize() -> void:
	var p := PlayerControllerScript.new()
	var stand: float = p.get_effective_move_speed()
	p.set_crouching(true)
	var crouch: float = p.get_effective_move_speed()
	if not (crouch < stand and crouch > 0.0):
		_fail("crouch should reduce but not zero effective speed (%.3f vs %.3f)" % [crouch, stand])
		return
	if not p.is_crouching():
		_fail("is_crouching should report true")
		return
	# Composes with the Domain 1 vitals gate: half multiplier AND crouch.
	p.set_movement_speed_multiplier(0.5)
	var composed: float = p.get_effective_move_speed()
	if absf(composed - p.move_speed * 0.5 * PlayerControllerScript.CROUCH_SPEED_FACTOR) > 0.001:
		_fail("crouch must compose multiplicatively with the vitals gate (got %.3f)" % composed)
		return
	p.free()
	print("PLAYER CROUCH PASS stand=%.2f crouch=%.2f composed=%.2f" % [stand, crouch, composed])
	quit(0)

func _fail(reason: String) -> void:
	push_error("PLAYER CROUCH FAIL reason=%s" % reason)
	quit(1)
