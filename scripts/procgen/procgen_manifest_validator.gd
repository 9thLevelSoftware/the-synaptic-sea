class_name ProcgenManifestValidator
extends RefCounted

const OK: String = "ok"
const MANIFEST_MISSING: String = "manifest_missing"
const MANIFEST_INVALID: String = "manifest_invalid"
const SCHEMA_MAJOR_UNKNOWN: String = "schema_major_unknown"
const TARGET_MISMATCH: String = "target_mismatch"
const GENERATOR_VERSION_MISMATCH: String = "generator_version_mismatch"
const CONTENT_HASH_MISMATCH: String = "content_hash_mismatch"
const CONTENT_MANIFEST_MISSING: String = "content_manifest_missing"
const CONTENT_MANIFEST_INVALID: String = "content_manifest_invalid"
const ARTIFACT_MISSING: String = "artifact_missing"
const ARTIFACT_HASH_MISMATCH: String = "artifact_hash_mismatch"

func validate(manifest: Dictionary, generator: Object, target_override: String = "") -> String:
	if manifest.is_empty(): return MANIFEST_MISSING
	var required: Array[String] = ["manifest_schema", "rust_source_commit", "generator_version", "content_manifest_path", "content_manifest_hash", "target", "artifact", "export_schemas"]
	for key in manifest.keys():
		if not required.has(str(key)): return MANIFEST_INVALID
	for key in required:
		if not manifest.has(key): return MANIFEST_INVALID
	var schema: String = str(manifest.get("manifest_schema", ""))
	if schema != "procgen-build-manifest-1":
		return SCHEMA_MAJOR_UNKNOWN if schema.begins_with("procgen-build-manifest-") else MANIFEST_INVALID
	if int(manifest.get("generator_version", -1)) != 2: return GENERATOR_VERSION_MISMATCH
	var source_commit: String = str(manifest.get("rust_source_commit", ""))
	if source_commit.length() != 40 or source_commit != source_commit.to_lower() or not _is_hex(source_commit): return MANIFEST_INVALID
	if str(manifest.get("content_manifest_path", "")) != "data/procgen/manifests/content_manifest.json": return MANIFEST_INVALID
	var target: String = str(manifest.get("target", ""))
	if target != "x86_64-pc-windows-msvc": return TARGET_MISMATCH
	var running_target: String = target_override
	if running_target.is_empty():
		running_target = "x86_64-pc-windows-msvc" if OS.get_name() == "Windows" and Engine.get_architecture_name() == "x86_64" else "unsupported"
	if running_target != target: return TARGET_MISMATCH
	if generator == null or not generator.has_method("generator_version") or int(generator.generator_version()) != 2:
		return GENERATOR_VERSION_MISMATCH
	var content_path: String = str(manifest.get("content_manifest_path", ""))
	if not FileAccess.file_exists("res://" + content_path): return CONTENT_MANIFEST_MISSING
	var content_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://" + content_path))
	if not content_variant is Dictionary: return CONTENT_MANIFEST_INVALID
	var content: Dictionary = content_variant as Dictionary
	for key in content.keys():
		if not ["manifest_schema", "files", "content_manifest_hash"].has(str(key)): return CONTENT_MANIFEST_INVALID
	if str(content.get("manifest_schema", "")) != "procgen-content-manifest-1" or not content.get("files", []) is Array: return CONTENT_MANIFEST_INVALID
	var computed: String = _content_digest(content.get("files", []) as Array)
	if computed.is_empty(): return CONTENT_MANIFEST_INVALID
	if computed != str(content.get("content_manifest_hash", "")) or computed != str(manifest.get("content_manifest_hash", "")): return CONTENT_HASH_MISMATCH
	var artifact: Variant = manifest.get("artifact", {})
	if not artifact is Dictionary: return MANIFEST_INVALID
	for key in (artifact as Dictionary).keys():
		if not ["kind", "path", "sha256"].has(str(key)): return MANIFEST_INVALID
	if str((artifact as Dictionary).get("kind", "")) != "gdextension" or str((artifact as Dictionary).get("path", "")) != "addons/derelict/bin/win64/derelict_godot.dll": return MANIFEST_INVALID
	var artifact_path: String = str((artifact as Dictionary).get("path", ""))
	if not FileAccess.file_exists("res://" + artifact_path): return ARTIFACT_MISSING
	if FileAccess.get_sha256("res://" + artifact_path) != str((artifact as Dictionary).get("sha256", "")): return ARTIFACT_HASH_MISMATCH
	var schemas: Dictionary = {"procgen_request":"procgen-request-1", "procgen_bundle":"procgen-bundle-1", "world_ir":"world-ir-1", "site_ir":"site-ir-1", "gameplay_ir":"gameplay-ir-1", "presentation_ir":"presentation-ir-1", "generation_trace":"generation-trace-1", "adaptive_proposal":"adaptive-proposal-1"}
	var schema_block: Variant = manifest.get("export_schemas", {})
	if not schema_block is Dictionary: return MANIFEST_INVALID
	for key in schema_block.keys():
		if not schemas.has(str(key)): return MANIFEST_INVALID
	for key in schemas.keys():
		if str(schema_block.get(key, "")) != str(schemas[key]): return MANIFEST_INVALID
	return OK

func _is_hex(value: String) -> bool:
	for code in value.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)): return false
	return true

func _content_digest(entries: Array) -> String:
	var paths: Array[String] = []
	for entry_variant in entries:
		if not entry_variant is Dictionary: return ""
		var entry: Dictionary = entry_variant
		for key in entry.keys():
			if not ["path", "sha256"].has(str(key)): return ""
		var path: String = str(entry.get("path", ""))
		var allowed: bool = false
		for prefix in ["native/worldgen/crates/derelict_core/assets/", "data/procgen/archetypes/", "data/procgen/biomes/", "data/procgen/difficulty/", "data/procgen/encounter_tables/", "data/procgen/templates/"]:
			if path.begins_with(prefix): allowed = true
		if path.is_empty() or path.contains("\\") or path.begins_with("/") or not allowed: return ""
		if paths.has(path) or (not paths.is_empty() and paths[-1] >= path): return ""
		paths.append(path)
		var absolute: String = "res://" + path
		if not FileAccess.file_exists(absolute) or FileAccess.get_sha256(absolute) != str(entry.get("sha256", "")): return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path in paths:
		context.update(path.to_utf8_buffer()); context.update(PackedByteArray([0])); context.update(FileAccess.get_file_as_bytes("res://" + path)); context.update(PackedByteArray([0]))
	return context.finish().hex_encode()

func validate_from_files(generator: Object, target_override: String = "") -> String:
	var path: String = "res://data/procgen/manifests/build/win64.json"
	if not FileAccess.file_exists(path): return MANIFEST_MISSING
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return MANIFEST_INVALID
	return validate(parsed as Dictionary, generator, target_override)
