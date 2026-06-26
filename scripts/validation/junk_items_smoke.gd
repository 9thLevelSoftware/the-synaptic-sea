extends SceneTree

func _initialize() -> void:
	var resolver_script := load("res://scripts/systems/junk_yield_resolver.gd")
	var defs_script := load("res://scripts/systems/item_defs.gd")
	if resolver_script == null or defs_script == null:
		_fail("required junk scripts failed to load")
		return
	var junk_defs: Dictionary = resolver_script.load_definitions()
	var item_defs: Dictionary = defs_script.load_definitions()
	if junk_defs.size() < 4:
		_fail("expected >= 4 junk definitions, got %d" % junk_defs.size())
		return
	var total_yield_entries: int = 0
	for item_id in junk_defs.keys():
		var resolver_yields: Array = resolver_script.yields_for_item(String(item_id), junk_defs)
		var merged_yields: Array = defs_script.junk_yields(item_defs, String(item_id))
		if resolver_yields.is_empty() or merged_yields.is_empty():
			_fail("junk item %s is missing salvage yields" % String(item_id))
			return
		if JSON.stringify(resolver_yields) != JSON.stringify(merged_yields):
			_fail("merged item defs drifted from junk catalog for %s" % String(item_id))
			return
		total_yield_entries += resolver_yields.size()
	print("JUNK ITEMS PASS items=%d yields=%d" % [junk_defs.size(), total_yield_entries])
	quit(0)

func _fail(reason: String) -> void:
	push_error("JUNK ITEMS FAIL reason=%s" % reason)
	quit(1)
