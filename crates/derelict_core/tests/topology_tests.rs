//! Phase 2 verification: template loading + cross-validation, and zone-tree
//! placement into hull masks — every template must place, connect, compile,
//! and validate across a spread of seeds.

use derelict_core::rng;
use derelict_core::role::Role;
use derelict_core::stages::hull::Mask;
use derelict_core::structural::compile::{compile, DefaultModulePicker};
use derelict_core::structural::plan::NO_ROOM;
use derelict_core::structural::validate::{validate, ValidationPolicy};
use derelict_core::topology::{place_topology, RoleParams, TemplateSet};
use std::collections::BTreeSet;

fn rect_masks(width: u16, height: u16, decks: usize) -> Vec<Mask> {
    let mut masks = Vec::new();
    for _ in 0..decks {
        let mut m = Mask::new(width, height);
        for y in 1..height as i32 - 1 {
            for x in 1..width as i32 - 1 {
                m.set(x, y, true);
            }
        }
        masks.push(m);
    }
    masks
}

fn params() -> RoleParams {
    RoleParams {
        weights: Default::default(),
        guaranteed: vec![],
        max_duplicates: 3,
    }
}

#[test]
fn all_templates_load_and_validate() {
    let set = TemplateSet::default_bundle().expect("templates parse and validate");
    assert_eq!(
        set.templates.len(),
        13,
        "all 13 Synaptic Sea templates ported"
    );
}

#[test]
fn template_compatibility_filters_guarantees() {
    let set = TemplateSet::default_bundle().unwrap();
    // Dock exists only in derelict_a, derelict_b, hangar_wing — the exact
    // bug class from The Synaptic Sea (silently skipped dock) becomes a
    // selection-time filter here.
    let dock_capable = set.compatible(&[Role::Dock], 1);
    let ids: BTreeSet<&str> = dock_capable.iter().map(|t| t.id.as_str()).collect();
    assert_eq!(
        ids,
        BTreeSet::from(["derelict_a", "derelict_b", "hangar_wing"]),
        "dock guarantee must filter to dock-capable templates"
    );
    // Multi-deck templates are excluded when the hull has one deck.
    assert!(set
        .compatible(&[], 1)
        .iter()
        .all(|t| t.max_zone_deck() == 0));
    assert!(set.compatible(&[], 3).iter().any(|t| t.id == "stacked_v2"));
}

#[test]
fn every_template_places_and_validates() {
    let set = TemplateSet::default_bundle().unwrap();
    let p = params();
    let mut failures: Vec<String> = Vec::new();
    for template in set.templates.values() {
        let decks = (template.max_zone_deck() + 1) as usize;
        for seed in 0..8u64 {
            let masks = rect_masks(24, 14, decks);
            let mut r = rng::stream(seed, "topo_test", 0);
            let placed = match place_topology(&mut r, template, &masks, &p) {
                Ok(pt) => pt,
                Err(e) => {
                    failures.push(format!("{} seed {seed}: {e}", template.id));
                    continue;
                }
            };
            // Rooms don't overlap (compile would error, but assert here too).
            let mut seen = BTreeSet::new();
            for room in &placed.topology.rooms {
                for c in &room.cells {
                    assert!(
                        seen.insert(c.key()),
                        "{} seed {seed}: overlap at {}",
                        template.id,
                        c.key()
                    );
                }
            }
            // Critical path runs entry -> goal.
            assert_eq!(placed.critical_path.first(), Some(&placed.entry_room));
            assert_eq!(placed.critical_path.last(), Some(&placed.goal_room));
            // Exactly one exterior door.
            let exterior = placed
                .topology
                .portals
                .iter()
                .filter(|p| p.exterior)
                .count();
            assert_eq!(exterior, 1, "{} seed {seed}", template.id);
            // Full structural compile + fail-closed validation.
            let plan = compile(&placed.topology, &DefaultModulePicker);
            assert!(
                plan.errors.is_empty(),
                "{} seed {seed}: {:?}",
                template.id,
                plan.errors
            );
            let policy = ValidationPolicy::pre_damage(placed.critical_path.clone());
            if let Err(issues) = validate(&plan, &placed.topology, &policy) {
                failures.push(format!(
                    "{} seed {seed}: validation {:?}",
                    template.id,
                    issues.iter().take(3).collect::<Vec<_>>()
                ));
            }
        }
    }
    assert!(
        failures.is_empty(),
        "placement failures:\n{}",
        failures.join("\n")
    );
}

#[test]
fn guaranteed_role_is_forced_into_plan() {
    let set = TemplateSet::default_bundle().unwrap();
    let template = &set.templates["derelict_a"];
    let mut p = params();
    p.guaranteed = vec![Role::Dock];
    for seed in 0..20u64 {
        let masks = rect_masks(24, 14, 1);
        let mut r = rng::stream(seed, "topo_guarantee", 0);
        let placed = place_topology(&mut r, template, &masks, &p).expect("placement");
        assert!(
            placed
                .topology
                .rooms
                .iter()
                .any(|room| room.role == Role::Dock),
            "seed {seed}: dock guarantee not enforced"
        );
    }
}

#[test]
fn hazard_comfort_never_adjacent() {
    let set = TemplateSet::default_bundle().unwrap();
    let p = params();
    for template in set.templates.values() {
        let decks = (template.max_zone_deck() + 1) as usize;
        for seed in 0..8u64 {
            let masks = rect_masks(24, 14, decks);
            let mut r = rng::stream(seed, "topo_hazard", 0);
            let Ok(placed) = place_topology(&mut r, template, &masks, &p) else {
                continue;
            };
            // Re-derive adjacency from cells and assert the invariant.
            let mut owner = std::collections::BTreeMap::new();
            for room in &placed.topology.rooms {
                for c in &room.cells {
                    owner.insert((c.deck, c.x, c.y), room.id);
                }
            }
            for room in &placed.topology.rooms {
                if !room.role.is_hazardous() {
                    continue;
                }
                for c in &room.cells {
                    for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                        let n = owner
                            .get(&(c.deck, c.x + dx, c.y + dy))
                            .copied()
                            .unwrap_or(NO_ROOM);
                        if n != NO_ROOM && n != room.id {
                            let other = placed.topology.room(n).unwrap();
                            assert!(
                                !other.role.is_crew_comfort(),
                                "{} seed {seed}: {:?} adjacent to {:?}",
                                template.id,
                                room.role,
                                other.role
                            );
                        }
                    }
                }
            }
        }
    }
}
