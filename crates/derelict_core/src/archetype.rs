//! Data-driven generation content: ship archetypes, furnishing rules, loot
//! tables. All authored as RON files; defaults are embedded in the binary so
//! the generator works with zero filesystem setup, and can be overridden by
//! loading replacement RON at runtime (modding / game-side tuning).

use crate::model::{CauseOfLoss, EntityKind, RoomType};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum SizePref {
    Largest,
    Large,
    Medium,
    Small,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RoomReq {
    pub kind: RoomType,
    /// Positional preference along the ship's long axis, -100 (stern) to
    /// +100 (bow). 0 = no preference. Bow is +x.
    pub bow_bias: i16,
    pub size_pref: SizePref,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ShipArchetype {
    pub id: String,
    pub display_name: String,
    /// Deck-0 hull length range (tiles along x).
    pub length: (u16, u16),
    /// Deck-0 hull beam range (tiles along y).
    pub beam: (u16, u16),
    pub decks: (u8, u8),
    /// Fraction of the hull envelope to fill with tiles, basis points.
    pub hull_fill_bp: u16,
    /// Probability per growth step of skipping the mirrored twin, bp.
    pub asymmetry_bp: u16,
    /// Boundary erosion (tiles) applied per deck away from the main deck.
    pub deck_erosion: u8,
    /// Minimum room dimension for BSP leaves.
    pub min_room_dim: u8,
    pub required_rooms: Vec<RoomReq>,
    /// (room type, weight) pool for filling leftover BSP slots.
    pub optional_rooms: Vec<(RoomType, u32)>,
    pub cause_weights: Vec<(CauseOfLoss, u32)>,
    /// Max breach count at intactness 0.
    pub max_breaches: u8,
    /// Number of extra loop-back corridor edges, bp of non-MST edges kept.
    pub corridor_loop_bp: u16,
    /// Vertical shaft count range (multi-deck ships).
    pub shafts: (u8, u8),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum Placement {
    WallAdjacent,
    Corner,
    Center,
    Free,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FurnitureRule {
    pub proto: String,
    pub kind: EntityKind,
    pub count: (u8, u8),
    pub place: Placement,
    /// For containers: chance the container is locked, bp.
    pub lock_bp: u16,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct FurnishingRules {
    pub rules: BTreeMap<RoomType, Vec<FurnitureRule>>,
    pub door_lock_bp: BTreeMap<RoomType, u16>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ItemDef {
    pub id: u32,
    pub name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LootEntry {
    /// Item name; resolved against the item registry at load time.
    pub item: String,
    pub weight: u32,
    pub qty: (u16, u16),
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LootTables {
    /// Per room type: pool of possible items for containers in that room.
    pub tables: BTreeMap<RoomType, Vec<LootEntry>>,
    /// Rolls per container, before richness scaling.
    pub rolls: (u8, u8),
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ItemRegistry {
    pub items: Vec<ItemDef>,
}

impl ItemRegistry {
    pub fn id_of(&self, name: &str) -> Option<u32> {
        self.items.iter().find(|i| i.name == name).map(|i| i.id)
    }
    pub fn name_of(&self, id: u32) -> Option<&str> {
        self.items
            .iter()
            .find(|i| i.id == id)
            .map(|i| i.name.as_str())
    }
}

/// The full bundle of generation content data.
#[derive(Clone, Debug)]
pub struct GenData {
    pub archetypes: BTreeMap<String, ShipArchetype>,
    pub furnishing: FurnishingRules,
    pub loot: LootTables,
    pub items: ItemRegistry,
}

#[derive(Debug)]
pub enum DataError {
    Parse(String),
    Validation(String),
}

impl std::fmt::Display for DataError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DataError::Parse(m) => write!(f, "data parse error: {m}"),
            DataError::Validation(m) => write!(f, "data validation error: {m}"),
        }
    }
}

impl std::error::Error for DataError {}

const DEFAULT_ARCHETYPES: &[&str] = &[
    include_str!("../assets/archetypes/shuttle.ron"),
    include_str!("../assets/archetypes/corvette.ron"),
    include_str!("../assets/archetypes/freighter.ron"),
    include_str!("../assets/archetypes/frigate.ron"),
];
const DEFAULT_FURNISHING: &str = include_str!("../assets/furnishing_rules/default.ron");
const DEFAULT_LOOT: &str = include_str!("../assets/loot_tables/default.ron");
const DEFAULT_ITEMS: &str = include_str!("../assets/items.ron");

impl GenData {
    /// Load the embedded default content bundle.
    pub fn default_bundle() -> Result<Self, DataError> {
        let mut archetypes = BTreeMap::new();
        for src in DEFAULT_ARCHETYPES {
            let a: ShipArchetype =
                ron::from_str(src).map_err(|e| DataError::Parse(e.to_string()))?;
            archetypes.insert(a.id.clone(), a);
        }
        let furnishing: FurnishingRules =
            ron::from_str(DEFAULT_FURNISHING).map_err(|e| DataError::Parse(e.to_string()))?;
        let loot: LootTables =
            ron::from_str(DEFAULT_LOOT).map_err(|e| DataError::Parse(e.to_string()))?;
        let items: ItemRegistry =
            ron::from_str(DEFAULT_ITEMS).map_err(|e| DataError::Parse(e.to_string()))?;
        let data = Self {
            archetypes,
            furnishing,
            loot,
            items,
        };
        data.validate()?;
        Ok(data)
    }

    /// Validate authored content so unsatisfiable data fails at load, not
    /// mid-generation: room tile budgets fit the smallest hull, loot items
    /// resolve, weights are non-degenerate.
    pub fn validate(&self) -> Result<(), DataError> {
        for (id, a) in &self.archetypes {
            if a.length.0 < 8 || a.beam.0 < 6 {
                return Err(DataError::Validation(format!(
                    "archetype '{id}': hull too small (min 8x6)"
                )));
            }
            if a.length.0 > a.length.1 || a.beam.0 > a.beam.1 || a.decks.0 > a.decks.1 {
                return Err(DataError::Validation(format!(
                    "archetype '{id}': inverted range"
                )));
            }
            // Min-tile-budget guard: required rooms must plausibly fit the
            // smallest hull at ~60% interior yield.
            let min_room = (a.min_room_dim as u32).pow(2);
            let budget = a.length.0 as u32 * a.beam.0 as u32 * 6 / 10;
            let need = a.required_rooms.len() as u32 * min_room;
            if need > budget {
                return Err(DataError::Validation(format!(
                    "archetype '{id}': {} required rooms cannot fit min hull ({need} > {budget} tiles)",
                    a.required_rooms.len()
                )));
            }
            if a.cause_weights.iter().map(|(_, w)| *w as u64).sum::<u64>() == 0 {
                return Err(DataError::Validation(format!(
                    "archetype '{id}': cause_weights all zero"
                )));
            }
        }
        for (room, entries) in &self.loot.tables {
            for e in entries {
                if self.items.id_of(&e.item).is_none() {
                    return Err(DataError::Validation(format!(
                        "loot table {room:?}: unknown item '{}'",
                        e.item
                    )));
                }
            }
        }
        Ok(())
    }
}
