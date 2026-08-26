class_name DerelictSite
extends Node2D
## On-demand derelict: give it a world position + archetype; when
## `discover()` is called it derives a deterministic site seed, generates on
## a background thread (polled, never blocking), instantiates the ship, and
## applies any saved mutation diff. Mutations are recorded and saved
## automatically.
##
## Co-op note: the (seed, params, generator_version) triple is all a client
## needs to regenerate this exact ship; replicate mutations by sending the
## persistence diff dict through your RPC layer and calling apply().

signal ship_ready(ship_node: DerelictShipNode)

@export var world_seed: int = 0
@export var world_x: int = 0
@export var world_y: int = 0
@export var archetype_id: String = "corvette"

var generator: RefCounted            # DerelictGenerator (from the extension)
var ship_node: DerelictShipNode
var persistence: ShipPersistence
var _request_id: int = 0
var _pending := false

func _ready() -> void:
	generator = ClassDB.instantiate("DerelictGenerator")
	set_process(false)

func site_id() -> String:
	return "site_%d_%d_%d" % [world_seed, world_x, world_y]

func site_seed() -> int:
	return generator.derive_site_seed(world_seed, world_x, world_y)

func discover(intactness_override: int = -1) -> void:
	if _pending:
		return
	var params := {"archetype_id": archetype_id}
	if intactness_override >= 0:
		params["intactness_override"] = intactness_override
	_request_id = generator.generate_async(site_seed(), params)
	_pending = true
	set_process(true)

func _process(_delta: float) -> void:
	if not _pending:
		set_process(false)
		return
	var result: Variant = generator.poll_async(_request_id)
	if result == null:
		return
	_pending = false
	set_process(false)
	var ship: Dictionary = result
	if ship.has("error"):
		push_error("derelict generation failed: %s" % ship["error"])
		return
	_instantiate(ship)

func _instantiate(ship: Dictionary) -> void:
	if ship_node:
		ship_node.queue_free()
	ship_node = DerelictShipNode.new()
	ship_node.name = "Ship"
	add_child(ship_node)
	ship_node.build(ship)

	persistence = ShipPersistence.load_for(site_id())
	if persistence == null:
		persistence = ShipPersistence.new(
			site_id(), int(ship["seed"]), int(ship["generator_version"]),
			{"archetype_id": archetype_id})
	else:
		persistence.apply(ship_node)
	ship_node.entity_mutated.connect(_on_mutation)
	ship_node.build_finished.connect(func() -> void:
		if persistence and not persistence.is_empty():
			persistence.apply(ship_node))
	ship_ready.emit(ship_node)

func _on_mutation(entity: DerelictEntity) -> void:
	persistence.record(entity)
	persistence.save()
