extends RefCounted
class_name TutorialStateSchema
## Static validation for `TutorialState` catalogs (REQ-UI-005 / ADR-0033).
##
## A tutorial trigger catalog is a JSON document with the following
## shape:
##
##   {
##     "version": "tutorial-triggers-1",
##     "tutorials": [
##       {
##         "id": "first_move",
##         "trigger_event": "player_moved",
##         "trigger_target": "any",
##         "title": "Movement",
##         "body": "WASD or the left stick to move.",
##         "codex_topic": "Survival",
##         "codex_entry_id": "first_move"
##       },
##       ...
##     ]
##   }
##
## The schema rejects:
##   - missing / non-Dictionary root
##   - wrong `version`
##   - non-Array `tutorials`
##   - entry missing any required field
##   - empty `id` / `trigger_event` / `title`
##   - duplicate `id` across tutorials
##   - duplicate `(trigger_event, trigger_target)` pair (one trigger = one tutorial)

const SCHEMA_VERSION: String = "tutorial-triggers-1"

static func validate(catalog: Variant) -> bool:
	if catalog == null or typeof(catalog) != TYPE_DICTIONARY:
		push_error("TutorialStateSchema: catalog must be a Dictionary; got %s" % typeof(catalog))
		return false
	var dict: Dictionary = catalog
	if str(dict.get("version", "")) != SCHEMA_VERSION:
		push_error("TutorialStateSchema: version mismatch (expected %s)" % SCHEMA_VERSION)
		return false
	var tutorials_variant: Variant = dict.get("tutorials", null)
	if typeof(tutorials_variant) != TYPE_ARRAY:
		push_error("TutorialStateSchema: 'tutorials' must be an Array")
		return false
	var tutorials: Array = tutorials_variant
	var seen_ids: Dictionary = {}
	var seen_triggers: Dictionary = {}
	for tutorial in tutorials:
		if typeof(tutorial) != TYPE_DICTIONARY:
			push_error("TutorialStateSchema: tutorial must be a Dictionary")
			return false
		var t_dict: Dictionary = tutorial
		var id_str: String = str(t_dict.get("id", ""))
		if id_str.is_empty():
			push_error("TutorialStateSchema: tutorial missing 'id'")
			return false
		if seen_ids.has(id_str):
			push_error("TutorialStateSchema: duplicate tutorial id '%s'" % id_str)
			return false
		seen_ids[id_str] = true
		var event_str: String = str(t_dict.get("trigger_event", ""))
		if event_str.is_empty():
			push_error("TutorialStateSchema: tutorial '%s' missing 'trigger_event'" % id_str)
			return false
		var target_str: String = str(t_dict.get("trigger_target", ""))
		if target_str.is_empty():
			push_error("TutorialStateSchema: tutorial '%s' missing 'trigger_target'" % id_str)
			return false
		var trigger_key: String = event_str + "|" + target_str
		if seen_triggers.has(trigger_key):
			push_error("TutorialStateSchema: duplicate trigger (event, target)=(%s, %s)" % [event_str, target_str])
			return false
		seen_triggers[trigger_key] = id_str
		var title: String = str(t_dict.get("title", ""))
		if title.is_empty():
			push_error("TutorialStateSchema: tutorial '%s' missing 'title'" % id_str)
			return false
		var body: String = str(t_dict.get("body", ""))
		if body.is_empty():
			push_error("TutorialStateSchema: tutorial '%s' missing 'body'" % id_str)
			return false
	return true