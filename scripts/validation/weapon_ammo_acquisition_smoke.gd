extends SceneTree

## Domain 5 / combat acquisition chain smoke.
##
## The audit found all three ranged weapons permanently unusable in production:
## no loot table, recipe, or starting kit ever granted a ranged weapon or a
## single round of ammo, and every existing combat smoke masked the gap by
## injecting ammo via inventory_state.add_item() seams and duplicating the
## coordinator's reload debit logic smoke-side.
##
## This smoke closes both holes:
## 1. data_reachable — for EVERY weapon in data/combat/weapon_definitions.json
##    with a non-empty ammo_item_id: the ammo item AND the weapon's equip item
##    (weapon ids ARE the equip item ids since PR #61) appear in at least
##    one entry of data/items/loot_tables.json, and both resolve in the merged
##    ItemDefs registry. Ammo/weapons that exist only in definitions are
##    unreachable content — that is a FAIL, not a balance choice.
## 2. looted_ammo — flare rounds actually arrive in inventory through the REAL
##    production loot path (corpse containers spawned by _on_threat_killed,
##    searched through try_interact), not an add_item seam.
## 3. production_reload — playable._begin_weapon_reload() (the coordinator
##    function, which debits inventory itself) starts a reload from the looted
##    reserve, and the reload completes on the AWAY branch _process path.
##
## Pass marker: WEAPON AMMO ACQUISITION PASS data_reachable=true looted_ammo=true production_reload=true away_ticks=30

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const WEAPON_DEFS_PATH: String = "res://data/combat/weapon_definitions.json"
const LOOT_TABLES_PATH: String = "res://data/items/loot_tables.json"
const TIMEOUT_FRAMES: int = 300
const MAX_LOOT_TRIES: int = 20

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if not is_instance_valid(playable):
		playable = _find_playable(main_node)
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _load_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

## The inventory item the player equips to wield this weapon. Weapon ids ARE
## the equip item ids (the pre-PR-#61 capacitor_cell alias let auto-equip eat
## looted ammo and never satisfied ThreatManager's literal equipped-id check).
func _equip_item_for_weapon(weapon_id: String) -> String:
	return weapon_id

func _validate() -> void:
	finished = true

	# --- Criterion 1: data reachability -------------------------------------
	var weapons: Dictionary = _load_json(WEAPON_DEFS_PATH)
	var tables: Dictionary = _load_json(LOOT_TABLES_PATH)
	if weapons.is_empty() or tables.is_empty():
		_fail("could not load weapon/loot data files")
		return
	var lootable_ids: Dictionary = {}
	for table_id in tables:
		if String(table_id).begins_with("_"):
			continue
		var table: Variant = tables[table_id]
		if not (table is Dictionary):
			continue
		for entry in (table as Dictionary).get("entries", []):
			if entry is Dictionary:
				lootable_ids[str((entry as Dictionary).get("item_id", ""))] = true
	var item_defs: Dictionary = ItemDefsScript.load_definitions()
	var ranged_checked: int = 0
	for weapon_id in weapons:
		var weapon: Variant = weapons[weapon_id]
		if not (weapon is Dictionary):
			continue
		var ammo_id: String = str((weapon as Dictionary).get("ammo_item_id", ""))
		if ammo_id.is_empty():
			continue  # melee
		ranged_checked += 1
		if not lootable_ids.has(ammo_id):
			_fail("ammo '%s' (weapon %s) appears in no loot table entry" % [ammo_id, weapon_id])
			return
		if not item_defs.has(ammo_id):
			_fail("ammo '%s' missing from merged ItemDefs registry" % ammo_id)
			return
		var equip_item: String = _equip_item_for_weapon(String(weapon_id))
		if not lootable_ids.has(equip_item):
			_fail("weapon equip item '%s' (weapon %s) appears in no loot table entry" % [equip_item, weapon_id])
			return
		if not item_defs.has(equip_item):
			_fail("weapon equip item '%s' missing from merged ItemDefs registry" % equip_item)
			return
	if ranged_checked < 3:
		_fail("expected >=3 ranged weapons in weapon_definitions.json, found %d" % ranged_checked)
		return
	var data_reachable: bool = true

	# --- Criterion 2: ammo arrives through the real loot path ---------------
	if playable.inventory_state == null or playable.ammo_state == null:
		_fail("inventory_state/ammo_state missing")
		return
	var tries: int = 0
	for i in range(MAX_LOOT_TRIES):
		tries += 1
		var iid: String = "ammo_acq_%d" % i
		playable._on_threat_killed({
			"archetype_id": "smoke_archetype",
			"instance_id": iid,
			"position": Vector3(4.0 + float(i), 0.5, -3.0),
			"loot_table": "combat_drop_common",
		})
		if not playable.search_loot_container_for_validation("corpse_%s" % iid):
			_fail("try_interact failed for corpse_%s" % iid)
			return
		if playable.inventory_state.get_quantity("flare_round") > 0:
			break
	var reserve: int = playable.inventory_state.get_quantity("flare_round")
	if reserve <= 0:
		_fail("no flare_round looted from %d combat_drop_common corpse rolls" % tries)
		return
	var looted_ammo: bool = true

	# --- Criterion 3: coordinator reload from the looted reserve ------------
	playable.inventory_state.add_item("flare_pistol", 1)
	if not playable._equip_from_inventory("flare_pistol", true):
		_fail("could not equip flare_pistol")
		return
	if playable.ammo_state.loaded("flare_pistol") != 0:
		_fail("magazine unexpectedly pre-loaded")
		return
	playable._begin_weapon_reload()
	if not playable.ammo_state.is_reloading():
		_fail("_begin_weapon_reload() did not start a reload (reserve=%d)" % reserve)
		return
	var target: int = playable.ammo_state.reload_target
	if playable.inventory_state.get_quantity("flare_round") != reserve - target:
		_fail("inventory reserve not debited by reload_target")
		return
	playable.away_from_start = true
	var away_ticks: int = 0
	for i in range(30):
		playable._process(0.1)  # 3.0s total > 1.5s reload
		away_ticks += 1
	if playable.ammo_state.is_reloading() or playable.ammo_state.loaded("flare_pistol") != target:
		_fail("reload did not complete on away branch: loaded=%d target=%d" % [playable.ammo_state.loaded("flare_pistol"), target])
		return
	var production_reload: bool = true

	# PR #61 Codex P2 guard: shock_probe is its own equip item (no
	# capacitor_cell alias). Equipping it must satisfy attack_with_weapon's
	# literal equipped-id check — an empty magazine ("empty_magazine") is the
	# expected outcome; "weapon_not_equipped" means the alias defect is back.
	playable.inventory_state.add_item("shock_probe", 1)
	if not playable._equip_from_inventory("shock_probe", false):
		_fail("could not equip shock_probe as its own item")
		return
	var probe_result: Dictionary = playable.threat_manager.attack_with_weapon(
		"shock_probe", playable.inventory_state, playable.equipment_state, playable.ammo_state)
	if str(probe_result.get("reason", "")) == "weapon_not_equipped":
		_fail("attack_with_weapon rejected an equipped shock_probe (equip-id alias regression)")
		return

	print("WEAPON AMMO ACQUISITION PASS data_reachable=%s looted_ammo=%s production_reload=%s away_ticks=%d" % [
		str(data_reachable).to_lower(), str(looted_ammo).to_lower(), str(production_reload).to_lower(), away_ticks])
	_cleanup(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("WEAPON AMMO ACQUISITION FAIL reason=%s" % reason)
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
