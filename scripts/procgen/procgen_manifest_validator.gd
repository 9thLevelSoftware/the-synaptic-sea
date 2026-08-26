class_name ProcgenManifestValidator
extends RefCounted

const OK: String = "ok"
const MANIFEST_MISSING: String = "manifest_missing"
const MANIFEST_INVALID: String = "manifest_invalid"
const SCHEMA_MAJOR_UNKNOWN: String = "schema_major_unknown"
const RUNTIME_MANIFEST_INVALID: String = "runtime_manifest_invalid"
const SOURCE_MISMATCH: String = "source_mismatch"
const SCHEMA_MAP_MISMATCH: String = "schema_map_mismatch"
const DIRTY_DEVELOPMENT: String = "dirty_development"
const TARGET_MISMATCH: String = "target_mismatch"
const GENERATOR_VERSION_MISMATCH: String = "generator_version_mismatch"
const CONTENT_HASH_MISMATCH: String = "content_hash_mismatch"
const CONTENT_MANIFEST_MISSING: String = "content_manifest_missing"
const CONTENT_MANIFEST_INVALID: String = "content_manifest_invalid"
const ARTIFACT_MISSING: String = "artifact_missing"
const ARTIFACT_HASH_MISMATCH: String = "artifact_hash_mismatch"

func validate(manifest: Dictionary, generator: Object, target_override: String = "", io_override: Dictionary = {}) -> String:
	if manifest.is_empty(): return MANIFEST_MISSING
	var required: Array[String] = ["manifest_schema", "rust_source_commit", "generator_version", "content_manifest_path", "content_manifest_hash", "target", "artifact", "export_schemas"]
	for key in manifest.keys():
		if not required.has(str(key)): return MANIFEST_INVALID
	for key in required:
		if not manifest.has(key): return MANIFEST_INVALID
	var schema: String = str(manifest.get("manifest_schema", ""))
	if schema != "procgen-build-manifest-3":
		return SCHEMA_MAJOR_UNKNOWN if schema.begins_with("procgen-build-manifest-") else MANIFEST_INVALID
	if int(manifest.get("generator_version", -1)) != 3: return GENERATOR_VERSION_MISMATCH
	var source_commit: String = str(manifest.get("rust_source_commit", ""))
	if source_commit.length() != 40 or source_commit != source_commit.to_lower() or not _is_hex(source_commit): return MANIFEST_INVALID
	if str(manifest.get("content_manifest_path", "")) != "data/procgen/manifests/content_manifest.json": return MANIFEST_INVALID
	var target: String = str(manifest.get("target", ""))
	if target != "x86_64-pc-windows-msvc" and target != "wasm32-unknown-unknown": return TARGET_MISMATCH
	var running_target: String = target_override
	if running_target.is_empty():
		running_target = "x86_64-pc-windows-msvc" if OS.get_name() == "Windows" and Engine.get_architecture_name() == "x86_64" else "unsupported"
	if running_target != target: return TARGET_MISMATCH
	if generator == null or not generator.has_method("generator_version") or int(generator.generator_version()) != 3:
		return GENERATOR_VERSION_MISMATCH
	var content_path: String = str(manifest.get("content_manifest_path", ""))
	if not _io_exists(content_path, io_override): return CONTENT_MANIFEST_MISSING
	var parser := JSON.new()
	if parser.parse(_io_text(content_path, io_override)) != 0: return CONTENT_MANIFEST_INVALID
	var content_variant: Variant = parser.data
	if not content_variant is Dictionary: return CONTENT_MANIFEST_INVALID
	var content: Dictionary = content_variant as Dictionary
	for key in content.keys():
		if not ["manifest_schema", "files", "content_manifest_hash"].has(str(key)): return CONTENT_MANIFEST_INVALID
	if str(content.get("manifest_schema", "")) != "procgen-content-manifest-1" or not content.get("files", []) is Array: return CONTENT_MANIFEST_INVALID
	var computed: String = _content_digest(content.get("files", []) as Array, io_override)
	if computed.is_empty(): return CONTENT_MANIFEST_INVALID
	if computed == "__CONTENT_FILE_MISMATCH__": return CONTENT_HASH_MISMATCH
	if computed != str(content.get("content_manifest_hash", "")) or computed != str(manifest.get("content_manifest_hash", "")): return CONTENT_HASH_MISMATCH
	var artifact: Variant = manifest.get("artifact", {})
	if not artifact is Dictionary: return MANIFEST_INVALID
	for key in (artifact as Dictionary).keys():
		if not ["kind", "path", "sha256"].has(str(key)): return MANIFEST_INVALID
	var expected_kind := "gdextension" if target == "x86_64-pc-windows-msvc" else "wasm"
	var expected_path := "addons/derelict/bin/win64/derelict_godot.dll" if target == "x86_64-pc-windows-msvc" else "addons/derelict/bin/web/derelict_wasm_bg.wasm"
	if str((artifact as Dictionary).get("kind", "")) != expected_kind or str((artifact as Dictionary).get("path", "")) != expected_path: return MANIFEST_INVALID
	var artifact_path: String = str((artifact as Dictionary).get("path", ""))
	if not _io_exists(artifact_path, io_override): return ARTIFACT_MISSING
	if _io_sha256(artifact_path, io_override) != str((artifact as Dictionary).get("sha256", "")): return ARTIFACT_HASH_MISMATCH
	var schemas: Dictionary = {"procgen_request":"procgen-request-2", "procgen_bundle":"procgen-bundle-4", "world_ir":"world-ir-2", "site_ir":"site-ir-2", "gameplay_ir":"gameplay-ir-2", "presentation_ir":"presentation-ir-2", "generation_trace":"generation-trace-3", "adaptive_proposal":"adaptive-proposal-1"}
	var schema_block: Variant = manifest.get("export_schemas", {})
	if not schema_block is Dictionary: return SCHEMA_MAP_MISMATCH
	for key in schema_block.keys():
		if not schemas.has(str(key)): return SCHEMA_MAP_MISMATCH
	for key in schemas.keys():
		if str(schema_block.get(key, "")) != str(schemas[key]): return SCHEMA_MAP_MISMATCH
	if generator == null or not generator.has_method("generator_manifest"):
		return RUNTIME_MANIFEST_INVALID
	var runtime_parser := JSON.new()
	if runtime_parser.parse(str(generator.generator_manifest())) != 0 or not runtime_parser.data is Dictionary:
		return RUNTIME_MANIFEST_INVALID
	var runtime: Dictionary = runtime_parser.data
	var runtime_keys: Array[String] = ["schema_version", "rust_source_commit", "generator_version", "content_manifest_hash", "export_schemas", "adapter_schemas", "target", "dirty_development"]
	for key in runtime.keys():
		if not runtime_keys.has(str(key)): return RUNTIME_MANIFEST_INVALID
	for key in runtime_keys:
		if not runtime.has(key): return RUNTIME_MANIFEST_INVALID
	if str(runtime.get("schema_version", "")) != "procgen-generator-manifest-3" \
			or int(runtime.get("generator_version", -1)) != int(manifest.get("generator_version", -2)) \
			or str(runtime.get("content_manifest_hash", "")) != str(manifest.get("content_manifest_hash", "")) \
			or str(runtime.get("target", "")) != str(manifest.get("target", "")):
		return RUNTIME_MANIFEST_INVALID
	if str(runtime.get("rust_source_commit", "")) != source_commit:
		return SOURCE_MISMATCH
	if runtime.get("dirty_development", null) is not bool or bool(runtime.get("dirty_development", true)):
		return DIRTY_DEVELOPMENT
	if not runtime.get("export_schemas", null) is Dictionary or not _same_json(runtime.export_schemas, schemas):
		return SCHEMA_MAP_MISMATCH
	var adapters: Dictionary = {"lifecycle_result":"procgen-lifecycle-result-4", "capabilities":"procgen-capabilities-3", "generator_manifest":"procgen-generator-manifest-3"}
	if not runtime.get("adapter_schemas", null) is Dictionary or not _same_json(runtime.adapter_schemas, adapters):
		return SCHEMA_MAP_MISMATCH
	return OK

func _is_hex(value: String) -> bool:
	for code in value.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)): return false
	return true

func _content_digest(entries: Array, io_override: Dictionary = {}) -> String:
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
		for exact_path in ["data/combat/threat_archetypes.json", "data/combat/threat_visual_catalog.json", "data/items/item_definitions.json", "data/kits/ship_structural_v0.json"]:
			if path == exact_path: allowed = true
		if path.is_empty() or path.contains("\\") or path.contains(":") or path.begins_with("/") or not allowed: return ""
		for segment in path.split("/"):
			if segment.is_empty() or segment == "." or segment == "..": return ""
		if paths.has(path) or (not paths.is_empty() and paths[-1] >= path): return ""
		paths.append(path)
		var absolute: String = "res://" + path
		if not _io_exists(path, io_override): return "__CONTENT_FILE_MISMATCH__"
		if _io_sha256(path, io_override) != str(entry.get("sha256", "")): return "__CONTENT_FILE_MISMATCH__"
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path in paths:
		context.update(path.to_utf8_buffer()); context.update(PackedByteArray([0])); context.update(_io_bytes(path, io_override)); context.update(PackedByteArray([0]))
	return context.finish().hex_encode()

func _same_json(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key in left.keys():
			if not right.has(key) or not _same_json(left[key], right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in left.size():
			if not _same_json(left[index], right[index]): return false
		return true
	return left == right

func _io_exists(path: String, override: Dictionary) -> bool:
	if override.has("missing") and (override["missing"] as Array).has(path): return false
	if override.has("files") and (override["files"] as Dictionary).has(path): return true
	return FileAccess.file_exists("res://" + path)

func _io_bytes(path: String, override: Dictionary) -> PackedByteArray:
	if override.has("files") and (override["files"] as Dictionary).has(path):
		var value: Variant = (override["files"] as Dictionary)[path]
		return value if value is PackedByteArray else str(value).to_utf8_buffer()
	return FileAccess.get_file_as_bytes("res://" + path)

func _io_text(path: String, override: Dictionary) -> String:
	if override.has("files") and (override["files"] as Dictionary).has(path):
		var value: Variant = (override["files"] as Dictionary)[path]
		return value if value is String else (value as PackedByteArray).get_string_from_utf8()
	return FileAccess.get_file_as_string("res://" + path)

func _io_sha256(path: String, override: Dictionary) -> String:
	if override.has("files") and (override["files"] as Dictionary).has(path):
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256); context.update(_io_bytes(path, override)); return context.finish().hex_encode()
	return FileAccess.get_sha256("res://" + path)

func validate_from_files(generator: Object, target_override: String = "") -> String:
	var path: String = "res://data/procgen/manifests/build/win64.json"
	if not FileAccess.file_exists(path): return MANIFEST_MISSING
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return MANIFEST_INVALID
	return validate(parsed as Dictionary, generator, target_override)
