extends RefCounted
class_name TooltipSchema
## Static validation for `TooltipPresenter` catalogs (REQ-UI-004 / ADR-0033).
##
## A tooltip catalog is a JSON document with the following shape:
##
##   {
##     "version": "tooltip-catalog-1",
##     "entries": [
##       {
##         "id": "interactable_circuit_board",
##         "subject_kind": "interactable",
##         "subject_id": "circuit_board",
##         "title": "Circuit Board",
##         "body": "Required to repair the junction.",
##         "footer": "[E] Pick up"
##       },
##       ...
##     ]
##   }
##
## The schema rejects:
##   - missing / non-Dictionary root
##   - wrong `version`
##   - non-Array `entries`
##   - entry missing any required field
##   - empty `subject_kind` / `subject_id` / `title`
##   - duplicate `id` across entries
##
## Unknown extra fields are ignored (forward-compat).

const SCHEMA_VERSION: String = "tooltip-catalog-1"

static func validate(catalog: Variant) -> bool:
	if catalog == null or typeof(catalog) != TYPE_DICTIONARY:
		push_error("TooltipSchema: catalog must be a Dictionary; got %s" % typeof(catalog))
		return false
	var dict: Dictionary = catalog
	if str(dict.get("version", "")) != SCHEMA_VERSION:
		push_error("TooltipSchema: version mismatch (expected %s)" % SCHEMA_VERSION)
		return false
	var entries_variant: Variant = dict.get("entries", null)
	if typeof(entries_variant) != TYPE_ARRAY:
		push_error("TooltipSchema: 'entries' must be an Array")
		return false
	var entries: Array = entries_variant
	var seen_ids: Dictionary = {}
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("TooltipSchema: entry must be a Dictionary")
			return false
		var entry_dict: Dictionary = entry
		var id_str: String = str(entry_dict.get("id", ""))
		if id_str.is_empty():
			push_error("TooltipSchema: entry missing 'id'")
			return false
		if seen_ids.has(id_str):
			push_error("TooltipSchema: duplicate entry id '%s'" % id_str)
			return false
		seen_ids[id_str] = true
		var subject_kind: String = str(entry_dict.get("subject_kind", ""))
		if subject_kind.is_empty():
			push_error("TooltipSchema: entry '%s' missing 'subject_kind'" % id_str)
			return false
		var subject_id: String = str(entry_dict.get("subject_id", ""))
		if subject_id.is_empty():
			push_error("TooltipSchema: entry '%s' missing 'subject_id'" % id_str)
			return false
		var title: String = str(entry_dict.get("title", ""))
		if title.is_empty():
			push_error("TooltipSchema: entry '%s' missing 'title'" % id_str)
			return false
		# body / footer are optional; default to empty strings.
	return true