extends RefCounted
class_name WebInfestationState

## Domain 4: the biomatter-web infestation that slowly devours a ship's hull.
## The hub is trapped in the Sargasso web (attached_to_web = true by default);
## coverage grows over time and translates into hull damage applied by the
## coordinator. A ship cut free from the web sees its coverage recede.
##
## Pure data — never touches the scene tree. A CONTINUOUS growth/drain hazard,
## not phase-based: the same exemption class as OxygenState, so it is NOT part of
## the PhaseTimer hazard_contract_smoke. It carries a hazard_kind discriminator
## purely for save-load robustness (apply_summary rejects a mismatched kind).

const HAZARD_KIND: String = "web_infestation"

var attached_to_web: bool = true
var coverage: float = 0.0          # 0..1 infestation level
var growth_rate: float = 0.02      # coverage/sec while attached
var recession_rate: float = 0.05   # coverage/sec while cut free
var damage_rate: float = 0.03      # hull damage/sec at full coverage
var contact_boost: float = 0.03    # extra growth/sec while docked to an attached derelict

func configure(config: Dictionary) -> void:
	growth_rate = maxf(0.0, float(config.get("growth_rate", 0.02)))
	recession_rate = maxf(0.0, float(config.get("recession_rate", 0.05)))
	damage_rate = maxf(0.0, float(config.get("damage_rate", 0.03)))
	contact_boost = maxf(0.0, float(config.get("contact_boost", 0.03)))
	coverage = clampf(float(config.get("seed_coverage", 0.0)), 0.0, 1.0)
	attached_to_web = bool(config.get("attached_to_web", true))

## Advance coverage by one tick and return the hull-damage magnitude for this tick.
## `contact` true = currently docked to a still-web-attached derelict (faster growth).
func tick(delta: float, contact: bool) -> float:
	if delta <= 0.0:
		return 0.0
	if attached_to_web:
		var rate: float = growth_rate + (contact_boost if contact else 0.0)
		coverage = clampf(coverage + rate * delta, 0.0, 1.0)
	else:
		coverage = clampf(coverage - recession_rate * delta, 0.0, 1.0)
	return coverage * damage_rate * delta

func cut_free() -> void:
	attached_to_web = false

func get_summary() -> Dictionary:
	return {
		"hazard_kind": HAZARD_KIND,
		"attached_to_web": attached_to_web,
		"coverage": coverage,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if str(summary.get("hazard_kind", "")) != HAZARD_KIND:
		return false
	attached_to_web = bool(summary.get("attached_to_web", attached_to_web))
	coverage = clampf(float(summary.get("coverage", coverage)), 0.0, 1.0)
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if coverage > 0.0:
		var tag: String = "SPREADING" if attached_to_web else "RECEDING"
		lines.append("Web Infestation %d%% [%s]" % [int(round(coverage * 100.0)), tag])
	return lines
