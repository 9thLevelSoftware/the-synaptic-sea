extends RefCounted
class_name GeneratedWorldPromptState

const LoadResult := preload("res://scripts/systems/procgen_load_result.gd")

var status := ""
var reason_code := ""
var preserved_path := ""
var can_start_new_world := false
var can_go_back := true

static func from_result(result: RefCounted):
	var state = load("res://scripts/ui/generated_world_prompt_state.gd").new()
	if result == null: return state
	state.status = result.status; state.reason_code = result.reason_code; state.preserved_path = result.preserved_path
	state.can_start_new_world = result.status == LoadResult.NEW_WORLD_REQUIRED
	return state
