//! Determinism replay tests: identical inputs must produce identical ships,
//! down to the serialized byte level.

use derelict_core::{GenData, GenParams};

#[test]
fn generate_twice_identical() {
    let data = GenData::default_bundle().unwrap();
    for arch in ["shuttle", "corvette", "freighter", "frigate"] {
        for seed in [0u64, 1, 42, 0xDEAD_BEEF] {
            let params = GenParams::new(arch);
            let a = derelict_core::generate_ship(seed, &params, &data).unwrap();
            let b = derelict_core::generate_ship(seed, &params, &data).unwrap();
            assert_eq!(a, b, "{arch} seed {seed}: ships differ between runs");
            let ba = bincode::serde::encode_to_vec(&a, bincode::config::standard()).unwrap();
            let bb = bincode::serde::encode_to_vec(&b, bincode::config::standard()).unwrap();
            assert_eq!(ba, bb, "{arch} seed {seed}: serialized bytes differ");
        }
    }
}

#[test]
fn different_seeds_differ() {
    let data = GenData::default_bundle().unwrap();
    let params = GenParams::new("corvette");
    let a = derelict_core::generate_ship(1, &params, &data).unwrap();
    let b = derelict_core::generate_ship(2, &params, &data).unwrap();
    assert_ne!(a, b);
}

#[test]
fn intactness_override_respected() {
    let data = GenData::default_bundle().unwrap();
    let mut params = GenParams::new("freighter");
    params.intactness_override = Some(10_000);
    let ship = derelict_core::generate_ship(5, &params, &data).unwrap();
    assert_eq!(ship.intactness, 10_000);
    assert!(!ship.fractured);
    assert!(
        ship.damage_events.is_empty(),
        "pristine ship must have no damage events"
    );
}
