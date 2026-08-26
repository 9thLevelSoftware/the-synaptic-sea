extends SceneTree

const CanonicalScript: GDScript = preload("res://scripts/procgen/procgen_canonical_json.gd")

func _init() -> void:
	var helper: RefCounted = CanonicalScript.new()
	var raw := '{"bundle":{"gameplay_ir":{"z":40.0,"a":1e+2},"request":{"presentation":{"ignored":true},"b":"x\\u0021","a":[40,40.0,-2.50e-1]},"version":"v","site_ir":{"escaped":"\\u0061"},"world_ir":{"n":null,"f":false}}}'
	var expected := '{"gameplay_ir":{"a":1e+2,"z":40.0},"request":{"a":[40,40.0,-2.50e-1],"b":"x!"},"site_ir":{"escaped":"a"},"version":"v","world_ir":{"f":false,"n":null}}'
	_expect(helper.canonicalize(raw) == expected, "canonical bytes")
	_expect(helper.semantic_hash(raw) == _sha256(expected), "canonical sha256")
	var reordered := '{"bundle":{"version":"v","world_ir":{"f":false,"n":null},"site_ir":{"escaped":"a"},"gameplay_ir":{"a":1e+2,"z":40.0},"request":{"b":"x!","a":[40,40.0,-2.50e-1],"presentation":0}}}'
	_expect(helper.canonicalize(reordered) == expected, "key reordering")
	for bad in [
		'{"bundle":{"version":1,"request":{"a":1,"a":2},"world_ir":{},"site_ir":{},"gameplay_ir":{}}}',
		'{"bundle":{"version":1,"request":{},"world_ir":{},"site_ir":{},"gameplay_ir":{}}} trailing',
		'{"bundle":{"version":1,"request":{"x":NaN},"world_ir":{},"site_ir":{},"gameplay_ir":{}}}',
		'{"bundle":{"version":01,"request":{},"world_ir":{},"site_ir":{},"gameplay_ir":{}}}'
	]:
		_expect(helper.canonicalize(bad).is_empty() and not helper.last_error.is_empty(), "reject malformed")
	print("TASK5 CANONICAL JSON SMOKE PASS")
	quit()

func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

func _expect(condition: bool, label: String) -> void:
	if not condition:
		push_error("TASK5 CANONICAL JSON SMOKE FAIL: " + label)
		quit(1)
