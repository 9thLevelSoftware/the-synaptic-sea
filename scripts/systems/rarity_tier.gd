extends RefCounted
class_name RarityTier

const ORDER: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]
const LABELS: Dictionary = {
	"common": "Common",
	"uncommon": "Uncommon",
	"rare": "Rare",
	"epic": "Epic",
	"legendary": "Legendary",
}
const COLORS: Dictionary = {
	"common": Color("#9AA4AF"),
	"uncommon": Color("#55C271"),
	"rare": Color("#4D9BFF"),
	"epic": Color("#A56DFF"),
	"legendary": Color("#FFB347"),
}
const WEIGHT_MULTIPLIERS: Dictionary = {
	"common": 1.00,
	"uncommon": 0.72,
	"rare": 0.45,
	"epic": 0.22,
	"legendary": 0.10,
}
const DEFAULT_RARITY: String = "common"

static func normalize(value: String) -> String:
	var rarity: String = value.strip_edges().to_lower()
	return rarity if ORDER.has(rarity) else DEFAULT_RARITY

static func label(value: String) -> String:
	var rarity: String = normalize(value)
	return str(LABELS.get(rarity, LABELS[DEFAULT_RARITY]))

static func color(value: String) -> Color:
	var rarity: String = normalize(value)
	return COLORS.get(rarity, COLORS[DEFAULT_RARITY])

static func hex(value: String) -> String:
	return color(value).to_html()

static func weight_multiplier(value: String) -> float:
	var rarity: String = normalize(value)
	return float(WEIGHT_MULTIPLIERS.get(rarity, 1.0))

static func rank(value: String) -> int:
	return ORDER.find(normalize(value))

static func max_rarity(a: String, b: String) -> String:
	return normalize(a) if rank(a) >= rank(b) else normalize(b)

static func from_roll(score: float) -> String:
	var s: float = clampf(score, 0.0, 1.0)
	if s >= 0.96:
		return "legendary"
	if s >= 0.84:
		return "epic"
	if s >= 0.64:
		return "rare"
	if s >= 0.34:
		return "uncommon"
	return "common"

static func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for rarity in ORDER:
		lines.append("%s=%s" % [rarity, hex(rarity)])
	return lines
