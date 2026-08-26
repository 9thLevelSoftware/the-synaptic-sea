//! Closed, bounded, run-local player snapshot used by Gate 3 gameplay domains.

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

pub const PLAYER_MODEL_SCHEMA_V2: &str = "player-model-2";
pub const PLAYER_SIGNAL_BASELINE_BP: u16 = 5_000;
pub const PLAYER_SIGNAL_MAX_BP: u16 = 10_000;

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, JsonSchema,
)]
#[serde(rename_all = "snake_case")]
pub enum PlayerSignalKind {
    CombatMastery,
    DamagePressure,
    ResourcePressure,
    ObjectivePace,
}

impl PlayerSignalKind {
    pub const ALL: [Self; 4] = [
        Self::CombatMastery,
        Self::DamagePressure,
        Self::ResourcePressure,
        Self::ObjectivePace,
    ];
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PlayerSignal {
    pub kind: PlayerSignalKind,
    pub value_bp: u16,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PlayerModelV2 {
    pub schema_version: String,
    pub signals: Vec<PlayerSignal>,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum PlayerModelError {
    #[error("player model JSON parse failed: {0}")]
    Json(String),
    #[error("invalid player model field: {0}")]
    Invalid(&'static str),
}

impl PlayerModelV2 {
    pub fn from_json(json: &str) -> Result<Self, PlayerModelError> {
        let model: Self = serde_json::from_str(json)
            .map_err(|error| PlayerModelError::Json(error.to_string()))?;
        model.validate()?;
        Ok(model)
    }

    pub fn validate(&self) -> Result<(), PlayerModelError> {
        if self.schema_version != PLAYER_MODEL_SCHEMA_V2 {
            return Err(PlayerModelError::Invalid("schema_version"));
        }
        if self.signals.len() > PlayerSignalKind::ALL.len() {
            return Err(PlayerModelError::Invalid("signal_count"));
        }
        if self
            .signals
            .iter()
            .any(|signal| signal.value_bp > PLAYER_SIGNAL_MAX_BP)
        {
            return Err(PlayerModelError::Invalid("signal_value"));
        }
        if self
            .signals
            .windows(2)
            .any(|pair| pair[0].kind >= pair[1].kind)
        {
            return Err(PlayerModelError::Invalid("signal_order"));
        }
        Ok(())
    }

    pub fn signal_bp(&self, kind: PlayerSignalKind) -> u16 {
        self.signals
            .iter()
            .find(|signal| signal.kind == kind)
            .map_or(PLAYER_SIGNAL_BASELINE_BP, |signal| signal.value_bp)
    }

    pub fn normalized_values(&self) -> [u16; 4] {
        PlayerSignalKind::ALL.map(|kind| self.signal_bp(kind))
    }
}
