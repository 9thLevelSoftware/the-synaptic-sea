//! `derelict_core` — deterministic procedural generation of derelict
//! spacecraft for isometric tile-based games.
//!
//! Pure Rust, no engine dependencies. The public contract:
//! `generate_ship(seed, params, data)` is a pure function — identical inputs
//! and `GENERATOR_VERSION` produce byte-identical ships on any platform.

pub mod archetype;
pub mod model;
pub mod manifest;
pub mod pipeline;
pub mod rng;
pub mod role;
pub mod stages;
pub mod structural;
pub mod topology;
pub mod procgen;

pub use archetype::GenData;
pub use model::{
    apply_diff, CauseOfLoss, Deck, DeckLayer, EntityKind, EntitySpec, FloorTile, GenParams,
    GridPos, ItemStack, RoomGraph, RoomNode, Ship, ShipMutationDiff, WallEdge, GENERATOR_VERSION,
};
pub use pipeline::{generate_ship, generate_ship_timed, GenError, GenReport};
pub use role::Role;
pub use stages::hull::derive_site_seed;
