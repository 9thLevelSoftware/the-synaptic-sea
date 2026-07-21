extends SceneTree

## REQ-CS-017 pure-model smoke: DeconstructionResolver.list_salvage_entries lists
## deconstruct recipes + inventory junk with correct ready/blocked status.

const DeconstructionResolverScript := preload("res://scripts/systems/deconstruction_resolver.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	var resolver = DeconstructionResolverScript.new()
	if not resolver.has_method("list_salvage_entries"):
		_fail("list_salvage_entries missing")
		return
	var inv = InventoryStateScript.new()
	var empty: Array = resolver.list_salvage_entries(inv)
	# Empty inv: deconstruct rows may still appear as missing_ingredients.
	var saw_deconstruct: bool = false
	for e in empty:
		var d: Dictionary = e as Dictionary
		if str(d.get("salvage_kind", "")) == "deconstruct":
			saw_deconstruct = true
			if bool(d.get("craftable", false)):
				_fail("empty inv should not make deconstruct ready: %s" % str(d.get("recipe_id", "")))
				return
	if not saw_deconstruct:
		_fail("expected deconstruction recipe rows even with empty inv")
		return

	# Seed a deconstructable item + a junk catalog item if available.
	inv.add_item("plating", 2)
	inv.add_item("scrap_metal", 4)
	# Common junk keys from junk_items.json — try a few; at least one should list.
	var junk_candidates: Array = ["broken_circuit", "scrap_metal", "hull_fragment", "corroded_pipe", "frayed_cable"]
	var junk_seeded: String = ""
	for jid in junk_candidates:
		# If already a deconstruct ingredient only, still fine — list may show both.
		inv.add_item(str(jid), 1)
		junk_seeded = str(jid)

	var mat = MaterialStateScript.new()
	var entries: Array = resolver.list_salvage_entries(inv)
	var ready_n: int = 0
	var decon_ready: int = 0
	var junk_ready: int = 0
	var prev: String = ""
	for e in entries:
		var d: Dictionary = e as Dictionary
		var rid: String = str(d.get("recipe_id", ""))
		if prev != "" and rid < prev:
			_fail("entries not sorted: %s before %s" % [prev, rid])
			return
		prev = rid
		if bool(d.get("craftable", false)):
			ready_n += 1
			if str(d.get("salvage_kind", "")) == "deconstruct":
				decon_ready += 1
			elif str(d.get("salvage_kind", "")) == "junk":
				junk_ready += 1

	if ready_n < 1:
		_fail("expected at least one ready salvage target after seeding")
		return

	var first: String = resolver.first_ready_salvage_id(inv)
	if first.is_empty():
		_fail("first_ready_salvage_id empty")
		return
	var produced: Dictionary = resolver.execute_salvage_target(first, inv, mat)
	if produced.is_empty():
		_fail("execute_salvage_target failed for %s" % first)
		return

	print("SALVAGE LIST PASS ready=%d decon_ready=%d junk_ready=%d executed=%s" % [
		ready_n, decon_ready, junk_ready, first])
	quit()
