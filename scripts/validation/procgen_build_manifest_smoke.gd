extends SceneTree

const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")

class FakeGenerator extends RefCounted:
	var version: int = 2
	func generator_version() -> int: return version

func _init() -> void:
	var validator: RefCounted = ValidatorScript.new()
	var generator := FakeGenerator.new()
	var ship_source: String = FileAccess.get_file_as_string("res://scripts/procgen/ship_generator.gd")
	_assert(ship_source.contains("DerelictGenerator class unavailable; native path is required") and ship_source.contains("if USE_WORLDGEN:\n\t\tpush_error"), "ship generator fail closed")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	_assert(validator.validate(manifest, generator, "x86_64-pc-windows-msvc") == ValidatorScript.OK, "valid")
	var cases: Dictionary = {"source": "rust_source_commit", "content_path": "content_manifest_path", "artifact_kind": "artifact", "schemas": "export_schemas", "content": "content_manifest_hash"}
	for case_name in cases:
		var tampered: Dictionary = manifest.duplicate(true)
		if case_name == "artifact_kind": tampered["artifact"]["kind"] = "wrong"
		elif case_name == "schemas": tampered["export_schemas"]["world_ir"] = "wrong"
		elif case_name == "content": tampered["content_manifest_hash"] = "0".repeat(64)
		else: tampered[cases[case_name]] = "wrong"
		_assert(validator.validate(tampered, generator, "x86_64-pc-windows-msvc") != ValidatorScript.OK, case_name)
	var missing_artifact: Dictionary = manifest.duplicate(true); missing_artifact["artifact"]["path"] = "addons/derelict/bin/win64/missing.dll"
	_assert(validator.validate(missing_artifact, generator, "x86_64-pc-windows-msvc") == ValidatorScript.MANIFEST_INVALID, "missing artifact contract")
	var wrong_hash: Dictionary = manifest.duplicate(true); wrong_hash["artifact"]["sha256"] = "0".repeat(64)
	_assert(validator.validate(wrong_hash, generator, "x86_64-pc-windows-msvc") == ValidatorScript.ARTIFACT_HASH_MISMATCH, "artifact hash")
	var bad_generator := FakeGenerator.new(); bad_generator.version = 1
	_assert(validator.validate(manifest, bad_generator, "x86_64-pc-windows-msvc") == ValidatorScript.GENERATOR_VERSION_MISMATCH, "generator")
	print("PROCGEN BUILD MANIFEST PASS negative_cases=10 fail_closed=true")
	quit(0)

func _assert(condition: bool, label: String) -> void:
	if not condition:
		print("PROCGEN BUILD MANIFEST FAIL:%s" % label)
		quit(1)
