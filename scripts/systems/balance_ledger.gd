extends RefCounted
class_name BalanceLedger

## REQ-INT-004 balance sanity ledger.
##
## Data-driven threshold checker for cross-system scenarios. It records which
## scenario metrics stay inside the safe ranges documented by Task 14.

var _scenario_rules: Dictionary = {} # scenario_id -> Array[Dictionary]
var _last_results: Array = []

func configure(data: Dictionary) -> bool:
	_scenario_rules.clear()
	_last_results.clear()
	if data == null or data.is_empty():
		return false
	var scenarios: Array = _as_array(data.get("scenarios", []))
	for raw in scenarios:
		var row: Dictionary = _as_dict(raw)
		var scenario_id: String = str(row.get("scenario_id", ""))
		if scenario_id.is_empty():
			continue
		var metrics: Array = []
		for metric_raw in _as_array(row.get("metrics", [])):
			var metric: Dictionary = _as_dict(metric_raw)
			if str(metric.get("metric", "")).is_empty():
				continue
			metrics.append(metric)
		_scenario_rules[scenario_id] = metrics
	return not _scenario_rules.is_empty()

func evaluate_scenario(scenario_id: String, metrics: Dictionary) -> Dictionary:
	var failures: Array = []
	var checked: int = 0
	var rules: Array = _as_array(_scenario_rules.get(scenario_id, []))
	if rules.is_empty():
		return {"pass": false, "scenario_id": scenario_id, "checked": 0, "failures": [{"reason": "unknown_scenario"}]}
	for raw_rule in rules:
		var rule: Dictionary = _as_dict(raw_rule)
		var metric_name: String = str(rule.get("metric", ""))
		if metric_name.is_empty():
			continue
		checked += 1
		if not metrics.has(metric_name):
			failures.append({"metric": metric_name, "reason": "missing"})
			continue
		var value: float = float(metrics.get(metric_name, 0.0))
		if rule.has("min") and value < float(rule.get("min", 0.0)):
			failures.append({"metric": metric_name, "reason": "below_min", "value": value, "min": float(rule.get("min", 0.0))})
		if rule.has("max") and value > float(rule.get("max", value)):
			failures.append({"metric": metric_name, "reason": "above_max", "value": value, "max": float(rule.get("max", value))})
	var result: Dictionary = {"pass": failures.is_empty(), "scenario_id": scenario_id, "checked": checked, "failures": failures}
	_last_results.append(result)
	return result

func get_summary() -> Dictionary:
	var pass_count: int = 0
	for result in _last_results:
		if bool((result as Dictionary).get("pass", false)):
			pass_count += 1
	return {"scenario_count": _scenario_rules.size(), "result_count": _last_results.size(), "pass_count": pass_count}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var summary: Dictionary = get_summary()
	lines.append("Balance Ledger: scenarios=%d results=%d pass=%d" % [
		int(summary.get("scenario_count", 0)),
		int(summary.get("result_count", 0)),
		int(summary.get("pass_count", 0)),
	])
	return lines

func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	if value == null:
		return []
	return [value]

func _as_dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}
