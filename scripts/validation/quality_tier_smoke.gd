extends SceneTree

const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

## QUALITY TIER PASS
## Validates QualityTierResolver thresholds, score computation, and tier mapping.

func _initialize() -> void:
	var resolver = QualityTierResolverScript.new()

	# Static score computation
	var score: float = QualityTierResolverScript.compute_score(0.5, 2, 1, true)
	assert(score > 0.0 and score <= 1.0, "score out of range")

	# Tier thresholds
	assert(QualityTierResolverScript.tier_for_score(0.0) == "poor", "0.0 should be poor")
	assert(QualityTierResolverScript.tier_for_score(0.34) == "poor", "0.34 should be poor")
	assert(QualityTierResolverScript.tier_for_score(0.35) == "standard", "0.35 should be standard")
	assert(QualityTierResolverScript.tier_for_score(0.55) == "good", "0.55 should be good")
	assert(QualityTierResolverScript.tier_for_score(0.75) == "excellent", "0.75 should be excellent")
	assert(QualityTierResolverScript.tier_for_score(0.90) == "masterwork", "0.90 should be masterwork")
	assert(QualityTierResolverScript.tier_for_score(1.0) == "masterwork", "1.0 should be masterwork")

	# Multipliers exist and are positive
	for tier in ["poor", "standard", "good", "excellent", "masterwork"]:
		var mult: float = resolver.multiplier_for_tier(tier)
		assert(mult > 0.0, "multiplier for %s should be positive" % tier)

	# Full resolve
	var result: Dictionary = resolver.resolve(0.6, 3, 2, true)
	assert(result.has("tier"), "resolve missing tier")
	assert(result.has("multiplier"), "resolve missing multiplier")
	assert(result.has("score"), "resolve missing score")
	assert(result["score"] is float and result["score"] > 0.0, "resolve score invalid")

	# Power bonus matters
	var with_power: Dictionary = resolver.resolve(0.5, 0, 0, true)
	var without_power: Dictionary = resolver.resolve(0.5, 0, 0, false)
	assert(with_power["score"] > without_power["score"], "power should boost score")

	print("QUALITY TIER PASS tiers=5 resolve=true power_bonus=true")
	quit()
