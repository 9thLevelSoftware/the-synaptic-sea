//! Target-neutral lifecycle, capability, and generator identity contracts.
use crate::manifest::ExportSchemas;
use crate::procgen::{Domain, ProcgenBundle, ProcgenError, ProcgenFailure};
use crate::world::PROCGEN_GENERATOR_VERSION;
use serde::{Deserialize, Serialize};

pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA: &str =
    crate::manifest::PROCGEN_LIFECYCLE_RESULT_SCHEMA_V5;
pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA_V2: &str =
    crate::manifest::PROCGEN_LIFECYCLE_RESULT_SCHEMA_V2;
pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3: &str =
    crate::manifest::PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3;
pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA_V4: &str =
    crate::manifest::PROCGEN_LIFECYCLE_RESULT_SCHEMA_V4;
pub const PROCGEN_LIFECYCLE_RESULT_SCHEMA_V5: &str =
    crate::manifest::PROCGEN_LIFECYCLE_RESULT_SCHEMA_V5;
pub const PROCGEN_CAPABILITIES_SCHEMA_V1: &str = "procgen-capabilities-1";
pub const PROCGEN_CAPABILITIES_SCHEMA_V2: &str = "procgen-capabilities-2";
pub const PROCGEN_CAPABILITIES_SCHEMA_V3: &str = "procgen-capabilities-3";
pub const PROCGEN_CAPABILITIES_SCHEMA_V4: &str = "procgen-capabilities-4";
pub const PROCGEN_CAPABILITIES_SCHEMA: &str = PROCGEN_CAPABILITIES_SCHEMA_V4;
pub const PROCGEN_GENERATOR_MANIFEST_SCHEMA_V1: &str = "procgen-generator-manifest-1";
pub const PROCGEN_GENERATOR_MANIFEST_SCHEMA_V2: &str = "procgen-generator-manifest-2";
pub const PROCGEN_GENERATOR_MANIFEST_SCHEMA_V3: &str = "procgen-generator-manifest-3";
pub const PROCGEN_GENERATOR_MANIFEST_SCHEMA_V4: &str = "procgen-generator-manifest-4";
pub const PROCGEN_GENERATOR_MANIFEST_SCHEMA: &str = PROCGEN_GENERATOR_MANIFEST_SCHEMA_V4;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum LifecycleStatus {
    Accepted,
    Queued,
    Running,
    CancelRequested,
    Completed,
    Failed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum LifecycleEvent {
    Rejected,
    Admitted,
    Queued,
    Started,
    CancelRequested,
    Cancelled,
    TimedOut,
    Completed,
    Failed,
    Overloaded,
    ResultConsumed,
    ResultExpired,
    Shutdown,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LifecycleResult {
    pub schema_version: String,
    pub status: LifecycleStatus,
    #[serde(default)]
    pub request_id: Option<i64>,
    #[serde(default)]
    pub bundle: Option<ProcgenBundle>,
    #[serde(default)]
    pub failure: Option<ProcgenFailure>,
    #[schemars(length(min = 1, max = 32))]
    pub events: Vec<LifecycleEvent>,
}

impl LifecycleResult {
    pub fn from_json(json: &str) -> Result<Self, LifecycleError> {
        let result: Self = serde_json::from_str(json)?;
        result.validate()?;
        Ok(result)
    }

    pub fn accepted(request_id: i64, events: Vec<LifecycleEvent>) -> Self {
        Self::new(
            LifecycleStatus::Accepted,
            Some(request_id),
            None,
            None,
            events,
        )
    }
    pub fn queued(request_id: i64, events: Vec<LifecycleEvent>) -> Self {
        Self::new(
            LifecycleStatus::Queued,
            Some(request_id),
            None,
            None,
            events,
        )
    }
    pub fn running(request_id: i64, events: Vec<LifecycleEvent>) -> Self {
        Self::new(
            LifecycleStatus::Running,
            Some(request_id),
            None,
            None,
            events,
        )
    }
    pub fn cancel_requested(request_id: i64, events: Vec<LifecycleEvent>) -> Self {
        Self::new(
            LifecycleStatus::CancelRequested,
            Some(request_id),
            None,
            None,
            events,
        )
    }
    pub fn failed(
        request_id: Option<i64>,
        failure: ProcgenFailure,
        events: Vec<LifecycleEvent>,
    ) -> Self {
        Self::new(
            LifecycleStatus::Failed,
            request_id,
            None,
            Some(failure),
            events,
        )
    }
    pub fn completed(
        request_id: Option<i64>,
        bundle: ProcgenBundle,
        events: Vec<LifecycleEvent>,
    ) -> Self {
        Self::new(
            LifecycleStatus::Completed,
            request_id,
            Some(bundle),
            None,
            events,
        )
    }
    fn new(
        status: LifecycleStatus,
        request_id: Option<i64>,
        bundle: Option<ProcgenBundle>,
        failure: Option<ProcgenFailure>,
        events: Vec<LifecycleEvent>,
    ) -> Self {
        Self {
            schema_version: PROCGEN_LIFECYCLE_RESULT_SCHEMA.into(),
            status,
            request_id,
            bundle,
            failure,
            events,
        }
    }

    pub fn validate(&self) -> Result<(), LifecycleError> {
        if self.schema_version != PROCGEN_LIFECYCLE_RESULT_SCHEMA {
            return Err(LifecycleError::Invalid("schema_version"));
        }
        if self.events.is_empty() || self.events.len() > 32 {
            return Err(LifecycleError::Invalid("events"));
        }
        if self.request_id.is_some_and(|id| id <= 0) {
            return Err(LifecycleError::Invalid("request_id"));
        }
        match self.status {
            LifecycleStatus::Accepted
            | LifecycleStatus::Queued
            | LifecycleStatus::Running
            | LifecycleStatus::CancelRequested => {
                if self.request_id.is_none() || self.bundle.is_some() || self.failure.is_some() {
                    return Err(LifecycleError::Invalid("state"));
                }
            }
            LifecycleStatus::Completed => {
                if self.bundle.is_none() || self.failure.is_some() {
                    return Err(LifecycleError::Invalid("state"));
                }
                self.bundle
                    .as_ref()
                    .unwrap()
                    .validate()
                    .map_err(LifecycleError::Bundle)?;
            }
            LifecycleStatus::Failed => {
                if self.bundle.is_some() || self.failure.is_none() {
                    return Err(LifecycleError::Invalid("state"));
                }
                self.failure
                    .as_ref()
                    .unwrap()
                    .validate()
                    .map_err(LifecycleError::Failure)?;
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct AdapterSchemas {
    pub lifecycle_result: String,
    pub capabilities: String,
    pub generator_manifest: String,
}
impl AdapterSchemas {
    pub fn v1() -> Self {
        Self {
            lifecycle_result: "procgen-lifecycle-result-1".into(),
            capabilities: PROCGEN_CAPABILITIES_SCHEMA_V1.into(),
            generator_manifest: PROCGEN_GENERATOR_MANIFEST_SCHEMA_V1.into(),
        }
    }
    fn validate(&self) -> Result<(), LifecycleError> {
        if self != &Self::platform_v5() {
            Err(LifecycleError::Invalid("schemas"))
        } else {
            Ok(())
        }
    }
    pub fn platform_v3() -> Self {
        Self {
            lifecycle_result: PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3.into(),
            capabilities: PROCGEN_CAPABILITIES_SCHEMA_V2.into(),
            generator_manifest: PROCGEN_GENERATOR_MANIFEST_SCHEMA_V2.into(),
        }
    }

    pub fn platform_v4() -> Self {
        Self {
            lifecycle_result: PROCGEN_LIFECYCLE_RESULT_SCHEMA_V4.into(),
            capabilities: PROCGEN_CAPABILITIES_SCHEMA_V3.into(),
            generator_manifest: PROCGEN_GENERATOR_MANIFEST_SCHEMA_V3.into(),
        }
    }

    pub fn platform_v5() -> Self {
        Self {
            lifecycle_result: PROCGEN_LIFECYCLE_RESULT_SCHEMA_V5.into(),
            capabilities: PROCGEN_CAPABILITIES_SCHEMA_V4.into(),
            generator_manifest: PROCGEN_GENERATOR_MANIFEST_SCHEMA_V4.into(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AdapterKind {
    Native,
    Web,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum WorkerMode {
    ThreadPool,
    Cooperative,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ProcgenCapabilities {
    pub schema_version: String,
    pub adapter_kind: AdapterKind,
    pub target: String,
    pub supports_sync: bool,
    pub supports_async: bool,
    pub supports_cancel: bool,
    pub worker_mode: WorkerMode,
    pub worker_count: u32,
    pub queue_capacity: u32,
    pub retained_results: u32,
    pub max_request_bytes: u64,
    pub max_entities: u32,
    pub max_trace_entries: u32,
    pub max_events: u32,
    pub deadline_ms: u64,
    pub supported_domains: Vec<Domain>,
    pub schemas: AdapterSchemas,
}
impl ProcgenCapabilities {
    pub fn from_json(json: &str) -> Result<Self, LifecycleError> {
        let value: Self = serde_json::from_str(json)?;
        value.validate()?;
        Ok(value)
    }

    pub fn validate(&self) -> Result<(), LifecycleError> {
        if self.schema_version != PROCGEN_CAPABILITIES_SCHEMA || self.target.is_empty() {
            return Err(LifecycleError::Invalid("identity"));
        }
        if self.worker_mode == WorkerMode::ThreadPool && self.worker_count == 0 {
            return Err(LifecycleError::Invalid("worker_count"));
        }
        if self.queue_capacity == 0
            || self.retained_results == 0
            || self.max_request_bytes == 0
            || self.max_entities == 0
            || self.max_trace_entries == 0
            || self.max_events == 0
            || self.deadline_ms == 0
            || self.max_events > 32
            || self.max_trace_entries > 4096
        {
            return Err(LifecycleError::Invalid("limits"));
        }
        if self.supported_domains
            != [
                Domain::World,
                Domain::Site,
                Domain::Gameplay,
                Domain::Presentation,
            ]
        {
            return Err(LifecycleError::Invalid("supported_domains"));
        }
        self.schemas.validate()
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GeneratorManifest {
    pub schema_version: String,
    pub rust_source_commit: String,
    pub generator_version: u32,
    pub content_manifest_hash: String,
    pub export_schemas: ExportSchemas,
    pub adapter_schemas: AdapterSchemas,
    pub target: String,
    pub dirty_development: bool,
}
impl GeneratorManifest {
    pub fn from_json(json: &str) -> Result<Self, LifecycleError> {
        let value: Self = serde_json::from_str(json)?;
        value.validate()?;
        Ok(value)
    }
    pub fn validate(&self) -> Result<(), LifecycleError> {
        if self.schema_version != PROCGEN_GENERATOR_MANIFEST_SCHEMA
            || self.target.is_empty()
            || self.generator_version != PROCGEN_GENERATOR_VERSION
            || self.rust_source_commit.len() != 40
            || !is_lower_hex(&self.rust_source_commit)
            || self.content_manifest_hash.len() != 64
            || !is_lower_hex(&self.content_manifest_hash)
            || self.export_schemas != ExportSchemas::platform_v5()
        {
            return Err(LifecycleError::Invalid("manifest"));
        }
        self.adapter_schemas.validate()
    }
}

#[derive(Debug, thiserror::Error)]
pub enum LifecycleError {
    #[error("lifecycle JSON parse failed: {0}")]
    Parse(#[from] serde_json::Error),
    #[error("lifecycle field {0} is invalid")]
    Invalid(&'static str),
    #[error("bundle contract invalid: {0}")]
    Bundle(ProcgenError),
    #[error("failure contract invalid: {0}")]
    Failure(ProcgenError),
}
fn is_lower_hex(value: &str) -> bool {
    value
        .bytes()
        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        && value == value.to_ascii_lowercase()
}
