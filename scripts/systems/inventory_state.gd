extends RefCounted
class_name InventoryState

## Runtime model for the Gate 2 inventory/tool loop.
## This model never reaches into the scene tree. PlayableGeneratedShip owns
## the tool pickup scene node and applies scene consequences from this summary.

const DEFAULT_TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"

var tool_ids: Array[String] = []
var _definitions: Dictionary = {}

func _init() -> void:
	_load_definitions(DEFAULT_TOOL_DEFINITIONS_PATH)

func _load_definitions(path: String) -> void:
	_definitions.clear()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_definitions = parsed

func add_tool(tool_id: String) -> bool:
	if tool_id.is_empty():
		return false
	if tool_ids.has(tool_id):
		return false
	tool_ids.append(tool_id)
	return true

func has_tool(tool_id: String) -> bool:
	return tool_ids.has(tool_id)

func remove_tool(tool_id: String) -> bool:
	var index := tool_ids.find(tool_id)
	if index < 0:
		return false
	tool_ids.remove_at(index)
	return true

func reset() -> void:
	tool_ids.clear()
	# Reload tool definitions so a fresh inventory on a reset slice can
	# still resolve display names / effects.
	_load_definitions(DEFAULT_TOOL_DEFINITIONS_PATH)

## REQ-012: restore this model from a summary dictionary matching
## get_summary()'s shape. Unknown tool ids are added but have no effect
## (the live drain multiplier and the dictionary effects look up by id,
## so unknown ids round-trip without breaking the carrier math). Returns
## true if any field changed.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_tool_ids_variant: Variant = summary.get("tool_ids", tool_ids)
	if typeof(new_tool_ids_variant) == TYPE_ARRAY:
		var new_tool_ids: Array[String] = []
		for tool_id in (new_tool_ids_variant as Array):
			new_tool_ids.append(String(tool_id))
		if new_tool_ids != tool_ids:
			tool_ids = new_tool_ids
			changed = true
	# `active_effects` and `drain_multiplier` are derived from tool_ids +
	# the definitions cache; restoring tool_ids above is sufficient to
	# re-derive both. We intentionally do not accept hand-edited
	# effect/multiplier overrides here so the carrier math remains
	# canonical.
	return changed

## Returns the current effective oxygen drain multiplier implied by the
## carried tools. REQ-007: 0.5 when portable_oxygen_pump is carried, 1.0
## otherwise. The value mirrors what OxygenState._compute_drain_multiplier
## computes from the inventory summary so callers can ask the inventory
## model directly without instantiating OxygenState.
func get_drain_multiplier() -> float:
	if tool_ids.has("portable_oxygen_pump"):
		return 0.5
	return 1.0

func get_definition(tool_id: String) -> Dictionary:
	var def: Variant = _definitions.get(tool_id, {})
	if def is Dictionary:
		return def
	return {}

func get_display_name(tool_id: String) -> String:
	var def := get_definition(tool_id)
	var name: String = str(def.get("display_name", ""))
	if name.is_empty():
		return tool_id.replace("_", " ").capitalize()
	return name

func get_summary() -> Dictionary:
	var effects: Array[Dictionary] = []
	for tool_id in tool_ids:
		var def := get_definition(tool_id)
		var effect: Variant = def.get("effect", {})
		if effect is Dictionary:
			effects.append({
				"tool_id": tool_id,
				"type": str(effect.get("type", "")),
				"value": effect.get("value", 1.0),
			})
	# Drain multiplier is the canonical value OxygenState consumes each
	# tick. InventoryState owns the calculation; OxygenState never re-derives
	# it. See REQ-007 and the inventory_tools spec.
	var drain_multiplier: float = get_drain_multiplier()
	return {
		"tool_ids": tool_ids.duplicate(),
		"active_effects": effects,
		"drain_multiplier": drain_multiplier,
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for tool_id in tool_ids:
		lines.append("Tool: %s" % get_display_name(tool_id))
		# REQ-007 / HUD visibility: also surface the carried tool id and its
		# effective drain multiplier as key=value lines so the status output
		# the main-scene smoke inspects carries the literal markers
		# `tool=<id>` and `drain_multiplier=<value>`. These are appended only
		# while the tool is present, so a fresh load with no tool produces
		# no such lines.
		lines.append("tool=%s" % tool_id)
		var multiplier: float = get_drain_multiplier()
		if tool_id == "portable_oxygen_pump" and multiplier != 1.0:
			lines.append("drain_multiplier=%s" % str(multiplier))
	return lines