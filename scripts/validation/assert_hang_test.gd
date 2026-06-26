extends SceneTree

func _initialize() -> void:
	assert(false, "deliberate failure")
	print("AFTER ASSERT")
	quit()
