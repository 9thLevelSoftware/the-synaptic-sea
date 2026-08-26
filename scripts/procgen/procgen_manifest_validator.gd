class_name ProcgenManifestValidator
extends RefCounted

const OK: String = "ok"
const MANIFEST_MISSING: String = "manifest_missing"
const MANIFEST_INVALID: String = "manifest_invalid"
const SCHEMA_MAJOR_UNKNOWN: String = "schema_major_unknown"
const TARGET_MISMATCH: String = "target_mismatch"
const GENERATOR_VERSION_MISMATCH: String = "generator_version_mismatch"
const CONTENT_HASH_MISMATCH: String = "content_hash_mismatch"
const ARTIFACT_MISSING: String = "artifact_missing"
const ARTIFACT_HASH_MISMATCH: String = "artifact_hash_mismatch"

func validate(manifest: Dictionary, generator: Object, target_override: String = "") -> String:
	if manifest.is_empty(): return MANIFEST_MISSING
	var schema: String = str(manifest.get("manifest_schema", ""))
	if schema != "procgen-build-manifest-1":
		return SCHEMA_MAJOR_UNKNOWN if schema.begins_with("procgen-build-manifest-") else MANIFEST_INVALID
	if int(manifest.get("generator_version", -1)) != 2: return GENERATOR_VERSION_MISMATCH
	var target: String = str(manifest.get("target", ""))
	if target != "x86_64-pc-windows-msvc": return TARGET_MISMATCH
	var running_target: String = target_override
	if running_target.is_empty():
		running_target = "x86_64-pc-windows-msvc" if OS.get_name() == "Windows" and OS.get_architecture_name() == "x86_64" else "unsupported"
	if running_target != target: return TARGET_MISMATCH
	if generator == null or not generator.has_method("generator_version") or int(generator.generator_version()) != 2:
		return GENERATOR_VERSION_MISMATCH
	var content_path: String = str(manifest.get("content_manifest_path", ""))
	if not FileAccess.file_exists("res://" + content_path): return CONTENT_HASH_MISMATCH
	var content_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://" + content_path))
	if not content_variant is Dictionary: return CONTENT_HASH_MISMATCH
	if str((content_variant as Dictionary).get("manifest_schema", "")) != "procgen-content-manifest-1": return CONTENT_HASH_MISMATCH
	if str(manifest.get("content_manifest_hash", "")) != str((content_variant as Dictionary).get("content_manifest_hash", "")): return CONTENT_HASH_MISMATCH
	var artifact: Variant = manifest.get("artifact", {})
	if not artifact is Dictionary: return MANIFEST_INVALID
	var artifact_path: String = str((artifact as Dictionary).get("path", ""))
	if not FileAccess.file_exists("res://" + artifact_path): return ARTIFACT_MISSING
	if FileAccess.get_sha256("res://" + artifact_path) != str((artifact as Dictionary).get("sha256", "")): return ARTIFACT_HASH_MISMATCH
	return OK

func validate_from_files(generator: Object, target_override: String = "") -> String:
	var path: String = "res://data/procgen/manifests/build/win64.json"
	if not FileAccess.file_exists(path): return MANIFEST_MISSING
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return MANIFEST_INVALID
	return validate(parsed as Dictionary, generator, target_override)
