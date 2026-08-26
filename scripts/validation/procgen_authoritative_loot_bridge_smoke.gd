extends SceneTree

const PlayableScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var playable = PlayableScript.new()
	playable.inventory_state = InventoryStateScript.new()
	playable.current_ship = ShipInstanceScript.new()
	playable.current_ship.marker_id = "site:fixture"
	playable.loot_container_root = Node3D.new()
	playable.add_child(playable.loot_container_root)
	playable.player = PlayerControllerScript.new()
	playable.add_child(playable.player)
	playable._loot_tables = {
		"combat_drop_common": {
			"entries":[{"item_id":"random_fallback", "qty_min":1, "qty_max":1}],
			"rolls":1,
		},
	}
	var exact_items: Array = [{
		"item_id":"item:rust_reward", "quantity":1,
		"frequency_bp":3500,
		"blueprint":{
			"id":"item:rust_reward", "family_id":"weapon", "rarity_id":"common",
			"socket_id":"socket_weapon",
			"affixes":[{"affix_id":"affix_damage", "stat":"damage", "value":20}],
			"stat_budget":200, "economy_value":100, "visual_tag":"item_weapon",
		},
		"asset_ids":["asset:primitive:item_weapon"],
		"presentation_binding_ids":["binding:item:weapon"],
	}]
	playable._on_threat_killed({
		"instance_id":"spawn:fixture_0",
		"archetype_id":"creature_brute",
		"reward_source_id":"reward:fixture",
		"generated_items":exact_items,
		"loot_table":"combat_drop_common",
		"position":Vector3(2.0, 0.0, 3.0),
	})
	_expect(playable.current_ship.pending_corpse_loot.size() == 1, failures, "pending exact corpse")
	if playable.current_ship.pending_corpse_loot.size() == 1:
		_expect(
			playable.current_ship.pending_corpse_loot[0].get("generated_items", []) == exact_items,
			failures,
			"pending exact payload")
	_expect(playable.loot_containers.size() == 1, failures, "live exact corpse")
	if playable.loot_containers.size() == 1:
		_expect(playable.loot_containers[0].loot_context.get("generated_items", []) == exact_items, failures, "live exact context")

	# Exercise the persistence/revisit path before searching the corpse.
	playable._clear_loot_containers()
	playable._spawn_pending_corpse_loot_containers()
	_expect(playable.loot_containers.size() == 1, failures, "respawn exact corpse")
	if playable.loot_containers.size() == 1:
		var corpse = playable.loot_containers[0]
		corpse.set_validation_player_in_range(playable.player)
		_expect(corpse.try_interact(playable.player), failures, "search exact corpse")
	_expect(playable.inventory_state.get_quantity("item:rust_reward") == 1, failures, "exact reward granted")
	_expect(playable.inventory_state.get_quantity("random_fallback") == 0, failures, "no legacy reroll")
	_expect(not playable.inventory_state.get_generated_item_record("item:rust_reward").is_empty(), failures, "generated definition registered")
	_expect(playable.inventory_state.get_category("item:rust_reward") == "generated_item", failures, "generated category")
	var restored_inventory = InventoryStateScript.new()
	_expect(restored_inventory.apply_summary(playable.inventory_state.get_summary()), failures, "generated definition restore")
	_expect(restored_inventory.get_quantity("item:rust_reward") == 1 \
			and not restored_inventory.get_generated_item_record("item:rust_reward").is_empty(), failures, "generated definition round trip")
	var tampered_item: Dictionary = exact_items[0].duplicate(true)
	tampered_item["presentation_binding_ids"] = ["binding:item:armor"]
	_expect(not InventoryStateScript.new().register_generated_item(tampered_item), failures, "tampered binding rejected")
	_expect(playable.current_ship.pending_corpse_loot.is_empty(), failures, "pending cleared")
	var layout_context: Dictionary = playable._build_loot_context({"generated_items":exact_items})
	_expect(layout_context.get("generated_items", []) == exact_items, failures, "layout exact context")

	playable.free()
	if failures.is_empty():
		print("PROCGEN AUTHORITATIVE LOOT BRIDGE PASS layout_exact=true corpse_exact=true revisit=true no_reroll=true")
		quit(0)
	else:
		push_error("PROCGEN AUTHORITATIVE LOOT BRIDGE FAIL reasons=%s" % str(failures))
		quit(1)


func _expect(condition: bool, failures: Array[String], label: String) -> void:
	if not condition:
		failures.append(label)
