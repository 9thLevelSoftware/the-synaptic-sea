extends SceneTree

## V2: goldens load + build ShipNavGraph + share schema keys with live serialize.
## Marker: PROCGEN GOLDEN PARITY PASS goldens=3 nav=true schema=true

const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")
const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")

const GOLDENS: Array[String] = [
	"res://data/procgen/golden/coherent_ship_001/layout.json",
	"res://data/procgen/golden/coherent_ship_002/layout.json",
	"res://data/procgen/golden/coherent_ship_003/layout.json",
]

func _initialize() -> void:
	var ser := LayoutSerializerScript.new()
	var live: Dictionary = ser.serialize({}, {}, [] as Array[Dictionary], "spine", 0, "parity")
	var required: Array = live.keys()
	var checked: int = 0
	for path in GOLDENS:
		var doc: Dictionary = _load_json(path)
		if doc.is_empty():
			_fail("load failed %s" % path)
			return
		if str(doc.get("schema_version", "")) != str(live.get("schema_version", "")):
			_fail("schema mismatch %s" % path)
			return
		for k in required:
			if not doc.has(k):
				_fail("golden missing key %s in %s" % [str(k), path])
				return
		var graph = ShipNavGraphScript.new()
		var n: int = graph.build_from_layout(doc)
		if n < 4:
			_fail("nav graph too small for %s nodes=%d" % [path, n])
			return
		checked += 1
	print("PROCGEN GOLDEN PARITY PASS goldens=%d nav=true schema=true" % checked)
	quit(0)

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var p: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return p if p is Dictionary else {}

func _fail(reason: String) -> void:
	push_error("PROCGEN GOLDEN PARITY FAIL reason=%s" % reason)
	quit(1)
