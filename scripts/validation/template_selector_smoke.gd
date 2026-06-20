extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")
const TemplateSelectorScript := preload("res://scripts/procgen/template_selector.gd")

func _initialize() -> void:
	var selector: TemplateSelectorScript = TemplateSelectorScript.new()

	# --- Case 1: explicit template in archetype ---
	var bp1: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)
	var archetype1: Dictionary = {"template": "spine"}
	var template1: TopologyTemplateScript = selector.select(bp1, archetype1)
	if template1 == null:
		push_error("TEMPLATE SELECTOR FAIL explicit spine returned null")
		quit(1)
		return
	if template1.id != "spine":
		push_error("TEMPLATE SELECTOR FAIL explicit spine id=%s" % template1.id)
		quit(1)
		return

	# --- Case 2: explicit stacked ---
	var archetype2: Dictionary = {"template": "stacked"}
	var template2: TopologyTemplateScript = selector.select(bp1, archetype2)
	if template2 == null or template2.id != "stacked":
		push_error("TEMPLATE SELECTOR FAIL explicit stacked id=%s" % str(template2))
		quit(1)
		return

	# --- Case 3: seed-based selection is deterministic ---
	var bp3: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 777)
	var t3a: TopologyTemplateScript = selector.select(bp3, {})
	var t3b: TopologyTemplateScript = selector.select(bp3, {})
	if t3a.id != t3b.id:
		push_error("TEMPLATE SELECTOR FAIL determinism a=%s b=%s" % [t3a.id, t3b.id])
		quit(1)
		return

	# --- Case 4: different seeds can produce different templates ---
	var seen_ids: Dictionary = {}
	for seed_val in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		var bp: ShipBlueprintScript = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, seed_val)
		var t: TopologyTemplateScript = selector.select(bp, {})
		if t == null:
			push_error("TEMPLATE SELECTOR FAIL seed %d returned null" % seed_val)
			quit(1)
			return
		seen_ids[t.id] = true
	if seen_ids.size() < 2:
		push_error("TEMPLATE SELECTOR FAIL 10 seeds all produced same template (rng not exercised)")
		quit(1)
		return

	print("TEMPLATE SELECTOR PASS explicit=true deterministic=true varied=true")
	quit(0)
