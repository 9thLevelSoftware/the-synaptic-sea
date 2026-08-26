//! Closed, deterministic authored item generation for GameplayIR-2.
use crate::rng::stable_index;
use crate::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

pub const MAX_ITEMS: usize = 64;
pub const MAX_AFFIXES: usize = 3;
/// Candidate reward sources are bounded by the public adapter entity ceiling;
/// generated item output remains independently capped by `MAX_ITEMS`.
pub const MAX_SOURCES: usize = 4_096;
pub const MAX_BP: u32 = 10_000;
pub const MAX_LOOT_RICHNESS_BP: u32 = 30_000;
type Result<T> = std::result::Result<T, ItemError>;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ItemCatalogue {
    pub schema_version: String,
    pub families: Vec<ItemFamily>,
    pub sockets: Vec<SocketDefinition>,
    pub affixes: Vec<AffixDefinition>,
    pub rarities: Vec<RarityEnvelope>,
    pub fallback: ItemBaseline,
    pub caps: EconomyCaps,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ItemFamily {
    pub id: String,
    pub socket_kinds: Vec<SocketKind>,
    pub base_value: u32,
    pub stat_budget: u32,
    pub drop_frequency_bp: u32,
    pub visual_tag: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SocketDefinition {
    pub id: String,
    pub kind: SocketKind,
    pub family_ids: Vec<String>,
    pub max_affixes: u8,
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum SocketKind {
    Core,
    Utility,
    Defense,
    Weapon,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AffixDefinition {
    pub id: String,
    pub socket_kind: SocketKind,
    pub stat: StatKind,
    pub min_value: u32,
    pub max_value: u32,
    pub cost_per_value: u32,
    pub value_per_point: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum StatKind {
    Damage,
    Armor,
    Capacity,
    Repair,
    Scan,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RarityEnvelope {
    pub id: String,
    pub min_budget: u32,
    pub max_budget: u32,
    pub value_multiplier_bp: u32,
    pub max_affixes: u8,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct EconomyCaps {
    pub max_total_value: u32,
    pub max_per_item_value: u32,
    pub max_count: u16,
    pub max_drop_frequency_bp: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ItemBaseline {
    pub id: String,
    pub family_id: String,
    pub rarity_id: String,
    pub visual_tag: String,
    pub base_value: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ItemGenerationContext {
    pub request: WorldGenerationRequest,
    pub difficulty_id: String,
    pub loot_richness_bp: u32,
    pub eligible_sources: Vec<SourceBinding>,
    pub max_total_value: u32,
    pub max_count: u16,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SourceBinding {
    pub source_id: String,
    pub source_kind: SourceKind,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum SourceKind {
    Container,
    EncounterReward,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ItemBlueprint {
    pub id: String,
    pub family_id: String,
    pub rarity_id: String,
    pub socket_id: String,
    pub affixes: Vec<AffixRoll>,
    pub stat_budget: u32,
    pub economy_value: u32,
    pub visual_tag: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AffixRoll {
    pub affix_id: String,
    pub stat: StatKind,
    pub value: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct DropBinding {
    pub item_id: String,
    pub source_id: String,
    pub frequency_bp: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ItemCandidateDecision {
    pub candidate_id: String,
    pub score_bp: u32,
    pub accepted: bool,
    pub rationale: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ItemGenerationTrace {
    pub considered: Vec<ItemCandidateDecision>,
    pub repairs: Vec<String>,
    pub fallback: Option<String>,
    pub selected: Vec<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ItemGenerationOutcome {
    pub items: Vec<ItemBlueprint>,
    pub drops: Vec<DropBinding>,
    pub trace: ItemGenerationTrace,
}
#[derive(Debug, thiserror::Error, Clone, PartialEq, Eq)]
pub enum ItemError {
    #[error("invalid item field: {0}")]
    Invalid(&'static str),
    #[error("item key: {0}")]
    Key(&'static str),
    #[error("no eligible item fallback")]
    NoFallback,
}
fn id(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.bytes().all(|b| {
            b.is_ascii_lowercase() || b.is_ascii_digit() || matches!(b, b':' | b'_' | b'-' | b'.')
        })
}
impl ItemCatalogue {
    pub fn bundled() -> Result<Self> {
        serde_json::from_str(include_str!("../assets/gameplay/items_v2.json"))
            .map_err(|_| ItemError::Invalid("catalogue_json"))
    }
    pub fn validate(&self) -> Result<()> {
        if self.schema_version != "item-catalogue-2"
            || self.families.is_empty()
            || self.families.len() > 32
            || self.sockets.is_empty()
            || self.affixes.is_empty()
            || self.rarities.is_empty()
        {
            return Err(ItemError::Invalid("catalogue_bounds"));
        }
        let ids: Vec<_> = self.families.iter().map(|x| &x.id).collect();
        if ids.iter().any(|x| !id(x)) || ids.windows(2).any(|w| w[0] >= w[1]) {
            return Err(ItemError::Invalid("family_ids"));
        }
        let fids: BTreeSet<_> = self.families.iter().map(|x| x.id.as_str()).collect();
        for f in &self.families {
            if f.socket_kinds.is_empty()
                || f.base_value == 0
                || f.stat_budget == 0
                || f.stat_budget > MAX_BP
                || f.drop_frequency_bp > MAX_BP
                || !id(&f.visual_tag)
            {
                return Err(ItemError::Invalid("family"));
            }
        }
        let sids: BTreeSet<_> = self.sockets.iter().map(|x| x.id.as_str()).collect();
        if sids.len() != self.sockets.len()
            || self.sockets.iter().any(|s| {
                !id(&s.id)
                    || s.family_ids.is_empty()
                    || s.max_affixes as usize > MAX_AFFIXES
                    || s.family_ids.iter().any(|f| !fids.contains(f.as_str()))
            })
        {
            return Err(ItemError::Invalid("socket"));
        }
        for s in &self.sockets {
            if s.family_ids.iter().any(|family_id| {
                let family = self.families.iter().find(|f| f.id == *family_id);
                family.is_none_or(|f| !f.socket_kinds.contains(&s.kind))
            }) {
                return Err(ItemError::Invalid("family_socket_kind"));
            }
            if !self.affixes.iter().any(|a| a.socket_kind == s.kind) {
                return Err(ItemError::Invalid("socket_affixes"));
            }
        }
        let aids: Vec<_> = self.affixes.iter().map(|x| &x.id).collect();
        if aids.iter().any(|x| !id(x)) || aids.windows(2).any(|w| w[0] >= w[1]) {
            return Err(ItemError::Invalid("affix_ids"));
        }
        if self.affixes.iter().any(|a| {
            a.min_value == 0
                || a.min_value > a.max_value
                || a.max_value > MAX_BP
                || a.cost_per_value == 0
                || a.value_per_point == 0
        }) {
            return Err(ItemError::Invalid("affix"));
        }
        let rids: Vec<_> = self.rarities.iter().map(|x| &x.id).collect();
        if rids.iter().any(|x| !id(x))
            || rids.windows(2).any(|w| w[0] >= w[1])
            || self.rarities.iter().any(|r| {
                r.min_budget > r.max_budget
                    || r.max_budget > MAX_BP
                    || r.value_multiplier_bp == 0
                    || r.max_affixes as usize > MAX_AFFIXES
            })
        {
            return Err(ItemError::Invalid("rarity"));
        }
        if !id(&self.fallback.id)
            || !fids.contains(self.fallback.family_id.as_str())
            || !rids.iter().any(|x| **x == self.fallback.rarity_id)
            || self.fallback.base_value == 0
            || self.fallback.base_value > self.caps.max_per_item_value
            || self.caps.max_total_value == 0
            || self.caps.max_per_item_value == 0
            || self.caps.max_count == 0
            || self.caps.max_count as usize > MAX_ITEMS
            || self.caps.max_drop_frequency_bp > MAX_BP
        {
            return Err(ItemError::Invalid("caps_fallback"));
        }
        let fallback_family = self
            .families
            .iter()
            .find(|f| f.id == self.fallback.family_id)
            .unwrap();
        let fallback_rarity = self
            .rarities
            .iter()
            .find(|r| r.id == self.fallback.rarity_id)
            .unwrap();
        if !id(&self.fallback.visual_tag)
            || self.fallback.visual_tag != fallback_family.visual_tag
            || fallback_rarity.min_budget > 0
            || !self.sockets.iter().any(|s| {
                s.family_ids.contains(&self.fallback.family_id)
                    && fallback_family.socket_kinds.contains(&s.kind)
                    && s.max_affixes > 0
            })
        {
            return Err(ItemError::Invalid("fallback_compatibility"));
        }
        Ok(())
    }
}
impl ItemGenerationContext {
    fn validate(&self, c: &ItemCatalogue) -> Result<()> {
        c.validate()?;
        let source_state_valid = (self.eligible_sources.is_empty() && self.max_count == 0)
            || (!self.eligible_sources.is_empty() && self.max_count > 0);
        if self.request.platform_version != PROCGEN_GENERATOR_VERSION
            || !id(&self.difficulty_id)
            || self.loot_richness_bp > MAX_LOOT_RICHNESS_BP
            || self.eligible_sources.len() > MAX_SOURCES
            || !source_state_valid
            || self.max_count as usize > MAX_ITEMS
            || self.max_total_value == 0
        {
            return Err(ItemError::Invalid("context"));
        }
        if self.eligible_sources.iter().any(|s| !id(&s.source_id))
            || self
                .eligible_sources
                .windows(2)
                .any(|w| w[0].source_id >= w[1].source_id)
        {
            return Err(ItemError::Invalid("sources"));
        }
        Ok(())
    }
}
impl ItemGenerationOutcome {
    pub fn validate(&self, c: &ItemGenerationContext, cat: &ItemCatalogue) -> Result<()> {
        c.validate(cat)?;
        if self.items.len() != self.drops.len()
            || self.items.len() > c.max_count as usize
            || self.trace.repairs.len() > 2
            || self.trace.considered.len() > 128
        {
            return Err(ItemError::Invalid("outcome_bounds"));
        }
        if c.eligible_sources.is_empty() {
            if !self.items.is_empty()
                || !self.drops.is_empty()
                || !self.trace.considered.is_empty()
                || !self.trace.selected.is_empty()
                || self.trace.fallback.as_deref() != Some("authored_safe_empty")
            {
                return Err(ItemError::Invalid("safe_empty"));
            }
            return Ok(());
        }
        if self.trace.fallback.as_deref() == Some("authored_safe_empty") {
            return Err(ItemError::Invalid("safe_empty"));
        }
        let mut seen = BTreeSet::new();
        let mut value = 0u32;
        for (i, d) in self.drops.iter().enumerate() {
            if d.item_id != self.items[i].id
                || !seen.insert(d.source_id.clone())
                || !c
                    .eligible_sources
                    .iter()
                    .any(|s| s.source_id == d.source_id)
                || d.frequency_bp > cat.caps.max_drop_frequency_bp
            {
                return Err(ItemError::Invalid("drop_binding"));
            }
            value = value
                .checked_add(self.items[i].economy_value)
                .ok_or(ItemError::Invalid("value_overflow"))?
        }
        if value > c.max_total_value.min(cat.caps.max_total_value) {
            return Err(ItemError::Invalid("economy_cap"));
        }
        for i in &self.items {
            validate_item(i, cat)?
        }
        Ok(())
    }
}
fn validate_item(i: &ItemBlueprint, c: &ItemCatalogue) -> Result<()> {
    let f = c
        .families
        .iter()
        .find(|x| x.id == i.family_id)
        .ok_or(ItemError::Invalid("family_ref"))?;
    let s = c
        .sockets
        .iter()
        .find(|x| x.id == i.socket_id)
        .ok_or(ItemError::Invalid("socket_ref"))?;
    let r = c
        .rarities
        .iter()
        .find(|x| x.id == i.rarity_id)
        .ok_or(ItemError::Invalid("rarity_ref"))?;
    if !s.family_ids.contains(&f.id)
        || i.affixes.len() > s.max_affixes as usize
        || i.affixes.len() > r.max_affixes as usize
        || i.stat_budget < r.min_budget
        || i.stat_budget > r.max_budget
        || i.stat_budget > f.stat_budget
        || i.economy_value > c.caps.max_per_item_value
        || i.visual_tag != f.visual_tag
        || !id(&i.id)
        || !id(&i.visual_tag)
    {
        return Err(ItemError::Invalid("item_compatibility"));
    }
    let mut stats = BTreeSet::new();
    let mut budget: u32 = 0;
    for a in &i.affixes {
        let d = c
            .affixes
            .iter()
            .find(|x| x.id == a.affix_id)
            .ok_or(ItemError::Invalid("affix_ref"))?;
        if d.socket_kind != s.kind
            || d.stat != a.stat
            || a.value < d.min_value
            || a.value > d.max_value
            || !stats.insert(a.stat.clone())
        {
            return Err(ItemError::Invalid("affix_compatibility"));
        }
        budget = budget
            .checked_add(
                a.value
                    .checked_mul(d.cost_per_value)
                    .ok_or(ItemError::Invalid("budget_overflow"))?,
            )
            .ok_or(ItemError::Invalid("budget_overflow"))?
    }
    if budget != i.stat_budget {
        return Err(ItemError::Invalid("stat_budget"));
    }
    Ok(())
}
pub fn generate_items(
    c: &ItemGenerationContext,
    cat: &ItemCatalogue,
) -> Result<ItemGenerationOutcome> {
    c.validate(cat)?;
    if c.eligible_sources.is_empty() {
        let outcome = ItemGenerationOutcome {
            items: Vec::new(),
            drops: Vec::new(),
            trace: ItemGenerationTrace {
                considered: Vec::new(),
                repairs: Vec::new(),
                fallback: Some("authored_safe_empty".into()),
                selected: Vec::new(),
            },
        };
        outcome.validate(c, cat)?;
        return Ok(outcome);
    }
    let mut k = WorldKey {
        world_seed: c.request.world_seed,
        platform_version: c.request.platform_version,
        content_manifest_hash: c.request.content_manifest_hash.clone(),
        site_id: c.request.site_id.clone(),
        x: c.request.x,
        y: c.request.y,
        domain: "gameplay".into(),
        channel: "gameplay.item_family".into(),
        sub_index: 0,
    };
    let seed = k.seed().map_err(ItemError::Key)?;
    let family_index = stable_index(seed, cat.families.len()).ok_or(ItemError::NoFallback)?;
    let f = &cat.families[family_index];
    let s = cat
        .sockets
        .iter()
        .find(|s| s.family_ids.contains(&f.id))
        .ok_or(ItemError::NoFallback)?;
    let r = cat
        .rarities
        .iter()
        .find(|r| r.min_budget <= f.stat_budget && r.max_budget >= f.stat_budget)
        .unwrap_or(&cat.rarities[0]);
    let n = ((c.loot_richness_bp / 2500) as usize + 1)
        .min(c.max_count as usize)
        .min(c.eligible_sources.len());
    let mut items = Vec::new();
    let mut drops = Vec::new();
    let mut decisions = Vec::new();
    for x in 0..n {
        k.channel = "gameplay.item_affix".into();
        k.sub_index = x as u32;
        let seed = k.seed().map_err(ItemError::Key)?;
        let ds: Vec<_> = cat
            .affixes
            .iter()
            .filter(|a| a.socket_kind == s.kind)
            .collect();
        if ds.is_empty() {
            decisions.push(ItemCandidateDecision {
                candidate_id: format!("item:{x:02}"),
                score_bp: 0,
                accepted: false,
                rationale: "rejected_no_compatible_affix".into(),
            });
            return fallback(c, cat, decisions);
        }
        let affix_index = stable_index(seed, ds.len()).ok_or(ItemError::NoFallback)?;
        let d = ds[affix_index];
        let item_id = format!("item:{x:02}");
        let width = match d
            .max_value
            .checked_sub(d.min_value)
            .and_then(|v| v.checked_add(1))
        {
            Some(width) => width,
            None => {
                decisions.push(ItemCandidateDecision {
                    candidate_id: item_id,
                    score_bp: (seed % 10001) as u32,
                    accepted: false,
                    rationale: "rejected_arithmetic_overflow".into(),
                });
                return fallback(c, cat, decisions);
            }
        };
        let v = match d.min_value.checked_add((seed % u64::from(width)) as u32) {
            Some(value) => value,
            None => {
                decisions.push(ItemCandidateDecision {
                    candidate_id: item_id,
                    score_bp: (seed % 10001) as u32,
                    accepted: false,
                    rationale: "rejected_arithmetic_overflow".into(),
                });
                return fallback(c, cat, decisions);
            }
        };
        let b = match v.checked_mul(d.cost_per_value) {
            Some(budget) => budget,
            None => {
                decisions.push(ItemCandidateDecision {
                    candidate_id: item_id,
                    score_bp: (seed % 10001) as u32,
                    accepted: false,
                    rationale: "rejected_arithmetic_overflow".into(),
                });
                return fallback(c, cat, decisions);
            }
        };
        let economy_value = match v
            .checked_mul(d.value_per_point)
            .and_then(|bonus| f.base_value.checked_add(bonus))
        {
            Some(value) => value,
            None => {
                decisions.push(ItemCandidateDecision {
                    candidate_id: item_id,
                    score_bp: (seed % 10001) as u32,
                    accepted: false,
                    rationale: "rejected_arithmetic_overflow".into(),
                });
                return fallback(c, cat, decisions);
            }
        };
        let item = ItemBlueprint {
            id: item_id.clone(),
            family_id: f.id.clone(),
            rarity_id: r.id.clone(),
            socket_id: s.id.clone(),
            affixes: vec![AffixRoll {
                affix_id: d.id.clone(),
                stat: d.stat.clone(),
                value: v,
            }],
            stat_budget: b,
            economy_value,
            visual_tag: f.visual_tag.clone(),
        };
        if validate_item(&item, cat).is_err() {
            decisions.push(ItemCandidateDecision {
                candidate_id: item_id,
                score_bp: (seed % 10001) as u32,
                accepted: false,
                rationale: "rejected_item_incompatible".into(),
            });
            return fallback(c, cat, decisions);
        }
        items.push(item);
        drops.push(DropBinding {
            item_id: item_id.clone(),
            source_id: c.eligible_sources[x].source_id.clone(),
            frequency_bp: f.drop_frequency_bp,
        });
        decisions.push(ItemCandidateDecision {
            candidate_id: item_id.clone(),
            score_bp: (seed % 10001) as u32,
            accepted: true,
            rationale: "authored_compatible".into(),
        })
    }
    let selected = items.iter().map(|item| item.id.clone()).collect();
    let out = ItemGenerationOutcome {
        items,
        drops,
        trace: ItemGenerationTrace {
            considered: decisions.clone(),
            repairs: vec![],
            fallback: None,
            selected,
        },
    };
    if out.validate(c, cat).is_err() {
        decisions.push(ItemCandidateDecision {
            candidate_id: "item:economy".into(),
            score_bp: 0,
            accepted: false,
            rationale: "rejected_economy_cap".into(),
        });
        return fallback(c, cat, decisions);
    }
    Ok(out)
}
fn fallback(
    c: &ItemGenerationContext,
    cat: &ItemCatalogue,
    considered: Vec<ItemCandidateDecision>,
) -> Result<ItemGenerationOutcome> {
    let b = &cat.fallback;
    let s = cat
        .sockets
        .iter()
        .find(|s| s.family_ids.contains(&b.family_id))
        .ok_or(ItemError::NoFallback)?;
    let i = ItemBlueprint {
        id: b.id.clone(),
        family_id: b.family_id.clone(),
        rarity_id: b.rarity_id.clone(),
        socket_id: s.id.clone(),
        affixes: vec![],
        stat_budget: 0,
        economy_value: b.base_value,
        visual_tag: b.visual_tag.clone(),
    };
    let out = ItemGenerationOutcome {
        items: vec![i.clone()],
        drops: vec![DropBinding {
            item_id: i.id,
            source_id: c.eligible_sources[0].source_id.clone(),
            frequency_bp: 0,
        }],
        trace: ItemGenerationTrace {
            considered,
            repairs: vec![],
            fallback: Some("authored_baseline".into()),
            selected: vec![b.id.clone()],
        },
    };
    out.validate(c, cat)?;
    Ok(out)
}
