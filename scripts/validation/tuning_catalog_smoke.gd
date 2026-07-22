extends SceneTree

## PKG-A4: TuningCatalog shell smoke.

const TuningCatalogScript := preload("res://scripts/systems/tuning_catalog.gd")


func _initialize() -> void:
	var cat = TuningCatalogScript.new()

	# Missing key → default
	if absf(cat.get_float("definitely.missing", 3.25) - 3.25) > 0.0001:
		_fail("missing float key should return default")
		return
	if cat.get_int("definitely.missing", 7) != 7:
		_fail("missing int key should return default")
		return
	if cat.get_bool("definitely.missing", true) != true:
		_fail("missing bool key should return default")
		return
	if cat.get_string("definitely.missing", "fallback") != "fallback":
		_fail("missing string key should return default")
		return

	# Shell balance file
	var shell_path: String = "res://data/balance/shell.json"
	if not FileAccess.file_exists(shell_path):
		_fail("shell.json missing at %s" % shell_path)
		return
	if not cat.load_file(shell_path):
		_fail("load_file shell.json failed")
		return
	if not cat.has_key("tuning.example_float"):
		_fail("expected flattened key tuning.example_float")
		return
	if absf(cat.get_float("tuning.example_float", 0.0) - 1.5) > 0.0001:
		_fail("tuning.example_float expected 1.5")
		return
	if cat.get_int("tuning.catalog_shell_version", 0) != 1:
		_fail("catalog_shell_version expected 1")
		return

	# Explicit defaults load (export-safe path list)
	var cat_defaults = TuningCatalogScript.new()
	var n_defaults: int = cat_defaults.load_defaults()
	if n_defaults < 1:
		_fail("load_defaults should load shell.json")
		return
	if absf(cat_defaults.get_float("tuning.example_float", 0.0) - 1.5) > 0.0001:
		_fail("load_defaults missing example_float")
		return

	# Directory load (dev convenience; falls back to defaults if listing fails)
	var cat2 = TuningCatalogScript.new()
	var n: int = cat2.load_directory("res://data/balance/")
	if n < 1:
		_fail("load_directory should load at least shell.json")
		return
	if absf(cat2.get_float("tuning.example_float", 0.0) - 1.5) > 0.0001:
		_fail("directory load missing example_float")
		return

	# Override after load
	var tmp_path: String = "user://tuning_catalog_smoke_override.json"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		_fail("could not write override fixture")
		return
	f.store_string("{\"tuning\":{\"example_float\":9.25}}")
	f.close()
	if not cat2.load_file(tmp_path):
		_fail("override load failed")
		return
	if absf(cat2.get_float("tuning.example_float", 0.0) - 9.25) > 0.0001:
		_fail("override should win")
		return

	print("TUNING CATALOG PASS shell=true dir_loaded=%d override=true" % n)
	quit(0)


func _fail(msg: String) -> void:
	print("TUNING CATALOG FAIL: %s" % msg)
	quit(1)
