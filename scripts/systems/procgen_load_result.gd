extends RefCounted
class_name ProcgenLoadResult

const COMPATIBLE := "compatible"
const NEW_WORLD_REQUIRED := "new_world_required"
const CORRUPT := "corrupt"
const IO_FAILURE := "io_failure"
const STATUSES := [COMPATIBLE, NEW_WORLD_REQUIRED, CORRUPT, IO_FAILURE]

var status := CORRUPT
var reason_code := ""
var preserved_path := ""
var identity_summary: Dictionary = {}
var envelope: RefCounted = null

static func make(value: String, reason: String, path := "", identity := {}):
	var result = load("res://scripts/systems/procgen_load_result.gd").new(); result.status = value if STATUSES.has(value) else CORRUPT
	result.reason_code = reason; result.preserved_path = path; result.identity_summary = identity.duplicate(true); return result

func is_compatible() -> bool: return status == COMPATIBLE
