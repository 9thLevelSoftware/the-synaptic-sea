extends SceneTree
const TutorialStateScript := preload("res://scripts/systems/tutorial_state.gd")
func _init() -> void:
	var state = TutorialStateScript.new()
	var catalog: Dictionary = {"version": "tutorial-triggers-1", "tutorials": [{"id": "first_move", "trigger_event": "player_moved", "trigger_target": "any", "title": "Movement", "body": "Move.", "codex_topic": "Survival", "codex_entry_id": "first_move"}]}
	assert(state.configure(catalog))
	assert(state.trigger("player_moved", "any") == "first_move")
	assert(state.has_pending_banner())
	assert(state.dismiss("first_move"))
	assert(state.get_unlocked_codex_ids().size() == 1)
	assert(state.trigger("player_moved", "any") == "")
	print("TUTORIAL STATE PASS once=true dismiss=true codex_unlocks=1")
	quit()
