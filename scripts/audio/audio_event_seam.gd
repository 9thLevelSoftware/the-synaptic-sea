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

const UI_INVENTORY_OPEN: StringName = &"ui.inventory.open"
const UI_INVENTORY_CLOSE: StringName = &"ui.inventory.close"
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
]
const ALL_UI_IDS: Array[StringName] = [
	UI_INVENTORY_OPEN, UI_INVENTORY_CLOSE, UI_OBJECTIVE_ADVANCE,
	UI_SAVE, UI_LOAD, UI_VITALS_LOW,
]
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
