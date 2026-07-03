extends RefCounted
class_name WebChartState
## Domain 10 (ADR-0045): session-only record of ship-marker knowledge the
## player has recorded onto their web chart. Two callers merge views in:
## found `web_chart` items (detail 2, "paper map" import) and scanner scans
## performed while a chart is possessed (detail 1-6, ScannerState.scan()'s
## own detail_level). No get_summary/apply_summary/SAVE_KEY -- deliberately
## ephemeral (ADR-0045), not a dead unused seam like TooltipPresenter's.
##
## Pure-model-first: no scene-tree access.

const REQUIRED_FIELDS: Array[String] = ["marker_id", "position", "size_class"]
const DETAIL_GATED_FIELDS: Array[String] = ["ship_type", "condition", "predicted_status", "predicted_offline", "loot_hint"]

var _entries: Dictionary = {}   # marker_id -> {position, size_class, detail, ...detail-gated fields}

## Merges `views` (an Array of scan()/chart view Dictionaries, the same shape
## ScannerState._marker_view() returns) into the chart at `detail_level`.
## Per marker: detail is max(existing.detail, detail_level) (never downgrades);
## fields present at the new detail are unioned in. Malformed views (missing
## a required field, non-Dictionary) are skipped, not rejected wholesale.
## Returns the count of markers that were newly added or had their detail
## upgraded (equal-or-lower detail on an already-known marker is a no-op and
## does not count).
func record_views(views: Array, detail_level: int) -> int:
	var changed: int = 0
	for view_variant in views:
		if typeof(view_variant) != TYPE_DICTIONARY:
			continue
		var view: Dictionary = view_variant
		var ok: bool = true
		for field in REQUIRED_FIELDS:
			if not view.has(field):
				ok = false
				break
		if not ok:
			continue
		var marker_id: String = str(view.get("marker_id", ""))
		if marker_id.is_empty():
			continue
		var existing: Dictionary = _entries.get(marker_id, {})
		var existing_detail: int = int(existing.get("detail", 0))
		if detail_level <= existing_detail and _entries.has(marker_id):
			continue   # no upgrade, no-op (idempotent re-record)
		var merged: Dictionary = existing.duplicate(true)
		merged["position"] = (view.get("position", []) as Array).duplicate()
		merged["size_class"] = int(view.get("size_class", 0))
		merged["detail"] = maxi(existing_detail, detail_level)
		for field in DETAIL_GATED_FIELDS:
			if view.has(field):
				merged[field] = view[field]
		_entries[marker_id] = merged
		changed += 1
	return changed

func get_known_marker_ids() -> Array:
	var ids: Array = _entries.keys()
	ids.sort()
	return ids

func get_entry(marker_id: String) -> Dictionary:
	var entry: Variant = _entries.get(marker_id, {})
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}

func get_known_count() -> int:
	return _entries.size()

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("WebChartState: known=%d" % _entries.size())
	return lines
