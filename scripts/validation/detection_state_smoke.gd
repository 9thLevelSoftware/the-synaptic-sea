extends SceneTree

const DetectionStateScript := preload("res://scripts/systems/detection_state.gd")

func _initialize() -> void:
	var detection = DetectionStateScript.new()
	detection.configure({"detect_threshold": 0.75, "memory_seconds": 3.0})
	detection.update_inputs(0.9, 0.1, 0.2, false, "corridor_a")
	detection.tick(0.1)
	if not detection.detected:
		_fail("expected initial detection")
		return
	if detection.last_reason != "sound":
		_fail("expected sound reason got %s" % detection.last_reason)
		return
	detection.update_inputs(0.0, 0.0, 0.0, true, "corridor_a")
	detection.tick(1.0)
	if not detection.detected:
		_fail("expected memory detection to persist")
		return
	if detection.last_reason != "memory":
		_fail("expected memory reason got %s" % detection.last_reason)
		return
	detection.tick(4.0)
	if detection.detected:
		_fail("expected detection to expire")
		return
	print("DETECTION STATE PASS score=%.2f memory=%.1f reason=%s" % [
		float(detection.awareness_score),
		float(detection.memory_remaining),
		detection.last_reason,
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("DETECTION STATE FAIL reason=%s" % reason)
	quit(1)
