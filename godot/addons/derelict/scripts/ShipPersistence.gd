class_name ShipPersistence
## Mutation-diff persistence: the base ship is never saved — it regenerates
## from (seed, params, generator_version); only player-caused mutations are
## stored and re-applied. The same apply path serves save/load today and
## host->client co-op replication later (replicate the diff dict via RPC and
## call apply()).

const SAVE_DIR := "user://derelicts"

var site_id: String
var seed_value: int
var generator_version: int
var params: Dictionary
## The diff. Keys mirror derelict_core::ShipMutationDiff.
var door_open: Dictionary = {}            # entity_id -> bool
var door_locked: Dictionary = {}          # entity_id -> bool
var container_inventory: Dictionary = {}  # entity_id -> Array[{item_id, qty}]
var removed_entities: Dictionary = {}     # entity_id -> true

func _init(p_site_id: String, p_seed: int, p_version: int, p_params: Dictionary) -> void:
	site_id = p_site_id
	seed_value = p_seed
	generator_version = p_version
	params = p_params

func is_empty() -> bool:
	return door_open.is_empty() and door_locked.is_empty() \
		and container_inventory.is_empty() and removed_entities.is_empty()

## Record a mutation from a live entity (connected to entity_mutated).
func record(entity: DerelictEntity) -> void:
	match entity.kind:
		"door":
			door_open[entity.entity_id] = entity.is_open()
			door_locked[entity.entity_id] = entity.is_locked()
		"container":
			container_inventory[entity.entity_id] = entity.inventory.duplicate(true)
		_:
			pass

func record_removed(entity_id: int) -> void:
	removed_entities[entity_id] = true

## Apply the diff onto a freshly built ship node. Fixed order (locks, open
## states, inventories, removals); unknown ids are skipped so generator
## upgrades degrade gracefully instead of crashing loads.
func apply(ship_node: DerelictShipNode) -> void:
	for id in door_locked:
		if ship_node.doors_by_id.has(int(id)):
			ship_node.doors_by_id[int(id)]["locked"] = door_locked[id]
	for id in door_open:
		if ship_node.doors_by_id.has(int(id)):
			ship_node.doors_by_id[int(id)]["open"] = door_open[id]
	for wl in ship_node.wall_layers:
		wl.queue_redraw()
	for id in container_inventory:
		var node: DerelictEntity = ship_node.entities_by_id.get(int(id))
		if node:
			node.inventory = container_inventory[id].duplicate(true)
			node.queue_redraw()
	for id in removed_entities:
		var node2: DerelictEntity = ship_node.entities_by_id.get(int(id))
		if node2:
			node2.queue_free()
			ship_node.entities_by_id.erase(int(id))

func save() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var payload := {
		"site_id": site_id,
		"seed": seed_value,
		"generator_version": generator_version,
		"params": params,
		"door_open": door_open,
		"door_locked": door_locked,
		"container_inventory": container_inventory,
		"removed_entities": removed_entities.keys(),
	}
	var f := FileAccess.open("%s/%s.json" % [SAVE_DIR, site_id], FileAccess.WRITE)
	f.store_string(JSON.stringify(payload))

static func load_for(p_site_id: String) -> ShipPersistence:
	var path := "%s/%s.json" % [SAVE_DIR, p_site_id]
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var payload: Variant = JSON.parse_string(f.get_as_text())
	if payload == null or typeof(payload) != TYPE_DICTIONARY:
		return null
	var p := ShipPersistence.new(
		payload["site_id"], int(payload["seed"]),
		int(payload["generator_version"]), payload.get("params", {}))
	# JSON round-trips keys as strings; normalize to ints.
	for k in payload.get("door_open", {}):
		p.door_open[int(k)] = payload["door_open"][k]
	for k in payload.get("door_locked", {}):
		p.door_locked[int(k)] = payload["door_locked"][k]
	for k in payload.get("container_inventory", {}):
		p.container_inventory[int(k)] = payload["container_inventory"][k]
	for k in payload.get("removed_entities", []):
		p.removed_entities[int(k)] = true
	return p
