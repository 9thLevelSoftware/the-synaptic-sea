extends RefCounted
class_name GeneratedWorldPromptState

const LoadResult := preload("res://scripts/systems/procgen_load_result.gd")
var status: String = ""
var reason_code: String = ""
var preserved_path: String = ""
var available_actions: Array = []
var can_start_new_world: bool = false
var can_go_back: bool = false

static func from_result(result: RefCounted):
	var state = load("res://scripts/ui/generated_world_prompt_state.gd").new()
	if result == null: return state
	if not result.has_method("to_dict") or LoadResult.from_dict(result.to_dict()) == null: return state
	state.status = result.status; state.reason_code = result.reason_code; state.preserved_path = result.preserved_path
	if result.status == LoadResult.NEW_WORLD_REQUIRED: state.available_actions = ["start_new_world", "back"]
	elif result.status == LoadResult.CORRUPT or result.status == LoadResult.IO_FAILURE: state.available_actions = ["back"]
	state.can_start_new_world = state.available_actions.has("start_new_world")
	state.can_go_back = state.available_actions.has("back")
	return state
