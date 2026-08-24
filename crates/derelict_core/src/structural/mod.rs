//! Canonical structural plan: the authoritative IR for generated ships.
//!
//! `plan` — grid/edge identity primitives and the IR types.
//! `compile` — authored topology → StructuralPlan (one record per boundary).
//! `validate` — fail-closed validation (pre- and post-damage policies).

pub mod compile;
pub mod plan;
pub mod project;
pub mod validate;
