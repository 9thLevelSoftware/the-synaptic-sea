extends RefCounted
class_name TooltipPresenter
## Pure tooltip query → payload resolver (REQ-UI-004 / ADR-0033).
##
## Owns a catalog of `{subject_kind, subject_id}` → `{title, body,
## footer}` mappings. `resolve(query)` returns a `TooltipPayload` or
## `null` for unknown ids. The catalog is the only source of truth;
## unknown ids are rejected, never silently mapped to a default.
##
## The presenter is headless-queryable: scenes subscribe to the
## `payload_changed` signal, but the resolver works without it. The
## `TooltipPanel` reads the payload and renders.
##
## Pure-model-first: no scene-tree access.

signal payload_changed(payload)

const TooltipPayloadScript := preload("res://scripts/systems/tooltip_payload.gd")
const TooltipSchemaScript := preload("res://scripts/schemas/tooltip_schema.gd")

const SCHEMA_VERSION: String = "tooltip-presenter-1"
const SAVE_KEY: String = "tooltip_presenter"

var _entries_by_kind: Dictionary = {}    # subject_kind -> {subject_id -> entry_dict}
var _entries_by_id: Dictionary = {}      # entry_id -> entry_dict
var _current_payload: Variant = null     # last-resolved TooltipPayload (or null)
var _last_query: Dictionary = {}         # last query dict for the summary

func configure(catalog: Dictionary) -> bool:
	if not TooltipSchemaScript.validate(catalog):
		return false
	_entries_by_kind.clear()
	_entries_by_id.clear()
	for entry in ((catalog as Dictionary).get("entries", []) as Array):
		var entry_dict: Dictionary = entry
		var kind: String = str(entry_dict.get("subject_kind", ""))
		var id_str: String = str(entry_dict.get("subject_id", ""))
		if not _entries_by_kind.has(kind):
			_entries_by_kind[kind] = {}
		(_entries_by_kind[kind] as Dictionary)[id_str] = entry_dict
		_entries_by_id[str(entry_dict.get("id", ""))] = entry_dict
	_current_payload = null
	_last_query = {}
	return true

## Resolve a tooltip query. `query` is a Dictionary with at least
## `subject_kind` and `subject_id`. Returns `null` for unknown ids or
## malformed queries. Emits `payload_changed` when the resolved
## payload differs from the previous one (so the panel can hide on a
## `null` result without bookkeeping).
func resolve(query: Dictionary) -> Variant:
	if query == null or typeof(query) != TYPE_DICTIONARY:
		_set_payload(null, query if typeof(query) == TYPE_DICTIONARY else {})
		return null
	var kind: String = str(query.get("subject_kind", ""))
	var id_str: String = str(query.get("subject_id", ""))
	if kind.is_empty() or id_str.is_empty():
		_set_payload(null, query)
		return null
	if not _entries_by_kind.has(kind):
		_set_payload(null, query)
		return null
	var kind_map: Dictionary = _entries_by_kind[kind]
	if not kind_map.has(id_str):
		_set_payload(null, query)
		return null
	var entry: Dictionary = kind_map[id_str]
	var payload := TooltipPayloadScript.new(
		str(entry.get("title", "")),
		str(entry.get("body", "")),
		str(entry.get("footer", "")),
		kind,
		id_str,
	)
	_set_payload(payload, query)
	return payload

## Returns the current payload (TooltipPayload or null). Used by
## TooltipPanel after subscribing to `payload_changed`.
func get_current_payload() -> Variant:
	return _current_payload

## Number of registered catalog entries.
func get_catalog_size() -> int:
	return _entries_by_id.size()

## Get the list of registered (kind, id) pairs sorted lexicographically.
func get_catalog_pairs() -> Array:
	var pairs: Array = []
	for kind in _entries_by_kind.keys():
		for id_str in (_entries_by_kind[kind] as Dictionary).keys():
			pairs.append("%s/%s" % [String(kind), String(id_str)])
	pairs.sort()
	return pairs

## Headless round-trip seam for the save/load smoke.
func get_summary() -> Dictionary:
	var payload_dict: Variant = null
	if _current_payload != null:
		payload_dict = _current_payload.to_dict() if _current_payload.has_method("to_dict") else null
	return {
		"schema": SCHEMA_VERSION,
		"catalog_size": _entries_by_id.size(),
		"has_payload": _current_payload != null,
		"payload": payload_dict,
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("TooltipPresenter: catalog=%d current=%s" % [
		_entries_by_id.size(),
		"present" if _current_payload != null else "none",
	])
	return lines

func _set_payload(payload, query: Dictionary) -> void:
	_current_payload = payload
	_last_query = query.duplicate(true)
	emit_signal("payload_changed", payload)