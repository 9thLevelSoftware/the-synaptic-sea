extends RefCounted
class_name TemplateSelector

# Picks a TopologyTemplate based on archetype, blueprint size, and seed.
# If the archetype specifies a "template" key, that template is loaded
# directly. Otherwise, the selector picks from available templates using
# the blueprint's seed as the RNG source.
#
# Expanded set in Task 12 package (REQs PG-001, PG-011). The legacy
# three-template set is preserved under the same `spine/bifurcated/stacked`
# ids; five new variants are added for the content-complete target.
# Use `select_with_options(blueprint, archetype, include_derelict, extended)`
# to opt into the full eight-template set explicitly. The default
# `select(...)` keeps the legacy three to preserve existing smoke contracts.

const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")

const TEMPLATE_DIR: String = "res://data/procgen/templates/"
const AVAILABLE_TEMPLATES: Array[String] = ["spine", "bifurcated", "stacked"]
## PKG-D5.4: full catalog toward 12–15 templates (legacy three preserved).
const EXTENDED_TEMPLATES: Array[String] = [
	"spine", "bifurcated", "stacked",
	"stacked_v2", "compact", "dispersed",
	"derelict_a", "derelict_b",
	"ring", "radial", "double_spine", "hangar_wing", "vault",
]
const DERELICT_TEMPLATES: Array[String] = ["derelict_a", "derelict_b"]
const WRECK_TEMPLATES: Array[String] = ["derelict_a", "derelict_b", "vault"]


func select(blueprint: RefCounted, archetype: Dictionary) -> RefCounted:
	var template_id: String = str(archetype.get("template", ""))

	if template_id.is_empty():
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = int(blueprint.seed_value)
		var idx: int = rng.randi_range(0, AVAILABLE_TEMPLATES.size() - 1)
		template_id = AVAILABLE_TEMPLATES[idx]

	return _load_template(template_id)


# Extended selector. When `include_derelict` is true the derelict_*
# templates are eligible; when `extended` is true the five new
# variants (stacked_v2, compact, dispersed, plus the two derelicts)
# are added to the pool. Both flags default to false to preserve
# the legacy three-template contract used by Phase 1 smokes.
func select_with_options(
		blueprint: RefCounted,
		archetype: Dictionary,
		include_derelict: bool = false,
		extended: bool = false) -> RefCounted:
	var template_id: String = str(archetype.get("template", ""))
	if not template_id.is_empty():
		return _load_template(template_id)

	var pool: Array[String] = AVAILABLE_TEMPLATES.duplicate()
	if extended:
		for t in EXTENDED_TEMPLATES:
			if not pool.has(t):
				pool.append(t)
	elif include_derelict:
		for t in DERELICT_TEMPLATES:
			if not pool.has(t):
				pool.append(t)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(blueprint.seed_value)
	var idx: int = rng.randi_range(0, pool.size() - 1)
	return _load_template(pool[idx])


# Returns a copy of the registered template ids for the given
# inclusion options. Used by smokes that need to enumerate the
# selectable set without spinning up the pipeline.
func available_templates(include_derelict: bool = false, extended: bool = false) -> Array[String]:
	var pool: Array[String] = AVAILABLE_TEMPLATES.duplicate()
	if extended:
		for t in EXTENDED_TEMPLATES:
			if not pool.has(t):
				pool.append(t)
	elif include_derelict:
		for t in DERELICT_TEMPLATES:
			if not pool.has(t):
				pool.append(t)
	return pool


## PKG-D5.4: count of JSON templates on disk under TEMPLATE_DIR.
func catalog_size_on_disk() -> int:
	var n: int = 0
	for tid in EXTENDED_TEMPLATES:
		var path: String = TEMPLATE_DIR + tid + ".json"
		if FileAccess.file_exists(ProjectSettings.globalize_path(path)):
			n += 1
	return n


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
