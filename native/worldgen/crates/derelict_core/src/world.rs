//! Coordinate-addressed platform-v3 world identity and bounded world-domain
//! contracts.  This module deliberately does not alter the structural v2
//! ship generator.
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

/// Platform contract version.  `model::GENERATOR_VERSION` remains structural v2.
pub const PROCGEN_GENERATOR_VERSION: u32 = 3;
pub const MAX_PUBLIC_SEED: u64 = 9_007_199_254_740_991;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoordinateMarker {
    pub x: i32,
    pub y: i32,
    pub kind: String,
    pub value: i32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RouteEdge {
    pub from: String,
    pub to: String,
    pub cost_bp: u32,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
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
    pub biome_id: String,
    pub hazard_id: String,
    pub resource_pressure_bp: u32,
    pub landmarks: Vec<String>,
    pub extraction_path: Vec<String>,
}

/// Current platform world document. The explicit v2 suffix above makes the
/// schema transition visible at call sites while this alias keeps the domain
/// API ergonomic for consumers.
pub type WorldIR = WorldIRv2;

impl WorldIRv2 {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.schema_version != "world-ir-2"
            || self.world_seed > MAX_PUBLIC_SEED
            || self.site_id.is_empty()
            || self.archetype_id.is_empty()
            || self.biome_id.is_empty()
            || self.hazard_id.is_empty()
            || self.extraction_path.len() < 3
            || self.resource_pressure_bp > 100_000
        {
            return Err("world_identity");
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
        if self.extraction_path.windows(2).any(|pair| {
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
}
