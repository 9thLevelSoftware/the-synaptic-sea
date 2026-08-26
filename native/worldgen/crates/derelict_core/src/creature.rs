//! Authored, validated creature blueprints for GameplayIR.
use crate::world::{WorldGenerationRequest, WorldKey, MAX_PUBLIC_SEED, PROCGEN_GENERATOR_VERSION};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

pub const CREATURE_RULES_VERSION: &str = "creature-rules-1";
pub const MAX_CANDIDATES: usize = 16;
pub const MAX_CELLS: usize = 64;

macro_rules! closed_enum { ($name:ident { $($v:ident),+ $(,)? }) => {
    #[derive(Clone, Copy, Debug, PartialEq, Eq, Ord, PartialOrd, Serialize, Deserialize, JsonSchema)]
    #[serde(rename_all = "snake_case")]
    pub enum $name { $($v),+ }
} }
closed_enum!(ThreatRole {
    Scout,
    Tank,
    Controller
});
closed_enum!(CounterplayRole {
    Evade,
    ArmorBreak,
    Interrupt
});
closed_enum!(BehaviorKind {
    Patrol,
    Ambush,
    Guard
});

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, Ord, PartialOrd, Serialize, Deserialize, JsonSchema,
)]
pub struct Cell {
    pub x: i8,
    pub y: i8,
}
macro_rules! dto { ($name:ident { $($field:ident : $ty:ty),+ $(,)? }) => {
    #[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
    #[serde(deny_unknown_fields)]
    pub struct $name { $(pub $field: $ty),+ }
} }
dto!(BodyPlan { id: String, family: String, max_mass: u16, footprint_id: String, rig_ids: Vec<String> });
dto!(Footprint { id: String, cells: Vec<Cell>, clearance: u16, traversal_bp: u16 });
dto!(Rig { id: String, body_ids: Vec<String>, animation_set_ids: Vec<String> });
dto!(AnimationSet { id: String, rig_ids: Vec<String>, required_behaviors: Vec<BehaviorKind> });
dto!(Ability { id: String, behavior_ids: Vec<String>, counterplay: CounterplayRole, threat_cost: u16, performance_cost: u16 });
dto!(Behavior { id: String, kind: BehaviorKind, ability_ids: Vec<String>, roles: Vec<ThreatRole> });
dto!(Material { id: String, body_ids: Vec<String>, visual_tags: Vec<String>, audio_tags: Vec<String> });
dto!(Counterplay { id: String, role: CounterplayRole, ability_ids: Vec<String>, approved_tags: Vec<String> });
dto!(CreatureRules { schema_version: String, platform_version: u32, max_threat: u16, max_performance: u16, max_instances: u16, approved_visual_tags: Vec<String>, approved_audio_tags: Vec<String> });
dto!(CreatureCatalogue { schema_version: String, rules: CreatureRules, body_plans: Vec<BodyPlan>, footprints: Vec<Footprint>, rigs: Vec<Rig>, animation_sets: Vec<AnimationSet>, abilities: Vec<Ability>, behaviors: Vec<Behavior>, materials: Vec<Material>, counterplay: Vec<Counterplay>, fallbacks: Vec<CreatureBlueprint> });
dto!(CreatureBlueprint {
    id: String,
    body_plan_id: String,
    footprint_id: String,
    rig_id: String,
    animation_set_id: String,
    ability_id: String,
    behavior_id: String,
    material_id: String,
    counterplay_id: String,
    threat_role: ThreatRole,
    threat_cost: u16,
    performance_cost: u16,
    instance_cap: u16
});
dto!(CreatureGenerationContext {
    request: WorldGenerationRequest,
    min_clearance: u16,
    max_footprint_cells: u16,
    threat_cap: u16,
    performance_cap: u16,
    instance_cap: u16
});
dto!(CandidateRecord {
    candidate_id: String,
    score: u32,
    accepted: bool,
    rationale: String
});
dto!(CreatureTrace { channel_ids: Vec<String>, considered: Vec<CandidateRecord>, rejected: Vec<CandidateRecord>, selected: Option<String>, repairs: Vec<String>, fallback: Option<String> });
dto!(CreatureGenerationOutcome {
    blueprint: CreatureBlueprint,
    trace: CreatureTrace
});
#[derive(Debug, thiserror::Error, Clone, PartialEq, Eq)]
pub enum CreatureError {
    #[error("invalid creature content: {0}")]
    Invalid(String),
    #[error("creature key: {0}")]
    Key(&'static str),
    #[error("no compatible creature blueprint")]
    NoCompatibleBlueprint,
}

fn valid_id(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"_:.-".contains(&b))
}
fn canonical<T>(xs: &[T], f: impl Fn(&T) -> &String) -> bool {
    xs.windows(2).all(|w| f(&w[0]) < f(&w[1]))
}
fn get<T>(xs: &[T], f: impl Fn(&T) -> bool) -> Option<&T> {
    xs.iter().find(|x| f(x))
}

impl CreatureCatalogue {
    pub fn bundled() -> Result<Self, CreatureError> {
        serde_json::from_str(include_str!("../assets/gameplay/creatures_v2.json"))
            .map_err(|e| CreatureError::Invalid(e.to_string()))
    }
    pub fn validate(&self) -> Result<(), CreatureError> {
        if self.schema_version != "creature-catalogue-2"
            || self.rules.schema_version != CREATURE_RULES_VERSION
            || self.rules.platform_version != PROCGEN_GENERATOR_VERSION
            || self.rules.max_threat == 0
            || self.rules.max_performance == 0
            || self.rules.max_instances == 0
        {
            return Err(CreatureError::Invalid("rules_bounds".into()));
        }
        if !canonical(&self.body_plans, |x| &x.id)
            || !canonical(&self.footprints, |x| &x.id)
            || !canonical(&self.rigs, |x| &x.id)
            || !canonical(&self.animation_sets, |x| &x.id)
            || !canonical(&self.abilities, |x| &x.id)
            || !canonical(&self.behaviors, |x| &x.id)
            || !canonical(&self.materials, |x| &x.id)
            || !canonical(&self.counterplay, |x| &x.id)
            || !canonical(&self.fallbacks, |x| &x.id)
        {
            return Err(CreatureError::Invalid("ids_not_canonical".into()));
        }
        for f in &self.footprints {
            validate_footprint(f)?;
        }
        for b in &self.body_plans {
            if !valid_id(&b.id)
                || !valid_id(&b.family)
                || b.max_mass == 0
                || b.rig_ids.is_empty()
                || get(&self.footprints, |x| x.id == b.footprint_id).is_none()
                || b.rig_ids
                    .iter()
                    .any(|id| get(&self.rigs, |x| x.id == *id).is_none())
            {
                return Err(CreatureError::Invalid(format!("body:{}", b.id)));
            }
        }
        for r in &self.rigs {
            if !valid_id(&r.id)
                || r.body_ids.is_empty()
                || r.animation_set_ids.is_empty()
                || r.body_ids
                    .iter()
                    .any(|id| get(&self.body_plans, |x| x.id == *id).is_none())
                || r.animation_set_ids
                    .iter()
                    .any(|id| get(&self.animation_sets, |x| x.id == *id).is_none())
            {
                return Err(CreatureError::Invalid(format!("rig:{}", r.id)));
            }
        }
        for a in &self.animation_sets {
            if !valid_id(&a.id)
                || a.rig_ids.is_empty()
                || a.rig_ids
                    .iter()
                    .any(|id| get(&self.rigs, |x| x.id == *id).is_none())
            {
                return Err(CreatureError::Invalid(format!("animation:{}", a.id)));
            }
        }
        for a in &self.abilities {
            if !valid_id(&a.id)
                || a.threat_cost == 0
                || a.performance_cost == 0
                || a.behavior_ids.is_empty()
                || a.behavior_ids
                    .iter()
                    .any(|id| get(&self.behaviors, |x| x.id == *id).is_none())
            {
                return Err(CreatureError::Invalid(format!("ability:{}", a.id)));
            }
        }
        for b in &self.behaviors {
            if !valid_id(&b.id)
                || b.ability_ids.is_empty()
                || b.roles.is_empty()
                || b.ability_ids
                    .iter()
                    .any(|id| get(&self.abilities, |x| x.id == *id).is_none())
            {
                return Err(CreatureError::Invalid(format!("behavior:{}", b.id)));
            }
        }
        for m in &self.materials {
            if !valid_id(&m.id)
                || m.body_ids.is_empty()
                || m.body_ids
                    .iter()
                    .any(|id| get(&self.body_plans, |x| x.id == *id).is_none())
                || m.visual_tags
                    .iter()
                    .any(|x| !self.rules.approved_visual_tags.contains(x))
                || m.audio_tags
                    .iter()
                    .any(|x| !self.rules.approved_audio_tags.contains(x))
            {
                return Err(CreatureError::Invalid(format!("material:{}", m.id)));
            }
        }
        for c in &self.counterplay {
            if !valid_id(&c.id)
                || c.ability_ids.is_empty()
                || c.ability_ids
                    .iter()
                    .any(|id| get(&self.abilities, |x| x.id == *id).is_none())
            {
                return Err(CreatureError::Invalid(format!("counterplay:{}", c.id)));
            }
        }
        for b in &self.fallbacks {
            self.validate_blueprint_unchecked(
                b,
                &CreatureGenerationContext {
                    request: WorldGenerationRequest {
                        world_seed: 0,
                        platform_version: 3,
                        content_manifest_hash: "0".repeat(64),
                        site_id: "fallback".into(),
                        x: 0,
                        y: 0,
                        archetype_id: "fallback".into(),
                    },
                    min_clearance: 0,
                    max_footprint_cells: MAX_CELLS as u16,
                    threat_cap: self.rules.max_threat,
                    performance_cap: self.rules.max_performance,
                    instance_cap: self.rules.max_instances,
                },
            )?;
        }
        Ok(())
    }
    pub fn validate_blueprint(
        &self,
        b: &CreatureBlueprint,
        c: &CreatureGenerationContext,
    ) -> Result<(), CreatureError> {
        validate_context(c, &self.rules)?;
        self.validate_blueprint_unchecked(b, c)
    }
    fn validate_blueprint_unchecked(
        &self,
        b: &CreatureBlueprint,
        c: &CreatureGenerationContext,
    ) -> Result<(), CreatureError> {
        if !valid_id(&b.id) {
            return Err(CreatureError::Invalid("blueprint_id".into()));
        }
        let body = get(&self.body_plans, |x| x.id == b.body_plan_id)
            .ok_or_else(|| CreatureError::Invalid("body_dangling".into()))?;
        let fp = get(&self.footprints, |x| x.id == b.footprint_id)
            .ok_or_else(|| CreatureError::Invalid("footprint_dangling".into()))?;
        let rig = get(&self.rigs, |x| x.id == b.rig_id)
            .ok_or_else(|| CreatureError::Invalid("rig_dangling".into()))?;
        let anim = get(&self.animation_sets, |x| x.id == b.animation_set_id)
            .ok_or_else(|| CreatureError::Invalid("animation_dangling".into()))?;
        let ability = get(&self.abilities, |x| x.id == b.ability_id)
            .ok_or_else(|| CreatureError::Invalid("ability_dangling".into()))?;
        let behavior = get(&self.behaviors, |x| x.id == b.behavior_id)
            .ok_or_else(|| CreatureError::Invalid("behavior_dangling".into()))?;
        let mat = get(&self.materials, |x| x.id == b.material_id)
            .ok_or_else(|| CreatureError::Invalid("material_dangling".into()))?;
        let cp = get(&self.counterplay, |x| x.id == b.counterplay_id)
            .ok_or_else(|| CreatureError::Invalid("counterplay_dangling".into()))?;
        if !body.rig_ids.contains(&rig.id)
            || !rig.body_ids.contains(&body.id)
            || !rig.animation_set_ids.contains(&anim.id)
            || !anim.rig_ids.contains(&rig.id)
            || body.footprint_id != fp.id
            || !mat.body_ids.contains(&body.id)
            || !behavior.ability_ids.contains(&ability.id)
            || !ability.behavior_ids.contains(&behavior.id)
            || !anim.required_behaviors.contains(&behavior.kind)
            || !cp.ability_ids.contains(&ability.id)
            || cp.role != ability.counterplay
            || !behavior.roles.contains(&b.threat_role)
            || ability.threat_cost != b.threat_cost
            || ability.performance_cost != b.performance_cost
            || fp.clearance < c.min_clearance
            || fp.cells.len() > c.max_footprint_cells as usize
            || b.threat_cost > c.threat_cap
            || b.performance_cost > c.performance_cap
            || b.instance_cap == 0
            || b.instance_cap > c.instance_cap
        {
            return Err(CreatureError::Invalid("compatibility_or_budget".into()));
        }
        Ok(())
    }
    pub fn generate(
        &self,
        c: &CreatureGenerationContext,
    ) -> Result<CreatureGenerationOutcome, CreatureError> {
        self.validate()?;
        let q = &c.request;
        let key = WorldKey {
            world_seed: q.world_seed,
            platform_version: q.platform_version,
            content_manifest_hash: q.content_manifest_hash.clone(),
            site_id: q.site_id.clone(),
            x: q.x,
            y: q.y,
            domain: "gameplay".into(),
            channel: "gameplay.creature_blueprint".into(),
            sub_index: 0,
        };
        let seed = key.seed().map_err(CreatureError::Key)?;
        let mut valid = Vec::new();
        let mut rejected = Vec::new();
        let mut all = self.fallbacks.clone();
        all.sort_by(|a, b| a.id.cmp(&b.id));
        for (i, b) in all.iter().take(MAX_CANDIDATES).enumerate() {
            let ok = self.validate_blueprint(b, c).is_ok();
            let candidate_offset = u64::try_from(i)
                .map_err(|_| CreatureError::Invalid("candidate_index".into()))?
                .wrapping_mul(7919);
            let rec = CandidateRecord {
                candidate_id: b.id.clone(),
                score: u32::try_from(seed.wrapping_add(candidate_offset) % 10_001)
                    .map_err(|_| CreatureError::Invalid("candidate_score".into()))?,
                accepted: ok,
                rationale: if ok {
                    "validated".into()
                } else {
                    "incompatible".into()
                },
            };
            if ok {
                valid.push((rec.score, b.clone(), rec));
            } else {
                rejected.push(rec);
            }
        }
        valid.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.id.cmp(&b.1.id)));
        let mut trace = CreatureTrace {
            channel_ids: vec![
                key.channel,
                "gameplay.creature_ability".into(),
                "gameplay.creature_material".into(),
            ],
            considered: valid
                .iter()
                .map(|x| x.2.clone())
                .chain(rejected.clone())
                .collect(),
            rejected,
            selected: None,
            repairs: Vec::new(),
            fallback: None,
        };
        if let Some((_, b, _)) = valid.first() {
            trace.selected = Some(b.id.clone());
            return Ok(CreatureGenerationOutcome {
                blueprint: b.clone(),
                trace,
            });
        }
        let b = self
            .fallbacks
            .first()
            .ok_or(CreatureError::NoCompatibleBlueprint)?
            .clone();
        self.validate_blueprint(&b, c)?;
        trace.fallback = Some(b.id.clone());
        Ok(CreatureGenerationOutcome {
            blueprint: b,
            trace,
        })
    }
}

/// Convenience entry point used by adapters and focused callers.
pub fn generate_creature_blueprint(
    context: &CreatureGenerationContext,
    catalogue: &CreatureCatalogue,
) -> Result<CreatureGenerationOutcome, CreatureError> {
    catalogue.generate(context)
}

pub fn validate_creature_catalogue(catalogue: &CreatureCatalogue) -> Result<(), CreatureError> {
    catalogue.validate()
}
fn validate_footprint(f: &Footprint) -> Result<(), CreatureError> {
    if !valid_id(&f.id)
        || f.cells.is_empty()
        || f.cells.len() > MAX_CELLS
        || f.clearance == 0
        || f.traversal_bp == 0
        || f.traversal_bp > 10_000
        || f.cells.iter().collect::<BTreeSet<_>>().len() != f.cells.len()
    {
        return Err(CreatureError::Invalid(format!("footprint:{}", f.id)));
    }
    let set: BTreeSet<_> = f.cells.iter().copied().collect();
    let mut seen = BTreeSet::new();
    let mut todo = vec![f.cells[0]];
    while let Some(c) = todo.pop() {
        if !seen.insert(c) {
            continue;
        }
        for n in [
            c.x.checked_add(1).map(|x| Cell { x, y: c.y }),
            c.x.checked_sub(1).map(|x| Cell { x, y: c.y }),
            c.y.checked_add(1).map(|y| Cell { x: c.x, y }),
            c.y.checked_sub(1).map(|y| Cell { x: c.x, y }),
        ]
        .into_iter()
        .flatten()
        {
            if set.contains(&n) {
                todo.push(n)
            }
        }
    }
    if seen.len() != set.len() {
        return Err(CreatureError::Invalid(format!(
            "footprint_disconnected:{}",
            f.id
        )));
    }
    Ok(())
}

fn validate_context(
    c: &CreatureGenerationContext,
    rules: &CreatureRules,
) -> Result<(), CreatureError> {
    let q = &c.request;
    if q.world_seed > MAX_PUBLIC_SEED
        || q.platform_version != PROCGEN_GENERATOR_VERSION
        || !valid_id(&q.site_id)
        || !valid_id(&q.archetype_id)
        || q.content_manifest_hash.len() != 64
        || !q
            .content_manifest_hash
            .bytes()
            .all(|b| b.is_ascii_hexdigit())
        || q.content_manifest_hash != q.content_manifest_hash.to_ascii_lowercase()
        || q.x == i32::MIN
        || q.x == i32::MAX
        || q.y == i32::MIN
        || q.y == i32::MAX
        || c.max_footprint_cells == 0
        || c.max_footprint_cells as usize > MAX_CELLS
        || c.threat_cap == 0
        || c.threat_cap > rules.max_threat
        || c.performance_cap == 0
        || c.performance_cap > rules.max_performance
        || c.instance_cap == 0
        || c.instance_cap > rules.max_instances
    {
        return Err(CreatureError::Invalid("context".into()));
    }
    Ok(())
}
