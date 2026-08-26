extends RefCounted
class_name ProcgenLoadResult

const COMPATIBLE := "compatible"
const NEW_WORLD_REQUIRED := "new_world_required"
const CORRUPT := "corrupt"
const IO_FAILURE := "io_failure"
const STATUSES := [COMPATIBLE, NEW_WORLD_REQUIRED, CORRUPT, IO_FAILURE]
const MAX_REASON := 96
const MAX_PATH := 1024
var status: String = CORRUPT
var reason_code: String = "malformed"
var preserved_path: String = ""
var identity_summary: Dictionary = {}
var envelope: RefCounted = null

static func make(value: Variant, reason: Variant, path: Variant = "", identity: Variant = {}):
	var result = load("res://scripts/systems/procgen_load_result.gd").new()
	result.status = value if typeof(value) == TYPE_STRING and STATUSES.has(value) else CORRUPT
	result.reason_code = reason if typeof(reason) == TYPE_STRING and reason.length() > 0 and reason.length() <= MAX_REASON else "malformed"
	result.preserved_path = path if typeof(path) == TYPE_STRING and path.length() <= MAX_PATH else ""
	result.identity_summary = identity.duplicate(true) if typeof(identity) == TYPE_DICTIONARY else {}
	return result

func is_compatible() -> bool:
	return status == COMPATIBLE
