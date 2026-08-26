//! Build-manifest contract shared by native adapters and tooling.
use serde::{Deserialize, Serialize};

pub const MANIFEST_SCHEMA: &str = "procgen-build-manifest-1";
pub const CONTENT_MANIFEST_SCHEMA: &str = "procgen-content-manifest-1";
pub const PROCGEN_REQUEST_SCHEMA: &str = "procgen-request-1";
pub const PROCGEN_BUNDLE_SCHEMA: &str = "procgen-bundle-1";
pub const WORLD_IR_SCHEMA: &str = "world-ir-1";
pub const SITE_IR_SCHEMA: &str = "site-ir-1";
pub const GAMEPLAY_IR_SCHEMA: &str = "gameplay-ir-1";
pub const PRESENTATION_IR_SCHEMA: &str = "presentation-ir-1";
pub const GENERATION_TRACE_SCHEMA: &str = "generation-trace-1";
pub const ADAPTIVE_PROPOSAL_SCHEMA: &str = "adaptive-proposal-1";

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct BuildManifest {
    pub manifest_schema: String,
    pub rust_source_commit: String,
    pub generator_version: u32,
    pub content_manifest_path: String,
    pub content_manifest_hash: String,
    pub target: String,
    pub artifact: Artifact,
    pub export_schemas: ExportSchemas,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Artifact { pub kind: String, pub path: String, pub sha256: String }

#[derive(Debug, Deserialize, Serialize, Clone, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
#[derive(schemars::JsonSchema)]
pub struct ExportSchemas {
    pub procgen_request: String,
    pub procgen_bundle: String,
    pub world_ir: String,
    pub site_ir: String,
    pub gameplay_ir: String,
    pub presentation_ir: String,
    pub generation_trace: String,
    pub adaptive_proposal: String,
}

impl ExportSchemas {
    pub fn v1() -> Self {
        Self {
            procgen_request: PROCGEN_REQUEST_SCHEMA.into(), procgen_bundle: PROCGEN_BUNDLE_SCHEMA.into(),
            world_ir: WORLD_IR_SCHEMA.into(), site_ir: SITE_IR_SCHEMA.into(), gameplay_ir: GAMEPLAY_IR_SCHEMA.into(),
            presentation_ir: PRESENTATION_IR_SCHEMA.into(), generation_trace: GENERATION_TRACE_SCHEMA.into(), adaptive_proposal: ADAPTIVE_PROPOSAL_SCHEMA.into(),
        }
    }
}

#[derive(Debug, Deserialize, Clone, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ContentManifest {
    pub manifest_schema: String,
    pub files: Vec<ContentFile>,
    pub content_manifest_hash: String,
}

#[derive(Debug, Deserialize, Clone, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ContentFile { pub path: String, pub sha256: String }

#[derive(Debug, thiserror::Error)]
pub enum ManifestError {
    #[error("manifest JSON parse failed: {0}")]
    Parse(#[from] serde_json::Error),
    #[error("unknown manifest schema major: {0}")]
    UnknownSchemaMajor(String),
    #[error("manifest field {0} is invalid")]
    InvalidField(&'static str),
}

impl BuildManifest {
    pub fn from_json(json: &str) -> Result<Self, ManifestError> {
        let manifest: Self = serde_json::from_str(json)?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn validate(&self) -> Result<(), ManifestError> {
        if self.manifest_schema != MANIFEST_SCHEMA {
            return Err(if self.manifest_schema.starts_with("procgen-build-manifest-") {
                ManifestError::UnknownSchemaMajor(self.manifest_schema.clone())
            } else { ManifestError::InvalidField("manifest_schema") });
        }
        if self.rust_source_commit.len() != 40 || !is_hex(&self.rust_source_commit) { return Err(ManifestError::InvalidField("rust_source_commit")); }
        if self.generator_version != 2 { return Err(ManifestError::InvalidField("generator_version")); }
        if self.content_manifest_path != "data/procgen/manifests/content_manifest.json" { return Err(ManifestError::InvalidField("content_manifest_path")); }
        if !is_sha256(&self.content_manifest_hash) { return Err(ManifestError::InvalidField("content_manifest_hash")); }
        if self.target != "x86_64-pc-windows-msvc" { return Err(ManifestError::InvalidField("target")); }
        if self.artifact.kind != "gdextension" || self.artifact.path != "addons/derelict/bin/win64/derelict_godot.dll" || !is_sha256(&self.artifact.sha256) { return Err(ManifestError::InvalidField("artifact")); }
        let schemas = [
            ("procgen_request", &self.export_schemas.procgen_request, "procgen-request-1"),
            ("procgen_bundle", &self.export_schemas.procgen_bundle, "procgen-bundle-1"),
            ("world_ir", &self.export_schemas.world_ir, "world-ir-1"),
            ("site_ir", &self.export_schemas.site_ir, "site-ir-1"),
            ("gameplay_ir", &self.export_schemas.gameplay_ir, "gameplay-ir-1"),
            ("presentation_ir", &self.export_schemas.presentation_ir, "presentation-ir-1"),
            ("generation_trace", &self.export_schemas.generation_trace, "generation-trace-1"),
            ("adaptive_proposal", &self.export_schemas.adaptive_proposal, "adaptive-proposal-1"),
        ];
        for (field, actual, expected) in schemas { if actual != expected { return Err(ManifestError::InvalidField(field)); } }
        Ok(())
    }

    pub fn content_from_json(json: &str) -> Result<ContentManifest, ManifestError> {
        let content: ContentManifest = serde_json::from_str(json)?;
        if content.manifest_schema != CONTENT_MANIFEST_SCHEMA || !is_sha256(&content.content_manifest_hash) {
            return Err(ManifestError::InvalidField("content_manifest"));
        }
        let mut previous = None;
        for file in &content.files {
            if !file.path.is_ascii() || file.path.contains('\\') || file.path.contains(':') || file.path.starts_with('/') || file.path.split('/').any(|part| part.is_empty() || part == "." || part == "..") || !is_sha256(&file.sha256) {
                return Err(ManifestError::InvalidField("content_manifest.files"));
            }
            if let Some(prev) = previous { if prev >= file.path.as_str() { return Err(ManifestError::InvalidField("content_manifest.files")); } }
            previous = Some(file.path.as_str());
        }
        Ok(content)
    }
}

fn is_hex(value: &str) -> bool { value.bytes().all(|b| b.is_ascii_digit() || (b >= b'a' && b <= b'f')) }
fn is_sha256(value: &str) -> bool { value.len() == 64 && is_hex(value) && value == value.to_ascii_lowercase() }
