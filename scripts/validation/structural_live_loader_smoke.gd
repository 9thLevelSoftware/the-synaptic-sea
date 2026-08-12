extends SceneTree

## Task 1.3: live generated/away ship path must materialize the canonical
## structural kit through ShipGenerator -> GeneratedShipLoader.

const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript: GDScript = preload("res://scripts/procgen/ship_generator.gd")

const SEEDS: Array[int] = [42, 777]
const BIOME_ID: String = "breach_field"
const DIFFICULTY_ID: String = "standard"


func _initialize() -> void:
	var generator = ShipGeneratorScript.new()
	generator.configure_run_context(BIOME_ID, DIFFICULTY_ID)
	var total_kit_meshes: int = 0
	var total_kit_wrappers: int = 0
	var total_floor_wrappers: int = 0
	var total_edge_wrappers: int = 0

	for seed_value in SEEDS:
		var blueprint = ShipBlueprintScript.new(
			ShipBlueprintScript.Size.MEDIUM,
			ShipBlueprintScript.Condition.WRECKED,
			seed_value)
		var ship: Node3D = generator.generate(blueprint, {})
		if ship == null:
			_fail("seed=%d generator returned null" % seed_value)
			return
		if not ship.has_method("has_loaded_ship") or not ship.has_loaded_ship():
			_free_ship(ship)
			_fail("seed=%d generated loader did not report loaded" % seed_value)
			return

		var structural_root: Node = ship.get_node_or_null("StructuralRoot")
		if structural_root == null:
			_free_ship(ship)
			_fail("seed=%d missing StructuralRoot" % seed_value)
			return
		var plan_variant: Variant = ship.layout_doc.get("structural_plan", null)
		if typeof(plan_variant) != TYPE_DICTIONARY:
			_free_ship(ship)
			_fail("seed=%d missing canonical structural_plan" % seed_value)
			return
		var plan: Dictionary = plan_variant
		var expected_floors: int = (plan.get("floor_placements", []) as Array).size()
		var expected_edges: int = (plan.get("placements", []) as Array).size()
		var floor_wrappers: int = _count_meta(structural_root, "structural_cell_key")
		var edge_wrappers: int = _count_meta(structural_root, "structural_edge_key")
		var kit_meshes: int = _count_mesh_instances(structural_root)
		var kit_wrappers: int = _count_meta(structural_root, "module_kind")
		if expected_floors <= 0 or floor_wrappers != expected_floors:
			_free_ship(ship)
			_fail("seed=%d floor wrappers=%d expected=%d" % [seed_value, floor_wrappers, expected_floors])
			return
		if edge_wrappers != expected_edges:
			_free_ship(ship)
			_fail("seed=%d edge wrappers=%d expected=%d" % [seed_value, edge_wrappers, expected_edges])
			return
		if kit_wrappers <= 0 or kit_meshes <= 0:
			_free_ship(ship)
			_fail("seed=%d kit wrappers=%d mesh_instances=%d" % [seed_value, kit_wrappers, kit_meshes])
			return

		total_kit_meshes += kit_meshes
		total_kit_wrappers += kit_wrappers
		total_floor_wrappers += floor_wrappers
		total_edge_wrappers += edge_wrappers
		_free_ship(ship)

	print(
		"STRUCTURAL LIVE LOADER PASS seeds=%d biome=%s kit_wrappers=%d kit_meshes=%d floor_wrappers=%d edge_wrappers=%d"
		% [SEEDS.size(), BIOME_ID, total_kit_wrappers, total_kit_meshes, total_floor_wrappers, total_edge_wrappers]
	)
	quit(0)


func _count_meta(node: Node, meta_name: String) -> int:
	var count: int = 1 if node.has_meta(meta_name) else 0
	for child in node.get_children():
		count += _count_meta(child, meta_name)
	return count


func _count_mesh_instances(node: Node) -> int:
	var count: int = 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count


func _free_ship(ship: Node) -> void:
	if ship != null and is_instance_valid(ship):
		ship.free()


func _fail(reason: String) -> void:
	push_error("STRUCTURAL LIVE LOADER FAIL reason=%s" % reason)
	quit(1)
