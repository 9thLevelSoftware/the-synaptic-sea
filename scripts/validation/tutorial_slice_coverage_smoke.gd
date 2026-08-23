extends SceneTree
## Task 2.1: vertical-slice tutorial catalog and production emitter coverage.
## Marker: TUTORIAL SLICE COVERAGE PASS

const TutorialStateScript := preload("res://scripts/systems/tutorial_state.gd")

const CATALOG_PATH: String = "res://data/ui/tutorial_triggers.json"
const CODEX_PATH: String = "res://data/ui/codex_entries.json"
const PLAYABLE_PATH: String = "res://scripts/procgen/playable_generated_ship.gd"

const REQUIRED_TUTORIAL_IDS: Array[String] = [
	"first_move",
	"first_interact",
	"first_inventory_open",
	"first_low_oxygen",
	"first_hazard",
	"first_breach",
	"first_threat_spotted",
	"first_loot_search",
	"first_scanner_open",
	"first_travel",
	"first_save",
	"first_death",
]

const REQUIRED_EMITTER_EVENTS: Array[String] = [
	"player_moved",
	"player_interacted",
	"inventory_opened",
	"vitals_warning",
	"hazard_entered",
	"breach_sealed",
	"threat_spotted",
	"loot_searched",
	"scanner_opened",
	"ship_traveled",
	"run_saved",
	"run_ended",
]

func _init() -> void:
	var catalog: Variant = _load_json(CATALOG_PATH)
	if typeof(catalog) != TYPE_DICTIONARY:
		_fail("tutorial catalog did not parse as a Dictionary")
		return
	var state = TutorialStateScript.new()
	if not state.configure(catalog as Dictionary):
		_fail("tutorial catalog failed schema validation")
		return
	var known: Dictionary = {}
	for tutorial_id in state.get_tutorial_ids():
		known[String(tutorial_id)] = true
	for required_id in REQUIRED_TUTORIAL_IDS:
		if not known.has(required_id):
			_fail("required tutorial id missing: %s" % required_id)
			return

	var codex: Variant = _load_json(CODEX_PATH)
	if typeof(codex) != TYPE_DICTIONARY:
		_fail("codex catalog did not parse as a Dictionary")
		return
	var codex_ids: Dictionary = {}
	for entry_variant in (codex as Dictionary).get("entries", []):
		if entry_variant is Dictionary:
			codex_ids[str((entry_variant as Dictionary).get("id", ""))] = true
	for tutorial_variant in (catalog as Dictionary).get("tutorials", []):
		if not (tutorial_variant is Dictionary):
			continue
		var tutorial: Dictionary = tutorial_variant
		var codex_entry_id: String = str(tutorial.get("codex_entry_id", ""))
		if codex_entry_id.is_empty() or not codex_ids.has(codex_entry_id):
			_fail("tutorial '%s' has no matching codex entry: %s" % [str(tutorial.get("id", "")), codex_entry_id])
			return

	var playable_source: String = FileAccess.get_file_as_string(PLAYABLE_PATH)
	for event_id in REQUIRED_EMITTER_EVENTS:
		if not playable_source.contains("trigger_tutorial(\"%s\"" % event_id):
			_fail("no production tutorial emitter found for event: %s" % event_id)
			return

	print("TUTORIAL SLICE COVERAGE PASS tutorials=%d required=%d codex=%d emitters=%d" % [
		state.get_catalog_size(), REQUIRED_TUTORIAL_IDS.size(), codex_ids.size(), REQUIRED_EMITTER_EVENTS.size()])
	quit(0)

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _fail(message: String) -> void:
	push_error("TUTORIAL SLICE COVERAGE FAIL: %s" % message)
	quit(1)
