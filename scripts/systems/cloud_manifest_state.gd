extends RefCounted
class_name CloudManifestState

## Cloud-ready manifest (ADR-0032).
##
## Pure data class. NOT a cloud SDK. The manifest is the sidecar a
## future Steam / iCloud / GOG Galaxy adapter would upload alongside
## each save. Today it captures:
##   - device_id: stable token derived from OS.user_data_dir
##   - build_id: ProjectSettings.application/config/version
##   - schema_version: mirrors CURRENT_SLICE_VERSION
##   - payload_sha256: SHA-256 of the slot file bytes
##   - payload_size_bytes
##   - created_at: ISO 8601
##   - sync_eligible: false when the save is migration-temp or corrupt
##   - cloud_provider: "stub" today; future values: "steam", "icloud", etc.
##
## On every successful save, the service writes the manifest to
## `user://saves/.cloud/<slot_id>.manifest.json`. On load, the service
## recomputes `payload_sha256` and refuses to load if the manifest's
## sha does not match the slot file (defense against silent FS tampering).

const MANIFEST_VERSION: String = "cloud-manifest-1"
const CLOUD_PROVIDER_STUB: String = "stub"

var device_id: String = ""
var build_id: String = ""
var schema_version: String = ""
var payload_sha256: String = ""
var payload_size_bytes: int = 0
var created_at: String = ""
var sync_eligible: bool = true
var cloud_provider: String = CLOUD_PROVIDER_STUB
var slot_id: String = ""

func to_dict() -> Dictionary:
	return {
		"manifest_version": MANIFEST_VERSION,
		"device_id": device_id,
		"build_id": build_id,
		"schema_version": schema_version,
		"payload_sha256": payload_sha256,
		"payload_size_bytes": payload_size_bytes,
		"created_at": created_at,
		"sync_eligible": sync_eligible,
		"cloud_provider": cloud_provider,
		"slot_id": slot_id,
	}

static func from_dict(data: Variant) -> CloudManifestState:
	var script: GDScript = load("res://scripts/systems/cloud_manifest_state.gd")
	var m: CloudManifestState = script.new()
	if typeof(data) != TYPE_DICTIONARY:
		return m
	var dict: Dictionary = data
	m.device_id = str(dict.get("device_id", ""))
	m.build_id = str(dict.get("build_id", ""))
	m.schema_version = str(dict.get("schema_version", ""))
	m.payload_sha256 = str(dict.get("payload_sha256", ""))
	m.payload_size_bytes = int(dict.get("payload_size_bytes", 0))
	m.created_at = str(dict.get("created_at", ""))
	m.sync_eligible = bool(dict.get("sync_eligible", true))
	m.cloud_provider = str(dict.get("cloud_provider", CLOUD_PROVIDER_STUB))
	m.slot_id = str(dict.get("slot_id", ""))
	return m

## Build a manifest for a freshly-written slot file.
static func build_for_slot(slot_id: String, slot_path: String, schema_version: String) -> CloudManifestState:
	var script: GDScript = load("res://scripts/systems/cloud_manifest_state.gd")
	var m: CloudManifestState = script.new()
	m.slot_id = slot_id
	m.device_id = _derive_device_id()
	m.build_id = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	m.schema_version = schema_version
	m.payload_sha256 = _sha256_of_file(slot_path)
	m.payload_size_bytes = _size_of_file(slot_path)
	m.created_at = Time.get_datetime_string_from_system(true)
	m.sync_eligible = true
	m.cloud_provider = CLOUD_PROVIDER_STUB
	return m

## Recompute the sha against the slot file's current bytes. Returns
## the empty string on I/O error; the caller treats that as "manifest
## does not match the slot file" and either rebuilds the manifest or
## refuses the load.
static func recompute_sha256(slot_path: String) -> String:
	return _sha256_of_file(slot_path)

static func _sha256_of_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	# Slot files are JSON; we hash the JSON text directly. Binary
	# hashing is unnecessary for our payload and would require an
	# extra String/PackedByteArray round-trip.
	var content: String = file.get_as_text()
	file.close()
	if content.is_empty():
		return ""
	return content.sha256_text()

static func _size_of_file(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var sz: int = int(file.get_length())
	file.close()
	return sz

static func _derive_device_id() -> String:
	# Stable across runs on the same machine: hash the user_data_dir.
	# The future cloud adapter will replace this with a real device token.
	var path: String = ProjectSettings.globalize_path("user://")
	return path.sha256_text().substr(0, 16)