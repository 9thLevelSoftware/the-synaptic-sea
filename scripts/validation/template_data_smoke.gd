extends SceneTree

const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")

const TEMPLATE_DIR: String = "res://data/procgen/templates/"
const EXPECTED_TEMPLATES: Array[String] = ["spine", "bifurcated", "stacked"]

func _initialize() -> void:
	for template_id in EXPECTED_TEMPLATES:
		var path: String = TEMPLATE_DIR + template_id + ".json"
		var abs_path: String = ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(abs_path):
			push_error("TEMPLATE DATA FAIL file not found: %s" % abs_path)
			quit(1)
			return

		var text: String = FileAccess.get_file_as_string(abs_path)
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			push_error("TEMPLATE DATA FAIL invalid JSON: %s" % path)
			quit(1)
			return

		var template: TopologyTemplateScript = TopologyTemplateScript.from_dict(parsed)
		if template == null:
			push_error("TEMPLATE DATA FAIL from_dict returned null: %s" % template_id)
			quit(1)
			return

		if template.id != template_id:
			push_error("TEMPLATE DATA FAIL id=%s expected=%s" % [template.id, template_id])
			quit(1)
			return

		if template.zones.is_empty():
			push_error("TEMPLATE DATA FAIL %s has no zones" % template_id)
			quit(1)
			return

		if template.connections.is_empty():
			push_error("TEMPLATE DATA FAIL %s has no connections" % template_id)
			quit(1)
			return

		# Every template must have an entry zone
		var entry_zone: Dictionary = template.get_zone("entry")
		if entry_zone.is_empty():
			push_error("TEMPLATE DATA FAIL %s missing entry zone" % template_id)
			quit(1)
			return

		# Every template must have a destination zone
		var dest_zone: Dictionary = template.get_zone("destination")
		if dest_zone.is_empty():
			push_error("TEMPLATE DATA FAIL %s missing destination zone" % template_id)
			quit(1)
			return

	# Stacked template must require 2 decks
	var stacked_text: String = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path(TEMPLATE_DIR + "stacked.json"))
	var stacked_data: Variant = JSON.parse_string(stacked_text)
	var stacked: TopologyTemplateScript = TopologyTemplateScript.from_dict(stacked_data)
	if stacked.deck_config.get("max_decks", 0) != 2:
		push_error("TEMPLATE DATA FAIL stacked max_decks=%s expected=2" % str(stacked.deck_config.get("max_decks", 0)))
		quit(1)
		return

	print("TEMPLATE DATA PASS templates=%d all_valid=true" % EXPECTED_TEMPLATES.size())
	quit(0)
