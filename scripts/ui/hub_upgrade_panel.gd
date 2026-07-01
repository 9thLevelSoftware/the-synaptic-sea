extends Control
class_name HubUpgradePanel

## REQ-PM-007 / REQ-PM-010 / ADR-0033 hub upgrade panel UI.
##
## Renders every upgrade in `data/player/hub_upgrades.json` with cost,
## prerequisites, ownership state, and affordability. Reads from
## `HubUpgradeState` + `MetaProgressionState`. The panel does not own
## the meta state; the playable ship's coordinator calls
## `HubUpgradeState.purchase(upgrade_id, meta_state)` on a confirmed
## purchase, then re-renders.

const HubUpgradeStateScript := preload("res://scripts/systems/hub_upgrade_state.gd")

var _catalog = null
var _meta_state = null
var _list_label: RichTextLabel = null
var _selected_index: int = 0

func _ready() -> void:
	_list_label = RichTextLabel.new()
	_list_label.name = "HubUpgradeList"
	_list_label.bbcode_enabled = true
	_list_label.fit_content = true
	add_child(_list_label)

func set_catalog(catalog) -> void:
	_catalog = catalog

func set_meta_state(meta_state) -> void:
	_meta_state = meta_state

func get_catalog_panel():
	return _catalog

func get_meta_state_panel():
	return _meta_state

func get_upgrade_count() -> int:
	if _catalog == null:
		return 0
	return _catalog.get_upgrade_count()

func get_owned_count() -> int:
	if _catalog == null or _meta_state == null:
		return 0
	var n: int = 0
	for uid in _catalog.get_upgrade_ids():
		if _meta_state.is_hub_upgrade_unlocked(uid):
			n += 1
	return n

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if _catalog == null:
		lines.append("Hub Upgrades: (catalog uninitialized)")
		return lines
	var owned: int = get_owned_count()
	var currency: int = 0
	if _meta_state != null and _meta_state.has_method("get_meta_currency"):
		currency = int(_meta_state.get_meta_currency())
	lines.append("Hub Upgrades: %d / %d owned  Currency: %d" % [owned, _catalog.get_upgrade_count(), currency])
	var idx: int = 0
	for entry in _catalog.get_upgrade_entries(_meta_state):
		var uid: String = str(entry.get("upgrade_id", ""))
		var display: String = str(entry.get("display_name", uid))
		var cost: int = int(entry.get("cost", 0))
		var prereqs: Array = entry.get("requires", []) as Array
		var owned_e: bool = bool(entry.get("owned", false))
		var affordable: bool = bool(entry.get("affordable", false))
		var marker: String = "[X]" if owned_e else ("[$]" if affordable else "[ ]")
		var cursor: String = ">" if idx == _selected_index else " "
		var prereq_str: String = "  req=%s" % ",".join(prereqs) if not prereqs.is_empty() else ""
		lines.append("%s%s %s cost=%d%s" % [cursor, marker, display, cost, prereq_str])
		idx += 1
	return lines

func render() -> void:
	if _list_label == null:
		return
	var lines: PackedStringArray = get_status_lines()
	var bb: String = ""
	for line in lines:
		bb += String(line) + "\n"
	_list_label.text = bb

## Domain 6 host/input seam: moves the selection cursor by `direction` rows
## (typically -1/+1), clamped to the current upgrade-entry list bounds.
func move_selection(direction: int) -> void:
	var n: int = _catalog.get_upgrade_entries(_meta_state).size() if _catalog != null else 0
	if n <= 0:
		_selected_index = 0
		return
	_selected_index = clampi(_selected_index + direction, 0, n - 1)

## Returns the upgrade_id at the cursor (in `get_upgrade_entries()` order),
## or "" when the catalog is uninitialized or the cursor is out of bounds.
func get_selected_id() -> String:
	if _catalog == null:
		return ""
	var entries: Array = _catalog.get_upgrade_entries(_meta_state)
	if _selected_index < 0 or _selected_index >= entries.size():
		return ""
	return str((entries[_selected_index] as Dictionary).get("upgrade_id", ""))

## Static factory used by the smoke: loads the catalog from disk and
## wires the supplied meta state (which the caller is expected to load).
static func build_default(meta_state):
	var catalog := HubUpgradeStateScript.new()
	catalog.configure()
	var panel = load("res://scripts/ui/hub_upgrade_panel.gd").new()
	panel.set_catalog(catalog)
	panel.set_meta_state(meta_state)
	return panel