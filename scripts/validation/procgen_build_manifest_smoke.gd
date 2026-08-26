extends SceneTree

const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")

class FakeGenerator extends RefCounted:
	var version: int = 3
	func generator_version() -> int: return version

func _init() -> void:
	var failures: Array[String] = []
	var stats: Dictionary = {"count": 0}
	var validator: RefCounted = ValidatorScript.new()
	var generator := FakeGenerator.new()
	var ship_source: String = FileAccess.get_file_as_string("res://scripts/procgen/ship_generator.gd")
	_expect(
		failures,
		stats,
		ship_source.contains("if not USE_WORLDGEN or not ClassDB.class_exists(\"DerelictGenerator\"):")
			and ship_source.contains("_generation_fail(\"native_adapter_unavailable\"")
			and ship_source.contains("func generate_migration_oracle("),
		"ship generator fail closed",
	)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	var content_path: String = "data/procgen/manifests/content_manifest.json"
	var artifact_path: String = str(manifest["artifact"]["path"])
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + content_path))
	var base_io: Dictionary = {"files": {content_path: FileAccess.get_file_as_string("res://" + content_path), artifact_path: FileAccess.get_file_as_bytes("res://" + artifact_path)}}
	_expect(failures, stats, validator.validate(manifest, generator, "x86_64-pc-windows-msvc", base_io) == ValidatorScript.OK, "valid")
	var cases: Dictionary = {"manifest_schema":"wrong", "rust_source_commit":"wrong", "generator_version":1, "content_manifest_path":"wrong", "content_manifest_hash":"0".repeat(64), "target":"linux", "artifact":"wrong", "export_schemas":"wrong"}
	for case_name in cases:
		var tampered: Dictionary = manifest.duplicate(true)
		if case_name == "artifact": tampered["artifact"]["kind"] = "wrong"
		else: tampered[case_name] = cases[case_name]
		_expect(failures, stats, validator.validate(tampered, generator, "x86_64-pc-windows-msvc", base_io) != ValidatorScript.OK, "top-level " + case_name)
	for schema_name in manifest["export_schemas"]:
		var tampered_schema: Dictionary = manifest.duplicate(true); tampered_schema["export_schemas"][schema_name] = "wrong"
		_expect(failures, stats, validator.validate(tampered_schema, generator, "x86_64-pc-windows-msvc", base_io) != ValidatorScript.OK, "schema " + schema_name)
	var extra: Dictionary = manifest.duplicate(true); extra["extra"] = true
	_expect(failures, stats, validator.validate(extra, generator, "x86_64-pc-windows-msvc", base_io) == ValidatorScript.MANIFEST_INVALID, "extra field")
	var missing: Dictionary = manifest.duplicate(true); missing.erase("target")
	_expect(failures, stats, validator.validate(missing, generator, "x86_64-pc-windows-msvc", base_io) == ValidatorScript.MANIFEST_INVALID, "missing field")
	var missing_artifact_io: Dictionary = base_io.duplicate(true); missing_artifact_io["missing"] = [artifact_path]
	_expect(failures, stats, validator.validate(manifest, generator, "x86_64-pc-windows-msvc", missing_artifact_io) == ValidatorScript.ARTIFACT_MISSING, "missing artifact")
	var wrong_hash: Dictionary = manifest.duplicate(true); wrong_hash["artifact"]["sha256"] = "0".repeat(64)
	_expect(failures, stats, validator.validate(wrong_hash, generator, "x86_64-pc-windows-msvc", base_io) == ValidatorScript.ARTIFACT_HASH_MISMATCH, "artifact hash")
	var content_missing_io: Dictionary = base_io.duplicate(true); content_missing_io["missing"] = [content_path]
	_expect(failures, stats, validator.validate(manifest, generator, "x86_64-pc-windows-msvc", content_missing_io) == ValidatorScript.CONTENT_MANIFEST_MISSING, "content missing")
	var content_bad_io: Dictionary = base_io.duplicate(true); content_bad_io["files"][content_path] = "not json"
	_expect(failures, stats, validator.validate(manifest, generator, "x86_64-pc-windows-msvc", content_bad_io) == ValidatorScript.CONTENT_MANIFEST_INVALID, "content malformed")
	var entry_bad_io: Dictionary = base_io.duplicate(true); var entry_bad: Dictionary = content.duplicate(true); entry_bad["files"] = (content["files"] as Array).duplicate(true); entry_bad["files"][0]["sha256"] = "0".repeat(64); entry_bad_io["files"][content_path] = JSON.stringify(entry_bad)
	_expect(failures, stats, validator.validate(manifest, generator, "x86_64-pc-windows-msvc", entry_bad_io) == ValidatorScript.CONTENT_HASH_MISMATCH, "content entry mismatch")
	var bytes_bad_io: Dictionary = base_io.duplicate(true); bytes_bad_io["files"][str((content["files"] as Array)[0]["path"])] = PackedByteArray([1, 2, 3])
	_expect(failures, stats, validator.validate(manifest, generator, "x86_64-pc-windows-msvc", bytes_bad_io) == ValidatorScript.CONTENT_HASH_MISMATCH, "content bytes mismatch")
	var aggregate_bad_io: Dictionary = base_io.duplicate(true); var aggregate_bad: Dictionary = content.duplicate(true); aggregate_bad["content_manifest_hash"] = "0".repeat(64); aggregate_bad_io["files"][content_path] = JSON.stringify(aggregate_bad)
	_expect(failures, stats, validator.validate(manifest, generator, "x86_64-pc-windows-msvc", aggregate_bad_io) == ValidatorScript.CONTENT_HASH_MISMATCH, "aggregate mismatch")
	var bad_generator := FakeGenerator.new(); bad_generator.version = 2
	_expect(failures, stats, validator.validate(manifest, bad_generator, "x86_64-pc-windows-msvc", base_io) == ValidatorScript.GENERATOR_VERSION_MISMATCH, "generator")
	_expect(failures, stats, validator.validate(manifest, generator, "linux", base_io) == ValidatorScript.TARGET_MISMATCH, "target")
	var unknown_major: Dictionary = manifest.duplicate(true); unknown_major["manifest_schema"] = "procgen-build-manifest-3"
	_expect(failures, stats, validator.validate(unknown_major, generator, "x86_64-pc-windows-msvc", base_io) == ValidatorScript.SCHEMA_MAJOR_UNKNOWN, "unknown major")
	if not failures.is_empty():
		for failure in failures: print("PROCGEN BUILD MANIFEST FAIL:%s" % failure)
		quit(1); return
	print("PROCGEN BUILD MANIFEST PASS negative_cases=%d fail_closed=true" % int(stats["count"]))
	quit(0)

func _expect(failures: Array[String], stats: Dictionary, condition: bool, label: String) -> void:
	stats["count"] = int(stats["count"]) + 1
	if not condition: failures.append(label)
