//! Build-manifest contract shared by native adapters and tooling.
use serde::{Deserialize, Serialize};

pub const MANIFEST_SCHEMA_V1: &str = "procgen-build-manifest-1";
pub const MANIFEST_SCHEMA_V2: &str = "procgen-build-manifest-2";
pub const MANIFEST_SCHEMA_V3: &str = "procgen-build-manifest-3";
pub const MANIFEST_SCHEMA_V4: &str = "procgen-build-manifest-4";
pub const MANIFEST_SCHEMA: &str = MANIFEST_SCHEMA_V4;
pub const CONTENT_MANIFEST_SCHEMA: &str = "procgen-content-manifest-1";
pub const PROCGEN_REQUEST_SCHEMA_V1: &str = "procgen-request-1";
pub const PROCGEN_REQUEST_SCHEMA_V2: &str = "procgen-request-2";
pub const PROCGEN_REQUEST_SCHEMA: &str = PROCGEN_REQUEST_SCHEMA_V2;
pub const PROCGEN_BUNDLE_SCHEMA_V1: &str = "procgen-bundle-1";
pub const WORLD_IR_SCHEMA_V1: &str = "world-ir-1";
pub const SITE_IR_SCHEMA_V1: &str = "site-ir-1";
pub const PROCGEN_BUNDLE_SCHEMA: &str = PROCGEN_BUNDLE_SCHEMA_V5;
pub const WORLD_IR_SCHEMA: &str = WORLD_IR_SCHEMA_V2;
pub const SITE_IR_SCHEMA: &str = SITE_IR_SCHEMA_V2;
pub const GAMEPLAY_IR_SCHEMA_V1: &str = "gameplay-ir-1";
pub const GAMEPLAY_IR_SCHEMA_V2: &str = "gameplay-ir-2";
pub const GAMEPLAY_IR_SCHEMA: &str = GAMEPLAY_IR_SCHEMA_V3;
pub const PRESENTATION_IR_SCHEMA_V1: &str = "presentation-ir-1";
pub const PRESENTATION_IR_SCHEMA_V2: &str = "presentation-ir-2";
pub const PRESENTATION_IR_SCHEMA: &str = PRESENTATION_IR_SCHEMA_V2;
pub const GENERATION_TRACE_SCHEMA_V1: &str = "generation-trace-1";
pub const GENERATION_TRACE_SCHEMA: &str = GENERATION_TRACE_SCHEMA_V4;
pub const ADAPTIVE_PROPOSAL_SCHEMA: &str = ADAPTIVE_PROPOSAL_SCHEMA_V2;
pub const PROCGEN_BUNDLE_SCHEMA_V2: &str = "procgen-bundle-2";
pub const WORLD_IR_SCHEMA_V2: &str = "world-ir-2";
pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA_V2: &str = "procgen-lifecycle-result-2";
pub const SITE_IR_SCHEMA_V2: &str = "site-ir-2";
pub const PROCGEN_BUNDLE_SCHEMA_V3: &str = "procgen-bundle-3";
pub const PROCGEN_BUNDLE_SCHEMA_V4: &str = "procgen-bundle-4";
pub const PROCGEN_BUNDLE_SCHEMA_V5: &str = "procgen-bundle-5";
pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3: &str = "procgen-lifecycle-result-3";
pub const GENERATION_TRACE_SCHEMA_V2: &str = "generation-trace-2";
pub const GENERATION_TRACE_SCHEMA_V3: &str = "generation-trace-3";
pub const GENERATION_TRACE_SCHEMA_V4: &str = "generation-trace-4";
pub const ADAPTIVE_PROPOSAL_SCHEMA_V1: &str = "adaptive-proposal-1";
pub const ADAPTIVE_PROPOSAL_SCHEMA_V2: &str = "adaptive-proposal-2";
pub const GAMEPLAY_IR_SCHEMA_V3: &str = "gameplay-ir-3";
pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA_V4: &str = "procgen-lifecycle-result-4";
pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA_V5: &str = "procgen-lifecycle-result-5";

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
pub struct Artifact {
    pub kind: String,
    pub path: String,
    pub sha256: String,
}

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
            procgen_request: PROCGEN_REQUEST_SCHEMA_V1.into(),
            procgen_bundle: PROCGEN_BUNDLE_SCHEMA_V1.into(),
            world_ir: WORLD_IR_SCHEMA_V1.into(),
            site_ir: SITE_IR_SCHEMA_V1.into(),
            gameplay_ir: GAMEPLAY_IR_SCHEMA_V1.into(),
            presentation_ir: PRESENTATION_IR_SCHEMA_V1.into(),
            generation_trace: GENERATION_TRACE_SCHEMA_V1.into(),
            adaptive_proposal: ADAPTIVE_PROPOSAL_SCHEMA_V1.into(),
        }
    }

    /// Current platform-v3 export map. The platform algorithm remains v3;
    /// Gate 2's mission overlay advances only the site and containing bundle.
    pub fn platform_v3() -> Self {
        Self {
            procgen_request: PROCGEN_REQUEST_SCHEMA_V1.into(),
            procgen_bundle: PROCGEN_BUNDLE_SCHEMA_V3.into(),
            world_ir: WORLD_IR_SCHEMA_V2.into(),
            site_ir: SITE_IR_SCHEMA_V2.into(),
            gameplay_ir: GAMEPLAY_IR_SCHEMA_V1.into(),
            presentation_ir: PRESENTATION_IR_SCHEMA_V1.into(),
            generation_trace: GENERATION_TRACE_SCHEMA_V2.into(),
            adaptive_proposal: ADAPTIVE_PROPOSAL_SCHEMA_V1.into(),
        }
    }

    pub fn platform_v4() -> Self {
        Self {
            procgen_request: PROCGEN_REQUEST_SCHEMA_V2.into(),
            procgen_bundle: PROCGEN_BUNDLE_SCHEMA_V4.into(),
            world_ir: WORLD_IR_SCHEMA_V2.into(),
            site_ir: SITE_IR_SCHEMA_V2.into(),
            gameplay_ir: GAMEPLAY_IR_SCHEMA_V2.into(),
            presentation_ir: PRESENTATION_IR_SCHEMA_V2.into(),
            generation_trace: GENERATION_TRACE_SCHEMA_V3.into(),
            adaptive_proposal: ADAPTIVE_PROPOSAL_SCHEMA_V1.into(),
        }
    }

    pub fn platform_v5() -> Self {
        Self {
            procgen_request: PROCGEN_REQUEST_SCHEMA_V2.into(),
            procgen_bundle: PROCGEN_BUNDLE_SCHEMA_V5.into(),
            world_ir: WORLD_IR_SCHEMA_V2.into(),
            site_ir: SITE_IR_SCHEMA_V2.into(),
            gameplay_ir: GAMEPLAY_IR_SCHEMA_V3.into(),
            presentation_ir: PRESENTATION_IR_SCHEMA_V2.into(),
            generation_trace: GENERATION_TRACE_SCHEMA_V4.into(),
            adaptive_proposal: ADAPTIVE_PROPOSAL_SCHEMA_V2.into(),
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
pub struct ContentFile {
    pub path: String,
    pub sha256: String,
}

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
    /// Validate the additive Gate-2 platform manifest without weakening the
    /// established v1 manifest validator used by structural artifacts.
    pub fn validate_platform_v3(&self) -> Result<(), ManifestError> {
        if self.manifest_schema != MANIFEST_SCHEMA_V2 {
            return Err(
                if self.manifest_schema.starts_with("procgen-build-manifest-") {
                    ManifestError::UnknownSchemaMajor(self.manifest_schema.clone())
                } else {
                    ManifestError::InvalidField("manifest_schema")
                },
            );
        }
        if self.generator_version != 3 {
            return Err(ManifestError::InvalidField("generator_version"));
        }
        if self.export_schemas != ExportSchemas::platform_v3() {
            return Err(ManifestError::InvalidField("export_schemas"));
        }
        if self.rust_source_commit.len() != 40
            || !is_hex(&self.rust_source_commit)
            || self.rust_source_commit != self.rust_source_commit.to_ascii_lowercase()
            || self.content_manifest_path != "data/procgen/manifests/content_manifest.json"
            || !is_sha256(&self.content_manifest_hash)
            || !is_sha256(&self.artifact.sha256)
        {
            return Err(ManifestError::InvalidField("manifest"));
        }
        let valid_pair = matches!(
            (
                self.target.as_str(),
                self.artifact.kind.as_str(),
                self.artifact.path.as_str()
            ),
            (
                "x86_64-pc-windows-msvc",
                "gdextension",
                "addons/derelict/bin/win64/derelict_godot.dll"
            ) | (
                "wasm32-unknown-unknown",
                "wasm",
                "addons/derelict/bin/web/derelict_wasm_bg.wasm"
            )
        );
        if !valid_pair {
            return Err(ManifestError::InvalidField("artifact"));
        }
        Ok(())
    }

    pub fn from_json(json: &str) -> Result<Self, ManifestError> {
        let manifest: Self = serde_json::from_str(json)?;
        manifest.validate_platform_v5()?;
        Ok(manifest)
    }

    pub fn from_json_platform_v1(json: &str) -> Result<Self, ManifestError> {
        let manifest: Self = serde_json::from_str(json)?;
        manifest.validate_platform_v1()?;
        Ok(manifest)
    }

    pub fn validate(&self) -> Result<(), ManifestError> {
        self.validate_platform_v5()
    }

    pub fn from_json_platform_v3(json: &str) -> Result<Self, ManifestError> {
        let manifest: Self = serde_json::from_str(json)?;
        manifest.validate_platform_v3()?;
        Ok(manifest)
    }

    pub fn validate_platform_v4(&self) -> Result<(), ManifestError> {
        if self.manifest_schema != MANIFEST_SCHEMA_V3 {
            return Err(
                if self.manifest_schema.starts_with("procgen-build-manifest-") {
                    ManifestError::UnknownSchemaMajor(self.manifest_schema.clone())
                } else {
                    ManifestError::InvalidField("manifest_schema")
                },
            );
        }
        if self.generator_version != 3 {
            return Err(ManifestError::InvalidField("generator_version"));
        }
        if self.export_schemas != ExportSchemas::platform_v4() {
            return Err(ManifestError::InvalidField("export_schemas"));
        }
        if self.rust_source_commit.len() != 40
            || !is_hex(&self.rust_source_commit)
            || self.rust_source_commit != self.rust_source_commit.to_ascii_lowercase()
            || self.content_manifest_path != "data/procgen/manifests/content_manifest.json"
            || !is_sha256(&self.content_manifest_hash)
            || !is_sha256(&self.artifact.sha256)
        {
            return Err(ManifestError::InvalidField("manifest"));
        }
        let valid_pair = matches!(
            (
                self.target.as_str(),
                self.artifact.kind.as_str(),
                self.artifact.path.as_str()
            ),
            (
                "x86_64-pc-windows-msvc",
                "gdextension",
                "addons/derelict/bin/win64/derelict_godot.dll"
            ) | (
                "wasm32-unknown-unknown",
                "wasm",
                "addons/derelict/bin/web/derelict_wasm_bg.wasm"
            )
        );
        if !valid_pair {
            return Err(ManifestError::InvalidField("artifact"));
        }
        Ok(())
    }

    pub fn from_json_platform_v4(json: &str) -> Result<Self, ManifestError> {
        let manifest: Self = serde_json::from_str(json)?;
        manifest.validate_platform_v4()?;
        Ok(manifest)
    }

    pub fn validate_platform_v5(&self) -> Result<(), ManifestError> {
        if self.manifest_schema != MANIFEST_SCHEMA_V4 {
            return Err(
                if self.manifest_schema.starts_with("procgen-build-manifest-") {
                    ManifestError::UnknownSchemaMajor(self.manifest_schema.clone())
                } else {
                    ManifestError::InvalidField("manifest_schema")
                },
            );
        }
        if self.generator_version != 3 || self.export_schemas != ExportSchemas::platform_v5() {
            return Err(ManifestError::InvalidField("export_schemas"));
        }
        if self.rust_source_commit.len() != 40
            || !is_hex(&self.rust_source_commit)
            || self.rust_source_commit != self.rust_source_commit.to_ascii_lowercase()
            || self.content_manifest_path != "data/procgen/manifests/content_manifest.json"
            || !is_sha256(&self.content_manifest_hash)
            || !is_sha256(&self.artifact.sha256)
        {
            return Err(ManifestError::InvalidField("manifest"));
        }
        let valid_pair = matches!(
            (
                self.target.as_str(),
                self.artifact.kind.as_str(),
                self.artifact.path.as_str()
            ),
            (
                "x86_64-pc-windows-msvc",
                "gdextension",
                "addons/derelict/bin/win64/derelict_godot.dll"
            ) | (
                "wasm32-unknown-unknown",
                "wasm",
                "addons/derelict/bin/web/derelict_wasm_bg.wasm"
            )
        );
        if !valid_pair {
            return Err(ManifestError::InvalidField("artifact"));
        }
        Ok(())
    }

    pub fn from_json_platform_v5(json: &str) -> Result<Self, ManifestError> {
        let manifest: Self = serde_json::from_str(json)?;
        manifest.validate_platform_v5()?;
        Ok(manifest)
    }

    pub fn validate_platform_v1(&self) -> Result<(), ManifestError> {
        if self.manifest_schema != MANIFEST_SCHEMA_V1 {
            return Err(
                if self.manifest_schema.starts_with("procgen-build-manifest-") {
                    ManifestError::UnknownSchemaMajor(self.manifest_schema.clone())
                } else {
                    ManifestError::InvalidField("manifest_schema")
                },
            );
        }
        if self.rust_source_commit.len() != 40 || !is_hex(&self.rust_source_commit) {
            return Err(ManifestError::InvalidField("rust_source_commit"));
        }
        if self.generator_version != 2 {
            return Err(ManifestError::InvalidField("generator_version"));
        }
        if self.content_manifest_path != "data/procgen/manifests/content_manifest.json" {
            return Err(ManifestError::InvalidField("content_manifest_path"));
        }
        if !is_sha256(&self.content_manifest_hash) {
            return Err(ManifestError::InvalidField("content_manifest_hash"));
        }
        let valid_pair = matches!(
            (
                self.target.as_str(),
                self.artifact.kind.as_str(),
                self.artifact.path.as_str()
            ),
            (
                "x86_64-pc-windows-msvc",
                "gdextension",
                "addons/derelict/bin/win64/derelict_godot.dll"
            ) | (
                "wasm32-unknown-unknown",
                "wasm",
                "addons/derelict/bin/web/derelict_wasm_bg.wasm"
            )
        );
        if !valid_pair || !is_sha256(&self.artifact.sha256) {
            return Err(ManifestError::InvalidField("artifact"));
        }
        let schemas = [
            (
                "procgen_request",
                &self.export_schemas.procgen_request,
                "procgen-request-1",
            ),
            (
                "procgen_bundle",
                &self.export_schemas.procgen_bundle,
                "procgen-bundle-1",
            ),
            ("world_ir", &self.export_schemas.world_ir, "world-ir-1"),
            ("site_ir", &self.export_schemas.site_ir, "site-ir-1"),
            (
                "gameplay_ir",
                &self.export_schemas.gameplay_ir,
                "gameplay-ir-1",
            ),
            (
                "presentation_ir",
                &self.export_schemas.presentation_ir,
                "presentation-ir-1",
            ),
            (
                "generation_trace",
                &self.export_schemas.generation_trace,
                "generation-trace-1",
            ),
            (
                "adaptive_proposal",
                &self.export_schemas.adaptive_proposal,
                "adaptive-proposal-1",
            ),
        ];
        for (field, actual, expected) in schemas {
            if actual != expected {
                return Err(ManifestError::InvalidField(field));
            }
        }
        Ok(())
    }

    pub fn content_from_json(json: &str) -> Result<ContentManifest, ManifestError> {
        let content: ContentManifest = serde_json::from_str(json)?;
        if content.manifest_schema != CONTENT_MANIFEST_SCHEMA
            || !is_sha256(&content.content_manifest_hash)
        {
            return Err(ManifestError::InvalidField("content_manifest"));
        }
        let mut previous = None;
        for file in &content.files {
            if !file.path.is_ascii()
                || file.path.contains('\\')
                || file.path.contains(':')
                || file.path.starts_with('/')
                || file
                    .path
                    .split('/')
                    .any(|part| part.is_empty() || part == "." || part == "..")
                || !is_sha256(&file.sha256)
            {
                return Err(ManifestError::InvalidField("content_manifest.files"));
            }
            if let Some(prev) = previous {
                if prev >= file.path.as_str() {
                    return Err(ManifestError::InvalidField("content_manifest.files"));
                }
            }
            previous = Some(file.path.as_str());
        }
        Ok(content)
    }
}

fn is_hex(value: &str) -> bool {
    value
        .bytes()
        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn is_sha256(value: &str) -> bool {
    value.len() == 64 && is_hex(value) && value == value.to_ascii_lowercase()
}
