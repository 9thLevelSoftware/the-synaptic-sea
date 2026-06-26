extends RefCounted
class_name FoodState

## Pure model for individual food item freshness and consumable effects.
## Per-item spoilage stage (Fresh -> Stale -> Rotten) affects hunger,
## sanity, and sickness risk when consumed. Never touches the scene tree.

const STALE_THRESHOLD: float = 0.5    # >50% elapsed = Stale
const ROTTEN_THRESHOLD: float = 1.0   # >=100% elapsed = Rotten

enum Stage { FRESH, STALE, ROTTEN }

var item_id: String = ""
var display_name: String = ""
var stage: int = Stage.FRESH
var elapsed_seconds: float = 0.0
var total_spoilage_seconds: float = 3600.0
var hunger_restore: float = 0.0
var thirst_restore: float = 0.0
var sanity_restore: float = 0.0
var fresh_multiplier: float = 1.0
var stale_multiplier: float = 0.6
var rotten_multiplier: float = 0.2
var rotten_sickness_risk: float = 0.25
var icon: String = ""

func configure(config: Dictionary) -> void:
	item_id = str(config.get("item_id", ""))
	display_name = str(config.get("display_name", item_id))
	stage = Stage.FRESH
	elapsed_seconds = 0.0
	total_spoilage_seconds = maxf(1.0, float(config.get("spoilage_seconds", 3600.0)))
	hunger_restore = float(config.get("hunger_restore", 0.0))
	thirst_restore = float(config.get("thirst_restore", 0.0))
	sanity_restore = float(config.get("sanity_restore", 0.0))
	fresh_multiplier = float(config.get("fresh_multiplier", 1.0))
	stale_multiplier = float(config.get("stale_multiplier", 0.6))
	rotten_multiplier = float(config.get("rotten_multiplier", 0.2))
	rotten_sickness_risk = float(config.get("rotten_sickness_risk", 0.25))
	icon = str(config.get("icon", ""))

func tick(delta_seconds: float) -> bool:
	if delta_seconds <= 0.0:
		return false
	var before: int = stage
	elapsed_seconds += delta_seconds
	var progress: float = elapsed_seconds / total_spoilage_seconds
	if progress >= ROTTEN_THRESHOLD:
		stage = Stage.ROTTEN
	elif progress >= STALE_THRESHOLD:
		stage = Stage.STALE
	else:
		stage = Stage.FRESH
	return stage != before

func get_effective_restores() -> Dictionary:
	var mult: float = fresh_multiplier
	if stage == Stage.STALE:
		mult = stale_multiplier
	elif stage == Stage.ROTTEN:
		mult = rotten_multiplier
	return {
		"hunger": hunger_restore * mult,
		"thirst": thirst_restore * mult,
		"sanity": sanity_restore * mult,
		"sickness_risk": rotten_sickness_risk if stage == Stage.ROTTEN else 0.0,
	}

func consume() -> Dictionary:
	var effect: Dictionary = get_effective_restores()
	# Consumption removes the item; the caller decrements inventory.
	return effect

func get_summary() -> Dictionary:
	return {
		"item_id": item_id,
		"display_name": display_name,
		"stage": stage,
		"elapsed_seconds": elapsed_seconds,
		"total_spoilage_seconds": total_spoilage_seconds,
		"hunger_restore": hunger_restore,
		"thirst_restore": thirst_restore,
		"sanity_restore": sanity_restore,
		"fresh_multiplier": fresh_multiplier,
		"stale_multiplier": stale_multiplier,
		"rotten_multiplier": rotten_multiplier,
		"rotten_sickness_risk": rotten_sickness_risk,
		"icon": icon,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_id: String = str(summary.get("item_id", item_id))
	if new_id != item_id:
		item_id = new_id
		changed = true
	var new_stage: int = int(summary.get("stage", stage))
	if new_stage != stage:
		stage = new_stage
		changed = true
	var new_elapsed: float = float(summary.get("elapsed_seconds", elapsed_seconds))
	if absf(new_elapsed - elapsed_seconds) > 0.001:
		elapsed_seconds = new_elapsed
		changed = true
	var new_total: float = float(summary.get("total_spoilage_seconds", total_spoilage_seconds))
	if absf(new_total - total_spoilage_seconds) > 0.001:
		total_spoilage_seconds = maxf(1.0, new_total)
		changed = true
	var new_hunger: float = float(summary.get("hunger_restore", hunger_restore))
	if absf(new_hunger - hunger_restore) > 0.001:
		hunger_restore = new_hunger
		changed = true
	var new_thirst: float = float(summary.get("thirst_restore", thirst_restore))
	if absf(new_thirst - thirst_restore) > 0.001:
		thirst_restore = new_thirst
		changed = true
	var new_sanity: float = float(summary.get("sanity_restore", sanity_restore))
	if absf(new_sanity - sanity_restore) > 0.001:
		sanity_restore = new_sanity
		changed = true
	return changed

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var stage_name: String = "FRESH"
	if stage == Stage.STALE:
		stage_name = "STALE"
	elif stage == Stage.ROTTEN:
		stage_name = "ROTTEN"
	lines.append("Food: %s [%s]" % [display_name, stage_name])
	var pct: int = int(round((elapsed_seconds / maxf(1.0, total_spoilage_seconds)) * 100.0))
	lines.append("  spoil=%d%%" % pct)
	var eff: Dictionary = get_effective_restores()
	lines.append("  hunger=+%.1f thirst=+%.1f sanity=%+.1f" % [
		eff["hunger"], eff["thirst"], eff["sanity"]
	])
	if eff["sickness_risk"] > 0.0:
		lines.append("  sickness_risk=%.0f%%" % (eff["sickness_risk"] * 100.0))
	return lines

static func stage_name(s: int) -> String:
	if s == Stage.STALE:
		return "STALE"
	elif s == Stage.ROTTEN:
		return "ROTTEN"
	return "FRESH"
