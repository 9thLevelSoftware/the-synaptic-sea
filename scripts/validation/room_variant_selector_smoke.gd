extends SceneTree

# room_variant_selector_smoke — REQ-PG-001, REQ-PG-002, REQ-PG-011.
#
# Asserts:
#   1. RoomVariantSelector.pick("airlock", 0, 42) returns a
#      non-empty variant string from the registered variant list.
#   2. Same (role, room_index, seed) always returns the same variant
#      (determinism).
#   3. Different room_index values can produce different variants
#      for the same role + seed.
#   4. Different seeds can produce different variants for the same
#      role + room_index.
#   5. Unknown role falls back to a stable string (does not crash).
#   6. variants_for_role("airlock") returns >= 4 distinct variants
#      (REQ-PG-002 acceptance criterion).
#   7. TemplateSelector.select_with_options returns a valid template
#      from the extended set; AVAIABLE_TEMPLATES >= 6 (REQ-PG-011).
#   8. Same seed selects the same template id from the extended set.
#   9. The non-extended select() still returns one of the legacy
#      three templates (backward compat).

const RoomVariantSelectorScript := preload("res://scripts/procgen/room_variant_selector.gd")
const TemplateSelectorScript := preload("res://scripts/procgen/template_selector.gd")


func _initialize() -> void:
	var selector: RefCounted = RoomVariantSelectorScript.new()

	# --- Case 1: pick returns non-empty for airlock ---
	var variant_a: String = String(selector.pick("airlock", 0, 42))
	if variant_a.is_empty():
		push_error("ROOM VARIANT SELECTOR FAIL pick(airlock, 0, 42) empty")
		quit(1)
		return

	# --- Case 2: determinism for same inputs ---
	var variant_a2: String = String(selector.pick("airlock", 0, 42))
	if variant_a != variant_a2:
		push_error("ROOM VARIANT SELECTOR FAIL not stable: %s vs %s" % [variant_a, variant_a2])
		quit(1)
		return

	# --- Case 3: Different room_index can yield different variants ---
	var seen_variants: Dictionary = {}
	for i in range(8):
		var v: String = String(selector.pick("corridor", i, 12345))
		seen_variants[v] = true
	if seen_variants.size() < 2:
		push_error("ROOM VARIANT SELECTOR FAIL only %d distinct variants for corridor across 8 rooms" % seen_variants.size())
		quit(1)
		return

	# --- Case 4: Different seeds can yield different variants ---
	var seen_seeds: Dictionary = {}
	for s in range(10):
		var v: String = String(selector.pick("corridor", 0, s * 137))
		seen_seeds[v] = true
	if seen_seeds.size() < 2:
		push_error("ROOM VARIANT SELECTOR FAIL only %d distinct variants for corridor across 10 seeds" % seen_seeds.size())
		quit(1)
		return

	# --- Case 5: Unknown role falls back deterministically ---
	var unknown_a: String = String(selector.pick("totally_made_up_role", 0, 42))
	var unknown_b: String = String(selector.pick("totally_made_up_role", 0, 42))
	if unknown_a.is_empty():
		push_error("ROOM VARIANT SELECTOR FAIL unknown role returned empty")
		quit(1)
		return
	if unknown_a != unknown_b:
		push_error("ROOM VARIANT SELECTOR FAIL unknown role not stable: %s vs %s" % [unknown_a, unknown_b])
		quit(1)
		return
	# Empty role also safe.
	var empty_role: String = String(selector.pick("", 0, 42))
	if empty_role.is_empty():
		push_error("ROOM VARIANT SELECTOR FAIL empty role returned empty")
		quit(1)
		return

	# --- Case 6: variants_for_role returns >= 4 variants for airlock ---
	var airlock_variants: Array[String] = selector.variants_for_role("airlock")
	if airlock_variants.size() < 4:
		push_error("ROOM VARIANT SELECTOR FAIL airlock variants=%d expected>=4" % airlock_variants.size())
		quit(1)
		return
	# And corridor
	var corridor_variants: Array[String] = selector.variants_for_role("corridor")
	if corridor_variants.size() < 4:
		push_error("ROOM VARIANT SELECTOR FAIL corridor variants=%d expected>=4" % corridor_variants.size())
		quit(1)
		return

	# --- Case 7: TemplateSelector extended set has >= 6 templates ---
	var template_sel: RefCounted = TemplateSelectorScript.new()
	var extended_set: Array[String] = template_sel.available_templates(false, true)
	if extended_set.size() < 6:
		push_error("ROOM VARIANT SELECTOR FAIL extended templates=%d expected>=6" % extended_set.size())
		quit(1)
		return

	# --- Case 8: select_with_options returns a valid template id ---
	var ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
	var bp: RefCounted = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		314)
	var template: RefCounted = template_sel.select_with_options(
		bp, {}, false, true)
	if template == null:
		push_error("ROOM VARIANT SELECTOR FAIL select_with_options returned null")
		quit(1)
		return
	var template_id: String = str(template.id)
	if not extended_set.has(template_id):
		push_error("ROOM VARIANT SELECTOR FAIL template id %s not in extended set" % template_id)
		quit(1)
		return

	# Determinism for select_with_options.
	var template_again: RefCounted = template_sel.select_with_options(
		bp, {}, false, true)
	if template_again == null or str(template_again.id) != template_id:
		push_error("ROOM VARIANT SELECTOR FAIL select_with_options not deterministic: %s vs %s" % [
			template_id, "n/a" if template_again == null else str(template_again.id)])
		quit(1)
		return

	# --- Case 9: Legacy select() still returns one of three templates ---
	var legacy_set: Array[String] = template_sel.available_templates(false, false)
	if legacy_set.size() != 3:
		push_error("ROOM VARIANT SELECTOR FAIL legacy templates=%d expected=3" % legacy_set.size())
		quit(1)
		return
	var legacy_template: RefCounted = template_sel.select(bp, {})
	if legacy_template == null:
		push_error("ROOM VARIANT SELECTOR FAIL legacy select returned null")
		quit(1)
		return
	if not legacy_set.has(str(legacy_template.id)):
		push_error("ROOM VARIANT SELECTOR FAIL legacy id %s not in legacy set" % str(legacy_template.id))
		quit(1)
		return

	print("ROOM VARIANT SELECTOR PASS distinct_per_index=%d distinct_per_seed=%d airlock_variants=%d corridor_variants=%d extended=%d legacy=3 deterministic=true" % [
		seen_variants.size(), seen_seeds.size(),
		airlock_variants.size(), corridor_variants.size(),
		extended_set.size(),
	])
	quit(0)
