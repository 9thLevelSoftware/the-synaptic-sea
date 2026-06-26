extends RefCounted
class_name SaveLoadMenu

## Save/Load menu UI seam (ADR-0031, REQ-SL-011).
##
## Pure seam. Reads `SaveLoadService.list_slots()` and exposes rows for
## a menu / pause-overlay UI. Headlessly testable because it never reads
## from the scene tree — the UI layer (a future `Control` node) just
## observes `refresh()` and dispatches user choices via `select_slot_for_load`.

var _service: Object = null

func bind(service: Object) -> void:
	_service = service

func refresh() -> Array:
	if _service == null:
		return []
	return _service.list_slots()

func select_slot_for_load(slot_id: String) -> Object:
	if _service == null:
		return null
	return _service.load_from_slot(slot_id)

func confirm_save_to_slot(slot_id: String, snapshot: RunSnapshot, slot_kind: String, display_name: String) -> bool:
	if _service == null:
		return false
	return _service.save_to_slot(slot_id, snapshot, slot_kind, false, display_name)

func confirm_quicksave(snapshot: RunSnapshot) -> bool:
	if _service == null:
		return false
	return _service.save_to_slot("quicksave", snapshot, "quick", true, "Quicksave")

func confirm_delete(slot_id: String) -> bool:
	if _service == null:
		return false
	return _service.delete_slot(slot_id)

## Convenience: returns one row for the active autosave (or null).
func active_autosave_row() -> Object:
	var rows: Array = refresh()
	for row in rows:
		if row != null and row.slot_id == "autosave_active":
			return row
	return null