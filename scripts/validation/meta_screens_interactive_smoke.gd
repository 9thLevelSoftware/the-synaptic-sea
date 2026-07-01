extends SceneTree

## Domain 6 interactive meta-screens smoke: drives MenuCoordinator's meta-screen
## selection + confirm seams to purchase a hub upgrade, spending meta currency.
## (Skill-tree unlock and class selection are added to this smoke in later tasks.)
##
## Marker: `META SCREENS INTERACTIVE PASS`

const MenuCoordinatorScript := preload("res://scripts/ui/menu_coordinator.gd")
const HubUpgradeStateScript := preload("res://scripts/systems/hub_upgrade_state.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const UnlockRegistryScript := preload("res://scripts/systems/unlock_registry.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const AchievementStateScript := preload("res://scripts/systems/achievement_state.gd")
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
const BuildMetadataStateScript := preload("res://scripts/systems/build_metadata_state.gd")
const SaveLoadMenuScript := preload("res://scripts/ui/save_load_menu.gd")
const LocalizationCatalogScript := preload("res://scripts/systems/localization_catalog.gd")

var _coord: Node = null
var _audio: Node = null

func _initialize() -> void:
	_coord = MenuCoordinatorScript.new()
	get_root().add_child(_coord)
	# _ready() (which builds the meta-screen panels into _meta_panels) is deferred to the
	# next idle frame by the engine, not run synchronously by add_child() — wait for it.
	await process_frame
	# Register the real menu catalog so menu_state knows "records_menu" — bind_meta_screens
	# only wires the meta-screen model refs, it does not register menu_state's menu list.
	# The other sub-states validate against schema version strings, so feed them their
	# real catalogs too (empty dicts fail schema validation and push_error).
	_coord.configure(
		_load_json("res://data/ui/menu_definitions.json"),
		_load_json("res://data/ui/tutorial_triggers.json"),
		_load_json("res://data/ui/codex_entries.json"),
		_load_json("res://data/ui/input_glyphs.json"),
		_load_json("res://data/ui/tooltip_catalog.json"),
		_load_json("res://data/ui/accessibility_presets.json"),
		{},
		null,
	)

	var hub = HubUpgradeStateScript.new(); hub.configure()
	var tree = SkillTreeStateScript.new()
	tree.configure(SkillTreeStateScript.load_skills_catalog(), SkillTreeStateScript.load_books_catalog())
	tree.load_prerequisites()
	var meta = MetaProgressionStateScript.new(); meta.configure({})
	meta.add_meta_currency(500)   # enough to afford a base upgrade
	var reg = UnlockRegistryScript.new()
	reg.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/player/unlock_tables.json")))
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var prog = PlayerProgressionScript.new()
	prog.configure(classes.get("engineer", null), PlayerProgressionScript.load_skills_catalog(), PlayerProgressionScript.load_books_catalog())
	var ach = AchievementStateScript.new()
	_audio = AudioManagerScript.new()
	var build_meta = BuildMetadataStateScript.new()
	var slmenu = SaveLoadMenuScript.new()
	# language_selector.set_catalog() expects a LocalizationCatalog object, not a raw dict.
	var loc := LocalizationCatalogScript.new()
	loc.configure({})

	_coord.bind_meta_screens(ach, _audio, tree, prog, hub, meta, loc, build_meta, slmenu, null, reg)

	# --- Hub upgrade purchase ---
	_coord.open_meta_screen("hub_upgrades")
	if _coord.get_active_meta_screen() != "hub_upgrades":
		_fail("hub_upgrades screen did not open")
		return
	var currency_before: int = meta.get_meta_currency()
	# get_upgrade_entries() sorts alphabetically by upgrade_id (hub_upgrade_state.gd), so the
	# cursor's initial row (index 0) is "hub_armory", which itself requires "hub_medical_bay"
	# — not purchasable first. Move deterministically to the alphabetically-sorted position of
	# "hub_medical_bay" (cost 75, no prereqs), which get_upgrade_ids() (also sorted) locates.
	var sorted_ids: Array = hub.get_upgrade_ids()
	var target_id := "hub_medical_bay"
	var target_index: int = sorted_ids.find(target_id)
	if target_index < 0:
		_fail("target upgrade '%s' not found in catalog" % target_id)
		return
	_coord.meta_screen_move_selection(target_index)
	var hub_panel = _coord.get_meta_screen_panel("hub_upgrades")
	if hub_panel == null or hub_panel.get_selected_id() != target_id:
		_fail("cursor did not land on %s (got %s)" % [target_id, str(hub_panel.get_selected_id() if hub_panel != null else "<null>")])
		return
	var result: Dictionary = _coord.meta_screen_confirm()
	if not bool(result.get("ok", false)):
		_fail("hub purchase confirm failed: %s" % str(result))
		return
	if meta.get_meta_currency() >= currency_before:
		_fail("purchase did not spend currency (%d -> %d)" % [currency_before, meta.get_meta_currency()])
		return
	if meta.get_unlocked_hub_upgrade_ids().is_empty():
		_fail("no hub upgrade recorded after purchase")
		return

	# --- Skill-tree unlock (fabrication requires repair >= 2, no book) ---
	# Level repair to 2 so the fabrication node is unlockable.
	while prog.get_skill_level("repair") < 2:
		prog.grant_xp("repair", 500)
	_coord.open_meta_screen("skill_tree")
	# Move the cursor to fabrication deterministically by scanning entries order.
	var entries: Array = tree.get_skill_entries()
	var skill_target_index: int = -1
	for i in range(entries.size()):
		if str((entries[i] as Dictionary).get("skill_id", "")) == "fabrication":
			skill_target_index = i
			break
	if skill_target_index < 0:
		_fail("fabrication not found in skill entries")
		return
	# Reset cursor to 0 then step down to the target.
	_coord.meta_screen_move_selection(-9999)
	for _i in range(skill_target_index):
		_coord.meta_screen_move_selection(1)
	var unlock_result: Dictionary = _coord.meta_screen_confirm()
	if not bool(unlock_result.get("ok", false)):
		_fail("skill unlock confirm failed: %s" % str(unlock_result))
		return
	if not tree.is_unlocked("fabrication"):
		_fail("fabrication should be unlocked after confirm")
		return

	# --- Unlock-registry records reader ---
	var unlocked_id: String = reg.unlock_for_trigger("scavenge_container", "any")
	if unlocked_id.is_empty():
		_fail("registry did not unlock on scavenge_container")
		return
	var lines: PackedStringArray = _coord.get_registry_unlock_lines()
	var found: bool = false
	for l in lines:
		if String(l).findn(reg.get_display_name(unlocked_id)) != -1:
			found = true
			break
	if not found:
		_fail("registry reader did not surface unlocked entry %s" % unlocked_id)
		return

	print("META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true registry_reader=true")
	_cleanup()
	quit(0)

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _cleanup() -> void:
	if is_instance_valid(_audio):
		_audio.queue_free()
	if is_instance_valid(_coord):
		_coord.queue_free()

func _fail(reason: String) -> void:
	push_error("META SCREENS INTERACTIVE FAIL reason=%s" % reason)
	_cleanup()
	quit(1)
