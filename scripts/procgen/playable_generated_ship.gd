extends Node3D
class_name PlayableGeneratedShip

const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")
const IsoCameraRigScript := preload("res://scripts/camera/iso_camera_rig.gd")
const InteractableScript := preload("res://scripts/interaction/interactable.gd")
const ObjectiveTrackerScript := preload("res://scripts/ui/objective_tracker.gd")
const ScannerPanelScript := preload("res://scripts/ui/scanner_panel.gd")
const ChartPanelScript := preload("res://scripts/ui/chart_panel.gd")
const WebChartStateScript := preload("res://scripts/systems/web_chart_state.gd")
const InventoryPanelScript := preload("res://scripts/ui/inventory_panel.gd")
const AccessibilitySettingsScript := preload("res://scripts/ui/accessibility_settings.gd")
const MenuCoordinatorScript := preload("res://scripts/ui/menu_coordinator.gd")
const ReadabilityPropFactoryScript := preload("res://scripts/procgen/readability_prop_factory.gd")
const RouteControlStateScript := preload("res://scripts/systems/route_control_state.gd")
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const ToolPickupScript := preload("res://scripts/tools/tool_pickup.gd")
const ElectricalArcStateScript := preload("res://scripts/systems/electrical_arc_state.gd")
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveSlotStateScript := preload("res://scripts/systems/save_slot_state.gd")
const PermadeathResolverScript := preload("res://scripts/systems/permadeath_resolver.gd")
# Timed/rotating autosave loop (ADR-0031/0032). Owned + ticked here so the
# borderline-Bucket-1 AutosavePolicy model is finally wired into the live run.
const AutosavePolicyScript := preload("res://scripts/systems/autosave_policy.gd")
# Bucket 3 meta-screen shell deps (constructed here, injected into MenuCoordinator).
const LocalizationCatalogScript := preload("res://scripts/systems/localization_catalog.gd")
const BuildMetadataStateScript := preload("res://scripts/systems/build_metadata_state.gd")
const DemoScopeGateScript := preload("res://scripts/systems/demo_scope_gate.gd")
const SaveLoadMenuScript := preload("res://scripts/ui/save_load_menu.gd")
const AchievementStateScript := preload("res://scripts/systems/achievement_state.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const SynapticSeaWorldScript := preload("res://scripts/systems/synaptic_sea_world.gd")
const ScannerStateScript := preload("res://scripts/systems/scanner_state.gd")
const TravelControllerScript := preload("res://scripts/systems/travel_controller.gd")
const LootContainerScript := preload("res://scripts/tools/loot_container.gd")
const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")
const LootDistributionScript := preload("res://scripts/systems/loot_distribution.gd")
const UniqueItemStateScript := preload("res://scripts/systems/unique_item_state.gd")
const RarityTierScript := preload("res://scripts/systems/rarity_tier.gd")
const BiomeProfileScript := preload("res://scripts/procgen/biome_profile.gd")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const SfxEventRouterScript := preload("res://scripts/systems/sfx_event_router.gd")
const RepairPointScript := preload("res://scripts/tools/repair_point.gd")
const BreachSealPointScript := preload("res://scripts/tools/breach_seal_point.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const FieldCraftingStateScript := preload("res://scripts/systems/field_crafting_state.gd")
const DeconstructionResolverScript := preload("res://scripts/systems/deconstruction_resolver.gd")
const CraftingStationScript := preload("res://scripts/tools/crafting_station.gd")
const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
const ShipOccupancyScript := preload("res://scripts/systems/ship_occupancy.gd")
const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const DockPortBarrierScript := preload("res://scripts/tools/dock_port_barrier.gd")
const BridgeTerminalScript := preload("res://scripts/tools/bridge_terminal.gd")
const HangarBayControlScript := preload("res://scripts/tools/hangar_bay_control.gd")
const CargoHoldControlScript := preload("res://scripts/tools/cargo_hold_control.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")
const CartControlScript := preload("res://scripts/tools/cart_control.gd")
const CartStateScript := preload("res://scripts/systems/cart_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")
const EncumbranceScript := preload("res://scripts/systems/encumbrance.gd")
const PlayerVitalsModelScript := preload("res://scripts/systems/player_vitals_model.gd")
const PlayerVitalsPanelScript := preload("res://scripts/ui/player_vitals_panel.gd")
const HotbarPanelScript := preload("res://scripts/ui/hotbar_panel.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const ThreatManagerScript := preload("res://scripts/systems/threat_manager.gd")
const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const HubUpgradeStateScript := preload("res://scripts/systems/hub_upgrade_state.gd")
const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const UnlockRegistryScript := preload("res://scripts/systems/unlock_registry.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const SanityStateScript := preload("res://scripts/systems/sanity_state.gd")
const HallucinationDirectorScript := preload("res://scripts/systems/hallucination_director.gd")
const HallucinationManagerScript := preload("res://scripts/systems/hallucination_manager.gd")
const HallucinationFXOverlayScript := preload("res://scripts/ui/hallucination_fx_overlay.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const BodyTemperatureStateScript := preload("res://scripts/systems/body_temperature_state.gd")
const StatusEffectsStateScript := preload("res://scripts/systems/status_effects_state.gd")
const SpoilageStateScript := preload("res://scripts/systems/spoilage_state.gd")
# CookingState retired as a coordinator dependency: kitchen meal production flows
# through CraftingState (station_kind=kitchen). cooking_state.gd remains as a
# pure-model leftover for any residual synthesizer-era callers; do not re-wire.
const HydroponicsStateScript := preload("res://scripts/systems/hydroponics_state.gd")
const WaterRecyclerStateScript := preload("res://scripts/systems/water_recycler_state.gd")
const PowerGridStateScript := preload("res://scripts/systems/power_grid_state.gd")
const LifeSupportExpandedStateScript := preload("res://scripts/systems/life_support_state.gd")
const HullIntegrityStateScript := preload("res://scripts/systems/hull_integrity_state.gd")
const WebInfestationStateScript := preload("res://scripts/systems/web_infestation_state.gd")
const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
const ExtinguisherStateScript := preload("res://scripts/systems/extinguisher_state.gd")
const FireSuppressionPointScript := preload("res://scripts/tools/fire_suppression_point.gd")
const ExtinguisherRechargePortScript := preload("res://scripts/tools/extinguisher_recharge_port.gd")
const PropulsionExpandedStateScript := preload("res://scripts/systems/propulsion_state.gd")
const SustenanceStateScript := preload("res://scripts/systems/sustenance_state.gd")
const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")
const ConsumableStateScript := preload("res://scripts/systems/consumable_state.gd")
const MedicineStateScript := preload("res://scripts/systems/medicine_state.gd")
const StimulantStateScript := preload("res://scripts/systems/stimulant_state.gd")
const AddictionStateScript := preload("res://scripts/systems/addiction_state.gd")
const AmmoStateScript := preload("res://scripts/systems/ammo_state.gd")
const UtilityItemResolverScript := preload("res://scripts/systems/utility_item_resolver.gd")
const SealedHatchScript := preload("res://scripts/interaction/sealed_hatch.gd")

signal playable_ready(summary: Dictionary)
signal playable_failed(reason: String)
signal playable_interaction_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String)
signal playable_slice_completed(summary: Dictionary)
## ADR-0043: emitted when the player chooses to leave gameplay back to the
## title screen (pause menu "Quit to Main Menu" or Save & Exit). title_main.gd
## connects to this on every gameplay instantiation (New Game and Continue
## both wire it via _poll_for_playable_started).
signal return_to_title_requested

const DEFAULT_LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const DEFAULT_KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const DEFAULT_GAMEPLAY_SLICE_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
const PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR: float = 0.55
# Phase 5a Task 5: co-presence offset. A traveled derelict's scene_root is placed
# at this world position so the derelict hull sits well clear of the home ship.
# 100 units ensures a generated layout (max radius ~24 units) does not overlap
# the home hull (Task 8 will replace this fixed offset with real DockPorts wiring).
const DERELICT_DOCK_OFFSET := Vector3(100.0, 0.0, 0.0)
# Phase 5b: the lifeboat no longer parks at a fixed anchor offset — it port-docks to
# the home ship's airlock via DockingManager at boot (see _build_lifeboat_at_home).
const ROUTE_GATE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 0.7)
const ROUTE_GATE_VISUAL_COLOR_CLOSED: Color = Color(1.0, 0.22, 0.18, 0.82)
const ROUTE_GATE_VISUAL_COLOR_OPEN: Color = Color(0.18, 0.75, 1.0, 0.18)
const BREACH_ZONE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 1.6)
const BREACH_ZONE_VISUAL_COLOR_OPEN: Color = Color(0.95, 0.32, 0.22, 0.65)
const BREACH_ZONE_VISUAL_COLOR_BLOCKED: Color = Color(0.65, 0.05, 0.05, 0.92)
const BREACH_ZONE_VISUAL_COLOR_SEALED: Color = Color(0.18, 0.55, 1.0, 0.55)
const BREACH_ZONE_FALLBACK_ID: String = "corridor_to_reactor"
const BREACH_ZONE_PROXIMITY_RADIUS: float = 2.4
const BREACH_ZONE_UNSAFE_LABEL_TEXT: String = "OXYGEN LOW"
# Retained for the golden_fire_zone_source_marker_smoke source-of-truth check:
# the golden layout's fire_zones marker `to_room` must equal this constant.
# The authoritative M7-B fire model (FireSuppressionState) renders passable
# per-compartment zones; this constant no longer drives runtime placement.
const FIRE_ZONE_FALLBACK_ROOM_ID: String = "cargo_01"
# REQ-013: electrical-arc zone. Mirrors the fire-zone visual sizing so the
# third hazard reads the same scale on screen; placement is template-
# specific (no fallback room is injected per hazard_type_3.md).
const ARC_ZONE_FALLBACK_ID: String = "side_corridor_arc"
const ARC_ZONE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 1.6)
const ARC_ZONE_VISUAL_COLOR_DISCHARGED: Color = Color(0.35, 0.85, 1.0, 0.35)
const ARC_ZONE_VISUAL_COLOR_ARCING: Color = Color(0.95, 0.32, 1.0, 0.82)
const ARC_ZONE_LABEL_TEXT_DISCHARGED: String = "ARC GROUNDED — CROSS"
const ARC_ZONE_LABEL_TEXT_ARCING: String = "ARC LIVE — WAIT"
const POWER_GRID_CONFIG_PATH: String = "res://data/ship_systems/power_budget_tables.json"
const HULL_COMPARTMENTS_CONFIG_PATH: String = "res://data/ship_systems/hull_compartments.json"
const WEB_INFESTATION_CONFIG_PATH: String = "res://data/ship_systems/web_infestation.json"
const FACILITY_UPGRADES_CONFIG_PATH: String = "res://data/ship_systems/facility_upgrades.json"
const HYDROPONICS_CROPS_CONFIG_PATH: String = "res://data/crops/hydroponics_crops.json"
const SHIP_SUBSYSTEM_TUNING_PATH: String = "res://data/ship_systems/subsystem_tuning.json"
const SEALED_HATCH_COUNT: int = 2

# Objective bridge: which manager subcomponents each objective brings operational.
# restore_systems delivers main power (distribution + battery); stabilize_reactor
# brings the reactor core to full health (extraction). download_logs/recover_supplies
# are narrative beats with no system backing.
const OBJECTIVE_REPAIR_MAP: Dictionary = {
	"restore_systems": [["power", "power_distribution"], ["power", "battery_cells"]],
	"download_logs": [["navigation", "nav_computer"]],
	"stabilize_reactor": [["power", "reactor_core"]],
}

@export var layout_path: String = DEFAULT_LAYOUT_PATH
@export var kit_path: String = DEFAULT_KIT_PATH
@export var gameplay_slice_path: String = DEFAULT_GAMEPLAY_SLICE_PATH
@export var blueprint_path: String = "res://data/procgen/golden/coherent_ship_001/blueprint.json"
@export var starting_class_id: String = "engineer"
var loader
var player
var camera_rig
var hud_layer: CanvasLayer
var scanner_panel   # ScannerPanel
var chart_panel      # ChartPanel
var web_chart_state = WebChartStateScript.new()
var inventory_panel
var tracker
var vitals_model            # PlayerVitalsModel
var vitals_panel            # PlayerVitalsPanel
var hotbar_panel            # HotbarPanel
var menu_coordinator
var interaction_root: Node3D
var affordance_root: Node3D
var affordance_labels: Dictionary = {}
@export var debug_affordance_labels_enabled: bool = false
# A11Y-P1-001: world Label3D pixel_size values for the affordance/landmark,
# breach unsafe, and fire-zone labels all flow through this single settings
# object. Default scale=1.0 reproduces the prior hard-coded pixel_size
# values (0.003 / 0.0035) exactly. Replace via
# apply_accessibility_settings() to enlarge world labels.
var accessibility_settings: RefCounted = AccessibilitySettingsScript.new()
var affordance_props: Dictionary = {}
var interactables: Array = []
var objective_completion_count: int = 0
var current_objective_sequence: int = 1
var slice_complete: bool = false
var ready_summary: Dictionary = {}
var playable_started: bool = false
var last_failure_reason: String = ""
var ship_systems_manager   # ShipSystemsManager (untyped: class_name globals unreliable under --headless --script)
var player_progression   # PlayerProgressionState (untyped: class_name unreliable headless)
var training_event_bus   # TrainingEventBus (REQ-PM-002 / ADR-0033)
var skill_tree_state     # SkillTreeState (REQ-PM-003)
var hub_upgrade_state    # HubUpgradeState (REQ-PM-007)
var meta_progression_state # MetaProgressionState (REQ-PM-006)
var unlock_registry      # UnlockRegistry (REQ-PM-009)
var current_ship           # ShipInstance (untyped: class_name globals unreliable headless)
var current_occupancy      # ShipInstance the player currently occupies (defaults to home_ship)
var synaptic_sea_world         # SynapticSeaWorld
var scanner_state          # ScannerState
var travel_controller      # TravelController
var ship_generator         # ShipGenerator (injected into travel)
# True while the player is aboard a traveled derelict (not the starting ship).
# Gates the starting-ship hazard/objective _process so the unoccupied starting
# ship does not keep simulating in the background.
var away_from_start: bool = false
# Sub-project #1 (world persistence): every visited derelict is retained by
# marker_id so its mutable state survives leaving. Only the ACTIVE ship has a
# live scene_root; a derelict's geometry is regenerated from seed on revisit
# while its systems_manager (and later objective/hazard/loot summaries) ride the
# retained ShipInstance.
var visited_ships: Dictionary = {}          # marker_id -> ShipInstance
var home_ship = null                        # the home ShipInstance (marker_id "")
# Live Persistent Ships Phase 1: monotonic in-run simulation clock (seconds).
# Accumulates every _process frame (before branching) so ships can stamp
# last_sim_time against it and be fast-forwarded by elapsed world_time on
# revisit (Phase 4 catch-up). Persisted in WorldSnapshot (additive).
var world_time: float = 0.0
# ADR-0046: accumulated in-run play time (seconds). Unlike world_time it
# only counts frames where the slice is actually playable (started, not
# complete), so menu/dead time is excluded. Ticked in _process BEFORE the
# home/away branch split so both branches count; captured into
# RunSnapshot.play_time_seconds and restored by _apply_run_snapshot.
var run_play_time_seconds: float = 0.0
# Phase 5a Task 7: the physical lifeboat docked to the starting derelict.
# Port-docked to the home ship's airlock at boot; shares ship_systems_manager with it.
var lifeboat_ship = null                    # ShipInstance (docked to home_ship)
var piloted_ship = null                     # the ShipInstance the player currently pilots (lifeboat or any claimed working vessel)
# Phase 5b Task 5: the active host's closed dock-seam barriers (Array[DockPortBarrier]).
# Spawned closed when the piloted ship docks to a host; the player breaches one to board.
var dock_barriers: Array = []
const PLAYER_LOCAL_ID := "player_local"
var bridge_terminals: Array = []
var hangar_controls: Array = []             # Array[HangarBayControl]
var cargo_hold_controls: Array = []         # Array[CargoHoldControl]
var cart_controls: Array = []               # Array[CartControl]
var grabbed_cart = null                     # CartState currently pushed by the player (or null)
# Sub-project #2: the active derelict's objective interactables live under a
# dedicated root (empty while on the home ship). Separate from the home gameplay
# roots so it stays attached when away_from_start.
var derelict_objective_root: Node3D = null
var derelict_interactables: Array = []
# Sub-project #3: scattered loot containers for the active derelict.
var loot_container_root: Node3D = null
var loot_containers: Array = []
# Domain 5: sealed hatches on the active derelict (locked passages the player bypasses
# with utility flags: lockpick for mechanical, hack_chip for electronic).
var sealed_hatches: Array = []
# Sub-project #4: timed repair points for damaged subcomponents.
var repair_point_root: Node3D = null
var repair_points: Array = []
# M7-A Task 5: breach seal points for breached hull compartments.
var breach_seal_points: Array = []
# M7-B Task 7: authoritative fire renders as PASSABLE per-compartment Area3D
# zones (visual + lookup only; never a collision blocker). compartment_id -> Area3D.
var fire_zone_nodes: Dictionary = {}
# M7-B Task 9: manual extinguish nodes (one per burning compartment) + the single
# home/lifeboat extinguisher recharge port. Tracked here so they share the fire
# zone build/clear lifecycle and the interact dispatcher precedence.
var fire_suppression_points: Array = []
var extinguisher_recharge_port  # ExtinguisherRechargePort
const FIRE_COMPARTMENT_SYSTEM := {
	"bridge": "navigation",
	"engineering": "power",
	"hydroponics": "life_support",
	"cargo": "",
}
# Maps a room ROLE to the hull/fire compartment it belongs to. Only these
# compartments exist (data/ship_systems/hull_compartments.json + FIRE_COMPARTMENT_SYSTEM),
# so variant hazards on other roles are loot/dressing-only.
const COMPARTMENT_FOR_ROLE := {
	"bridge": "bridge",
	"cockpit": "bridge",
	"engineering": "engineering",
	"reactor": "engineering",
	"engine_bay": "engineering",
	"hydroponics": "hydroponics",
	"cargo": "cargo",
	"storage": "cargo",
}
const RoomVariantSelectorHazardScript := preload("res://scripts/procgen/room_variant_selector.gd")
const OXYGEN_MIN_FOR_FIRE: float = 5.0
const FIRE_HEALTH_DRAIN_PER_SECOND: float = 2.0
const FIRE_SYSTEM_DAMAGE_PER_SECOND: float = 0.05
# Derelict-side fire: only ~1 in 7 boarded derelicts present any fire (deterministic per
# seed). Fire is one of several possible derelict conditions, not a default.
const FIRE_PRESENCE_PERCENT: int = 15
# ADR-0038: crafting / salvage economy wired into the live run. These pure models are
# coordinator-owned and ticked from _process; the station nodes are the player-reachable seam.
var crafting_state                          # CraftingState
var material_state                          # MaterialState
var field_crafting_state                    # FieldCraftingState
var deconstruction_resolver                 # DeconstructionResolver
var crafting_station_root: Node3D = null
var crafting_stations: Array = []
const CRAFTING_STATION_KINDS: Array[String] = ["fabricator", "medbay", "kitchen", "synthesizer", "workbench", "salvage"]
var production_stations: Array = []
var _loot_tables: Dictionary = {}
var _salvage_loot_tables: Dictionary = {}   # objective_id -> loot_table key
var unique_item_state
var _loot_biome_ids_cache: Array[String] = []
var _last_loot_feedback_line: String = ""
# REQ-AU-001..010: most-recent audio caption + its remaining display time.
# Mirrors the _last_loot_feedback_line pattern: no new HUD framework, just
# another line folded into _combined_system_status_lines(). Multiple
# captions arriving in one frame keep only the most recent (pump order).
var _last_caption_line: String = ""
var _last_tooltip_focus_subject_id: String = ""
var _caption_expiry_seconds: float = 0.0
var _home_player_position: Vector3 = Vector3.ZERO
# Narrative objective flags with no manager backing (supplies/logs). Set on
# completion; persisted in the snapshot; read by _manager_compat_summary().
var completed_objective_types: Dictionary = {}
var route_control_state: RouteControlState
var route_control_root: Node3D
var route_gate_nodes: Array = []
var oxygen_state: OxygenState
var oxygen_root: Node3D
var breach_zone_node: StaticBody3D
var unsafe_room_marker: Label3D
# --- Inventory / Tool pickup integration -------------------------------------
# REQ-007: a single ToolPickup carrying the portable_oxygen_pump lives in a
# fixed side room (tool_storage_01 if the loader defines it, otherwise a
# fallback position near the player start). Acquiring the pickup adds the
# tool id to InventoryState exactly once; OxygenState reads the inventory
# summary each frame to halve the drain rate inside an unsealed breach.
#
# REQ-014: a second ToolPickup carrying the junction_calibrator lives in
# a different side room (galley_01 with a player-spawn fallback offset).
# Acquiring the pickup adds "junction_calibrator" to InventoryState; the
# next interaction with a `kind == "repair_junction"` objective node
# triggers objective_progress_state.apply_junction_calibrator(sequence),
# which reduces required_steps by one (min 1) and marks the sequence
# calibrator_applied. The pickup is single-use; a successful application
# removes the calibrator from inventory and hides the pickup marker.

var inventory_state: InventoryState
var equipment_state                  # EquipmentState (untyped: class_name unreliable headless)
var _item_defs: Dictionary = {}      # cached merged item-def catalog (lazy; equip/encumbrance reads)
var tool_pickup: ToolPickup
var tool_pickup_root: Node3D
const TOOL_PICKUP_INTERACTION_RADIUS: float = 1.8
const TOOL_PICKUP_FALLBACK_OFFSET: Vector3 = Vector3(4.0, 0.0, 0.0)
# REQ-RL-003 / REQ-RL-004: per-run achievement service. Loaded at boot
# when an `AchievementState` was injected by the build script; emits
# unlock events when gameplay milestones fire (tool pickup, objective
# completion, reactor stabilization, run complete). Cross-run state is
# a deferred Steamworks concern (ADR-0029); this is the per-run hook.
var achievement_state  # AchievementState (untyped: class_name unreliable headless)
# REQ-014: junction calibrator pickup. Sits in a different side room so
# the player can pick it up independently of the oxygen pump.
var junction_calibrator_pickup: ToolPickup
const JUNCTION_CALIBRATOR_INTERACTION_RADIUS: float = 1.8
const JUNCTION_CALIBRATOR_FALLBACK_OFFSET: Vector3 = Vector3(-4.0, 0.0, 0.0)
const JUNCTION_CALIBRATOR_FALLBACK_ROOM_ID: String = "galley_01"
# Sequence -> "repair_junction" / "single" lookup. Populated in
# _build_interactables alongside the interactable group so the
# completion handler can apply the calibrator to the right sequences
# without re-walking the loader's objective specs.
var sequence_kinds: Dictionary = {}
# REQ-013: electrical-arc hazard runtime state. electrical_arc_state is
# the pure model; arc_root owns the scene node; arc_zone_node is the
# StaticBody3D whose collision is toggled; arc_zone_label is the
# localized Label3D that swaps between DISCHARGED and ARCING text.
var electrical_arc_state: ElectricalArcState
# ADR-0034: food / cooking / spoilage / sustenance runtime state.
# Untyped because class_name globals are unreliable under --headless --script.
var spoilage_state  # SpoilageState
var hydroponics_state  # HydroponicsState
var water_recycler_state  # WaterRecyclerState
var power_grid_state  # PowerGridState
var life_support_expanded_state  # LifeSupportState
var hull_integrity_state  # HullIntegrityState
var hull_web_state  # WebInfestationState (hub hull's live web damage source)
var fire_suppression_state  # FireSuppressionState
var extinguisher_state  # ExtinguisherState
var propulsion_expanded_state  # PropulsionState
var sustenance_state  # SustenanceState
# Task 05 consumables runtime state.
var effect_dispatcher  # EffectDispatcher
var consumable_state  # ConsumableState
var medicine_state  # MedicineState
var stimulant_state  # StimulantState
var addiction_state  # AddictionState
var ammo_state  # AmmoState
var utility_item_state  # UtilityItemResolver
var threat_manager  # ThreatManager
var _last_weapon_hotbar_text: String = ""
# REQ-SV: survival vitals runtime state.  Untyped for headless reliability.
var vitals_state  # VitalsState
var sanity_state  # SanityState
# ADR-0042: sanity-driven hallucinations (pure director + scene manager).
var hallucination_director  # HallucinationDirector
var hallucination_manager   # HallucinationManager
var _hallucination_fx_overlay: CanvasLayer  # screen-FX overlay (alpha = hallucination_intensity)
var radiation_state  # RadiationState
var body_temperature_state  # BodyTemperatureState
var status_effects_state  # StatusEffectsState
# REQ-AU-001..010: audio runtime. audio_manager is owned by the playable
# (NOT an autoload, per AGENTS.md). audio_root is a Node3D parent for any
# spatial AudioStreamPlayer3D the manager spawns.
var audio_manager: Node
var audio_root: Node3D
# REQ-AU-001: edge-detection flag for the vitals_critical -> UI_VITALS_LOW
# one-shot emit. Set to false so the first transition into critical fires
# the alert; reset to false when vitals recover.
var _prev_vitals_critical: bool = false
var arc_root: Node3D
var arc_zone_node: StaticBody3D
var arc_zone_label: Label3D
var arc_zone_resolved_room_id: String = ""
var objective_progress_state: ObjectiveProgressState
var sequence_interactables: Dictionary = {}
# REQ-012: current-run save/load state.
var save_load_service: SaveLoadService
var last_saved_snapshot: RunSnapshot
var _is_reloading: bool = false
# Timed/rotating autosave loop. Additive to the REQ-012 checkpoint save
# (_auto_save_current_run -> save_world -> current_run.json); writes rotating
# autosave_a/b/c slots the SaveLoadMenu surfaces. No new RunSnapshot field.
var autosave_policy               # AutosavePolicy (RefCounted)
var _autosave_run_seconds: float = 0.0
var _last_autosave_result: Dictionary = {}
# Bucket 3 meta-screen shell deps (injected into MenuCoordinator.bind_meta_screens).
var localization_catalog          # LocalizationCatalog
var build_metadata_state          # BuildMetadataState
var save_load_menu                # SaveLoadMenu (RefCounted slot presenter)
# Tranche 6 (REQ-RL-006 / ADR-0029): demo scope gate — coordinator-owned,
# consulted at the five manifest enforcement points. Inert unless the live
# BuildMetadataState reports build_kind == "demo".
var demo_scope_gate               # DemoScopeGate
var _last_derelict_hazard_budget: int = -1   # validation seam: hazard cap applied on last derelict travel (-1 unlimited)
var _last_derelict_hazards_seeded: Array = []  # validation seam: hazard kinds whose seeding RAN on last travel

## NOTE: This scene relies on GeneratedShipLoader.load_from_paths() being
## SYNCHRONOUS and emitting `ship_loaded` on the same call stack — the
## _on_ship_loaded handler (and therefore _spawn_player / _spawn_camera /
## _build_interactables) depends on that ordering. If the loader is ever
## refactored to run on a thread, use call_deferred(), or otherwise defer
## emission of `ship_loaded`, this scene must be adjusted (e.g. move
## ready-signal logic out of _ready and gate it on ship_loaded explicitly).
func _ready() -> void:
	ensure_default_input_actions()
	_build_runtime_nodes()
	loader.load_from_paths(layout_path, kit_path, gameplay_slice_path)

# A11Y-P1-002 (P1 accessibility: alternate keyboard bindings): movement,
# interaction, and manual save/load expose at least one alternate keyboard
# path beyond the original WASD/E/F5/F9 layout. The primary bindings stay
# active so the existing keyboard-only path remains discoverable; alternates
# (arrow keys for movement, Enter/Space for interact) are added to the same
# InputMap actions so the player can pick whichever layout they prefer.
# The chosen keycodes do not collide with F5/F9 (save/load) or with each
# other, so adding them cannot change the save/load binding discoverability.
# Each entry is intentionally an Array literal so the alternate-binding
# surface is data — future feature/options work can swap in remap sources
# without touching the registration call sites.
const DEFAULT_MOVE_BINDINGS: Dictionary = {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
}
const DEFAULT_INTERACT_BINDINGS: Array[Key] = [KEY_E, KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]
# ADR-0043: F5/F9 keep their pre-Domain-8 world.json save/load behavior
# unchanged (request_save/request_load), now documented as dev/debug
# keys -- the player-facing save surfaces are the pause menu's Save /
# Save & Exit items and the interactive save_load slot screen.
const DEFAULT_SAVE_RUN_BINDINGS: Array[Key] = [KEY_F5]
const DEFAULT_QUICKSAVE_BINDINGS: Array[Key] = [KEY_F6]
const DEFAULT_LOAD_RUN_BINDINGS: Array[Key] = [KEY_F9]
const DEFAULT_ATTACK_BINDINGS: Array[Key] = [KEY_F]
const DEFAULT_RELOAD_BINDINGS: Array[Key] = [KEY_R]
const DEFAULT_CROUCH_BINDINGS: Array[Key] = [KEY_CTRL]

func ensure_default_input_actions() -> void:
	for action_name in DEFAULT_MOVE_BINDINGS:
		_ensure_key_action_set(action_name, DEFAULT_MOVE_BINDINGS[action_name])
	_ensure_key_action_set("interact", DEFAULT_INTERACT_BINDINGS)
	_ensure_key_action_set("attack_primary", DEFAULT_ATTACK_BINDINGS)
	_ensure_key_action_set("reload_weapon", DEFAULT_RELOAD_BINDINGS)
	_ensure_key_action_set("crouch", DEFAULT_CROUCH_BINDINGS)
	# ADR-0038: emergency field crafting bound to C (previously unbound).
	_ensure_key_action_set("field_craft", [KEY_C])
	# REQ-012: manual save/load input actions. F5 saves, F9 loads.
	_ensure_key_action_set("save_run", DEFAULT_SAVE_RUN_BINDINGS)
	_ensure_key_action_set("quicksave_run", DEFAULT_QUICKSAVE_BINDINGS)
	_ensure_key_action_set("load_run", DEFAULT_LOAD_RUN_BINDINGS)
	_ensure_key_action_set("toggle_scanner", [KEY_TAB])
	_ensure_key_action_set("toggle_inventory", [KEY_I])
	_ensure_key_action_set("ui_up", [KEY_UP])
	_ensure_key_action_set("ui_down", [KEY_DOWN])
	_ensure_key_action_set("ui_left", [KEY_LEFT])
	_ensure_key_action_set("ui_right", [KEY_RIGHT])
	_ensure_key_action_set("ui_accept", [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER])
	_ensure_key_action_set("ui_cancel", [KEY_ESCAPE])
	_ensure_key_action_set("ui_pause", [KEY_ESCAPE])
	_ensure_key_action_set("ui_open_codex", [KEY_F1])
	_ensure_key_action_set("ui_open_map", [KEY_M])

## A11Y-P1-001: swap in a new accessibility settings object and re-apply
## its scale to the HUD tracker and all existing world Label3D nodes.
## Existing labels are updated in place; nothing needs to be rebuilt. The
## scale itself flows through the new settings' clamp range, so callers
## can pass a freshly-instantiated AccessibilitySettingsScript with
## any scale in [1.0, 2.0] without worrying about out-of-range
## pixel_size values.
func apply_accessibility_settings(settings: RefCounted) -> void:
	if settings == null:
		return
	accessibility_settings = settings
	if tracker != null and tracker.has_method("apply_accessibility_settings"):
		tracker.apply_accessibility_settings(settings)
	if is_instance_valid(vitals_panel) and vitals_panel.has_method("apply_accessibility_settings"):
		vitals_panel.apply_accessibility_settings(settings)
	if is_instance_valid(hotbar_panel) and hotbar_panel.has_method("apply_accessibility_settings"):
		hotbar_panel.apply_accessibility_settings(settings)
	if is_instance_valid(menu_coordinator) and menu_coordinator.has_method("apply_accessibility_settings"):
		menu_coordinator.apply_accessibility_settings(settings)
	_apply_world_label_scale()

func _apply_world_label_scale() -> void:
	if affordance_root != null:
		for child in affordance_root.get_children():
			if child is Label3D:
				# Default base pixel_size for the affordance/landmark labels is
				# 0.003 (matches the pre-A11Y-P1-001 constant in
				# _make_affordance_label). This pass is idempotent: every call
				# rewrites the value from the same base, so swapping the scale
				# repeatedly does not drift.
				_apply_pixel_size_to_label(child, 0.003)
	if unsafe_room_marker != null:
		_apply_pixel_size_to_label(unsafe_room_marker, 0.0035)
	if arc_zone_label != null:
		_apply_pixel_size_to_label(arc_zone_label, 0.0035)

func _apply_pixel_size_to_label(label: Node, base_pixel_size: float) -> void:
	if not (label is Label3D):
		return
	(label as Label3D).pixel_size = accessibility_settings.scaled_world_pixel_size(base_pixel_size)

## Headless-validation seam: must be called only after `playable_ready`
## has fired (i.e. ship loaded, player spawned, interactables populated).
## Calling it earlier short-circuits to false because player / interactables
## are not yet wired up.
##
## Deliberately uses `set_validation_player_in_range(player)` on the
## interactable to bypass the normal Area3D body-entered physics overlap
## check (which is unreliable / never fires deterministically in a
## headless smoke run), then teleports the player onto the interactable
## and requests the interaction so the harness can assert the full
## _on_interactable_completed path runs end-to-end.
##
## Returns true once at least one objective has been completed.
func complete_first_interaction_for_validation() -> bool:
	if player == null or interactables.is_empty():
		return false
	var interactable = interactables[0]
	if not interactable.has_method("set_validation_player_in_range"):
		return false
	interactable.set_validation_player_in_range(player)
	player.teleport_to(interactable.global_position)
	player.request_interact()
	return objective_completion_count >= 1

## Headless-validation seam: teleports the player to the room center of the
## given room_id (as resolved by the loader) plus the standard spawn height
## offset above the navigation floor. Returns false (without mutating player
## state) if the player / loader are not ready, the loader does not implement
## `get_room_center`, or the loader cannot resolve the room id (i.e. it
## returns Vector3.INF). Must be called only after `playable_ready` has
## fired.
func teleport_player_to_room_for_validation(room_id: String) -> bool:
	if player == null or loader == null or not loader.has_method("get_room_center"):
		return false
	var room_center: Vector3 = loader.get_room_center(room_id)
	if room_center == Vector3.INF:
		return false
	player.teleport_to(room_center + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0))
	return true

func get_playable_summary() -> Dictionary:
	return {
		"loaded": loader != null and loader.has_loaded_ship(),
		"player_spawned": player != null,
		"camera_spawned": camera_rig != null and camera_rig.camera != null,
		"objective_count": interactables.size(),
		"objective_sequence_count": sequence_interactables.size(),
		"objectives_completed": objective_completion_count,
		"collision_shape_count": loader.count_collision_shapes() if loader != null else 0,
		"start_position": player.global_position if player != null else Vector3.INF,
		"goal_position": loader.get_goal_position() if loader != null else Vector3.INF,
	}

## Blueprint-driven entry point: build a GeneratedShip Node3D tree from a
## ShipBlueprint via the ShipGenerator and add it as a direct child of this
## playable scene. The generator returns a freshly-built GeneratedShipLoader
## root named "GeneratedShip" with "StructuralRoot" (geometry + nav) and
## "ObjectiveRoot" Node3D children nested inside it; we re-parent that root
## under self so the existing playable infrastructure (player spawn, camera
## rig, interactables) can reference it the same way it references the
## GeneratedShipLoader output.
##
## This is intentionally orthogonal to loader.load_from_paths(): callers
## who already have a ShipBlueprint (e.g. generated procedurally, replayed
## from a save fixture, or seeded for tests) can use this seam to bypass
## the layout/kit JSON paths entirely. The caller still owns subsequent
## ship_loaded wiring (the loader's `ship_loaded` signal is the production
## trigger for _on_ship_loaded — this method does NOT fire that signal,
## since the loader has not run).
##
## Returns the generated root Node3D on success, or null if the blueprint
## is null or the generator produced no ship.
##
## NOTE: parameter is intentionally untyped (`Variant`) because Godot
## `class_name` globals are not always registered at parse time in
## `godot --headless --script` mode. The runtime check via
## `ShipBlueprintScript.new(...)` in ShipGenerator is the same pattern
## used by ShipGenerator.generate(blueprint) itself.
func load_from_blueprint(blueprint) -> Node3D:
	if blueprint == null:
		push_error("PlayableGeneratedShip.load_from_blueprint: blueprint must not be null")
		return null
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()
	var generated: Node3D = generator.generate(blueprint)
	if generated == null:
		push_error("PlayableGeneratedShip.load_from_blueprint: ShipGenerator failed to build a ship")
		return null
	add_child(generated)
	return generated

func get_current_objective_sequence() -> int:
	return current_objective_sequence

func get_slice_completion_summary() -> Dictionary:
	return {
		"objective_count": interactables.size(),
		"objectives_completed": objective_completion_count,
		"current_sequence": current_objective_sequence,
		"run_complete": slice_complete,
		"player_spawned": player != null,
		"camera_spawned": camera_rig != null and camera_rig.camera != null,
	}

func get_objective_progress_summary() -> Dictionary:
	if objective_progress_state == null:
		return {}
	return objective_progress_state.get_summary()

func get_interactable_by_sequence(sequence: int):
	var group: Array = sequence_interactables.get(sequence, [])
	for interactable in group:
		if is_instance_valid(interactable) and int(interactable.get("sequence")) == sequence:
			return interactable
	return null

## Validation seam: every interactable belonging to a sequence. Multi-step
## objectives (e.g. the repair_junction at objective 2) expose one
## interactable per step at distinct positions; drivers that only touch the
## first (see get_interactable_by_sequence) cannot complete the junction.
func get_interactables_by_sequence(sequence: int) -> Array:
	var out: Array = []
	for interactable in sequence_interactables.get(sequence, []):
		if is_instance_valid(interactable) and int(interactable.get("sequence")) == sequence:
			out.append(interactable)
	return out

func teleport_player_to_objective_for_validation(sequence: int) -> bool:
	if player == null:
		return false
	var interactable = get_interactable_by_sequence(sequence)
	if interactable == null or not (interactable is Node3D):
		return false
	player.teleport_to((interactable as Node3D).global_position)
	return true

## Headless-validation seam: teleports the player to the breach zone center
## so the smoke can drive runtime oxygen drain via real _process frames.
## Must be called only after `playable_ready` has fired.
func teleport_player_to_breach_zone_for_validation() -> bool:
	if player == null or breach_zone_node == null:
		return false
	player.teleport_to(breach_zone_node.global_position)
	return true

## Headless-validation seam: returns true while the runtime per-frame tick
## considers the player to be inside the breach zone (uses the same horizontal
## proximity radius as the live hazard integration).
func is_player_in_breach_zone_for_validation() -> bool:
	return is_player_in_breach_zone()

## Headless-validation seam: drives oxygen to zero by reconfiguring OxygenState
## with drain_rate = 1000 and tick(delta=10) so the runtime tick path itself
## (the same _refresh_oxygen_state(false, delta) the live game uses) flips
## passability_blocked to true. This is a runtime consequence, not a direct
## model mutation: OxygenState.tick(...) still runs from the scene tree on
## the next frame. Returns true when passability_blocked is now true.
# ADR-0042: validation seams for the sanity hallucination loop.
func get_hallucination_director_for_validation():
	return hallucination_director

func get_hallucination_manager_for_validation():
	return hallucination_manager

func force_runtime_oxygen_to_zero_for_validation() -> bool:
	if oxygen_state == null:
		return false
	# Duplicate the breach_zone_ids array because OxygenState.configure()
	# clears its stored breach_zone_ids first and then iterates the passed-
	# in array; if we hand it the same Array reference, the iteration sees
	# an empty list and configure() leaves breach_open=false.
	oxygen_state.configure({
		"zone_ids": oxygen_state.breach_zone_ids.duplicate(),
		"max_oxygen": oxygen_state.max_oxygen,
		"drain_rate": 1000.0,
		"regen_rate": oxygen_state.regen_rate,
		"recovery_threshold": oxygen_state.recovery_threshold,
		"safe_threshold": oxygen_state.safe_threshold,
	})
	# Force-apply the scene state derived from the current model so the
	# collision toggle and HUD line update without waiting for the player to
	# be in the breach zone; the next _process tick will continue driving
	# drain via the live runtime path. Per ADR-0005 the tick context is a
	# Dictionary; passing a bool is preserved as a legacy positional form
	# so this validation seam still works without an explicit wrapping
	# dictionary.
	if is_player_in_breach_zone():
		oxygen_state.tick(10.0, true)
	else:
		oxygen_state.tick(10.0, false)
	_refresh_oxygen_state(false, 0.0)
	return oxygen_state.is_passability_blocked()

func complete_objective_sequence_for_validation(sequence: int) -> bool:
	if sequence != current_objective_sequence:
		return false
	var group: Array = sequence_interactables.get(sequence, [])
	if group.is_empty():
		return false
	for interactable in group:
		if not (interactable is Node3D):
			continue
		player.teleport_to((interactable as Node3D).global_position)
		if not interactable.has_method("set_validation_player_in_range"):
			return false
		interactable.set_validation_player_in_range(player)
		# If this interactable was already completed (e.g. multi-step and we
		# are finishing the second step after the first one), skip.
		if bool(interactable.get("completed")):
			continue
		player.request_interact()
	# Sequence complete iff current_objective_sequence has advanced past
	# the requested sequence. For multi-step sequences, the per-step path
	# in _on_interactable_completed only fires once for the whole sequence,
	# so objective_completion_count lags by one (it is incremented AFTER
	# the last step), while current_objective_sequence is incremented
	# immediately on sequence completion.
	return current_objective_sequence > sequence or slice_complete

func complete_all_objectives_for_validation() -> bool:
	var expected_total: int = sequence_interactables.size()
	if expected_total <= 0:
		return false
	while not slice_complete:
		var sequence: int = current_objective_sequence
		if sequence > expected_total:
			break
		if not complete_objective_sequence_for_validation(sequence):
			return false
	return slice_complete and objective_completion_count == expected_total

func get_affordance_summary() -> Dictionary:
	var objective_labels: int = _count_affordance_prefix("ObjectiveAffordance_")
	var blocked_labels: int = _count_affordance_prefix("BlockedAffordance_")
	var vertical_labels: int = _count_affordance_prefix("VerticalAffordance_")
	var landmark_labels: int = _count_affordance_prefix("LandmarkAffordance_")
	var readability: Dictionary = get_readability_summary()
	var entry_beacons: int = int(readability.get("entry_beacons", 0))
	var destination_markers: int = int(readability.get("destination_markers", 0))
	if landmark_labels < 2 and entry_beacons + destination_markers >= 2:
		landmark_labels = entry_beacons + destination_markers
	return {
		"objective_labels": objective_labels,
		"blocked_labels": blocked_labels,
		"vertical_labels": vertical_labels,
		"landmark_labels": landmark_labels,
		"has_blocked_text": blocked_labels > 0 or _any_affordance_text_contains("Blocked"),
		"has_vertical_text": vertical_labels > 0 or _any_affordance_text_contains("Ramp"),
	}

func _count_affordance_prefix(prefix: String) -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if child.name.begins_with(prefix):
			count += 1
	return count

func _any_affordance_text_contains(token: String) -> bool:
	if affordance_root == null:
		return false
	for child in affordance_root.get_children():
		if child is Label3D:
			var label: Label3D = child as Label3D
			if label.text.contains(token):
				return true
	return false

func get_readability_summary() -> Dictionary:
	return {
		"objective_props": _count_readability_kind_prefix("Objective"),
		"blocked_props": _count_readability_kind("BlockedBiomatter"),
		"ramp_props": _count_readability_kind("RampCue"),
		"entry_beacons": _count_readability_kind("EntryBeacon"),
		"destination_markers": _count_readability_kind("DestinationReactorCore"),
		"route_cues": _count_readability_kind("RouteCue"),
		"visible_label3d_count": _count_visible_label3d(),
		"visible_interaction_markers": _count_visible_interaction_markers(),
		"objective_prop_kinds": _objective_readability_kinds(),
	}

func _count_readability_kind(kind: String) -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if str(child.get_meta("readability_kind", "")) == kind:
			count += 1
	return count

func _count_readability_kind_prefix(prefix: String) -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if str(child.get_meta("readability_kind", "")).begins_with(prefix):
			count += 1
	return count

func _objective_readability_kinds() -> Array[String]:
	var out: Array[String] = []
	if affordance_root == null:
		return out
	for child in affordance_root.get_children():
		var kind: String = str(child.get_meta("readability_kind", ""))
		if kind.begins_with("Objective") and not out.has(kind):
			out.append(kind)
	return out

func _count_visible_label3d() -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if child is Label3D and child.visible:
			count += 1
	return count

func _count_visible_interaction_markers() -> int:
	var count: int = 0
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if interactable == null:
			continue
		var marker_node: Variant = interactable.get("marker")
		if marker_node != null and marker_node is Node3D and (marker_node as Node3D).visible:
			count += 1
	return count

func _build_slice_affordance_labels() -> void:
	if affordance_root == null:
		return
	for child in affordance_root.get_children():
		affordance_root.remove_child(child)
		child.queue_free()
	affordance_labels.clear()
	affordance_props.clear()
	_build_objective_affordance_props()
	_build_blocked_affordance_props()
	_build_vertical_affordance_props()
	_build_entry_destination_props()
	_build_route_readability_props()
	if debug_affordance_labels_enabled:
		_build_objective_affordance_labels()
		_build_blocked_affordance_labels()
		_build_vertical_affordance_labels()
		_build_landmark_affordance_labels()

func _build_objective_affordance_props() -> void:
	for interactable_variant in interactables:
		if not (interactable_variant is Node3D):
			continue
		var interactable: Node3D = interactable_variant as Node3D
		var sequence: int = int(interactable.get("sequence"))
		var objective_type: String = str(interactable.get("objective_type"))
		var prop: Node3D = ReadabilityPropFactoryScript.create_objective_prop(sequence, objective_type)
		_register_affordance_prop(prop, interactable.global_position)

func _build_blocked_affordance_props() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_blocked_route_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var prop: Node3D = ReadabilityPropFactoryScript.create_blocked_biomatter()
		prop.name = "BlockedAffordance_%02d_BlockedBiomatter" % index
		_register_affordance_prop(prop, (node as Node3D).global_position)

func _build_vertical_affordance_props() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_visible_vertical_transition_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var prop: Node3D = ReadabilityPropFactoryScript.create_ramp_cue()
		prop.name = "VerticalAffordance_%02d_RampCue" % index
		_register_affordance_prop(prop, (node as Node3D).global_position)

func _build_entry_destination_props() -> void:
	if loader == null:
		return
	var entry_position: Vector3 = loader.get_start_transform().origin
	if entry_position != Vector3.INF:
		_register_affordance_prop(ReadabilityPropFactoryScript.create_entry_beacon(), entry_position)
	var destination_position: Vector3 = loader.get_goal_position()
	if destination_position == Vector3.INF and not interactables.is_empty() and interactables[interactables.size() - 1] is Node3D:
		destination_position = (interactables[interactables.size() - 1] as Node3D).global_position
	if destination_position != Vector3.INF:
		_register_affordance_prop(ReadabilityPropFactoryScript.create_destination_reactor_core(), destination_position)

func _build_route_readability_props() -> void:
	if loader == null:
		return
	var critical_path: Array = []
	if loader.has_method("get_critical_path"):
		var raw_critical_path: Variant = loader.get_critical_path()
		if typeof(raw_critical_path) == TYPE_ARRAY:
			critical_path = raw_critical_path
	var points: Array = []
	var start_position: Vector3 = loader.get_start_transform().origin
	if start_position != Vector3.INF:
		points.append(start_position)
	for room_id_variant in critical_path:
		var room_center: Vector3 = Vector3.INF
		if loader.has_method("get_room_center"):
			room_center = loader.get_room_center(str(room_id_variant))
		if room_center != Vector3.INF:
			points.append(room_center)
	var destination_position: Vector3 = loader.get_goal_position()
	if destination_position != Vector3.INF:
		points.append(destination_position)
	var cue_index: int = 0
	var pair_count: int = max(points.size() - 1, 0)
	for i in range(pair_count):
		var from_pos: Vector3 = points[i]
		var to_pos: Vector3 = points[i + 1]
		if from_pos.distance_to(to_pos) < 0.25:
			continue
		cue_index += 1
		var cue: Node3D = ReadabilityPropFactoryScript.create_route_cue(cue_index, from_pos, to_pos)
		_register_affordance_prop(cue, cue.position)

func _build_route_control_gates() -> void:
	if route_control_root == null:
		return
	for child in route_control_root.get_children():
		route_control_root.remove_child(child)
		child.queue_free()
	route_gate_nodes.clear()
	var gate_ids: Array = []
	if loader == null:
		if route_control_state != null:
			route_control_state.configure_from_blocked_routes(gate_ids)
		return
	var index: int = 0
	for node in loader.get_blocked_route_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var gate_id: String = "powered_route_gate_%02d" % index
		var gate: StaticBody3D = _create_route_gate(gate_id, index, (node as Node3D).global_position)
		route_control_root.add_child(gate)
		route_gate_nodes.append(gate)
		gate_ids.append(gate_id)
	if route_control_state != null:
		route_control_state.configure_from_blocked_routes(gate_ids)
	_apply_route_gate_scene_state()

func _create_route_gate(gate_id: String, index: int, world_position: Vector3) -> StaticBody3D:
	var gate: StaticBody3D = StaticBody3D.new()
	gate.name = "RouteGate_%02d_PoweredBlocker" % index
	gate.position = world_position
	gate.collision_layer = 1
	gate.collision_mask = 1
	gate.set_meta("route_gate_id", gate_id)
	gate.set_meta("route_gate_kind", "powered_blocker")
	gate.set_meta("required_system", "main_power_restored")
	gate.set_meta("route_gate_open", false)
	gate.set_meta("system_cleared", false)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "RouteGateCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = ROUTE_GATE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, ROUTE_GATE_COLLISION_SIZE.y * 0.5, 0.0)
	gate.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "RouteGateVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = ROUTE_GATE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_route_gate_material(false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(visual)
	return gate

func _make_route_gate_material(is_open: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = ROUTE_GATE_VISUAL_COLOR_OPEN if is_open else ROUTE_GATE_VISUAL_COLOR_CLOSED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _register_affordance_prop(prop: Node3D, world_position: Vector3) -> void:
	if prop == null or affordance_root == null:
		return
	prop.position = world_position
	affordance_root.add_child(prop)
	affordance_props[prop.name] = prop

func _build_objective_affordance_labels() -> void:
	for interactable_variant in interactables:
		if not (interactable_variant is Node3D):
			continue
		var interactable: Node3D = interactable_variant as Node3D
		var sequence: int = int(interactable.get("sequence"))
		var objective_type: String = str(interactable.get("objective_type"))
		var text: String = "%02d %s\nE" % [sequence, _short_objective_label(objective_type)]
		_make_affordance_label("ObjectiveAffordance_%02d" % sequence, text, interactable.global_position + Vector3(0.0, 2.4, 0.0), Color(0.35, 1.0, 0.45, 1.0))

func _build_blocked_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_blocked_route_nodes():
		if not (node is Node3D):
			continue
		index += 1
		_make_affordance_label("BlockedAffordance_%02d" % index, "Blocked\nBio", (node as Node3D).global_position + Vector3(0.0, 2.8, 0.0), Color(1.0, 0.28, 0.22, 1.0))

func _build_vertical_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_visible_vertical_transition_nodes():
		if not (node is Node3D):
			continue
		index += 1
		_make_affordance_label("VerticalAffordance_%02d" % index, "Ramp\nUp", (node as Node3D).global_position + Vector3(0.0, 2.2, 0.0), Color(1.0, 0.78, 0.25, 1.0))

func _build_landmark_affordance_labels() -> void:
	if loader == null:
		return
	var index: int = 0
	for node in loader.get_landmark_nodes():
		if not (node is Node3D):
			continue
		index += 1
		var text: String = "Beacon" if index == 1 else "Core"
		_make_affordance_label("LandmarkAffordance_%02d" % index, text, (node as Node3D).global_position + Vector3(0.0, 2.8, 0.0), Color(0.28, 0.75, 1.0, 1.0))

func _make_affordance_label(node_name: String, text: String, world_position: Vector3, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = node_name
	label.text = text
	label.position = world_position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	# A11Y-P1-001: world label pixel_size flows through the single
	# accessibility_settings seam. Default scale=1.0 keeps the prior
	# 0.003 value exactly; larger scales divide the pixel_size so the
	# label renders larger on screen for the same world position.
	label.pixel_size = accessibility_settings.scaled_world_pixel_size(0.003)
	label.modulate = color
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	affordance_root.add_child(label)
	affordance_labels[node_name] = label
	return label

func _short_objective_label(raw: String) -> String:
	match raw:
		"recover_supplies":
			return "Supplies"
		"restore_systems":
			return "Systems"
		"download_logs":
			return "Logs"
		"stabilize_reactor":
			return "Reactor"
		_:
			return _title_from_snake(raw)

func _title_from_snake(raw: String) -> String:
	var words: PackedStringArray = PackedStringArray()
	for part in raw.split("_", false):
		words.append(part.capitalize())
	return " ".join(words)

func _build_runtime_nodes() -> void:
	ship_systems_manager = ShipSystemsManagerScript.new()
	var bp = _load_blueprint_for_systems()
	ship_systems_manager.configure(ship_systems_manager.load_definitions(), bp.condition, bp.seed_value)
	_apply_lifeboat_opening_damage()
	player_progression = PlayerProgressionScript.new()
	_configure_player_progression()
	# REQ-PM-002 / ADR-0033 — training event bus resolves every gameplay
	# loop (repair / combat / crafting / discovery) into a deterministic
	# XP grant on player_progression. Configured after player_progression
	# so the bus can read the player's class multipliers.
	training_event_bus = TrainingEventBusScript.new()
	training_event_bus.configure()
	# REQ-PM-003 / ADR-0033 — skill tree + book prereqs.
	skill_tree_state = SkillTreeStateScript.new()
	skill_tree_state.configure(
		PlayerProgressionScript.load_skills_catalog(),
		PlayerProgressionScript.load_books_catalog(),
	)
	skill_tree_state.load_prerequisites()
	# Domain 6 (WI-2): gate live XP so an advanced skill trains only once its
	# skill-tree node is unlocked. Base skills (not in skill_tree.json) are ungated.
	training_event_bus.skill_gate = func(skill_id: String) -> bool:
		if skill_tree_state == null:
			return true
		if not skill_tree_state.is_gated(skill_id):
			return true
		return skill_tree_state.is_unlocked(skill_id)
	# REQ-PM-006 / ADR-0033 — meta state (cross-run). Loaded from
	# user://meta_progression.json; missing file defaults to zeroed.
	meta_progression_state = MetaProgressionStateScript.new()
	if not meta_progression_state.load_from_disk():
		meta_progression_state.reset_all()
	# REQ-PM-007 / ADR-0033 — hub upgrade catalog.
	hub_upgrade_state = HubUpgradeStateScript.new()
	hub_upgrade_state.configure()
	# REQ-PM-009 / ADR-0033 — cross-run unlock registry (codex / scenes /
	# classes). Loaded from user://unlock_registry.json.
	unlock_registry = UnlockRegistryScript.new()
	var unlock_catalog_path: String = "res://data/player/unlock_tables.json"
	if FileAccess.file_exists(unlock_catalog_path):
		var unlock_text: String = FileAccess.get_file_as_string(unlock_catalog_path)
		var unlock_parsed: Variant = JSON.parse_string(unlock_text)
		if typeof(unlock_parsed) == TYPE_DICTIONARY:
			unlock_registry.configure(unlock_parsed)
		else:
			unlock_registry.configure()
	else:
		unlock_registry.configure()
	unlock_registry.load_from_disk()
	unique_item_state = UniqueItemStateScript.new()
	unique_item_state.configure()
	# Re-run progression setup after loading cross-run meta + hub state so
	# persistent starting-skill and XP-multiplier bonuses are actually applied.
	_configure_player_progression()
	route_control_state = RouteControlStateScript.new()
	route_gate_nodes.clear()
	objective_progress_state = ObjectiveProgressStateScript.new()
	loader = GeneratedShipLoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(_on_ship_loaded)
	loader.load_failed.connect(_on_loader_failed)
	add_child(loader)
	interaction_root = Node3D.new()
	interaction_root.name = "InteractionRoot"
	add_child(interaction_root)
	affordance_root = Node3D.new()
	affordance_root.name = "SliceAffordanceRoot"
	add_child(affordance_root)
	route_control_root = Node3D.new()
	route_control_root.name = "RouteControlRoot"
	add_child(route_control_root)
	oxygen_state = OxygenStateScript.new()
	oxygen_root = Node3D.new()
	oxygen_root.name = "OxygenRoot"
	add_child(oxygen_root)
	# REQ-007 inventory/tool runtime nodes. InventoryState is a pure model
	# (RefCounted); tool_pickup_root is the parent for any ToolPickup node
	# the coordinator spawns during ship load.
	inventory_state = InventoryStateScript.new()
	equipment_state = EquipmentStateScript.create()
	tool_pickup_root = Node3D.new()
	tool_pickup_root.name = "ToolPickupRoot"
	add_child(tool_pickup_root)
	# REQ-013: electrical-arc runtime nodes. The model + scene root are
	# always allocated so _process and _refresh_arc_state can be called
	# unconditionally; the per-template `_build_arc_zone()` decides
	# whether to spawn a real StaticBody3D / Label3D or to leave them
	# null (the loader returns an empty `arc_zone_specs` when no marker
	# is present and the scene must skip arc setup without crashing).
	electrical_arc_state = ElectricalArcStateScript.new()
	arc_root = Node3D.new()
	arc_root.name = "ElectricalArcRoot"
	add_child(arc_root)
	# REQ-SV: instantiate survival vitals models.
	vitals_state = VitalsStateScript.new()
	sanity_state = SanityStateScript.new()
	radiation_state = RadiationStateScript.new()
	body_temperature_state = BodyTemperatureStateScript.new()
	status_effects_state = StatusEffectsStateScript.new()
	# ADR-0034: instantiate food / cooking / spoilage / sustenance models.
	spoilage_state = SpoilageStateScript.new()
	hydroponics_state = HydroponicsStateScript.new()
	water_recycler_state = WaterRecyclerStateScript.new()
	_configure_expanded_ship_system_models()
	effect_dispatcher = EffectDispatcherScript.new()
	effect_dispatcher.configure({})
	consumable_state = ConsumableStateScript.new()
	consumable_state.configure({})
	medicine_state = MedicineStateScript.new()
	medicine_state.configure({})
	stimulant_state = StimulantStateScript.new()
	stimulant_state.configure({})
	addiction_state = AddictionStateScript.new()
	addiction_state.configure({})
	ammo_state = AmmoStateScript.new()
	ammo_state.configure({})
	utility_item_state = UtilityItemResolverScript.new()
	utility_item_state.configure({})
	threat_manager = ThreatManagerScript.new()
	threat_manager.name = "ThreatManager"
	add_child(threat_manager)
	if not threat_manager.threat_killed.is_connected(_on_threat_killed):
		threat_manager.threat_killed.connect(_on_threat_killed)
	# REQ-AU-001..010: build the AudioManager service. The manager owns
	# six pure models (bus_config, ambient, sfx_router, music, spatial,
	# meta_event) and a per-bus AudioStreamPlayer pool. Constructed after
	# the hazards so the manager's music-state engine can read engagement /
	# hazard / vitals signals from the same models the rest of the scene
	# uses.
	audio_manager = AudioManagerScript.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	audio_root = Node3D.new()
	audio_root.name = "AudioRoot"
	add_child(audio_root)
	derelict_objective_root = Node3D.new()
	derelict_objective_root.name = "DerelictObjectiveRoot"
	add_child(derelict_objective_root)
	loot_container_root = Node3D.new()
	loot_container_root.name = "LootContainerRoot"
	add_child(loot_container_root)
	repair_point_root = Node3D.new()
	repair_point_root.name = "RepairPointRoot"
	add_child(repair_point_root)
	# ADR-0038: instantiate the crafting / salvage economy models (each auto-loads its JSON
	# catalog in _init). The station nodes that make them player-reachable are built later
	# in _build_crafting_stations() once the home ship scene_root exists.
	crafting_state = CraftingStateScript.new()
	material_state = MaterialStateScript.new()
	field_crafting_state = FieldCraftingStateScript.new()
	deconstruction_resolver = DeconstructionResolverScript.new()
	crafting_station_root = Node3D.new()
	crafting_station_root.name = "CraftingStationRoot"
	add_child(crafting_station_root)
	_loot_tables = LootRollerScript.load_tables()
	# REQ-012: current-run save/load service. Single slot at
	# user://saves/current_run.json; deleted on playable_slice_completed.
	# Constructed BEFORE _build_hud_layer() because the menu shell's meta-screen
	# binding (below) consumes save_load_menu / localization_catalog / build_metadata.
	save_load_service = SaveLoadServiceScript.new()
	# run_id slot-ownership rework: stamp this session's run identity into
	# the service immediately, so every save this run makes before any
	# later Continue/F9 load is already attributed to this run's freeze set.
	_run_id = _generate_run_id()
	save_load_service.set_active_run_id(_run_id)
	# Timed/rotating autosave loop (additive to the REQ-012 checkpoint save).
	# Defaults: 90 in-game-second cadence, 8-event cadence, 5 s real-time budget
	# guard, rotating autosave_a/b/c. Driven from _process via _tick_autosave_policy().
	autosave_policy = AutosavePolicyScript.new()
	# Bucket 3 meta-screen shell deps: localization catalog + build metadata from the
	# release data bundle, and the save-slot presenter bound to the live save service.
	localization_catalog = LocalizationCatalogScript.new()
	localization_catalog.configure(_load_json_dict("res://data/release/localization_catalog.json"))
	build_metadata_state = BuildMetadataStateScript.new()
	build_metadata_state.configure(_load_json_dict("res://data/release/build_metadata.json"))
	# Tranche 6 (2026-07-06 audit HIGH): the demo scope gate finally gets its
	# production callsites. Configured against the SAME BuildMetadataState
	# instance so the gate reads the live build kind at every consult.
	demo_scope_gate = DemoScopeGateScript.new()
	demo_scope_gate.configure(_load_json_dict("res://data/release/demo_scope_manifest.json"), build_metadata_state)
	save_load_menu = SaveLoadMenuScript.new()
	save_load_menu.bind(save_load_service)
	# Construct the per-run achievement state here (previously only injected by the
	# external build script, so it was null in the live run — leaving unlock_for_trigger
	# dormant). Guarded so an external injection still wins. Configured from the same
	# catalog the AchievementsPanel renders.
	if achievement_state == null:
		achievement_state = AchievementStateScript.new()
		achievement_state.configure(_load_json_dict("res://data/release/achievement_catalog.json"))
	_build_hud_layer()
	# Phase 4.5: Synaptic Sea map + scanner + travel. Seed the world from the
	# starting blueprint's seed so the marker field is deterministic per run.
	# Player starts at Synaptic Sea map origin (abstract X-Z map space — NOT the
	# physical scene origin where ship geometry is instantiated).
	var start_bp = _load_blueprint_for_systems()
	synaptic_sea_world = SynapticSeaWorldScript.new(start_bp.seed_value, Vector3.ZERO)
	scanner_state = ScannerStateScript.new()
	travel_controller = TravelControllerScript.new()
	ship_generator = ShipGeneratorScript.new()

## Configures the progression model from starting_class_id (defaults to engineer
## when the id is unknown). Idempotent: re-callable on reload.
func _configure_player_progression() -> void:
	if player_progression == null:
		return
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var chosen_class: String = starting_class_id
	if meta_progression_state != null:
		var sel: String = meta_progression_state.get_selected_class()
		if not sel.is_empty() and classes.has(sel):
			# Only honor the selection if it is a base class or an unlocked one.
			var is_unlockable: bool = bool(classes[sel].unlockable)
			if not is_unlockable or meta_progression_state.is_class_unlocked(sel):
				chosen_class = sel
	var class_def = classes.get(chosen_class, classes.get("engineer", null))
	if class_def == null:
		push_error("PlayableGeneratedShip: no class definition for '%s' (fell back from starting_class_id '%s') or fallback 'engineer' (data/player/classes.json missing or malformed)" % [chosen_class, starting_class_id])
	player_progression.configure(
		class_def,
		PlayerProgressionScript.load_skills_catalog(),
		PlayerProgressionScript.load_books_catalog(),
	)
	# REQ-PM-007 / ADR-0033 — apply persistent starting-skill bonuses
	# purchased as hub upgrades on prior runs.
	if hub_upgrade_state != null and meta_progression_state != null:
		var bonuses: Dictionary = hub_upgrade_state.compose_starting_skill_bonuses(meta_progression_state)
		for sid in bonuses:
			if player_progression.skills.has(sid):
				var current: int = int(player_progression.skills[sid])
				var bonus: int = int(bonuses[sid])
				player_progression.skills[sid] = clampi(current + bonus, 0, PlayerProgressionScript.MAX_SKILL_LEVEL)
	# REQ-PM-007 — apply persistent XP multiplier bonuses.
	if hub_upgrade_state != null and meta_progression_state != null:
		var mults: Dictionary = hub_upgrade_state.compose_xp_multipliers(meta_progression_state)
		for cat in mults:
			var m: float = float(mults[cat])
			if m > 1.0:
				# PlayerProgressionState._xp_multipliers is keyed by category;
				# multiplicative composition means the upgrade bonus layers
				# on top of the class multiplier already in place.
				var existing: float = float(player_progression._xp_multipliers.get(cat, 1.0))
				player_progression._xp_multipliers[cat] = existing * m

## Loads the blueprint sidecar that seeds the ShipSystemsManager's condition
## damage. Falls back to a DAMAGED/seed=17 default (never crashes the slice)
## when the sidecar is absent or malformed.
func _load_blueprint_for_systems():
	var fallback = ShipBlueprintScript.new(ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.DAMAGED, 17)
	if blueprint_path.is_empty() or not FileAccess.file_exists(blueprint_path):
		push_warning("PlayableGeneratedShip: blueprint sidecar missing at %s; using DAMAGED/seed=17 default" % blueprint_path)
		return fallback
	var text: String = FileAccess.get_file_as_string(blueprint_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PlayableGeneratedShip: blueprint sidecar malformed at %s; using default" % blueprint_path)
		return fallback
	return ShipBlueprintScript.from_dict(parsed as Dictionary)

func _load_json_dict(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary

func _configure_expanded_ship_system_models() -> void:
	power_grid_state = PowerGridStateScript.new()
	power_grid_state.configure(_load_json_dict(POWER_GRID_CONFIG_PATH))
	hull_integrity_state = HullIntegrityStateScript.new()
	hull_integrity_state.configure(_load_json_dict(HULL_COMPARTMENTS_CONFIG_PATH))
	hull_web_state = WebInfestationStateScript.new()
	hull_web_state.configure(_load_json_dict(WEB_INFESTATION_CONFIG_PATH))
	var tuning: Dictionary = _load_json_dict(SHIP_SUBSYSTEM_TUNING_PATH)
	life_support_expanded_state = LifeSupportExpandedStateScript.new()
	life_support_expanded_state.configure(tuning.get("life_support", {}))
	fire_suppression_state = FireSuppressionStateScript.new()
	fire_suppression_state.configure(tuning.get("fire_suppression", {}))
	extinguisher_state = ExtinguisherStateScript.new()
	extinguisher_state.configure(tuning.get("extinguisher", {}))
	propulsion_expanded_state = PropulsionExpandedStateScript.new()
	propulsion_expanded_state.configure(tuning.get("propulsion", {}))
	sustenance_state = SustenanceStateScript.new()
	sustenance_state.configure(_load_json_dict(FACILITY_UPGRADES_CONFIG_PATH))

## Seed a freshly-generated derelict's per-ship structural models from tuning and stamp
## its sim clock. Called ONCE on first visit (not on revisit — a retained instance already
## carries its caught-up state). The hub never uses this (it has the coordinator singletons).
func _seed_ship_models(inst) -> void:
	if inst == null:
		return
	inst.get_hull().configure(_load_json_dict(HULL_COMPARTMENTS_CONFIG_PATH))
	inst.get_web().configure(_load_json_dict(WEB_INFESTATION_CONFIG_PATH))   # attached_to_web=true by default
	inst.last_sim_time = world_time

func _manager_broken_systems() -> Array[String]:
	var broken: Array[String] = []
	if ship_systems_manager == null:
		return broken
	for subsystem_id in ["life_support", "propulsion"]:
		if not ship_systems_manager.systems.has(subsystem_id) or not ship_systems_manager.is_operational(subsystem_id):
			broken.append(subsystem_id)
	return broken

## Tick the active ship's fire model (home: hub; away: derelict) once and apply
## its per-compartment system damage. Extracted from _recompute_expanded_ship_systems
## so the recompute can run on BOTH _process branches (Domain 4) without double-
## ticking the fire the away branch already owns. Call exactly once per branch.
func _tick_active_fire(delta: float) -> void:
	var afs = _active_fire_state()
	if afs == null:
		return
	if afs.tick(delta, _build_fire_context()):
		_refresh_fire_zones()
	# A burning compartment degrades the ship system housed there (M7-B Task 8).
	_apply_fire_system_damage(delta)

## Foundation contagion seed: while away and docked to a still-web-attached
## derelict, the web creeps onto the hub faster (contact boost). Full dock-graph
## spread is the follow-on web spec.
func _active_derelict_web_attached() -> bool:
	return away_from_start and current_ship != null and current_ship.is_web_attached()

## Live Persistent Ships Phase 3: the unified per-ship sim tick. Advances ONE ship's
## systems manager and applies its biomatter-web hull damage, resolving the ship's own
## models via _web_for/_hull_for. Works for any ship (hub or derelict); used continuously
## for present ships and (Phase 4) for catch-up over a large dt. Does NOT tick fire (that
## stays on the active-ship scene path) or the hub expanded recompute.
func _advance_ship(ship, delta: float) -> void:
	if ship == null:
		return
	ship.last_sim_time = world_time   # FIX C1: stamp present ship's clock so catch-up on revisit covers absence only (not presence+absence)
	if ship.systems_manager != null:
		ship.systems_manager.advance(delta)
	var web = _web_for(ship)
	var hull = _hull_for(ship)
	if web == null or hull == null:
		return
	# Contact boost is the hub's only (an attached derelict docked to the hub). A derelict's
	# own attachment drives its base web growth; cross-ship spread is a follow-on.
	var contact: bool = _active_derelict_web_attached() if ship == home_ship else false
	var dmg: float = web.tick(delta, contact)
	if dmg <= 0.0:
		return
	for cid in hull.compartments.keys():
		hull.damage_compartment(str(cid), dmg)

const CATCHUP_SUBSTEP_SECONDS: float = 5.0     # cap per advance step so fire/system models stay stable over big gaps
const MAX_CATCHUP_SECONDS: float = 1800.0      # bound total absence catch-up to 30 min of sim (no infinite decay)

## Live Persistent Ships Phase 4: fast-forward an absent ship's sim by the world_time elapsed
## since it was last advanced, in capped sub-steps. The hub is never absent (ticked every
## frame) so it is excluded. New derelicts have last_sim_time == world_time (seeded), so a
## first visit is a no-op. Idempotent: stamps last_sim_time = world_time so a re-entry without
## further world_time advance does nothing.
func _catch_up_ship(inst) -> void:
	if inst == null or inst == home_ship:
		return
	var dt: float = minf(world_time - inst.last_sim_time, MAX_CATCHUP_SECONDS)
	if dt <= 0.0:
		return
	inst.last_sim_time = world_time
	while dt > 0.0:
		var step: float = minf(CATCHUP_SUBSTEP_SECONDS, dt)
		_advance_ship(inst, step)
		dt -= step

func _recompute_expanded_ship_systems(delta: float) -> void:
	if power_grid_state == null:
		return
	var power_health: float = 0.0
	if ship_systems_manager != null and ship_systems_manager.get_system("power") != null:
		power_health = ship_systems_manager.get_system("power").health()
	power_grid_state.rebalance(power_health, _manager_broken_systems())
	if propulsion_expanded_state != null and hull_integrity_state != null:
		propulsion_expanded_state.tick(delta, {
			"powered_ratio": power_grid_state.get_allocation_ratio("propulsion"),
			"manager_operational": ship_systems_manager != null and ship_systems_manager.is_operational("propulsion"),
			"hull_penalty": 1.0 - hull_integrity_state.average_integrity(),
		})
	if life_support_expanded_state != null and hull_integrity_state != null:
		var recycled_water: float = 0.0
		if water_recycler_state != null:
			recycled_water = float(water_recycler_state.output_ready)
		life_support_expanded_state.tick(delta, {
			"powered_ratio": power_grid_state.get_allocation_ratio("life_support"),
			"breach_count": hull_integrity_state.get_breach_count(),
			"recycled_water": recycled_water,
		})
	# ADR-0038: drive station power from the same "stations" channel, then advance the
	# single active craft. Field crafting is unpowered, so it ticks regardless (and also in
	# the _process away-branch for emergency crafts started before travel).
	if crafting_state != null:
		var stations_powered: bool = power_grid_state.get_allocation_ratio("stations") > 0.0
		for kind in CRAFTING_STATION_KINDS:
			crafting_state.get_or_create_station(kind).set_power(stations_powered)
		for st in crafting_stations:
			if is_instance_valid(st):
				st.set_powered(stations_powered)
		if crafting_state.tick(delta):
			_on_craft_completed()
	# M7-B Task 9: the extinguisher recharge port draws from the same "stations"
	# channel as the crafting stations, but its power is independent of crafting_state.
	if is_instance_valid(extinguisher_recharge_port):
		extinguisher_recharge_port.set_powered(power_grid_state.get_allocation_ratio("stations") > 0.0)
	if sustenance_state != null:
		sustenance_state.tick(delta, {
			"powered_ratio": power_grid_state.get_allocation_ratio("sustenance"),
			"hydroponics_summary": hydroponics_state.get_summary() if hydroponics_state != null else {},
			"water_recycler_summary": water_recycler_state.get_summary() if water_recycler_state != null else {},
			"meals_active": crafting_state != null and crafting_state.is_crafting() and crafting_state.get_active_station_kind() in ["kitchen", "synthesizer"],
		})

func _expanded_ship_systems_summary() -> Dictionary:
	return {
		"power_grid_summary": power_grid_state.get_summary() if power_grid_state != null else {},
		"life_support_state_summary": life_support_expanded_state.get_summary() if life_support_expanded_state != null else {},
		"hull_integrity_summary": hull_integrity_state.get_summary() if hull_integrity_state != null else {},
		"web_infestation_summary": hull_web_state.get_summary() if hull_web_state != null else {},
		"fire_suppression_summary": fire_suppression_state.get_summary() if fire_suppression_state != null else {},
		"extinguisher_summary": extinguisher_state.get_summary() if extinguisher_state != null else {},
		"propulsion_state_summary": propulsion_expanded_state.get_summary() if propulsion_expanded_state != null else {},
		"sustenance_state_summary": sustenance_state.get_summary() if sustenance_state != null else {},
	}

func get_ship_systems_expanded_summary() -> Dictionary:
	return _expanded_ship_systems_summary()

func set_manual_power_route_for_validation(subsystem_id: String, units: float) -> bool:
	if power_grid_state == null:
		return false
	var ok: bool = power_grid_state.set_manual_route(subsystem_id, units)
	_recompute_expanded_ship_systems(0.0)
	_refresh_tracker_system_status_lines()
	return ok

func force_hull_breach_for_validation(compartment_id: String, amount: float = 0.6) -> bool:
	if hull_integrity_state == null:
		return false
	var ok: bool = hull_integrity_state.damage_compartment(compartment_id, amount, true)
	_recompute_expanded_ship_systems(0.0)
	_refresh_tracker_system_status_lines()
	return ok

func seal_hull_breach_for_validation(compartment_id: String, amount: float = 1.0) -> bool:
	if hull_integrity_state == null:
		return false
	var ok: bool = hull_integrity_state.seal_compartment(compartment_id, amount)
	_recompute_expanded_ship_systems(0.0)
	_refresh_tracker_system_status_lines()
	return ok

func get_breach_seal_points_for_validation() -> Array:
	return breach_seal_points.duplicate()

func teleport_player_to_breach_seal_point_for_validation(seal_point) -> bool:
	if player == null or seal_point == null or not is_instance_valid(seal_point):
		return false
	if player is Node3D and seal_point is Node3D:
		(player as Node3D).global_position = (seal_point as Node3D).global_position
		return true
	return false

func ignite_compartment_for_validation(compartment_id: String, intensity: float = 1.0) -> bool:
	if fire_suppression_state == null:
		return false
	var ok: bool = fire_suppression_state.ignite(compartment_id, intensity)
	_recompute_expanded_ship_systems(0.0)
	_refresh_tracker_system_status_lines()
	return ok

## Validation seam: the live ShipSystemsManager (null before _build_runtime_nodes()).
func get_ship_systems_manager():
	return ship_systems_manager

## Validation seam: the live PlayerProgressionState (null before _build_runtime_nodes()).
func get_player_progression():
	return player_progression

## REQ-PM-002 / ADR-0033 validation seam.
func get_training_event_bus():
	return training_event_bus

## REQ-PM-003 / ADR-0033 validation seam.
func get_skill_tree_state():
	return skill_tree_state

## REQ-PM-007 / ADR-0033 validation seam.
func get_hub_upgrade_state():
	return hub_upgrade_state

## REQ-PM-006 / ADR-0033 validation seam.
func get_meta_progression_state():
	return meta_progression_state

## REQ-PM-009 / ADR-0033 validation seam.
func get_unlock_registry():
	return unlock_registry

## REQ-PM-008 / ADR-0033 — explicit end-of-run trigger (death, extraction,
## abandon). Applies the meta payout, persists meta + unlock state, then
## wipes the current-run save file so a fresh run starts clean.
##
## Returns the payout amount in meta_currency. Idempotent: a second call
## after the slice is already complete returns 0 and is a no-op.
# run_id slot-ownership rework (ADR-0043 addendum): identifies THIS run
# instance to SaveLoadService. Every save_world()/save_to_slot() call
# stamps this id onto the payload and index row inside the service itself
# (no coordinator call site can forget to stamp it), so
# _freeze_run_on_death() can ask the service which slots this run actually
# wrote instead of relying on convention-tracked flags
# (_persisted_lineage_active / _manual_slots_written_this_run, both
# deleted). Set at session start and re-set on a successful Continue/F9
# load (see request_load()).
var _run_id: String = ""

## run_id slot-ownership rework: a fresh per-session run identity. Ticks
## microseconds are not guaranteed unique across process starts on their
## own, so a random 16-bit suffix is appended; collision with another
## run's id would falsely merge two runs' freeze sets, which the suffix
## makes astronomically unlikely without needing a UUID dependency.
func _generate_run_id() -> String:
	return "%d-%04x" % [Time.get_ticks_usec(), randi() % 0x10000]

func end_run(reason: String = "extraction") -> int:
	if slice_complete:
		return 0
	slice_complete = true
	tracker.mark_run_complete()
	# REQ-RL-003: extracted achievement also fires on explicit end_run
	# (extraction/death) so non-slice completion paths still unlock.
	_try_unlock_achievement("run_complete", reason)
	var payout: int = int(_apply_meta_payout_and_persist(reason))
	if save_load_service != null:
		if reason == "death":
			# ADR-0043: permadeath freezes, it does not delete. world.json and
			# every slot written this run stay on disk; a death record gates
			# every future load of them (SaveLoadService.load_world /
			# load_from_slot), and the slot screen renders them DEAD with an
			# epitaph (ADR-0032's original browse-the-epitaph intent).
			_freeze_run_on_death()
		else:
			# Extraction/completion path UNCHANGED -- still deletes. A finished
			# successful run has nothing to "continue"; this is not permadeath.
			save_load_service.delete_current_run()
			for slot_id in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
				save_load_service.delete_slot(slot_id)
	# Session 3 (audit): the title screen consumes this summary — carry the
	# end_run reason so "Last run: death" vs "Last run: extraction" renders.
	var completion_summary: Dictionary = get_slice_completion_summary()
	completion_summary["reason"] = reason
	emit_signal("playable_slice_completed", completion_summary)
	return payout

## ADR-0043 / run_id slot-ownership rework: freeze every slot this run
## instance actually wrote instead of deleting it. Replaces the old
## convention-tracked lineage flag + manual-slot dictionary: SaveLoadService
## already knows -- from the run_id it stamped on every write -- exactly
## which slots (world, the active-autosave alias, AUTOSAVE_SLOT_IDS, the
## quickslot, and any manual slot_01..06) belong to _run_id, so freeze_run()
## resolves the whole set structurally. A fresh run whose _run_id has never
## been stamped onto a disk row (New Game, die-before-any-save) freezes
## nothing -- it cannot brick a different, still-live run's Continue,
## because slot_ids_for_run() only returns rows this run's id actually
## touched.
func _freeze_run_on_death() -> void:
	save_load_service.freeze_run(_run_id, "death", _build_epitaph_text(), world_time, current_objective_sequence)

## ADR-0043: short human-readable epitaph text for the frozen slot rows /
## death record. Cause is always "death" today (the only end_run reason
## that freezes); location comes from the current ship's marker_id (empty
## string = home ship).
func _build_epitaph_text() -> String:
	var location: String = ""
	var cur = get_current_ship()
	if is_instance_valid(cur):
		location = String(cur.marker_id)
	var location_label: String = location if not location.is_empty() else "the home ship"
	return "Died aboard %s at objective %d (run time %.0fs)" % [location_label, current_objective_sequence, world_time]

## REQ-PM-002 / ADR-0033 — public seam for gameplay code (repair points,
## combat, cooking, scanners, etc.) to fire a deterministic training event
## through the bus. Returns the resolved (skill_id, base_xp) record or
## null on rejection (unknown event, missing progression, suppressed).
func emit_training_event(event_id: String, target_id: String = ""):
	if training_event_bus == null or player_progression == null:
		return null
	return training_event_bus.emit(event_id, target_id, player_progression)

## Phase 4.5 validation seam: the current ShipInstance (null before the first
## ship loads).
func get_current_ship():
	return current_ship

## Phase 5a Task 5 validation seam: the home ShipInstance.
func get_home_ship_for_validation():
	return home_ship

## Phase 5a Task 7 validation seam: the docked lifeboat ShipInstance.
func get_lifeboat_ship_for_validation():
	return lifeboat_ship

## Phase 5a Task 6: build the occupancy-entry list for ShipOccupancy.resolve().
## Phase 5b Task 5: the PILOTED ship (lifeboat) is listed FIRST — it physically docks
## flush to its host and its tighter interior sits INSIDE the host's generous per-room
## AABB, so the player standing in the lifeboat must resolve to the lifeboat, not the
## host. (Pre-5b ordered home first for dock-seam priority, but with physical docking
## the ride fully overlaps the host; piloted-first is the correct containment priority.)
## Home and the active derelict follow as hosts the player can cross into once they
## breach the dock barrier and step out of the piloted ship's interior.
func _occupancy_entries() -> Array:
	var entries: Array = []
	# Piloted ship (the player's ride) has top priority when its interior contains them.
	if piloted_ship != null and piloted_ship.scene_root != null and is_instance_valid(piloted_ship.scene_root) and piloted_ship.scene_root.get_parent() == self:
		entries.append({"inst": piloted_ship, "aabb": piloted_ship.interior_aabb()})
	# Lifeboat (when not the piloted ship handle) kept for back-compat with the docked
	# home lifeboat occupancy (Phase 5a Task 7).
	if lifeboat_ship != null and lifeboat_ship != piloted_ship and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root) and lifeboat_ship.scene_root.get_parent() == self:
		entries.append({"inst": lifeboat_ship, "aabb": lifeboat_ship.interior_aabb()})
	# Phase 5b Task 6: a host (home or derelict) is only resolvable as "occupied" once
	# the player has opened its dock-seam barrier — "you must open the port to board."
	# The piloted ship and lifeboat are the player's own ride and are never gated.
	if home_ship != null and home_ship.scene_root != null and is_instance_valid(home_ship.scene_root) and _ship_boardable(home_ship):
		entries.append({"inst": home_ship, "aabb": home_ship.interior_aabb()})
	if current_ship != null and current_ship != home_ship and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root) and _ship_boardable(current_ship):
		entries.append({"inst": current_ship, "aabb": current_ship.interior_aabb()})
	return entries

## True if `inst` can be boarded: it has no dock barrier, or its dock barrier is open.
## (The piloted ship and any ship without a seam barrier are always boardable.)
func _ship_boardable(inst) -> bool:
	if inst == null:
		return false
	if inst == piloted_ship:
		return true
	for b in dock_barriers:
		if is_instance_valid(b) and String(b.marker_id) == String(inst.marker_id):
			return b.opened
	return true   # no barrier for this ship -> boardable (defensive)

## Phase 5a Task 6: derive current_occupancy from world position.
## Also keeps away_from_start consistent so existing hazard/persistence readers
## keep working unchanged.
func recompute_occupancy() -> void:
	if home_ship == null:
		return
	var resolved = home_ship
	if player != null and player is Node3D:
		var r = ShipOccupancyScript.resolve((player as Node3D).global_position, _occupancy_entries())
		if r != null:
			resolved = r
	current_occupancy = resolved
	# Phase 5b Task 5: "away" means the player is away from the HOME complex. With
	# physical docking the player rides the piloted ship; while that ship is docked to
	# the home ship, occupying it is still "at home" (the ride is parked at home). So
	# away is false when occupancy is home OR the piloted ship docked to home.
	var at_home_complex: bool = (current_occupancy == home_ship) \
		or (piloted_ship != null and current_occupancy == piloted_ship and piloted_ship.parent_ship == home_ship)
	away_from_start = not at_home_complex

## A bridge terminal fired login_requested. Gate on the ship being a working
## vessel, then claim it for the local player and take command. Refused logins
## leave piloted_ship unchanged.
func _on_login_requested(ship_id: String) -> void:
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return
	if not inst.is_working_vessel():
		return   # silent: refusing a login on an unrepaired vessel is an expected player action
	inst.get_access().claim(PLAYER_LOCAL_ID)
	set_piloted_ship(inst)

## Re-points piloted_ship to `inst` (the player's active ride). Gated on the local
## player having access. Recomputes occupancy. Returns {success, reason}.
func set_piloted_ship(inst) -> Dictionary:
	if inst == null:
		return {"success": false, "reason": "unknown_ship"}
	if not inst.get_access().has_access(PLAYER_LOCAL_ID):
		return {"success": false, "reason": "no_access"}
	piloted_ship = inst
	recompute_occupancy()
	return {"success": true, "reason": "ok"}

## Phase 5a Task 6 validation seam: returns current_occupancy.
func get_current_occupancy_for_validation():
	return current_occupancy

## Phase 5b Task 5 validation seam: the piloted ship's current host (the derelict
## or home ship it is docked to). Equals current_ship.
func get_current_host_for_validation():
	return current_ship

## 5c seam: calls set_piloted_ship for ship_id without the login/claim path
## (used to exercise the no_access guard directly).
func set_piloted_ship_by_id_for_validation(ship_id: String) -> Dictionary:
	return set_piloted_ship(_find_ship_by_id(ship_id))

## Phase 5b Task 5 validation seam: teleport the player to the piloted ship's
## interior center so it reads as aboard the ride.
func board_piloted_ship_for_validation() -> void:
	if piloted_ship != null and player != null and player is Node3D and player.has_method("teleport_to"):
		player.teleport_to(piloted_ship.interior_aabb().get_center())

## Phase 5b Task 5 validation seam: true iff some active dock barrier is closed.
func has_closed_dock_barrier_for_validation() -> bool:
	for b in dock_barriers:
		if is_instance_valid(b) and not b.opened:
			return true
	return false

## Phase 5b Task 5 validation seam: true iff the piloted ship's lifted airlock port
## is within 0.5u of the host's lifted dock port (proves a real flush dock).
func piloted_flush_to_host_for_validation() -> bool:
	if piloted_ship == null or current_ship == null or not is_instance_valid(current_ship.scene_root):
		return false
	var cc := 0 if current_ship == home_ship else _ship_condition_class(current_ship)
	var host_local: Dictionary = DockPortsScript.for_derelict(current_ship.built_layout, _ship_seed(current_ship), cc)
	var host_world: Dictionary = DockingManagerScript.host_port_to_world(current_ship, host_local)
	if host_world.is_empty():
		return false
	var lb_local: Dictionary = DockPortsScript.for_lifeboat(piloted_ship.built_layout)
	if not is_instance_valid(piloted_ship.scene_root) or not (piloted_ship.scene_root as Node3D).is_inside_tree():
		return false
	var lb_world: Vector3 = (piloted_ship.scene_root as Node3D).global_transform * (lb_local["position"] as Vector3)
	return lb_world.distance_to(host_world["position"] as Vector3) <= 0.5

## 5c seams for rigid-pair travel.
func current_ship_id_for_validation() -> String:
	return String(current_ship.ship_id) if current_ship != null else ""

func is_marker_current_for_validation(marker_id: String) -> bool:
	return current_ship != null and String(current_ship.marker_id) == marker_id

func lifeboat_docked_to_piloted_for_validation() -> bool:
	return lifeboat_ship != null and piloted_ship != null and lifeboat_ship.parent_ship == piloted_ship

## True iff the lifeboat's lifted airlock port is within 0.5u of the piloted ship's
## lifted dock port — i.e. the lifeboat is flush against the (moved) piloted ship.
func lifeboat_flush_to_piloted_for_validation() -> bool:
	if lifeboat_ship == null or piloted_ship == null:
		return false
	if not is_instance_valid(lifeboat_ship.scene_root) or not is_instance_valid(piloted_ship.scene_root):
		return false
	if not (lifeboat_ship.scene_root as Node3D).is_inside_tree() or not (piloted_ship.scene_root as Node3D).is_inside_tree():
		return false
	var piloted_local: Dictionary = _piloted_port_local()
	var piloted_world: Dictionary = DockingManagerScript.host_port_to_world(piloted_ship, piloted_local)
	if piloted_world.is_empty():
		return false
	var lb_local: Dictionary = DockPortsScript.for_lifeboat(lifeboat_ship.built_layout)
	var lb_world: Vector3 = (lifeboat_ship.scene_root as Node3D).global_transform * (lb_local["position"] as Vector3)
	return lb_world.distance_to(piloted_world["position"] as Vector3) <= 0.5

## Phase 5b Task 5 validation seam: force-repair every subcomponent of every system
## on the piloted ship's shared systems manager, so propulsion (and scanners/nav) read
## operational and travel is permitted. Mirrors the per-system force_repair loops in
## travel_integration_smoke / repair_loop_smoke, hoisted into the coordinator.
func force_repair_all_for_validation() -> void:
	if ship_systems_manager == null:
		return
	for sid in ship_systems_manager.systems.keys():
		var sys = ship_systems_manager.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			ship_systems_manager.force_repair(sid, sub.subcomponent_id)

## Phase 5b Task 5 validation seam: in-range marker ids the player can travel to.
## Reuses scan()'s gated marker list (the same source travel_integration_smoke reads
## via markers_in_range), returning just the ids.
func scannable_marker_ids_for_validation() -> Array:
	var out: Array = []
	if synaptic_sea_world == null or scanner_state == null:
		return out
	for m in synaptic_sea_world.markers_in_range(scanner_state.range_radius):
		out.append(String(m.marker_id))
	return out

## Validation seam: the subset of in-range markers whose generated layouts actually
## contain a bridge room and are therefore claimable/pilotable. This makes smokes
## deterministic when nearby marker geometry changes: bridge presence is weighted,
## so raw in-range markers are no longer guaranteed to include a claimable host.
func claimable_marker_ids_for_validation() -> Array:
	var out: Array = []
	if synaptic_sea_world == null or scanner_state == null or ship_generator == null:
		return out
	for marker in synaptic_sea_world.markers_in_range(scanner_state.range_radius):
		if _marker_has_bridge_for_validation(marker):
			out.append(String(marker.marker_id))
	return out

func _marker_has_bridge_for_validation(marker) -> bool:
	if marker == null or ship_generator == null:
		return false
	# Match the live travel path's run context so bridge-presence previews stay
	# consistent with the actual built derelict (the variant selector is biome-driven).
	var ctx: Dictionary = _resolve_derelict_run_context(marker)
	ship_generator.configure_run_context(str(ctx.get("biome", "")), str(ctx.get("difficulty", "")))
	var built = ship_generator.generate_from_seed(int(marker.seed_value), int(marker.size_class), int(marker.condition))
	if built == null:
		return false
	var has_bridge: bool = built.has_method("get_layout_copy") and _layout_has_bridge(built.get_layout_copy())
	built.queue_free()
	return has_bridge

## Phase 5a Task 5 validation seam: count of distinct in-tree ship scene_roots
## currently parented under the coordinator. Returns 1 when only the home ship
## is present (no lifeboat or derelict), 2 when the home derelict + lifeboat are
## co-present at home (Task 7 canonical opening), or home + traveled derelict.
## Returns 3 when home + lifeboat + derelict are all present.
func active_ship_root_count_for_validation() -> int:
	var count := 0
	if home_ship != null and home_ship.scene_root != null and is_instance_valid(home_ship.scene_root) and home_ship.scene_root.get_parent() == self:
		count += 1
	# Phase 5a Task 7: lifeboat is a distinct in-tree root co-present at home.
	if lifeboat_ship != null and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root) and lifeboat_ship.scene_root.get_parent() == self:
		count += 1
	if current_ship != null and current_ship != home_ship and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root) and current_ship.scene_root.get_parent() == self:
		count += 1
	return count

## Phase 4.5 validation seam: the SynapticSeaWorld map model.
func get_synaptic_sea_world():
	return synaptic_sea_world

## Operational status feeding scan/travel. Travel capability always comes from the
## player's functional ship — the lifeboat (the coordinator-owned starting systems
## manager) — whether the player is on the lifeboat or boarded on a docked derelict.
## The lifeboat is the guaranteed ride, so a boarded derelict's broken systems never
## strand the player; an unrepaired lifeboat simply cannot jump until its propulsion
## is restored. (Retires ADR-0011 placeholder.)
func _current_systems_ops() -> Dictionary:
	# Travel capability comes from the ship the player is PILOTING (5c: that may be a
	# claimed derelict, not just the lifeboat). Fall back to the coordinator's starting
	# manager before a piloted ship exists.
	var mgr = piloted_ship.systems_manager if piloted_ship != null and piloted_ship.systems_manager != null else ship_systems_manager
	var propulsion_ok: bool = mgr != null and mgr.is_operational("propulsion")
	if propulsion_expanded_state != null:
		propulsion_ok = propulsion_ok and propulsion_expanded_state.can_propel()
	return {
		"navigation": mgr != null and mgr.is_operational("navigation"),
		"scanners": mgr != null and mgr.is_operational("scanners"),
		"propulsion": propulsion_ok,
	}

## Resolves the visible markers at the gated detail level, deriving operational
## status from the CURRENT ship's systems and scanner skill from progression.
func scan() -> Dictionary:
	if current_ship == null or synaptic_sea_world == null or scanner_state == null:
		return {"detail_level": 0, "markers": []}
	var ops: Dictionary = _current_systems_ops()
	var skill: int = 0
	if player_progression != null and player_progression.has_method("get_skill_level"):
		skill = int(player_progression.get_skill_level("scanner_operation"))
	var result: Dictionary = scanner_state.scan(synaptic_sea_world, ops, skill)
	# Domain 10 (ADR-0045) Source B: a possessed web_chart auto-records every
	# scan's markers at the scan's own detail_level. Scanning without a chart
	# records nothing (nothing to write on) -- no RNG, fully deterministic.
	if inventory_state != null and int(inventory_state.get_quantity("web_chart")) > 0:
		web_chart_state.record_views(result.get("markers", []) as Array, int(result.get("detail_level", 0)))
	return result

## Resolves a marker by id from the in-range set and travels to it. Returns
## {success:false, reason:"unknown_marker"} if the id is not currently in range.
func travel_to_marker_id(marker_id: String) -> Dictionary:
	if synaptic_sea_world == null or scanner_state == null:
		return {"success": false, "reason": "not_ready", "ship": null}
	for m in synaptic_sea_world.markers_in_range(scanner_state.range_radius):
		if String(m.marker_id) == marker_id:
			var result: Dictionary = travel_to(m)
			if bool(result.get("success", false)) and is_instance_valid(menu_coordinator):
				menu_coordinator.trigger_tutorial("ship_traveled", "any")
			return result
	return {"success": false, "reason": "unknown_marker", "ship": null}

## Makes `inst` the active boarded derelict: attaches the freshly built
## `new_root` at DERELICT_DOCK_OFFSET (so it is co-present with the home
## ship, which stays in-tree at origin), and flips away_from_start. Shared
## by travel_to (revisit/first-visit) and world-load (_apply_world_snapshot).
## Does NOT re-home the player — callers position the player afterwards.
## Phase 5a Task 5: home ship is NO LONGER detached. Home and derelict are
## co-present at distinct world positions (origin vs DERELICT_DOCK_OFFSET).
func _attach_derelict_active(inst, new_root: Node3D) -> void:
	# Live Persistent Ships Phase 4: fast-forward the absent ship's sim by elapsed world_time
	# before activating it. First visit: dt=0 (seeded), no-op. Revisit: applies the absence.
	_catch_up_ship(inst)
	inst.scene_root = new_root
	add_child(new_root)
	new_root.position = DERELICT_DOCK_OFFSET   # initial world anchor; piloted ship docks TO it
	if inst.built_layout.is_empty() and new_root.has_method("get_layout_copy"):
		inst.built_layout = new_root.get_layout_copy()
	current_ship = inst
	away_from_start = true
	# Domain 10 Task 5 fix (finding 2): reset the proximity-tooltip focus cache on
	# board too — objective types repeat across derelicts, so a stale subject_id
	# left over from the previous ship would suppress a legitimate re-query for a
	# same-typed interactable on THIS ship. Mirror _refresh_tooltip_focus's own
	# focus-lost clear transition (empty subject_id -> null payload -> panel hides).
	_last_tooltip_focus_subject_id = ""
	if is_instance_valid(menu_coordinator):
		menu_coordinator.set_tooltip_query({"subject_kind": "interactable", "subject_id": ""})
	# Phase 5b Task 5: the piloted ship (lifeboat) PHYSICALLY undocks from its old
	# host and re-docks to this derelict, so the ride — and the player aboard it —
	# moves with it. The player is carried by preserving their pose relative to the
	# piloted ship root across the dock move (the dock changes that root's transform).
	if piloted_ship != null:
		var carry := _capture_player_carry()
		var child_carry := _capture_subtree()
		_unbay_from_parent(piloted_ship)   # clear a stale bay slot if the piloted ship was bayed (PR#16 P2)
		DockingManagerScript.undock(piloted_ship)
		var dock_res: Dictionary = _dock_piloted_to(inst)
		if not bool(dock_res.get("success", false)):
			# Belt-and-suspenders: the travel_to precheck already rules out
			# incompatibility, but if a dock ever fails after undocking, re-dock to home
			# so the player is never physically stranded undocked.
			push_error("PlayableGeneratedShip: travel dock failed (%s) — re-docking piloted ship to home" % str(dock_res.get("reason", "?")))
			_dock_piloted_to(home_ship)
		else:
			if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
				audio_manager.play_sfx(AudioEventSeamScript.SFX_DOCK_LAND)
		_apply_player_carry(carry)
		_reposition_subtree(child_carry)
	_spawn_dock_barrier(inst)
	_spawn_bridge_terminal(inst)
	_spawn_hangar_control(inst)
	_spawn_cargo_hold_control(inst)
	_spawn_cart_controls_for_ship(inst)
	# Phase 5b Task 5: occupancy is the piloted ship — the player rides it to the host
	# and stays aboard (no teleport into the derelict). recompute_occupancy() then
	# tracks the player as they breach the dock seam and walk into the host.
	current_occupancy = piloted_ship if piloted_ship != null else inst
	_build_derelict_objectives()
	_build_loot_containers()
	_build_sealed_hatches()
	_build_repair_points()
	# Derelict-side breaches: variant-driven hull breaches (deterministic per seed).
	# Seeded BEFORE _build_breach_seal_points() so the seal-point builder sees
	# variant breaches in the hull and creates player-interactable seal nodes.
	# Also seeded before fire so the fire presence-gate exclusion can see variant
	# breaches (fire ordering preserved by being earlier than both fire calls).
	# Tranche 6 (REQ-RL-006): demo builds cap how many hazard KINDS a derelict
	# seeds (manifest multi_hazard.run params.max_hazards; -1 = unlimited in
	# dev/release). Cap order is the code's existing seed order: breach, fire, arc.
	_last_derelict_hazard_budget = _demo_max_hazards()
	_last_derelict_hazards_seeded = []
	if _last_derelict_hazard_budget != 0:
		_seed_derelict_breaches()
		_last_derelict_hazards_seeded.append("breach")
	_build_breach_seal_points()
	# Derelict-side fire: per-ship pre-seeded environmental fire (presence-gated, capped).
	if _last_derelict_hazard_budget < 0 or _last_derelict_hazard_budget > 1:
		_seed_derelict_fire()
		_last_derelict_hazards_seeded.append("fire")
	_build_fire_zones()
	# M7-B Task 9: manual extinguish nodes + recharge port share the fire lifecycle.
	_build_fire_suppression_points()
	_build_extinguisher_recharge_port()
	# Tranche 1 (audit): the derelict's own arc zones were dead data — build
	# them from the DERELICT loader (away_from_start is already true here).
	if _last_derelict_hazard_budget < 0 or _last_derelict_hazard_budget > 2:
		_build_arc_zone()
		_last_derelict_hazards_seeded.append("arc")
	_restore_arc_summary_for_current_ship()

## Captures the player's world pose relative to the piloted ship's scene_root so the
## player can be carried when the piloted ship is repositioned by a dock. Returns
## {} when there is no player / piloted root to anchor against.
func _capture_player_carry() -> Dictionary:
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return {}
	var root: Node3D = piloted_ship.scene_root as Node3D
	if player == null or not (player is Node3D) or not root.is_inside_tree():
		return {}
	# Local offset of the player within the piloted ship's frame (inverse * world).
	var local: Vector3 = root.global_transform.affine_inverse() * (player as Node3D).global_position
	return {"local": local}

## Re-applies a captured player carry after the piloted ship root moved, so the
## player ends up at the same spot INSIDE the (repositioned) piloted ship.
func _apply_player_carry(carry: Dictionary) -> void:
	if carry.is_empty() or piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return
	var root: Node3D = piloted_ship.scene_root as Node3D
	if player == null or not root.is_inside_tree() or not player.has_method("teleport_to"):
		return
	player.teleport_to(root.global_transform * (carry["local"] as Vector3))

## Captures EVERY transitive dock descendant of the piloted ship (airlock children
## and bayed children, any depth) relative to the piloted ship's root, BEFORE a dock
## move repositions that root. Returns [{inst, local_xform}, ...]. DFS generalization
## of the 5c one-level capture; depth-1 is just the first ring of the walk.
func _capture_subtree() -> Array:
	var out: Array = []
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return out
	var root_node: Node3D = piloted_ship.scene_root as Node3D
	if not root_node.is_inside_tree():
		return out
	var inv: Transform3D = root_node.global_transform.affine_inverse()
	var stack: Array = piloted_ship.docked_ships.duplicate()
	var seen: Dictionary = {}
	while not stack.is_empty():
		var child = stack.pop_back()
		if child == null or seen.has(child):
			continue
		seen[child] = true
		if is_instance_valid(child.scene_root) and (child.scene_root as Node3D).is_inside_tree():
			out.append({"inst": child, "local_xform": inv * (child.scene_root as Node3D).global_transform})
		for grandchild in child.docked_ships:
			if grandchild != null and not seen.has(grandchild):
				stack.append(grandchild)
	return out

## Re-applies captured descendant relatives AFTER the piloted root moved, so the
## whole nested group rides rigidly with it. Every descendant was captured in the
## piloted root's frame, so a single re-peg per node is depth-agnostic.
func _reposition_subtree(captured: Array) -> void:
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return
	var root_node: Node3D = piloted_ship.scene_root as Node3D
	if not root_node.is_inside_tree():
		return
	for entry_v in captured:
		var entry: Dictionary = entry_v
		var child = entry.get("inst", null)
		# child is a RefCounted ShipInstance (== null is the correct nil check); guard
		# is_inside_tree() before writing global_transform (no orphan-node write).
		if child == null or not is_instance_valid(child.scene_root) or not (child.scene_root as Node3D).is_inside_tree():
			continue
		(child.scene_root as Node3D).global_transform = root_node.global_transform * (entry["local_xform"] as Transform3D)

## Spawns the closed dock-seam barrier for `inst` at its dock-port world position,
## condition from the derelict's seed/condition. Home derelict is always intact.
func _spawn_dock_barrier(inst) -> void:
	_clear_dock_barriers()
	if inst == null or not is_instance_valid(inst.scene_root):
		return
	var local: Dictionary = DockPortsScript.for_derelict(inst.built_layout, _ship_seed(inst), _ship_condition_class(inst))
	if local.is_empty():
		return
	var cond: String = "intact" if inst == home_ship else str(local.get("condition", "intact"))
	var barrier = DockPortBarrierScript.new()
	# Local position under the derelict's scene_root (the port is ship-local).
	(inst.scene_root as Node3D).add_child(barrier)
	barrier.configure(String(inst.marker_id), cond, player_progression, local["position"] as Vector3, 6.0, 1.8)
	barrier.breach_opened.connect(_on_dock_barrier_opened)
	dock_barriers.append(barrier)

func _clear_dock_barriers() -> void:
	for b in dock_barriers:
		if is_instance_valid(b):
			if b.get_parent() != null:
				b.get_parent().remove_child(b)
			b.queue_free()
	dock_barriers.clear()

func _on_dock_barrier_opened(_marker_id: String) -> void:
	# Boarding the derelict is now possible; occupancy flips as the player crosses.
	recompute_occupancy()

## Ship-local center of `inst`'s bridge room (role == "bridge"), or Vector3.INF if the
## ship has NO bridge room. Derived from inst.built_layout via DockPorts so it works
## uniformly for the lifeboat (plain Node3D scene_root), procgen derelicts, and golden
## ships. Claimability requires a real bridge: a ship without one is not pilotable
## (just a loot/explore space) — deliberately NO entry-room fallback.
func _command_room_local_center(inst) -> Vector3:
	if inst == null or typeof(inst.built_layout) != TYPE_DICTIONARY or (inst.built_layout as Dictionary).is_empty():
		return Vector3.INF
	return DockPortsScript.bridge_center(inst.built_layout)

## Spawns the bridge terminal for a pilotable ship at its bridge room (ship-local),
## parented under the ship's scene_root so it inherits the ship transform and is
## freed with it. The home ship is never pilotable -> no terminal. A ship with NO
## bridge room gets NO terminal (it cannot be claimed/piloted — loot space only).
func _spawn_bridge_terminal(inst) -> void:
	if inst == null or inst == home_ship or not is_instance_valid(inst.scene_root):
		return
	var local_center: Vector3 = _command_room_local_center(inst)
	if local_center == Vector3.INF:
		return   # no bridge room -> not claimable
	# Prune dead entries + any existing terminal for this same ship (idempotent re-spawn).
	var kept: Array = []
	for t in bridge_terminals:
		if not is_instance_valid(t):
			continue
		if String(t.ship_id) == String(inst.ship_id):
			if t.get_parent() != null:
				t.get_parent().remove_child(t)
			t.queue_free()
			continue
		kept.append(t)
	bridge_terminals = kept
	var terminal = BridgeTerminalScript.new()
	(inst.scene_root as Node3D).add_child(terminal)
	terminal.configure(String(inst.ship_id), local_center, 1.8)
	terminal.login_requested.connect(_on_login_requested)
	bridge_terminals.append(terminal)

func _clear_bridge_terminals() -> void:
	for t in bridge_terminals:
		if is_instance_valid(t):
			if t.get_parent() != null:
				t.get_parent().remove_child(t)
			t.queue_free()
	bridge_terminals.clear()

## Reads inst.built_layout and (re)configures inst's HangarBay slot_count/size from
## DockPorts.for_hangar. No-op (leaves a 0-slot bay) when the ship has no hangar/cargo
## room. Returns the for_hangar descriptor (or {}).
func _configure_bay_from_layout(inst) -> Dictionary:
	if inst == null or typeof(inst.built_layout) != TYPE_DICTIONARY or (inst.built_layout as Dictionary).is_empty():
		return {}
	var desc: Dictionary = DockPortsScript.for_hangar(inst.built_layout, _ship_seed(inst))
	if desc.is_empty():
		return {}
	var bay = inst.get_hangar()
	# Preserve existing occupancy when re-configuring (e.g. on reload); only (re)size
	# when the bay is unconfigured, so a restored slot map is never clobbered.
	if bay.slot_count == 0:
		bay.slot_count = int(desc.get("slot_count", 0))
		bay.slot_size_class = int(desc.get("slot_size_class", 0))
		bay.slots.clear()
		for _i in range(bay.slot_count):
			bay.slots.append("")
	return desc

## Spawns a HangarBayControl for a ship that has a bay (hangar room, or the home
## ship's cargo fallback), parented under its scene_root. Unlike the bridge terminal,
## the HOME ship IS allowed a bay. Idempotent: prunes any existing control for the
## same carrier id. No-op when the ship has no bay.
func _spawn_hangar_control(inst) -> void:
	if inst == null or not is_instance_valid(inst.scene_root):
		return
	var desc: Dictionary = _configure_bay_from_layout(inst)
	if desc.is_empty():
		return
	var anchors: Array = desc.get("slot_anchors", [])
	if anchors.is_empty():
		return
	# Place the control at the centroid of the slot anchors (bay center).
	var center := Vector3.ZERO
	for a in anchors:
		center += a as Vector3
	center /= float(anchors.size())
	# Prune dead entries + any existing control for this same carrier (idempotent).
	var kept: Array = []
	for c in hangar_controls:
		if not is_instance_valid(c):
			continue
		if String(c.carrier_id) == String(inst.ship_id):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
			continue
		kept.append(c)
	hangar_controls = kept
	var control = HangarBayControlScript.new()
	(inst.scene_root as Node3D).add_child(control)
	control.configure(String(inst.ship_id), center, 1.8)
	control.bay_dock_requested.connect(_on_bay_dock_requested)
	control.bay_launch_requested.connect(_on_bay_launch_requested)
	hangar_controls.append(control)

func _clear_hangar_controls() -> void:
	for c in hangar_controls:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	hangar_controls.clear()

func _spawn_cargo_hold_control(inst) -> void:
	if inst == null or not is_instance_valid(inst.scene_root):
		return
	# Tranche 6 (REQ-RL-006): demo builds cap the ship cargo hold BEFORE the
	# cargo-room check — in demo the hold is eagerly created capped, so every
	# later lazy get_inventory() consumer (deposits, snapshots) sees the cap.
	# No-op in dev/release (preserves the "no lazy ShipInventory" intent below).
	_apply_demo_cargo_cap(inst)
	var center: Vector3 = DockPortsScript._room_floor_center(inst.built_layout, "cargo", "cargo")
	if center == Vector3.INF:
		return   # no cargo room -> no hold, no lazy ShipInventory
	# Prune dead entries + any existing control for this same carrier (idempotent).
	var kept: Array = []
	for c in cargo_hold_controls:
		if not is_instance_valid(c):
			continue
		if String(c.carrier_id) == String(inst.ship_id):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
			continue
		kept.append(c)
	cargo_hold_controls = kept
	var control = CargoHoldControlScript.new()
	(inst.scene_root as Node3D).add_child(control)
	control.configure(String(inst.ship_id), center, 1.8)
	control.cargo_deposit_requested.connect(_on_cargo_deposit_requested)
	control.cargo_withdraw_requested.connect(_on_cargo_withdraw_requested)
	cargo_hold_controls.append(control)

func _clear_cargo_hold_controls() -> void:
	for c in cargo_hold_controls:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	cargo_hold_controls.clear()

## Spawn a CartControl node for an existing CartState parked on `inst`.
## Idempotent per cart_id: prunes any existing control for the same cart_id first.
func _spawn_cart_control(inst, cart) -> void:
	if inst == null or cart == null or not is_instance_valid(inst.scene_root):
		return
	# Prune dead entries + any existing control for this same cart_id (idempotent).
	var kept: Array = []
	for c in cart_controls:
		if not is_instance_valid(c):
			continue
		if String(c.cart_id) == String(cart.cart_id):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
			continue
		kept.append(c)
	cart_controls = kept
	var control = CartControlScript.new()
	(inst.scene_root as Node3D).add_child(control)
	control.configure(String(cart.cart_id), cart.parked_position, 1.8)
	control.cart_grab_requested.connect(_on_cart_grab_requested)
	control.cart_load_requested.connect(_on_cart_load_requested)
	control.cart_unload_requested.connect(_on_cart_unload_requested)
	cart_controls.append(control)

## Ensures a cargo-capable ship has at least one parked salvage cart so the
## cart loop is organically reachable (grab/load/unload) without the validation
## seam. No-op when carts already exist, or when no cargo/hangar room can host
## a park position. Idempotent.
func _ensure_organic_cart(inst) -> void:
	if inst == null:
		return
	if not inst.get_carts().is_empty():
		return
	var layout: Dictionary = inst.built_layout if typeof(inst.built_layout) == TYPE_DICTIONARY else {}
	if layout.is_empty():
		return
	var center: Vector3 = DockPortsScript._room_floor_center(layout, "cargo", "cargo")
	if center == Vector3.INF:
		center = DockPortsScript._room_floor_center(layout, "hangar", "hangar")
	if center == Vector3.INF:
		return
	# Distinct id from spawn_cart_for_validation ("cart_<ship_id>") so smokes
	# that still inject a validation cart do not collide on cart_id.
	var cart = CartStateScript.create("organic_cart_%s" % String(inst.ship_id), 200.0)
	cart.parked_ship_id = String(inst.ship_id)
	# Offset slightly from hold control so the two interactables do not stack.
	cart.parked_position = center + Vector3(1.5, 0.0, 0.0)
	inst.get_carts().append(cart)

func _spawn_cart_controls_for_ship(inst) -> void:
	if inst == null:
		return
	_ensure_organic_cart(inst)
	for cart in inst.get_carts():
		_spawn_cart_control(inst, cart)

func _clear_cart_controls() -> void:
	for c in cart_controls:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	cart_controls.clear()

func _find_cart_by_id(cart_id: String) -> Dictionary:
	for inst in _all_known_ships():
		for cart in inst.get_carts():
			if String(cart.cart_id) == cart_id:
				return {"cart": cart, "ship": inst}
	return {}

func _on_cart_grab_requested(cart_id: String) -> void:
	var hit: Dictionary = _find_cart_by_id(cart_id)
	if hit.is_empty():
		return
	grabbed_cart = hit["cart"]
	_recompute_player_encumbrance()      # applies the push penalty

func _on_cart_load_requested(cart_id: String) -> void:
	_open_transfer_panel_for_cart(cart_id)

func _on_cart_unload_requested(cart_id: String, _category: String) -> void:
	_open_transfer_panel_for_cart(cart_id)

func _on_cargo_deposit_requested(ship_id: String) -> void:
	_open_transfer_panel_for_ship(ship_id)

func _on_cargo_withdraw_requested(ship_id: String, _category: String) -> void:
	_open_transfer_panel_for_ship(ship_id)

## Recompute the player's effective carry budget from worn equipment and apply the
## Heavy Load movement penalty (× any active cart push penalty). Called on every
## inventory/equipment/cart change.
func _recompute_player_encumbrance() -> void:
	if inventory_state == null:
		return
	var bonus: float = 0.0
	var saved: float = 0.0
	if equipment_state != null:
		bonus = equipment_state.get_carry_capacity_bonus()   # + future strength bonus
		saved = EncumbranceScript.weight_reduction_saved(
			inventory_state.get_total_weight(), equipment_state.get_container_reductions())
	inventory_state.bonus_capacity = bonus
	inventory_state.weight_reduction = saved
	if is_instance_valid(player):
		var mult: float = EncumbranceScript.move_speed_multiplier(inventory_state.get_load_ratio())
		player.move_speed = float(player.DEFAULT_MOVE_SPEED) * mult * _cart_push_multiplier()

## Equip item_id from the player inventory into its slot. Honors the both-hands
## cart block. `auto` (pickup path) only fills EMPTY slots; manual equip displaces
## the worn item back into inventory. Returns true on success.
func _equip_from_inventory(item_id: String, auto: bool) -> bool:
	if equipment_state == null or inventory_state == null:
		return false
	if not equipment_state.can_equip(item_id):
		return false
	var slot: String = ItemDefsScript.equip_slot(_definitions_for_equip(), item_id)
	if (slot == "primary_hand" or slot == "secondary_hand") and _is_cart_grabbed():
		return false   # both hands occupied by a grabbed cart
	if auto and equipment_state.is_slot_occupied(slot):
		return false   # auto-equip never swaps a filled slot
	if inventory_state.get_quantity(item_id) <= 0:
		return false
	inventory_state.remove_item(item_id, 1)
	var res: Dictionary = equipment_state.equip(item_id)
	if not bool(res.get("ok", false)):
		inventory_state.add_item(item_id, 1)   # equip failed -> put it back
		return false
	var displaced: String = str(res.get("displaced", ""))
	if displaced != "":
		inventory_state.add_item(displaced, 1)
	_recompute_player_encumbrance()
	return true

## Unequip a slot back into the player inventory. Returns the unequipped id ("" if empty).
func _unequip_to_inventory(slot: String) -> String:
	if equipment_state == null or inventory_state == null:
		return ""
	var item_id: String = equipment_state.unequip(slot)
	if item_id != "":
		inventory_state.add_item(item_id, 1)
		_recompute_player_encumbrance()
	return item_id

func _definitions_for_equip() -> Dictionary:
	# The merged item-def catalog, lazily loaded once and cached. ItemDefs.load_definitions()
	# does synchronous disk I/O parsing several JSON files; caching avoids repeating that on
	# every equip / auto-equip during gameplay loops (the defs are static at runtime).
	if _item_defs.is_empty():
		_item_defs = ItemDefsScript.load_definitions()
	return _item_defs

func _is_cart_grabbed() -> bool:
	return grabbed_cart != null

func _cart_push_multiplier() -> float:
	return float(grabbed_cart.push_speed_multiplier) if grabbed_cart != null else 1.0

## A ship currently airlock-docked to `carrier` (parent_ship == carrier) that is NOT
## already bayed there and whose airlock port size_class fits a free slot. null if none.
func _bay_dock_candidate(carrier):
	if carrier == null:
		return null
	var bay = carrier.get_hangar()
	for child in carrier.docked_ships:
		if child == null or not is_instance_valid(child.scene_root):
			continue
		if bay.slot_of(String(child.ship_id)) != -1:
			continue   # already bayed
		var size_class: int = _ship_dock_size_class(child)
		if bay.free_slot_for(size_class) != -1:
			return child
	return null

## A ship's own dock/airlock port size_class (1 today for every ship). Reads its
## airlock port when present, else the dock port, else AIRLOCK_SIZE_CLASS.
func _ship_dock_size_class(inst) -> int:
	if inst == null or typeof(inst.built_layout) != TYPE_DICTIONARY:
		return DockPortsScript.AIRLOCK_SIZE_CLASS
	var p: Dictionary = DockPortsScript.for_lifeboat(inst.built_layout)
	if p.is_empty():
		p = DockPortsScript.for_derelict(inst.built_layout)
	return int(p.get("size_class", DockPortsScript.AIRLOCK_SIZE_CLASS))

func _first_occupied_slot(bay) -> int:
	for i in range(bay.slots.size()):
		if String(bay.slots[i]) != "":
			return i
	return -1

## Places `mobile` at carrier-local slot anchor `slot_index` (world transform).
func _place_in_slot(carrier, mobile, slot_index: int) -> void:
	if carrier == null or mobile == null:
		return
	if not is_instance_valid(carrier.scene_root) or not is_instance_valid(mobile.scene_root):
		return
	# Both roots must be in-tree before a global_transform write (we write mobile's below).
	if not (carrier.scene_root as Node3D).is_inside_tree() or not (mobile.scene_root as Node3D).is_inside_tree():
		return
	var desc: Dictionary = DockPortsScript.for_hangar(carrier.built_layout, _ship_seed(carrier))
	var anchors: Array = desc.get("slot_anchors", [])
	if slot_index < 0 or slot_index >= anchors.size():
		return
	var anchor: Vector3 = anchors[slot_index]
	(mobile.scene_root as Node3D).global_transform = (carrier.scene_root as Node3D).global_transform * Transform3D(Basis(), anchor)

## Docks a co-present airlock-docked ship into a free hangar slot of `carrier_id`.
## Silent refusal (no candidate / no slot / not co-present). slot_index is advisory
## (-1 = first free).
func _on_bay_dock_requested(carrier_id: String, slot_index: int) -> void:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return
	var bay = carrier.get_hangar()
	if bay.slot_count <= 0:
		return
	var candidate = _bay_dock_candidate(carrier)
	if candidate == null:
		return   # silent: not_co_present / no_free_slot / incompatible_size
	var size_class: int = _ship_dock_size_class(candidate)
	var idx: int = bay.dock(String(candidate.ship_id), size_class)
	if idx == -1:
		return
	# Transition the candidate from airlock-docked to slot-bayed: drop its airlock
	# alignment, keep it a dock child of the carrier, and re-peg it to the slot anchor.
	DockingManagerScript.undock(candidate)
	candidate.parent_ship = carrier
	if not carrier.docked_ships.has(candidate):
		carrier.docked_ships.append(candidate)
	_place_in_slot(carrier, candidate, idx)
	recompute_occupancy()

## Launches a bayed ship of `carrier_id` back out to a co-present anchor near the
## carrier. slot_index -1 = first occupied. Silent refusal when nothing is bayed.
func _on_bay_launch_requested(carrier_id: String, slot_index: int) -> void:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return
	var bay = carrier.get_hangar()
	var idx := slot_index
	if idx < 0:
		idx = _first_occupied_slot(bay)
	if idx < 0:
		return
	var ship_id: String = bay.launch(idx)
	if ship_id == "":
		return
	var launched = _find_ship_by_id(ship_id)
	if launched == null:
		return
	launched.parent_ship = null
	carrier.docked_ships.erase(launched)
	if is_instance_valid(launched.scene_root) and is_instance_valid(carrier.scene_root) \
			and (carrier.scene_root as Node3D).is_inside_tree() \
			and (launched.scene_root as Node3D).is_inside_tree():
		# Park it just outside the bay (carrier-local -Z), co-present and free.
		(launched.scene_root as Node3D).global_transform = \
			(carrier.scene_root as Node3D).global_transform * Transform3D(Basis(), Vector3(0.0, 0.0, -8.0))
	recompute_occupancy()

## Clears `inst`'s hangar slot in its parent's bay BEFORE the ship leaves via a
## non-launch path (the travel undock of a bayed piloted ship). Without this, a ship
## that undocks while still occupying a bay slot leaves a stale slot id: the slot stays
## unusable and the ship's next airlock re-dock is misclassified as a hangar edge by
## _current_dock_edges (Codex PR#16 P2). Must run BEFORE DockingManager.undock (which
## nulls parent_ship). No-op when the ship is not bayed.
func _unbay_from_parent(inst) -> void:
	if inst == null or inst.parent_ship == null:
		return
	var parent = inst.parent_ship
	if parent.hangar == null:
		return
	var s: int = parent.hangar.slot_of(String(inst.ship_id))
	if s != -1:
		parent.hangar.launch(s)

## Builds the active derelict's objective interactables from its loader specs and
## restores completed/cleared state from its (retained or loaded) controller. Called
## whenever a derelict becomes active. No-op on the home ship.
func _build_derelict_objectives() -> void:
	_clear_derelict_objectives()
	_salvage_loot_tables.clear()
	if current_ship == null or String(current_ship.marker_id) == "":
		return
	var active_loader = current_ship.scene_root
	if not is_instance_valid(active_loader) or not active_loader.has_method("get_objective_specs_copy"):
		return
	var specs: Array = active_loader.get_objective_specs_copy()
	var controller = current_ship.get_objective_controller()
	# First visit registers the set; a retained/restored controller is already
	# configured, so this is a no-op that preserves progress.
	controller.configure(specs)
	for spec_variant in specs:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var sequence: int = int(spec.get("sequence", 0))
		if sequence <= 0:
			continue
		var position_variant: Variant = spec.get("position", Vector3.INF)
		if typeof(position_variant) != TYPE_VECTOR3:
			continue
		# Record salvage objective loot tables for grant on completion.
		if str(spec.get("type", "")) == "salvage":
			_salvage_loot_tables[str(spec.get("id", ""))] = str(spec.get("loot_table", "salvage_cargo"))
		var interactable = InteractableScript.new()
		interactable.configure_from_objective(spec, position_variant, 1.8)
		interactable.interaction_completed.connect(_on_derelict_interactable_completed)
		# Restore: a persisted-complete objective reads as done and cannot be re-fired
		# (try_interact returns false when completed).
		if controller.is_objective_complete(sequence):
			interactable.completed = true
			interactable.set_active(false)
		# Phase 5a Task 5 (co-presence): parent the interactable under the derelict's
		# scene_root so it inherits the DERELICT_DOCK_OFFSET transform and is freed
		# automatically when the derelict scene_root is freed on departure.
		current_ship.scene_root.add_child(interactable)
		derelict_interactables.append(interactable)
	# Show the derelict's objectives in the HUD while aboard, then reflect any
	# persisted/restored completion (set_objectives resets the tracker's completed
	# set, so this must run after it).
	if tracker != null:
		tracker.set_objectives(specs)
		_refresh_derelict_tracker()

## Mirrors the active derelict's controller state into the ObjectiveTracker: marks
## completed sequences, advances the "Current" pointer to the lowest incomplete
## objective, and flags run-complete once the derelict is cleared. Idempotent
## (tracker.mark_completed keys a dict), so it serves both restore-on-board and
## per-completion updates. No-op on the home ship (driven by the singleton loop).
func _refresh_derelict_tracker() -> void:
	if tracker == null or current_ship == null or String(current_ship.marker_id) == "":
		return
	var controller = current_ship.get_objective_controller()
	var first_incomplete: int = -1
	for it in derelict_interactables:
		if not is_instance_valid(it):
			continue
		var seq: int = int(it.sequence)
		if controller.is_objective_complete(seq):
			tracker.mark_completed(seq)
		elif first_incomplete < 0 or seq < first_incomplete:
			first_incomplete = seq
	if controller.is_cleared():
		tracker.mark_run_complete()
	elif first_incomplete > 0:
		tracker.set_current_sequence(first_incomplete)

## Frees the active derelict's interactables. The controller (state) lives on the
## ShipInstance and is untouched.
## Phase 5a Task 5 (co-presence): interactables are parented under the derelict
## scene_root (freed with it on departure) rather than derelict_objective_root
## (which remains empty). derelict_objective_root is kept as an empty placeholder
## so the coordinator structure is unchanged. Just clear the reference array here;
## nodes parented under scene_root are freed when scene_root is freed.
func _clear_derelict_objectives() -> void:
	if is_instance_valid(derelict_objective_root):
		for child in derelict_objective_root.get_children():
			derelict_objective_root.remove_child(child)
			child.queue_free()
	derelict_interactables.clear()

## Pushes the current inventory state to the HUD. Reuses _refresh_tracker_system_status_lines
## so the full combined status (systems + oxygen + inventory) is always consistent.
func _refresh_inventory_hud() -> void:
	_refresh_tracker_system_status_lines()

## Builds scattered loot containers for the active ship (derelict or home lifeboat).
## Containers already in the ship's looted_container_ids read as searched (no respawn).
## Sub-project #4: the home ship early-return is removed; the home loader is used when home.
func _build_loot_containers() -> void:
	_clear_loot_containers()
	if current_ship == null:
		return
	var active_loader = current_ship.scene_root if (away_from_start and current_ship != null) else loader
	if not is_instance_valid(active_loader) or not active_loader.has_method("get_loot_container_specs_copy"):
		return
	var looted: Array = current_ship.looted_container_ids
	for spec_variant in active_loader.get_loot_container_specs_copy():
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var cid: String = str(spec.get("id", ""))
		var pos_variant: Variant = spec.get("position", Vector3.INF)
		if cid.is_empty() or typeof(pos_variant) != TYPE_VECTOR3:
			continue
		var lc = LootContainerScript.new()
		var seed_source: String = "%s:%s" % [String(current_ship.marker_id), cid]
		lc.configure(cid, str(spec.get("loot_table", "generic_crate")), seed_source,
			inventory_state, _loot_tables, pos_variant, 1.8, _build_loot_context(spec))
		if looted.has(cid):
			lc.set_searched(true)
		# Bind the container node so the handler can pass its world position
		# into play_sfx (spatial pickup audio, REQ-AU-005).
		var searched_cb: Callable = _on_loot_container_searched.bind(lc)
		if not lc.container_searched.is_connected(searched_cb):
			lc.container_searched.connect(searched_cb)
		# Phase 5a Task 5 (co-presence): derelict loot containers parent under the
		# derelict's scene_root so they inherit DERELICT_DOCK_OFFSET and are freed
		# automatically with the derelict on departure. Home loot containers continue
		# to parent under the coordinator-owned loot_container_root at origin.
		if away_from_start and current_ship != null and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
			current_ship.scene_root.add_child(lc)
		else:
			loot_container_root.add_child(lc)
		loot_containers.append(lc)
	# Domain 2: re-spawn unsearched combat corpses after layout crates so leave
	# + revisit / save-load keep kill drops reachable until searched.
	_spawn_pending_corpse_loot_containers()

func _clear_loot_containers() -> void:
	if is_instance_valid(loot_container_root):
		for child in loot_container_root.get_children():
			loot_container_root.remove_child(child)
			child.queue_free()
	# Phase 5a Task 5 (co-presence): derelict loot containers parent under
	# current_ship.scene_root rather than loot_container_root, so loot_container_root
	# only holds home-ship containers. The derelict containers are freed when
	# scene_root is freed on departure — just clear the reference array.
	loot_containers.clear()

## Domain 5: seeds locked passage hatches on the active derelict, deterministically
## per ship marker_id. Two hatches alternate mechanical/electronic lock kind.
## No-op when not away_from_start (hatches are derelict-only) or no positions exist.
func _build_sealed_hatches() -> void:
	_clear_sealed_hatches()
	if current_ship == null:
		return
	if not away_from_start:
		return
	var positions: Array = _distributed_room_positions()
	if positions.is_empty():
		return
	var bypassed: Array = current_ship.bypassed_hatch_ids
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(current_ship.marker_id))
	var count: int = mini(SEALED_HATCH_COUNT, positions.size())
	for i in range(count):
		var idx: int = (int(rng.randi()) + i * 7) % positions.size()
		var pos_variant: Variant = positions[idx]
		if typeof(pos_variant) != TYPE_VECTOR3:
			continue
		var hid: String = "%s:hatch_%d" % [String(current_ship.marker_id), i]
		var lock_kind: String = SealedHatchScript.MECHANICAL if (i % 2 == 0) else SealedHatchScript.ELECTRONIC
		var hatch = SealedHatchScript.new()
		hatch.configure(hid, lock_kind, pos_variant, 1.8)
		if bypassed.has(hid):
			hatch.set_bypassed(true)
		if not hatch.hatch_bypassed.is_connected(_on_hatch_bypassed):
			hatch.hatch_bypassed.connect(_on_hatch_bypassed)
		if current_ship != null and is_instance_valid(current_ship.scene_root):
			current_ship.scene_root.add_child(hatch)
		sealed_hatches.append(hatch)

func _clear_sealed_hatches() -> void:
	for h in sealed_hatches:
		if is_instance_valid(h):
			h.queue_free()
	sealed_hatches.clear()

## Builds repair points for every currently-damaged subcomponent of the active ship,
## distributing them across the ship's rooms. Works for the lifeboat (home) and derelicts.
func _build_repair_points() -> void:
	_clear_repair_points()
	if not is_instance_valid(repair_point_root):
		return
	var mgr = _active_systems_manager()
	if mgr == null:
		return
	# Phase 5a fix (Codex P1): HOME repair points parent under lifeboat_ship.scene_root
	# (now port-docked to the home airlock), so their positions must be LIFEBOAT-LOCAL —
	# otherwise the derelict-frame _distributed_room_positions() values get the lifeboat
	# transform added and the (travel-gating) propulsion repair lands OUTSIDE the lifeboat.
	# The away-derelict branch parents under current_ship.scene_root, whose derelict-frame
	# positions correctly match its geometry — so it keeps _distributed_room_positions().
	var use_lifeboat: bool = (not away_from_start) and lifeboat_ship != null \
		and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root)
	var positions: Array = _lifeboat_local_repair_positions() if use_lifeboat else _distributed_room_positions()
	if positions.is_empty():
		return
	var idx: int = 0
	for sid in mgr.system_order:
		var system = mgr.get_system(sid)
		if system == null:
			continue
		for sub in system.subcomponents:
			if sub.is_functional():
				continue
			var pos: Vector3 = positions[idx % positions.size()]
			idx += 1
			var rp = RepairPointScript.new()
			rp.configure(sid, sub.subcomponent_id, mgr, inventory_state, player_progression,
				pos, sub.repair_seconds, sub.min_skill, 1.8)
			if not rp.repair_completed.is_connected(_on_repair_completed):
				rp.repair_completed.connect(_on_repair_completed)
			if not rp.repair_blocked.is_connected(_on_repair_blocked):
				rp.repair_blocked.connect(_on_repair_blocked)
			# Phase 5a Task 5 (co-presence): derelict repair points parent under the
			# derelict's scene_root so they inherit DERELICT_DOCK_OFFSET and are freed
			# automatically with the derelict on departure.
			# Phase 5a Task 7: HOME repair points (the lifeboat's nav_linkage blocker)
			# parent under lifeboat_ship.scene_root so the player physically repairs
			# inside the docked lifeboat. Falls back to repair_point_root if the
			# lifeboat has not been built yet.
			if away_from_start and current_ship != null and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
				current_ship.scene_root.add_child(rp)
			elif lifeboat_ship != null and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root):
				lifeboat_ship.scene_root.add_child(rp)
			else:
				repair_point_root.add_child(rp)
			repair_points.append(rp)

func _clear_repair_points() -> void:
	if is_instance_valid(repair_point_root):
		for child in repair_point_root.get_children():
			repair_point_root.remove_child(child)
			child.queue_free()
	# Phase 5a Task 7: home repair points are now parented under lifeboat_ship.scene_root.
	# Free any that are still parented there (e.g., on a same-ship reload that bypasses the
	# derelict-departure path). Derelict repair points parent under current_ship.scene_root and
	# are freed when that root is freed on departure — no action needed for them here.
	for rp in repair_points:
		if is_instance_valid(rp) and rp.get_parent() != repair_point_root:
			var rp_parent = rp.get_parent()
			if rp_parent != null and is_instance_valid(rp_parent):
				rp_parent.remove_child(rp)
			rp.queue_free()
	# Phase 5a Task 5 (co-presence): derelict repair points parent under
	# current_ship.scene_root rather than repair_point_root, so repair_point_root
	# only holds fallback home-ship repair points. The derelict repair points
	# are freed when scene_root is freed on departure — just clear the array.
	repair_points.clear()

func _build_breach_seal_points() -> void:
	_clear_breach_seal_points()
	var hull = _active_hull()
	if hull == null:
		return
	# Only seal breached compartments; healthy hull needs no seal node.
	var breached: Array = []
	for cid in hull.compartments:
		if bool((hull.compartments[cid] as Dictionary).get("breach_open", false)):
			breached.append(str(cid))
	if breached.is_empty():
		return
	var use_lifeboat: bool = (not away_from_start) and lifeboat_ship != null \
		and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root)
	var positions: Array = _lifeboat_local_repair_positions() if use_lifeboat else _distributed_room_positions()
	if positions.is_empty():
		return
	var idx: int = 0
	for cid in breached:
		var pos: Vector3 = positions[idx % positions.size()]
		idx += 1
		var sp = BreachSealPointScript.new()
		sp.configure(cid, hull, inventory_state, player_progression, pos, 4.0, "hull_sealant", 1.0, 1.8)
		if not sp.breach_sealed.is_connected(_on_breach_sealed):
			sp.breach_sealed.connect(_on_breach_sealed)
		# Tranche 1 (audit): seal_blocked fired on four failure paths but was
		# never connected — a blocked seal gave zero player feedback.
		if not sp.seal_blocked.is_connected(_on_seal_blocked):
			sp.seal_blocked.connect(_on_seal_blocked)
		if away_from_start and current_ship != null and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
			current_ship.scene_root.add_child(sp)
		elif lifeboat_ship != null and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root):
			lifeboat_ship.scene_root.add_child(sp)
		else:
			repair_point_root.add_child(sp)
		breach_seal_points.append(sp)

func _clear_breach_seal_points() -> void:
	for sp in breach_seal_points:
		if is_instance_valid(sp):
			var parent = sp.get_parent()
			if parent != null and is_instance_valid(parent):
				parent.remove_child(sp)
			sp.queue_free()
	breach_seal_points.clear()

func _on_breach_sealed(compartment_id: String) -> void:
	# HullIntegrityState is already mutated by the seal node; the next
	# _recompute_expanded_ship_systems picks up the lower breach_count.
	# Tranche 1 (audit): this was a pass-only no-op — surface the seal on the
	# HUD feedback line and fire the tool-use cue so the action lands.
	_set_hazard_feedback_line("Breach sealed: %s" % compartment_id)
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx(AudioEventSeamScript.SFX_TOOL_USE)

## Tranche 1 (audit): shared surface for hazard-interaction feedback. Reuses
## the _last_loot_feedback_line channel (the one line _combined_system_status_lines
## already folds into the HUD) — no new HUD framework, matching the caption
## pattern documented at the var declaration.
func _set_hazard_feedback_line(text: String) -> void:
	_last_loot_feedback_line = text
	_refresh_tracker_system_status_lines()

func _on_extinguish_blocked(compartment_id: String, reason: String) -> void:
	_set_hazard_feedback_line("Extinguish blocked (%s): %s" % [compartment_id, _hazard_block_reason_text(reason)])

func _on_seal_blocked(compartment_id: String, reason: String) -> void:
	_set_hazard_feedback_line("Seal blocked (%s): %s" % [compartment_id, _hazard_block_reason_text(reason)])

func _hazard_block_reason_text(reason: String) -> String:
	match reason:
		"missing_extinguisher": return "no fire extinguisher"
		"missing_sealant": return "no hull sealant"
		"no_charge": return "extinguisher empty"
		"not_burning": return "no fire here"
		"not_breached": return "no open breach"
		"extinguish_failed": return "extinguish failed"
		_: return "cannot complete"

# --- M7-B Task 7: authoritative compartment fire ----------------------------
# The old timer-based FireState is retired. FireSuppressionState is the single
# source of truth; the coordinator ticks it against a per-frame context and
# renders the burning set as PASSABLE Area3D zones (the player can walk into a
# fire). Tasks 8/9 add vitals/system teeth and recharge wiring on top of the
# same context + lifecycle built here.

func _fire_tuning() -> Dictionary:
	return _load_json_dict(SHIP_SUBSYSTEM_TUNING_PATH).get("fire_suppression", {})

## Configures a per-ship derelict FireSuppressionState from shared tuning (compartments,
## adjacency, rates). Required before seeding or after restoring from a summary so spread
## topology exists.
func _configure_derelict_fire(fs) -> void:
	if fs != null:
		fs.configure(_fire_tuning())

## Scans the boarded derelict's built layout for rooms whose variant carries a
## hazard of `kind` ("fire" or "breach") AND whose role maps to a real
## compartment. Returns the deterministic, de-duplicated, sorted compartment id
## list. Empty when no such variant landed on a mapped role.
func _variant_hazard_compartments(kind: String) -> Array:
	var out: Dictionary = {}
	if current_ship == null:
		return []
	var layout: Dictionary = current_ship.built_layout
	# Derelict layout is populated by the attach path before seeding; no home-loader
	# fallback — wrong ship.
	if layout.is_empty():
		return []
	var rooms_variant: Variant = layout.get("rooms", [])
	if not (rooms_variant is Array):
		return []
	var selector := RoomVariantSelectorHazardScript.new()
	for room_variant in (rooms_variant as Array):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var role: String = str(room.get("room_role", room.get("role", "")))
		var compartment: String = str(COMPARTMENT_FOR_ROLE.get(role, ""))
		if compartment.is_empty():
			continue
		var variant: String = str(room.get("variant", "standard"))
		var hazard: Dictionary = (selector.effects_for(variant).get("sim", {}) as Dictionary).get("hazard", {})
		if str(hazard.get("kind", "")) == kind:
			out[compartment] = true
	var result: Array = out.keys()
	result.sort()
	return result

## Pre-seeds environmental fire on a freshly built derelict. Deterministic, RNG-free:
## a per-seed presence gate (FIRE_PRESENCE_PERCENT) decides whether THIS derelict burns at
## all; when it does, ignites up to a condition-scaled cap of compartments whose mapped
## system is damaged (and not breached). Never called on the home/lifeboat ship or on the
## save-restore path (restored fire comes from the applied ShipInstance "fire" summary).
func _seed_derelict_fire() -> void:
	if not away_from_start or current_ship == null:
		return
	if current_ship.fire_seeded:
		return  # already seeded (revisit) or restored from save — preserve the player's burning set
	var fs = current_ship.get_fire()
	if fs == null:
		return
	_configure_derelict_fire(fs)
	# Mark seeded on the first build regardless of whether the presence gate lit anything,
	# so a fire-free derelict is not re-rolled on revisit/reload.
	current_ship.fire_seeded = true
	var seed_int: int = _ship_seed(current_ship)
	# Variant-forced fire: a fire-kind variant on a compartment-mapped room
	# means that derelict burns there regardless of the presence roll.
	var forced_fire: Array = _variant_hazard_compartments("fire")
	for cid in forced_fire:
		fs.ignite(str(cid), 1.0)
	# Presence gate — most derelicts board fire-free (variant fires already lit).
	if (abs(hash("%d:fire_presence" % seed_int)) % 100) >= FIRE_PRESENCE_PERCENT:
		return
	var mgr = _active_systems_manager()
	if mgr == null:
		return
	# Candidate compartments: mapped system damaged, not breached. Deterministic order.
	# Read the ACTIVE hull (derelict's own hull when away) so the exclusion sees
	# the derelict's breaches, not the home hull singleton.
	var active_hull = _active_hull()
	var breached := {}
	if active_hull != null:
		for cid in active_hull.compartments:
			if bool((active_hull.compartments[cid] as Dictionary).get("breach_open", false)):
				breached[str(cid)] = true
	var candidates: Array = []
	for cid in FIRE_COMPARTMENT_SYSTEM:
		var sid: String = str(FIRE_COMPARTMENT_SYSTEM[cid])
		if sid.is_empty() or breached.has(str(cid)):
			continue
		var sys = mgr.get_system(sid)
		if sys != null and not sys.is_self_functional():
			candidates.append(str(cid))
	candidates.sort()
	var cap: int = 2 + (1 if _ship_condition_class(current_ship) == ShipBlueprint.Condition.WRECKED else 0)
	var lit: int = 0
	for cid in candidates:
		if lit >= cap:
			break
		fs.ignite(cid, 1.0)
		lit += 1

## Away-branch only: force-breaches compartments of rooms carrying a breach-kind
## variant on the boarded derelict — on the DERELICT'S OWN hull model
## (current_ship.get_hull()), mirroring _seed_derelict_fire's use of
## current_ship.get_fire(). NOT the bare hull_integrity_state member: that is the
## coordinator's home/hub hull singleton (see _active_hull()). Deterministic;
## guarded by breach_seeded so revisits/restores don't re-seed (restored breaches
## come from the derelict instance's applied hull summary).
func _seed_derelict_breaches() -> void:
	if not away_from_start or current_ship == null:
		return
	if current_ship.breach_seeded:
		return
	current_ship.breach_seeded = true  # Flag set before the hull fetch: even a zero-breach derelict must be marked seeded.
	var hull = current_ship.get_hull()
	if hull == null:
		return
	for cid in _variant_hazard_compartments("breach"):
		if hull.compartments.has(str(cid)):
			hull.damage_compartment(str(cid), 1.0, true)

## Builds the per-frame context the authoritative fire model ticks against.
func _build_fire_context() -> Dictionary:
	# Read the ACTIVE hull (derelict when away, home otherwise) so the fire tick
	# sees the correct ship's breaches. On the home branch _active_hull() returns
	# hull_integrity_state, so home behavior is byte-identical.
	var active_hull = _active_hull()
	var breached: Array = []
	if active_hull != null:
		for cid in active_hull.compartments:
			if bool((active_hull.compartments[cid] as Dictionary).get("breach_open", false)):
				breached.append(str(cid))
	var damaged: Array = []
	var oxygen_present: bool = true
	var powered: float = 0.0
	var arc_arcing: bool = false
	if not away_from_start:
		# Home path: derive damaged compartments from the home systems manager,
		# oxygen from the life-support expanded model, and powered_ratio from the
		# home power grid. On a derelict: no re-ignition chain (pre-seeded only),
		# breathable pockets exist, and there is no auto-suppression grid.
		if ship_systems_manager != null:
			for cid in FIRE_COMPARTMENT_SYSTEM:
				var sid: String = str(FIRE_COMPARTMENT_SYSTEM[cid])
				if sid.is_empty():
					continue
				var sys = ship_systems_manager.get_system(sid)
				if sys != null and not sys.is_self_functional():
					damaged.append(cid)
		if life_support_expanded_state != null:
			oxygen_present = life_support_expanded_state.oxygen_percent > OXYGEN_MIN_FOR_FIRE
		powered = power_grid_state.get_allocation_ratio("stations") if power_grid_state != null else 0.0
		# arc_arcing is home-only: electrical_arc_state is coordinator/home-owned and is
		# NOT ticked or reset when away, so reading it on the derelict path would leak a
		# frozen phase into the derelict fire's arc-cascade step (re-igniting "engineering"
		# nondeterministically based on travel timing). Stays false when away.
		if electrical_arc_state != null:
			arc_arcing = electrical_arc_state.phase == ElectricalArcState.Phase.ARCING
	return {
		"powered_ratio": powered,
		"ship_oxygen_present": oxygen_present,
		"breached_compartments": breached,
		"damaged_compartments": damaged,
		"arc_arcing": arc_arcing,
	}

## Seeds fires in compartments whose mapped system is already damaged at build
## time, so a damaged ship presents fire immediately rather than only after the
## ignition accumulator fills. Only called on a genuine fresh build, never on the
## save-restore path (restored fires come from the applied summary).
func _seed_fires_from_damage() -> void:
	# M7-B: fire is home/lifeboat-only for now; derelict-side fire is deferred
	# (away-ship parity is a follow-up per the fire-suppression spec).
	if away_from_start:
		return
	if fire_suppression_state == null:
		return
	var ctx := _build_fire_context()
	var breached := {}
	for c in ctx.get("breached_compartments", []):
		breached[str(c)] = true
	if not bool(ctx.get("ship_oxygen_present", true)):
		return
	for cid in ctx.get("damaged_compartments", []):
		if not breached.has(str(cid)):
			fire_suppression_state.ignite(str(cid), 1.0)

## M7-B Task 8: returns the intensity of the fire the player is currently standing
## in (0.0 if none). The player overlaps a fire when within the fire zone's radius
## (~2.0) of its world position.
func _player_fire_intensity() -> float:
	if player == null or _active_fire_state() == null:
		return 0.0
	for cid in fire_zone_nodes:
		var z = fire_zone_nodes[cid]
		if not is_instance_valid(z) or not (z is Node3D):
			continue
		if (z as Node3D).global_position.distance_to(player.global_position) <= 2.0:
			return _active_fire_state().get_intensity(str(cid))
	return 0.0

## M7-B Task 8: applies fire degradation to the ship system housed in each burning
## compartment, scaled by fire intensity. Compartments with no mapped system are skipped.
func _apply_fire_system_damage(delta: float) -> void:
	var afs = _active_fire_state()
	if afs == null or _active_systems_manager() == null:
		return
	for cid in afs.get_burning_compartments():
		var sid: String = str(FIRE_COMPARTMENT_SYSTEM.get(str(cid), ""))
		if sid.is_empty():
			continue
		var intensity: float = afs.get_intensity(str(cid))
		_active_systems_manager().damage_system(sid, FIRE_SYSTEM_DAMAGE_PER_SECOND * intensity * delta)

func _build_fire_zones() -> void:
	_clear_fire_zones()
	var afs = _active_fire_state()
	if afs == null:
		return
	var burning: Array = afs.get_burning_compartments()
	if burning.is_empty():
		return
	# Codex P1: home fire zones parent under lifeboat_ship.scene_root (port-docked),
	# so positions must be LIFEBOAT-LOCAL — matching _build_repair_points/_build_breach_seal_points.
	# Raw _distributed_room_positions() are derelict-frame and land off the lifeboat floor.
	var use_lifeboat: bool = (not away_from_start) and lifeboat_ship != null \
		and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root)
	# Tranche 5 (2026-07-06 audit HIGH): the loader's get_fire_zone_markers() /
	# get_fire_zone_specs() had zero callers while the arc/breach siblings
	# already consume theirs. Away branch only: the boarded derelict's
	# layout-declared fire zones position (and annotate) the first N burning
	# compartments' visuals; distributed positions cover the rest. Home stays
	# lifeboat-local (Codex P1) — home-loader-frame markers would regress it.
	var layout_zones: Array = [] if use_lifeboat else _away_fire_layout_zones()
	var positions: Array = _lifeboat_local_repair_positions() if use_lifeboat else _distributed_room_positions()
	if positions.is_empty() and layout_zones.is_empty():
		return
	var idx: int = 0
	for cid in burning:
		var pos: Vector3
		var layout_spec: Dictionary = {}
		if idx < layout_zones.size():
			pos = layout_zones[idx]["position"]
			layout_spec = layout_zones[idx]["spec"]
		else:
			if positions.is_empty():
				break
			pos = positions[(idx - layout_zones.size()) % positions.size()]
		idx += 1
		var zone := Area3D.new()
		zone.name = "FireZone_%s" % str(cid)
		# Passable: monitoring/monitorable off — these are visual + lookup nodes,
		# NOT collision blockers. The player must be able to walk into a fire.
		zone.monitoring = false
		zone.monitorable = false
		zone.set_meta("fire_compartment_id", str(cid))
		if not layout_spec.is_empty():
			zone.set_meta("fire_zone_layout_id", str(layout_spec.get("zone_id", "")))
			zone.set_meta("fire_zone_layout_kind", str(layout_spec.get("kind", "")))
		zone.position = pos
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.0
		shape.shape = sphere
		zone.add_child(shape)
		var visual := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 1.2, 1.2)
		visual.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.3, 0.05, 0.65)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.1)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		visual.material_override = mat
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		zone.add_child(visual)
		_attach_zone_to_active_ship(zone)
		fire_zone_nodes[str(cid)] = zone

# Layout-declared fire zones of the BOARDED derelict, as [{position, spec}]
# pairs in the derelict's own frame. Mirrors _active_arc_loader's away-branch
# preference; empty at home (lifeboat frame) and for procgen layouts that
# declare no fire_zones. Positions are the loader's precomputed midpoint
# markers; specs carry the layout's zone_id/kind/rooms metadata.
func _away_fire_layout_zones() -> Array:
	if not away_from_start or current_ship == null:
		return []
	var root: Node = current_ship.scene_root
	if root == null or not is_instance_valid(root):
		return []
	if not root.has_method("get_fire_zone_markers") or not root.has_method("get_fire_zone_specs"):
		return []
	var markers: Array = root.call("get_fire_zone_markers")
	var specs: Array = root.call("get_fire_zone_specs")
	var out: Array = []
	for i in range(markers.size()):
		if not (markers[i] is Vector3) or markers[i] == Vector3.INF:
			continue
		var spec: Dictionary = {}
		if i < specs.size() and specs[i] is Dictionary:
			spec = specs[i]
		out.append({"position": markers[i], "spec": spec})
	return out

func _attach_zone_to_active_ship(node: Node) -> void:
	if away_from_start and current_ship != null and current_ship.scene_root != null and is_instance_valid(current_ship.scene_root):
		current_ship.scene_root.add_child(node)
	elif lifeboat_ship != null and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root):
		lifeboat_ship.scene_root.add_child(node)
	else:
		repair_point_root.add_child(node)

# ADR-0042: construct + configure the deterministic hallucination director and its
# scene manager, then attach the manager to the active ship (same helper the fire zones
# use). Called from _on_ship_loaded so it runs on every fresh build and post-reload load.
func _build_hallucination_runtime() -> void:
	if hallucination_manager != null and is_instance_valid(hallucination_manager):
		hallucination_manager.clear_all()
		if hallucination_manager.get_parent() != null:
			hallucination_manager.get_parent().remove_child(hallucination_manager)
		hallucination_manager.queue_free()
	hallucination_director = HallucinationDirectorScript.new()
	hallucination_director.configure({"seed": _ship_seed(current_ship)})
	hallucination_manager = HallucinationManagerScript.new()
	hallucination_manager.name = "HallucinationManager"
	hallucination_manager.configure(hallucination_director)
	_attach_zone_to_active_ship(hallucination_manager)
	# ADR-0042 Task 5: wire the false-HUD/ambient/screen-FX channels. Ambient cues go
	# through the live AudioManager; the screen-FX overlay is a lightweight CanvasLayer
	# whose ColorRect alpha tracks hallucination_intensity.
	hallucination_manager.set_channels(audio_manager, _ensure_hallucination_fx_overlay())

# ADR-0042 Task 5: lazily build the screen-FX overlay. A HallucinationFXOverlay
# (CanvasLayer) holds a full-rect red ColorRect whose alpha tracks the
# `hallucination_intensity` meta the HallucinationManager writes each frame. Kept
# intentionally minimal — richer shader work is a non-goal for v1.
func _ensure_hallucination_fx_overlay() -> CanvasLayer:
	if _hallucination_fx_overlay != null and is_instance_valid(_hallucination_fx_overlay):
		return _hallucination_fx_overlay
	var layer = HallucinationFXOverlayScript.new()
	layer.name = "HallucinationFXOverlay"
	add_child(layer)
	_hallucination_fx_overlay = layer
	return layer

func _clear_fire_zones() -> void:
	for cid in fire_zone_nodes:
		var z = fire_zone_nodes[cid]
		if is_instance_valid(z):
			var parent = z.get_parent()
			if parent != null and is_instance_valid(parent):
				parent.remove_child(z)
			z.queue_free()
	fire_zone_nodes.clear()

func _refresh_fire_zones() -> void:
	# Rebuild only when the burning set differs from the rendered set.
	var burning := {}
	var _afs_rfz = _active_fire_state()
	if _afs_rfz != null:
		for cid in _afs_rfz.get_burning_compartments():
			burning[str(cid)] = true
	var rendered := {}
	for cid in fire_zone_nodes:
		rendered[str(cid)] = true
	# Compare as sorted sets so a different key order does not force a needless rebuild.
	var burning_keys: Array = burning.keys()
	burning_keys.sort()
	var rendered_keys: Array = rendered.keys()
	rendered_keys.sort()
	if burning_keys != rendered_keys:
		_build_fire_zones()
		# M7-B Task 9: keep the manual extinguish nodes tracking the burning set.
		_build_fire_suppression_points()

# --- M7-B Task 9: manual extinguish loop -------------------------------------
# One FireSuppressionPoint per burning compartment, rebuilt from model truth on
# every change. The single recharge port lives on the home/lifeboat ship only.

func _build_fire_suppression_points() -> void:
	_clear_fire_suppression_points()
	var afs = _active_fire_state()
	if afs == null:
		return
	var burning: Array = afs.get_burning_compartments()
	if burning.is_empty():
		return
	# Codex P1: home suppression points parent under lifeboat_ship.scene_root, so positions
	# must be LIFEBOAT-LOCAL — otherwise extinguish range checks land off the lifeboat floor.
	var use_lifeboat: bool = (not away_from_start) and lifeboat_ship != null \
		and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root)
	var positions: Array = _lifeboat_local_repair_positions() if use_lifeboat else _distributed_room_positions()
	if positions.is_empty():
		return
	var idx: int = 0
	for cid in burning:
		var pos: Vector3 = positions[idx % positions.size()]
		idx += 1
		var fp = FireSuppressionPointScript.new()
		fp.configure(str(cid), afs, extinguisher_state, inventory_state, player_progression, pos, 4.0, "fire_extinguisher", 1.8)
		if not fp.fire_extinguished.is_connected(_on_fire_extinguished):
			fp.fire_extinguished.connect(_on_fire_extinguished)
		# Tranche 1 (audit): extinguish_blocked fired on five failure paths but
		# was never connected — a blocked extinguish gave zero player feedback.
		if not fp.extinguish_blocked.is_connected(_on_extinguish_blocked):
			fp.extinguish_blocked.connect(_on_extinguish_blocked)
		_attach_zone_to_active_ship(fp)
		fire_suppression_points.append(fp)

func _clear_fire_suppression_points() -> void:
	for fp in fire_suppression_points:
		if is_instance_valid(fp):
			var parent = fp.get_parent()
			if parent != null and is_instance_valid(parent):
				parent.remove_child(fp)
			fp.queue_free()
	fire_suppression_points.clear()

func _on_fire_extinguished(_compartment_id: String) -> void:
	# _refresh_fire_zones() already rebuilds suppression points when the burning
	# set changes (Task 9), so no second explicit _build_fire_suppression_points().
	_refresh_fire_zones()

func _build_extinguisher_recharge_port() -> void:
	_clear_extinguisher_recharge_port()
	if extinguisher_state == null:
		return
	# Codex P1: the recharge port parents under lifeboat_ship.scene_root, so its position
	# must be LIFEBOAT-LOCAL — matching repair/breach/fire builders. Tranche 1 (audit):
	# the `not away_from_start` term was missing here (its fire-zone sibling has it), so
	# a derelict rebuild positioned the port at LIFEBOAT-local coords while parenting it
	# under the DERELICT root — the port landed off-floor in the wrong frame.
	var use_lifeboat: bool = (not away_from_start) and lifeboat_ship != null \
		and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root)
	var positions: Array = _lifeboat_local_repair_positions() if use_lifeboat else _distributed_room_positions()
	var pos: Vector3 = positions[0] if not positions.is_empty() else Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	var port = ExtinguisherRechargePortScript.new()
	port.configure(extinguisher_state, pos, 1.8)
	_attach_zone_to_active_ship(port)
	extinguisher_recharge_port = port

func _clear_extinguisher_recharge_port() -> void:
	if is_instance_valid(extinguisher_recharge_port):
		var parent = extinguisher_recharge_port.get_parent()
		if parent != null and is_instance_valid(parent):
			parent.remove_child(extinguisher_recharge_port)
		extinguisher_recharge_port.queue_free()
	extinguisher_recharge_port = null

# --- validation seams ---
func get_extinguisher_state():
	return extinguisher_state

func get_fire_suppression_points_for_validation() -> Array:
	return fire_suppression_points.duplicate()

func get_extinguisher_recharge_port_for_validation():
	return extinguisher_recharge_port

func teleport_player_to_fire_suppression_point_for_validation(point) -> bool:
	if player == null or point == null or not is_instance_valid(point):
		return false
	if player is Node3D and point is Node3D:
		(player as Node3D).global_position = (point as Node3D).global_position
		return true
	return false

func get_burning_compartments_for_validation() -> Array:
	return fire_suppression_state.get_burning_compartments() if fire_suppression_state != null else []

func get_fire_zone_nodes_for_validation() -> Array:
	return fire_zone_nodes.values()

func force_ignite_compartment_for_validation(compartment_id: String, intensity: float = 1.0) -> bool:
	if fire_suppression_state == null:
		return false
	var ok: bool = fire_suppression_state.ignite(compartment_id, intensity)
	_refresh_fire_zones()
	return ok

## Ignites a compartment in the ACTIVE fire state (derelict's when away, home model
## otherwise). Use this in away-branch smokes where force_ignite_compartment_for_validation
## acts on the home model and cannot reach the derelict's per-ship FireSuppressionState.
func force_ignite_active_compartment_for_validation(cid: String, intensity: float = 1.0) -> bool:
	var afs = _active_fire_state()
	if afs == null:
		return false
	var ok: bool = afs.ignite(cid, intensity)
	_refresh_fire_zones()
	return ok

## Validation seam: the active fire state (derelict's when away, home model otherwise).
## Use when a smoke needs direct access to the fire model for inspection or setup.
func get_active_fire_state_for_validation():
	return _active_fire_state()

## ADR-0038: builds one player-reachable CraftingStation per curated kind on the home ship.
## Stations live on the home ship (not derelicts) and are parented under home_ship.scene_root
## so they inherit its transform and are freed with it. Idempotent: re-callable on reload.
func _build_crafting_stations() -> void:
	_clear_crafting_stations()
	if away_from_start or not is_instance_valid(home_ship) or not is_instance_valid(home_ship.scene_root):
		return
	if crafting_state == null:
		return
	var positions: Array = _home_local_station_positions()
	if positions.is_empty():
		# Fallback: spread the stations around the scene_root origin so they always exist
		# (interactable via range gate / the validation teleport seam) even when the home
		# structure can't be resolved into floor cells.
		var y: float = PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR
		for i in range(CRAFTING_STATION_KINDS.size()):
			positions.append(Vector3(float(i) * 2.0, y, 0.0))
	var idx: int = 0
	for kind in CRAFTING_STATION_KINDS:
		var pos: Vector3 = positions[idx % positions.size()]
		idx += 1
		var st = CraftingStationScript.new()
		st.configure(kind, crafting_state, material_state, inventory_state,
			deconstruction_resolver, player_progression, pos, 1.8)
		if not st.craft_started.is_connected(_on_craft_started):
			st.craft_started.connect(_on_craft_started)
		if not st.salvage_completed.is_connected(_on_salvage_completed):
			st.salvage_completed.connect(_on_salvage_completed)
		if not st.craft_blocked.is_connected(_on_craft_blocked):
			st.craft_blocked.connect(_on_craft_blocked)
		home_ship.scene_root.add_child(st)
		crafting_stations.append(st)

func _clear_crafting_stations() -> void:
	for st in crafting_stations:
		if is_instance_valid(st):
			var p = st.get_parent()
			if is_instance_valid(p):
				p.remove_child(st)
			st.queue_free()
	crafting_stations.clear()

## Domain 3: builds one PlayerReachable ProductionStation per persistent food-production
## model (hydroponics + water_recycler) on the home ship. Mirrors _build_crafting_stations.
func _build_production_stations() -> void:
	_clear_production_stations()
	if away_from_start or not is_instance_valid(home_ship) or not is_instance_valid(home_ship.scene_root):
		return
	if hydroponics_state == null or water_recycler_state == null or inventory_state == null:
		return
	var crops_cfg: Dictionary = _load_json_dict(HYDROPONICS_CROPS_CONFIG_PATH)
	var positions: Array = _home_local_station_positions()
	var y: float = PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR
	var specs: Array = [
		{"kind": "hydroponics", "model": hydroponics_state, "config": crops_cfg},
		{"kind": "water_recycler", "model": water_recycler_state, "config": {}},
	]
	var power_cb: Callable = func() -> float:
		# Boolean power gate as large float: sustenance band either powers the station
		# (>= half allocation) or it does not. Mirrors how crafting treats station power.
		var ratio: float = power_grid_state.get_allocation_ratio("sustenance") if power_grid_state != null else 0.0
		return 999.0 if ratio >= 0.5 else 0.0
	var skill_cb: Callable = func() -> int:
		return int(player_progression.get_skill_level("fabrication")) if player_progression != null and player_progression.has_method("get_skill_level") else 0
	var idx: int = 0
	for spec in specs:
		var pos: Vector3 = positions[idx % positions.size()] if not positions.is_empty() else Vector3(float(idx) * 2.0, y, 0.0)
		idx += 1
		var st = ProductionStationScript.new()
		st.configure(str(spec["kind"]), spec["model"], inventory_state, power_cb, skill_cb, spec["config"] as Dictionary, pos, 1.8)
		if not st.production_started.is_connected(_on_production_started):
			st.production_started.connect(_on_production_started)
		if not st.production_harvested.is_connected(_on_production_harvested):
			st.production_harvested.connect(_on_production_harvested)
		if not st.production_blocked.is_connected(_on_production_blocked):
			st.production_blocked.connect(_on_production_blocked)
		home_ship.scene_root.add_child(st)
		production_stations.append(st)

func _clear_production_stations() -> void:
	for st in production_stations:
		if is_instance_valid(st):
			var p = st.get_parent()
			if is_instance_valid(p):
				p.remove_child(st)
			st.queue_free()
	production_stations.clear()

## HOME-LOCAL station positions, derived from the home ship's actual room nodes (the same
## "ShipStructure"-child approach interior_aabb()/_lifeboat_local_repair_positions() use), so
## a station parented under home_ship.scene_root lands ON a real floor cell. Returns [] when
## the structure can't be resolved (caller then falls back to spread anchors).
func _home_local_station_positions() -> Array:
	var out: Array = []
	if home_ship == null or not is_instance_valid(home_ship.scene_root):
		return out
	var y: float = PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR
	var sr: Node3D = home_ship.scene_root
	var structure: Node = sr.get_node_or_null("ShipStructure")
	if structure == null:
		for c in sr.get_children():
			if c.get_child_count() > 0:
				structure = c
				break
	if structure == null:
		return out
	for room_node in structure.get_children():
		if room_node is Node3D:
			out.append((room_node as Node3D).position + Vector3(0.0, y, 0.0))
	return out

## The systems manager of the ship the player is currently aboard: the derelict's when away,
## the lifeboat's when home. (Repair points act on the ship under the player's feet; the
## travel gate separately reads the PILOTED ship's systems — see _current_systems_ops.)
func _active_systems_manager():
	if away_from_start and current_ship != null and current_ship.systems_manager != null:
		return current_ship.systems_manager
	return ship_systems_manager

## The fire model of the ship the player is currently aboard: the derelict's per-ship
## FireSuppressionState when away, the coordinator's home model otherwise. Mirrors
## _active_systems_manager(). The derelict instance is configured from tuning by
## _seed_derelict_fire() / the restore path before use.
func _active_fire_state():
	if away_from_start and current_ship != null:
		return current_ship.get_fire()
	return fire_suppression_state

## The hull/web of the ship the player is currently aboard: the derelict's per-ship
## model when away, the hub's coordinator singleton otherwise. Mirrors _active_fire_state().
func _active_hull():
	if away_from_start and current_ship != null and current_ship != home_ship:
		return current_ship.get_hull()
	return hull_integrity_state

func _active_web():
	if away_from_start and current_ship != null and current_ship != home_ship:
		return current_ship.get_web()
	return hull_web_state

## Resolve a SPECIFIC ship's hull/web (hub -> singleton, any other ship -> its own model).
## Used by the unified per-ship tick (_advance_ship) in Phase 3.
func _hull_for(ship):
	if ship == null or ship == home_ship:
		return hull_integrity_state
	return ship.get_hull()

func _web_for(ship):
	if ship == null or ship == home_ship:
		return hull_web_state
	return ship.get_web()

## Floor-cell world positions distributed across the active ship's rooms, for repair-point
## placement. Reuses the active loader's room/cell resolution where available.
func _distributed_room_positions() -> Array:
	var out: Array = []
	var active_loader = current_ship.scene_root if (away_from_start and current_ship != null) else loader
	if is_instance_valid(active_loader) and active_loader.has_method("get_objective_specs_copy"):
		for spec in active_loader.get_objective_specs_copy():
			if typeof(spec) == TYPE_DICTIONARY and typeof(spec.get("position", null)) == TYPE_VECTOR3:
				out.append(spec["position"])
	# Fallback: derive from loot container specs if no objective positions exist.
	if out.is_empty() and is_instance_valid(active_loader) and active_loader.has_method("get_loot_container_specs_copy"):
		for spec in active_loader.get_loot_container_specs_copy():
			if typeof(spec) == TYPE_DICTIONARY and typeof(spec.get("position", null)) == TYPE_VECTOR3:
				out.append(spec["position"])
	return out

func _on_repair_completed(system_id: String, subcomponent_id: String) -> void:
	_refresh_inventory_hud()
	# Repairs consume parts from the player inventory (RepairPoint is configured
	# with inventory_state), so carry weight drops here. Recompute encumbrance so
	# the cached weight_reduction / bonus_capacity (and the Heavy-Load penalty)
	# reflect the post-consume load instead of going stale until the next
	# equip/transfer. Restores the ADR-0028 invariant: every inventory-content
	# change refreshes the reduction cache.
	_recompute_player_encumbrance()
	# REQ-RL-003: first_repair achievement (repair_consumed / any) — channel
	# completion is the live "parts were spent" moment for RepairPoint.
	_try_unlock_achievement("repair_consumed", "%s.%s" % [system_id, subcomponent_id])
	var mgr = _active_systems_manager()
	var operational: bool = mgr != null and mgr.is_operational(system_id)
	print("REPAIR COMPLETED system=%s sub=%s operational=%s" % [
		system_id, subcomponent_id, str(operational).to_lower()])

func _on_repair_blocked(_system_id: String, _subcomponent_id: String, reason: String) -> void:
	if vitals_model != null:
		vitals_model.notify_repair_blocked(reason)

## ADR-0038: a station began a timed craft (ingredients already consumed by begin_craft).
## The craft advances in _recompute_expanded_ship_systems and deposits via _on_craft_completed.
func _on_craft_started(station_kind: String, recipe_id: String) -> void:
	_refresh_inventory_hud()
	_recompute_player_encumbrance()
	print("CRAFT STARTED station=%s recipe=%s" % [station_kind, recipe_id])

## ADR-0038: a global craft (station or field) finished. Collects the product and deposits
## it into the player inventory, then refreshes HUD + encumbrance. Idempotent: a no-op when
## finish_craft() returns empty.
## REQ-FC (Codex PR #43): register a newly acquired food/drink item with the spoilage
## tracker so it ages from acquisition. Crafted/looted food previously only hit
## inventory_state and was never tracked, so the eat-time spoilage multiplier always fell
## back to FRESH in real play. Idempotent: skips items already tracked or not food/drink.
func _register_food_for_spoilage(item_id: String) -> void:
	if spoilage_state == null or item_id.is_empty() or spoilage_state.has_food(item_id):
		return
	var defs: Dictionary = ItemDefsScript.load_definitions()
	var definition: Variant = defs.get(item_id, null)
	if not (definition is Dictionary):
		return
	var category: String = str((definition as Dictionary).get("category", ""))
	if category == "food" or category == "drink":
		spoilage_state.add_food(item_id, definition as Dictionary)

func _on_craft_completed() -> void:
	if crafting_state == null:
		return
	var result: Dictionary = crafting_state.finish_craft()
	var item_id: String = str(result.get("item_id", ""))
	var qty: int = int(result.get("quantity", 0))
	if item_id.is_empty() or qty <= 0:
		return
	if inventory_state != null:
		# Stations gate on can_accept() before starting, so a full stack here is only the rare
		# during-craft fill; surface (not silently drop) any overflow rather than emitting a
		# WARNING (the regression bundle fails on unexpected WARNING lines).
		var added: int = inventory_state.add_item(item_id, qty)
		if added < qty:
			print("CRAFT OVERFLOW item=%s lost=%d reason=stack_full" % [item_id, qty - added])
		_register_food_for_spoilage(item_id)
	_refresh_inventory_hud()
	_recompute_player_encumbrance()
	print("CRAFT COMPLETED item=%s qty=%d quality=%s" % [
		item_id, qty, str(result.get("quality_tier", "standard"))])

## ADR-0038: an emergency field craft finished. Same deposit path as station crafts.
func _on_field_craft_completed() -> void:
	if field_crafting_state == null:
		return
	var result: Dictionary = field_crafting_state.finish_craft()
	var item_id: String = str(result.get("item_id", ""))
	var qty: int = int(result.get("quantity", 0))
	if item_id.is_empty() or qty <= 0:
		return
	if inventory_state != null:
		var added: int = inventory_state.add_item(item_id, qty)
		if added < qty:
			print("FIELD CRAFT OVERFLOW item=%s lost=%d reason=stack_full" % [item_id, qty - added])
		_register_food_for_spoilage(item_id)
	_refresh_inventory_hud()
	_recompute_player_encumbrance()
	print("FIELD CRAFT COMPLETED item=%s qty=%d quality=%s" % [
		item_id, qty, str(result.get("quality_tier", "standard"))])
	# Domain 6 (WI-2): field fabrication trains the tree-gated `fabrication` skill
	# through the bus. When the Fabrication node is locked the skill_gate drops the
	# event (no XP); once unlocked, field-crafting advances fabrication — which in
	# turn improves field-craft quality (get_skill_level("fabrication") at :3415).
	emit_training_event("fabricate_part", item_id)

## ADR-0038: a salvage station deconstructed an item (the station already deposited the
## yield into inventory); just refresh HUD + encumbrance and report.
func _on_salvage_completed(item_id: String, yields: Dictionary) -> void:
	_refresh_inventory_hud()
	_recompute_player_encumbrance()
	print("SALVAGE COMPLETED item=%s qty=%d" % [item_id, int(yields.get("quantity", 0))])

func _on_craft_blocked(station_kind: String, reason: String) -> void:
	print("CRAFT BLOCKED station=%s reason=%s" % [station_kind, reason])

## Domain 3: signal handlers for persistent production stations (hydroponics/water_recycler).
func _on_production_started(station_kind: String, input_id: String) -> void:
	_refresh_inventory_hud()
	_recompute_player_encumbrance()
	print("PRODUCTION STARTED station=%s input=%s" % [station_kind, input_id])

func _on_production_harvested(station_kind: String, item_id: String, qty: int) -> void:
	# qty is the count actually deposited; a 0 means nothing landed (e.g. a full stack), so
	# do NOT register existing inventory of the same id for spoilage. With the output-full
	# guard in ProductionStation this should not fire at 0, but guard defensively.
	if qty <= 0:
		return
	# The station already deposited into inventory; register produce for spoilage
	# (mirrors _on_craft_completed) and refresh HUD/encumbrance.
	_register_food_for_spoilage(item_id)
	_refresh_inventory_hud()
	_recompute_player_encumbrance()
	print("PRODUCTION HARVESTED station=%s item=%s qty=%d" % [station_kind, item_id, qty])

func _on_production_blocked(station_kind: String, reason: String) -> void:
	print("PRODUCTION BLOCKED station=%s reason=%s" % [station_kind, reason])

## ADR-0038: handles the player's field_craft (KEY_C) press — begins the first craftable
## portable recipe (station_kind == "field_crafting") via the coordinator-owned model.
func _on_player_field_craft_requested(_player_body) -> void:
	if field_crafting_state == null or inventory_state == null:
		return
	if field_crafting_state.is_crafting():
		print("FIELD CRAFT BLOCKED reason=busy")
		return
	var recipes: Array = field_crafting_state.get_field_recipes()
	recipes.sort_custom(func(a, b): return str(a.get("recipe_id", "")) < str(b.get("recipe_id", "")))
	var skill: int = 0
	if player_progression != null and player_progression.has_method("get_skill_level"):
		skill = int(player_progression.get_skill_level("fabrication"))
	var blocked_by_full: bool = false
	for recipe in recipes:
		var rid: String = str(recipe.get("recipe_id", ""))
		if rid.is_empty():
			continue
		if not field_crafting_state.can_craft(rid, inventory_state):
			continue
		# Don't consume ingredients for an output the inventory can't store (begin_craft
		# consumes immediately; add_item drops over-stack overflow on completion).
		var produces: Variant = recipe.get("produces", {})
		if produces is Dictionary and not inventory_state.can_accept(
				str((produces as Dictionary).get("item_id", "")), int((produces as Dictionary).get("quantity", 0))):
			blocked_by_full = true
			continue
		if field_crafting_state.begin_craft(rid, inventory_state, material_state, skill):
			_refresh_inventory_hud()
			_recompute_player_encumbrance()
			print("FIELD CRAFT STARTED recipe=%s" % rid)
			return
	print("FIELD CRAFT BLOCKED reason=%s" % ("output_full" if blocked_by_full else "no_craftable_recipe"))

## Validation seam: start a repair-point channel via the real path, by subcomponent.
func repair_subcomponent_for_validation(system_id: String, subcomponent_id: String) -> bool:
	if not is_instance_valid(player):
		return false
	for rp in repair_points:
		if is_instance_valid(rp) and rp.system_id == system_id and rp.subcomponent_id == subcomponent_id and not rp.repaired:
			# Put the player at the repair point so the real range gate (not a
			# candidate_player bypass) admits the channel — mirrors the loot smoke seam.
			if player.has_method("teleport_to"):
				player.teleport_to(rp.global_position)
			return rp.try_start(player)
	return false

## Validation seam: pump all channeling repair points by delta (deterministic timed advance).
func advance_repair_channels_for_validation(delta: float) -> void:
	for rp in repair_points:
		if is_instance_valid(rp) and rp.channeling:
			rp.advance_channel(delta)

## ADR-0038 validation seam: start a station craft/salvage via the REAL interaction path,
## by station kind. Teleports the player onto the station so the range gate (not a
## candidate bypass) admits the interact — mirrors repair_subcomponent_for_validation.
func craft_at_station_for_validation(station_kind: String) -> bool:
	if not is_instance_valid(player):
		return false
	for st in crafting_stations:
		if is_instance_valid(st) and st.station_kind == station_kind:
			if player.has_method("teleport_to"):
				player.teleport_to(st.global_position)
			# Force the station model powered so the deterministic advance below isn't
			# gated by the live power grid (which may allocate 0 to "stations" on a
			# damaged boot). Mirrors how the real loop drives set_power each frame.
			if crafting_state != null:
				crafting_state.get_or_create_station(station_kind).set_power(true)
			st.set_powered(true)
			return st.try_interact(player)
	return false

## Domain 3 validation seam (mirrors craft_at_station_for_validation): teleport the player
## onto a production station and interact. The station infers start-vs-harvest from its own
## model state, so a first call starts production and a later call harvests. `_harvest` is an
## intentionally-unused call-site readability label (false=start, true=collect); the
## underscore marks it as accepted-but-not-branched-on.
func produce_at_station_for_validation(station_kind: String, _harvest: bool) -> bool:
	if not is_instance_valid(player):
		return false
	for st in production_stations:
		if is_instance_valid(st) and st.station_kind == station_kind:
			if player.has_method("teleport_to"):
				player.teleport_to(st.global_position)
			st.set_validation_player_in_range(player)
			return st.try_interact(player)
	return false

## Domain 3 validation seam: deterministically advance the production models (hydroponics +
## water_recycler) by delta, bypassing the _process guard that blocks after slice_complete.
## Mirrors advance_crafting_for_validation. Call once per simulated second in smoke loops
## instead of _process(1.0) to avoid the slice_complete early-return after player death.
func advance_production_for_validation(delta: float) -> void:
	if hydroponics_state != null and hydroponics_state.state == HydroponicsStateScript.State.PLANTED:
		hydroponics_state.tick(delta)
	if water_recycler_state != null and water_recycler_state.state == WaterRecyclerStateScript.State.RECYCLING:
		water_recycler_state.tick(delta)

## ADR-0038 validation seam: deterministically advance the active station craft (and field
## craft) by delta, depositing outputs through the real completion handlers when they finish.
## Keeps the active station powered so the advance never stalls on the live power grid.
func advance_crafting_for_validation(delta: float) -> void:
	if crafting_state != null:
		var active_kind: String = crafting_state.get_active_station_kind()
		if not active_kind.is_empty():
			crafting_state.get_or_create_station(active_kind).set_power(true)
		if crafting_state.tick(delta):
			_on_craft_completed()
	if field_crafting_state != null and field_crafting_state.tick(delta):
		_on_field_craft_completed()

## LIFEBOAT-LOCAL repair-point positions, derived from the ACTUAL built lifeboat room nodes.
## LifeBoatBuilder.build() lays rooms via StructuralPlacer's BFS grid (CELL_SIZE+ROOM_GAP
## spacing + airlock separation) — NOT the fixed ROOM_CELL_X cells — so hardcoding positions
## places repair points off the real floor. We read each room node's local position from the
## "ShipStructure" container (which sits at the scene_root origin, so its children's positions
## are lifeboat-local). A repair point parented under lifeboat_ship.scene_root at one of these
## therefore lands ON an actual lifeboat room. Returns [] if the structure can't be found
## (caller then falls through to repair_point_root, never to an off-floor position).
func _lifeboat_local_repair_positions() -> Array:
	var out: Array = []
	if lifeboat_ship == null or not is_instance_valid(lifeboat_ship.scene_root):
		return out
	var y: float = PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR
	var sr: Node3D = lifeboat_ship.scene_root
	var structure: Node = sr.get_node_or_null("ShipStructure")
	if structure == null:
		# Fallback: the first child that contains room nodes.
		for c in sr.get_children():
			if c.get_child_count() > 0:
				structure = c
				break
	if structure == null:
		return out
	for room_node in structure.get_children():
		if room_node is Node3D:
			out.append((room_node as Node3D).position + Vector3(0.0, y, 0.0))
	return out

## Curates the lifeboat's propulsion so the opening blocker is a single low-skill repair:
## nav_linkage broken (circuit_board, skill 2, no tool), the other propulsion subs healthy.
## Propulsion is offline at boot (and stays so until repaired), making "repair the lifeboat to
## travel" the opening. Other systems keep their deterministic condition damage (the existing
## objective loop repairs power/navigation; nothing else depends on propulsion's start health).
func _apply_lifeboat_opening_damage() -> void:
	if ship_systems_manager == null:
		return
	var prop = ship_systems_manager.get_system("propulsion")
	if prop == null:
		return
	for sub in prop.subcomponents:
		sub.health = 1.0
	var blocker = prop.get_subcomponent("nav_linkage")
	if blocker != null:
		blocker.health = ShipSystemsManagerScript.DAMAGED_HEALTH

## Records a searched scattered container on the per-ship slice + refreshes the HUD.
## `source` is the emitting LootContainer node (bound at connect time); null for
## callers without a scene position (objective loot, legacy validation seams).
func _on_loot_container_searched(container_id: String, granted: Array, source: Node3D = null) -> void:
	if current_ship != null and not current_ship.looted_container_ids.has(container_id):
		current_ship.looted_container_ids.append(container_id)
	# Combat corpses leave pending_corpse_loot once searched so they do not
	# re-spawn on revisit (looted_container_ids is the durable "already searched" set).
	if current_ship != null and container_id.begins_with("corpse_"):
		_clear_pending_corpse_loot(current_ship, container_id)
	# Tranche 6 (corrected unlock-wiring audit item): searching a container is
	# the authored scavenge_container training action (+50 scavenging XP,
	# data/player/training_actions.json) and the trigger for the
	# codex_scavenging_intro + salvage_captain unlocks — it was never emitted
	# in production, so all three were dead. Event-driven (fires from the
	# interact path on BOTH home and away), not a per-frame system.
	emit_training_event("scavenge_container", container_id)
	# REQ-RL-003: first_loot achievement (loot_searched / any).
	_try_unlock_achievement("loot_searched", container_id)
	_postprocess_loot_grants(granted, container_id, source)
	_refresh_inventory_hud()
	# Auto-equip granted containers into empty slots (Phase-7 deferral: no equip UI yet).
	for entry in granted:
		var gid: String = str(entry.get("item_id", ""))
		if gid == "":
			continue
		_register_food_for_spoilage(gid)
		if equipment_state != null and equipment_state.can_equip(gid):
			_equip_from_inventory(gid, true)
	_recompute_player_encumbrance()
	print("LOOT CONTAINER SEARCHED marker=%s container=%s granted=%d" % [
		String(current_ship.marker_id) if current_ship != null else "", container_id, granted.size()])

## Domain 5: a sealed hatch was bypassed. Consumes the matching utility flag, removes
## any associated status effect, and records the bypass for per-ship persistence.
func _on_hatch_bypassed(hatch_id: String, lock_kind: String) -> void:
	var flag: String = "lockpick" if lock_kind == SealedHatchScript.MECHANICAL else "hack_chip"
	var depleted: bool = false
	if utility_item_state != null:
		depleted = utility_item_state.consume_flag(flag)
	# Only clear the ready-status when all charges of this flag are spent; stacked
	# lockpick/hack_chip sets should retain the status until the last charge fires.
	if depleted and status_effects_state != null and status_effects_state.has_method("remove_effect"):
		status_effects_state.remove_effect("utility_%s_ready" % flag, 9999)
	# Track for persistence so a revisited derelict remembers the open hatch.
	if current_ship != null and not current_ship.bypassed_hatch_ids.has(hatch_id):
		current_ship.bypassed_hatch_ids.append(hatch_id)
	_refresh_inventory_hud()

## Domain 5: attempts to bypass the nearest unblocked sealed hatch using the player's
## active utility flags. Returns true iff a hatch was opened.
func _try_bypass_nearest_hatch() -> bool:
	if not is_instance_valid(player):
		return false
	for h in sealed_hatches:
		if not is_instance_valid(h) or h.bypassed:
			continue
		var res: Dictionary = h.try_bypass(player, utility_item_state.active_flags if utility_item_state != null else {})
		if bool(res.get("ok", false)):
			return true
	return false

## Domain 2 (BP3): a threat died — grant XP through the progression bus and spawn a
## lootable corpse container at its position (reusing the closed loot/interact path).
## Runs on BOTH _process branches (the signal fires from tick_threats, called on the
## away branch too), so derelict kills reward identically.
##
## Unsearched corpses are also recorded on the ship's pending_corpse_loot so a leave
## + revisit (or save/load) re-spawns the drop — previously they lived only in the
## transient loot_containers array and vanished with scene_root.
func _on_threat_killed(record: Dictionary) -> void:
	# XP (data-driven interim skill via training_actions.json).
	emit_training_event("threat_killed", str(record.get("archetype_id", "")))
	# Lootable corpse container.
	if inventory_state == null:
		return
	var pos: Vector3 = record.get("position", Vector3.ZERO)
	var cid: String = "corpse_%s" % str(record.get("instance_id", ""))
	# Decide the parent FIRST so the position can be framed correctly. Derelict corpses
	# parent under the derelict's scene_root (freed with the derelict on departure); home
	# corpses parent under loot_container_root at origin.
	var parent_node: Node = loot_container_root
	var local_pos: Vector3 = pos
	if away_from_start and current_ship != null and is_instance_valid(current_ship.scene_root):
		parent_node = current_ship.scene_root
		# The kill record position is GLOBAL world-space (threat world_position bakes in the
		# derelict's global anchor, _combat_anchor_for_current_ship = scene_root.global_position).
		# LootContainer stores the configured position as the node's LOCAL position, so under the
		# offset scene_root (DERELICT_DOCK_OFFSET) we must convert global -> local; otherwise the
		# corpse double-offsets ~100u away and the range interaction can never reach it.
		local_pos = (current_ship.scene_root as Node3D).to_local(pos)
	if parent_node == null or not is_instance_valid(parent_node):
		return
	var loot_table: String = str(record.get("loot_table", "combat_drop_common"))
	var seed_source: String = "kill:%s" % cid
	# Persist for revisit/save before spawning the live node.
	if current_ship != null:
		_register_pending_corpse_loot(current_ship, cid, loot_table, seed_source, local_pos)
	_spawn_corpse_loot_container(cid, loot_table, seed_source, local_pos, parent_node)

## Records an unsearched combat corpse on the ship so leave/revisit re-spawns it.
func _register_pending_corpse_loot(ship, container_id: String, loot_table: String, seed_source: String, local_pos: Vector3) -> void:
	if ship == null or container_id.is_empty():
		return
	for entry in ship.pending_corpse_loot:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("container_id", "")) == container_id:
			return
	ship.pending_corpse_loot.append({
		"container_id": container_id,
		"loot_table": loot_table,
		"seed_source": seed_source,
		"position": [local_pos.x, local_pos.y, local_pos.z],
	})

## Drops a pending corpse record once searched (looted_container_ids is the authority
## for "already searched"; pending list is only for unsearched re-spawns).
func _clear_pending_corpse_loot(ship, container_id: String) -> void:
	if ship == null or container_id.is_empty():
		return
	var kept: Array = []
	for entry in ship.pending_corpse_loot:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("container_id", "")) == container_id:
			continue
		kept.append(entry)
	ship.pending_corpse_loot = kept

func _spawn_corpse_loot_container(container_id: String, loot_table: String, seed_source: String, local_pos: Vector3, parent_node: Node) -> void:
	if parent_node == null or not is_instance_valid(parent_node) or inventory_state == null:
		return
	# Skip if already live in the current array.
	for existing in loot_containers:
		if is_instance_valid(existing) and String(existing.container_id) == container_id:
			return
	var lc = LootContainerScript.new()
	lc.configure(container_id, loot_table, seed_source, inventory_state, _loot_tables, local_pos, 1.8, {})
	var searched_cb: Callable = _on_loot_container_searched.bind(lc)
	if not lc.container_searched.is_connected(searched_cb):
		lc.container_searched.connect(searched_cb)
	parent_node.add_child(lc)
	loot_containers.append(lc)

## Re-spawns unsearched combat corpses from the ship's pending list (after layout loot).
func _spawn_pending_corpse_loot_containers() -> void:
	if current_ship == null or inventory_state == null:
		return
	var looted: Array = current_ship.looted_container_ids
	var parent_node: Node = loot_container_root
	if away_from_start and is_instance_valid(current_ship.scene_root):
		parent_node = current_ship.scene_root
	if parent_node == null or not is_instance_valid(parent_node):
		return
	for entry_variant in current_ship.pending_corpse_loot:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var cid: String = str(entry.get("container_id", ""))
		if cid.is_empty() or looted.has(cid):
			continue
		var pos_arr: Variant = entry.get("position", null)
		var local_pos := Vector3.ZERO
		if pos_arr is Array and (pos_arr as Array).size() == 3:
			local_pos = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		_spawn_corpse_loot_container(
			cid,
			str(entry.get("loot_table", "combat_drop_common")),
			str(entry.get("seed_source", "kill:%s" % cid)),
			local_pos,
			parent_node
		)

## Validation seam: search a loot container by id through the real interaction path.
func search_loot_container_for_validation(container_id: String) -> bool:
	for lc in loot_containers:
		if is_instance_valid(lc) and String(lc.container_id) == container_id and not lc.searched:
			lc.set_validation_player_in_range(player)
			return lc.try_interact(player)
	return false

## Routes a derelict interactable completion to the active ship's controller.
func _on_derelict_interactable_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String, step_id: String) -> void:
	if current_ship == null:
		return
	var controller = current_ship.get_objective_controller()
	controller.complete(sequence)
	# Reflect the completion (and run-complete on clear) in the HUD.
	_refresh_derelict_tracker()
	# Sub-project #3: grant salvage-point loot on objective completion (once only —
	# the interactable cannot re-fire after completed = true).
	if objective_type == "salvage" and _salvage_loot_tables.has(objective_id):
		var seed_source: String = "%s:%s" % [String(current_ship.marker_id), objective_id]
		var rolled: Array = LootDistributionScript.roll(_salvage_loot_tables[objective_id], seed_source, _loot_tables, {
			"biome_id": _resolve_current_loot_biome_id(),
			"loot_quality_modifier": _resolve_current_loot_quality_modifier(),
			"depth": _resolve_current_loot_depth(),
			"condition": _resolve_current_loot_condition(),
			"container_kind": "salvage_objective",
			"item_definitions": ItemDefsScript.load_definitions(),
			"unique_state": unique_item_state,
		})
		var granted: Array = []
		for entry in rolled:
			var added: int = inventory_state.add_item(str(entry.get("item_id", "")), int(entry.get("quantity", 0)))
			if added > 0:
				var granted_entry: Dictionary = (entry as Dictionary).duplicate(true)
				granted_entry["quantity"] = added
				granted.append(granted_entry)
		_postprocess_loot_grants(granted, objective_id)
		_refresh_inventory_hud()
		_recompute_player_encumbrance()   # salvage rewards change carry weight -> refresh Heavy Load
	print("DERELICT OBJECTIVE COMPLETE marker=%s sequence=%d type=%s cleared=%s" % [
		String(current_ship.marker_id), sequence, objective_type, str(controller.is_cleared()).to_lower()])
	if is_instance_valid(menu_coordinator):
		menu_coordinator.trigger_tutorial("objective_completed", objective_type)

## Validation seam: complete a derelict objective by sequence through the real
## interaction path (bypassing proximity via set_validation_player_in_range).
func complete_derelict_objective_for_validation(sequence: int) -> bool:
	for it in derelict_interactables:
		if is_instance_valid(it) and int(it.sequence) == sequence and not it.completed:
			it.set_validation_player_in_range(player)
			return it.try_interact(player)
	return false

## Validates + executes a jump to a marker, swapping current_ship and re-homing
## the player on success. Travel is gated by the CURRENT ship's propulsion.
func travel_to(marker) -> Dictionary:
	if current_ship == null or synaptic_sea_world == null or travel_controller == null or ship_generator == null:
		return {"success": false, "reason": "not_ready", "ship": null}
	# Reject travel to the marker of the ship we are currently PILOTING. Selecting it would
	# regenerate that ship's geometry: because current_ship == piloted_ship here,
	# _attach_derelict_active would overwrite piloted_ship.scene_root (leaking the old root)
	# and then dock the ship to itself — a failed/softlocked state. (Codex P2) This is
	# narrowly scoped to current_ship == piloted_ship; the lifeboat-piloted "revisit in place"
	# case (current_ship is the host derelict, piloted is the separate lifeboat) still works:
	# the host is freed and regenerated and the lifeboat re-docks, as in 5b.
	if piloted_ship != null and current_ship == piloted_ship and String(marker.marker_id) == String(current_ship.marker_id):
		return {"success": false, "reason": "already_here", "ship": null}
	# Phase 5b Task 5 precondition: the player must be aboard the piloted ship to
	# travel — the ride physically takes them with it. Occupancy is authoritative.
	recompute_occupancy()
	if piloted_ship != null and current_occupancy != piloted_ship:
		return {"success": false, "reason": "not_aboard_ship", "ship": null}
	# Capture the world state attempt_travel mutates on success (scanner position +
	# generated mark) so the dock-compat check below can roll it back on rejection.
	var prev_player_pos: Vector3 = synaptic_sea_world.player_position
	var was_generated: bool = synaptic_sea_world.is_generated(String(marker.marker_id))
	var ops_t: Dictionary = {"propulsion": bool(_current_systems_ops().get("propulsion", false))}
	# Light up the procgen expansion lane for this derelict: resolve a deterministic
	# biome + difficulty from the target marker and hand them to the generator so
	# ShipLayoutGenerator runs EncounterInjector + room-variant selection and stamps
	# biome_id/difficulty_id on the layout (consumed by threat spawning + scanner/HUD).
	var run_ctx: Dictionary = _resolve_derelict_run_context(marker)
	ship_generator.configure_run_context(str(run_ctx.get("biome", "")), str(run_ctx.get("difficulty", "")))
	var result: Dictionary = travel_controller.attempt_travel(
		marker, ops_t, synaptic_sea_world, ship_generator, scanner_state.range_radius)
	if not bool(result.get("success", false)):
		return result
	var new_root: Node3D = result.get("ship", null)
	if new_root == null:
		return {"success": false, "reason": "generation_failed", "ship": null}

	# Spec edge case: abort with dock_incompatible BEFORE freeing the current host,
	# so a port-mismatch never leaves a half-undocked state. ports_compatible needs only
	# type/size (layout-derived), so the target's LOCAL port suffices here (no placement yet).
	if piloted_ship != null and new_root.has_method("get_layout_copy"):
		var target_local: Dictionary = DockPortsScript.for_derelict(new_root.get_layout_copy(), int(marker.seed_value), int(marker.condition))
		var lb_local: Dictionary = _piloted_port_local()
		if not DockPortsScript.ports_compatible(target_local, lb_local):
			new_root.queue_free()
			# Codex P2: attempt_travel already advanced the scanner position + generated
			# mark; roll them back so a rejected target leaves no world/scanner state
			# pointing at a derelict the player never docked to (current_ship is untouched).
			synaptic_sea_world.set_player_position(prev_player_pos)
			if not was_generated:
				synaptic_sea_world.unmark_generated(String(marker.marker_id))
			return {"success": false, "reason": "dock_incompatible", "ship": null}

	# Leaving the current ship.
	# Phase 5a Task 5 (co-presence): the HOME ship is NO LONGER detached — it stays
	# in-tree at origin while the new derelict is placed at DERELICT_DOCK_OFFSET.
	# The home gameplay roots (interaction_root, oxygen_root, etc.) also stay
	# in-tree. A DERELICT (non-empty marker_id) keeps its retained ShipInstance in
	# visited_ships but frees its scene_root (geometry regenerates from seed on revisit).
	_sync_current_ship_combat_summary()
	_sync_current_ship_arc_summary()
	var leaving = current_ship
	if String(leaving.marker_id) == "":
		# Leaving home: record the player's position so travel_home can restore it.
		_home_player_position = (player as Node3D).global_position if player != null and player is Node3D else _home_player_position
		# Home hull STAYS in-tree (co-presence — no remove_child).
	else:
		if leaving == piloted_ship:
			# 5c: the player is piloting this ship — it is the ride, not a host to abandon.
			# It will be re-docked to the new target below; do NOT free it.
			pass
		elif leaving.scene_root != null and is_instance_valid(leaving.scene_root):
			if leaving.scene_root.get_parent() == self:
				remove_child(leaving.scene_root)
			leaving.scene_root.queue_free()
			leaving.scene_root = null  # retained instance, scene dropped

	var mid: String = String(marker.marker_id)
	var inst
	if visited_ships.has(mid):
		# Revisit: reuse the retained instance (its systems state is preserved);
		# the freshly generated geometry replaces the freed scene.
		inst = visited_ships[mid]
	else:
		# First visit: build the per-ship systems manager seeded by condition so a
		# wrecked ship boards with mostly-offline systems, and register it.
		var new_bp = ShipBlueprintScript.new(int(marker.size_class), int(marker.condition), int(marker.seed_value))
		var new_mgr = ShipSystemsManagerScript.new()
		new_mgr.configure(new_mgr.load_definitions(), new_bp.condition, new_bp.seed_value)
		inst = ShipInstanceScript.create("ship_%s" % mid, mid, new_bp, new_mgr, null)
		visited_ships[mid] = inst
		_seed_ship_models(inst)

	_attach_derelict_active(inst, new_root)
	_configure_threat_runtime_for_current_ship()
	# Phase 5b Task 5: NO player teleport into the derelict. The player rides the
	# piloted ship, which docked flush to the target; _attach_derelict_active carried
	# the player along. They cross the (closed) dock barrier themselves to board the
	# host. recompute_occupancy() confirms the player is still aboard the piloted ship.
	recompute_occupancy()
	return result

## Returns the player to the home ship instance: frees the active derelict's
## scene (its retained instance stays in visited_ships), restores
## current_ship = home_ship, and re-homes the player at the position they left
## from. Returns false if not currently away or the home ship is unavailable.
## Phase 5a Task 5 (co-presence): home hull was NEVER detached, so NO
## add_child(home_ship.scene_root) and NO _reattach_starting_gameplay_roots().
## #4 invariants preserved: repair-point/loot rebuild for the home ship.
func travel_home() -> bool:
	if not away_from_start or home_ship == null:
		return false
	_sync_current_ship_combat_summary()
	_sync_current_ship_arc_summary()
	# Phase 5b Task 5: undock the piloted ship from the current derelict so the ride
	# physically detaches before the host is freed (capture the player carry first so
	# they ride the piloted ship back home rather than being left in the freed frame).
	var carry := _capture_player_carry()
	var child_carry := _capture_subtree()
	if piloted_ship != null:
		_unbay_from_parent(piloted_ship)   # clear a stale bay slot if the piloted ship was bayed (PR#16 P2)
		DockingManagerScript.undock(piloted_ship)
	var leaving = current_ship
	if leaving != null and String(leaving.marker_id) != "":
		if leaving == piloted_ship:
			# 5c: the player is piloting this ship — it is the ride, not a host to abandon.
			# It is re-docked to home below; do NOT free it.
			pass
		elif leaving.scene_root != null and is_instance_valid(leaving.scene_root):
			if leaving.scene_root.get_parent() == self:
				remove_child(leaving.scene_root)
			leaving.scene_root.queue_free()
			leaving.scene_root = null
	# Home hull stays in-tree — no re-add needed (co-presence).
	current_ship = home_ship
	away_from_start = false
	_configure_threat_runtime_for_current_ship()
	# Domain 10 Task 5 fix (finding 2): the proximity-tooltip focus cache is keyed
	# only by subject_id, which repeats across derelicts (objective types are
	# reused per ship). Reset it on unboard so a same-typed interactable on the
	# NEXT ship is not suppressed as a "no change" — mirror _refresh_tooltip_focus's
	# own focus-lost clear transition (empty subject_id -> null payload -> panel hides).
	_last_tooltip_focus_subject_id = ""
	if is_instance_valid(menu_coordinator):
		menu_coordinator.set_tooltip_query({"subject_kind": "interactable", "subject_id": ""})
	_clear_derelict_objectives()
	_clear_loot_containers()
	_clear_repair_points()
	_clear_breach_seal_points()
	# ADR-0042: drop phantoms so they do not leak across the ship transition.
	if hallucination_manager != null and is_instance_valid(hallucination_manager):
		hallucination_manager.clear_all()
	_clear_fire_zones()
	_clear_fire_suppression_points()
	_clear_extinguisher_recharge_port()
	_build_loot_containers()
	_build_sealed_hatches()
	_build_repair_points()
	_build_breach_seal_points()
	# M7-B Task 7: returning home rebuilds interactables — re-seed/render fire.
	_seed_fires_from_damage()
	_build_fire_zones()
	# Tranche 1 (audit): the derelict arc zone was freed with the derelict
	# root — rebuild against the HOME loader (away_from_start is false here).
	_build_arc_zone()
	_restore_arc_summary_for_current_ship()
	# ADR-0042: the hallucination manager was attached to the (now-freed) derelict root,
	# so rebuild it on the home ship — otherwise home-side hallucinations never render
	# after a round trip while the director still feeds tier-3 teeth into vitals.
	_build_hallucination_runtime()
	# M7-B Task 9: manual extinguish nodes + recharge port share the fire lifecycle.
	_build_fire_suppression_points()
	_build_extinguisher_recharge_port()
	_build_crafting_stations()
	_build_production_stations()
	if tracker != null and loader != null and loader.has_method("get_objective_specs_copy"):
		# set_objectives resets the tracker's completed set; re-apply the home loop's
		# progress so returning home does not blank a partially-completed home HUD.
		tracker.set_objectives(loader.get_objective_specs_copy())
		_refresh_home_tracker_completed()
	# Phase 5b Task 5: re-dock the piloted ship to home and carry the player aboard it.
	# The player stays aboard the piloted ship (which re-docked to home) — no teleport
	# into the home derelict's frame.
	if piloted_ship != null:
		_dock_piloted_to(home_ship)
		_apply_player_carry(carry)
		_reposition_subtree(child_carry)
	_spawn_dock_barrier(home_ship)
	current_occupancy = piloted_ship if piloted_ship != null else home_ship
	recompute_occupancy()
	return true

## Re-applies the home objective loop's completion state to the ObjectiveTracker
## after a set_objectives reset (sequences below current_objective_sequence are
## complete). Mirrors, for the home ship's singleton loop, what
## _refresh_derelict_tracker does for a derelict.
func _refresh_home_tracker_completed() -> void:
	if tracker == null:
		return
	for s in range(1, current_objective_sequence):
		tracker.mark_completed(s)
	tracker.set_current_sequence(current_objective_sequence)
	if slice_complete:
		tracker.mark_run_complete()

## Validation seam: the marker_ids of every retained visited derelict.
func get_visited_ship_ids() -> Array:
	return visited_ships.keys()

## Validation seam: true if any combined status line contains `token`.
func get_combined_system_status_lines_contains(token: String) -> bool:
	for line in _combined_system_status_lines():
		if String(line).contains(token):
			return true
	return false

## Allocates the HUD CanvasLayer and the ObjectiveTracker that lives
## inside it. Called from _build_runtime_nodes (initial slice setup)
## and from _on_ship_loaded (reload via REQ-012). Extracted from
## _build_runtime_nodes so the reload path can rebuild the tracker
## after _reset_runtime_for_reload frees it — without this, the
## reload path left `tracker` pointing at a freed Node and every
## post-load interaction crashed with "Nonexistent function
## 'mark_completed' in base 'previously freed'" (REQ-014 blocking
## finding B / pre-existing REQ-012 reload lifecycle debt).
func _build_hud_layer() -> void:
	# Always release the prior hud_layer if the caller (reload) is
	# rebuilding on top of a stale one. The node itself is freed by
	# _reset_runtime_for_reload's hud_layer teardown; nulling here is
	# the safety net so the helper is idempotent.
	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.queue_free()
	hud_layer = CanvasLayer.new()
	hud_layer.name = "PlayableHudLayer"
	hud_layer.layer = 20
	add_child(hud_layer)
	tracker = ObjectiveTrackerScript.new()
	tracker.name = "ObjectiveTracker"
	# A11Y-P1-001: pass the ship's accessibility_settings into the tracker
	# so the HUD font_size and panel size come from the same seam as the
	# world Label3D labels. Tracker is parented to the hud_layer below, so
	# the tracker's _ready() will run after this call returns.
	if tracker.has_method("apply_accessibility_settings"):
		tracker.apply_accessibility_settings(accessibility_settings)
	hud_layer.add_child(tracker)
	vitals_model = PlayerVitalsModelScript.new()
	vitals_panel = PlayerVitalsPanelScript.new()
	vitals_panel.name = "PlayerVitalsPanel"
	# A11Y parity (ADR-0027): drive the vitals panel font/size from the same
	# accessibility seam as the tracker, before it is parented (its _ready then
	# builds at the stored scale).
	if vitals_panel.has_method("apply_accessibility_settings"):
		vitals_panel.apply_accessibility_settings(accessibility_settings)
	hud_layer.add_child(vitals_panel)
	hotbar_panel = HotbarPanelScript.new()
	hotbar_panel.name = "WeaponHotbarPanel"
	if hotbar_panel.has_method("apply_accessibility_settings"):
		hotbar_panel.apply_accessibility_settings(accessibility_settings)
	hud_layer.add_child(hotbar_panel)
	scanner_panel = ScannerPanelScript.new()
	scanner_panel.name = "ScannerPanel"
	scanner_panel.visible = false
	hud_layer.add_child(scanner_panel)
	scanner_panel.bind(self)
	# Restore player control on every panel close path via the signal, not just
	# the two close paths wired into _input.
	scanner_panel.panel_closed.connect(_on_scanner_panel_closed)
	chart_panel = ChartPanelScript.new()
	chart_panel.name = "ChartPanel"
	chart_panel.visible = false
	hud_layer.add_child(chart_panel)
	chart_panel.bind(web_chart_state)
	# Restore player control on every panel close path via the signal, not just
	# the toggle-close path wired into _input.
	chart_panel.panel_closed.connect(_on_chart_panel_closed)
	inventory_panel = InventoryPanelScript.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.visible = false
	hud_layer.add_child(inventory_panel)
	inventory_panel.panel_closed.connect(_on_inventory_panel_closed)
	inventory_panel.transfer_completed.connect(_on_inventory_transfer_completed)
	inventory_panel.use_requested.connect(_on_inventory_use_requested)
	menu_coordinator = MenuCoordinatorScript.new()
	menu_coordinator.name = "MenuCoordinator"
	hud_layer.add_child(menu_coordinator)
	menu_coordinator.modal_opened.connect(_on_ui_modal_opened)
	menu_coordinator.modal_closed.connect(_on_ui_modal_closed)
	menu_coordinator.save_requested.connect(request_save)
	menu_coordinator.load_requested.connect(request_load)
	menu_coordinator.quit_requested.connect(_on_ui_quit_requested)
	menu_coordinator.save_and_exit_requested.connect(_on_save_and_exit_requested)
	menu_coordinator.settings_changed.connect(_on_ui_settings_changed)
	var configured: bool = menu_coordinator.configure(
		_load_json_dict("res://data/ui/menu_definitions.json"),
		_load_json_dict("res://data/ui/tutorial_triggers.json"),
		_load_json_dict("res://data/ui/codex_entries.json"),
		_load_json_dict("res://data/ui/input_glyphs.json"),
		_load_json_dict("res://data/ui/tooltip_catalog.json"),
		_load_json_dict("res://data/ui/accessibility_presets.json"),
		_build_ui_bindings_table(),
		accessibility_settings,
	)
	if not configured:
		push_warning("PlayableGeneratedShip: MenuCoordinator configure returned false")
	# Bucket 3: make the menu/meta-screen shell player-reachable. Inject the
	# coordinator-owned states (+ the 3 release-bundle deps) so the Records submenu
	# can open Achievements / Skill Tree / Hub Upgrades / Class / Audio Log / Audio
	# Settings / Language / Save-Load / Build Info / Credits from the live pause menu.
	menu_coordinator.bind_meta_screens(
		achievement_state,
		audio_manager,
		skill_tree_state,
		player_progression,
		hub_upgrade_state,
		meta_progression_state,
		localization_catalog,
		build_metadata_state,
		save_load_menu,
		accessibility_settings,
		unlock_registry,
		_build_run_snapshot,
		demo_scope_gate,
		_demo_save_refused,
	)
	menu_coordinator.set_load_available(is_load_available())
	menu_coordinator.set_inventory_items(_inventory_hotbar_ids())
	menu_coordinator.set_hotbar_slots(_get_consumable_slot_labels())
	# Domain 10 (ADR-0045) tooltip trigger 2: same injection pattern as
	# audio_settings_panel.set_settings_push (ADR-0044) -- hand the panel a
	# Callable into this coordinator's menu_coordinator seam rather than the
	# panel holding a MenuCoordinator reference directly.
	if is_instance_valid(inventory_panel):
		inventory_panel.set_tooltip_query_push(Callable(menu_coordinator, "set_tooltip_query"))
	menu_coordinator.open_main_menu()

func _on_scanner_panel_closed() -> void:
	if is_instance_valid(player):
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)

func _on_chart_panel_closed() -> void:
	if is_instance_valid(player):
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)

func _freeze_player_for_panel() -> void:
	if is_instance_valid(player):
		player.set_physics_process(false)
		player.set_process_input(false)
		player.set_process_unhandled_input(false)

func _on_inventory_panel_closed() -> void:
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx(AudioEventSeamScript.UI_INVENTORY_CLOSE)
	if is_instance_valid(player):
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)

## A transfer/equip mutated player state: refresh carry budget (Heavy Load) and oxygen
## (the O2-pump drain benefit follows the pump in/out of the player inventory).
func _on_inventory_transfer_completed() -> void:
	_recompute_player_encumbrance()
	_ensure_consumable_hotbar_assignments()
	_refresh_oxygen_state(false, 0.0)
	_refresh_consumable_ui()
	_refresh_weapon_hotbar()

func _on_inventory_use_requested(item_id: String, use_all: bool) -> void:
	_use_consumable_item(item_id, use_all)

func _open_inventory_self() -> void:
	if not is_instance_valid(inventory_panel) or inventory_state == null:
		return
	inventory_panel.open_self(inventory_state, equipment_state)
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx(AudioEventSeamScript.UI_INVENTORY_OPEN)
	if is_instance_valid(menu_coordinator):
		menu_coordinator.trigger_tutorial("inventory_opened", "any")
	_freeze_player_for_panel()

func _open_transfer_panel_for_ship(ship_id: String) -> void:
	if not is_instance_valid(inventory_panel) or inventory_state == null:
		return
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return
	inventory_panel.open_transfer(inventory_state, inst.get_inventory(), "HOLD", equipment_state)
	_freeze_player_for_panel()

func _open_transfer_panel_for_cart(cart_id: String) -> void:
	if not is_instance_valid(inventory_panel) or inventory_state == null:
		return
	var hit: Dictionary = _find_cart_by_id(cart_id)
	if hit.is_empty():
		return
	inventory_panel.open_transfer(inventory_state, hit["cart"].get_hold(), "CART", equipment_state)
	_freeze_player_for_panel()

func _build_ui_bindings_table() -> Dictionary:
	var table: Dictionary = {
		"interact": get_input_action_keycodes_for_validation("interact"),
		"move_up": get_input_action_keycodes_for_validation("move_forward"),
		"move_down": get_input_action_keycodes_for_validation("move_back"),
		"move_left": get_input_action_keycodes_for_validation("move_left"),
		"move_right": get_input_action_keycodes_for_validation("move_right"),
		"toggle_inventory": get_input_action_keycodes_for_validation("toggle_inventory"),
		"toggle_scanner": get_input_action_keycodes_for_validation("toggle_scanner"),
		"ui_pause": get_input_action_keycodes_for_validation("ui_pause"),
		"ui_cancel": get_input_action_keycodes_for_validation("ui_cancel"),
		"ui_accept": get_input_action_keycodes_for_validation("ui_accept"),
		"save_run": get_input_action_keycodes_for_validation("save_run"),
		"load_run": get_input_action_keycodes_for_validation("load_run"),
		"ui_open_codex": get_input_action_keycodes_for_validation("ui_open_codex"),
		"ui_open_map": get_input_action_keycodes_for_validation("ui_open_map"),
	}
	for action_name in ["move_forward", "move_back", "move_left", "move_right"]:
		if not InputMap.has_action(action_name):
			continue
	return table

func _inventory_hotbar_ids() -> Array:
	if inventory_state == null:
		return []
	var ids: Array = inventory_state.items.keys()
	ids.sort()
	var out: Array = []
	for id_variant in ids:
		out.append(String(id_variant))
	return out

func _weapon_ammo_item_id(weapon_id: String) -> String:
	# Single source of truth: weapon_definitions.json's ammo_item_id (the same
	# field _begin_weapon_reload reads). The old hardcoded match here silently
	# diverged from the data file for any new/renamed weapon.
	if not is_instance_valid(threat_manager):
		return ""
	var weapon: Variant = threat_manager.weapon_definitions.get(weapon_id, {})
	if weapon is Dictionary:
		return str((weapon as Dictionary).get("ammo_item_id", ""))
	return ""

func _equipped_primary_weapon_id() -> String:
	if equipment_state == null:
		return ""
	# Weapon ids ARE the equip item ids (PR #61 Codex P2): the old
	# capacitor_cell->shock_probe alias made the ammo double as the weapon,
	# so auto-equip consumed looted ammo and ThreatManager.attack_with_weapon
	# (which compares equipped ids literally) always rejected the probe.
	# The weapon set comes from weapon_definitions.json (same source
	# _begin_weapon_reload reads) — no hardcoded list to diverge.
	if not is_instance_valid(threat_manager):
		return ""
	for slot_id in ["primary_hand", "secondary_hand"]:
		var item_id: String = str(equipment_state.get_equipped(slot_id))
		if threat_manager.weapon_definitions.has(item_id):
			return item_id
	return ""

func _player_armor_profile() -> Dictionary:
	var profile: Dictionary = {
		"flat_reduction": {},
		"resistance": {},
		"durability": 0.0,
		"max_durability": 0.0,
		"wear_factor": 0.35,
	}
	if equipment_state == null:
		return profile
	var suit_id: String = str(equipment_state.get_equipped("suit"))
	if suit_id == "hardsuit":
		profile["resistance"] = {
			"physical": 0.20,
			"bleed": 0.15,
			"fire": 0.25,
			"electric": 0.20,
		}
		profile["durability"] = 40.0
		profile["max_durability"] = 40.0
	return profile

func _combat_anchor_for_current_ship() -> Vector3:
	if current_ship != null and is_instance_valid(current_ship.scene_root):
		return (current_ship.scene_root as Node3D).global_position
	return Vector3.ZERO

func _combat_layout_for_current_ship() -> Dictionary:
	if current_ship != null and typeof(current_ship.built_layout) == TYPE_DICTIONARY and not current_ship.built_layout.is_empty():
		return current_ship.built_layout
	if loader != null and loader.has_method("get_layout_copy"):
		return loader.get_layout_copy()
	return {}

func _combat_markers_for_current_ship() -> Array:
	var layout: Dictionary = _combat_layout_for_current_ship()
	var raw: Variant = layout.get("encounters", [])
	if raw is Array and not (raw as Array).is_empty():
		return (raw as Array).duplicate(true)
	if loader != null and loader.has_method("get_encounter_markers"):
		return loader.get_encounter_markers()
	return []

func _sync_current_ship_combat_summary() -> void:
	if current_ship == null or threat_manager == null:
		return
	current_ship.combat_summary = threat_manager.get_summary()

func _sync_current_ship_arc_summary() -> void:
	if current_ship == null or electrical_arc_state == null:
		return
	current_ship.arc_summary = electrical_arc_state.get_summary().duplicate(true)

func _restore_arc_summary_for_current_ship() -> void:
	if current_ship == null or electrical_arc_state == null:
		return
	if not current_ship.arc_summary.is_empty():
		electrical_arc_state.apply_summary(current_ship.arc_summary)
	_refresh_arc_state(true)
	_sync_current_ship_arc_summary()

func _configure_threat_runtime_for_current_ship() -> void:
	if threat_manager == null:
		return
	var anchor: Vector3 = _combat_anchor_for_current_ship()
	threat_manager.fallback_anchor = anchor
	if current_ship != null and not current_ship.combat_summary.is_empty():
		threat_manager.apply_summary(current_ship.combat_summary)
	else:
		threat_manager.configure_for_layout(_combat_layout_for_current_ship(), _combat_markers_for_current_ship(), anchor)
	_refresh_weapon_hotbar()

func _refresh_weapon_hotbar() -> void:
	if not is_instance_valid(hotbar_panel):
		return
	var weapon_id: String = _equipped_primary_weapon_id()
	if weapon_id.is_empty():
		_last_weapon_hotbar_text = "Weapon: unarmed | Threat: %.2f | Hostiles: %d" % [
			threat_manager.awareness_indicator if is_instance_valid(threat_manager) else 0.0,
			threat_manager.get_active_threat_count() if is_instance_valid(threat_manager) else 0,
		]
		hotbar_panel.set_hotbar_text(_last_weapon_hotbar_text)
		return
	var weapon_name: String = ItemDefsScript.display_name(_definitions_for_equip(), weapon_id)
	var ammo_item_id: String = _weapon_ammo_item_id(weapon_id)
	var ammo_text: String = "melee"
	if not ammo_item_id.is_empty() and inventory_state != null:
		ammo_text = "%s=%d" % [ammo_item_id, inventory_state.get_quantity(ammo_item_id)]
	var combat_text: String = "idle"
	if is_instance_valid(threat_manager):
		combat_text = "combat" if threat_manager.has_combat_engagement() else "stealth"
	_last_weapon_hotbar_text = "%s | %s | Threat %.2f | %s" % [
		weapon_name,
		ammo_text,
		threat_manager.awareness_indicator if is_instance_valid(threat_manager) else 0.0,
		combat_text,
	]
	hotbar_panel.set_hotbar_text(_last_weapon_hotbar_text)

func _attack_with_equipped_weapon() -> Dictionary:
	if threat_manager == null:
		return {"ok": false, "reason": "threat_manager_missing"}
	var weapon_id: String = _equipped_primary_weapon_id()
	if weapon_id.is_empty():
		weapon_id = "crowbar"
	var result: Dictionary = threat_manager.attack_with_weapon(weapon_id, inventory_state, equipment_state, ammo_state)
	if bool(result.get("ok", false)):
		_refresh_inventory_hud()
		_refresh_player_vitals(0.0)
		_sync_current_ship_combat_summary()
	# ADR-0042: a swing also dissipates a phantom within reach. On an empty magazine
	# the shot is a dry-fire click (no round spent) but the swing still counts as the
	# wasted-action teeth.
	if hallucination_manager != null and is_instance_valid(hallucination_manager):
		var ppos: Vector3 = (player as Node3D).global_position if player != null and player is Node3D else Vector3.ZERO
		if hallucination_manager.dissipate_phantom_in_range(ppos):
			result["phantom_dissipated"] = true
			result["ok"] = true
			_refresh_inventory_hud()
	_refresh_weapon_hotbar()
	return result

## Domain 5: begin a timed reload for the currently equipped ranged weapon. Debits
## reload_target rounds from inventory immediately; AmmoState credits the magazine on
## completion (after RELOAD_SECONDS). Melee weapons (no ammo_item_id) are no-ops.
func _begin_weapon_reload() -> void:
	if ammo_state == null or ammo_state.is_reloading() or threat_manager == null:
		return
	var weapon_id: String = _equipped_primary_weapon_id()
	if weapon_id.is_empty():
		return
	var weapon: Dictionary = threat_manager.weapon_definitions.get(weapon_id, {}) if threat_manager.weapon_definitions.get(weapon_id, {}) is Dictionary else {}
	var ammo_item_id: String = str(weapon.get("ammo_item_id", ""))
	if ammo_item_id.is_empty():
		return  # melee: no reload
	var mag_size: int = int(weapon.get("magazine_size", 0))
	var reserve: int = inventory_state.get_quantity(ammo_item_id) if inventory_state != null else 0
	if ammo_state.begin_reload(weapon_id, mag_size, reserve):
		if inventory_state != null:
			inventory_state.remove_item(ammo_item_id, ammo_state.reload_target)  # commit reserve
		_refresh_inventory_hud()
		_refresh_weapon_hotbar()

## Domain 2 (BP2): a derived "is the player in a lit area" signal. A powered ship is
## lit (player more visible); an unpowered/derelict ship is dark (stealthier). Uses
## the active ship's power system (no per-room lighting model exists).
func _player_room_lit() -> bool:
	var mgr = _active_systems_manager()
	return mgr != null and mgr.is_operational("power")

func _tick_threat_runtime(delta: float) -> void:
	if threat_manager == null:
		return
	var player_pos: Vector3 = (player as Node3D).global_position if player != null and player is Node3D else Vector3.ZERO
	var moving: bool = is_instance_valid(player) and player.has_method("is_moving") and player.is_moving()
	var crouching: bool = is_instance_valid(player) and player.has_method("is_crouching") and player.is_crouching()
	threat_manager.set_player_signals(
		0.3 if moving else 0.05,          # noise from movement
		0.6 if _player_room_lit() else 0.15,  # light from room power
		0.8,                               # base visibility (proximity-scaled per threat in the manager)
		crouching,                          # crouch reduces emitted noise + visibility in DetectionState
		"",
	)
	threat_manager.tick_threats(delta, vitals_state, status_effects_state, _player_armor_profile(), player_pos)
	_sync_current_ship_combat_summary()
	_refresh_weapon_hotbar()

func _consumable_pipeline_context() -> Dictionary:
	return {
		"effect_dispatcher": effect_dispatcher,
		"consumable_state": consumable_state,
		"medicine_state": medicine_state,
		"stimulant_state": stimulant_state,
		"addiction_state": addiction_state,
		"ammo_state": ammo_state,
		"utility_state": utility_item_state,
		"vitals_state": vitals_state,
		"sanity_state": sanity_state,
		"radiation_state": radiation_state,
		"body_temperature_state": body_temperature_state,
		"status_effects_state": status_effects_state,
		"spoilage_state": spoilage_state,
	}

func _get_consumable_slot_labels() -> Array:
	var out: Array = []
	if consumable_state == null:
		return out
	for item_id_variant in consumable_state.hotbar_slots:
		var item_id: String = str(item_id_variant)
		if item_id.is_empty():
			out.append("(empty)")
		else:
			var qty: int = inventory_state.get_quantity(item_id) if inventory_state != null else 0
			out.append("%s x%d" % [ItemDefsScript.display_name(_definitions_for_equip(), item_id), qty])
	return out

func _refresh_consumable_ui(selected_index: int = 0) -> void:
	if is_instance_valid(menu_coordinator):
		menu_coordinator.set_inventory_items(_inventory_hotbar_ids())
		menu_coordinator.set_hotbar_slots(_get_consumable_slot_labels(), selected_index)

func _ensure_consumable_hotbar_assignments() -> void:
	if consumable_state == null or inventory_state == null:
		return
	var usable: Array = []
	for item_id_variant in _inventory_hotbar_ids():
		var item_id: String = str(item_id_variant)
		if inventory_state.get_quantity(item_id) > 0 and consumable_state.has_use_action(item_id):
			usable.append(item_id)
	for slot_index in range(consumable_state.hotbar_slots.size()):
		var current: String = str(consumable_state.hotbar_slots[slot_index])
		if current.is_empty() or inventory_state.get_quantity(current) <= 0 or not consumable_state.has_use_action(current):
			consumable_state.assign_hotbar_slot(slot_index, usable[slot_index] if slot_index < usable.size() else "")

func _use_consumable_item(item_id: String, use_all: bool = false) -> Dictionary:
	if consumable_state == null or inventory_state == null:
		return {"ok": false, "reason": "consumable_pipeline_missing"}
	var result: Dictionary = consumable_state.use_item(item_id, inventory_state, _consumable_pipeline_context(), use_all)
	if bool(result.get("ok", false)):
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx(AudioEventSeamScript.SFX_TOOL_USE)
		_ensure_consumable_hotbar_assignments()
		_recompute_player_encumbrance()
		_refresh_oxygen_state(false, 0.0)
		_refresh_player_vitals(0.0)
		_refresh_consumable_ui()
	return result

func _use_consumable_hotbar_slot(slot_index: int) -> Dictionary:
	if consumable_state == null or inventory_state == null:
		return {"ok": false, "reason": "consumable_pipeline_missing"}
	var result: Dictionary = consumable_state.use_hotbar_slot(slot_index, inventory_state, _consumable_pipeline_context())
	if bool(result.get("ok", false)):
		_ensure_consumable_hotbar_assignments()
		_recompute_player_encumbrance()
		_refresh_oxygen_state(false, 0.0)
		_refresh_player_vitals(0.0)
		_refresh_consumable_ui(slot_index)
	return result

func _refresh_ui_shell_runtime() -> void:
	if not is_instance_valid(menu_coordinator):
		return
	menu_coordinator.set_load_available(is_load_available())
	menu_coordinator.set_inventory_items(_inventory_hotbar_ids())
	menu_coordinator.set_hotbar_slots(_get_consumable_slot_labels())
	_refresh_weapon_hotbar()

## Domain 10 (ADR-0045) tooltip trigger 1: proximity focus on interactables.
## Called from BOTH _process branches (mirrors _refresh_audio_state's dual
## wiring -- the derelict field run is the PRIMARY gameplay context, so this
## must not be home-only). Scans the live interactable collections
## (candidate_player is already maintained by Interactable's own
## body_entered/body_exited physics callbacks -- this scan is read-only) for
## the nearest node whose candidate_player == player, and calls
## set_tooltip_query ONLY when the focused subject id changes (TooltipPresenter.
## resolve() emits payload_changed unconditionally on every call, so an
## unguarded per-frame call here would spam the signal). On focus lost, pushes
## an empty subject_id -- an unknown/empty id resolves to a null payload
## (TooltipPresenter's existing graceful path), which hides the panel.
func _refresh_tooltip_focus() -> void:
	if not is_instance_valid(menu_coordinator) or not is_instance_valid(player):
		return
	var nearest: Node = null
	var nearest_dist: float = INF
	var player_pos: Vector3 = (player as Node3D).global_position if player is Node3D else Vector3.ZERO
	for collection in [interactables, derelict_interactables]:
		for it in collection:
			if not is_instance_valid(it) or it.candidate_player != player:
				continue
			var it_pos: Vector3 = (it as Node3D).global_position if it is Node3D else Vector3.ZERO
			var dist: float = it_pos.distance_to(player_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = it
	var subject_id: String = String(nearest.tooltip_subject_id) if nearest != null else ""
	if subject_id == _last_tooltip_focus_subject_id:
		return
	_last_tooltip_focus_subject_id = subject_id
	menu_coordinator.set_tooltip_query({"subject_kind": "interactable", "subject_id": subject_id})

## Validation seam: the last subject_id pushed by _refresh_tooltip_focus
## (matches the get_last_caption_line() convention).
func get_focused_tooltip_subject_for_validation() -> String:
	return _last_tooltip_focus_subject_id

func _on_ui_modal_opened(_menu_id: String) -> void:
	_freeze_player_for_panel()

func _on_ui_modal_closed(_previous_menu_id: String) -> void:
	if player != null:
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)

func _on_ui_quit_requested() -> void:
	# ADR-0043: "Quit to Main Menu" now really returns to the title screen
	# instead of reopening the in-scene main_menu overlay (the old stub
	# behavior -- there was no real title/quit path before this domain).
	emit_signal("return_to_title_requested")

## ADR-0043 Save & Exit: request_save() the SAME guarded path F5/autosave
## already use (world.json write), then leave to the title screen only on
## success. Deliberately does NOT reuse AutosavePolicy.try_quicksave's
## cooldown -- that guard exists to stop autosave-cadence thrashing during
## active play, not to gate a terminal "I am leaving" action; a cooldown
## that could silently skip the write on the player's exit is a
## correctness footgun. On failure, surface a toast and do NOT exit --
## never silently lose progress on a leave action. The toast is driven by
## the "save_and_exit_failed"/"any" tutorial trigger registered in
## data/ui/tutorial_triggers.json; menu_coordinator.trigger_tutorial()
## returning a non-empty id (and firing TutorialState.triggered) is the
## proof this actually renders -- an unregistered trigger id would
## silently no-op instead (see save_and_exit_smoke.gd's failure stage).
func _on_save_and_exit_requested() -> void:
	var ok: bool = request_save()
	if ok:
		emit_signal("return_to_title_requested")
	else:
		if is_instance_valid(menu_coordinator):
			menu_coordinator.trigger_tutorial("save_and_exit_failed", "any")

func _on_ui_settings_changed(_summary: Dictionary) -> void:
	apply_accessibility_settings(accessibility_settings)
	# REQ-AU criterion 3 (ADR-0044): SettingsState.captions is the single
	# source of truth for SfxEventRouter.captions_enabled. _summary is the
	# SettingsState payload emitted by menu_coordinator.settings_changed
	# (settings_state.get_summary()), which always carries a "captions" key
	# (schema default true) — read it directly rather than re-deriving it
	# from menu_coordinator to keep this a pure one-line push.
	if is_instance_valid(audio_manager) and audio_manager.sfx_router != null:
		audio_manager.sfx_router.captions_enabled = bool(_summary.get("captions", true))

func _on_ship_loaded(summary: Dictionary) -> void:
	if playable_started:
		return
	playable_started = true
	# REQ-014 blocking finding B: rebuild the HUD/tracker on every ship
	# load, not just the first one. After _reset_runtime_for_reload
	# tears down the previous slice (incl. hud_layer and tracker), the
	# coordinator must rebuild them or the post-load interaction path
	# (e.g. completing a repair_junction after load) crashes with
	# "Nonexistent function 'mark_completed' in base 'previously freed'".
	_build_hud_layer()
	_spawn_player()
	_spawn_camera()
	_refresh_ui_shell_runtime()
	# Phase 4.5: wrap the freshly-loaded starting ship as current_ship. Reuses
	# the coordinator's existing ship_systems_manager (Approach A: the starting
	# slice's systems are untouched). marker_id "" marks it as the home ship.
	if current_ship == null:
		current_ship = ShipInstanceScript.create("ship_start", "", _load_blueprint_for_systems(), ship_systems_manager, loader)
		# Sub-project #1: keep a stable reference to the home ship so travel_home
		# and world-load can restore it.
		home_ship = current_ship
		# Store the layout so DockPorts can derive port descriptors for boot docking.
		home_ship.built_layout = loader.get_layout_copy()
		_spawn_hangar_control(home_ship)
		_spawn_cargo_hold_control(home_ship)
		_spawn_cart_controls_for_ship(home_ship)
		# Phase 5a Task 6: initialise occupancy to home ship (player starts here).
		current_occupancy = home_ship
		# Phase 5a Task 7: build the physical lifeboat docked to the starting derelict.
		# The lifeboat is now port-aligned via DockingManager (replaces fixed LIFEBOAT_DOCK_OFFSET).
		_build_lifeboat_at_home()
	_configure_threat_runtime_for_current_ship()
	_build_interactables()
	_build_slice_affordance_labels()
	_build_route_control_gates()
	_refresh_route_control_from_ship_systems()
	_build_breach_zone()
	# REQ-007: spawn the portable oxygen pump pickup now that the player,
	# interactables, and breach zone exist. The pickup is parented to
	# tool_pickup_root and reads its world position from a side room
	# (tool_storage_01 if defined) with a player-spawn fallback.
	_build_tool_pickup()
	_ensure_consumable_hotbar_assignments()
	_refresh_consumable_ui()
	# REQ-014: spawn the junction_calibrator pickup in a different side
	# room (galley_01 with a player-spawn fallback offset on the
	# opposite side of the spawn). Same parent root as the oxygen pump
	# so the existing reset/reload teardown covers it.
	_build_junction_calibrator_pickup()
	_refresh_oxygen_state(true, 0.0)
	_refresh_weapon_hotbar()
	_build_arc_zone()
	_restore_arc_summary_for_current_ship()
	_build_loot_containers()
	_build_sealed_hatches()
	_build_repair_points()
	_build_breach_seal_points()
	# M7-B Task 7: genuine fresh build — seed fires from already-damaged systems,
	# then render the burning set as passable zones.
	_seed_fires_from_damage()
	_build_fire_zones()
	# ADR-0042: (re)build the sanity hallucination director + manager for the active
	# ship. Attaches like fire zones so phantom world positions are valid in-frame; runs
	# on every ship load (fresh build + post-reload), so it lives here rather than in the
	# reload-only reset path. clear_all() on the prior manager runs in the teardown sites.
	_build_hallucination_runtime()
	# M7-B Task 9: manual extinguish nodes + recharge port share the fire lifecycle.
	_build_fire_suppression_points()
	_build_extinguisher_recharge_port()
	_build_crafting_stations()
	_build_production_stations()
	tracker.set_objectives(loader.get_objective_specs_copy())
	current_objective_sequence = 1
	slice_complete = false
	_activate_current_objective()
	ready_summary = summary.duplicate(true)
	ready_summary["player_spawned"] = player != null
	ready_summary["camera_spawned"] = camera_rig != null
	ready_summary["collision_shape_count"] = loader.count_collision_shapes()
	ready_summary["playable_interactable_count"] = interactables.size()
	print("PLAYABLE SHIP READY player_spawned=%s camera_spawned=%s objectives=%d collision_shapes=%d" % [str(player != null).to_lower(), str(camera_rig != null).to_lower(), interactables.size(), loader.count_collision_shapes()])
	emit_signal("playable_ready", get_playable_summary())

func _on_loader_failed(reason: String) -> void:
	last_failure_reason = reason
	push_error("PLAYABLE SHIP FAIL reason=%s" % reason)
	emit_signal("playable_failed", reason)

## Break the home_ship ↔ lifeboat_ship RefCounted cycle before this Node3D is
## freed. Without this, both ShipInstances keep each other alive (and their
## preloaded GDScript resources with them), producing the "7 resources still in
## use at exit" error that breaks the regression bundle's clean_output contract.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_break_ship_instance_cycles()

func _break_ship_instance_cycles() -> void:
	# Break lifeboat → home cycle.
	if lifeboat_ship != null:
		lifeboat_ship.parent_ship = null
		lifeboat_ship.docked_ships.clear()
	# Break home → lifeboat cycle.
	if home_ship != null:
		home_ship.docked_ships.clear()
	# Break any visited-derelict parent_ship back-pointers.
	for mid in visited_ships:
		var inst = visited_ships[mid]
		if inst != null:
			inst.parent_ship = null
			inst.docked_ships.clear()

## Phase 5a Task 7: build the physical lifeboat and dock it to the home derelict.
## Called from the home-wrap path in _on_ship_loaded (guarded by `current_ship == null`).
## Safe to call multiple times — frees any prior lifeboat_ship.scene_root first.
func _build_lifeboat_at_home() -> void:
	# Free any prior lifeboat root (reload safety — should not be in-tree here since
	# _reset_runtime_for_reload tears it down, but guard defensively).
	if lifeboat_ship != null and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root):
		var old_root: Node3D = lifeboat_ship.scene_root as Node3D
		if old_root != null and old_root.get_parent() == self:
			remove_child(old_root)
		old_root.queue_free()
		lifeboat_ship = null

	# Skin the lifeboat's structural modules by the run's deterministic biome
	# (seed-based; same resolver the loot system uses). The floorplan is fixed —
	# only the per-role module kit changes, so each run's home craft looks themed
	# without altering the layout the player learns.
	var lb_root: Node3D = LifeBoatBuilderScript.build(_resolve_current_loot_biome_id())
	if lb_root == null:
		push_error("PlayableGeneratedShip: LifeBoatBuilder.build() returned null; lifeboat not created")
		return

	# Create the ShipInstance: shared systems_manager so #4 opening-damage, travel-gate,
	# and repair semantics stay exactly as they are.
	lifeboat_ship = ShipInstanceScript.create("lifeboat", "", null, ship_systems_manager, lb_root)
	lifeboat_ship.built_layout = LifeBoatBuilderScript.build_layout()
	lifeboat_ship.get_access().claim(PLAYER_LOCAL_ID)

	# Add to the scene tree FIRST so host/mobile global_transforms resolve, then
	# port-align the lifeboat to the home airlock via DockingManager (the lifeboat now
	# port-docks to the host instead of parking at a fixed anchor offset).
	add_child(lb_root)
	piloted_ship = lifeboat_ship
	var dock_result: Dictionary = _dock_piloted_to(home_ship)
	if not bool(dock_result.get("success", false)):
		push_error("PlayableGeneratedShip: boot dock failed — reason=%s" % str(dock_result.get("reason", "?")))
	# Phase 5b Task 6: spawn the boot home barrier so boarding home at the canonical
	# opening is consistent with boarding a travel target (both require seam interaction).
	_spawn_dock_barrier(home_ship)
	# 5c: the lifeboat's bridge terminal is spawned AFTER _spawn_dock_barrier(home_ship)
	# because that call clears bridge_terminals (it shares the dock-transition teardown).
	# Spawned post-add_child so the terminal is in-tree for the login range gate.
	_spawn_bridge_terminal(lifeboat_ship)
	_spawn_hangar_control(lifeboat_ship)
	_spawn_cargo_hold_control(lifeboat_ship)
	_spawn_cart_controls_for_ship(lifeboat_ship)

## Port-aligns piloted_ship's airlock to host's dock port and writes the dock
## relationship. host.scene_root must be in-tree. Returns the dock() result dict.
## The piloted ship's OWN dock port (ship-local). The lifeboat exposes an airlock
## port; a claimed derelict exposes its dock-room port. Used both to dock the piloted
## ship to a target and to pre-check compatibility before committing a travel.
func _piloted_port_local() -> Dictionary:
	if piloted_ship == null:
		return {}
	if piloted_ship == lifeboat_ship:
		return DockPortsScript.for_lifeboat(piloted_ship.built_layout)
	return DockPortsScript.for_derelict(piloted_ship.built_layout, _ship_seed(piloted_ship), _ship_condition_class(piloted_ship))

func _dock_piloted_to(host) -> Dictionary:
	if piloted_ship == null or host == null or host.scene_root == null:
		return {"success": false, "reason": "dock_failed"}
	var cc := 0 if host == home_ship else _ship_condition_class(host)
	var host_local: Dictionary = DockPortsScript.for_derelict(host.built_layout, _ship_seed(host), cc)
	var host_world: Dictionary = DockingManagerScript.host_port_to_world(host, host_local)
	var mobile_local: Dictionary = _piloted_port_local()
	if not DockPortsScript.ports_compatible(host_world, mobile_local):
		return {"success": false, "reason": "dock_incompatible"}
	return DockingManagerScript.dock(host, piloted_ship, host_world, mobile_local)

func _ship_seed(inst) -> int:
	if inst != null and inst.blueprint != null and ("seed_value" in inst.blueprint):
		return int(inst.blueprint.seed_value)
	return 0

func _ship_condition_class(inst) -> int:
	if inst != null and inst.blueprint != null and ("condition" in inst.blueprint):
		return int(inst.blueprint.condition)
	return 0

func _spawn_player() -> void:
	player = PlayerControllerScript.new()
	player.name = "PlayerController"
	add_child(player)
	player.teleport_to(loader.get_start_transform().origin + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0))
	player.interact_requested.connect(_on_player_interact_requested)
	player.field_craft_requested.connect(_on_player_field_craft_requested)

func _spawn_camera() -> void:
	camera_rig = IsoCameraRigScript.new()
	camera_rig.name = "IsoCameraRig"
	add_child(camera_rig)
	camera_rig.set_follow_target(player)
	camera_rig.make_current()

func _build_interactables() -> void:
	interactables.clear()
	sequence_interactables.clear()
	# REQ-014: clear the per-sequence kind lookup so a fresh interactable
	# build reflects only the current loader's objective specs (e.g. after
	# a save/load reload).
	sequence_kinds.clear()
	if objective_progress_state != null:
		objective_progress_state.reset()
	for child in interaction_root.get_children():
		interaction_root.remove_child(child)
		child.free()
	for objective_variant in loader.get_objective_specs_copy():
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var sequence: int = int(objective.get("sequence", 0))
		var kind: String = str(objective.get("kind", "single"))
		# REQ-014: cache the kind per sequence so _on_interactable_completed
		# can decide whether to apply the junction_calibrator without
		# re-walking the loader's objective specs.
		sequence_kinds[sequence] = kind
		var steps: Array = []
		var steps_variant: Variant = objective.get("steps", [])
		if typeof(steps_variant) == TYPE_ARRAY:
			steps = steps_variant
		if kind == "repair_junction" and steps.size() > 1:
			var required_steps: int = steps.size()
			var objective_type: String = str(objective.get("type", "unknown"))
			if objective_progress_state != null:
				objective_progress_state.register_objective(sequence, objective_type, required_steps)
			for step_variant in steps:
				if typeof(step_variant) != TYPE_DICTIONARY:
					continue
				var step: Dictionary = step_variant
				var step_position_variant: Variant = step.get("position", Vector3.INF)
				if typeof(step_position_variant) != TYPE_VECTOR3:
					continue
				var interactable = InteractableScript.new()
				interactable.configure_from_step(objective, step, step_position_variant, 1.8)
				interactable.interaction_completed.connect(_on_interactable_completed)
				interaction_root.add_child(interactable)
				interactables.append(interactable)
				_add_interactable_to_sequence(sequence, interactable)
		else:
			var position_variant: Variant = objective.get("position", Vector3.INF)
			if typeof(position_variant) != TYPE_VECTOR3:
				continue
			var interactable = InteractableScript.new()
			interactable.configure_from_objective(objective, position_variant, 1.8)
			interactable.interaction_completed.connect(_on_interactable_completed)
			interaction_root.add_child(interactable)
			interactables.append(interactable)
			_add_interactable_to_sequence(sequence, interactable)

func _add_interactable_to_sequence(sequence: int, interactable: Node) -> void:
	if not sequence_interactables.has(sequence):
		sequence_interactables[sequence] = []
	sequence_interactables[sequence].append(interactable)

func _on_player_interact_requested(player_body: PlayerController) -> void:
	# Phase 4.5: while aboard a traveled derelict the starting ship's retained
	# interactables/pickups are detached but still referenced here; gate them so
	# a derelict cannot complete stale starting-ship objectives.
	# Phase 5b: barrier pass is unconditional — the home seam also has a barrier at boot,
	# so opening/breaching the dock seam must work whether the player is at home or away.
	for b in dock_barriers:
		if is_instance_valid(b) and not b.opened and b.try_start(player_body):
			return
	for t in bridge_terminals:
		if is_instance_valid(t) and t.try_login(player_body):
			return
	if away_from_start:
		# Sub-project #4: try repair points before loot/objectives.
		for rp in repair_points:
			if is_instance_valid(rp) and rp.try_start(player_body):
				return
		# M7-A: hull breach seal points share the repair-point precedence (survival-critical).
		for sp in breach_seal_points:
			if is_instance_valid(sp) and sp.try_start(player_body):
				return
		# M7-B: fire suppression points share the survival-critical precedence.
		for fp in fire_suppression_points:
			if is_instance_valid(fp) and fp.try_start(player_body):
				return
		# Sub-project #3: derelict loot containers are pickup-like interactables.
		# Try them before objectives, matching the home ship's tool-pickup
		# precedence when an objective and pickup share the same interaction area.
		for lc in loot_containers:
			if is_instance_valid(lc) and lc.try_interact(player_body):
				return
		# Domain 5: sealed hatch bypass (lockpick/hack_chip flag required).
		if _try_bypass_nearest_hatch():
			return
		# Sub-project #2: the boarded derelict has its own objective interactables.
		for it in derelict_interactables:
			if is_instance_valid(it) and it.try_interact(player_body):
				return
		# Hangar bay dock/launch (co-present ships into/out of hangar slots).
		if _try_hangar_interact(player_body):
			return
		# Sub-project #6 (cargo): deposit is the lowest-priority fallback — only fires
		# if nothing more specific (repair/loot/objective) claimed the interact here.
		if _try_cargo_deposit(player_body):
			return
		if _try_cart_interact(player_body):
			return
		return
	# Sub-project #4: try lifeboat repair points before pickups/objectives.
	for rp in repair_points:
		if is_instance_valid(rp) and rp.try_start(player_body):
			return
	# M7-A: hull breach seal points share the repair-point precedence (survival-critical).
	for sp in breach_seal_points:
		if is_instance_valid(sp) and sp.try_start(player_body):
			return
	# M7-B: fire suppression points share the survival-critical precedence.
	for fp in fire_suppression_points:
		if is_instance_valid(fp) and fp.try_start(player_body):
			return
	# ADR-0038: home-ship crafting / salvage stations. Range-gated; tried after repairs so a
	# repair point and a station sharing an area resolve to the repair first.
	for st in crafting_stations:
		if is_instance_valid(st) and st.try_interact(player_body):
			return
	# Domain 3: persistent production stations (hydroponics + water_recycler). Same
	# priority tier as crafting stations; tried right after them.
	for st in production_stations:
		if is_instance_valid(st) and st.try_interact(player_body):
			return
	# Home-ship loot containers (spawned by _build_loot_containers when current is home).
	# Previously only the away branch iterated loot_containers, so home crates were
	# unreachable through the real interact path (validation seam only).
	for lc in loot_containers:
		if is_instance_valid(lc) and lc.try_interact(player_body):
			return
	# REQ-007: tool pickup is an interaction like any other. Try it first
	# (before objective interactables) so the player can pick up the pump
	# when standing in front of it.
	if tool_pickup != null and tool_pickup.try_interact(player_body):
		return
	# REQ-014: junction_calibrator pickup is a second pickup; the
	# acquisition event is dispatched through the same shared ToolPickup
	# signal as the oxygen pump so the coordinator can refresh the HUD
	# via the same code path.
	if junction_calibrator_pickup != null and junction_calibrator_pickup.try_interact(player_body):
		return
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if interactable.try_interact(player_body):
			return
	# Hangar bay dock/launch at home (home ship is the primary hangar host).
	if _try_hangar_interact(player_body):
		return
	# Sub-project #6 (cargo): deposit-all is the lowest-priority fallback at home too —
	# walk up to the cargo hold and interact to dump salvage when nothing else claims it.
	if _try_cargo_deposit(player_body):
		return
	if _try_cart_interact(player_body):
		return

## Walk-up cargo deposit: deposits all haulable salvage into the hold of whichever
## cargo control the player is standing at (strict in-range gate). Returns true iff a
## deposit fired. Emit-only control + coordinator-owned transfer (single ownership).
func _try_cargo_deposit(player_body) -> bool:
	for ch in cargo_hold_controls:
		if is_instance_valid(ch) and ch.try_deposit(player_body):
			return true
	return false

## Hangar bay interact: prefer docking a co-present airlock-docked ship into a free
## slot; otherwise launch the first bayed ship. Only fires when a HangarBayControl is
## in range AND a real dock/launch action is available (does not consume interact on
## a silent no-op). Returns true iff a hangar request was emitted.
func _try_hangar_interact(player_body) -> bool:
	for c in hangar_controls:
		if not is_instance_valid(c):
			continue
		var carrier = _find_ship_by_id(String(c.carrier_id))
		if carrier == null:
			continue
		var bay = carrier.get_hangar()
		if bay == null or bay.slot_count <= 0:
			continue
		# Prefer dock when a co-present candidate exists and a free slot is available.
		if _bay_dock_candidate(carrier) != null and c.try_dock(player_body, -1):
			return true
		# Otherwise launch the first occupied slot (if any).
		if _first_occupied_slot(bay) >= 0 and c.try_launch(player_body, -1):
			return true
	return false

## Walk-up cart interact: grab if not held, else load salvage into it. Lowest-priority
## fallback (Phase 7 will add the picker for unload/release; seam-driven for now).
func _try_cart_interact(player_body) -> bool:
	for c in cart_controls:
		if not is_instance_valid(c):
			continue
		if grabbed_cart == null:
			if c.try_grab(player_body):
				return true
		else:
			if c.try_load(player_body):
				return true
	return false

func _on_interactable_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String, step_id: String) -> void:
	if sequence != current_objective_sequence:
		return

	# REQ-014: apply the junction_calibrator BEFORE the step completion
	# so the reduced required_steps is reflected in the same interaction
	# frame's progress summary. Only sequences whose gameplay_slice spec
	# declared `kind == "repair_junction"` are eligible; the sequence_kinds
	# lookup is populated by _build_interactables from the loader specs.
	#
	# The pre-calibration required_steps is what governs whether we take
	# the multi-step complete_step path or the single-step completion path.
	# Reading the value AFTER the calibrator consume would observe the
	# post-calibration required_steps (e.g. 1 for a 2-step junction reduced
	# by the calibrator) and skip complete_step, leaving the model with
	# completed_steps=0 even though the coordinator advanced the sequence.
	# That is the exact REQ-014 blocking-finding-A symptom (the model is
	# "complete=false" while the ship/route/inventory state already moved on).
	var pre_required_steps: int = 1
	if objective_progress_state != null:
		pre_required_steps = int(objective_progress_state.get_step_progress(sequence).get("required_steps", 1))
	_consume_junction_calibrator_if_eligible(sequence)
	var is_multi_step: bool = pre_required_steps > 1
	if is_multi_step:
		var step_changed: bool = objective_progress_state.complete_step(sequence, step_id)
		if not step_changed:
			return
		var progress: Dictionary = objective_progress_state.get_step_progress(sequence)
		if tracker != null:
			tracker.set_step_progress(sequence, progress)
		print("OBJECTIVE STEP COMPLETED sequence=%d step=%s progress=%d/%d" % [
			sequence,
			step_id,
			int(progress.get("completed_steps", 0)),
			int(progress.get("required_steps", 1)),
		])
		if not objective_progress_state.is_sequence_complete(sequence):
			return
		# Fall through to single-step completion path exactly once.

	objective_completion_count += 1
	# REQ-RL-003: objective achievements. Catalog uses trigger_target
	# "objectives[0]" for the first sequence and the objective_type string
	# for type-specific entries (e.g. restore_systems).
	if objective_completion_count == 1:
		_try_unlock_achievement("objective_completed", "objectives[0]")
	_try_unlock_achievement("objective_completed", objective_type)
	if objective_type == "stabilize_reactor":
		_try_unlock_achievement("reactor_stabilized", "reactor")
	if ship_systems_manager != null:
		completed_objective_types[objective_type] = true
		for pair in OBJECTIVE_REPAIR_MAP.get(objective_type, []):
			ship_systems_manager.force_repair(str(pair[0]), str(pair[1]))
		if player_progression != null and (objective_type == "restore_systems" or objective_type == "stabilize_reactor"):
			# Domain 6 (WI-5): single ingest path -- the bus is the sole grant
			# (repair_full_system = 120). The prior direct grant_xp (50) plus
			# the bus (120) double-granted 170 XP; removed.
			if training_event_bus != null:
				training_event_bus.emit("repair_full_system", str(sequence), player_progression)
		var compat: Dictionary = _manager_compat_summary()
		_apply_ship_systems_consequences(objective_type)
		_refresh_route_control_from_ship_systems()
		if oxygen_state != null:
			oxygen_state.apply_ship_systems_summary(compat)
			_refresh_oxygen_state(false, 0.0)
		var route_summary: Dictionary = get_route_control_summary()
		print("SHIP SYSTEM UPDATED sequence=%d type=%s power=%d reactor=%d extraction=%s route_opened=%d blockers=%d" % [
			sequence,
			objective_type,
			int(compat.get("power_percent", 0)),
			int(compat.get("reactor_stability_percent", 0)),
			str(bool(compat.get("extraction_unlocked", false))),
			int(route_summary.get("opened_gate_count", 0)),
			int(route_summary.get("active_blocker_count", 0)),
		])
	tracker.mark_completed(sequence)
	print("PLAYABLE INTERACTION interaction=%s objective=%s sequence=%d type=%s room=%s" % [interaction_id, objective_id, sequence, objective_type, room_id])
	emit_signal("playable_interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id)
	# A "sequence" is one logical objective; multi-step objectives contribute
	# one objective_completion_count increment (here) and N interactables
	# (one per step). Compare against the number of sequences, not the
	# number of interactables, so the slice is considered complete once
	# every distinct sequence has fired apply_objective() exactly once.
	var total_sequences: int = sequence_interactables.size()
	if objective_completion_count >= total_sequences:
		slice_complete = true
		current_objective_sequence = total_sequences + 1
		tracker.mark_run_complete()
		# REQ-RL-003: extracted achievement (run_complete / any).
		_try_unlock_achievement("run_complete", "complete")
		print("PLAYABLE SLICE COMPLETE objectives_completed=%d" % objective_completion_count)
		# REQ-PM-008 / ADR-0033 — apply the meta payout and persist
		# meta + unlock state before wiping the run snapshot.
		_apply_meta_payout_and_persist("completion")
		# REQ-012: drop the current-run save file so a stale snapshot
		# cannot be resumed into a finished run. A fresh run
		# automatically starts with no save file (delete returns true
		# when the file is already absent).
		if save_load_service != null:
			save_load_service.delete_current_run()
			# Also drop the rotating autosave_a/b/c slots written during this run.
			# delete_current_run() only clears the current_run/world rows; without
			# this, a completed run's timed-autosave snapshots survive into the next
			# run and show up in SaveLoadMenu.list_slots() as resumable rows —
			# defeating the REQ-012 stale-resume guard above (Codex review on PR #35).
			for slot_id in SaveSlotStateScript.AUTOSAVE_SLOT_IDS:
				save_load_service.delete_slot(slot_id)
		var objective_completion_summary: Dictionary = get_slice_completion_summary()
		objective_completion_summary["reason"] = "complete"
		emit_signal("playable_slice_completed", objective_completion_summary)
		return
	# REQ-012: auto-save at every stable objective-completion boundary.
	# Multi-step objectives only fire this once (after the final step
	# completes), which matches the auto-save contract.
	# Order matters: advance the live sequence FIRST so the snapshot
	# captures the resumed sequence the player is about to be working
	# on (after objective 1 -> 2). Saving before the increment would
	# persist the just-completed sequence and a load would put the
	# player back on the same objective they just finished.
	current_objective_sequence += 1
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx(AudioEventSeamScript.UI_OBJECTIVE_ADVANCE)
	_auto_save_current_run()
	# NOTE: we deliberately do NOT force a rotating autosave here. The checkpoint
	# is already persisted to current_run.json above (the REQ-012 resume point), and
	# the timed/event cadence captures rotating autosave_a/b/c snapshots on its own.
	# Forcing a second synchronous disk write on the same objective-completion frame
	# was redundant and risked a save-stutter (Gemini review on PR #35).
	_activate_current_objective()

func _apply_ship_systems_consequences(objective_type: String) -> void:
	if objective_type == "restore_systems":
		_clear_blocked_affordances()

func _clear_blocked_affordances() -> void:
	if affordance_root == null:
		return
	for child in affordance_root.get_children():
		if String(child.name).begins_with("BlockedAffordance_"):
			child.visible = false
			child.set_meta("system_cleared", true)

func get_blocked_affordance_visible_count() -> int:
	if affordance_root == null:
		return 0
	var count: int = 0
	for child in affordance_root.get_children():
		if String(child.name).begins_with("BlockedAffordance_") and child.visible:
			count += 1
	return count

func _refresh_route_control_from_ship_systems() -> void:
	if route_control_state == null or ship_systems_manager == null:
		_refresh_tracker_system_status_lines()
		return
	route_control_state.apply_ship_systems_summary(_manager_compat_summary())
	_apply_route_gate_scene_state()
	_refresh_tracker_system_status_lines()

func _apply_route_gate_scene_state() -> void:
	if route_control_state == null:
		return
	for gate_variant in route_gate_nodes:
		if not (gate_variant is Node):
			continue
		var gate: Node = gate_variant as Node
		var gate_id: String = str(gate.get_meta("route_gate_id", ""))
		var is_open: bool = route_control_state.is_gate_open(gate_id)
		gate.set_meta("route_gate_open", is_open)
		gate.set_meta("system_cleared", is_open)
		gate.visible = true
		_set_route_gate_collision_enabled(gate, not is_open)
		_update_route_gate_visual(gate, is_open)

func _set_route_gate_collision_enabled(gate: Node, enabled: bool) -> void:
	for child in gate.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_route_gate_visual(gate: Node, is_open: bool) -> void:
	for child in gate.get_children():
		if child is MeshInstance3D and child.name == "RouteGateVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_route_gate_material(is_open)
			visual.visible = not is_open

func _refresh_tracker_system_status_lines() -> void:
	if tracker == null:
		return
	tracker.set_system_status_lines(_combined_system_status_lines())

func _combined_system_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if ship_systems_manager != null:
		var compat: Dictionary = _manager_compat_summary()
		lines.append("Power: %d%%" % int(compat.get("power_percent", 0)))
		lines.append("Reactor: %d%%" % int(compat.get("reactor_stability_percent", 0)))
		lines.append("Supplies: %s" % ("OK" if bool(compat.get("emergency_supplies_recovered", false)) else "LOW"))
		lines.append("Main Power: %s" % ("ON" if bool(compat.get("main_power_restored", false)) else "OFF"))
		lines.append("Logs: %s" % ("DOWNLOADED" if bool(compat.get("navigation_logs_downloaded", false)) else "PENDING"))
		lines.append("Reactor: %s" % ("STABLE" if bool(compat.get("reactor_stabilized", false)) else "UNSTABLE"))
	if route_control_state != null:
		for line in route_control_state.get_status_lines():
			lines.append(String(line))
	# ADR-0027: player oxygen + breach now live solely in the bottom-left
	# PlayerVitalsPanel; the tracker no longer mirrors oxygen_state lines.
	# REQ-007: still surface carried tools/items, but the inventory weight
	# readout is owned by the vitals panel's Load line, so drop the weight= line.
	if inventory_state != null:
		for line in inventory_state.get_status_lines():
			var inv_text: String = String(line)
			if inv_text.begins_with("weight="):
				continue
			lines.append(inv_text)
	if not _last_loot_feedback_line.is_empty():
		lines.append(_last_loot_feedback_line)
	if not _last_caption_line.is_empty():
		lines.append("Caption: %s" % _last_caption_line)
	if unique_item_state != null:
		for line in unique_item_state.get_status_lines():
			lines.append(String(line))
	if power_grid_state != null:
		for line in power_grid_state.get_status_lines():
			lines.append(String(line))
	if life_support_expanded_state != null:
		for line in life_support_expanded_state.get_status_lines():
			lines.append(String(line))
	var hull = _active_hull()
	if hull != null:
		for line in hull.get_status_lines():
			lines.append(String(line))
	var active_fire_state = _active_fire_state()
	if active_fire_state != null:
		for line in active_fire_state.get_status_lines():
			lines.append(String(line))
	if propulsion_expanded_state != null:
		for line in propulsion_expanded_state.get_status_lines():
			lines.append(String(line))
	if sustenance_state != null:
		for line in sustenance_state.get_status_lines():
			lines.append(String(line))
	if player_progression != null:
		lines.append("Repair Skill: %d" % player_progression.get_skill_level("repair"))
	# ADR-0042 Task 5: merge false-HUD hallucination readouts (phantom blips / wrong
	# bearings) so the tracker shows lies when sanity is low. These are derived from the
	# director's hud events and clear automatically when sanity recovers.
	if hallucination_manager != null and is_instance_valid(hallucination_manager):
		for line in hallucination_manager.get_hallucinated_status_lines():
			lines.append(String(line))
	return lines

func get_combined_system_status_lines() -> PackedStringArray:
	return _combined_system_status_lines()

func _sub_health(system_id: String, sub_id: String) -> float:
	if ship_systems_manager == null:
		return 0.0
	var system = ship_systems_manager.get_system(system_id)
	if system == null:
		return 0.0
	var sub = system.get_subcomponent(sub_id)
	return sub.health if sub != null else 0.0

func _sub_functional(system_id: String, sub_id: String) -> bool:
	if ship_systems_manager == null:
		return false
	var system = ship_systems_manager.get_system(system_id)
	if system == null:
		return false
	var sub = system.get_subcomponent(sub_id)
	return sub != null and sub.is_functional()

## Flag-shaped summary derived from manager subcomponent state + the narrative
## record. Feeds the unchanged route_control_state / breach oxygen_state models
## and the HUD (ShipSystemsManager is the sole source of truth for ship-system state).
func _manager_compat_summary() -> Dictionary:
	var power_restored: bool = _sub_functional("power", "power_distribution") and _sub_functional("power", "battery_cells")
	var reactor_full: bool = _sub_health("power", "reactor_core") >= 1.0
	var power_health: float = 0.0
	if ship_systems_manager != null and ship_systems_manager.get_system("power") != null:
		power_health = ship_systems_manager.get_system("power").health()
	return {
		"emergency_supplies_recovered": completed_objective_types.has("recover_supplies"),
		"main_power_restored": power_restored,
		"navigation_logs_downloaded": completed_objective_types.has("download_logs"),
		"reactor_stabilized": reactor_full,
		"blocked_routes_cleared": power_restored,
		"extraction_unlocked": reactor_full,
		"power_percent": int(round(power_health * 100.0)),
		"reactor_stability_percent": int(round(_sub_health("power", "reactor_core") * 100.0)),
	}

func get_ship_systems_summary() -> Dictionary:
	var summary: Dictionary = {}
	if ship_systems_manager == null:
		summary["main_power_restored"] = false
		summary["extraction_unlocked"] = false
		summary["power_percent"] = 0
		summary["reactor_stability_percent"] = 0
		summary["blocked_affordance_visible_count"] = 0
		return summary
	summary = _manager_compat_summary()
	summary["blocked_affordance_visible_count"] = get_blocked_affordance_visible_count()
	for key in _expanded_ship_systems_summary().keys():
		summary[key] = _expanded_ship_systems_summary()[key]
	return summary

func get_route_control_summary() -> Dictionary:
	var summary: Dictionary = {}
	if route_control_state == null:
		summary["route_gate_count"] = 0
		summary["active_blocker_count"] = 0
		summary["opened_gate_count"] = 0
		summary["powered_gates_open"] = false
		summary["extraction_unlocked"] = false
		summary["gate_ids"] = []
		summary["route_gate_collision_enabled_count"] = 0
		return summary
	summary = route_control_state.get_summary()
	summary["route_gate_collision_enabled_count"] = get_route_gate_collision_enabled_count()
	return summary

func get_route_gate_nodes() -> Array:
	return route_gate_nodes.duplicate()

func get_route_gate_collision_enabled_count() -> int:
	var count: int = 0
	for gate_variant in route_gate_nodes:
		if not (gate_variant is Node):
			continue
		var gate: Node = gate_variant as Node
		for child in gate.get_children():
			if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
				count += 1
	return count

# --- Hazard / OxygenState integration -----------------------------------------
# Per-frame oxygen ticks are wired here so the Gate 1 hazard pressure loop
# is a real runtime system (see docs/game/features/hazards.md lines 24, 39,
# 52, 74, 83-88 and REQ-006). The tick reads the actual player position
# (via is_player_in_breach_zone) and delegates drain/regen to OxygenState.
# It runs while the playable slice is alive (started but not yet complete)
# and is intentionally a no-op before ship load completes.

func _process(delta: float) -> void:
	world_time += delta  # Live Persistent Ships Phase 1: advance before any branch/return
	if playable_started and not slice_complete:
		run_play_time_seconds += delta  # ADR-0046: before the branch split, so home AND away count
	if away_from_start:
		# Tranche 1 (audit): mirror the home branch's post-death guard — death
		# away (end_run sets slice_complete) must stop the sim exactly like
		# death at home; previously every system kept ticking on a corpse.
		if not playable_started or slice_complete:
			return
		# Keep the vitals panel live on a boarded derelict: Heavy-Load, repair
		# progress, and the repair_blocked message + its countdown still apply
		# away from home. Personal O2 also ticks here (field_atmosphere) so
		# suit pressure drains on the derelict — life-support atmosphere bite
		# is hub-only by design; personal oxygen owns the field.
		_refresh_oxygen_state(false, delta)
		_tick_threat_runtime(delta)
		# ADR-0042 (Codex PR #44): the derelict field run is the PRIMARY low-sanity context,
		# but this branch returns before the home-path sanity/hallucination tick. Drive it here
		# too: away is never a safe zone, so sanity drains, the director advances, phantoms /
		# false-HUD / FX render, and the tier-3 health teeth feed into _tick_survival_attrition
		# below (Domain 1 Task 6: shared helper now covers the full vitals + death cascade).
		if sanity_state != null:
			sanity_state.in_safe_zone = false
			sanity_state.steady_multiplier = 0.5 if (status_effects_state != null and status_effects_state.has_effect("utility_flare")) else 1.0
			sanity_state.tick(delta)
			if hallucination_director != null:
				hallucination_director.tick(delta, {
					"sanity": sanity_state.sanity,
					"in_safe_zone": false,
					"anchor_positions": _distributed_room_positions(),
				})
				if hallucination_manager != null and is_instance_valid(hallucination_manager):
					var ppos_away: Vector3 = (player as Node3D).global_position if player != null and player is Node3D else Vector3.ZERO
					hallucination_manager.render(delta, ppos_away)
		# Derelict-side fire (wire BOTH branches): tick the active (derelict) fire model so
		# it spreads, degrades derelict systems, and feeds the player-vitals teeth below.
		# Fire is ticked here via _tick_active_fire on BOTH branches (home and away).
		# Live Persistent Ships Phase 3: _advance_ship (hub + boarded derelict) +
		# _recompute_expanded_ship_systems run in the block below.
		_tick_active_fire(delta)
		# Domain 1: survival attrition + stakes on the derelict branch (shared
		# helper). Runs radiation/body-temp/status + the vitals cascade + death,
		# so the away path is no longer starved past the 4808 early-return.
		_tick_survival_attrition(delta)
		_refresh_player_vitals(delta)
		# Tranche 1 (audit): home gets per-frame tracker status lines through
		# _refresh_oxygen_state; the away branch skipped them, so Power/Reactor/
		# Threats lines froze for the whole boarding run.
		_refresh_tracker_system_status_lines()
		# ADR-0038 (superseded by Domain 4): field crafting completes away from home.
		# Powered-station crafting is NO LONGER paused away — the hub recompute runs on
		# both branches now (live sim), so powered stations stay live on a derelict too.
		if field_crafting_state != null and field_crafting_state.tick(delta):
			_on_field_craft_completed()
		# Timed autosave still advances on a derelict — a long boarding run is
		# exactly the data-loss case it protects (the checkpoint save also runs away).
		_tick_autosave_policy(delta)
		# REQ-AU-001 (Codex PR #43): refresh + tick audio on the derelict path too, else
		# COMBAT music / engagement flags go stale during actual away-from-start combat
		# (this branch returns before the home-path audio tick below).
		if is_instance_valid(audio_manager) and audio_manager.has_method("tick"):
			audio_manager.tick(delta)
			_refresh_audio_state(false, delta)
		# Live Persistent Ships Phase 3: _advance_ship ticks BOTH present ships on the
		# away branch — the hub (always co-present) and the boarded derelict (guarded so
		# the hub is never advanced twice if current_ship == home_ship). Fire stays on
		# _tick_active_fire above; _recompute_expanded_ship_systems follows for hub power.
		_advance_ship(home_ship, delta)
		if current_ship != null and current_ship != home_ship:
			_advance_ship(current_ship, delta)
		_recompute_expanded_ship_systems(delta)
		# Recharge port is power-gated on the DERELICT's own power system (engineering gate):
		# present but dead until the player restores derelict power. This MUST run AFTER
		# _recompute_expanded_ship_systems (which sets the port to hub power_grid state),
		# so the derelict-based gate takes final precedence on the away branch.
		if is_instance_valid(extinguisher_recharge_port):
			var _dmgr = _active_systems_manager()
			extinguisher_recharge_port.set_powered(_dmgr != null and _dmgr.is_operational("power"))
		# Domain 3 + Phase 3: food spoilage + production advance on the derelict branch too (see
		# _tick_food_runtime). Powered station crafting also advances on both branches
		# via _recompute_expanded_ship_systems called above (ADR-0038 superseded).
		_tick_food_runtime(delta)
		# Domain 5: tick the reload timer on the away branch (derelict = primary combat context).
		if ammo_state != null and not ammo_state.tick(delta).is_empty():
			_refresh_weapon_hotbar()
		# REQ-013 / Tranche 1 (audit): the electrical-arc hazard cycles on the
		# derelict too — this was the #42/#43/#44 regression class (system
		# ticked on the home branch only, dead in the primary field context).
		if electrical_arc_state != null:
			electrical_arc_state.tick(delta, {})
			_refresh_arc_state(false)
		# Domain 5: stimulant buff timers + addiction withdrawal/tolerance decay advance
		# on the derelict branch too (item USE already worked away; only per-frame decay
		# was home-only). Shared with the home block at the bottom of _process.
		if stimulant_state != null:
			stimulant_state.tick(delta, addiction_state, _consumable_pipeline_context())
		if addiction_state != null:
			addiction_state.tick(delta, status_effects_state)
		# Domain 10 (ADR-0045): proximity tooltip focus on the away branch too --
		# the derelict field run is the PRIMARY exploration context.
		_refresh_tooltip_focus()
		return
	if not playable_started or slice_complete:
		return
	if oxygen_state == null:
		return
	_tick_autosave_policy(delta)
	_tick_threat_runtime(delta)
	_advance_ship(home_ship, delta)
	_recompute_expanded_ship_systems(delta)
	_tick_active_fire(delta)
	if field_crafting_state != null and field_crafting_state.tick(delta):
		_on_field_craft_completed()
	_refresh_oxygen_state(false, delta)
	# M7-B Task 7: the authoritative fire model is ticked via _tick_active_fire(delta)
	# (called directly on BOTH branches, NOT inside _recompute_expanded_ship_systems).
	# Passable fire zones are refreshed when the burning set changes.
	# REQ-013: tick the electrical-arc model with the same per-frame
	# delta so its phase / passability advance in lock-step with fire.
	# electrical_arc_state.tick ignores the second arg (no per-frame
	# context is needed; oxygen is the only Alpha hazard that uses it).
	if electrical_arc_state != null:
		electrical_arc_state.tick(delta, {})
		_refresh_arc_state(false)
	if stimulant_state != null:
		stimulant_state.tick(delta, addiction_state, _consumable_pipeline_context())
	if addiction_state != null:
		addiction_state.tick(delta, status_effects_state)
	# Domain 5: tick the reload timer on the home branch too (symmetry with away branch).
	if ammo_state != null and not ammo_state.tick(delta).is_empty():
		_refresh_weapon_hotbar()
	# REQ-SV / Domain 1: survival attrition + stakes (shared by both branches).
	_tick_survival_attrition(delta)
	if sanity_state != null:
		# Synaptic Sea field = not in a safe zone (away_from_start or breach open)
		var in_safe: bool = not away_from_start and (oxygen_state == null or not oxygen_state.get_summary().get("breach_open", false))
		sanity_state.in_safe_zone = in_safe
		sanity_state.steady_multiplier = 0.5 if (status_effects_state != null and status_effects_state.has_effect("utility_flare")) else 1.0
		sanity_state.tick(delta)
		# ADR-0042: drive sanity hallucinations from the post-tick sanity value.
		if hallucination_director != null:
			var hctx := {
				"sanity": sanity_state.sanity,
				"in_safe_zone": in_safe,
				"anchor_positions": _distributed_room_positions(),
			}
			hallucination_director.tick(delta, hctx)
			if hallucination_manager != null and is_instance_valid(hallucination_manager):
				var ppos: Vector3 = (player as Node3D).global_position if player != null and player is Node3D else Vector3.ZERO
				hallucination_manager.render(delta, ppos)
	# ADR-0034 / Domain 3: tick food spoilage + production (shared by BOTH _process branches).
	_tick_food_runtime(delta)
	# REQ-AU-001..010: tick the audio manager. The manager advances the
	# ambient crossfade, music layer crossfade, sfx cooldowns + captions,
	# and the meta-event scheduler. Tick before any HUD caption drain so
	# the audio summary the HUD reads is at most one frame stale.
	if is_instance_valid(audio_manager) and audio_manager.has_method("tick"):
		audio_manager.tick(delta)
		_refresh_audio_state(false, delta)
	# Domain 10 (ADR-0045): proximity tooltip focus on the home branch too.
	_refresh_tooltip_focus()

## Domain 1 (survival_vitals): the single survival-attrition tick, called from
## BOTH _process branches so radiation / body-temperature / status / the vitals
## cascade — and the terminal stakes (movement gating + death) — are live on a
## boarded derelict (the PRIMARY context), not home-only. The away early-return
## at line 4808 previously starved this entire loop in the field.
##
## Order preserves the prior home semantics: the vitals context reads the
## CURRENT (pre-tick) source values, vitals ticks, then the environmental
## sources advance. The hallucination teeth are read with the same one-frame
## lag the home path already tolerated (the sanity block ticks the director
## separately on each branch).
func _tick_survival_attrition(delta: float) -> void:
	if vitals_state == null:
		return
	# Real environmental hazard signal (replaces the always-false away_from_start
	# literal at the old line 4886): you are in a thermal/radiation hazard zone on
	# a derelict OR when the hub hull is breached. Mirrors radiation's prior in_rad.
	var breach_open: bool = oxygen_state != null and oxygen_state.get_summary().get("breach_open", false)
	var in_hazard_env: bool = away_from_start or breach_open
	# Assemble the vitals context from current source state (pre-tick).
	var temp_mult: float = 1.0
	if body_temperature_state != null:
		temp_mult = body_temperature_state.get_thirst_multiplier()
	var rad_drain: float = 0.0
	if radiation_state != null:
		rad_drain = radiation_state.get_health_drain_per_second()
	var status_mult: float = 1.0
	if status_effects_state != null:
		status_mult = status_effects_state.get_modifier("stamina_recovery")
	# Hub ambient atmosphere bites only while ABOARD (away, the personal hazards own it).
	var atmo_drain: float = 0.0
	if life_support_expanded_state != null and not away_from_start:
		atmo_drain = life_support_expanded_state.get_health_drain_per_second()
		temp_mult *= life_support_expanded_state.get_thirst_multiplier()
	var hteeth: Dictionary = hallucination_director.get_direct_teeth() if hallucination_director != null else {"health_drain_per_second": 0.0, "stamina_recovery_mult": 1.0}
	var encumb_drain: float = 0.0
	if inventory_state != null:
		encumb_drain = EncumbranceScript.health_drain_per_second(inventory_state.get_load_ratio())
	vitals_state.tick(delta, {
		"temperature_thirst_mult": temp_mult,
		"radiation_health_drain": rad_drain,
		"atmosphere_health_drain": atmo_drain,
		"fire_health_drain": FIRE_HEALTH_DRAIN_PER_SECOND * _player_fire_intensity(),
		"status_stamina_recovery_mult": status_mult,
		"sanity_health_drain": float(hteeth["health_drain_per_second"]),
		"sanity_stamina_recovery_mult": float(hteeth["stamina_recovery_mult"]),
		"encumbrance_health_drain": encumb_drain,
		"moving": is_instance_valid(player) and player.has_method("is_moving") and player.is_moving(),
	})
	# Stakes: penalize movement from low vitals, then end the run on incapacitation.
	_apply_vitals_action_gating()
	_check_vitals_death()
	# Advance the environmental sources AFTER the vitals read (preserves prior order).
	if radiation_state != null:
		radiation_state.in_radiation_zone = in_hazard_env
		radiation_state.tick(delta)
	if body_temperature_state != null:
		body_temperature_state.in_extreme_zone = in_hazard_env
		body_temperature_state.tick(delta)
	if status_effects_state != null:
		status_effects_state.tick(delta)

## Domain 1: push the vitals movement gate onto the player every frame.
func _apply_vitals_action_gating() -> void:
	if not is_instance_valid(player) or vitals_state == null:
		return
	if not player.has_method("set_movement_speed_multiplier"):
		return
	player.set_movement_speed_multiplier(vitals_state.get_movement_speed_multiplier())

## Domain 3: advance food spoilage and in-progress production. Called from BOTH _process
## branches. DELIBERATE divergence from crafting (powered crafting stations PAUSE while away):
## growth/recycling are time-based biological/chemical processes that do not require the
## player aboard, so a crop planted before boarding keeps growing on the derelict run and is
## HARVESTABLE on return. Spoilage is likewise time-based and must not freeze on a derelict.
func _tick_food_runtime(delta: float) -> void:
	if spoilage_state != null:
		spoilage_state.tick(delta)
	if hydroponics_state != null and hydroponics_state.state == HydroponicsStateScript.State.PLANTED:
		hydroponics_state.tick(delta)
	if water_recycler_state != null and water_recycler_state.state == WaterRecyclerStateScript.State.RECYCLING:
		water_recycler_state.tick(delta)

## Domain 1: terminal stake. When the player is incapacitated (health<=0) end the
## run as a death. end_run is idempotent (guards slice_complete), so this is safe
## to call every frame and from both branches.
func _check_vitals_death() -> void:
	if vitals_state == null or slice_complete:
		return
	if vitals_state.is_incapacitated():
		end_run("death")

func _build_breach_zone() -> void:
	if oxygen_root == null:
		return
	for child in oxygen_root.get_children():
		oxygen_root.remove_child(child)
		child.queue_free()
	breach_zone_node = null
	unsafe_room_marker = null
	var world_position: Vector3 = _resolve_breach_zone_world_position()
	if oxygen_state == null:
		oxygen_state = OxygenStateScript.new()
	# Per ADR-0005 HazardStateContract: configure() takes a Dictionary so
	# each hazard model unpacks the fields it cares about. OxygenState
	# reads max_oxygen / drain_rate / regen_rate / recovery_threshold /
	# safe_threshold plus the zone_ids array.
	oxygen_state.configure({
		"zone_ids": [BREACH_ZONE_FALLBACK_ID],
		"max_oxygen": OxygenStateScript.DEFAULT_MAX_OXYGEN,
		"drain_rate": OxygenStateScript.DEFAULT_DRAIN_RATE,
		"regen_rate": OxygenStateScript.DEFAULT_REGEN_RATE,
		"recovery_threshold": OxygenStateScript.DEFAULT_RECOVERY_THRESHOLD,
		"safe_threshold": OxygenStateScript.DEFAULT_SAFE_THRESHOLD,
	})
	breach_zone_node = _create_breach_zone_node(world_position)
	oxygen_root.add_child(breach_zone_node)
	unsafe_room_marker = _create_unsafe_room_marker(world_position)
	oxygen_root.add_child(unsafe_room_marker)

func _resolve_breach_zone_world_position() -> Vector3:
	if loader != null and loader.has_method("get_breach_zone_markers"):
		var markers: Array = loader.get_breach_zone_markers()
		if markers.size() > 0 and markers[0] is Vector3:
			var candidate: Vector3 = markers[0]
			if candidate != Vector3.INF:
				return candidate
	# Fallback: midpoint between objective-3 and objective-4 interactable positions.
	var obj3_pos: Vector3 = Vector3.INF
	var obj4_pos: Vector3 = Vector3.INF
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if not (interactable is Node3D):
			continue
		var seq: int = int(interactable.get("sequence"))
		if seq == 3:
			obj3_pos = (interactable as Node3D).global_position
		elif seq == 4:
			obj4_pos = (interactable as Node3D).global_position
	if obj3_pos == Vector3.INF or obj4_pos == Vector3.INF:
		# Last-ditch: fall back to player spawn + 6m forward.
		if player != null:
			return player.global_position + Vector3(0.0, 0.0, 6.0)
		return Vector3.ZERO
	return (obj3_pos + obj4_pos) * 0.5

func _create_breach_zone_node(world_position: Vector3) -> StaticBody3D:
	var zone: StaticBody3D = StaticBody3D.new()
	zone.name = "BreachZone_OxygenCorridor"
	zone.position = world_position
	zone.collision_layer = 1
	zone.collision_mask = 1
	zone.set_meta("breach_zone_id", BREACH_ZONE_FALLBACK_ID)
	zone.set_meta("breach_zone_kind", "oxygen_breach")
	zone.set_meta("breach_zone_open", true)
	zone.set_meta("breach_zone_sealed", false)
	zone.set_meta("breach_zone_passability_blocked", false)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "BreachZoneCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = BREACH_ZONE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, BREACH_ZONE_COLLISION_SIZE.y * 0.5, 0.0)
	zone.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "BreachZoneVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = BREACH_ZONE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_breach_zone_material(true, false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.add_child(visual)
	return zone

func _make_breach_zone_material(is_open: bool, is_blocked: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	if is_blocked:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_BLOCKED
	elif is_open:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_OPEN
	else:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_SEALED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _create_unsafe_room_marker(world_position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "BreachUnsafeMarker"
	label.text = BREACH_ZONE_UNSAFE_LABEL_TEXT
	label.position = world_position + Vector3(0.0, BREACH_ZONE_COLLISION_SIZE.y + 0.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	# A11Y-P1-001: world label pixel_size flows through the single
	# accessibility_settings seam. Default scale=1.0 keeps the prior
	# 0.0035 value exactly; larger scales divide the pixel_size so the
	# label renders larger on screen for the same world position.
	label.pixel_size = accessibility_settings.scaled_world_pixel_size(0.0035)
	label.modulate = Color(1.0, 0.32, 0.22, 1.0)
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	label.visible = false
	return label

func _refresh_oxygen_state(force_initial: bool, delta_seconds: float) -> void:
	if oxygen_state == null:
		_refresh_tracker_system_status_lines()
		return
	# REQ-007: keep OxygenState's view of the inventory in sync with the
	# coordinator's InventoryState BEFORE the per-frame tick so the drain
	# multiplier reflects any tools acquired this frame.
	if inventory_state != null:
		oxygen_state.apply_inventory_summary(inventory_state.get_summary())
	if equipment_state != null:
		oxygen_state.apply_equipment_summary(
			{"drain_multiplier": equipment_state.get_oxygen_drain_multiplier()})
	if force_initial:
		oxygen_state.apply_ship_systems_summary({})  # no-op; recompute passability
		_apply_breach_zone_scene_state()
		_refresh_tracker_system_status_lines()
		_refresh_player_vitals(delta_seconds)
		return
	# Per-tick path: home uses the spatial breach-zone gate; derelict/field
	# uses continuous suit-pressure drain (field_atmosphere) so personal O2
	# advances on the primary gameplay context (both-branch rule).
	if away_from_start:
		oxygen_state.tick(delta_seconds, {
			"field_atmosphere": true,
			"player_in_breach_zone": false,
		})
	else:
		oxygen_state.tick(delta_seconds, {
			"player_in_breach_zone": is_player_in_breach_zone(),
			"field_atmosphere": false,
		})
	_apply_breach_zone_scene_state()
	_refresh_tracker_system_status_lines()
	_refresh_player_vitals(delta_seconds)

func _refresh_player_vitals(delta_seconds: float) -> void:
	# A freed Node stays non-null in Godot, so guard the panel with
	# is_instance_valid (a hud_layer teardown on reload frees it).
	if vitals_model == null or not is_instance_valid(vitals_panel):
		return
	if oxygen_state != null:
		vitals_model.apply_oxygen_summary(oxygen_state.get_summary())
	if inventory_state != null:
		var ratio: float = inventory_state.get_load_ratio()
		vitals_model.apply_inventory_load(ratio, EncumbranceScript.move_speed_multiplier(ratio), inventory_state.weight_reduction)
	var channeling: bool = false
	var progress: float = 0.0
	for rp in repair_points:
		if is_instance_valid(rp) and rp.channeling:
			channeling = true
			progress = rp.progress
			break
	vitals_model.set_repair_progress(channeling, progress)
	# REQ-SV: feed survival vitals into the HUD model.
	if vitals_state != null:
		vitals_model.apply_vitals_summary(vitals_state.get_summary())
	if sanity_state != null:
		vitals_model.apply_sanity_summary(sanity_state.get_summary())
	if radiation_state != null:
		vitals_model.apply_radiation_summary(radiation_state.get_summary())
	if body_temperature_state != null:
		vitals_model.apply_temperature_summary(body_temperature_state.get_summary())
	if status_effects_state != null:
		vitals_model.apply_status_effects_summary(status_effects_state.get_summary())
	vitals_model.tick(delta_seconds)
	vitals_panel.set_status_lines(vitals_model.get_status_lines())

func get_player_vitals_lines() -> PackedStringArray:
	if vitals_model == null:
		return PackedStringArray()
	return vitals_model.get_status_lines()

func _apply_breach_zone_scene_state() -> void:
	if oxygen_state == null or breach_zone_node == null:
		return
	var summary: Dictionary = oxygen_state.get_summary()
	var breach_open: bool = bool(summary.get("breach_open", false))
	var breach_sealed: bool = bool(summary.get("breach_sealed", false))
	var passability_blocked: bool = bool(summary.get("passability_blocked", false))
	breach_zone_node.set_meta("breach_zone_open", breach_open)
	breach_zone_node.set_meta("breach_zone_sealed", breach_sealed)
	breach_zone_node.set_meta("breach_zone_passability_blocked", passability_blocked)
	# Per the feature spec: the breach zone is passable while the player has
	# oxygen above the recovery threshold; once oxygen hits zero, the
	# collision is enabled to block forward traversal until oxygen recovers.
	# Once sealed (objective 2), the corridor is safe and collision is off.
	var collision_enabled: bool = breach_open and passability_blocked
	_set_breach_zone_collision_enabled(breach_zone_node, collision_enabled)
	_update_breach_zone_visual(breach_zone_node, breach_open, passability_blocked)
	if unsafe_room_marker != null:
		unsafe_room_marker.visible = breach_open and not breach_sealed

func _set_breach_zone_collision_enabled(zone: Node, enabled: bool) -> void:
	for child in zone.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_breach_zone_visual(zone: Node, is_open: bool, is_blocked: bool) -> void:
	for child in zone.get_children():
		if child is MeshInstance3D and child.name == "BreachZoneVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_breach_zone_material(is_open, is_blocked)
			visual.visible = is_open

func get_oxygen_summary() -> Dictionary:
	var summary: Dictionary = {}
	if oxygen_state == null:
		summary["oxygen"] = 0.0
		summary["max_oxygen"] = 0.0
		summary["drain_rate"] = 0.0
		summary["regen_rate"] = 0.0
		summary["recovery_threshold"] = 0.0
		summary["safe_threshold"] = 0.0
		summary["breach_open"] = false
		summary["breach_sealed"] = false
		summary["passability_blocked"] = false
		summary["player_in_breach_zone"] = false
		summary["breach_zone_ids"] = []
		return summary
	summary = oxygen_state.get_summary()
	return summary

func get_breach_zone_node() -> Node:
	return breach_zone_node

func get_breach_zone_collision_enabled_count() -> int:
	if breach_zone_node == null:
		return 0
	for child in breach_zone_node.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return 1
	return 0

func is_player_in_breach_zone() -> bool:
	if breach_zone_node == null or player == null:
		return false
	if not (player is Node3D):
		return false
	var zone_pos: Vector3 = breach_zone_node.global_position
	var player_pos: Vector3 = (player as Node3D).global_position
	var dx: float = player_pos.x - zone_pos.x
	var dz: float = player_pos.z - zone_pos.z
	# Use a horizontal proximity radius (the corridor is wider than tall; using
	# 3D distance would falsely report "in zone" when the player is one floor up).
	return (dx * dx + dz * dz) <= (BREACH_ZONE_PROXIMITY_RADIUS * BREACH_ZONE_PROXIMITY_RADIUS)

func _activate_current_objective() -> void:
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if interactable.has_method("set_active"):
			interactable.set_active(int(interactable.get("sequence")) == current_objective_sequence)
	if tracker != null:
		tracker.set_current_sequence(current_objective_sequence)
		var progress: Dictionary = {}
		if objective_progress_state != null:
			progress = objective_progress_state.get_step_progress(current_objective_sequence)
		tracker.set_step_progress(current_objective_sequence, progress)
		var current = get_interactable_by_sequence(current_objective_sequence)
		if current != null:
			tracker.set_interaction_prompt(str(current.get("prompt_text")))

func _ensure_key_action_set(action_name: String, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var existing_keycodes: Dictionary = {}
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event: InputEventKey = event
			existing_keycodes[int(key_event.keycode)] = true
	for keycode_variant in keycodes:
		var keycode: int = int(keycode_variant)
		if existing_keycodes.has(keycode):
			continue
		var input_event: InputEventKey = InputEventKey.new()
		input_event.keycode = keycode
		InputMap.action_add_event(action_name, input_event)
		existing_keycodes[keycode] = true

# Returns the keycodes currently registered on an action, in InputMap
# registration order. Used by validation to assert the alternate-binding
# surface (A11Y-P1-002) without leaking any new public state onto the
# playable coordinator. Returns an empty array if the action does not
# exist or has no InputEventKey bindings.
func get_input_action_keycodes_for_validation(action_name: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action_name):
		return out
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event: InputEventKey = event
			out.append(int(key_event.keycode))
	return out

func get_menu_coordinator_for_validation():
	return menu_coordinator

func dismiss_latest_tutorial_for_validation() -> bool:
	if not is_instance_valid(menu_coordinator):
		return false
	return menu_coordinator.dismiss_latest_tutorial()

## Applies a settings summary to the live session's MenuCoordinator (title-screen
## dirty-flag handoff and validation seam both delegate here).
func apply_ui_settings_summary(summary: Dictionary) -> bool:
	if not is_instance_valid(menu_coordinator):
		return false
	return menu_coordinator.apply_settings_summary(summary)

## ADR-0043 title handoff seam: dismisses the in-scene boot-time main_menu
## _build_runtime_nodes() parks open via menu_coordinator.open_main_menu().
## The title screen already collected New Game / Continue intent before
## instantiating this scene, so the child's own main_menu overlay is
## redundant and must not survive the handoff (it would otherwise keep
## capturing input via menu_coordinator.handle_ui_input, parking the
## player on a second menu instead of gameplay).
func dismiss_boot_menu() -> bool:
	if not is_instance_valid(menu_coordinator):
		return false
	return menu_coordinator.dismiss_boot_menu()

## Validation-only alias kept for existing smokes; delegates to the production seam.
func apply_ui_settings_summary_for_validation(summary: Dictionary) -> bool:
	return apply_ui_settings_summary(summary)

# --- Hazard / ElectricalArcState integration ----------------------------------
# REQ-013: electrical-arc zone scene integration. The third hazard's pure model
# (ElectricalArcState) ticks from _process and toggles a localized
# StaticBody3D / CollisionShape3D collision segment and a Label3D.
# Placement is template-specific (no fallback room id is injected), so
# when the loader reports an empty `arc_zone_specs` the scene simply
# skips arc setup and _refresh_arc_state becomes a no-op.

func _build_arc_zone() -> void:
	if arc_root == null:
		return
	for child in arc_root.get_children():
		arc_root.remove_child(child)
		child.queue_free()
	# Derelict arc nodes parent under the derelict's scene_root (freed with it
	# on departure), so also clear by handle in case the previous zone lives
	# outside arc_root.
	for stale in [arc_zone_node, arc_zone_label]:
		if stale != null and is_instance_valid(stale):
			if stale.get_parent() != null:
				stale.get_parent().remove_child(stale)
			stale.queue_free()
	arc_zone_node = null
	arc_zone_label = null
	arc_zone_resolved_room_id = ""
	# Per ADR-0005: configure() is called even when no markers exist so
	# the model state is always coherent (DISCHARGED, time_in_state == 0.0,
	# passability_blocked == false). This is the FRESH state the smoke
	# asserts on the very first frame after ship load.
	if electrical_arc_state == null:
		electrical_arc_state = ElectricalArcStateScript.new()
	electrical_arc_state.configure({
		"zone_ids": [],
		"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
		"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
	})
	var resolution: Dictionary = _resolve_arc_zone_world_position()
	var world_position: Vector3 = resolution.get("position", Vector3.INF)
	arc_zone_resolved_room_id = str(resolution.get("room_id", ""))
	# No marker and no fallback -> skip arc setup. Refresh later will
	# stay a no-op because arc_zone_node / arc_zone_label are null.
	if world_position == Vector3.INF:
		return
	var zone_id: String = str(resolution.get("zone_id", ARC_ZONE_FALLBACK_ID))
	if zone_id.is_empty():
		zone_id = ARC_ZONE_FALLBACK_ID
	electrical_arc_state.configure({
		"zone_ids": [zone_id],
		"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
		"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
	})
	arc_zone_node = _create_arc_zone_node(zone_id, world_position)
	arc_zone_label = _create_arc_zone_label(world_position)
	# Away: parent under the derelict's scene_root so the zone inherits the
	# dock offset and is freed with the derelict (loot-container pattern).
	# Home: keep the original arc_root parent.
	if away_from_start and current_ship != null and is_instance_valid(current_ship.scene_root):
		current_ship.scene_root.add_child(arc_zone_node)
		current_ship.scene_root.add_child(arc_zone_label)
	else:
		arc_root.add_child(arc_zone_node)
		arc_root.add_child(arc_zone_label)

# The loader whose arc markers drive the CURRENT context: the boarded
# derelict's own loader root when away (Tranche 1 audit fix — derelict arc
# zones were dead data before), the home loader otherwise. Mirrors the
# active_loader selection in _build_loot_containers.
func _active_arc_loader() -> Node:
	if away_from_start and current_ship != null and is_instance_valid(current_ship.scene_root) \
			and current_ship.scene_root.has_method("get_arc_zone_markers"):
		return current_ship.scene_root
	return loader if (loader is Node and is_instance_valid(loader)) else null

func _resolve_arc_zone_world_position() -> Dictionary:
	var arc_loader: Node = _active_arc_loader()
	if arc_loader != null and arc_loader.has_method("get_arc_zone_markers"):
		var markers: Array = arc_loader.call("get_arc_zone_markers")
		if markers.size() > 0 and markers[0] is Vector3:
			var candidate: Vector3 = markers[0]
			if candidate != Vector3.INF:
				return {
					"position": candidate,
					"room_id": _resolved_arc_marker_room_id(),
					"zone_id": _resolved_arc_marker_zone_id(),
				}
	# No fallback room is injected per hazard_type_3.md (placement is
	# template-specific). An empty arc_zones array means the template
	# does not include this hazard; skip arc setup cleanly.
	return {"position": Vector3.INF, "room_id": "", "zone_id": ""}

# Returns the `to_room` of the first arc_zones marker the loader exposes,
# or "" if no marker is present. Mirrors _resolved_marker_room_id() for
# fire zones so the validation smoke can confirm marker-to-resolved-room
# agreement without re-walking the loader's internal arrays.
func _resolved_arc_marker_room_id() -> String:
	var loader_node: Node = _active_arc_loader()
	if loader_node == null:
		return ""
	if not loader_node.has_method("get_arc_zone_specs"):
		return ""
	var specs_variant: Variant = loader_node.call("get_arc_zone_specs")
	if typeof(specs_variant) != TYPE_ARRAY:
		return ""
	for spec_variant in (specs_variant as Array):
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var to_room: String = str((spec_variant as Dictionary).get("to_room", ""))
		if not to_room.is_empty():
			return to_room
	return ""

func _resolved_arc_marker_zone_id() -> String:
	var loader_node: Node = _active_arc_loader()
	if loader_node == null:
		return ""
	if not loader_node.has_method("get_arc_zone_specs"):
		return ""
	var specs_variant: Variant = loader_node.call("get_arc_zone_specs")
	if typeof(specs_variant) != TYPE_ARRAY:
		return ""
	for spec_variant in (specs_variant as Array):
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var zone_id: String = str((spec_variant as Dictionary).get("id", ""))
		if not zone_id.is_empty():
			return zone_id
	return ""

func _create_arc_zone_node(zone_id: String, world_position: Vector3) -> StaticBody3D:
	var zone: StaticBody3D = StaticBody3D.new()
	zone.name = "ElectricalArcZone_NonCriticalLink"
	zone.position = world_position
	zone.collision_layer = 1
	zone.collision_mask = 1
	zone.set_meta("arc_zone_id", zone_id)
	zone.set_meta("arc_zone_kind", "electrical_arc")
	zone.set_meta("arc_zone_phase", "DISCHARGED")
	zone.set_meta("arc_zone_passability_blocked", false)
	zone.set_meta("arc_zone_resolved_room_id", arc_zone_resolved_room_id)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "ArcZoneCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = ARC_ZONE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, ARC_ZONE_COLLISION_SIZE.y * 0.5, 0.0)
	# The arc zone starts DISCHARGED -> passable. Collision is enabled
	# by _apply_arc_zone_scene_state when the model flips to ARCING.
	collision_shape.disabled = true
	zone.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "ArcZoneVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = ARC_ZONE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_arc_zone_material(false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.add_child(visual)
	return zone

func _make_arc_zone_material(is_arcing: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = ARC_ZONE_VISUAL_COLOR_ARCING if is_arcing else ARC_ZONE_VISUAL_COLOR_DISCHARGED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _create_arc_zone_label(world_position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "ArcZoneLabel"
	label.text = ARC_ZONE_LABEL_TEXT_DISCHARGED
	label.position = world_position + Vector3(0.0, ARC_ZONE_COLLISION_SIZE.y + 0.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	# A11Y-P1-001: world label pixel_size flows through the single
	# accessibility_settings seam. Default scale=1.0 keeps the prior
	# 0.0035 value exactly; larger scales divide the pixel_size so the
	# label renders larger on screen for the same world position.
	label.pixel_size = accessibility_settings.scaled_world_pixel_size(0.0035)
	label.modulate = ARC_ZONE_VISUAL_COLOR_DISCHARGED
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	return label

func _refresh_arc_state(force_initial: bool) -> void:
	if electrical_arc_state == null:
		return
	# When no arc zone was built (template has no arc marker), keep the
	# model in DISCHARGED so its summary remains coherent for save/load
	# but skip scene-state application entirely.
	if arc_zone_node == null:
		return
	_apply_arc_zone_scene_state()

func _apply_arc_zone_scene_state() -> void:
	if electrical_arc_state == null or arc_zone_node == null:
		return
	var summary: Dictionary = electrical_arc_state.get_summary()
	var arcing: bool = bool(summary.get("arcing", false))
	var state_text: String = str(summary.get("state", "DISCHARGED"))
	arc_zone_node.set_meta("arc_zone_phase", state_text)
	arc_zone_node.set_meta("arc_zone_passability_blocked", arcing)
	_set_arc_zone_collision_enabled(arc_zone_node, arcing)
	_update_arc_zone_visual(arc_zone_node, arcing)
	if arc_zone_label != null:
		arc_zone_label.text = ARC_ZONE_LABEL_TEXT_ARCING if arcing else ARC_ZONE_LABEL_TEXT_DISCHARGED
		arc_zone_label.modulate = ARC_ZONE_VISUAL_COLOR_ARCING if arcing else ARC_ZONE_VISUAL_COLOR_DISCHARGED

func _set_arc_zone_collision_enabled(zone: Node, enabled: bool) -> void:
	for child in zone.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_arc_zone_visual(zone: Node, is_arcing: bool) -> void:
	for child in zone.get_children():
		if child is MeshInstance3D and child.name == "ArcZoneVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_arc_zone_material(is_arcing)

func get_arc_summary() -> Dictionary:
	var summary: Dictionary = {}
	if electrical_arc_state == null:
		summary["hazard_kind"] = "electrical_arc"
		summary["state"] = "DISCHARGED"
		summary["phase"] = 0
		summary["time_in_state"] = 0.0
		summary["cycle_duration"] = 0.0
		summary["arcing"] = false
		summary["passability_blocked"] = false
		summary["arcing_duration"] = 0.0
		summary["discharged_duration"] = 0.0
		summary["zone_ids"] = []
		return summary
	return electrical_arc_state.get_summary()

func get_arc_zone_node() -> Node:
	return arc_zone_node

func get_arc_zone_resolved_room_id() -> String:
	return arc_zone_resolved_room_id

func get_arc_zone_collision_enabled_count() -> int:
	if arc_zone_node == null:
		return 0
	for child in arc_zone_node.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return 1
	return 0

func teleport_player_to_arc_zone_for_validation() -> bool:
	if player == null or arc_zone_node == null:
		return false
	player.teleport_to(arc_zone_node.global_position)
	return true

# REQ-AU-001..010: audio runtime refresh. Mirrors _refresh_arc_state:
# the AudioManager owns the per-bus AudioStreamPlayer
# pool and pushes volumes from its summaries; this method is the per-frame
# seam that re-syncs the scene tree with the model's state. `force_initial`
# is true on first build / save-reload to push the summary even when no
# delta exists.
func _refresh_audio_state(force_initial: bool, _delta_seconds: float = 0.0) -> void:
	if audio_manager == null:
		return
	# Update the music-state flags based on the current gameplay signals.
	# Engagement defaults to false (no hostile AI in the vertical slice);
	# hazard_active is true when ANY hazard model reports non-safe state.
	# Fire audio must follow the ACTIVE fire model: on the away branch this is the
	# derelict's per-ship FireSuppressionState, so a burning derelict gets crackle/
	# hazard music and a home fire does not leak phantom crackle while away. At home
	# _active_fire_state() returns fire_suppression_state, so the home path is unchanged.
	var afs = _active_fire_state()
	var hazard_active: bool = false
	if oxygen_state != null and bool(oxygen_state.is_passability_blocked()):
		hazard_active = true
	if afs != null and not afs.get_burning_compartments().is_empty():
		hazard_active = true
	if electrical_arc_state != null and bool(electrical_arc_state.is_passability_blocked()):
		hazard_active = true
	# vitals_critical: derived from vitals_model oxygen <= 0 OR health below 25%.
	# vitals_model is optional in the playable scene; default to false when missing.
	# NOTE: PlayerVitalsModel exposes get_vitals_summary() (not get_summary()); the
	# health key is "health" (0-100) and the HP threshold is 25 out of 100.
	var vitals_critical: bool = false
	if vitals_model != null and vitals_model.has_method("get_vitals_summary"):
		var vs: Dictionary = vitals_model.get_vitals_summary()
		if float(vs.get("oxygen", 1.0)) <= 0.0:
			vitals_critical = true
		elif float(vs.get("health", 100.0)) < 25.0:
			vitals_critical = true
	# REQ-AU-001: pass the live combat engagement flag so COMBAT music is
	# reachable when a threat is in an engaged/aware state.
	var engagement: bool = false
	if is_instance_valid(threat_manager) and threat_manager.has_method("has_combat_engagement"):
		engagement = bool(threat_manager.has_combat_engagement())
	audio_manager.update_music_flags(engagement, hazard_active, vitals_critical)
	# REQ-AU-003: push live room-role ambient + hazard threat into AmbientZoneState.
	# Previously only smokes called set_room_role/set_threat_level; production never did.
	_push_ambient_zone_from_gameplay(hazard_active, engagement)
	# REQ-AU-001: emit hazard-coupled SFX through the router (cooldown-gated
	# so a burning / arcing state does not flood the bus every frame).
	if audio_manager.has_method("play_sfx"):
		# Fire crackle — any burning compartment present in the ACTIVE fire model.
		if afs != null and not afs.get_burning_compartments().is_empty():
			audio_manager.play_sfx(AudioEventSeamScript.SFX_FIRE_CRACKLE)
		# Arc zap — arcing phase active.
		if electrical_arc_state != null and electrical_arc_state.phase == ElectricalArcState.Phase.ARCING:
			audio_manager.play_sfx(AudioEventSeamScript.SFX_ARC_ZAP)
		# Suit breath — audible when oxygen is critically low or HP is critical.
		if vitals_critical:
			audio_manager.play_sfx(AudioEventSeamScript.SFX_SUIT_BREATH)
		# Vitals-low UI alert — emit exactly once per rising edge into critical.
		if vitals_critical and not _prev_vitals_critical:
			audio_manager.play_sfx(AudioEventSeamScript.UI_VITALS_LOW)
	_prev_vitals_critical = vitals_critical
	# Attach the AudioListener to the player when a player anchor exists.
	if player != null and is_instance_valid(player) and player is Node3D:
		audio_manager.attach_listener(player as Node3D)
	audio_manager.update_listener_transform()
	audio_manager.apply_spatial_attenuation()
	# REQ-AU criterion 3: pump pending captions to the HUD. Both _process
	# branches (away and home paths) already call _refresh_audio_state,
	# so this single call site satisfies the both-branches requirement
	# structurally — no per-branch wiring needed here.
	audio_manager.pump_captions(Callable(self, "_on_audio_caption"))
	if not _last_caption_line.is_empty():
		_caption_expiry_seconds -= _delta_seconds
		if _caption_expiry_seconds <= 0.0:
			_last_caption_line = ""
			_caption_expiry_seconds = 0.0

## Maps layout room_role strings onto AmbientZoneState ROOM_ROLE_* ids.
func _ambient_role_for_layout_role(layout_role: String) -> StringName:
	var r: String = layout_role.to_lower()
	if r in ["cargo", "storage", "salvage"]:
		return AudioEventSeamScript.ROOM_ROLE_CARGO
	if r in ["engine", "engineering", "reactor", "engine_bay", "propulsion", "power"]:
		return AudioEventSeamScript.ROOM_ROLE_ENGINE
	if r in ["medical", "med_bay", "triage", "clinic"]:
		return AudioEventSeamScript.ROOM_ROLE_MED_BAY
	if r in ["crew_quarters", "quarters", "mess_hall", "habitation", "galley"]:
		return AudioEventSeamScript.ROOM_ROLE_CREW_QUARTERS
	if r in ["dock", "docking", "airlock", "bay", "hangar", "bridge"]:
		return AudioEventSeamScript.ROOM_ROLE_DOCKING
	return AudioEventSeamScript.ROOM_ROLE_DOCKING

## Nearest layout room_role to the player (ship-local). Empty when no layout/player.
func _nearest_layout_room_role() -> String:
	if player == null or not (player is Node3D):
		return ""
	var layout: Dictionary = {}
	if current_ship != null and typeof(current_ship.built_layout) == TYPE_DICTIONARY:
		layout = current_ship.built_layout
	elif loader != null and loader.has_method("get_layout_copy"):
		layout = loader.get_layout_copy()
	var rooms_variant: Variant = layout.get("rooms", [])
	if not (rooms_variant is Array) or (rooms_variant as Array).is_empty():
		return ""
	var player_pos: Vector3 = (player as Node3D).global_position
	var best_role: String = ""
	var best_dist: float = INF
	for room_v in (rooms_variant as Array):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var role: String = str(room.get("room_role", room.get("role", "")))
		if role.is_empty():
			continue
		var center := Vector3.ZERO
		var pos_v: Variant = room.get("world_position", room.get("position", null))
		if pos_v is Vector3:
			center = pos_v as Vector3
		elif pos_v is Array and (pos_v as Array).size() >= 3:
			center = Vector3(float(pos_v[0]), float(pos_v[1]), float(pos_v[2]))
		elif loader != null and loader.has_method("get_room_center") and room.has("id"):
			center = loader.get_room_center(str(room.get("id", "")))
		else:
			continue
		# Prefer ship-local centers when parented under a docked root.
		var world_center: Vector3 = center
		if current_ship != null and is_instance_valid(current_ship.scene_root) and (current_ship.scene_root as Node3D).is_inside_tree():
			world_center = (current_ship.scene_root as Node3D).to_global(center)
		var dist: float = player_pos.distance_to(world_center)
		if dist < best_dist:
			best_dist = dist
			best_role = role
	return best_role

## Drive AmbientZoneState from live room + hazard context (both _process branches
## reach this via _refresh_audio_state).
func _push_ambient_zone_from_gameplay(hazard_active: bool, engagement: bool) -> void:
	if audio_manager == null or audio_manager.ambient_zone_state == null:
		return
	var layout_role: String = _nearest_layout_room_role()
	var ambient_role: StringName = _ambient_role_for_layout_role(layout_role)
	# Only restart crossfade when the role actually changes (set_room_role is
	# idempotent on same role unless force_restart).
	var current: String = String(audio_manager.ambient_zone_state.get_current_role())
	if current != String(ambient_role):
		audio_manager.ambient_zone_state.set_room_role(ambient_role, false, false)
	# Threat meter: combat engagement full, active hazard partial, else calm.
	var threat: float = 0.0
	if engagement:
		threat = 1.0
	elif hazard_active:
		threat = 0.7
	audio_manager.ambient_zone_state.set_threat_level(threat)

## Callback for audio_manager.pump_captions(): records the most recent
## caption dict as the HUD's displayed caption line. `caption` carries at
## least {event_id, text, duration, elapsed} (SfxEventRouter's queue shape).
## Multiple captions pumped in the same frame: last call wins (most recent).
func _on_audio_caption(caption: Dictionary) -> void:
	var text: String = String(caption.get("text", ""))
	if text.is_empty():
		return
	_last_caption_line = text
	var duration: float = float(caption.get("duration", SfxEventRouterScript.DEFAULT_CAPTION_DURATION))
	_caption_expiry_seconds = duration

## Validation seam: full audio summary from the manager. Used by the
## main playable slice audio smoke and by the audio_save_load smoke.
func get_audio_summary() -> Dictionary:
	if audio_manager == null:
		return {}
	return audio_manager.get_summary()

## Validation seam: convenience accessors used by smokes that need to
## inspect the audio manager's state without poking at its internals.
func get_audio_manager() -> Node:
	return audio_manager

## Validation seam: the most recently pumped audio caption, or "" if none is
## currently displayed (either nothing has fired yet, or the last one expired).
func get_last_caption_line() -> String:
	return _last_caption_line

## Validation seam: the most recent loot-feedback line (mirrors
## get_last_caption_line()). Domain 10 (ADR-0045) reuses this seam for the
## "No web chart" ui_open_map gate-rejection feedback.
func get_last_loot_feedback_line_for_validation() -> String:
	return _last_loot_feedback_line

func get_audio_bus_player_count() -> int:
	if audio_manager == null:
		return 0
	var count: int = 0
	for bus_id in ["sfx", "music", "voice", "ui", "ambient", "meta"]:
		if audio_manager.has_method("get_bus_player") and audio_manager.get_bus_player(StringName(bus_id)) != null:
			count += 1
	return count

func get_audio_spatial_player_count() -> int:
	if audio_manager == null:
		return 0
	if not audio_manager.has_method("get_spatial_player_count"):
		return 0
	return int(audio_manager.get_spatial_player_count())

# --- Inventory / Tool pickup integration -------------------------------------
# REQ-007: a single ToolPickup carrying the portable_oxygen_pump lives in a
# fixed side room (tool_storage_01 if the loader defines it, otherwise a
# fallback position near the player start). Acquiring the pickup adds the
# tool id to InventoryState exactly once; OxygenState reads the inventory
# summary each frame to halve the drain rate inside an unsealed breach.

func _build_tool_pickup() -> void:
	if tool_pickup_root == null:
		return
	for child in tool_pickup_root.get_children():
		tool_pickup_root.remove_child(child)
		child.queue_free()
	tool_pickup = null
	var world_position: Vector3 = _resolve_tool_pickup_world_position()
	tool_pickup = ToolPickupScript.new()
	tool_pickup.configure("portable_oxygen_pump", inventory_state, world_position, TOOL_PICKUP_INTERACTION_RADIUS)
	if not tool_pickup.tool_acquired.is_connected(_on_tool_pickup_acquired):
		tool_pickup.tool_acquired.connect(_on_tool_pickup_acquired)
	tool_pickup_root.add_child(tool_pickup)

func _resolve_tool_pickup_world_position() -> Vector3:
	if loader != null and loader.has_method("get_room_center"):
		var room_center: Vector3 = loader.get_room_center("tool_storage_01")
		if room_center != Vector3.INF:
			return room_center + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	# Fallback: near player start (no tool_storage_01 in the Gate 2 fixture).
	if player != null:
		return player.global_position + TOOL_PICKUP_FALLBACK_OFFSET
	if loader != null:
		return loader.get_start_transform().origin + TOOL_PICKUP_FALLBACK_OFFSET + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	return TOOL_PICKUP_FALLBACK_OFFSET

func _on_tool_pickup_acquired(p_tool_id: String) -> void:
	_refresh_tracker_system_status_lines()
	print("PLAYABLE TOOL ACQUIRED tool_id=%s" % p_tool_id)
	_recompute_player_encumbrance()
	_ensure_consumable_hotbar_assignments()
	_refresh_consumable_ui()
	# REQ-RL-003 / REQ-RL-004: route the tool pickup into the achievement
	# service when one is attached. Silent no-op when no service is
	# injected (the per-run achievement service is opt-in for tests).
	_try_unlock_achievement("tool_acquired", p_tool_id)

## REQ-RL-003: resolve (trigger_event, trigger_target) against the per-run
## achievement catalog. Exact target first; AchievementState also matches
## catalog entries with trigger_target "any" via the wildcard alias. Silent
## no-op when the service is missing or no entry matches.
func _try_unlock_achievement(trigger_event: String, trigger_target: String) -> void:
	if achievement_state == null or trigger_event.is_empty():
		return
	var unlocked_id: String = str(achievement_state.unlock_for_trigger(trigger_event, trigger_target))
	if not unlocked_id.is_empty():
		print("ACHIEVEMENT UNLOCKED trigger=%s target=%s id=%s" % [trigger_event, trigger_target, unlocked_id])

# --- REQ-014: junction_calibrator pickup -------------------------------------
# A second ToolPickup configured with tool_id = "junction_calibrator".
# Acquiring the pickup adds the id to InventoryState exactly once; the
# next interaction with a repair_junction sequence consumes it via
# _consume_junction_calibrator_if_eligible. The acquisition signal is
# the same shared ToolPickup.tool_acquired; _on_tool_pickup_acquired
# handles the HUD refresh / log line for both pickups.

func _build_junction_calibrator_pickup() -> void:
	if tool_pickup_root == null:
		return
	# Keep only the junction_calibrator pickup in scope for this build.
	# The REQ-007 oxygen pump child stays in the tree; we just create a
	# sibling ToolPickup under the same tool_pickup_root.
	var world_position: Vector3 = _resolve_junction_calibrator_world_position()
	junction_calibrator_pickup = ToolPickupScript.new()
	junction_calibrator_pickup.configure(
		"junction_calibrator",
		inventory_state,
		world_position,
		JUNCTION_CALIBRATOR_INTERACTION_RADIUS
	)
	if not junction_calibrator_pickup.tool_acquired.is_connected(_on_tool_pickup_acquired):
		junction_calibrator_pickup.tool_acquired.connect(_on_tool_pickup_acquired)
	tool_pickup_root.add_child(junction_calibrator_pickup)

func _resolve_junction_calibrator_world_position() -> Vector3:
	if loader != null and loader.has_method("get_room_center"):
		var room_center: Vector3 = loader.get_room_center(JUNCTION_CALIBRATOR_FALLBACK_ROOM_ID)
		if room_center != Vector3.INF:
			return room_center + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	# Fallback: opposite side of the player spawn from the oxygen pump so
	# the two pickups do not collide in space.
	if player != null:
		return player.global_position + JUNCTION_CALIBRATOR_FALLBACK_OFFSET
	if loader != null:
		return loader.get_start_transform().origin + JUNCTION_CALIBRATOR_FALLBACK_OFFSET + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
	return JUNCTION_CALIBRATOR_FALLBACK_OFFSET

## REQ-014: hide the junction_calibrator pickup marker after a reload
## when the restored state already represents a carried or spent
## calibrator. `_build_junction_calibrator_pickup` always creates a
## fresh ToolPickup with its marker visible; the only live code path
## that hides the marker is `_consume_junction_calibrator_if_eligible`,
## which the reload cannot reach because the snapshot is applied AFTER
## the pickup is built. The reload path therefore needs its own
## reconciliation step, driven by the same two model summaries the
## pickup's runtime visibility depends on.
func _reconcile_junction_calibrator_marker_after_reload() -> void:
	if junction_calibrator_pickup == null:
		return
	var carried: bool = inventory_state != null and inventory_state.has_tool("junction_calibrator")
	var spent: bool = false
	if objective_progress_state != null:
		for sequence_variant in objective_progress_state.get_summary().keys():
			var seq: int = int(sequence_variant)
			if seq <= 0:
				continue
			if objective_progress_state.has_calibrator_applied(seq):
				spent = true
				break
	if carried or spent:
		junction_calibrator_pickup.set_marker_visible(false)
	_refresh_tracker_system_status_lines()

## REQ-014: consume a carried junction_calibrator against the given
## sequence iff the sequence is registered as `kind == "repair_junction"`
## in the loader specs. On a successful application the calibrator is
## removed from inventory and the HUD status line is refreshed.
## Called at the start of `_on_interactable_completed` so the reduced
## required_steps is in force before `complete_step` runs in the same
## interaction frame.
func _consume_junction_calibrator_if_eligible(sequence: int) -> void:
	if sequence <= 0:
		return
	if inventory_state == null or objective_progress_state == null:
		return
	if str(sequence_kinds.get(sequence, "single")) != "repair_junction":
		return
	if not inventory_state.has_tool("junction_calibrator"):
		return
	if not objective_progress_state.apply_junction_calibrator(sequence):
		# One-step junction or already-applied or already-complete: do
		# NOT remove the calibrator. The spec's "minimum one step"
		# contract is the model's responsibility; we trust its return.
		return
	if not inventory_state.remove_tool("junction_calibrator"):
		# Defensive: roll the model back so the calibrator is not
		# silently spent while still in inventory. The model's apply
		# method leaves no public rollback, so we re-apply the prior
		# step count from a fresh get_step_progress and reset the
		# calibrator_applied flag through a tiny inverse. We prefer to
		# fail loudly here rather than desync inventory vs. model.
		var before: Dictionary = objective_progress_state.get_step_progress(sequence)
		var after: Dictionary = before.duplicate()
		after["required_steps"] = int(before.get("required_steps", 1)) + 1
		after["calibrator_applied"] = false
		# Re-store via apply_summary round-trip on a single-sequence
		# summary to avoid poking at the model's internals.
		objective_progress_state.apply_summary({
			sequence: {
				"objective_type": str(after.get("objective_type", "")),
				"required_steps": int(after.get("required_steps", 1)),
				"completed_steps": int(before.get("completed_steps", 0)),
				"completed_step_ids": (before.get("completed_step_ids", []) as Array).duplicate(),
				"complete": bool(before.get("complete", false)),
				"calibrator_applied": false,
			}
		})
		push_warning("PlayableGeneratedShip: junction_calibrator consumed by model but not removed from inventory; rolled back")
	# Hide the pickup marker if it is still visible (the pickup is one-
	# shot per slice run regardless of the order of consume vs pickup).
	if junction_calibrator_pickup != null:
		junction_calibrator_pickup.set_marker_visible(false)
	_refresh_tracker_system_status_lines()
	var progress: Dictionary = objective_progress_state.get_step_progress(sequence)
	print("JUNCTION CALIBRATOR APPLIED sequence=%d required_steps=%d completed_steps=%d" % [
		sequence,
		int(progress.get("required_steps", 1)),
		int(progress.get("completed_steps", 0)),
	])

# --- Headless validation seams ------------------------------------------------

func get_inventory_summary() -> Dictionary:
	if inventory_state == null:
		return { "tool_ids": [], "active_effects": [] }
	return inventory_state.get_summary()

func get_tool_pickup_node() -> Node:
	return tool_pickup

## REQ-014: returns the second ToolPickup (junction_calibrator), or null
## before _build_junction_calibrator_pickup has run.
func get_junction_calibrator_pickup_node() -> Node:
	return junction_calibrator_pickup

## REQ-014: teleports the player to the junction_calibrator pickup so
## the main-scene smoke can drive the acquisition through the real
## PlayerController.request_interact() path.
func teleport_player_to_junction_calibrator_for_validation() -> bool:
	if player == null or junction_calibrator_pickup == null:
		return false
	player.teleport_to(junction_calibrator_pickup.global_position)
	return true

## REQ-014: drives the same ToolPickup.try_interact path as a real
## player press, returning true only when the inventory model now
## contains the calibrator. Mirrors acquire_tool_for_validation but
## for the second pickup; intentionally does not duplicate the oxygen-
## pump helper so each pickup keeps a single canonical acquisition seam.
func acquire_junction_calibrator_for_validation() -> bool:
	if junction_calibrator_pickup == null or inventory_state == null:
		return false
	if junction_calibrator_pickup.tool_id != "junction_calibrator":
		return false
	if not teleport_player_to_junction_calibrator_for_validation():
		return false
	junction_calibrator_pickup.set_validation_player_in_range(player)
	player.request_interact()
	return inventory_state.has_tool("junction_calibrator")

## REQ-014: validation seam for the main-scene smoke. Equivalent to
## the coordinator's auto-consume path but invoked directly so the
## smoke can assert required_steps=2 (etc.) without running the full
## interactable complete handshake a second time.
func apply_junction_calibrator_for_validation(sequence: int) -> bool:
	if sequence <= 0:
		return false
	_consume_junction_calibrator_if_eligible(sequence)
	return true

## REQ-014: validation seam for the main-scene smoke. Registers a
## `repair_junction`-kind sequence in the objective_progress_state with
## the given required_steps and caches the kind in sequence_kinds so
## the smoke can drive `_consume_junction_calibrator_if_eligible`
## end-to-end without depending on the seed template's exact step
## count. The seed template's sequence 2 is a 2-step junction; REQ-014
## acceptance criteria require a 3-step reduction target so the main-
## scene smoke registers its own synthetic sequence here and asserts
## `required_steps=2` after the calibrator is applied.
func register_junction_sequence_for_validation(sequence: int, required_steps: int) -> bool:
	if sequence <= 0 or required_steps < 1:
		return false
	if objective_progress_state == null:
		return false
	sequence_kinds[sequence] = "repair_junction"
	# Reset the existing record first so the smoke gets a clean state
	# even if a same-numbered sequence was loaded from the template.
	objective_progress_state.reset()
	for spec_variant in loader.get_objective_specs_copy():
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var spec_sequence: int = int(spec.get("sequence", 0))
		var spec_kind: String = str(spec.get("kind", "single"))
		sequence_kinds[spec_sequence] = spec_kind
		var spec_steps: Array = []
		var spec_steps_variant: Variant = spec.get("steps", [])
		if typeof(spec_steps_variant) == TYPE_ARRAY:
			spec_steps = spec_steps_variant
		if spec_kind == "repair_junction" and spec_steps.size() > 1:
			objective_progress_state.register_objective(spec_sequence, str(spec.get("type", "unknown")), spec_steps.size())
	# Then layer the smoke's synthetic junction on top. If the smoke
	# re-uses a real sequence number from the template, this registration
	# overwrites the prior record; that is acceptable because the smoke
	# will not complete that real sequence afterward.
	objective_progress_state.register_objective(sequence, "repair_junction", required_steps)
	return true

func teleport_player_to_tool_pickup_for_validation() -> bool:
	if player == null or tool_pickup == null:
		return false
	player.teleport_to(tool_pickup.global_position)
	return true

func acquire_tool_for_validation(p_tool_id: String) -> bool:
	if tool_pickup == null or inventory_state == null:
		return false
	if tool_pickup.tool_id != p_tool_id:
		return false
	if not teleport_player_to_tool_pickup_for_validation():
		return false
	tool_pickup.set_validation_player_in_range(player)
	player.request_interact()
	return inventory_state.has_tool(p_tool_id)

# --- REQ-012 current-run save/load -------------------------------------------
# Per ADR-0007, only current-run state is serialized. The hub ship, derelict
# selection, meta-currency, unlocks, faction/narrative progress, and
# cross-run bookkeeping are explicitly excluded. Adding a new field to
# RunSnapshot requires a new ADR.

## Captures a fresh RunSnapshot from the current runtime state. Returns
## null if the slice is not started or any required model is missing.
func _build_run_snapshot(use_home_arc_summary: bool = false) -> RunSnapshot:
	if not playable_started or slice_complete:
		return null
	if save_load_service == null:
		return null
	var snapshot := RunSnapshotScript.new()
	snapshot.layout_path = layout_path
	snapshot.kit_path = kit_path
	snapshot.gameplay_slice_path = gameplay_slice_path
	if player != null and player is Node3D:
		var pos: Vector3 = (player as Node3D).global_position
		snapshot.player_position = [pos.x, pos.y, pos.z]
	snapshot.current_objective_sequence = current_objective_sequence
	if ship_systems_manager != null:
		snapshot.ship_systems_summary = ship_systems_manager.get_summary()
		# Persist only the authoritative objective record; flag-shaped fields
		# (main_power_restored, emergency_supplies_recovered, ...) are derived
		# live from manager health + this record via _manager_compat_summary(),
		# never stored (ADR-0009).
		snapshot.ship_systems_summary["completed_objective_types"] = completed_objective_types.keys()
		for key in _expanded_ship_systems_summary().keys():
			snapshot.ship_systems_summary[key] = _expanded_ship_systems_summary()[key]
	if route_control_state != null:
		snapshot.route_control_summary = get_route_control_summary()
	if oxygen_state != null:
		snapshot.oxygen_summary = get_oxygen_summary()
	if inventory_state != null:
		snapshot.inventory_summary = inventory_state.get_summary()
	# ADR-0038: persist crafting + material state via the existing additive fields. Field
	# crafting nests under crafting_summary["field_crafting"] so no new RunSnapshot field is
	# introduced (apply_summary ignores unknown keys; FieldCraftingState reads the nested key).
	if crafting_state != null:
		snapshot.crafting_summary = crafting_state.get_summary()
		if field_crafting_state != null:
			snapshot.crafting_summary["field_crafting"] = field_crafting_state.get_summary().get("field_crafting", {})
	if material_state != null:
		snapshot.material_summary = material_state.get_summary()
	if is_instance_valid(threat_manager):
		snapshot.inventory_summary["combat_hotbar_text"] = _last_weapon_hotbar_text
		snapshot.inventory_summary["threat_summary"] = threat_manager.get_summary()
	# M7-B Task 7: the old timer FireState is retired. Authoritative fire state
	# round-trips via fire_suppression_summary (see _expanded_ship_systems_summary
	# / the ship_systems_summary restore path). The legacy snapshot.fire_summary
	# field is left at its default for save-format back-compat.
	if use_home_arc_summary:
		if home_ship != null and not home_ship.arc_summary.is_empty():
			snapshot.electrical_arc_summary = home_ship.arc_summary.duplicate(true)
	elif electrical_arc_state != null:
		_sync_current_ship_arc_summary()
		snapshot.electrical_arc_summary = electrical_arc_state.get_summary()
	if objective_progress_state != null:
		snapshot.objective_progress_summary = objective_progress_state.get_summary()
	if player_progression != null:
		snapshot.player_progression_summary = player_progression.get_summary()
	if skill_tree_state != null:
		snapshot.skill_tree_summary = skill_tree_state.to_dict()
	if is_instance_valid(menu_coordinator):
		snapshot.settings_summary = menu_coordinator.get_settings_summary()
	if is_instance_valid(audio_manager):
		snapshot.audio_summary = audio_manager.get_summary()
	# REQ-SV: capture survival vitals summaries.
	if vitals_state != null:
		snapshot.vitals_summary = vitals_state.get_summary()
	if sanity_state != null:
		snapshot.sanity_summary = sanity_state.get_summary()
	if radiation_state != null:
		snapshot.radiation_summary = radiation_state.get_summary()
	if body_temperature_state != null:
		snapshot.temperature_summary = body_temperature_state.get_summary()
	if status_effects_state != null:
		snapshot.status_effects_summary = status_effects_state.get_summary()
	# Session 3 B3 (ADR-0042): persist the hallucination director — active
	# events, deterministic rng step, tier teeth — so saving mid-episode
	# does not silently reset it on load.
	if hallucination_director != null:
		snapshot.hallucination_summary = hallucination_director.get_summary()
	# ADR-0034: capture food / cooking / spoilage summaries.
	if spoilage_state != null:
		snapshot.spoilage_summary = spoilage_state.get_summary()
	if hydroponics_state != null:
		snapshot.hydroponics_summary = hydroponics_state.get_summary()
	if water_recycler_state != null:
		snapshot.water_recycler_summary = water_recycler_state.get_summary()
	if consumable_state != null:
		snapshot.consumable_summary = consumable_state.get_summary()
	if medicine_state != null:
		snapshot.medicine_summary = medicine_state.get_summary()
	if stimulant_state != null:
		snapshot.stimulant_summary = stimulant_state.get_summary()
	if addiction_state != null:
		snapshot.addiction_summary = addiction_state.get_summary()
	if ammo_state != null:
		snapshot.ammo_summary = ammo_state.get_summary()
	if utility_item_state != null:
		snapshot.utility_summary = utility_item_state.get_summary()
	# ADR-0046: real slot metadata — accumulated play time, the active
	# ship's location (marker id, or "home" for the hub), and the Synaptic
	# Sea world seed. _index_run_slot reads these instead of placeholders.
	snapshot.play_time_seconds = run_play_time_seconds
	snapshot.current_location = "home"
	if current_ship != null and String(current_ship.marker_id) != "":
		snapshot.current_location = String(current_ship.marker_id)
	if synaptic_sea_world != null:
		snapshot.world_seed = int(synaptic_sea_world.world_seed)
	snapshot.slice_version = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	snapshot.godot_version = Engine.get_version_info()["string"]
	snapshot.saved_at = Time.get_datetime_string_from_system(true)
	return snapshot

## Writes the whole world to the single save slot. Routed through the
## world-save format (ADR-0012) so every write to user://saves/current_run.json
## — auto-save here AND manual request_save — is a WorldSnapshot. Otherwise an
## auto-save on objective completion would overwrite a manual F5 world-save with
## a RunSnapshot and fail the version gate on the next load. The in-memory
## RunSnapshot seam (last_saved_snapshot / get_last_saved_snapshot) is preserved
## because the auto-save regression smokes assert its current_objective_sequence.
func _auto_save_current_run() -> bool:
	if save_load_service == null or slice_complete:
		return false
	if _demo_save_refused():
		return false
	var ws = _build_world_snapshot()
	if ws == null:
		return false
	if save_load_service.save_world(ws):
		last_saved_snapshot = _build_run_snapshot()  # preserve in-memory RunSnapshot seam (get_last_saved_snapshot)
		return true
	return false

## Monotonically-growing activity proxy for the autosave policy's event channel
## (objective checkpoints + every logged training/run event). Used by
## AutosavePolicy.cadence_events to fire an autosave after enough activity.
func _autosave_event_count() -> int:
	var count: int = objective_completion_count
	if training_event_bus != null:
		count += training_event_bus.get_log().size()
	return count

## Timed/rotating autosave loop. Additive to the REQ-012 checkpoint save —
## writes a RunSnapshot into a rotating autosave_a/b/c slot whenever the policy
## fires (time cadence, event cadence, or a forced checkpoint). Never touches the
## current_run.json path the resume smokes depend on.
func _tick_autosave_policy(delta: float) -> void:
	if autosave_policy == null or save_load_service == null or slice_complete:
		return
	if _demo_save_refused():
		return
	_autosave_run_seconds += delta
	var r: Dictionary = autosave_policy.tick(_autosave_run_seconds, _autosave_event_count())
	if not bool(r.get("should_save", false)):
		return
	var snap: RunSnapshot = _build_run_snapshot()
	if snap == null:
		return
	var slot_id: String = str(r.get("slot_id", ""))
	if slot_id.is_empty():
		return
	if save_load_service.save_to_slot(slot_id, snap, SaveSlotStateScript.SLOT_KIND_AUTO, false, "Autosave"):
		last_saved_snapshot = snap
		_last_autosave_result = r

## Validation seam: the live AutosavePolicy instance (null before runtime build).
func get_autosave_policy_for_validation():
	return autosave_policy

## Validation seam: the last {should_save, slot_id, reason} the autosave loop acted on.
func get_last_autosave_result() -> Dictionary:
	return _last_autosave_result

## Validation seam: force a single rotating autosave through the real coordinator
## path (no 90 s wait) and return the policy's result dict.
func force_autosave_for_validation() -> Dictionary:
	if autosave_policy == null:
		return {}
	autosave_policy.force = true
	_tick_autosave_policy(0.0)
	# If the policy had never been ticked, its first tick only seeds counters
	# (the force flag survives the seed branch); tick once more to actually fire.
	if autosave_policy.force:
		_tick_autosave_policy(0.0)
	return _last_autosave_result

## REQ-PM-008 / ADR-0033 — at run-end, fold the run summary into the
## meta_progression_state (currency + counters), persist the meta + unlock
## state to disk, and emit the resolved unlock events from the bus log so
## codex / scene / class unlocks can record themselves on the registry.
##
## `reason` is "completion" or "death". The payout is the same either way
## (per the spec: death still earns currency for what was accomplished).
func _apply_meta_payout_and_persist(reason: String = "completion") -> int:
	if meta_progression_state == null:
		return 0
	var summary: Dictionary = get_slice_completion_summary() if has_method("get_slice_completion_summary") else {}
	var completed: int = int(summary.get("completed_objectives", objective_completion_count))
	var skill_levels: Dictionary = {}
	if player_progression != null:
		for sid in player_progression.skills:
			skill_levels[sid] = int(player_progression.skills[sid])
	var run_summary: Dictionary = {
		"completed_objectives": completed,
		"skill_levels": skill_levels,
		"discoveries": 0,
		"reason": reason,
	}
	var payout: int = int(meta_progression_state.apply_meta_payout(run_summary))
	# Persist unlocks; bridge registry class-unlocks into the meta class set so the
	# class picker can select them next run, then persist meta AFTER the bridge.
	if unlock_registry != null:
		if training_event_bus != null:
			for entry in training_event_bus.get_log():
				var evt: String = str(entry.get("event_id", ""))
				var tgt: String = str(entry.get("target_id", ""))
				if not evt.is_empty():
					# Keep the registry's own first-match unlock accounting (codex/scene display).
					unlock_registry.unlock_for_trigger(evt, tgt)
					# Bridge EVERY class row for this trigger into the meta class set,
					# independent of unlock_for_trigger's single return (P1 fix).
					for cls in unlock_registry.class_ids_for_trigger(evt, tgt):
						meta_progression_state.unlock_class(cls)
		unlock_registry.save_to_disk()
	meta_progression_state.save_to_disk()
	print("META PAYOUT reason=%s payout=%d meta_currency=%d runs_completed=%d" % [
		reason,
		payout,
		int(meta_progression_state.meta_currency),
		int(meta_progression_state.total_runs_completed),
	])
	return payout

## Manual quicksave (F6 / quicksave_run). Writes the rotating quicksave slot via
## AutosavePolicy.try_quicksave (cooldown-gated) + SaveLoadService.save_to_slot
## SLOT_KIND_QUICK. Distinct from F5 world save and from Save & Exit.
func request_quicksave() -> bool:
	if slice_complete or save_load_service == null or autosave_policy == null:
		return false
	if _demo_save_refused():
		return false
	var gate: Dictionary = autosave_policy.try_quicksave()
	if not bool(gate.get("should_save", false)):
		return false
	var snap: RunSnapshot = _build_run_snapshot()
	if snap == null:
		return false
	var slot_id: String = str(gate.get("slot_id", SaveSlotStateScript.QUICKSAVE_SLOT_ID))
	if slot_id.is_empty():
		slot_id = SaveSlotStateScript.QUICKSAVE_SLOT_ID
	if save_load_service.save_to_slot(slot_id, snap, SaveSlotStateScript.SLOT_KIND_QUICK, true, "Quicksave"):
		last_saved_snapshot = snap
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx(AudioEventSeamScript.UI_SAVE)
		return true
	return false

## Validation seam: drive the real quicksave path (respects cooldown).
func request_quicksave_for_validation() -> bool:
	return request_quicksave()

## Manual save trigger (F5 / save_run input). Saves the whole world, so saving is
## allowed anywhere — including aboard a traveled derelict (save-anywhere; ADR-0012
## supersedes the Phase 4.5 away-save rejection). Refuses only before the slice has
## started or after it has completed.
func request_save() -> bool:
	if not playable_started or slice_complete:
		return false
	if save_load_service == null:
		return false
	# Tranche 6 (REQ-RL-006, user decision 2026-07-07): demo builds REFUSE
	# further saves past the authored play-time cap — existing saves are kept,
	# nothing is ever wiped. Surfaced on the HUD feedback line.
	if _demo_save_refused():
		# PR #68 review (Kilo): render the ACTUAL manifest cap, not a literal.
		_last_loot_feedback_line = "Demo build: save limit reached (%d min)" % int(_demo_save_cap_seconds() / 60.0)
		return false
	var ws = _build_world_snapshot()
	if ws == null:
		return false
	var result: bool = save_load_service.save_world(ws)
	if result:
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx(AudioEventSeamScript.UI_SAVE)
		print("PLAYABLE SHIP SAVED location=%s sequence=%d" % [ws.current_location, current_objective_sequence])
		if is_instance_valid(menu_coordinator):
			menu_coordinator.trigger_tutorial("run_saved", "any")
			menu_coordinator.set_load_available(true)
	return result

## Tranche 6 (REQ-RL-006) demo-gate helpers. All three are permissive when the
## gate is absent or the live build kind is dev/release — demo enforcement
## only ever narrows behavior in an actual demo build.

## The authored demo play-time save budget in seconds (single source of truth
## for the refusal check AND the player-facing feedback line — PR #68 Kilo).
func _demo_save_cap_seconds() -> float:
	if demo_scope_gate == null:
		return 1200.0
	return float(demo_scope_gate.get_params("long_run.persistence").get("max_play_seconds", 1200))

## True when a demo build has exhausted its authored play-time save budget
## (long_run.persistence params.max_play_seconds). Saves are refused, never wiped.
func _demo_save_refused() -> bool:
	if demo_scope_gate == null or not demo_scope_gate.is_blocked("long_run.persistence"):
		return false
	return run_play_time_seconds >= _demo_save_cap_seconds()

## Demo derelict hazard-kind budget (multi_hazard.run params.max_hazards).
## -1 = unlimited (dev/release or gate absent).
func _demo_max_hazards() -> int:
	if demo_scope_gate == null or not demo_scope_gate.is_blocked("multi_hazard.run"):
		return -1
	return maxi(0, int(demo_scope_gate.get_params("multi_hazard.run").get("max_hazards", 1)))

## Caps a ship's cargo hold to the demo max weight (cargo_hold.full_inventory
## params.max_weight_kg). Eagerly creates the hold in demo so every later lazy
## get_inventory() consumer sees the cap. No-op outside demo builds.
func _apply_demo_cargo_cap(inst) -> void:
	if inst == null or demo_scope_gate == null:
		return
	if not demo_scope_gate.is_blocked("cargo_hold.full_inventory"):
		return
	var cap: float = float(demo_scope_gate.get_params("cargo_hold.full_inventory").get("max_weight_kg", 6.0))
	var hold = inst.get_inventory()
	if hold != null and hold.get_max_weight() > cap:
		hold.max_weight = cap

## Validation / public seam: the SaveLoadService instance. Returns null
## before _build_runtime_nodes() has run.
func get_save_load_service() -> SaveLoadService:
	return save_load_service

## Validation / public seam: the most recent successful snapshot. Null
## until the first request_save() (or auto-save) has completed.
func get_last_saved_snapshot() -> RunSnapshot:
	return last_saved_snapshot

## Validation / public seam: true if a save file currently exists on
## disk (regardless of version compatibility).
func is_load_available() -> bool:
	if save_load_service == null:
		return false
	return save_load_service.has_save()

## Manual load trigger (F9 / load_run input). Loads the whole world and applies it
## (home ship + visited-ship registry + active location + in-ship position).
func request_load() -> bool:
	if save_load_service == null:
		return false
	var ws = save_load_service.load_world()
	if ws == null:
		push_warning("PlayableGeneratedShip: no compatible world save to load")
		return false
	var loaded: bool = _apply_world_snapshot(ws)
	if loaded:
		# run_id slot-ownership rework: a successful Continue/F9 world load
		# means this run instance now owns the loaded world.json's run_id --
		# its pre-existing autosave family is attributed to that same id, so
		# a death from here freezes them via the normal freeze_run(_run_id)
		# path. If the loaded world.json predates this field (empty run_id,
		# legacy save), generate a fresh id instead: this deliberately fails
		# OPEN (dying before the first save under the fresh id freezes
		# nothing) rather than writing a backfilled id to disk on load --
		# see ADR-0043 addendum for the rejected write-on-read alternative.
		_run_id = ws.run_id if not String(ws.run_id).is_empty() else _generate_run_id()
		save_load_service.set_active_run_id(_run_id)
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx(AudioEventSeamScript.UI_LOAD)
		if is_instance_valid(menu_coordinator):
			menu_coordinator.set_load_available(true)
	return loaded

## Reconstructs the slice through the normal load path, then applies
## the saved model summaries. Designed to be called from a fully
## bootstrapped coordinator (e.g. during a manual F9 load). Returns
## true on success.
func _apply_run_snapshot(snapshot: RunSnapshot) -> bool:
	if snapshot == null or not playable_started:
		return false
	# Reset the live slice to a fresh state. _ready() will be re-driven
	# by resetting the loader and asking it to reload from the saved
	# paths synchronously.
	_is_reloading = true
	_reset_runtime_for_reload()
	layout_path = snapshot.layout_path
	kit_path = snapshot.kit_path
	gameplay_slice_path = snapshot.gameplay_slice_path
	# The loader is sync; ship_loaded fires on the same call stack, but
	# we guard _on_ship_loaded with a reload-aware flag so the first
	# _on_ship_loaded after a reload does NOT mark playable_started
	# prematurely (it must re-emit).
	playable_started = false
	loader.load_from_paths(layout_path, kit_path, gameplay_slice_path)
	if not playable_started:
		# Loader must have failed; _on_ship_loaded bailed out.
		_is_reloading = false
		push_error("PlayableGeneratedShip: load failed because slice did not start")
		return false
	# ADR-0046: resume the accumulated play-time clock from the save.
	# current_location/world_seed are stamped-at-save metadata: location is
	# re-derived live from current_ship at the next save, and the world seed
	# is owned by the world-save path (SynapticSeaWorld.apply_summary).
	run_play_time_seconds = snapshot.play_time_seconds
	# Apply the saved model state to the freshly-built slice.
	if ship_systems_manager != null and not snapshot.ship_systems_summary.is_empty():
		ship_systems_manager.apply_summary(snapshot.ship_systems_summary)
		if power_grid_state != null:
			power_grid_state.apply_summary(snapshot.ship_systems_summary.get("power_grid_summary", {}))
		if life_support_expanded_state != null:
			life_support_expanded_state.apply_summary(snapshot.ship_systems_summary.get("life_support_state_summary", {}))
		if hull_integrity_state != null:
			hull_integrity_state.apply_summary(snapshot.ship_systems_summary.get("hull_integrity_summary", {}))
		if hull_web_state != null:
			hull_web_state.apply_summary(snapshot.ship_systems_summary.get("web_infestation_summary", {}))
		if fire_suppression_state != null:
			fire_suppression_state.apply_summary(snapshot.ship_systems_summary.get("fire_suppression_summary", {}))
		if extinguisher_state != null:
			extinguisher_state.apply_summary(snapshot.ship_systems_summary.get("extinguisher_summary", {}))
		if propulsion_expanded_state != null:
			propulsion_expanded_state.apply_summary(snapshot.ship_systems_summary.get("propulsion_state_summary", {}))
		if sustenance_state != null:
			sustenance_state.apply_summary(snapshot.ship_systems_summary.get("sustenance_state_summary", {}))
		completed_objective_types.clear()
		for t in snapshot.ship_systems_summary.get("completed_objective_types", []):
			completed_objective_types[str(t)] = true
		objective_completion_count = max(0, snapshot.current_objective_sequence - 1)
		# Re-apply scene consequences for every completed objective. The reload
		# rebuilds affordances visible (via _build_slice_affordance_labels), so a
		# completed restore_systems must re-clear the blocked-biomatter props or
		# they reappear after loading (PR #2 review finding). The handler is a
		# no-op for objective types without scene consequences, so iterating all
		# completed types is safe and future-proof.
		for completed_type in completed_objective_types:
			_apply_ship_systems_consequences(str(completed_type))
		_recompute_expanded_ship_systems(0.0)
		_refresh_route_control_from_ship_systems()
		if oxygen_state != null:
			oxygen_state.apply_ship_systems_summary(_manager_compat_summary())
	if route_control_state != null and not snapshot.route_control_summary.is_empty():
		route_control_state.apply_summary(snapshot.route_control_summary)
		_apply_route_gate_scene_state()
	if oxygen_state != null and not snapshot.oxygen_summary.is_empty():
		oxygen_state.apply_summary(snapshot.oxygen_summary)
		_refresh_oxygen_state(true, 0.0)
	# ADR-0038: restore crafting + material state (and nested field-craft progress). Both
	# apply_summary calls receive the same crafting_summary dict — CraftingState reads
	# active_craft/station_summaries, FieldCraftingState reads the nested "field_crafting" key.
	if crafting_state != null and not snapshot.crafting_summary.is_empty():
		crafting_state.apply_summary(snapshot.crafting_summary)
		if field_crafting_state != null:
			field_crafting_state.apply_summary(snapshot.crafting_summary)
	if material_state != null and not snapshot.material_summary.is_empty():
		material_state.apply_summary(snapshot.material_summary)
	if inventory_state != null and not snapshot.inventory_summary.is_empty():
		inventory_state.apply_summary(snapshot.inventory_summary)
		_last_weapon_hotbar_text = str(snapshot.inventory_summary.get("combat_hotbar_text", _last_weapon_hotbar_text))
		var threat_summary: Variant = snapshot.inventory_summary.get("threat_summary", {})
		if is_instance_valid(threat_manager) and threat_summary is Dictionary and not (threat_summary as Dictionary).is_empty():
			threat_manager.apply_summary(threat_summary as Dictionary)
			_sync_current_ship_combat_summary()
	# M7-B Task 7: authoritative fire is restored via the ship_systems_summary
	# (fire_suppression_summary) applied above; the burning set is re-rendered by
	# the _build_fire_zones() call on the restore build path. The legacy
	# snapshot.fire_summary field is intentionally not read here.
	# REQ-013: restore the electrical-arc summary alongside fire. The
	# model's apply_summary rejects summaries whose hazard_kind does
	# not match, so an older snapshot written before REQ-013 lands is
	# silently ignored instead of corrupting the live state.
	if electrical_arc_state != null and not snapshot.electrical_arc_summary.is_empty():
		electrical_arc_state.apply_summary(snapshot.electrical_arc_summary)
		_refresh_arc_state(true)
		_sync_current_ship_arc_summary()
	if objective_progress_state != null and not snapshot.objective_progress_summary.is_empty():
		objective_progress_state.apply_summary(snapshot.objective_progress_summary)
	if player_progression != null and not snapshot.player_progression_summary.is_empty():
		player_progression.apply_summary(snapshot.player_progression_summary)
	if skill_tree_state != null and not snapshot.skill_tree_summary.is_empty():
		skill_tree_state.apply_summary(snapshot.skill_tree_summary)
	if is_instance_valid(menu_coordinator) and not snapshot.settings_summary.is_empty():
		menu_coordinator.apply_settings_summary(snapshot.settings_summary)
	# REQ-AU-010: re-apply the audio summary to the AudioManager so save/load
	# restores per-bus volume, ambient role, sfx router cooldowns, music
	# state, spatial resolver config, and meta-event schedule.
	if is_instance_valid(audio_manager) and not snapshot.audio_summary.is_empty():
		audio_manager.apply_summary(snapshot.audio_summary)
	_reconcile_captions_with_settings()
	# REQ-SV: restore survival vitals summaries.
	if vitals_state != null and not snapshot.vitals_summary.is_empty():
		vitals_state.apply_summary(snapshot.vitals_summary)
	if sanity_state != null and not snapshot.sanity_summary.is_empty():
		sanity_state.apply_summary(snapshot.sanity_summary)
	if radiation_state != null and not snapshot.radiation_summary.is_empty():
		radiation_state.apply_summary(snapshot.radiation_summary)
	if body_temperature_state != null and not snapshot.temperature_summary.is_empty():
		body_temperature_state.apply_summary(snapshot.temperature_summary)
	if status_effects_state != null and not snapshot.status_effects_summary.is_empty():
		status_effects_state.apply_summary(snapshot.status_effects_summary)
	# Session 3 B3 (ADR-0042): restore the hallucination director. Ordering
	# matters — the loader reload above already ran _build_hallucination_runtime
	# (a fresh director per ship), so applying here lands on the rebuilt
	# instance instead of being wiped by the rebuild.
	if hallucination_director != null and not snapshot.hallucination_summary.is_empty():
		hallucination_director.apply_summary(snapshot.hallucination_summary)
	# ADR-0034: restore food / cooking / spoilage summaries.
	if spoilage_state != null and not snapshot.spoilage_summary.is_empty():
		spoilage_state.apply_summary(snapshot.spoilage_summary)
	if hydroponics_state != null and not snapshot.hydroponics_summary.is_empty():
		hydroponics_state.apply_summary(snapshot.hydroponics_summary)
	if water_recycler_state != null and not snapshot.water_recycler_summary.is_empty():
		water_recycler_state.apply_summary(snapshot.water_recycler_summary)
	if consumable_state != null and not snapshot.consumable_summary.is_empty():
		consumable_state.apply_summary(snapshot.consumable_summary)
	if medicine_state != null and not snapshot.medicine_summary.is_empty():
		medicine_state.apply_summary(snapshot.medicine_summary)
	if stimulant_state != null and not snapshot.stimulant_summary.is_empty():
		stimulant_state.apply_summary(snapshot.stimulant_summary)
	if addiction_state != null and not snapshot.addiction_summary.is_empty():
		addiction_state.apply_summary(snapshot.addiction_summary)
	if ammo_state != null and not snapshot.ammo_summary.is_empty():
		ammo_state.apply_summary(snapshot.ammo_summary)
	if utility_item_state != null and not snapshot.utility_summary.is_empty():
		utility_item_state.apply_summary(snapshot.utility_summary)
	_ensure_consumable_hotbar_assignments()
	_refresh_consumable_ui()
	# REQ-014: reconcile the junction_calibrator pickup marker visibility
	# with the restored inventory + objective_progress summaries. The
	# marker is rebuilt visible by `_build_junction_calibrator_pickup`,
	# but a loaded save may have already carried or consumed the tool.
	# Without this, the reload path resurrects the pickup marker even
	# though the calibrator is in the carried inventory (or already spent),
	# which lets the reviewer probe re-acquire the calibrator after load.
	_reconcile_junction_calibrator_marker_after_reload()
	# Rebuild repair points after all systems summaries have been applied so
	# only truly-damaged subcomponents get markers (Fix 2: stale markers
	# built before apply_summary healed already-repaired subcomponents).
	_build_repair_points()
	_build_breach_seal_points()
	# M7-B Task 7: save-restore path — render the burning set from the applied
	# fire_suppression_summary. Do NOT seed here (restored fires are authoritative).
	_build_fire_zones()
	# M7-B Task 9: rebuild manual extinguish nodes + recharge port for restored fires.
	_build_fire_suppression_points()
	_build_extinguisher_recharge_port()
	_build_crafting_stations()
	_build_production_stations()
	# Restore the saved objective sequence AFTER all model state has
	# been applied so the subsequent _activate_current_objective() call
	# sees the right state.
	current_objective_sequence = max(1, snapshot.current_objective_sequence)
	_activate_current_objective()
	_refresh_weapon_hotbar()
	# Teleport the player to the saved position last so any spawn-side
	# effects (e.g. hazard proximity) do not overwrite the snapshot.
	if player != null and player is Node3D and snapshot.player_position.size() >= 3:
		(player as Node3D).global_position = Vector3(
			snapshot.player_position[0],
			snapshot.player_position[1],
			snapshot.player_position[2],
		)
	last_saved_snapshot = snapshot
	_is_reloading = false
	print("PLAYABLE SHIP LOADED sequence=%d position=(%.2f,%.2f,%.2f)" % [
		current_objective_sequence,
		snapshot.player_position[0],
		snapshot.player_position[1],
		snapshot.player_position[2],
	])
	return true

## SettingsState is the single source of truth for captions (ADR-0044).
## Called after audio_summary restore because a pre-unification save can
## carry a divergent router flag (the panel checkbox never worked before
## the unification, so the two summaries were written independently).
func _reconcile_captions_with_settings() -> void:
	if not is_instance_valid(audio_manager) or not is_instance_valid(menu_coordinator):
		return
	if audio_manager.sfx_router == null:
		return
	audio_manager.sfx_router.captions_enabled = menu_coordinator.settings_state.is_captions_enabled()

## ADR-0031/0043 slot-screen seam: apply a manual-slot RunSnapshot onto the
## currently-active (already-booted) ship only. Does NOT touch
## visited_ships/world_time/dock topology/current_location -- manual slots
## are ship-only side-saves, exactly ADR-0031's original text. Returns
## true on success; false on a null snapshot or an _apply_run_snapshot
## failure (e.g. not yet playable_started).
func apply_manual_slot(snapshot: RunSnapshot) -> bool:
	if snapshot == null:
		return false
	# ADR-0043 review fix: the menu dispatch block (and this call) is reachable
	# post-death (slice_complete==true) because epitaph/menu browsing must
	# survive death by design. A manual slot from a PRIOR run can still be
	# loadable here (extraction only deletes autosaves, never manual slots),
	# which would let _apply_run_snapshot "succeed" into a permanently dead
	# session (_process and gameplay input both no-op forever after death).
	# _apply_run_snapshot itself is a shared reload primitive whose other
	# caller (_apply_world_snapshot / request_load) is already reachable only
	# from pre-death input, so the guard belongs here, not there.
	if slice_complete:
		return false
	var applied: bool = _apply_run_snapshot(snapshot)
	if applied and is_instance_valid(menu_coordinator):
		menu_coordinator.trigger_tutorial("manual_slot_loaded", "any")
	return applied

## ADR-0043: notices a slot-screen confirm result surfaced through
## MenuCoordinator.get_last_meta_screen_confirm_result() and applies the
## gameplay-side consequence the coordinator itself cannot (it owns no
## gameplay state). Called every frame handle_ui_input returns true; a
## non-save_load or action=="none"/"arm"/"delete_armed" result is a no-op.
## Clears the coordinator's stored result after handling so a later
## handle_ui_input==true call (e.g. for ui_pause) never re-applies a stale
## confirm Dictionary from a previous, unrelated event.
func _dispatch_save_load_confirm_result(result: Dictionary) -> void:
	if str(result.get("screen", "")) != "save_load":
		return
	var action: String = str(result.get("action", ""))
	var ok: bool = bool(result.get("ok", false))
	if action == "load" and ok:
		var snapshot: RunSnapshot = result.get("snapshot", null) as RunSnapshot
		apply_manual_slot(snapshot)
	elif action == "load_world" and ok:
		# PR #57 Codex P2 (world-row Load): world.json is a WorldSnapshot, not
		# a RunSnapshot, so menu_coordinator cannot decode/apply it itself (no
		# gameplay state there). Route through the same proven world-apply
		# path F9 and the title screen's Continue already use.
		request_load()
	# action == "save": no bookkeeping needed here. save_to_slot() already
	# stamped _run_id onto the manual slot's payload and index row inside
	# SaveLoadService (run_id slot-ownership rework) -- freeze_run(_run_id)
	# finds it via the index the same way it finds world/autosave rows, so
	# a manual save never needs a coordinator-side tracked set to freeze
	# correctly, and never risks claiming the shared world/autosave lineage
	# either (that is a structurally separate row).
	if not action.is_empty():
		menu_coordinator.clear_last_meta_screen_confirm_result()

## Builds a full WorldSnapshot from live state. The home-ship slice is the
## existing RunSnapshot; when the player is aboard a derelict the home slice's
## player_position is overridden with the position they left home from (the live
## player position belongs to the derelict and is stored separately). Each
## retained ShipInstance contributes its own slice; current_location names the
## active ship.
func _build_world_snapshot():
	_sync_current_ship_combat_summary()
	_sync_current_ship_arc_summary()
	var ws = WorldSnapshotScript.new()
	if synaptic_sea_world != null:
		ws.world_summary = synaptic_sea_world.get_summary()
	if meta_progression_state != null:
		ws.meta_progression_summary = meta_progression_state.to_dict()
	if unique_item_state != null:
		ws.unique_item_summary = unique_item_state.get_summary()
	var home_snap = _build_run_snapshot(away_from_start)
	if home_snap != null:
		if away_from_start:
			home_snap.player_position = [_home_player_position.x, _home_player_position.y, _home_player_position.z]
		ws.home_ship = home_snap.to_dict()
	# The home ship's loot-search state rides the WorldSnapshot (RunSnapshot does not
	# carry it). Without this, the #4 home loot-lift would respawn the starting
	# containers unsearched after a fresh-process load → starter-part duplication.
	if home_ship != null:
		ws.home_looted_containers = home_ship.looted_container_ids.duplicate()
		ws.home_ship_inventory = home_ship.get_inventory().get_summary()
		var home_cart_dicts: Array = []
		for c in home_ship.get_carts():
			home_cart_dicts.append(c.get_summary())
		ws.home_ship_carts = home_cart_dicts
	if equipment_state != null:
		ws.player_equipment = equipment_state.get_summary()
	ws.visited_ships = {}
	for mid in visited_ships:
		ws.visited_ships[String(mid)] = visited_ships[mid].get_summary()
	ws.current_location = String(current_ship.marker_id) if current_ship != null else ""
	ws.world_time = world_time
	if player != null and player is Node3D:
		var p: Vector3 = (player as Node3D).global_position
		ws.player_position_in_ship = [p.x, p.y, p.z]
	ws.dock_edges = _current_dock_edges()
	ws.piloted_ship_id = piloted_ship.ship_id if piloted_ship != null else ""
	ws.aboard_ship_id = current_occupancy.ship_id if current_occupancy != null else ""
	ws.opened_ports = _opened_port_marker_ids()
	# Tranche 6 (REQ-RL-006): demo builds do not persist cross-run world state.
	# PR #68 review (Codex P2): the kept set must cover every ship the snapshot
	# still REFERENCES — the currently-boarded ship (same-run away-saves stay
	# restorable) plus anything named by piloted_ship_id / aboard_ship_id / the
	# dock edges (edge shape: host = marker_id, mobile = ship_id) — otherwise a
	# claimed mobile derelict docked to a host is unreconstructable in
	# _apply_docking_snapshot after a demo load. Runs AFTER those fields are
	# stamped so the keep set derives from the snapshot's own references.
	if demo_scope_gate != null and demo_scope_gate.is_blocked("world_persistence.cross_run"):
		var keep_markers: Dictionary = {}
		var keep_ship_ids: Dictionary = {}
		if away_from_start and current_ship != null:
			keep_markers[String(current_ship.marker_id)] = true
		if String(ws.piloted_ship_id) != "":
			keep_ship_ids[String(ws.piloted_ship_id)] = true
		if String(ws.aboard_ship_id) != "":
			keep_ship_ids[String(ws.aboard_ship_id)] = true
		for edge_v in ws.dock_edges:
			if typeof(edge_v) != TYPE_DICTIONARY:
				continue
			var edge_host: String = String((edge_v as Dictionary).get("host", ""))
			var edge_mobile: String = String((edge_v as Dictionary).get("mobile", ""))
			if not edge_host.is_empty():
				keep_markers[edge_host] = true
			if not edge_mobile.is_empty():
				keep_ship_ids[edge_mobile] = true
		var demo_kept: Dictionary = {}
		for kept_mid in ws.visited_ships:
			var summ_v: Variant = ws.visited_ships[kept_mid]
			var summ_ship_id: String = ""
			if summ_v is Dictionary:
				summ_ship_id = String((summ_v as Dictionary).get("ship_id", ""))
			if keep_markers.has(String(kept_mid)) \
					or (not summ_ship_id.is_empty() and keep_ship_ids.has(summ_ship_id)):
				demo_kept[String(kept_mid)] = summ_v
		ws.visited_ships = demo_kept
	# run_id slot-ownership rework: stamp this run's identity onto the
	# snapshot directly (SaveLoadService.save_world() also stamps it from
	# _active_run_id right before writing, but setting it here keeps
	# _build_world_snapshot()'s output self-consistent for any caller that
	# inspects the snapshot before it reaches the service, e.g. validation).
	ws.run_id = _run_id
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = Time.get_datetime_string_from_system(true)
	return ws

## Returns the current dock-edge set as a serialisable Array.
## Each entry is {host: String, mobile: String, port_type: String}.
## Emits an edge for EVERY known ship that has a parent_ship (de-duped), so the
## lifeboat->claimed-derelict edge persists when the player pilots a derelict.
func _current_dock_edges() -> Array:
	var edges: Array = []
	var seen: Dictionary = {}
	for inst in _all_known_ships():
		if inst == null or inst.parent_ship == null:
			continue
		var key: String = "%s>%s" % [String(inst.ship_id), String(inst.parent_ship.marker_id)]
		if seen.has(key):
			continue
		seen[key] = true
		# A child is a HANGAR edge iff its parent's bay holds it in a slot; else airlock.
		var port_type: String = "airlock"
		var slot_index: int = -1
		var parent = inst.parent_ship
		if parent.hangar != null:
			var s: int = parent.hangar.slot_of(String(inst.ship_id))
			if s != -1:
				port_type = "hangar"
				slot_index = s
		edges.append({
			"host": String(parent.marker_id),
			"mobile": String(inst.ship_id),
			"port_type": port_type,
			"slot_index": slot_index,
		})
	return edges

## Every ShipInstance the coordinator currently tracks (home, lifeboat, current,
## and all visited), de-duplicated.
func _all_known_ships() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for inst in [home_ship, lifeboat_ship, current_ship]:
		if inst != null and not seen.has(inst):
			seen[inst] = true
			out.append(inst)
	for mid in visited_ships:
		var inst = visited_ships[mid]
		if inst != null and not seen.has(inst):
			seen[inst] = true
			out.append(inst)
	return out

## Returns the marker_ids of every dock barrier that is currently opened.
func _opened_port_marker_ids() -> Array:
	var out: Array = []
	for b in dock_barriers:
		if is_instance_valid(b) and b.opened:
			out.append(String(b.marker_id))
	return out

## Task 7 validation seam: the live dock-edge set (same shape _build_world_snapshot saves).
func current_dock_edges_for_validation() -> Array:
	return _current_dock_edges()

## Task 7 validation seam: true iff the restored barrier for the given marker_id is opened.
func restored_port_opened_for_validation(marker_id: String) -> bool:
	for b in dock_barriers:
		if is_instance_valid(b) and String(b.marker_id) == marker_id:
			return b.opened
	return false

## Task 7 validation seam: calls request_save() (world save) and returns its result.
func save_world_for_validation() -> bool:
	return request_save()

## Task 7 validation seam: calls request_load() (world load) and returns its result.
func load_world_for_validation() -> bool:
	return request_load()

## Regenerates a derelict's geometry from its retained blueprint, makes it the
## active ship (re-applying its persisted systems state is implicit — the
## ShipInstance already holds it), and re-homes the player at pos_in_ship.
func _activate_derelict_from_instance(inst, pos_in_ship: Array) -> bool:
	if inst == null or ship_generator == null:
		return false
	# Rebuild from this derelict's OWN seed/size/condition so a save-reload reproduces
	# its injected encounters + biome/difficulty stamps (not empty / a stale marker's).
	_apply_run_context_from_blueprint(inst.blueprint)
	var new_root: Node3D = ship_generator.generate(inst.blueprint)
	if new_root == null:
		return false
	_attach_derelict_active(inst, new_root)
	_configure_threat_runtime_for_current_ship()
	if player != null and player is Node3D and pos_in_ship.size() >= 3:
		(player as Node3D).global_position = Vector3(float(pos_in_ship[0]), float(pos_in_ship[1]), float(pos_in_ship[2]))
	return true

## Regenerates geometry (scene_root + bridge terminal) for a derelict ShipInstance
## that is co-present but NOT the active current_ship — e.g. a claimed derelict the
## player was PILOTING while docked to a different host (after rigid-pair travel). The
## current_location-driven rebuild (_activate_derelict_from_instance) only materializes
## the active host, so without this such a mobile endpoint would reload with
## scene_root == null and the saved dock edge could not be re-established. (Codex P2)
## No-op for home/lifeboat (marker_id "") and for ships that already have geometry.
## Positions at DERELICT_DOCK_OFFSET; _apply_docking_snapshot then re-docks it flush.
func _ensure_derelict_geometry(inst) -> void:
	if inst == null or ship_generator == null:
		return
	if String(inst.marker_id) == "" or is_instance_valid(inst.scene_root):
		return
	# Regenerate from this derelict's OWN context (see _apply_run_context_from_blueprint).
	_apply_run_context_from_blueprint(inst.blueprint)
	var new_root: Node3D = ship_generator.generate(inst.blueprint)
	if new_root == null:
		return
	inst.scene_root = new_root
	add_child(new_root)
	(new_root as Node3D).position = DERELICT_DOCK_OFFSET
	if inst.built_layout.is_empty() and new_root.has_method("get_layout_copy"):
		inst.built_layout = new_root.get_layout_copy()
	_spawn_bridge_terminal(inst)
	_spawn_hangar_control(inst)
	_spawn_cargo_hold_control(inst)
	_spawn_cart_controls_for_ship(inst)

## Applies a WorldSnapshot: rebuilds the home ship first (this resets the runtime
## and returns to home if currently away), restores the SynapticSeaWorld and the
## visited-ships registry, then re-activates the saved derelict if the snapshot
## was taken aboard one. Returns false on any hard failure.
func _apply_world_snapshot(ws) -> bool:
	if ws == null:
		return false
	# 1. Home ship via the existing single-ship reload path. Reconstruct a
	#    RunSnapshot object from the embedded dict (version-gated like a disk load).
	var home_snap = RunSnapshotScript.from_dict(ws.home_ship, SaveLoadServiceScript.CURRENT_SLICE_VERSION, Engine.get_version_info()["string"])
	if home_snap == null:
		push_warning("PlayableGeneratedShip: world load rejected — embedded home slice incompatible")
		return false
	# Restore the home-departure position. On an away-save the home slice's
	# player_position holds where the player left home from (see _build_world_snapshot);
	# without copying it back, a later travel_home() after a fresh process would
	# teleport the player to the origin instead of their saved home position.
	if home_snap.player_position.size() >= 3:
		_home_player_position = Vector3(home_snap.player_position[0], home_snap.player_position[1], home_snap.player_position[2])
	if not _apply_run_snapshot(home_snap):
		return false
	# 1b. Restore the home ship's loot-search state and rebuild its containers so
	#     already-searched starting containers read as searched (prevents starter-part
	#     re-loot after a fresh-process load). We are home here (the reload reset us),
	#     so current_ship == home_ship and _build_loot_containers targets the home ship.
	if home_ship != null:
		home_ship.looted_container_ids = ws.home_looted_containers.duplicate()
		if not ws.home_ship_inventory.is_empty():
			home_ship.get_inventory().apply_summary(ws.home_ship_inventory)
		# Restore home-ship carts BEFORE spawning their controls so the CartStates
		# are in place when _spawn_cart_controls_for_ship iterates them.
		home_ship.get_carts().clear()
		for cd in ws.home_ship_carts:
			if typeof(cd) == TYPE_DICTIONARY:
				var cart = CartStateScript.create()
				cart.apply_summary(cd as Dictionary)
				home_ship.get_carts().append(cart)
		_spawn_cart_controls_for_ship(home_ship)
		if not away_from_start:
			_build_loot_containers()
			_build_sealed_hatches()
	# 1c. Restore player equipment (player-global — runs regardless of home_ship branch).
	#     Loading restores the EXACT saved state: a non-empty snapshot is applied; an EMPTY
	#     snapshot (older save, or nothing was worn) clears any currently-worn gear so
	#     pre-load equipment never leaks across a load (_reset_runtime_for_reload does not
	#     touch equipment_state).
	if equipment_state != null:
		if not ws.player_equipment.is_empty():
			equipment_state.apply_summary(ws.player_equipment)
			# Legacy-save reconciliation (PR #62): apply_summary restores slot
			# ids blindly. An id that no longer declares an equip slot (e.g.
			# capacitor_cell, demoted from equip item to pure ammo) is moved
			# back to inventory instead of squatting in the slot.
			for slot in equipment_state.slots.keys():
				var equipped_id: String = str(equipment_state.slots[slot])
				if equipped_id != "" and not equipment_state.can_equip(equipped_id):
					equipment_state.unequip(String(slot))
					if inventory_state != null:
						inventory_state.add_item(equipped_id, 1)
		else:
			equipment_state.slots.clear()
	_recompute_player_encumbrance()
	if meta_progression_state != null and not ws.meta_progression_summary.is_empty():
		meta_progression_state.apply_summary(ws.meta_progression_summary)
	if unique_item_state != null:
		unique_item_state.apply_summary(ws.unique_item_summary)
	# 2. World model. _apply_run_snapshot reset us to the home ship; home_ship is
	#    re-wrapped by _on_ship_loaded during that reload.
	if synaptic_sea_world != null and not ws.world_summary.is_empty():
		synaptic_sea_world.apply_summary(ws.world_summary)
	# 3. Rebuild the retained-derelict registry from the slices.
	visited_ships.clear()
	for mid in ws.visited_ships:
		var inst = ShipInstanceScript.create("", "", ShipBlueprintScript.new(), null, null)
		if inst.apply_summary(ws.visited_ships[mid]):
			visited_ships[String(mid)] = inst
	world_time = float(ws.world_time)  # Live Persistent Ships Phase 1 (additive; 0.0 default for older saves)
	# 4. If saved aboard a derelict, re-activate it.
	if String(ws.current_location) != "":
		var active = visited_ships.get(String(ws.current_location), null)
		if active == null:
			push_warning("PlayableGeneratedShip: world load — current_location '%s' missing from visited_ships" % String(ws.current_location))
			return true  # home is already correctly restored; treat as on-home
		if not _activate_derelict_from_instance(active, ws.player_position_in_ship):
			push_warning("PlayableGeneratedShip: world load — failed to re-activate derelict '%s'" % String(ws.current_location))
			return true
	# 5. Restore opened-port flags (Task 7: dock-edge persistence).
	# After ships are rebuilt and barriers spawned (step 4 / _attach_derelict_active),
	# re-open any barriers that were opened at save time. This is not cosmetic: a host
	# whose barrier is closed is non-boardable (_ship_boardable returns false), so a
	# previously-breached derelict would become unboardable after load without this.
	for b in dock_barriers:
		if is_instance_valid(b) and ws.opened_ports.has(String(b.marker_id)):
			b.set_opened(true)
	# run_id restore happens in request_load() (the caller that has ws in
	# scope for the Continue/F9 path) -- not here, so there is exactly one
	# site that decides _run_id after a load.
	# 5c. Ensure every derelict that is an endpoint of a saved dock edge has geometry
	# BEFORE re-docking. Step 4 only materializes current_location; a claimed derelict the
	# player was PILOTING (docked to a different host after rigid-pair travel) is otherwise
	# restored data-only (scene_root == null), which would leave piloted_ship geometry-less
	# and the L->D / D->host edges undockable. (Codex P2) Idempotent: _ensure_derelict_geometry
	# skips home/lifeboat and ships that already have geometry.
	for edge_v in ws.dock_edges:
		if typeof(edge_v) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_v
		_ensure_derelict_geometry(_find_ship_by_id(String(edge.get("mobile", ""))))
		_ensure_derelict_geometry(_find_ship_by_id_or_marker(String(edge.get("host", ""))))
	# 6. Re-apply the persisted docking snapshot (piloted pointer + dock-edge set +
	# occupancy). This is the general N-ship persistence mechanism: the dock edges are
	# the source of truth, not the implicit current_location-driven rebuild. Idempotent
	# (a no-op confirm when step 4 already re-docked 5b's single mobile ship).
	_apply_docking_snapshot(ws)
	return true

## Restores the piloted pointer, dock-edge set, and occupancy from the snapshot
## (the general N-ship persistence mechanism). Idempotent: confirms/re-applies the
## edge the current_location-driven rebuild already established for 5b's single ship.
## Consumes ws.piloted_ship_id, ws.dock_edges, ws.aboard_ship_id — every saved
## docking field is read here so persistence is genuine, not implicit.
func _apply_docking_snapshot(ws) -> void:
	# Piloted pointer (today the lifeboat; resolved by ship_id so it generalizes to N ships).
	if String(ws.piloted_ship_id) != "":
		var p = _find_ship_by_id(String(ws.piloted_ship_id))
		if p != null:
			piloted_ship = p
	# Dock-edge set: ensure each mobile ship is docked to the host named in the snapshot.
	# Edge shape (see _current_dock_edges): host = host.marker_id, mobile = mobile.ship_id.
	for edge_v in ws.dock_edges:
		if typeof(edge_v) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_v
		var mobile = _find_ship_by_id(String(edge.get("mobile", "")))
		var host = _find_ship_by_id_or_marker(String(edge.get("host", "")))
		if mobile == null or host == null:
			continue
		if str(edge.get("port_type", "airlock")) == "hangar":
			# Hangar edge: re-peg the carrier's bay + place at slot anchor. Do NOT run
			# the airlock port-alignment (_dock_piloted_to) — bayed ships sit at slots.
			_redock_bayed(mobile, host, int(edge.get("slot_index", -1)))
		elif mobile.parent_ship != host:
			# Re-establish only when the rebuild did not already dock this edge (idempotent).
			# _dock_piloted_to reads the module-level piloted_ship, so swap it for the move.
			var saved_piloted = piloted_ship
			piloted_ship = mobile
			_dock_piloted_to(host)
			piloted_ship = saved_piloted
	# Occupancy: restore the ship the player was aboard (by ship_id). Leave as set by
	# _attach_derelict_active when the id does not resolve. Do NOT call
	# recompute_occupancy() here — that breaks world_save_anywhere (player's saved world
	# position may resolve to a different ship than the one they were logically aboard).
	if String(ws.aboard_ship_id) != "":
		var a = _find_ship_by_id(String(ws.aboard_ship_id))
		if a != null:
			current_occupancy = a

## Restores a hangar edge: re-pegs the carrier's bay slot, re-establishes the
## parent/child link, and places the bayed ship at its slot anchor. Configures the
## carrier's bay from its layout first so slot_count/size exist after a fresh load.
func _redock_bayed(mobile, host, slot_index: int) -> void:
	if mobile == null or host == null:
		return
	if not is_instance_valid(mobile.scene_root) or not is_instance_valid(host.scene_root):
		return
	_configure_bay_from_layout(host)
	var bay = host.get_hangar()
	if slot_index >= 0 and slot_index < bay.slots.size():
		bay.slots[slot_index] = String(mobile.ship_id)
	else:
		slot_index = bay.dock(String(mobile.ship_id), _ship_dock_size_class(mobile))
	mobile.parent_ship = host
	if not host.docked_ships.has(mobile):
		host.docked_ships.append(mobile)
	_place_in_slot(host, mobile, slot_index)

## Resolves a ShipInstance by its ship_id across home/lifeboat/active/visited registries.
func _find_ship_by_id(id: String):
	if id == "":
		return null
	if home_ship != null and String(home_ship.ship_id) == id: return home_ship
	if lifeboat_ship != null and String(lifeboat_ship.ship_id) == id: return lifeboat_ship
	if current_ship != null and String(current_ship.ship_id) == id: return current_ship
	for mid in visited_ships:
		if String((visited_ships[mid]).ship_id) == id: return visited_ships[mid]
	return null

## Resolves a dock host. Edges store the host's marker_id ("" = home), so match on
## marker_id first, then fall back to ship_id lookup.
func _find_ship_by_id_or_marker(key: String):
	if key == "" and home_ship != null: return home_ship
	if current_ship != null and String(current_ship.marker_id) == key: return current_ship
	if home_ship != null and String(home_ship.marker_id) == key: return home_ship
	for mid in visited_ships:
		if String((visited_ships[mid]).marker_id) == key: return visited_ships[mid]
	return _find_ship_by_id(key)

func _build_loot_context(spec: Dictionary) -> Dictionary:
	return {
		"biome_id": _resolve_current_loot_biome_id(),
		"loot_quality_modifier": _resolve_current_loot_quality_modifier(),
		"depth": _resolve_current_loot_depth(),
		"condition": _resolve_current_loot_condition(),
		"container_kind": str(spec.get("kind", spec.get("loot_table", "generic_crate"))),
		"item_definitions": ItemDefsScript.load_definitions(),
		"unique_state": unique_item_state,
	}

func _resolve_current_loot_quality_modifier() -> float:
	var biome_id: String = _resolve_current_loot_biome_id()
	if biome_id.is_empty():
		return 1.0
	var rel_path: String = "res://data/procgen/biomes/" + biome_id + ".json"
	if FileAccess.file_exists(rel_path):
		var text: String = FileAccess.get_file_as_string(rel_path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			var biome_obj = BiomeProfileScript.from_dict(parsed as Dictionary)
			if biome_obj != null:
				return float(biome_obj.loot_quality_modifier)
	# Fall back to the same built-in dict table used by ShipLayoutGenerator._resolve_biome()
	match biome_id:
		"breach_field":
			return 1.1
		"dead_fleet":
			return 1.4
		_:
			return 1.0


func _resolve_current_loot_biome_id() -> String:
	var biome_ids: Array[String] = _loot_biome_ids()
	if biome_ids.is_empty():
		return "abyssal_synaptic_sea"
	var seed_value: int = 0
	if current_ship != null and current_ship.blueprint != null:
		seed_value = int(current_ship.blueprint.seed_value)
	return BiomeProfileScript.select_biome(seed_value, biome_ids)

## Resolves the deterministic {biome, difficulty} a derelict should be generated
## with from its seed/size/condition. Biome reuses the same seed->biome selector as
## the loot path; difficulty is depth-banded. Shared by the marker-driven travel
## path and the blueprint-driven rebuild paths so a derelict ALWAYS regenerates from
## its OWN context — never a stale last-traveled one.
func _resolve_run_context(seed_value: int, size: int, condition: int) -> Dictionary:
	var biome: String = "abyssal_synaptic_sea"
	var biome_ids: Array[String] = _loot_biome_ids()
	if not biome_ids.is_empty():
		biome = BiomeProfileScript.select_biome(seed_value, biome_ids)
	return {"biome": biome, "difficulty": _difficulty_id_for_depth(size * 2 + condition)}

## Deterministic difficulty band. depth = size * 2 + condition: 0-2 standard,
## 3-4 hardened, 5+ deep_dive. Ids match data/procgen/difficulty/*.json
## (ShipLayoutGenerator falls back to built-in defaults for these three ids even if
## a file is absent). Tunable.
func _difficulty_id_for_depth(depth: int) -> String:
	if depth >= 5:
		return "deep_dive"
	if depth >= 3:
		return "hardened"
	return "standard"

## Marker wrapper — the travel + scanner-preview paths address derelicts by marker.
func _resolve_derelict_run_context(marker) -> Dictionary:
	if marker == null:
		return {"biome": "abyssal_synaptic_sea", "difficulty": "standard"}
	return _resolve_run_context(int(marker.seed_value), int(marker.size_class), int(marker.condition))

## Applies a derelict's OWN run context to the generator before a blueprint-driven
## rebuild (save-reload via _activate_derelict_from_instance, geometry regen via
## _ensure_derelict_geometry). Without this the generator's mutable biome/difficulty
## fields are empty on a fresh load (losing encounter injection + stamps) or stale
## from the last traveled marker (wrong biome/difficulty) — see the rebuild sites.
func _apply_run_context_from_blueprint(blueprint) -> void:
	if ship_generator == null:
		return
	if blueprint == null:
		ship_generator.configure_run_context("", "")
		return
	var ctx: Dictionary = _resolve_run_context(int(blueprint.seed_value), int(blueprint.size), int(blueprint.condition))
	ship_generator.configure_run_context(str(ctx.get("biome", "")), str(ctx.get("difficulty", "")))

func _resolve_current_loot_depth() -> int:
	if current_ship == null or current_ship.blueprint == null:
		return 0
	var blueprint = current_ship.blueprint
	return maxi(0, int(blueprint.size) * 2 + int(blueprint.condition) + (1 if away_from_start else 0))

func _resolve_current_loot_condition() -> String:
	if current_ship == null or current_ship.blueprint == null:
		return "damaged"
	match int(current_ship.blueprint.condition):
		0:
			return "pristine"
		1:
			return "damaged"
		_:
			return "wrecked"

func _loot_biome_ids() -> Array[String]:
	if not _loot_biome_ids_cache.is_empty():
		return _loot_biome_ids_cache
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/items/biome_definitions.json"))
	if parsed is Dictionary:
		var biomes_v: Variant = (parsed as Dictionary).get("biomes", {})
		if biomes_v is Dictionary:
			for biome_id in (biomes_v as Dictionary).keys():
				_loot_biome_ids_cache.append(String(biome_id))
	_loot_biome_ids_cache.sort()
	if _loot_biome_ids_cache.is_empty():
		_loot_biome_ids_cache.append("abyssal_synaptic_sea")
	return _loot_biome_ids_cache

func _postprocess_loot_grants(granted: Array, source_id: String, source: Node3D = null) -> void:
	if granted.is_empty():
		_last_loot_feedback_line = "Loot: %s empty" % source_id
		return
	for entry in granted:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item_id: String = str((entry as Dictionary).get("item_id", ""))
		var unique_id: String = str((entry as Dictionary).get("unique_id", ""))
		var seed_key: String = str((entry as Dictionary).get("seed_key", ""))
		var codex_entry_id: String = str((entry as Dictionary).get("codex_entry_id", ""))
		if unique_item_state != null and not unique_id.is_empty():
			unique_item_state.claim(unique_id, seed_key, codex_entry_id)
		elif unique_item_state != null and not codex_entry_id.is_empty():
			unique_item_state.record_codex_unlock(codex_entry_id)
		if meta_progression_state != null and not codex_entry_id.is_empty():
			meta_progression_state.unlock_codex_entry(codex_entry_id)
		if equipment_state != null and item_id != "" and equipment_state.can_equip(item_id):
			_equip_from_inventory(item_id, true)
		# Domain 10 (ADR-0045) Source A: a found web_chart imports every currently
		# in-range world marker at detail 2 (position + ship_type), the "paper map"
		# import. Idempotent (record_views never downgrades), so repeat pickups are
		# harmless -- no first-pickup tracking is needed. Deterministic, no RNG.
		if item_id == "web_chart" and is_instance_valid(synaptic_sea_world):
			var scan_range: float = scanner_state.range_radius if scanner_state != null else 250.0
			var import_views: Array = []
			for m in synaptic_sea_world.markers_in_range(scan_range):
				import_views.append({
					"marker_id": m.marker_id,
					"position": [m.position.x, m.position.y, m.position.z],
					"distance": m.position.distance_to(synaptic_sea_world.player_position),
					"size_class": m.size_class,
					"ship_type": m.ship_type,
				})
			web_chart_state.record_views(import_views, 2)
	var first: Dictionary = granted[0] as Dictionary
	var rarity_text: String = RarityTierScript.label(str(first.get("rarity", "common")))
	_last_loot_feedback_line = "Loot: %s x%d [%s]" % [
		ItemDefsScript.display_name(ItemDefsScript.load_definitions(), str(first.get("item_id", ""))),
		int(first.get("quantity", 0)),
		rarity_text,
	]
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		# Emit at the source container's world position when known (spatial
		# pickup audio, REQ-AU-005); fall back to the non-spatial bus path.
		if is_instance_valid(source) and source.is_inside_tree():
			audio_manager.play_sfx(AudioEventSeamScript.SFX_TOOL_PICKUP, source.global_position)
		else:
			audio_manager.play_sfx(AudioEventSeamScript.SFX_TOOL_PICKUP)

## Tear down every runtime child so a fresh load can rebuild the slice
## cleanly. Mirrors the setup done by _build_runtime_nodes() and the
## various _build_*_zone helpers, but in reverse.
func _reset_runtime_for_reload() -> void:
	# REQ-012 fix: if the player is aboard a traveled derelict when a reload is
	# triggered, we must return to the starting ship BEFORE rebuilding the slice.
	# Without this block:
	#   - away_from_start stays true → _process returns forever (sim wedged)
	#   - current_ship still points at the stale derelict → _on_ship_loaded's
	#     `if current_ship == null` guard is false → the reloaded starting ship
	#     is never wrapped as current_ship
	#   - the derelict root remains a child of this coordinator → leaked scene
	# Phase 5a Task 5 (co-presence) changes: the home hull and its gameplay
	# roots are NEVER detached, so there is no "loader off-tree" or
	# "gameplay roots off-tree" to re-attach here. Only the DERELICT root
	# must be freed. _reattach_starting_gameplay_roots() is removed.
	if away_from_start:
		# Free EVERY co-present derelict root, not just current_ship's. 5c: the player may be
		# piloting a CLAIMED derelict that is docked to a DIFFERENT host, so the piloted
		# derelict's root is a separate child of this coordinator — freeing only current_ship
		# would orphan it (leaked scene + "resources still in use at exit"). Home/lifeboat
		# roots (marker_id "") are intentionally NOT freed here: the home hull stays co-present,
		# and the lifeboat is rebuilt (and its prior root freed) by _build_lifeboat_at_home.
		# queue_free defers destruction to end-of-frame so physics/nav resources unregister
		# cleanly; the reload's slice rebuild replaces the ShipInstances afterward.
		for inst in _all_known_ships():
			if inst == null or String(inst.marker_id) == "":
				continue
			var droot = inst.scene_root
			if droot != null and is_instance_valid(droot):
				if droot.get_parent() == self:
					remove_child(droot)
				droot.queue_free()
			inst.scene_root = null
		# Break dock-relationship cycles (parent_ship <-> docked_ships) among the old
		# ShipInstances. RefCounted has no cycle collector, so once the reload's slice
		# rebuild (visited_ships.clear()) and the lifeboat rebuild drop their dict/var
		# references, a surviving D<->host cycle would keep the old instances and their
		# sub-states alive — leaked RefCounted at exit. The reload re-establishes the
		# dock graph from the snapshot, so severing it here is safe.
		for inst in _all_known_ships():
			if inst != null:
				inst.parent_ship = null
				inst.docked_ships = []
				# 5d: clear bay slots too. A stale occupant id left in the home/lifeboat
				# bay would desync the reload's slot re-peg (and keep a freed ship_id
				# pinned). The reload re-pegs occupancy from the snapshot edges.
				if inst.hangar != null:
					for i in range(inst.hangar.slots.size()):
						inst.hangar.slots[i] = ""
		# Co-presence: home hull / loader / gameplay roots were never detached —
		# no re-attach needed here (contrast with old single-active model).
		away_from_start = false
		# Domain 10 Task 5 fix wave 2 (re-review): third away_from_start=false
		# transition — reload-while-away. Same stale-focus-cache root cause as the
		# board/unboard sites: reset the subject cache and force-clear the tooltip
		# panel so a same-typed interactable after reload is not suppressed.
		_last_tooltip_focus_subject_id = ""
		if is_instance_valid(menu_coordinator):
			menu_coordinator.set_tooltip_query({"subject_kind": "interactable", "subject_id": ""})
		# Phase 5a Task 6: keep occupancy in lockstep — reload returns to the home
		# ship (home hull is never detached under co-presence, so home_ship is valid).
		current_occupancy = home_ship
		# Sub-project #2 (I1): free the prior derelict's objective interactables on
		# reload. _build_derelict_objectives (the only other caller of
		# _clear_derelict_objectives) does not run on a reload-into-home path
		# (_apply_world_snapshot skips re-activation when current_location == ""),
		# so without this the Area3D interactables stay orphaned under
		# derelict_objective_root (or the freed scene_root in the co-presence
		# model), overlaying the home ship. Harmless on the reload-into-derelict
		# path (_build_derelict_objectives re-clears anyway).
		_clear_derelict_objectives()
		_clear_loot_containers()
		_clear_repair_points()
		_clear_breach_seal_points()
		_clear_sealed_hatches()
	# Allow _on_ship_loaded to re-wrap the freshly-reloaded starting ship on
	# every reload (home-save or away-save). Previously this was only inside
	# `if away_from_start` — but when saving at home current_ship was never
	# nulled, so _on_ship_loaded's `if current_ship == null` guard stayed false
	# and _build_lifeboat_at_home() was never called on reload-from-home.
	current_ship = null
	# Player first so the camera unfollows before the rig is freed.
	if player != null and is_instance_valid(player):
		player.queue_free()
		player = null
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.queue_free()
		camera_rig = null
	if interaction_root != null and is_instance_valid(interaction_root):
		for child in interaction_root.get_children():
			interaction_root.remove_child(child)
			child.queue_free()
	if affordance_root != null and is_instance_valid(affordance_root):
		for child in affordance_root.get_children():
			affordance_root.remove_child(child)
			child.queue_free()
	if route_control_root != null and is_instance_valid(route_control_root):
		for child in route_control_root.get_children():
			route_control_root.remove_child(child)
			child.queue_free()
	if oxygen_root != null and is_instance_valid(oxygen_root):
		for child in oxygen_root.get_children():
			oxygen_root.remove_child(child)
			child.queue_free()
	if tool_pickup_root != null and is_instance_valid(tool_pickup_root):
		for child in tool_pickup_root.get_children():
			tool_pickup_root.remove_child(child)
			child.queue_free()
	# ADR-0042: clear phantoms on reload teardown (a fresh manager is rebuilt in
	# _on_ship_loaded once the reloaded ship is active).
	if hallucination_manager != null and is_instance_valid(hallucination_manager):
		hallucination_manager.clear_all()
	_clear_fire_zones()
	# M7-B Task 9: manual extinguish nodes + recharge port share the fire teardown.
	_clear_fire_suppression_points()
	_clear_extinguisher_recharge_port()
	if arc_root != null and is_instance_valid(arc_root):
		for child in arc_root.get_children():
			arc_root.remove_child(child)
			child.queue_free()
	# Phase 5a Task 7: free the lifeboat scene_root on reload so _build_lifeboat_at_home()
	# can build a fresh one. The lifeboat is NOT freed during the away-branch above
	# (it is at home, not a traveled derelict), so it must be freed here unconditionally.
	if lifeboat_ship != null and lifeboat_ship.scene_root != null and is_instance_valid(lifeboat_ship.scene_root):
		var lb_root: Node3D = lifeboat_ship.scene_root as Node3D
		if lb_root != null and lb_root.get_parent() == self:
			remove_child(lb_root)
		lb_root.queue_free()
	# Break the home_ship ↔ lifeboat_ship RefCounted cycle before releasing our
	# reference. Without this, both ShipInstances keep each other alive via
	# parent_ship / docked_ships and their preloaded GDScript resources leak.
	if lifeboat_ship != null:
		lifeboat_ship.parent_ship = null
	if home_ship != null:
		home_ship.docked_ships.erase(lifeboat_ship)
	lifeboat_ship = null
	# Drop the stale piloted_ship handle so the reload path does not hold a freed
	# ShipInstance reference between teardown and the next _build_lifeboat_at_home.
	piloted_ship = null
	# Phase 5b Task 5: free any active dock-seam barriers (they are parented under a
	# host scene_root that may be freed on reload — clear the references to avoid a
	# stale/leaked Array entry).
	_clear_dock_barriers()
	_clear_bridge_terminals()
	_clear_hangar_controls()
	_clear_cargo_hold_controls()
	_clear_cart_controls()
	grabbed_cart = null
	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.queue_free()
	# REQ-014 blocking finding B: null the hud_layer and tracker
	# references so a subsequent _build_hud_layer() rebuild starts from
	# a clean slate. Without nulling tracker, _build_hud_layer would
	# overwrite the field but the old tracker Node would still be
	# parented to a freed CanvasLayer; without nulling hud_layer, the
	# helper's idempotent guard would re-free the same node twice.
	hud_layer = null
	tracker = null
	scanner_panel = null
	inventory_panel = null
	interactables.clear()
	sequence_interactables.clear()
	affordance_labels.clear()
	affordance_props.clear()
	route_gate_nodes.clear()
	# Sub-project #1: drop retained visited-derelict instances on reload. The
	# active derelict scene is already freed and current_ship nulled above; a
	# stale ShipInstance left in visited_ships would make a post-reload revisit
	# reuse pre-reload systems state instead of building a fresh condition-seeded
	# instance. home_ship is NOT cleared — _on_ship_loaded reassigns it.
	visited_ships.clear()
	objective_completion_count = 0
	slice_complete = false
	# Reset pure models so a fresh load starts from a clean state and
	# then has the snapshot re-applied.
	if ship_systems_manager != null:
		var bp_reset = _load_blueprint_for_systems()
		ship_systems_manager.configure(ship_systems_manager.load_definitions(), bp_reset.condition, bp_reset.seed_value)
		_apply_lifeboat_opening_damage()
	_configure_player_progression()
	completed_objective_types.clear()
	if route_control_state != null:
		route_control_state.configure_from_blocked_routes([])
	if oxygen_state != null:
		oxygen_state.configure({
			"zone_ids": [],
			"max_oxygen": OxygenStateScript.DEFAULT_MAX_OXYGEN,
			"drain_rate": OxygenStateScript.DEFAULT_DRAIN_RATE,
			"regen_rate": OxygenStateScript.DEFAULT_REGEN_RATE,
			"recovery_threshold": OxygenStateScript.DEFAULT_RECOVERY_THRESHOLD,
			"safe_threshold": OxygenStateScript.DEFAULT_SAFE_THRESHOLD,
		})
	if inventory_state != null:
		inventory_state.reset()
	# M7-B Task 7: reconfigure the authoritative fire model from tuning so a
	# reload starts with no burning compartments (configure() clears active_fires).
	# A reload-from-save then re-applies fire_suppression_summary over this.
	if fire_suppression_state != null:
		fire_suppression_state.configure(_load_json_dict(SHIP_SUBSYSTEM_TUNING_PATH).get("fire_suppression", {}))
	if electrical_arc_state != null:
		electrical_arc_state.configure({
			"zone_ids": [],
			"arcing_duration": ElectricalArcStateScript.DEFAULT_ARCING_DURATION,
			"discharged_duration": ElectricalArcStateScript.DEFAULT_DISCHARGED_DURATION,
		})
	# REQ-SV: reset survival vitals models on reload.
	if vitals_state != null:
		vitals_state.configure({})
	if sanity_state != null:
		sanity_state.configure({})
	if radiation_state != null:
		radiation_state.configure({})
	if body_temperature_state != null:
		body_temperature_state.configure({})
	if status_effects_state != null:
		status_effects_state.configure({})
	if objective_progress_state != null:
		objective_progress_state.reset()
	breach_zone_node = null
	unsafe_room_marker = null
	arc_zone_node = null
	arc_zone_label = null
	tool_pickup = null
	arc_zone_resolved_room_id = ""
	# REQ-014: drop the second ToolPickup reference so a fresh load
	# rebuilds it cleanly. The node itself is freed by the
	# tool_pickup_root teardown above.
	junction_calibrator_pickup = null
	# REQ-014: clear the per-sequence kind lookup so a reload reflects
	# the freshly-built interactable group, not the prior run's.
	sequence_kinds.clear()
	# Reset the timed autosave loop: the same PlayableGeneratedShip + AutosavePolicy
	# instances are reused across a reload, so a stale run-clock or event count would
	# carry over. Without this the loaded run's (lower) event count drives a negative
	# delta that blocks event autosaves, and the carried-over clock fires a redundant
	# autosave on the next tick. reset() reseeds the policy's counters/budget.
	_autosave_run_seconds = 0.0
	_last_autosave_result = {}
	if autosave_policy != null:
		autosave_policy.reset()
	# The loader's own load_from_paths() entry point calls
	# clear_loaded_ship() first, so re-driving it is safe without any
	# extra reset here.

## Menu-modal guard (Tranche 4, 2026-07-06 audit HIGH): true when no menu is
## open, so gameplay panel toggles (scanner / chart / inventory) may act.
## Without this, toggles stacked overlays on top of the pause/meta menu —
## menu_coordinator.handle_ui_input never saw those actions because each
## toggle block returns before the menu dispatch. Same guard family as the
## chart/scanner-vs-inventory mutual exclusion (commit 849b2d5).
func _menus_are_closed() -> bool:
	if not is_instance_valid(menu_coordinator):
		return true
	if menu_coordinator.menu_state == null:
		return true
	return menu_coordinator.menu_state.is_in_play()

func _input(event: InputEvent) -> void:
	if not playable_started:
		return
	# ADR-0043: slice_complete no longer hard-gates the whole function. Death
	# ends the run but must not lock the player out of the menu (epitaph
	# browsing on the frozen slot screen is the whole point of the freeze).
	# Only the gameplay-input tail below (hotbar/attack/reload/save/load) is
	# still gated on slice_complete -- see the "if slice_complete: return"
	# inserted right after the menu_coordinator dispatch block.
	# Phase 4.5: scanner panel toggle + navigation. Opening the panel freezes
	# player movement/interaction so the shared arrow/Enter keys drive the panel.
	# Control is restored on close by the panel_closed signal handler, which
	# covers every close path — not just toggle-close / confirm-success.
	if scanner_panel != null:
		if event.is_action_pressed("toggle_scanner") and _menus_are_closed() and (not is_instance_valid(inventory_panel) or not inventory_panel.is_open()):
			scanner_panel.toggle()
			if player != null and scanner_panel.is_open():
				player.set_physics_process(false)
				player.set_process_input(false)
				player.set_process_unhandled_input(false)
			get_viewport().set_input_as_handled()
			return
		if scanner_panel.is_open():
			if event.is_action_pressed("ui_down"):
				scanner_panel.move_selection(1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_up"):
				scanner_panel.move_selection(-1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_accept"):
				scanner_panel.confirm_selection()
				get_viewport().set_input_as_handled()
			return  # swallow other input while the scanner is open
	if is_instance_valid(chart_panel):
		if chart_panel.is_open():
			if event.is_action_pressed("ui_open_map") or event.is_action_pressed("ui_cancel"):
				chart_panel.close()
				get_viewport().set_input_as_handled()
			return  # swallow other input while the chart is open (read-only panel)
		if event.is_action_pressed("ui_open_map") and _menus_are_closed() and (not is_instance_valid(inventory_panel) or not inventory_panel.is_open()):
			var has_chart: bool = inventory_state != null and int(inventory_state.get_quantity("web_chart")) > 0
			if has_chart:
				chart_panel.open()
				_freeze_player_for_panel()
			else:
				# Domain 10 (ADR-0045): no chart possessed -- surface a HUD feedback
				# line via the existing system-status-lines seam (mirrors
				# _last_loot_feedback_line) rather than opening an empty panel.
				_last_loot_feedback_line = "No web chart"
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(inventory_panel):
		if inventory_panel.is_open():
			if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel"):
				inventory_panel.close()
				get_viewport().set_input_as_handled()
			return  # swallow other keys while the inventory panel is open (mouse drives it)
		if event.is_action_pressed("toggle_inventory") and _menus_are_closed():
			_open_inventory_self()
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(menu_coordinator):
		if menu_coordinator.handle_ui_input(event):
			_dispatch_save_load_confirm_result(menu_coordinator.get_last_meta_screen_confirm_result())
			get_viewport().set_input_as_handled()
			return
		for action_name in ["move_forward", "move_back", "move_left", "move_right"]:
			if event.is_action_pressed(action_name):
				menu_coordinator.trigger_tutorial("player_moved", "any")
				break
	# ADR-0043: everything below this point is live gameplay input (hotbar,
	# attack, reload, manual save/load keys) -- correctly still locked out
	# once the run has ended (death or extraction). Only the menu dispatch
	# above this line must survive slice_complete.
	if slice_complete:
		return
	if save_load_service == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_use_consumable_hotbar_slot(0)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_2:
			_use_consumable_hotbar_slot(1)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_3:
			_use_consumable_hotbar_slot(2)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("attack_primary"):
		_attack_with_equipped_weapon()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reload_weapon"):
		_begin_weapon_reload()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("save_run"):
		request_save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quicksave_run"):
		request_quicksave()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("load_run"):
		request_load()
		get_viewport().set_input_as_handled()

func use_inventory_item_for_validation(item_id: String, use_all: bool = false) -> Dictionary:
	return _use_consumable_item(item_id, use_all)

func assign_hotbar_slot_for_validation(slot_index: int, item_id: String) -> bool:
	if consumable_state == null:
		return false
	var ok: bool = consumable_state.assign_hotbar_slot(slot_index, item_id)
	if ok:
		_refresh_consumable_ui(slot_index)
	return ok

func use_hotbar_slot_for_validation(slot_index: int) -> Dictionary:
	return _use_consumable_hotbar_slot(slot_index)

## Phase 5b Task 6 validation seam: opens the first closed dock-seam barrier
## without requiring player proximity. Returns true if the barrier is now opened.
func open_active_dock_barrier_for_validation() -> bool:
	for b in dock_barriers:
		if is_instance_valid(b) and not b.opened:
			if b.condition == "broken":
				b.channeling = true
				b._scaled_seconds = 0.01
				b.advance_channel(100.0)
			else:
				b.set_opened(true)
				b.emit_signal("breach_opened", b.marker_id)
			return b.opened
	return false

## Phase 5b Task 6 validation seam: teleports the player to a room of current_ship
## that lies OUTSIDE the piloted ship's interior AABB (so occupancy resolves
## unambiguously to the host, not the overlapping docked lifeboat). Returns true on a
## genuine outside-room teleport; returns FALSE (without moving the player) when no such
## room exists (host entirely inside the lifeboat AABB — unexpected for a multi-room
## derelict) so the smoke fails honestly rather than asserting against an ambiguous point.
func board_host_for_validation() -> bool:
	if current_ship == null or player == null or not (player is Node3D):
		return false
	# Find a room of current_ship whose world position is outside the piloted ship's AABB.
	var lb_aabb: AABB = AABB()
	if piloted_ship != null and piloted_ship.scene_root != null and is_instance_valid(piloted_ship.scene_root):
		lb_aabb = piloted_ship.interior_aabb()
	var sr = current_ship.scene_root
	if sr != null and is_instance_valid(sr):
		var st = sr.get_node_or_null("ShipStructure")
		if st == null:
			for c in sr.get_children():
				if c.get_child_count() > 0:
					st = c
					break
		if st != null:
			for rn in st.get_children():
				if not (rn is Node3D):
					continue
				var gp: Vector3 = (rn as Node3D).global_position
				if not lb_aabb.grow(0.001).has_point(gp):
					(player as Node3D).global_position = gp
					return true
	# No room outside the piloted AABB — do NOT teleport to an ambiguous center.
	push_error("board_host_for_validation: no host room found outside piloted AABB; cannot prove a genuine flip")
	return false

## 5c seam: drives the real login path for ship_id — teleports the player to that
## ship's bridge terminal and calls try_login (so the real in-range gate admits it).
## Returns true iff the login was accepted (piloted_ship changed to ship_id's instance).
func login_at_terminal_for_validation(ship_id: String) -> bool:
	for t in bridge_terminals:
		if is_instance_valid(t) and String(t.ship_id) == ship_id:
			if is_instance_valid(player) and player.has_method("teleport_to") and t.is_inside_tree():
				player.teleport_to(t.global_position)
			var before = piloted_ship
			t.try_login(player)
			return piloted_ship != before and piloted_ship != null and String(piloted_ship.ship_id) == ship_id
	return false

## 5c seam: force-repair every subcomponent of ship_id's OWN systems manager so its
## propulsion reads operational (makes it a working vessel for tests).
func make_ship_working_for_validation(ship_id: String) -> void:
	var inst = _find_ship_by_id(ship_id)
	if inst == null or inst.systems_manager == null:
		return
	for sid in inst.systems_manager.systems.keys():
		var sys = inst.systems_manager.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			inst.systems_manager.force_repair(sid, sub.subcomponent_id)

## 5c seam: the current piloted ship's id ("" if none).
func piloted_ship_id_for_validation() -> String:
	return String(piloted_ship.ship_id) if piloted_ship != null else ""

## 5c seam: true iff the piloted ship exists AND has live geometry (a valid scene_root).
func piloted_ship_has_geometry_for_validation() -> bool:
	return piloted_ship != null and is_instance_valid(piloted_ship.scene_root)

## 5c seam: the owner_id recorded on ship_id ("" if unknown/unowned).
func ship_owner_for_validation(ship_id: String) -> String:
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return ""
	return inst.get_access().owner_id

## 5c seam: registers an offline derelict-like ship that HAS a bridge room (so it is
## claimable), with its own systems manager and a spawned bridge terminal, parented at
## a distinct world offset, for login tests. Loops candidate seeds until the generated
## layout contains a bridge room (bridge is weighted, not guaranteed). Returns its id,
## or "" if no bridge-bearing layout was found in the search budget.
func register_offline_test_ship_for_validation() -> String:
	if ship_generator == null:
		return ""
	# Bare-geometry test ship (bridge-presence probe only) — reset any stale run context
	# so it does not inherit a previously-traveled marker's biome/difficulty.
	ship_generator.configure_run_context("", "")
	var built = null
	var chosen_seed := -1
	for seed_try in range(0, 200):
		var candidate = ship_generator.generate_from_seed(seed_try, 1, 2)   # size 1, condition 2 (wrecked -> propulsion offline)
		if candidate == null:
			continue
		if candidate.has_method("get_layout_copy") and _layout_has_bridge(candidate.get_layout_copy()):
			built = candidate
			chosen_seed = seed_try
			break
		# Not claimable -> discard this candidate root so it does not leak.
		candidate.queue_free()
	if built == null:
		return ""
	var bp = ShipBlueprintScript.new(1, 2, chosen_seed)
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), bp.condition, bp.seed_value)
	var inst = ShipInstanceScript.create("ship_offline_test", "cell:cell:%d" % chosen_seed, bp, mgr, null)
	inst.scene_root = built
	add_child(built)
	(built as Node3D).position = Vector3(0.0, 0.0, 60.0)
	if inst.built_layout.is_empty() and built.has_method("get_layout_copy"):
		inst.built_layout = built.get_layout_copy()
	visited_ships[String(inst.marker_id)] = inst
	_spawn_bridge_terminal(inst)
	_spawn_hangar_control(inst)
	_spawn_cargo_hold_control(inst)
	_spawn_cart_controls_for_ship(inst)
	return String(inst.ship_id)

## True iff a layout dict contains a room with room_role == "bridge".
func _layout_has_bridge(layout: Dictionary) -> bool:
	var rooms_v: Variant = layout.get("rooms", [])
	if typeof(rooms_v) != TYPE_ARRAY:
		return false
	for room_v in (rooms_v as Array):
		if typeof(room_v) == TYPE_DICTIONARY and str((room_v as Dictionary).get("room_role", "")) == "bridge":
			return true
	return false

## 5c seam: true iff the current active ship has a bridge room (is claimable).
func current_ship_has_bridge_for_validation() -> bool:
	return current_ship != null and typeof(current_ship.built_layout) == TYPE_DICTIONARY and _layout_has_bridge(current_ship.built_layout)

## 5d seams: hangar-bay dock/launch validation surface.
func home_ship_id_for_validation() -> String:
	return String(home_ship.ship_id) if home_ship != null else ""

func cargo_deposit_for_validation(ship_id: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	if inst == null or inventory_state == null:
		return 0
	var moved: int = int(CargoTransferScript.deposit_all(inventory_state, inst.get_inventory()).get("total_moved", 0))
	_recompute_player_encumbrance()
	return moved

func cargo_withdraw_for_validation(ship_id: String, category: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	if inst == null or inventory_state == null:
		return 0
	var moved: int = int(CargoTransferScript.withdraw_category(inst.get_inventory(), inventory_state, category).get("total_moved", 0))
	_recompute_player_encumbrance()
	return moved

func inventory_panel_is_open_for_validation() -> bool:
	return is_instance_valid(inventory_panel) and inventory_panel.is_open()

func inventory_open_self_for_validation() -> bool:
	_open_inventory_self()
	return inventory_panel_is_open_for_validation()

func inventory_close_for_validation() -> void:
	if is_instance_valid(inventory_panel) and inventory_panel.is_open():
		inventory_panel.close()

func inventory_panel_deposit_all_for_validation() -> int:
	if not is_instance_valid(inventory_panel) or not inventory_panel.is_open():
		return 0
	return int(inventory_panel.deposit_all_to_container())

func inventory_transfer_first_to_container_for_validation(item_id: String) -> int:
	# Open-transfer must already be active. Selects item_id on the YOU pane and moves the
	# whole stack into the container; returns moved.
	if not is_instance_valid(inventory_panel) or not inventory_panel.is_open():
		return 0
	var ids: Array = inventory_panel.get_pane_ids("self")
	var idx: int = ids.find(item_id)
	if idx < 0:
		return 0
	inventory_panel.select_row("self", idx, false, false)
	return int(inventory_panel.transfer_selected("self"))

func inventory_transfer_first_from_container_for_validation(item_id: String) -> int:
	if not is_instance_valid(inventory_panel) or not inventory_panel.is_open():
		return 0
	var ids: Array = inventory_panel.get_pane_ids("container")
	var idx: int = ids.find(item_id)
	if idx < 0:
		return 0
	inventory_panel.select_row("container", idx, false, false)
	return int(inventory_panel.transfer_selected("container"))

func player_frozen_for_validation() -> bool:
	return is_instance_valid(player) and not player.is_physics_processing()

func ship_hold_quantity_for_validation(ship_id: String, item_id: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return 0
	return inst.get_inventory().get_quantity(item_id)

func ship_has_cargo_hold_for_validation(ship_id: String) -> bool:
	for c in cargo_hold_controls:
		if is_instance_valid(c) and String(c.carrier_id) == ship_id:
			return true
	return false

## Drives the REAL player-interact dispatch (_on_player_interact_requested), NOT the
## direct transfer seam: positions the player at the ship's cargo control so the strict
## in-range gate admits it, fires interact, and returns how many items landed in the
## hold. A return of 0 means the cargo control is not wired into the interact path.
func cargo_interact_deposit_for_validation(ship_id: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	if inst == null or player == null or not (player is Node3D):
		return 0
	var control = null
	for c in cargo_hold_controls:
		if is_instance_valid(c) and String(c.carrier_id) == ship_id:
			control = c
			break
	if control == null or not control.is_inside_tree() or not (player as Node3D).is_inside_tree():
		return 0
	(player as Node3D).global_position = control.global_position
	var before: int = _hold_item_total(inst)
	_on_player_interact_requested(player)   # opens the transfer panel for this hold
	inventory_panel_deposit_all_for_validation()
	return _hold_item_total(inst) - before

func _hold_item_total(inst) -> int:
	var total: int = 0
	var hold = inst.get_inventory()
	for k in hold.items:
		total += int(hold.items[k])
	return total

func lifeboat_ship_id_for_validation() -> String:
	return String(lifeboat_ship.ship_id) if lifeboat_ship != null else ""

func ship_bay_slot_count_for_validation(ship_id: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	return inst.get_hangar().slot_count if inst != null else 0

func ship_is_bayed_in_for_validation(mobile_id: String, carrier_id: String) -> bool:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return false
	return carrier.get_hangar().slot_of(mobile_id) != -1

func bay_dock_for_validation(carrier_id: String) -> int:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return -1
	var before: int = _first_occupied_slot(carrier.get_hangar())
	_on_bay_dock_requested(carrier_id, -1)
	# Return the slot the candidate landed in (first occupied that was not before, else any occupied).
	var candidate_slot: int = -1
	for i in range(carrier.get_hangar().slots.size()):
		if String(carrier.get_hangar().slots[i]) != "":
			candidate_slot = i
			if i != before:
				break
	return candidate_slot

func bay_launch_for_validation(carrier_id: String) -> int:
	var carrier = _find_ship_by_id(carrier_id)
	if carrier == null:
		return -1
	var idx: int = _first_occupied_slot(carrier.get_hangar())
	_on_bay_launch_requested(carrier_id, -1)
	return idx

## 5d seam: drive the DFS rigid-pair capture/reposition directly (for a deterministic depth-2 guard).
func capture_subtree_for_validation() -> Array:
	return _capture_subtree()

func reposition_subtree_for_validation(captured: Array) -> void:
	_reposition_subtree(captured)

## 5d seam: true iff `child_id` resolves to a ship whose root's offset to the piloted
## root is finite (it is positioned in the piloted frame, i.e. it rode the subtree).
func nested_child_tracks_piloted_for_validation(child_id: String) -> bool:
	if piloted_ship == null or not is_instance_valid(piloted_ship.scene_root):
		return false
	var child = _find_ship_by_id(child_id)
	if child == null or not is_instance_valid(child.scene_root):
		return false
	var root_node: Node3D = piloted_ship.scene_root as Node3D
	var cn: Node3D = child.scene_root as Node3D
	if not root_node.is_inside_tree() or not cn.is_inside_tree():
		return false
	return root_node.global_position.distance_to(cn.global_position) < 1000.0

## Task 7 equipment seams.
func equip_for_validation(item_id: String) -> bool:
	# Seed one into inventory if absent so the seam can drive equip deterministically.
	if inventory_state != null and inventory_state.get_quantity(item_id) <= 0:
		inventory_state.add_item(item_id, 1)
	return _equip_from_inventory(item_id, false)

func unequip_for_validation(slot: String) -> String:
	return _unequip_to_inventory(slot)

func player_capacity_for_validation() -> float:
	return inventory_state.get_capacity() if inventory_state != null else 0.0

func player_equipped_for_validation(slot: String) -> String:
	return equipment_state.get_equipped(slot) if equipment_state != null else ""

func player_move_speed_for_validation() -> float:
	return float(player.move_speed) if is_instance_valid(player) else 0.0

func overload_player_for_validation(item_id: String, qty: int) -> void:
	if inventory_state != null:
		inventory_state.add_item(item_id, qty)
	_recompute_player_encumbrance()

## Task 11 cart validation seams.
func spawn_cart_for_validation(ship_id: String) -> String:
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return ""
	var cart = CartStateScript.create("cart_%s" % ship_id, 200.0)
	cart.parked_ship_id = ship_id
	inst.get_carts().append(cart)
	_spawn_cart_control(inst, cart)
	return cart.cart_id

func cart_grab_for_validation(cart_id: String) -> bool:
	var hit: Dictionary = _find_cart_by_id(cart_id)
	if hit.is_empty() or player == null or not (player is Node3D):
		return false
	var control = null
	for c in cart_controls:
		if is_instance_valid(c) and String(c.cart_id) == cart_id:
			control = c
			break
	if control == null or not control.is_inside_tree() or not (player as Node3D).is_inside_tree():
		return false
	(player as Node3D).global_position = control.global_position
	return control.try_grab(player)

func cart_load_for_validation(cart_id: String) -> int:
	var hit: Dictionary = _find_cart_by_id(cart_id)
	if hit.is_empty() or inventory_state == null:
		return 0
	return int(CargoTransferScript.deposit_all(inventory_state, hit["cart"].get_hold()).get("total_moved", 0))

func cart_unload_for_validation(cart_id: String, category: String) -> int:
	var hit: Dictionary = _find_cart_by_id(cart_id)
	if hit.is_empty() or inventory_state == null:
		return 0
	return int(CargoTransferScript.withdraw_category(hit["cart"].get_hold(), inventory_state, category).get("total_moved", 0))

func cart_is_grabbed_for_validation() -> bool:
	return _is_cart_grabbed()

func cart_hold_quantity_for_validation(cart_id: String, item_id: String) -> int:
	var hit: Dictionary = _find_cart_by_id(cart_id)
	if hit.is_empty():
		return 0
	return hit["cart"].get_hold().get_quantity(item_id)
