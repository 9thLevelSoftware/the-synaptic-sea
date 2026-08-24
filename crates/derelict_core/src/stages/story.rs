//! Stage 7: story/sim layer — what happened to this ship. The chosen cause
//! of loss becomes a damage profile of integer bias weights consumed by the
//! damage and loot stages, plus environmental-storytelling knobs.

use crate::archetype::ShipArchetype;
use crate::model::{CauseOfLoss, RoomType};
use crate::rng::weighted_choice;
use rand_pcg::Pcg64;

#[derive(Clone, Debug)]
pub struct DamageProfile {
    pub cause: CauseOfLoss,
    /// Breaches concentrate near these room types.
    pub breach_bias_rooms: Vec<RoomType>,
    /// Chance (bp) of scorch decals around each breach.
    pub scorch_bp: u32,
    /// Extra scorch zones around these rooms (reactor fires etc.).
    pub scorch_rooms: Vec<RoomType>,
    /// Crew body count range (scaled up as intactness drops).
    pub bodies: (u8, u8),
    pub body_rooms: Vec<RoomType>,
    /// Loot richness multiplier, bp (pirates strip ships; plague leaves all).
    pub loot_mult_bp: u16,
    /// Chance (bp) that each Armory container was emptied.
    pub weapon_empty_bp: u32,
    /// Extra chance (bp) that interior doors are locked/sealed.
    pub sealed_door_bp: u32,
}

pub fn choose_cause(rng: &mut Pcg64, arch: &ShipArchetype, over: Option<CauseOfLoss>) -> CauseOfLoss {
    if let Some(c) = over {
        return c;
    }
    let weights: Vec<u32> = arch.cause_weights.iter().map(|(_, w)| *w).collect();
    match weighted_choice(rng, &weights) {
        Some(i) => arch.cause_weights[i].0,
        None => CauseOfLoss::Unknown,
    }
}

pub fn profile_for(cause: CauseOfLoss) -> DamageProfile {
    use CauseOfLoss::*;
    use RoomType::*;
    match cause {
        ReactorBreach => DamageProfile {
            cause,
            breach_bias_rooms: vec![Reactor, Engineering],
            scorch_bp: 8500,
            scorch_rooms: vec![Reactor, Engineering],
            bodies: (1, 4),
            body_rooms: vec![Engineering, Reactor, Corridor],
            loot_mult_bp: 9000,
            weapon_empty_bp: 0,
            sealed_door_bp: 500,
        },
        Depressurization => DamageProfile {
            cause,
            breach_bias_rooms: vec![Cargo, CrewQuarters, Corridor],
            scorch_bp: 1500,
            scorch_rooms: vec![],
            bodies: (2, 6),
            body_rooms: vec![CrewQuarters, Corridor, Galley],
            loot_mult_bp: 10_000,
            weapon_empty_bp: 0,
            sealed_door_bp: 2500, // emergency bulkheads sealed
        },
        PirateBoarding => DamageProfile {
            cause,
            breach_bias_rooms: vec![Airlock, Bridge],
            scorch_bp: 4000,
            scorch_rooms: vec![],
            bodies: (3, 8),
            body_rooms: vec![Corridor, Bridge, Airlock, CrewQuarters],
            loot_mult_bp: 5500, // stripped
            weapon_empty_bp: 7500,
            sealed_door_bp: 0,
        },
        Plague => DamageProfile {
            cause,
            breach_bias_rooms: vec![],
            scorch_bp: 500,
            scorch_rooms: vec![],
            bodies: (4, 10),
            body_rooms: vec![CrewQuarters, Medbay, Galley],
            loot_mult_bp: 11_000, // untouched cargo
            weapon_empty_bp: 0,
            sealed_door_bp: 5500, // quarantine seals
        },
        DriveMisjump => DamageProfile {
            cause,
            breach_bias_rooms: vec![Engineering],
            scorch_bp: 6000,
            scorch_rooms: vec![Engineering],
            bodies: (0, 3),
            body_rooms: vec![Engineering, Bridge],
            loot_mult_bp: 10_000,
            weapon_empty_bp: 0,
            sealed_door_bp: 500,
        },
        Unknown => DamageProfile {
            cause,
            breach_bias_rooms: vec![],
            scorch_bp: 2000,
            scorch_rooms: vec![],
            bodies: (0, 4),
            body_rooms: vec![CrewQuarters, Corridor],
            loot_mult_bp: 9500,
            weapon_empty_bp: 0,
            sealed_door_bp: 1500,
        },
    }
}
