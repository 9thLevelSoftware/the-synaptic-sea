extends SceneTree

const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")

class FakeGenerator extends RefCounted:
	func generator_version() -> int: return 2

func _init() -> void:
	var validator: RefCounted = ValidatorScript.new()
	var result: String = validator.validate_from_files(FakeGenerator.new(), "x86_64-pc-windows-msvc")
	if result != ValidatorScript.OK:
		print("PROCGEN_MANIFEST_SMOKE_FAIL:%s" % result)
		quit(1)
		return
	print("PROCGEN_MANIFEST_SMOKE_PASS")
	quit(0)
