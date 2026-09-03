extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")

const LAYOUT_PATH := "res://data/procgen/smoke/seed_000017/layout.json"
const GAMEPLAY_PATH := "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
const JSON_SAFE_MAX_DEPTH := 64


func _initialize() -> void:
	var blueprint = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		17,
	)
	var layout_generator = ShipLayoutGeneratorScript.new()
	var layout: Dictionary = layout_generator.generate_with_options(blueprint, {}, "", "", false)
	if layout.is_empty():
		_fail("layout generation returned empty")
		return

	# Authority is the generator-stamped plan. Do not recompile or overwrite it:
	# a second compile drops `validated=true` and reintroduces Vector3/Vector2i
	# values that JSON.stringify would emit as opaque strings.
	var stamped_variant: Variant = layout.get("structural_plan", null)
	if typeof(stamped_variant) != TYPE_DICTIONARY:
		_fail("generator did not stamp structural_plan")
		return
	var stamped: Dictionary = stamped_variant
	if not bool(stamped.get("validated", false)):
		_fail("stamped structural_plan missing validated=true")
		return
	if not bool(layout.get("structural_plan_validated", false)):
		_fail("layout missing structural_plan_validated=true")
		return

	var gameplay: Dictionary = GameplaySliceBuilderScript.new().build(layout)
	if gameplay.is_empty() or not (gameplay.get("objectives", []) is Array) or (gameplay.get("objectives", []) as Array).is_empty():
		_fail("gameplay slice returned no objectives")
		return
	var layout_arcs: Variant = layout.get("arc_zones", [])
	var slice_arcs: Variant = gameplay.get("arc_zones", [])
	if (not (layout_arcs is Array) or (layout_arcs as Array).is_empty()) and slice_arcs is Array and not (slice_arcs as Array).is_empty():
		layout["arc_zones"] = (slice_arcs as Array).duplicate(true)

	if not _write_json(LAYOUT_PATH, layout) or not _write_json(GAMEPLAY_PATH, gameplay):
		_fail("could not write refreshed fixture")
		return

	var plan: Dictionary = layout.get("structural_plan", {})
	if not bool(plan.get("validated", false)):
		_fail("normalized structural_plan lost validated=true")
		return
	print(
		"SEED 000017 FIXTURE REFRESH PASS schema=%s rooms=%d objectives=%d floors=%d ceilings=%d sockets=%d placements=%d"
		% [
			str(layout.get("schema_version", "")),
			(layout.get("rooms", []) as Array).size(),
			(gameplay.get("objectives", []) as Array).size(),
			(plan.get("floor_placements", []) as Array).size(),
			(plan.get("ceiling_placements", []) as Array).size(),
			(plan.get("socket_bindings", []) as Array).size(),
			(plan.get("placements", []) as Array).size(),
		]
	)
	quit(0)


func _write_json(path: String, value: Dictionary) -> bool:
	var normalized: Dictionary = _json_safe(value, 0)
	if not bool(normalized.get("ok", false)):
		push_error("SEED 000017 FIXTURE REFRESH FAIL json-safe: %s" % str(normalized.get("error", "unknown")))
		return false
	var payload_variant: Variant = normalized.get("value", null)
	if typeof(payload_variant) != TYPE_DICTIONARY:
		push_error("SEED 000017 FIXTURE REFRESH FAIL json-safe produced non-object")
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload_variant, "  "))
	file.close()
	return true


func _json_safe(value: Variant, depth: int) -> Dictionary:
	if depth > JSON_SAFE_MAX_DEPTH:
		return {"ok": false, "error": "json-safe depth exceeded"}
	var value_type: int = typeof(value)
	match value_type:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return {"ok": true, "value": value}
		TYPE_FLOAT:
			if not is_finite(float(value)):
				return {"ok": false, "error": "nonfinite float"}
			return {"ok": true, "value": value}
		TYPE_VECTOR2:
			var vector2: Vector2 = value
			if not is_finite(vector2.x) or not is_finite(vector2.y):
				return {"ok": false, "error": "nonfinite Vector2"}
			return {"ok": true, "value": [vector2.x, vector2.y]}
		TYPE_VECTOR2I:
			var cell: Vector2i = value
			return {"ok": true, "value": [cell.x, cell.y]}
		TYPE_VECTOR3:
			var vector3: Vector3 = value
			if not is_finite(vector3.x) or not is_finite(vector3.y) or not is_finite(vector3.z):
				return {"ok": false, "error": "nonfinite Vector3"}
			return {"ok": true, "value": [vector3.x, vector3.y, vector3.z]}
		TYPE_ARRAY:
			var array_out: Array = []
			for child in value:
				var child_result: Dictionary = _json_safe(child, depth + 1)
				if not bool(child_result.get("ok", false)):
					return child_result
				array_out.append(child_result.get("value", null))
			return {"ok": true, "value": array_out}
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var dictionary_out: Dictionary = {}
			for key_variant in source.keys():
				var key_type: int = typeof(key_variant)
				var key_text: String = ""
				if key_type == TYPE_STRING:
					key_text = String(key_variant)
				elif key_type == TYPE_INT:
					key_text = str(int(key_variant))
				else:
					return {"ok": false, "error": "unsupported dict key type=%d" % key_type}
				var child_result: Dictionary = _json_safe(source[key_variant], depth + 1)
				if not bool(child_result.get("ok", false)):
					return child_result
				dictionary_out[key_text] = child_result.get("value", null)
			return {"ok": true, "value": dictionary_out}
		_:
			return {"ok": false, "error": "unsupported type=%d" % value_type}


func _fail(reason: String) -> void:
	push_error("SEED 000017 FIXTURE REFRESH FAIL reason=%s" % reason)
	quit(1)
