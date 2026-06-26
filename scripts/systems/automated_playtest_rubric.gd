extends RefCounted
class_name AutomatedPlaytestRubric

## REQ-INT-005 automated cross-system playtest rubric.
##
## Pure deterministic scorer for scripted scenario summaries. It is deliberately
## data-driven so future main-scene or human-playtest logs can feed the same
## contract without changing the scoring rules.

var required_stages: Array = []
var min_visible_consequences: int = 1
var min_player_choices: int = 1
var max_stuck_events: int = 0
var min_score: float = 0.75
var _last_result: Dictionary = {}

func configure(data: Dictionary) -> bool:
	if data == null:
		data = {}
	required_stages = _to_string_array(data.get("required_stages", []))
	min_visible_consequences = int(data.get("min_visible_consequences", 1))
	min_player_choices = int(data.get("min_player_choices", 1))
	max_stuck_events = int(data.get("max_stuck_events", 0))
	min_score = float(data.get("min_score", 0.75))
	return true

func evaluate_scenario(scenario: Dictionary) -> Dictionary:
	var stages_seen: Dictionary = {}
	for stage in _to_string_array(scenario.get("stages", [])):
		stages_seen[stage] = true
	var visible_count: int = 0
	var system_tags: Dictionary = {}
	var steps: Array = _as_array(scenario.get("steps", []))
	for raw_step in steps:
		var step: Dictionary = _as_dict(raw_step)
		var stage: String = str(step.get("stage", ""))
		if not stage.is_empty():
			stages_seen[stage] = true
		if bool(step.get("visible_consequence", false)):
			visible_count += 1
		for system_id in _to_string_array(step.get("systems", [])):
			if not system_id.is_empty():
				system_tags[system_id] = true
	var missing_stages: Array = []
	for required in required_stages:
		if not stages_seen.has(str(required)):
			missing_stages.append(str(required))
	var required_count: int = maxi(1, required_stages.size())
	var covered_count: int = required_count - missing_stages.size()
	var stage_score: float = clampf(float(covered_count) / float(required_count), 0.0, 1.0)
	var visible_score: float = clampf(float(visible_count) / float(maxi(1, min_visible_consequences)), 0.0, 1.0)
	var choice_count: int = int(scenario.get("player_choice_count", scenario.get("hud_updates", 0)))
	var choice_score: float = clampf(float(choice_count) / float(maxi(1, min_player_choices)), 0.0, 1.0)
	var stuck_events: int = int(scenario.get("stuck_events", 0))
	var stuck_score: float = 1.0 if stuck_events <= max_stuck_events else 0.0
	var score: float = (stage_score + visible_score + choice_score + stuck_score) / 4.0
	var passed: bool = missing_stages.is_empty() and visible_count >= min_visible_consequences and choice_count >= min_player_choices and stuck_events <= max_stuck_events and score >= min_score
	_last_result = {
		"pass": passed,
		"score": score,
		"covered_stage_count": covered_count,
		"required_stage_count": required_count,
		"missing_stages": missing_stages,
		"visible_consequence_count": visible_count,
		"system_tag_count": system_tags.size(),
		"choice_count": choice_count,
		"stuck_events": stuck_events,
	}
	return _last_result.duplicate(true)

func get_summary() -> Dictionary:
	return _last_result.duplicate(true)

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Automated Playtest Rubric: score=%.2f pass=%s" % [float(_last_result.get("score", 0.0)), str(bool(_last_result.get("pass", false))).to_lower()])
	lines.append("  stages=%d/%d visible=%d choices=%d stuck=%d" % [
		int(_last_result.get("covered_stage_count", 0)),
		int(_last_result.get("required_stage_count", 0)),
		int(_last_result.get("visible_consequence_count", 0)),
		int(_last_result.get("choice_count", 0)),
		int(_last_result.get("stuck_events", 0)),
	])
	return lines

func _to_string_array(value: Variant) -> Array:
	var out: Array = []
	for item in _as_array(value):
		out.append(str(item))
	return out

func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	if value == null:
		return []
	return [value]

func _as_dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}
