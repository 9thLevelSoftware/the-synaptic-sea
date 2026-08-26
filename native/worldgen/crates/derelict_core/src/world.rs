//! Coordinate-addressed platform-v3 world identity and bounded world-domain
//! contracts.  This module deliberately does not alter the structural v2
//! ship generator.
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

const MAX_ID_LEN: usize = 64;

/// Platform contract version.  `model::GENERATOR_VERSION` remains structural v2.
pub const PROCGEN_GENERATOR_VERSION: u32 = 3;
pub const MAX_PUBLIC_SEED: u64 = 9_007_199_254_740_991;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorldKey {
    pub world_seed: u64,
    pub platform_version: u32,
    pub content_manifest_hash: String,
    pub site_id: String,
    pub x: i32,
    pub y: i32,
    pub domain: String,
    pub channel: String,
    pub sub_index: u32,
}

impl WorldKey {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.world_seed > MAX_PUBLIC_SEED {
            return Err("world_seed");
        }
        if self.platform_version != PROCGEN_GENERATOR_VERSION {
            return Err("platform_version");
        }
        if self.content_manifest_hash.len() != 64
            || !self
                .content_manifest_hash
                .bytes()
                .all(|b| b.is_ascii_hexdigit())
            || self.content_manifest_hash != self.content_manifest_hash.to_ascii_lowercase()
        {
            return Err("content_manifest_hash");
        }
        if !valid_id(&self.site_id) || !valid_id(&self.domain) || !valid_id(&self.channel) {
            return Err("identity");
        }
        Ok(())
    }

    /// SHA-256 over length-delimited UTF-8/integer fields.  Every component is
    /// included independently, avoiding delimiter and signed-coordinate
    /// collisions.  The result is always exactly representable in JS/Godot.
    pub fn seed(&self) -> Result<u64, &'static str> {
        self.validate()?;
        let mut h = Sha256::new();
        put_u64(&mut h, self.world_seed);
        put_u64(&mut h, u64::from(self.platform_version));
        put_text(&mut h, &self.content_manifest_hash);
        put_text(&mut h, &self.site_id);
        put_i32(&mut h, self.x);
        put_i32(&mut h, self.y);
        put_text(&mut h, &self.domain);
        put_text(&mut h, &self.channel);
        put_u64(&mut h, u64::from(self.sub_index));
        let digest = h.finalize();
        let mut bytes = [0_u8; 8];
        bytes.copy_from_slice(&digest[..8]);
        Ok(u64::from_be_bytes(bytes) & MAX_PUBLIC_SEED)
    }
}

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_ID_LEN
        && value.bytes().all(|b| {
            b.is_ascii_lowercase()
                || b.is_ascii_digit()
                || b == b':'
                || b == b'_'
                || b == b'-'
                || b == b'.'
        })
}

pub fn derive_site_seed_v3(key: &WorldKey) -> Result<u64, &'static str> {
    key.seed()
}

fn put_len(h: &mut Sha256, n: usize) {
    h.update((n as u64).to_be_bytes());
}
fn put_text(h: &mut Sha256, value: &str) {
    put_len(h, value.len());
    h.update(value.as_bytes());
}
fn put_u64(h: &mut Sha256, value: u64) {
    put_len(h, 8);
    h.update(value.to_be_bytes());
}
fn put_i32(h: &mut Sha256, value: i32) {
    put_len(h, 4);
    h.update(value.to_be_bytes());
}

fn in_range(seed: u64, range: &RouteRange) -> u32 {
    let span = u64::from(range.max_bp - range.min_bp) + 1;
    range.min_bp + (seed % span) as u32
}

fn canonical_edge(from: &str, to: &str) -> (String, String) {
    if from < to {
        (from.into(), to.into())
    } else {
        (to.into(), from.into())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CoordinateMarker {
    pub marker_id: String,
    pub site_id: String,
    pub x: i32,
    pub y: i32,
    pub archetype_id: String,
    pub site_seed: u64,
    pub selected: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RouteEdge {
    pub from: String,
    pub to: String,
    pub cost_bp: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct BiomeField {
    pub marker_id: String,
    pub biome_id: String,
    pub intensity_bp: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct HazardField {
    pub marker_id: String,
    pub hazard_id: String,
    pub severity_bp: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ResourcePressure {
    pub marker_id: String,
    pub resource_id: String,
    pub pressure_bp: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LandmarkRecord {
    pub id: String,
    pub marker_id: String,
    pub kind: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorldAnchor {
    pub id: String,
    pub kind: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ExtractionGuarantee {
    pub selected_marker_id: String,
    pub hub_anchor_id: String,
    pub extraction_anchor_id: String,
    pub path: Vec<String>,
}

/// Canonical radius-one sector: row-major neighbors (the center is excluded).
pub fn radius_one_coordinates(x: i32, y: i32) -> Result<Vec<(i32, i32)>, &'static str> {
    [
        (-1, -1),
        (0, -1),
        (1, -1),
        (-1, 0),
        (1, 0),
        (-1, 1),
        (0, 1),
        (1, 1),
    ]
    .into_iter()
    .map(|(dx, dy)| Some((x.checked_add(dx)?, y.checked_add(dy)?)))
    .collect::<Option<Vec<_>>>()
    .ok_or("coordinate_boundary")
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorldIRv2 {
    pub schema_version: String,
    pub world_seed: u64,
    pub site_id: String,
    pub x: i32,
    pub y: i32,
    pub archetype_id: String,
    pub site_seed: u64,
    pub markers: Vec<CoordinateMarker>,
    pub routes: Vec<RouteEdge>,
    pub biome_fields: Vec<BiomeField>,
    pub hazard_fields: Vec<HazardField>,
    pub resource_pressures: Vec<ResourcePressure>,
    pub landmarks: Vec<LandmarkRecord>,
    pub anchors: Vec<WorldAnchor>,
    pub extraction: ExtractionGuarantee,
}

/// Current platform world document. The explicit v2 suffix above makes the
/// schema transition visible at call sites while this alias keeps the domain
/// API ergonomic for consumers.
pub type WorldIR = WorldIRv2;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RouteRange {
    pub min_bp: u32,
    pub max_bp: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorldRules {
    pub schema_version: String,
    pub platform_version: u32,
    pub archetypes: Vec<String>,
    pub biomes: Vec<String>,
    pub hazards: Vec<String>,
    pub landmarks: Vec<String>,
    pub resources: Vec<String>,
    pub route_cost_bp: RouteRange,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorldFallback {
    pub schema_version: String,
    pub platform_version: u32,
    pub fallback_id: String,
    pub biome_id: String,
    pub hazard_id: String,
    pub landmarks: Vec<String>,
    pub neighbor_archetype_id: String,
    pub resource_id: String,
    pub route_cost_bp: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorldGenerationRequest {
    pub world_seed: u64,
    pub platform_version: u32,
    pub content_manifest_hash: String,
    pub site_id: String,
    pub x: i32,
    pub y: i32,
    pub archetype_id: String,
}
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum WorldError {
    #[error("invalid world field: {0}")]
    Invalid(&'static str),
    #[error("world key: {0}")]
    Key(&'static str),
}

impl WorldRules {
    pub fn bundled() -> Result<Self, WorldError> {
        serde_json::from_str(include_str!("../assets/world/rules_v3.json"))
            .map_err(|_| WorldError::Invalid("rules_json"))
    }
    pub fn validate(&self) -> Result<(), WorldError> {
        if self.schema_version != "world-rules-1"
            || self.platform_version != PROCGEN_GENERATOR_VERSION
            || self.archetypes.len() != 4
            || self.biomes.is_empty()
            || self.hazards.is_empty()
            || self.landmarks.is_empty()
            || self.resources.is_empty()
            || self.route_cost_bp.min_bp == 0
            || self.route_cost_bp.min_bp > self.route_cost_bp.max_bp
            || self.route_cost_bp.max_bp > 10_000
        {
            return Err(WorldError::Invalid("rules_bounds"));
        }
        if self
            .archetypes
            .iter()
            .chain(self.biomes.iter())
            .chain(self.hazards.iter())
            .chain(self.landmarks.iter())
            .chain(self.resources.iter())
            .any(|s| !valid_id(s))
            || self.archetypes.iter().collect::<BTreeSet<_>>().len() != self.archetypes.len()
            || self.biomes.iter().collect::<BTreeSet<_>>().len() != self.biomes.len()
            || self.hazards.iter().collect::<BTreeSet<_>>().len() != self.hazards.len()
            || self.landmarks.iter().collect::<BTreeSet<_>>().len() != self.landmarks.len()
            || self.resources.iter().collect::<BTreeSet<_>>().len() != self.resources.len()
        {
            return Err(WorldError::Invalid("rules_unique"));
        }
        Ok(())
    }
}
impl WorldFallback {
    pub fn bundled() -> Result<Self, WorldError> {
        serde_json::from_str(include_str!("../assets/world/safe_fallback_v3.json"))
            .map_err(|_| WorldError::Invalid("fallback_json"))
    }
    pub fn validate(&self, rules: &WorldRules) -> Result<(), WorldError> {
        rules.validate()?;
        if self.schema_version != "world-fallback-1"
            || self.platform_version != PROCGEN_GENERATOR_VERSION
            || !valid_id(&self.fallback_id)
            || !rules.biomes.contains(&self.biome_id)
            || !rules.hazards.contains(&self.hazard_id)
            || self.landmarks.is_empty()
            || self.landmarks.iter().any(|id| !valid_id(id))
            || self.landmarks.iter().collect::<BTreeSet<_>>().len() != self.landmarks.len()
            || self
                .landmarks
                .iter()
                .any(|id| !rules.landmarks.contains(id))
            || !rules.archetypes.contains(&self.neighbor_archetype_id)
            || !rules.resources.contains(&self.resource_id)
            || self.route_cost_bp < rules.route_cost_bp.min_bp
            || self.route_cost_bp > rules.route_cost_bp.max_bp
        {
            return Err(WorldError::Invalid("fallback"));
        }
        Ok(())
    }
}

/// A complete, bounded resolution result. Decision values are stable codes;
/// request/site identifiers are deliberately excluded from the trace.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct WorldGenerationOutcome {
    pub world_ir: WorldIR,
    pub candidate_decisions: Vec<String>,
    pub repairs: Vec<String>,
    pub fallback: Option<String>,
}

impl WorldGenerationOutcome {
    pub fn validate(
        &self,
        rules: &WorldRules,
        request: &WorldGenerationRequest,
    ) -> Result<(), WorldError> {
        if self.candidate_decisions.len() > 128
            || self.repairs.len() > 1
            || self
                .candidate_decisions
                .iter()
                .any(|s| s.len() > 96 || !stable_code(s))
            || self.repairs.iter().any(|s| s.len() > 96 || !stable_code(s))
            || self
                .fallback
                .as_ref()
                .is_some_and(|s| s.len() > 96 || !stable_code(s))
        {
            return Err(WorldError::Invalid("trace_bounds"));
        }
        if self.fallback.is_none() {
            self.world_ir.validate_for_request(request, rules)
        } else {
            Err(WorldError::Invalid("fallback_context"))
        }
    }
    pub fn validate_with_fallback(
        &self,
        rules: &WorldRules,
        request: &WorldGenerationRequest,
        fallback: &WorldFallback,
    ) -> Result<(), WorldError> {
        if self.fallback.as_deref() != Some(fallback.fallback_id.as_str()) {
            return Err(WorldError::Invalid("fallback_context"));
        }
        self.world_ir
            .validate_for_fallback(request, rules, fallback)
    }
}

fn stable_code(value: &str) -> bool {
    !value.is_empty()
        && value.bytes().all(|b| {
            b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-' || b == b':'
        })
}
impl WorldGenerationRequest {
    fn validate(&self, rules: &WorldRules) -> Result<(), WorldError> {
        if self.world_seed > MAX_PUBLIC_SEED
            || self.platform_version != 3
            || !valid_id(&self.site_id)
            || !valid_id(&self.archetype_id)
            || self.content_manifest_hash.len() != 64
            || !self
                .content_manifest_hash
                .bytes()
                .all(|b| b.is_ascii_hexdigit())
            || self.content_manifest_hash != self.content_manifest_hash.to_ascii_lowercase()
            || !rules.archetypes.iter().any(|a| a == &self.archetype_id)
            || self.x == i32::MIN
            || self.x == i32::MAX
            || self.y == i32::MIN
            || self.y == i32::MAX
        {
            return Err(WorldError::Invalid("request"));
        }
        if radius_one_coordinates(self.x, self.y)
            .map_err(WorldError::Invalid)?
            .iter()
            .any(|(x, y)| self.site_id == format!("site:{x}:{y}"))
        {
            return Err(WorldError::Invalid("site_collision"));
        }
        Ok(())
    }
}

pub fn generate_candidate(
    req: &WorldGenerationRequest,
    rules: &WorldRules,
) -> Result<WorldIRv2, WorldError> {
    req.validate(rules)?;
    let coords = radius_one_coordinates(req.x, req.y).map_err(WorldError::Invalid)?;
    let selected_seed = key(
        req,
        "site",
        "site.structural",
        0,
        req.x,
        req.y,
        &req.site_id,
    )?
    .seed()
    .map_err(WorldError::Key)?;
    let mut markers = vec![CoordinateMarker {
        marker_id: "marker:0".into(),
        site_id: req.site_id.clone(),
        x: req.x,
        y: req.y,
        archetype_id: req.archetype_id.clone(),
        site_seed: selected_seed,
        selected: true,
    }];
    for (i, (x, y)) in coords.iter().enumerate() {
        let sid = format!("site:{x}:{y}");
        let seed = key(req, "site", "site.structural", 0, *x, *y, &sid)?
            .seed()
            .map_err(WorldError::Key)?;
        let archetype =
            rules.archetypes[(key(req, "world", "world.archetype", i as u32, *x, *y, &sid)?
                .seed()
                .map_err(WorldError::Key)? as usize)
                % rules.archetypes.len()]
            .clone();
        markers.push(CoordinateMarker {
            marker_id: format!("marker:{}", i + 1),
            site_id: sid,
            x: *x,
            y: *y,
            archetype_id: archetype,
            site_seed: seed,
            selected: false,
        });
    }
    let mut routes = Vec::new();
    for i in 1..9 {
        let route_seed = key(
            req,
            "world",
            "world.route_cost",
            i as u32,
            req.x,
            req.y,
            &format!("marker:{i}"),
        )?
        .seed()
        .map_err(WorldError::Key)?;
        let (from, to) = canonical_edge("marker:0", &format!("marker:{i}"));
        routes.push(RouteEdge {
            from,
            to,
            cost_bp: in_range(route_seed, &rules.route_cost_bp),
        });
    }
    let hub_seed = key(
        req,
        "world",
        "world.route_cost",
        9,
        req.x,
        req.y,
        "anchor:hub",
    )?
    .seed()
    .map_err(WorldError::Key)?;
    let (from, to) = canonical_edge("marker:0", "anchor:hub");
    routes.push(RouteEdge {
        from,
        to,
        cost_bp: in_range(hub_seed, &rules.route_cost_bp),
    });
    let extraction_seed = key(
        req,
        "world",
        "world.route_cost",
        10,
        req.x,
        req.y,
        "anchor:extraction",
    )?
    .seed()
    .map_err(WorldError::Key)?;
    let (from, to) = canonical_edge("anchor:hub", "anchor:extraction");
    routes.push(RouteEdge {
        from,
        to,
        cost_bp: in_range(extraction_seed, &rules.route_cost_bp),
    });
    routes.sort_by(|a, b| (a.from.as_str(), a.to.as_str()).cmp(&(b.from.as_str(), b.to.as_str())));
    let mut biome_fields = Vec::with_capacity(markers.len());
    let mut hazard_fields = Vec::with_capacity(markers.len());
    let mut resource_pressures = Vec::with_capacity(markers.len());
    let mut landmarks = Vec::with_capacity(markers.len());
    for (i, m) in markers.iter().enumerate() {
        let biome_seed = key(req, "world", "world.biome", i as u32, m.x, m.y, &m.site_id)?
            .seed()
            .map_err(WorldError::Key)?;
        let hazard_seed = key(req, "world", "world.hazard", i as u32, m.x, m.y, &m.site_id)?
            .seed()
            .map_err(WorldError::Key)?;
        let resource_seed = key(
            req,
            "world",
            "world.resource",
            i as u32,
            m.x,
            m.y,
            &m.site_id,
        )?
        .seed()
        .map_err(WorldError::Key)?;
        let landmark_seed = key(
            req,
            "world",
            "world.landmark",
            i as u32,
            m.x,
            m.y,
            &m.site_id,
        )?
        .seed()
        .map_err(WorldError::Key)?;
        biome_fields.push(BiomeField {
            marker_id: m.marker_id.clone(),
            biome_id: rules.biomes[biome_seed as usize % rules.biomes.len()].clone(),
            intensity_bp: (biome_seed % 10001) as u32,
        });
        hazard_fields.push(HazardField {
            marker_id: m.marker_id.clone(),
            hazard_id: rules.hazards[hazard_seed as usize % rules.hazards.len()].clone(),
            severity_bp: (hazard_seed % 10001) as u32,
        });
        resource_pressures.push(ResourcePressure {
            marker_id: m.marker_id.clone(),
            resource_id: rules.resources[resource_seed as usize % rules.resources.len()].clone(),
            pressure_bp: (resource_seed % 10001) as u32,
        });
        landmarks.push(LandmarkRecord {
            id: format!("landmark:{i}"),
            marker_id: m.marker_id.clone(),
            kind: rules.landmarks[landmark_seed as usize % rules.landmarks.len()].clone(),
        });
    }
    let world = WorldIRv2 {
        schema_version: "world-ir-2".into(),
        world_seed: req.world_seed,
        site_id: req.site_id.clone(),
        x: req.x,
        y: req.y,
        archetype_id: req.archetype_id.clone(),
        site_seed: markers[0].site_seed,
        markers,
        routes,
        biome_fields,
        hazard_fields,
        resource_pressures,
        landmarks,
        anchors: vec![
            WorldAnchor {
                id: "anchor:hub".into(),
                kind: "hub".into(),
            },
            WorldAnchor {
                id: "anchor:extraction".into(),
                kind: "extraction".into(),
            },
        ],
        extraction: ExtractionGuarantee {
            selected_marker_id: "marker:0".into(),
            hub_anchor_id: "anchor:hub".into(),
            extraction_anchor_id: "anchor:extraction".into(),
            path: vec![
                "marker:0".into(),
                "anchor:hub".into(),
                "anchor:extraction".into(),
            ],
        },
    };
    world.validate_for_request(req, rules)?;
    Ok(world)
}

/// Resolve an injected candidate. Exactly one narrowly-defined repair is
/// permitted: the canonical selected-marker to hub edge may be absent.
pub fn resolve_world(
    req: &WorldGenerationRequest,
    candidate: WorldIR,
    rules: &WorldRules,
    fallback: &WorldFallback,
) -> Result<WorldGenerationOutcome, WorldError> {
    req.validate(rules)?;
    rules.validate()?;
    fallback.validate(rules)?;
    let mut decisions = vec!["considered_candidate".to_string()];
    if candidate.validate_for_request(req, rules).is_ok() {
        decisions.push("selected_candidate".into());
        let out = WorldGenerationOutcome {
            world_ir: candidate,
            candidate_decisions: decisions,
            repairs: vec![],
            fallback: None,
        };
        out.validate(rules, req)?;
        return Ok(out);
    }

    // Compare against a pristine candidate with only the canonical hub edge
    // removed. This proves that no unrelated defect is repaired accidentally.
    let pristine = generate_candidate(req, rules)?;
    let expected_hub = pristine
        .routes
        .iter()
        .find(|r| {
            (r.from == "anchor:hub" && r.to == "marker:0")
                || (r.from == "marker:0" && r.to == "anchor:hub")
        })
        .cloned()
        .ok_or(WorldError::Invalid("canonical_route"))?;
    let mut repairable = pristine.clone();
    repairable.routes.retain(|r| r != &expected_hub);
    if candidate == repairable {
        let mut repaired = candidate;
        repaired.routes.push(expected_hub);
        repaired.routes.sort_by(|a, b| {
            (a.from.as_str(), a.to.as_str()).cmp(&(b.from.as_str(), b.to.as_str()))
        });
        if repaired.validate_for_request(req, rules).is_ok() {
            decisions.push("repaired_candidate".into());
            let out = WorldGenerationOutcome {
                world_ir: repaired,
                candidate_decisions: decisions,
                repairs: vec!["repair_missing_selected_hub_route".into()],
                fallback: None,
            };
            out.validate(rules, req)?;
            return Ok(out);
        }
    }

    decisions.push("rejected_candidate".into());
    let world = bind_fallback(req, rules, fallback)?;
    decisions.push("selected_fallback".into());
    let out = WorldGenerationOutcome {
        world_ir: world,
        candidate_decisions: decisions,
        repairs: vec![],
        fallback: Some(fallback.fallback_id.clone()),
    };
    out.validate_with_fallback(rules, req, fallback)?;
    Ok(out)
}

/// Production entry point: bundled documents are validated before any output
/// is selected, and failures are closed (no partial WorldIR is returned).
pub fn generate_world(req: &WorldGenerationRequest) -> Result<WorldGenerationOutcome, WorldError> {
    let rules = WorldRules::bundled()?;
    let fallback = WorldFallback::bundled()?;
    rules.validate()?;
    fallback.validate(&rules)?;
    let candidate = generate_candidate(req, &rules)?;
    resolve_world(req, candidate, &rules, &fallback)
}

fn bind_fallback(
    req: &WorldGenerationRequest,
    rules: &WorldRules,
    fallback: &WorldFallback,
) -> Result<WorldIR, WorldError> {
    let coords = radius_one_coordinates(req.x, req.y).map_err(WorldError::Invalid)?;
    let mut markers = Vec::with_capacity(9);
    for (i, (x, y)) in std::iter::once((req.x, req.y)).chain(coords).enumerate() {
        let site_id = if i == 0 {
            req.site_id.clone()
        } else {
            format!("site:{x}:{y}")
        };
        let seed = key(req, "site", "site.structural", 0, x, y, &site_id)?
            .seed()
            .map_err(WorldError::Key)?;
        markers.push(CoordinateMarker {
            marker_id: format!("marker:{i}"),
            site_id,
            x,
            y,
            archetype_id: if i == 0 {
                req.archetype_id.clone()
            } else {
                fallback.neighbor_archetype_id.clone()
            },
            site_seed: seed,
            selected: i == 0,
        });
    }
    let mut routes = Vec::with_capacity(10);
    for i in 1..9 {
        routes.push(authored_route(
            req,
            i,
            "marker:0",
            &format!("marker:{i}"),
            rules,
            fallback.route_cost_bp,
        )?);
    }
    routes.push(authored_route(
        req,
        9,
        "marker:0",
        "anchor:hub",
        rules,
        fallback.route_cost_bp,
    )?);
    routes.push(authored_route(
        req,
        10,
        "anchor:hub",
        "anchor:extraction",
        rules,
        fallback.route_cost_bp,
    )?);
    routes.sort_by(|a, b| (a.from.as_str(), a.to.as_str()).cmp(&(b.from.as_str(), b.to.as_str())));
    let mut biomes = Vec::with_capacity(9);
    let mut hazards = Vec::with_capacity(9);
    let mut resources = Vec::with_capacity(9);
    let mut landmarks = Vec::with_capacity(9);
    for (i, m) in markers.iter().enumerate() {
        biomes.push(BiomeField {
            marker_id: m.marker_id.clone(),
            biome_id: fallback.biome_id.clone(),
            intensity_bp: 5000,
        });
        hazards.push(HazardField {
            marker_id: m.marker_id.clone(),
            hazard_id: fallback.hazard_id.clone(),
            severity_bp: 1000,
        });
        resources.push(ResourcePressure {
            marker_id: m.marker_id.clone(),
            resource_id: fallback.resource_id.clone(),
            pressure_bp: 5000,
        });
        landmarks.push(LandmarkRecord {
            id: format!("landmark:{i}"),
            marker_id: m.marker_id.clone(),
            kind: fallback.landmarks[i % fallback.landmarks.len()].clone(),
        });
    }
    let world = WorldIR {
        schema_version: "world-ir-2".into(),
        world_seed: req.world_seed,
        site_id: req.site_id.clone(),
        x: req.x,
        y: req.y,
        archetype_id: req.archetype_id.clone(),
        site_seed: markers[0].site_seed,
        markers,
        routes,
        biome_fields: biomes,
        hazard_fields: hazards,
        resource_pressures: resources,
        landmarks,
        anchors: vec![
            WorldAnchor {
                id: "anchor:hub".into(),
                kind: "hub".into(),
            },
            WorldAnchor {
                id: "anchor:extraction".into(),
                kind: "extraction".into(),
            },
        ],
        extraction: ExtractionGuarantee {
            selected_marker_id: "marker:0".into(),
            hub_anchor_id: "anchor:hub".into(),
            extraction_anchor_id: "anchor:extraction".into(),
            path: vec![
                "marker:0".into(),
                "anchor:hub".into(),
                "anchor:extraction".into(),
            ],
        },
    };
    world.validate_for_fallback(req, rules, fallback)?;
    Ok(world)
}

fn derived_route(
    req: &WorldGenerationRequest,
    sub_index: u32,
    from: &str,
    to: &str,
    rules: &WorldRules,
) -> Result<RouteEdge, WorldError> {
    let site = if sub_index < 9 {
        to
    } else if sub_index == 9 {
        "anchor:hub"
    } else {
        "anchor:extraction"
    };
    let seed = key(
        req,
        "world",
        "world.route_cost",
        sub_index,
        req.x,
        req.y,
        site,
    )?
    .seed()
    .map_err(WorldError::Key)?;
    let (from, to) = canonical_edge(from, to);
    Ok(RouteEdge {
        from,
        to,
        cost_bp: in_range(seed, &rules.route_cost_bp),
    })
}
fn authored_route(
    req: &WorldGenerationRequest,
    sub_index: u32,
    from: &str,
    to: &str,
    rules: &WorldRules,
    cost_bp: u32,
) -> Result<RouteEdge, WorldError> {
    let _ = derived_route(req, sub_index, from, to, rules)?;
    let (from, to) = canonical_edge(from, to);
    Ok(RouteEdge { from, to, cost_bp })
}
fn key(
    r: &WorldGenerationRequest,
    d: &str,
    c: &str,
    n: u32,
    x: i32,
    y: i32,
    s: &str,
) -> Result<WorldKey, WorldError> {
    Ok(WorldKey {
        world_seed: r.world_seed,
        platform_version: r.platform_version,
        content_manifest_hash: r.content_manifest_hash.clone(),
        site_id: s.into(),
        x,
        y,
        domain: d.into(),
        channel: c.into(),
        sub_index: n,
    })
}

impl WorldIRv2 {
    pub fn validate_for_request(
        &self,
        req: &WorldGenerationRequest,
        rules: &WorldRules,
    ) -> Result<(), WorldError> {
        self.validate_for_request_mode(req, rules, None)
    }

    fn validate_for_fallback(
        &self,
        req: &WorldGenerationRequest,
        rules: &WorldRules,
        fallback: &WorldFallback,
    ) -> Result<(), WorldError> {
        fallback.validate(rules)?;
        self.validate_for_request_mode(req, rules, Some(fallback))
    }

    fn validate_for_request_mode(
        &self,
        req: &WorldGenerationRequest,
        rules: &WorldRules,
        fallback: Option<&WorldFallback>,
    ) -> Result<(), WorldError> {
        req.validate(rules)?;
        self.validate_with_rules(rules)?;
        if self.world_seed != req.world_seed
            || self.site_id != req.site_id
            || self.x != req.x
            || self.y != req.y
            || self.archetype_id != req.archetype_id
            || self.site_seed != self.markers[0].site_seed
        {
            return Err(WorldError::Invalid("request_identity"));
        }
        // Authored fallback fields are intentionally stable content rather
        // than generated channel rolls. Their references and bounds were
        // checked by validate_with_rules; identity, topology and routes still
        // undergo the complete request-key validation below.
        for (i, marker) in self.markers.iter().enumerate() {
            let (x, y, site_id, archetype) = if i == 0 {
                (req.x, req.y, req.site_id.clone(), req.archetype_id.clone())
            } else {
                let (x, y) =
                    radius_one_coordinates(req.x, req.y).map_err(WorldError::Invalid)?[i - 1];
                let sid = format!("site:{x}:{y}");
                let seed = key(req, "world", "world.archetype", (i - 1) as u32, x, y, &sid)?
                    .seed()
                    .map_err(WorldError::Key)?;
                let expected = &rules.archetypes[seed as usize % rules.archetypes.len()];
                if fallback.is_none() && marker.archetype_id != *expected {
                    return Err(WorldError::Invalid("marker_archetype"));
                }
                if let Some(f) = fallback {
                    if marker.archetype_id != f.neighbor_archetype_id {
                        return Err(WorldError::Invalid("fallback_archetype"));
                    }
                } else if marker.archetype_id != *expected {
                    return Err(WorldError::Invalid("marker_archetype"));
                }
                (x, y, sid, expected.clone())
            };
            if marker.x != x
                || marker.y != y
                || marker.site_id != site_id
                || (fallback.is_none() && marker.archetype_id != archetype)
                || marker.selected != (i == 0)
                || marker.site_seed
                    != key(req, "site", "site.structural", 0, x, y, &site_id)?
                        .seed()
                        .map_err(WorldError::Key)?
            {
                return Err(WorldError::Invalid("marker_identity"));
            }
            let channels = [
                ("world.biome", 0),
                ("world.hazard", 1),
                ("world.resource", 2),
                ("world.landmark", 3),
            ];
            for (channel, kind) in channels {
                let seed = key(req, "world", channel, i as u32, x, y, &site_id)?
                    .seed()
                    .map_err(WorldError::Key)?;
                match kind {
                    0 if fallback.is_none()
                        && (self.biome_fields[i].biome_id
                            != rules.biomes[seed as usize % rules.biomes.len()]
                            || self.biome_fields[i].intensity_bp != (seed % 10001) as u32) =>
                    {
                        return Err(WorldError::Invalid("biome"))
                    }
                    1 if fallback.is_none()
                        && (self.hazard_fields[i].hazard_id
                            != rules.hazards[seed as usize % rules.hazards.len()]
                            || self.hazard_fields[i].severity_bp != (seed % 10001) as u32) =>
                    {
                        return Err(WorldError::Invalid("hazard"))
                    }
                    2 if fallback.is_none()
                        && (self.resource_pressures[i].resource_id
                            != rules.resources[seed as usize % rules.resources.len()]
                            || self.resource_pressures[i].pressure_bp != (seed % 10001) as u32) =>
                    {
                        return Err(WorldError::Invalid("resource"))
                    }
                    3 if fallback.is_none()
                        && self.landmarks[i].kind
                            != rules.landmarks[seed as usize % rules.landmarks.len()] =>
                    {
                        return Err(WorldError::Invalid("landmark"))
                    }
                    _ => {}
                }
                if let Some(f) = fallback {
                    if self.biome_fields[i].biome_id != f.biome_id
                        || self.biome_fields[i].intensity_bp != 5000
                        || self.hazard_fields[i].hazard_id != f.hazard_id
                        || self.hazard_fields[i].severity_bp != 1000
                        || self.resource_pressures[i].resource_id != f.resource_id
                        || self.resource_pressures[i].pressure_bp != 5000
                        || self.landmarks[i].kind != f.landmarks[i % f.landmarks.len()]
                    {
                        return Err(WorldError::Invalid("fallback_content"));
                    }
                }
            }
        }
        let mut expected_routes = vec![
            (
                "anchor:extraction".to_string(),
                "anchor:hub".to_string(),
                10_u32,
                "anchor:extraction".to_string(),
            ),
            (
                "anchor:hub".to_string(),
                "marker:0".to_string(),
                9,
                "anchor:hub".to_string(),
            ),
        ];
        expected_routes.extend((1..9).map(|i| {
            (
                "marker:0".to_string(),
                format!("marker:{i}"),
                i as u32,
                format!("marker:{i}"),
            )
        }));
        expected_routes
            .sort_by(|a, b| (a.0.as_str(), a.1.as_str()).cmp(&(b.0.as_str(), b.1.as_str())));
        for (edge, (from, to, n, site)) in self.routes.iter().zip(expected_routes) {
            let seed = key(req, "world", "world.route_cost", n, req.x, req.y, &site)?
                .seed()
                .map_err(WorldError::Key)?;
            if edge.from != from
                || edge.to != to
                || (fallback.is_none() && edge.cost_bp != in_range(seed, &rules.route_cost_bp))
                || (fallback.is_some_and(|f| edge.cost_bp != f.route_cost_bp))
            {
                return Err(WorldError::Invalid("route"));
            }
        }
        Ok(())
    }
    pub fn validate_with_rules(&self, rules: &WorldRules) -> Result<(), WorldError> {
        rules.validate().map_err(|_| WorldError::Invalid("rules"))?;
        self.validate().map_err(WorldError::Invalid)?;
        if !rules.archetypes.iter().any(|a| a == &self.archetype_id) {
            return Err(WorldError::Invalid("archetype"));
        }
        if self
            .markers
            .iter()
            .any(|m| !rules.archetypes.iter().any(|a| a == &m.archetype_id))
        {
            return Err(WorldError::Invalid("marker_archetype"));
        }
        if self
            .biome_fields
            .iter()
            .any(|f| !rules.biomes.contains(&f.biome_id))
            || self
                .hazard_fields
                .iter()
                .any(|f| !rules.hazards.contains(&f.hazard_id))
            || self
                .resource_pressures
                .iter()
                .any(|f| !rules.resources.contains(&f.resource_id))
            || self
                .landmarks
                .iter()
                .any(|f| !rules.landmarks.contains(&f.kind))
        {
            return Err(WorldError::Invalid("field_family"));
        }
        if self.routes.iter().any(|r| {
            r.cost_bp < rules.route_cost_bp.min_bp || r.cost_bp > rules.route_cost_bp.max_bp
        }) {
            return Err(WorldError::Invalid("route_cost"));
        }
        Ok(())
    }
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.schema_version != "world-ir-2"
            || self.world_seed > MAX_PUBLIC_SEED
            || self.site_id.is_empty()
            || self.archetype_id.is_empty()
            || self.markers.len() != 9
            || self.routes.len() != 10
            || self.biome_fields.len() != 9
            || self.hazard_fields.len() != 9
            || self.resource_pressures.len() != 9
            || self.anchors.len() != 2
            || self.extraction.path != vec!["marker:0", "anchor:hub", "anchor:extraction"]
        {
            return Err("world_identity");
        }
        if self.anchors
            != vec![
                WorldAnchor {
                    id: "anchor:hub".into(),
                    kind: "hub".into(),
                },
                WorldAnchor {
                    id: "anchor:extraction".into(),
                    kind: "extraction".into(),
                },
            ]
        {
            return Err("anchors");
        }
        if self.markers.iter().enumerate().any(|(i, m)| {
            m.marker_id != format!("marker:{i}")
                || !valid_id(&m.marker_id)
                || !valid_id(&m.site_id)
                || !valid_id(&m.archetype_id)
                || m.site_seed > MAX_PUBLIC_SEED
                || m.selected != (i == 0)
        }) {
            return Err("markers");
        }
        let mut endpoints = BTreeSet::new();
        let known: BTreeSet<String> = (0..9)
            .map(|i| format!("marker:{i}"))
            .chain(["anchor:hub".to_string(), "anchor:extraction".to_string()])
            .collect();
        for edge in &self.routes {
            if edge.from.is_empty()
                || edge.to.is_empty()
                || !known.contains(&edge.from)
                || !known.contains(&edge.to)
                || edge.from >= edge.to
                || edge.cost_bp == 0
                || edge.cost_bp > 10_000
                || !endpoints.insert((edge.from.clone(), edge.to.clone()))
            {
                return Err("routes");
            }
        }
        if self.biome_fields.iter().enumerate().any(|(i, f)| {
            f.marker_id != self.markers[i].marker_id
                || !valid_id(&f.biome_id)
                || f.intensity_bp > 10_000
        }) || self.hazard_fields.iter().enumerate().any(|(i, f)| {
            f.marker_id != self.markers[i].marker_id
                || !valid_id(&f.hazard_id)
                || f.severity_bp > 10_000
        }) || self.resource_pressures.iter().enumerate().any(|(i, f)| {
            f.marker_id != self.markers[i].marker_id
                || !valid_id(&f.resource_id)
                || f.pressure_bp > 10_000
        }) || self.landmarks.iter().enumerate().any(|(i, f)| {
            f.id != format!("landmark:{i}")
                || f.marker_id != self.markers[i].marker_id
                || !valid_id(&f.id)
                || !valid_id(&f.kind)
        }) {
            return Err("fields");
        }
        if self.extraction.selected_marker_id != "marker:0"
            || self.extraction.hub_anchor_id != "anchor:hub"
            || self.extraction.extraction_anchor_id != "anchor:extraction"
            || self.extraction.path.windows(2).any(|pair| {
                !endpoints.contains(&(pair[0].clone(), pair[1].clone()))
                    && !endpoints.contains(&(pair[1].clone(), pair[0].clone()))
            })
        {
            return Err("extraction_path");
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn key() -> WorldKey {
        WorldKey {
            world_seed: 42,
            platform_version: 3,
            content_manifest_hash: "a".repeat(64),
            site_id: "site".into(),
            x: -1,
            y: 2,
            domain: "world".into(),
            channel: "biome".into(),
            sub_index: 0,
        }
    }
    #[test]
    fn full_key_is_bounded_and_sensitive() {
        let a = key().seed().unwrap();
        assert_eq!(a, 7_276_578_952_791_713);
        assert!(a <= MAX_PUBLIC_SEED);
        let mut b = key();
        b.y = 3;
        assert_ne!(a, b.seed().unwrap());
    }
    #[test]
    fn rejects_public_seed_overflow() {
        let mut k = key();
        k.world_seed = MAX_PUBLIC_SEED + 1;
        assert_eq!(k.seed(), Err("world_seed"));
    }
    #[test]
    fn negative_coordinates_are_distinct() {
        let mut a = key();
        a.x = -1;
        let mut b = a.clone();
        b.x = 1;
        assert_ne!(a.seed(), b.seed());
    }
    #[test]
    fn every_key_component_is_addressed() {
        let base = key().seed().unwrap();
        let mut variants = Vec::new();
        let mut k = key();
        k.world_seed += 1;
        variants.push(k);
        let mut k = key();
        k.platform_version = 4;
        variants.push(k);
        let mut k = key();
        k.content_manifest_hash = "b".repeat(64);
        variants.push(k);
        let mut k = key();
        k.site_id = "other".into();
        variants.push(k);
        let mut k = key();
        k.x += 1;
        variants.push(k);
        let mut k = key();
        k.y += 1;
        variants.push(k);
        let mut k = key();
        k.domain = "site".into();
        variants.push(k);
        let mut k = key();
        k.channel = "hazard".into();
        variants.push(k);
        let mut k = key();
        k.sub_index = 1;
        variants.push(k);
        assert!(variants.into_iter().all(|k| k.seed() != Ok(base)));
    }
    #[test]
    fn radius_one_is_canonical_and_excludes_center() {
        assert_eq!(
            radius_one_coordinates(4, 7).unwrap(),
            vec![
                (3, 6),
                (4, 6),
                (5, 6),
                (3, 7),
                (5, 7),
                (3, 8),
                (4, 8),
                (5, 8)
            ]
        );
    }
    #[test]
    fn bundled_rules_parse_and_generate_complete_candidate() {
        let rules = WorldRules::bundled().unwrap();
        rules.validate().unwrap();
        let req = WorldGenerationRequest {
            world_seed: 42,
            platform_version: 3,
            content_manifest_hash: "a".repeat(64),
            site_id: "selected".into(),
            x: 4,
            y: 7,
            archetype_id: "shuttle".into(),
        };
        let world = generate_candidate(&req, &rules).unwrap();
        assert_eq!(world.markers.len(), 9);
        assert_eq!(world.biome_fields.len(), 9);
        world.validate_with_rules(&rules).unwrap();
    }
    #[test]
    fn request_boundary_and_closed_json_are_rejected() {
        let rules = WorldRules::bundled().unwrap();
        let mut req = WorldGenerationRequest {
            world_seed: MAX_PUBLIC_SEED + 1,
            platform_version: 3,
            content_manifest_hash: "a".repeat(64),
            site_id: "s".into(),
            x: 1,
            y: 1,
            archetype_id: "shuttle".into(),
        };
        assert!(generate_candidate(&req, &rules).is_err());
        req.world_seed = 1;
        let bad = serde_json::to_string(&rules)
            .unwrap()
            .replace("}", ",\"extra\":1}");
        assert!(serde_json::from_str::<WorldRules>(&bad).is_err());
    }
    #[test]
    fn fallback_is_closed_and_does_not_force_archetype() {
        let fallback = WorldFallback::bundled().unwrap();
        fallback.validate(&WorldRules::bundled().unwrap()).unwrap();
        assert_eq!(fallback.platform_version, 3);
        assert!(serde_json::from_str::<WorldFallback>("{\"schema_version\":\"world-fallback-1\",\"platform_version\":3,\"fallback_id\":\"x\",\"biome_id\":\"b\",\"hazard_id\":\"h\",\"landmarks\":[],\"route_cost_bp\":1,\"extra\":1}").is_err());
    }

    #[test]
    fn world_key_rejects_malformed_identity_components() {
        let mut k = key();
        k.content_manifest_hash = "A".repeat(64);
        assert_eq!(k.seed(), Err("content_manifest_hash"));
        k = key();
        k.site_id = "SITE".into();
        assert_eq!(k.seed(), Err("identity"));
        k = key();
        k.domain = "x".repeat(MAX_ID_LEN + 1);
        assert_eq!(k.seed(), Err("identity"));
    }

    #[test]
    fn request_aware_validation_rejects_each_major_mutation() {
        let rules = WorldRules::bundled().unwrap();
        let req = WorldGenerationRequest {
            world_seed: 42,
            platform_version: 3,
            content_manifest_hash: "a".repeat(64),
            site_id: "selected".into(),
            x: 4,
            y: 7,
            archetype_id: "shuttle".into(),
        };
        let world = generate_candidate(&req, &rules).unwrap();
        let mutations: [fn(&mut WorldIRv2); 4] = [
            |w: &mut WorldIRv2| w.markers[1].x += 1,
            |w: &mut WorldIRv2| w.biome_fields[0].intensity_bp ^= 1,
            |w: &mut WorldIRv2| w.routes[0].cost_bp += 1,
            |w: &mut WorldIRv2| w.extraction.path.reverse(),
        ];
        for mutate in mutations {
            let mut altered = world.clone();
            mutate(&mut altered);
            assert!(altered.validate_for_request(&req, &rules).is_err());
        }
    }
}
