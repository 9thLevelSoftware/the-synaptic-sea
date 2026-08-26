//! Closed, manifest-bound presentation assembly. Presentation is cosmetic only.
use crate::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
const MAX_ID: usize = 96;
const MAX_TAGS: usize = 16;
const MAX_ASSETS: usize = 256;
const MAX_SUBJECTS: usize = 128;
const MAX_DECISIONS: usize = 256;
fn id(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= MAX_ID
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"_:.-".contains(&b))
}
fn text(s: &str) -> bool {
    !s.is_empty() && s.len() <= 512
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AssetKind {
    Mesh,
    Material,
    Rig,
    Animation,
    Vfx,
    Audio,
    Caption,
    Primitive,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum SubjectKind {
    Ship,
    Creature,
    Item,
    Environment,
    Objective,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema, Default)]
#[serde(deny_unknown_fields)]
pub struct Provenance {
    pub source: String,
    pub license: String,
    pub tool_or_model_version: String,
    pub inputs: Vec<String>,
    pub parameters_or_seed: String,
    pub human_changes: String,
    pub technical_validation: String,
    pub art_approval: String,
    pub promoted_content_manifest_entry: String,
}
impl Provenance {
    pub fn validate(&self) -> Result<(), PresentationError> {
        if !text(&self.source)
            || !text(&self.license)
            || !text(&self.tool_or_model_version)
            || self.inputs.is_empty()
            || self.inputs.len() > 32
            || self.inputs.iter().any(|x| !text(x))
            || !text(&self.parameters_or_seed)
            || !text(&self.human_changes)
            || !text(&self.technical_validation)
            || !text(&self.art_approval)
            || !id(&self.promoted_content_manifest_entry)
        {
            return Err(PresentationError::Invalid("provenance"));
        }
        Ok(())
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum AssetRecord {
    Mesh {
        asset_id: String,
        tags: Vec<String>,
        compatible_tags: Vec<String>,
        compatible_subject_kinds: Vec<SubjectKind>,
        adapter_binding_id: String,
        provenance: Provenance,
    },
    Material {
        asset_id: String,
        tags: Vec<String>,
        compatible_tags: Vec<String>,
        compatible_subject_kinds: Vec<SubjectKind>,
        adapter_binding_id: String,
        provenance: Provenance,
    },
    Rig {
        asset_id: String,
        tags: Vec<String>,
        compatible_tags: Vec<String>,
        compatible_subject_kinds: Vec<SubjectKind>,
        adapter_binding_id: String,
        provenance: Provenance,
    },
    Animation {
        asset_id: String,
        tags: Vec<String>,
        compatible_tags: Vec<String>,
        compatible_subject_kinds: Vec<SubjectKind>,
        adapter_binding_id: String,
        provenance: Provenance,
    },
    Vfx {
        asset_id: String,
        tags: Vec<String>,
        compatible_tags: Vec<String>,
        compatible_subject_kinds: Vec<SubjectKind>,
        adapter_binding_id: String,
        provenance: Provenance,
    },
    Audio {
        asset_id: String,
        tags: Vec<String>,
        compatible_tags: Vec<String>,
        compatible_subject_kinds: Vec<SubjectKind>,
        adapter_binding_id: String,
        provenance: Provenance,
    },
    Caption {
        asset_id: String,
        tags: Vec<String>,
        compatible_tags: Vec<String>,
        compatible_subject_kinds: Vec<SubjectKind>,
        adapter_binding_id: String,
        provenance: Provenance,
    },
    Primitive {
        asset_id: String,
        tags: Vec<String>,
        compatible_tags: Vec<String>,
        compatible_subject_kinds: Vec<SubjectKind>,
        adapter_binding_id: String,
        provenance: Provenance,
    },
}
impl AssetRecord {
    fn fields(
        &self,
    ) -> (
        &str,
        &[String],
        &[String],
        &[SubjectKind],
        &str,
        &Provenance,
        AssetKind,
    ) {
        match self {
            Self::Mesh {
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
            } => (
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
                AssetKind::Mesh,
            ),
            Self::Material {
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
            } => (
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
                AssetKind::Material,
            ),
            Self::Rig {
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
            } => (
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
                AssetKind::Rig,
            ),
            Self::Animation {
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
            } => (
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
                AssetKind::Animation,
            ),
            Self::Vfx {
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
            } => (
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
                AssetKind::Vfx,
            ),
            Self::Audio {
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
            } => (
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
                AssetKind::Audio,
            ),
            Self::Caption {
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
            } => (
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
                AssetKind::Caption,
            ),
            Self::Primitive {
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
            } => (
                asset_id,
                tags,
                compatible_tags,
                compatible_subject_kinds,
                adapter_binding_id,
                provenance,
                AssetKind::Primitive,
            ),
        }
    }
    fn asset_id(&self) -> &str {
        self.fields().0
    }
    pub fn kind(&self) -> AssetKind {
        self.fields().6
    }
    fn validate(&self, m: &BTreeSet<&String>) -> Result<(), PresentationError> {
        let (a, t, c, sk, b, p, _) = self.fields();
        if !id(a)
            || !id(b)
            || b.contains("script")
            || b.contains("execute")
            || t.is_empty()
            || t.len() > MAX_TAGS
            || c.len() > MAX_TAGS
            || sk.is_empty()
            || sk.len() > MAX_TAGS
            || sk.windows(2).any(|w| w[0] >= w[1])
            || t.iter().chain(c).any(|x| !id(x))
            || p.promoted_content_manifest_entry != a
            || !m.iter().any(|x| x.as_str() == a)
        {
            return Err(PresentationError::Invalid("asset_record"));
        }
        p.validate()
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PresentationCatalogue {
    pub schema_version: String,
    pub manifest_entries: Vec<String>,
    pub assets: Vec<AssetRecord>,
}
impl PresentationCatalogue {
    pub fn bundled() -> Result<Self, PresentationError> {
        serde_json::from_str(include_str!("../assets/presentation/catalog_v2.json"))
            .map_err(|_| PresentationError::Invalid("catalogue_json"))
    }
    pub fn validate(&self) -> Result<(), PresentationError> {
        if self.schema_version != "presentation-catalogue-2"
            || self.manifest_entries.len() > MAX_ASSETS
            || self.manifest_entries.iter().any(|x| !id(x))
        {
            return Err(PresentationError::Invalid("catalogue"));
        }
        let m: BTreeSet<_> = self.manifest_entries.iter().collect();
        if m.len() != self.manifest_entries.len()
            || self.assets.is_empty()
            || self.assets.len() > MAX_ASSETS
        {
            return Err(PresentationError::Invalid("catalogue_bounds"));
        }
        let mut ids = BTreeSet::new();
        for a in &self.assets {
            a.validate(&m)?;
            if !ids.insert(a.asset_id()) {
                return Err(PresentationError::Invalid("duplicate_asset"));
            }
        }
        Ok(())
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PresentationSubject {
    pub subject_id: String,
    pub subject_kind: SubjectKind,
    pub binding_tags: Vec<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PresentationContext {
    pub request: WorldGenerationRequest,
    pub presentation_seed: u64,
    pub locale: String,
    pub subjects: Vec<PresentationSubject>,
}
impl PresentationContext {
    fn validate(&self) -> Result<(), PresentationError> {
        if self.subjects.is_empty()
            || self.subjects.len() > MAX_SUBJECTS
            || !id(&self.locale)
            || self.locale.len() > 16
            || self.presentation_seed > crate::world::MAX_PUBLIC_SEED
            || self.request.platform_version != PROCGEN_GENERATOR_VERSION
            || self.request.content_manifest_hash.len() != 64
            || !self
                .request
                .content_manifest_hash
                .bytes()
                .all(|b| b.is_ascii_hexdigit())
            || self.request.content_manifest_hash
                != self.request.content_manifest_hash.to_ascii_lowercase()
            || self
                .subjects
                .windows(2)
                .any(|w| w[0].subject_id >= w[1].subject_id)
        {
            return Err(PresentationError::Invalid("context"));
        }
        let mut ids = BTreeSet::new();
        for s in &self.subjects {
            if !id(&s.subject_id)
                || s.binding_tags.is_empty()
                || s.binding_tags.len() > MAX_TAGS
                || s.binding_tags.iter().any(|x| !id(x))
                || !ids.insert(&s.subject_id)
            {
                return Err(PresentationError::Invalid("subject"));
            }
        }
        Ok(())
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AssemblyInstruction {
    pub subject_id: String,
    pub asset_ids: Vec<String>,
    pub adapter_binding_ids: Vec<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Decision {
    pub decision_id: String,
    pub channel: String,
    pub considered: Vec<CandidateRecord>,
    pub rejected: Vec<CandidateRecord>,
    pub selected: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CandidateRecord {
    pub asset_id: String,
    pub accepted: bool,
    pub rationale: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PresentationOutput {
    pub schema_version: String,
    pub instructions: Vec<AssemblyInstruction>,
    pub decisions: Vec<Decision>,
    pub repairs: Vec<String>,
    pub fallback_subjects: Vec<String>,
}
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum PresentationError {
    #[error("presentation invalid: {0}")]
    Invalid(&'static str),
    #[error("presentation key: {0}")]
    Key(&'static str),
}
pub fn assemble(
    c: &PresentationContext,
    cat: &PresentationCatalogue,
) -> Result<PresentationOutput, PresentationError> {
    c.validate()?;
    cat.validate()?;
    let mut ins = Vec::new();
    let mut ds = Vec::new();
    let mut fb = Vec::new();
    for (i, s) in c.subjects.iter().enumerate() {
        if i >= MAX_DECISIONS {
            return Err(PresentationError::Invalid("decision_bounds"));
        }
        let k = WorldKey {
            world_seed: c.request.world_seed,
            platform_version: PROCGEN_GENERATOR_VERSION,
            content_manifest_hash: c.request.content_manifest_hash.clone(),
            site_id: c.request.site_id.clone(),
            x: c.request.x,
            y: c.request.y,
            domain: "presentation".into(),
            channel: "presentation.asset_assembly".into(),
            sub_index: i as u32,
        };
        let seed = k.seed().map_err(PresentationError::Key)? ^ c.presentation_seed;
        let mut can: Vec<_> = cat
            .assets
            .iter()
            .filter(|a| {
                let f = a.fields();
                f.3.contains(&s.subject_kind) && s.binding_tags.iter().all(|tag| f.2.contains(tag))
            })
            .collect();
        can.sort_by_key(|a| a.asset_id());
        let mut considered = Vec::new();
        let mut rejected = Vec::new();
        for a in &cat.assets {
            let f = a.fields();
            let rationale = if !f.3.contains(&s.subject_kind) {
                "incompatible_subject_kind"
            } else if !s.binding_tags.iter().all(|tag| f.2.contains(tag)) {
                "missing_compatible_tag"
            } else {
                "eligible"
            };
            let record = CandidateRecord {
                asset_id: a.asset_id().into(),
                accepted: rationale == "eligible",
                rationale: rationale.into(),
            };
            if record.accepted {
                considered.push(record);
            } else {
                rejected.push(record);
            }
        }
        considered.sort_by(|a, b| a.asset_id.cmp(&b.asset_id));
        rejected.sort_by(|a, b| a.asset_id.cmp(&b.asset_id));
        let chosen = can
            .get((seed as usize) % can.len().max(1))
            .copied()
            .ok_or(PresentationError::Invalid("no_fallback"))?;
        if can.is_empty() {
            fb.push(s.subject_id.clone())
        }
        ds.push(Decision {
            decision_id: format!("decision:{i}"),
            channel: "presentation.asset_assembly".into(),
            considered,
            rejected,
            selected: chosen.asset_id().into(),
        });
        ins.push(AssemblyInstruction {
            subject_id: s.subject_id.clone(),
            asset_ids: vec![chosen.asset_id().into()],
            adapter_binding_ids: vec![chosen.fields().4.into()],
        })
    }
    let o = PresentationOutput {
        schema_version: "presentation-ir-2".into(),
        instructions: ins,
        decisions: ds,
        repairs: Vec::new(),
        fallback_subjects: fb,
    };
    o.validate(c, cat)?;
    Ok(o)
}
impl PresentationOutput {
    pub fn validate(
        &self,
        c: &PresentationContext,
        cat: &PresentationCatalogue,
    ) -> Result<(), PresentationError> {
        c.validate()?;
        cat.validate()?;
        if self.schema_version != "presentation-ir-2"
            || self.instructions.len() != c.subjects.len()
            || self.decisions.len() != self.instructions.len()
            || self.repairs.len() > 1
        {
            return Err(PresentationError::Invalid("output"));
        }
        for (i, x) in self.instructions.iter().enumerate() {
            if x.subject_id != c.subjects[i].subject_id
                || x.asset_ids.len() != 1
                || x.adapter_binding_ids.len() != 1
            {
                return Err(PresentationError::Invalid("instruction"));
            }
            let a = cat
                .assets
                .iter()
                .find(|a| a.asset_id() == x.asset_ids[0])
                .ok_or(PresentationError::Invalid("dangling_asset"))?;
            if a.fields().4 != x.adapter_binding_ids[0] {
                return Err(PresentationError::Invalid("binding"));
            }
            let subject = &c.subjects[i];
            let f = a.fields();
            if !f.3.contains(&subject.subject_kind)
                || !subject.binding_tags.iter().all(|tag| f.2.contains(tag))
            {
                return Err(PresentationError::Invalid("incompatible_asset"));
            }
            let decision = &self.decisions[i];
            if decision.selected != x.asset_ids[0]
                || decision.considered.len() + decision.rejected.len() != cat.assets.len()
                || decision.considered.len() > MAX_ASSETS
                || decision.rejected.len() > MAX_ASSETS
                || decision
                    .considered
                    .iter()
                    .chain(decision.rejected.iter())
                    .any(|candidate| {
                        !id(&candidate.asset_id)
                            || candidate.rationale.is_empty()
                            || candidate.rationale.len() > MAX_ID
                    })
                || !decision
                    .considered
                    .iter()
                    .any(|candidate| candidate.asset_id == decision.selected && candidate.accepted)
            {
                return Err(PresentationError::Invalid("decision_trace"));
            }
        }
        Ok(())
    }
}
