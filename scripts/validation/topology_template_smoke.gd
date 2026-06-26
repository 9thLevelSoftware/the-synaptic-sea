extends SceneTree

const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")

func _initialize() -> void:
	# --- Case 1: from_dict round-trip ---
	var data: Dictionary = {
		"id": "test_template",
		"description": "Test topology",
		"zones": [
			{
				"id": "entry",
				"role_pool": ["airlock"],
				"count": 1,
				"position_hint": "bow",
				"deck": 0,
				"layout": "single",
				"attach_to": "",
			},
			{
				"id": "spine",
				"role_pool": ["corridor", "main_spine"],
				"count": [3, 5],
				"position_hint": "center",
				"deck": 0,
				"layout": "linear",
				"attach_to": "entry",
			},
		],
		"connections": [
			{"from": "entry", "to": "spine[0]", "distribution": "adjacent"},
		],
		"deck_config": {
			"max_decks": 2,
			"vertical_transition_probability": 0.4,
		},
	}

	var template: TopologyTemplateScript = TopologyTemplateScript.from_dict(data)
	if template == null:
		push_error("TOPOLOGY TEMPLATE FAIL from_dict returned null")
		quit(1)
		return

	if template.id != "test_template":
		push_error("TOPOLOGY TEMPLATE FAIL id=%s expected=test_template" % template.id)
		quit(1)
		return

	if template.zones.size() != 2:
		push_error("TOPOLOGY TEMPLATE FAIL zones=%d expected=2" % template.zones.size())
		quit(1)
		return

	if template.connections.size() != 1:
		push_error("TOPOLOGY TEMPLATE FAIL connections=%d expected=1" % template.connections.size())
		quit(1)
		return

	if template.deck_config.get("max_decks", 0) != 2:
		push_error("TOPOLOGY TEMPLATE FAIL max_decks=%s expected=2" % str(template.deck_config.get("max_decks", 0)))
		quit(1)
		return

	# --- Case 2: get_zone lookup ---
	var entry_zone: Dictionary = template.get_zone("entry")
	if entry_zone.is_empty():
		push_error("TOPOLOGY TEMPLATE FAIL get_zone('entry') returned empty")
		quit(1)
		return

	var missing_zone: Dictionary = template.get_zone("nonexistent")
	if not missing_zone.is_empty():
		push_error("TOPOLOGY TEMPLATE FAIL get_zone('nonexistent') should be empty")
		quit(1)
		return

	# --- Case 3: get_zones_attached_to ---
	var attached: Array[Dictionary] = template.get_zones_attached_to("entry")
	if attached.size() != 1:
		push_error("TOPOLOGY TEMPLATE FAIL attached_to entry=%d expected=1" % attached.size())
		quit(1)
		return
	if str(attached[0].get("id", "")) != "spine":
		push_error("TOPOLOGY TEMPLATE FAIL attached zone id=%s expected=spine" % str(attached[0].get("id", "")))
		quit(1)
		return

	# --- Case 4: count can be int or array ---
	var entry_count = template.zones[0].get("count", 0)
	if typeof(entry_count) != TYPE_INT and typeof(entry_count) != TYPE_FLOAT:
		push_error("TOPOLOGY TEMPLATE FAIL entry count type=%d expected int" % typeof(entry_count))
		quit(1)
		return

	var spine_count = template.zones[1].get("count", 0)
	if typeof(spine_count) != TYPE_ARRAY:
		push_error("TOPOLOGY TEMPLATE FAIL spine count type=%d expected array" % typeof(spine_count))
		quit(1)
		return

	print("TOPOLOGY TEMPLATE PASS from_dict=true get_zone=true attached=true count_types=true")
	quit(0)
