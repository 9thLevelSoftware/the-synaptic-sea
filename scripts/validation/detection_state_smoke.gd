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
	# Domain 2: emitted profile is the post-crouch signal the AI consumes.
	var de: DetectionState = DetectionStateScript.new()
	de.configure({})
	de.update_inputs(1.0, 0.5, 0.8, false, "")
	var prof: Dictionary = de.get_emitted_profile()
	if absf(float(prof["noise"]) - 1.0) > 0.001 or absf(float(prof["light"]) - 0.5) > 0.001 or absf(float(prof["visibility"]) - 0.8) > 0.001:
		_fail("emitted profile should equal raw signals when standing")
		return
	de.update_inputs(1.0, 0.5, 0.8, true, "")  # crouching
	var profc: Dictionary = de.get_emitted_profile()
	# Pin the exact 0.65 crouch multiplier (part of the contract): 1.0*0.65=0.65, 0.8*0.65=0.52.
	if absf(float(profc["noise"]) - 0.65) > 0.001 or absf(float(profc["visibility"]) - 0.52) > 0.001:
		_fail("crouch should apply the 0.65 multiplier to emitted noise + visibility")
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
