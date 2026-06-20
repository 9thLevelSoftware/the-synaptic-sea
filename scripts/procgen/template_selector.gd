extends RefCounted
class_name TemplateSelector

# Picks a TopologyTemplate based on archetype, blueprint size, and seed.
# If the archetype specifies a "template" key, that template is loaded
# directly. Otherwise, the selector picks from available templates using
# the blueprint's seed as the RNG source.

const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")

const TEMPLATE_DIR: String = "res://data/procgen/templates/"
const AVAILABLE_TEMPLATES: Array[String] = ["spine", "bifurcated", "stacked"]


func select(blueprint: RefCounted, archetype: Dictionary) -> RefCounted:
	var template_id: String = str(archetype.get("template", ""))

	if template_id.is_empty():
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = int(blueprint.seed_value)
		var idx: int = rng.randi_range(0, AVAILABLE_TEMPLATES.size() - 1)
		template_id = AVAILABLE_TEMPLATES[idx]

	return _load_template(template_id)


func _load_template(template_id: String) -> RefCounted:
	var path: String = TEMPLATE_DIR + template_id + ".json"
	var abs_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		push_error("TEMPLATE SELECTOR FAIL template file not found: %s" % abs_path)
		return null

	var text: String = FileAccess.get_file_as_string(abs_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("TEMPLATE SELECTOR FAIL invalid JSON: %s" % path)
		return null

	return TopologyTemplateScript.from_dict(parsed)
