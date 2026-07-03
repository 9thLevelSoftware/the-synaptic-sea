extends SceneTree

## Domain 10 (ADR-0045) WebChartState pure model smoke.
## 1. record at detail 2 -> fields present, no detail-4+ fields.
## 2. re-record same marker at detail 5 (upgrade) -> fields added, never downgrades.
## 3. re-record at a LOWER detail afterwards -> no-op (stays at max).
## 4. malformed/unknown views are skipped, not rejected wholesale.
## Marker: WEB CHART STATE PASS known=N detail_upgrade=true

const WebChartStateScript := preload("res://scripts/systems/web_chart_state.gd")

func _initialize() -> void:
	var chart = WebChartStateScript.new()

	var views_detail2: Array = [
		{"marker_id": "m1", "position": [10.0, 0.0, 20.0], "size_class": 1, "ship_type": "freighter"},
		{"marker_id": "m2", "position": [30.0, 0.0, 40.0], "size_class": 0, "ship_type": "corvette"},
	]
	var added: int = chart.record_views(views_detail2, 2)
	if added != 2:
		_fail("first record expected added=2 got %d" % added)
		return
	var e1: Dictionary = chart.get_entry("m1")
	if int(e1.get("detail", 0)) != 2 or String(e1.get("ship_type", "")) != "freighter":
		_fail("m1 detail-2 fields missing/wrong: %s" % str(e1))
		return
	if e1.has("condition") or e1.has("loot_hint"):
		_fail("m1 should not have detail>=3 fields yet: %s" % str(e1))
		return

	var views_detail5: Array = [
		{"marker_id": "m1", "position": [10.0, 0.0, 20.0], "size_class": 1, "ship_type": "freighter",
			"condition": 1, "predicted_status": "systems degraded", "predicted_offline": ["scanners"]},
	]
	var upgraded: int = chart.record_views(views_detail5, 5)
	if upgraded != 1:
		_fail("upgrade record expected added=1 got %d" % upgraded)
		return
	var e1_upgraded: Dictionary = chart.get_entry("m1")
	if int(e1_upgraded.get("detail", 0)) != 5:
		_fail("m1 detail did not upgrade to 5: %s" % str(e1_upgraded))
		return
	if String(e1_upgraded.get("predicted_status", "")) != "systems degraded":
		_fail("m1 missing detail-4 field after upgrade: %s" % str(e1_upgraded))
		return

	# Re-record at a LOWER detail: must be a no-op (never downgrades).
	var noop_added: int = chart.record_views(views_detail2, 2)
	if noop_added != 0:
		_fail("lower-detail re-record should be a no-op, got added=%d" % noop_added)
		return
	if int(chart.get_entry("m1").get("detail", 0)) != 5:
		_fail("m1 detail regressed below 5 after lower-detail re-record")
		return

	# Malformed views: missing marker_id / missing required field / non-dict entries.
	var malformed: Array = [
		{"position": [1.0, 1.0, 1.0], "size_class": 0},   # missing marker_id
		{"marker_id": "m3"},                                # missing position/size_class
		"not_a_dict",
	]
	var malformed_added: int = chart.record_views(malformed, 3)
	if malformed_added != 0:
		_fail("malformed views should all be skipped, got added=%d" % malformed_added)
		return

	if chart.get_known_count() != 2:
		_fail("expected known_count=2, got %d" % chart.get_known_count())
		return

	print("WEB CHART STATE PASS known=%d detail_upgrade=true" % chart.get_known_count())
	quit(0)

func _fail(reason: String) -> void:
	push_error("WEB CHART STATE FAIL reason=%s" % reason)
	quit(1)
