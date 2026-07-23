extends RefCounted
class_name AudioEventSeam

## Audio event id catalog (REQ-AU-001, ADR-0029).
##
## Every gameplay audio event is a typed constant in this table. The SfxEventRouter
## and AudioManager route through these ids; callers never reach into buses
## directly. New events are added here so the table is the single source of truth
## for "what audio ids exist".
##
## Categories:
##   SFX_*      routed to bus=sfx (gameplay SFX)
##   UI_*       routed to bus=ui  (HUD / panel feedback)
##   META_*     routed to bus=meta (meta-event dispatches)
##   VOICE_*    routed to bus=voice (audio-log playback)
##   AMB_*      routed to bus=ambient (room-role ambient layers)

const SFX_TOOL_PICKUP: StringName = &"sfx.tool.pickup"
const SFX_TOOL_USE: StringName = &"sfx.tool.use"
const SFX_SUIT_BREATH: StringName = &"sfx.suit.breath"
const SFX_DOOR_OPEN: StringName = &"sfx.door.open"
const SFX_DOOR_CLOSE: StringName = &"sfx.door.close"
const SFX_FIRE_CRACKLE: StringName = &"sfx.fire.crackle"
const SFX_ARC_ZAP: StringName = &"sfx.arc.zap"
const SFX_FOOTSTEP: StringName = &"sfx.footstep"
const SFX_DROP_ITEM: StringName = &"sfx.drop.item"
const SFX_DOCK_LAND: StringName = &"sfx.dock.land"
const SFX_HALLUCINATION_WHISPER: StringName = &"sfx.hallucination.whisper"
## PKG-D10: pillar / combat / work verbs (placeholder clips OK).
const SFX_WORK_CUT: StringName = &"sfx.work.cut"
const SFX_WORK_WELD: StringName = &"sfx.work.weld"
const SFX_WORK_PATCH: StringName = &"sfx.work.patch"
const SFX_WORK_UNBOLT: StringName = &"sfx.work.unbolt"
const SFX_WORK_PRY: StringName = &"sfx.work.pry"
const SFX_WORK_SPLICE: StringName = &"sfx.work.splice"
const SFX_WORK_HARVEST: StringName = &"sfx.work.harvest"
const SFX_WORK_PLANT: StringName = &"sfx.work.plant"
const SFX_WORK_MOUNT: StringName = &"sfx.work.mount"
const SFX_COMBAT_HIT: StringName = &"sfx.combat.hit"
const SFX_COMBAT_THREAT_ALERT: StringName = &"sfx.combat.threat_alert"
const SFX_WOUND_BANDAGE: StringName = &"sfx.wound.bandage"
const SFX_WOUND_TREAT: StringName = &"sfx.wound.treat"
const SFX_CRAFT_COMPLETE: StringName = &"sfx.craft.complete"
const SFX_REPAIR_COMPLETE: StringName = &"sfx.repair.complete"
const SFX_SANITY_AMBIENT: StringName = &"sfx.sanity.ambient"
const SFX_SANITY_HUD: StringName = &"sfx.sanity.hud_glitch"
const SFX_SANITY_PHANTOM: StringName = &"sfx.sanity.phantom"

const UI_INVENTORY_OPEN: StringName = &"ui.inventory.open"
const UI_WORK_PROGRESS: StringName = &"ui.work.progress"
const UI_WOUNDS_OPEN: StringName = &"ui.wounds.open"
const UI_CHART_ROUTE: StringName = &"ui.chart.route"
const UI_SHIP_MOD_OPEN: StringName = &"ui.ship_mod.open"
const UI_SHIP_MOD_INSTALL: StringName = &"ui.ship_mod.install"
const UI_SHIP_MOD_UNINSTALL: StringName = &"ui.ship_mod.uninstall"
const UI_INVENTORY_CLOSE: StringName = &"ui.inventory.close"
const UI_PANEL_OPEN: StringName = &"ui.panel.open"
const UI_PANEL_CLOSE: StringName = &"ui.panel.close"
const UI_OBJECTIVE_ADVANCE: StringName = &"ui.objective.advance"
const UI_SAVE: StringName = &"ui.save"
const UI_LOAD: StringName = &"ui.load"
const UI_VITALS_LOW: StringName = &"ui.vitals.low"

const META_BEACON_DISTRESS: StringName = &"meta.beacon.distress"
const META_BIOMATTER_PULSE: StringName = &"meta.biomatter.pulse"
const META_HULL_GROAN: StringName = &"meta.hull.groan"
const META_REACTOR_HUM: StringName = &"meta.reactor.hum"

const VOICE_LOG_PLAY: StringName = &"voice.log.play"

const AMB_CARGO: StringName = &"amb.cargo"
const AMB_ENGINE: StringName = &"amb.engine"
const AMB_MED_BAY: StringName = &"amb.med_bay"
const AMB_CREW_QUARTERS: StringName = &"amb.crew_quarters"
const AMB_DOCKING: StringName = &"amb.docking"

## All SFX-prefixed ids — useful for static catalog checks.
const ALL_SFX_IDS: Array[StringName] = [
	SFX_TOOL_PICKUP, SFX_TOOL_USE, SFX_SUIT_BREATH, SFX_DOOR_OPEN, SFX_DOOR_CLOSE,
	SFX_FIRE_CRACKLE, SFX_ARC_ZAP, SFX_FOOTSTEP, SFX_DROP_ITEM, SFX_DOCK_LAND,
	SFX_HALLUCINATION_WHISPER,
	SFX_WORK_CUT, SFX_WORK_WELD, SFX_WORK_PATCH, SFX_WORK_UNBOLT, SFX_WORK_PRY,
	SFX_WORK_SPLICE, SFX_WORK_HARVEST, SFX_WORK_PLANT, SFX_WORK_MOUNT,
	SFX_COMBAT_HIT, SFX_COMBAT_THREAT_ALERT,
	SFX_WOUND_BANDAGE, SFX_WOUND_TREAT,
	SFX_CRAFT_COMPLETE, SFX_REPAIR_COMPLETE,
	SFX_SANITY_AMBIENT, SFX_SANITY_HUD, SFX_SANITY_PHANTOM,
]
const ALL_UI_IDS: Array[StringName] = [
	UI_INVENTORY_OPEN, UI_INVENTORY_CLOSE, UI_PANEL_OPEN, UI_PANEL_CLOSE, UI_OBJECTIVE_ADVANCE,
	UI_SAVE, UI_LOAD, UI_VITALS_LOW,
	UI_WORK_PROGRESS, UI_WOUNDS_OPEN, UI_CHART_ROUTE,
	UI_SHIP_MOD_OPEN, UI_SHIP_MOD_INSTALL, UI_SHIP_MOD_UNINSTALL,
]

## Verb string (WorkAction definition.verb) -> event id for PKG-D10 coverage.
const WORK_VERB_TO_SFX: Dictionary = {
	"cut": SFX_WORK_CUT,
	"weld": SFX_WORK_WELD,
	"patch": SFX_WORK_PATCH,
	"unbolt": SFX_WORK_UNBOLT,
	"pry": SFX_WORK_PRY,
	"splice": SFX_WORK_SPLICE,
	"harvest": SFX_WORK_HARVEST,
	"plant": SFX_WORK_PLANT,
	"mount": SFX_WORK_MOUNT,
	"suppress": SFX_TOOL_USE,
	"craft": SFX_CRAFT_COMPLETE,
}


static func sfx_for_work_verb(verb: String) -> StringName:
	var key: String = verb.to_lower()
	if WORK_VERB_TO_SFX.has(key):
		return WORK_VERB_TO_SFX[key]
	return SFX_TOOL_USE
const ALL_META_IDS: Array[StringName] = [
	META_BEACON_DISTRESS, META_BIOMATTER_PULSE, META_HULL_GROAN, META_REACTOR_HUM,
]
const ALL_VOICE_IDS: Array[StringName] = [VOICE_LOG_PLAY]
const ALL_AMBIENT_IDS: Array[StringName] = [AMB_CARGO, AMB_ENGINE, AMB_MED_BAY, AMB_CREW_QUARTERS, AMB_DOCKING]

## Bus id constants. Mirrors AudioBusConfig bus ids so callers reference a
## single source of truth instead of repeating string literals.
const BUS_MASTER: StringName = &"master"
const BUS_SFX: StringName = &"sfx"
const BUS_MUSIC: StringName = &"music"
const BUS_VOICE: StringName = &"voice"
const BUS_UI: StringName = &"ui"
const BUS_AMBIENT: StringName = &"ambient"
const BUS_META: StringName = &"meta"
const ALL_BUS_IDS: Array[StringName] = [BUS_MASTER, BUS_SFX, BUS_MUSIC, BUS_VOICE, BUS_UI, BUS_AMBIENT, BUS_META]

## Room role ids for ambient zone mapping (REQ-AU-003).
const ROOM_ROLE_CARGO: StringName = &"cargo"
const ROOM_ROLE_ENGINE: StringName = &"engine"
const ROOM_ROLE_MED_BAY: StringName = &"med_bay"
const ROOM_ROLE_CREW_QUARTERS: StringName = &"crew_quarters"
const ROOM_ROLE_DOCKING: StringName = &"docking"
const ALL_ROOM_ROLES: Array[StringName] = [
	ROOM_ROLE_CARGO, ROOM_ROLE_ENGINE, ROOM_ROLE_MED_BAY,
	ROOM_ROLE_CREW_QUARTERS, ROOM_ROLE_DOCKING,
]

## Music state names (REQ-AU-004).
const MUSIC_STATE_EXPLORATION: StringName = &"EXPLORATION"
const MUSIC_STATE_TENSION: StringName = &"TENSION"
const MUSIC_STATE_COMBAT: StringName = &"COMBAT"
const MUSIC_STATE_CRITICAL: StringName = &"CRITICAL"
const ALL_MUSIC_STATES: Array[StringName] = [
	MUSIC_STATE_EXPLORATION, MUSIC_STATE_TENSION, MUSIC_STATE_COMBAT, MUSIC_STATE_CRITICAL,
]

## Music layer ids. The DynamicMusicState machine owns a per-state gain set;
## layer ids are stable strings so the crossfade scheduler can keep state
## across state transitions.
const MUSIC_LAYER_BASE: StringName = &"layer.base"
const MUSIC_LAYER_TENSION_DRONE: StringName = &"layer.tension_drone"
const MUSIC_LAYER_COMBAT_PERCUSSION: StringName = &"layer.combat_percussion"
const MUSIC_LAYER_CRITICAL_PAD: StringName = &"layer.critical_pad"
const ALL_MUSIC_LAYERS: Array[StringName] = [
	MUSIC_LAYER_BASE, MUSIC_LAYER_TENSION_DRONE,
	MUSIC_LAYER_COMBAT_PERCUSSION, MUSIC_LAYER_CRITICAL_PAD,
]

## Meta-event types (REQ-AU-007). MetaEventState keeps a schedule of these.
const META_EVENT_BEACON: StringName = &"beacon_distress"
const META_EVENT_PULSE: StringName = &"biomatter_pulse"
const META_EVENT_GROAN: StringName = &"hull_groan"
