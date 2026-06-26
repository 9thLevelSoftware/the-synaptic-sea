extends RefCounted
class_name HubUpgradeState

## REQ-PM-007 / ADR-0033 hub-upgrade catalog + purchase gates.
##
## Loads `data/player/hub_upgrades.json` (id, display_name, description,
## cost, requires, effects). `purchase(upgrade_id, meta_state)` gates on
## catalog membership, prerequisite upgrades, and meta currency.
##
## Pure: no scene tree, no RNG. The hub upgrade panel UI reads from this
## model and exposes per-upgrade status lines.

const DEFAULT_UPGRADES_PATH := "res://data/player/hub_upgrades.json"

var _upgrades_by_id: Dictionary = {}   # upgrade_id -> full entry dict

static func load_default(path: String = DEFAULT_UPGRADES_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

## Configures from a parsed Dictionary (the JSON content) or loads the
## default file when `catalog == null`. Returns false on parse error.
func configure(catalog: Dictionary = {}) -> bool:
	_upgrades_by_id.clear()
	var src: Dictionary = catalog
	if src == null or src.is_empty():
		src = load_default()
	if src.is_empty():
		return false
	var variant: Variant = src.get("upgrades", [])
	if typeof(variant) != TYPE_ARRAY:
		return false
	for entry in (variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uid: String = str((entry as Dictionary).get("upgrade_id", ""))
		if uid.is_empty():
			continue
		_upgrades_by_id[uid] = (entry as Dictionary).duplicate(true)
	return true

func is_known(upgrade_id: String) -> bool:
	return _upgrades_by_id.has(upgrade_id)

func get_upgrade_count() -> int:
	return _upgrades_by_id.size()

func get_upgrade_ids() -> Array:
	var keys: Array = _upgrades_by_id.keys()
	keys.sort()
	return keys

func get_cost(upgrade_id: String) -> int:
	if not is_known(upgrade_id):
		return -1
	return int(_upgrades_by_id[upgrade_id].get("cost", 0))

func get_requires(upgrade_id: String) -> Array:
	if not is_known(upgrade_id):
		return []
	var variant: Variant = _upgrades_by_id[upgrade_id].get("requires", [])
	if typeof(variant) != TYPE_ARRAY:
		return []
	var out: Array = []
	for r in (variant as Array):
		out.append(str(r))
	return out

func get_effect(upgrade_id: String, effect_key: String, fallback: Variant = 0) -> Variant:
	if not is_known(upgrade_id):
		return fallback
	var effects: Dictionary = _upgrades_by_id[upgrade_id].get("effects", {}) as Dictionary
	if not effects.has(effect_key):
		return fallback
	return effects[effect_key]

func get_display_name(upgrade_id: String) -> String:
	if not is_known(upgrade_id):
		return ""
	return str(_upgrades_by_id[upgrade_id].get("display_name", upgrade_id))

func get_description(upgrade_id: String) -> String:
	if not is_known(upgrade_id):
		return ""
	return str(_upgrades_by_id[upgrade_id].get("description", ""))

## Returns true when the player can currently afford + satisfy the
## prereqs for `upgrade_id`. Reads the player's meta state for currency
## and unlock set; the caller is expected to have already loaded both.
func can_purchase(upgrade_id: String, meta_state) -> Dictionary:
	if not is_known(upgrade_id):
		return {"can": false, "reason": "unknown_upgrade"}
	var cost: int = get_cost(upgrade_id)
	if cost < 0:
		return {"can": false, "reason": "invalid_cost"}
	if meta_state == null:
		return {"can": false, "reason": "no_meta_state"}
	if not meta_state.has_method("get_meta_currency") or not meta_state.has_method("is_hub_upgrade_unlocked"):
		return {"can": false, "reason": "invalid_meta_state"}
	if meta_state.is_hub_upgrade_unlocked(upgrade_id):
		return {"can": false, "reason": "already_owned"}
	var prereqs: Array = get_requires(upgrade_id)
	var missing: Array = []
	for req_id in prereqs:
		if not meta_state.is_hub_upgrade_unlocked(req_id):
			missing.append(req_id)
	if not missing.is_empty():
		return {"can": false, "reason": "missing_prereqs", "missing": missing}
	if int(meta_state.get_meta_currency()) < cost:
		return {"can": false, "reason": "insufficient_currency", "cost": cost, "currency": int(meta_state.get_meta_currency())}
	return {"can": true, "reason": "ok", "cost": cost}

## Attempts to purchase `upgrade_id`. On success: deducts the cost from
## `meta_state` and adds the id to `meta_state.unlocked_hub_upgrade_ids`.
## Returns true on a state change. Idempotent: a second purchase of an
## already-owned upgrade returns false with reason="already_owned".
func purchase(upgrade_id: String, meta_state) -> bool:
	if meta_state == null:
		return false
	var check: Dictionary = can_purchase(upgrade_id, meta_state)
	if not bool(check.get("can", false)):
		return false
	var cost: int = get_cost(upgrade_id)
	if not meta_state.spend_meta_currency(cost):
		return false
	if not meta_state.unlock_hub_upgrade(upgrade_id):
		# Roll back on idempotency miss (defensive — can_purchase already
		# rejected already_owned, but a concurrent mutation between the
		# check and the unlock could race in pathological cases).
		meta_state.add_meta_currency(cost)
		return false
	return true

## Returns the per-upgrade entries (id + display + cost + prereqs + effects)
## for the hub upgrade panel UI.
func get_upgrade_entries(meta_state = null) -> Array:
	var out: Array = []
	for uid in _upgrades_by_id:
		var entry: Dictionary = _upgrades_by_id[uid]
		var cost: int = int(entry.get("cost", 0))
		var prereqs: Array = get_requires(uid)
		var owned: bool = meta_state != null and meta_state.has_method("is_hub_upgrade_unlocked") and meta_state.is_hub_upgrade_unlocked(uid)
		var affordable: bool = meta_state != null and meta_state.has_method("get_meta_currency") and int(meta_state.get_meta_currency()) >= cost
		out.append({
			"upgrade_id": uid,
			"display_name": str(entry.get("display_name", uid)),
			"description": str(entry.get("description", "")),
			"cost": cost,
			"requires": prereqs,
			"effects": (entry.get("effects", {}) as Dictionary).duplicate(true),
			"owned": owned,
			"affordable": affordable,
		})
	out.sort_custom(func(a, b): return String(a.get("upgrade_id", "")) < String(b.get("upgrade_id", "")))
	return out

## Composes the player's effective XP multipliers (per category) by
## starting from 1.0 and applying every owned hub upgrade's
## `xp_multiplier_bonus`. Returns {category -> float}.
func compose_xp_multipliers(meta_state) -> Dictionary:
	var out: Dictionary = {
		"technical": 1.0,
		"medical": 1.0,
		"navigation": 1.0,
		"survival": 1.0,
		"social": 1.0,
	}
	if meta_state == null or not meta_state.has_method("is_hub_upgrade_unlocked"):
		return out
	for uid in _upgrades_by_id:
		if not meta_state.is_hub_upgrade_unlocked(uid):
			continue
		var bonus: Variant = get_effect(uid, "xp_multiplier_bonus", {})
		if typeof(bonus) != TYPE_DICTIONARY:
			continue
		for cat in bonus:
			var mult: float = float(bonus[cat])
			out[String(cat)] = float(out.get(String(cat), 1.0)) * mult
	return out

## Composes the player's effective starting-skill bonuses by collecting
## every owned hub upgrade's `starting_skill_bonus`. Returns
## {skill_id -> int}. Applied on a fresh run by the playable ship.
func compose_starting_skill_bonuses(meta_state) -> Dictionary:
	var out: Dictionary = {}
	if meta_state == null or not meta_state.has_method("is_hub_upgrade_unlocked"):
		return out
	for uid in _upgrades_by_id:
		if not meta_state.is_hub_upgrade_unlocked(uid):
			continue
		var bonus: Variant = get_effect(uid, "starting_skill_bonus", {})
		if typeof(bonus) != TYPE_DICTIONARY:
			continue
		for sid in bonus:
			var v: int = int(bonus[sid])
			out[String(sid)] = int(out.get(String(sid), 0)) + v
	return out

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Hub Upgrades Catalog: %d" % _upgrades_by_id.size())
	return lines