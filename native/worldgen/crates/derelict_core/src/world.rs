//! Coordinate-addressed platform-v3 world identity and bounded world-domain
//! contracts.  This module deliberately does not alter the structural v2
//! ship generator.
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

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
        if self.site_id.is_empty() || self.domain.is_empty() || self.channel.is_empty() {
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
pub struct SiteRecord {
    pub site_id: String,
    pub x: i32,
    pub y: i32,
    pub archetype_id: String,
    pub site_seed: u64,
    pub selected: bool,
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

/// Canonical radius-one sector: center first, then row-major neighbors.
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
            .any(|s| s.is_empty())
            || self.archetypes.iter().collect::<BTreeSet<_>>().len() != self.archetypes.len()
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
}
impl WorldGenerationRequest {
    fn validate(&self, rules: &WorldRules) -> Result<(), WorldError> {
        if self.world_seed > MAX_PUBLIC_SEED
            || self.platform_version != 3
            || self.site_id.is_empty()
            || !rules.archetypes.iter().any(|a| a == &self.archetype_id)
            || self.x == i32::MIN
            || self.x == i32::MAX
            || self.y == i32::MIN
            || self.y == i32::MAX
        {
            return Err(WorldError::Invalid("request"));
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
    let mut markers = vec![CoordinateMarker {
        marker_id: "marker:0".into(),
        site_id: req.site_id.clone(),
        x: req.x,
        y: req.y,
        archetype_id: req.archetype_id.clone(),
        site_seed: key(
            req,
            "site",
            "site.structural",
            0,
            req.x,
            req.y,
            &req.site_id,
        )?
        .seed()
        .map_err(WorldError::Key)?,
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
        routes.push(RouteEdge {
            from: "marker:0".into(),
            to: format!("marker:{i}"),
            cost_bp: rules.route_cost_bp.min_bp,
        });
    }
    routes.push(RouteEdge {
        from: "anchor:hub".into(),
        to: "marker:0".into(),
        cost_bp: rules.route_cost_bp.min_bp,
    });
    routes.push(RouteEdge {
        from: "anchor:extraction".into(),
        to: "anchor:hub".into(),
        cost_bp: rules.route_cost_bp.min_bp,
    });
    routes.sort_by(|a, b| (a.from.as_str(), a.to.as_str()).cmp(&(b.from.as_str(), b.to.as_str())));
    let fields = |domain: &str, channel: &str, values: &Vec<CoordinateMarker>| {
        values
            .iter()
            .enumerate()
            .map(|(i, m)| {
                let s = key(req, domain, channel, i as u32, m.x, m.y, &m.site_id)
                    .ok()
                    .and_then(|k| k.seed().ok())
                    .unwrap_or(0);
                (i, s)
            })
            .collect::<Vec<_>>()
    };
    let biome_fields = markers
        .iter()
        .enumerate()
        .map(|(i, m)| BiomeField {
            marker_id: m.marker_id.clone(),
            biome_id: rules.biomes
                [fields("world", "world.biome", &markers)[i].1 as usize % rules.biomes.len()]
            .clone(),
            intensity_bp: fields("world", "world.biome", &markers)[i].1 as u32 % 10001,
        })
        .collect();
    let hazard_fields = markers
        .iter()
        .enumerate()
        .map(|(i, m)| HazardField {
            marker_id: m.marker_id.clone(),
            hazard_id: rules.hazards
                [fields("world", "world.hazard", &markers)[i].1 as usize % rules.hazards.len()]
            .clone(),
            severity_bp: fields("world", "world.hazard", &markers)[i].1 as u32 % 10001,
        })
        .collect();
    let resource_pressures = markers
        .iter()
        .enumerate()
        .map(|(i, m)| ResourcePressure {
            marker_id: m.marker_id.clone(),
            resource_id: rules.resources
                [fields("world", "world.resource", &markers)[i].1 as usize % rules.resources.len()]
            .clone(),
            pressure_bp: fields("world", "world.resource", &markers)[i].1 as u32 % 10001,
        })
        .collect();
    let landmarks = markers
        .iter()
        .enumerate()
        .map(|(i, m)| LandmarkRecord {
            id: format!("landmark:{i}"),
            marker_id: m.marker_id.clone(),
            kind: rules.landmarks
                [fields("world", "world.landmark", &markers)[i].1 as usize % rules.landmarks.len()]
            .clone(),
        })
        .collect();
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
    world.validate_with_rules(rules)?;
    Ok(world)
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
        if self
            .markers
            .iter()
            .enumerate()
            .any(|(i, m)| m.marker_id != format!("marker:{i}") || m.site_seed > MAX_PUBLIC_SEED)
        {
            return Err("markers");
        }
        let mut endpoints = BTreeSet::new();
        for edge in &self.routes {
            if edge.from.is_empty()
                || edge.to.is_empty()
                || edge.from >= edge.to
                || edge.cost_bp == 0
                || edge.cost_bp > 100_000
                || !endpoints.insert((edge.from.clone(), edge.to.clone()))
            {
                return Err("routes");
            }
        }
        if self.extraction.path.windows(2).any(|pair| {
            !endpoints.contains(&(pair[0].clone(), pair[1].clone()))
                && !endpoints.contains(&(pair[1].clone(), pair[0].clone()))
        }) {
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
}
