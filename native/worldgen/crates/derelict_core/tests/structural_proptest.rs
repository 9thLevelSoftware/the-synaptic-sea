//! Property-based invariants for the structural IR: whatever topology we
//! throw at the compiler, the canonical-boundary and bijection contracts
//! hold and the validator agrees.

use derelict_core::role::Role;
use derelict_core::structural::compile::{compile, DefaultModulePicker};
use derelict_core::structural::plan::*;
use derelict_core::structural::validate::{validate, ValidationPolicy};
use proptest::prelude::*;

proptest! {
    /// Both sides of any boundary derive the identical edge key.
    #[test]
    fn edge_key_is_symmetric(deck in 0u8..4, x in -50i32..50, y in -50i32..50, d in 0usize..4) {
        let dir = Dir::ALL[d];
        let cell = Cell::new(deck, x, y);
        let neighbor = cell.neighbor(dir);
        prop_assert_eq!(edge_key(cell, dir), edge_key(neighbor, dir.opposite()));
    }

    /// Distinct geometric boundaries never collide on the same key.
    #[test]
    fn edge_keys_are_unique_per_boundary(x in -20i32..20, y in -20i32..20) {
        let cell = Cell::new(0, x, y);
        let mut keys: Vec<String> = Vec::new();
        for dir in Dir::ALL {
            keys.push(edge_key(cell, dir));
        }
        keys.sort();
        keys.dedup();
        prop_assert_eq!(keys.len(), 4, "the four edges of one cell must have distinct keys");
    }
}

/// Strategy: a strip of 1..6 rectangular rooms laid side by side along +x,
/// each with a door to the previous room — always a valid connected ship.
fn room_strip() -> impl Strategy<Value = Topology> {
    proptest::collection::vec((1u8..4, 1u8..4), 1..6).prop_map(|sizes| {
        let mut rooms = Vec::new();
        let mut portals = Vec::new();
        let mut x0 = 0i32;
        for (i, (w, h)) in sizes.iter().enumerate() {
            let id = (i + 1) as RoomId;
            let mut cells = Vec::new();
            for dx in 0..*w as i32 {
                for dy in 0..*h as i32 {
                    cells.push(Cell::new(0, x0 + dx, dy));
                }
            }
            rooms.push(RoomSpec {
                id,
                role: if i == 0 {
                    Role::Airlock
                } else {
                    Role::Compartment
                },
                deck: 0,
                cells,
            });
            if i > 0 {
                // Door on the shared boundary at y = 0 (always exists since
                // every room includes row 0).
                portals.push(PortalIntent {
                    from_room: id - 1,
                    to_room: id,
                    from_cell: Cell::new(0, x0 - 1, 0),
                    to_cell: Cell::new(0, x0, 0),
                    state: EdgeKind::Door,
                    exterior: false,
                });
            }
            x0 += *w as i32;
        }
        Topology {
            rooms,
            portals,
            verticals: Vec::new(),
        }
    })
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]
    #[test]
    fn compiled_strips_always_validate(topo in room_strip()) {
        let plan = compile(&topo, &DefaultModulePicker);
        prop_assert!(plan.errors.is_empty(), "compiler errors: {:?}", plan.errors);

        // Floor bijection with occupancy.
        prop_assert_eq!(plan.floor_placements.len(), plan.occupancy.len());

        // OPEN edges are never materialized.
        prop_assert!(plan.placements.iter().all(|p| p.kind != EdgeKind::Open));

        // No duplicate edge keys among placements.
        let mut keys: Vec<&str> = plan.placements.iter().map(|p| p.edge_key.as_str()).collect();
        let n = keys.len();
        keys.sort();
        keys.dedup();
        prop_assert_eq!(keys.len(), n);

        // Every declared portal produced exactly one portal edge.
        let portal_edges = plan.edges.values().filter(|e| e.portal).count();
        prop_assert_eq!(portal_edges, topo.portals.len());

        // Full validation passes with the room chain as critical path.
        let path: Vec<RoomId> = topo.rooms.iter().map(|r| r.id).collect();
        let policy = ValidationPolicy::pre_damage(path);
        let verdict = validate(&plan, &topo, &policy);
        prop_assert!(verdict.is_ok(), "validation failed: {:?}", verdict.err());
    }
}
