//! Prints the worldgen structural compilation of the differential fixture in
//! the same normalized format as The Synaptic Sea's
//! `worldgen_diff_probe.gd`, for line-by-line comparison of the port.

use derelict_core::role::Role;
use derelict_core::structural::compile::{compile, DefaultModulePicker};
use derelict_core::structural::plan::*;

fn main() {
    let topo = Topology {
        rooms: vec![
            RoomSpec {
                id: 1,
                role: Role::Airlock,
                deck: 0,
                cells: vec![
                    Cell::new(0, 0, 0),
                    Cell::new(0, 1, 0),
                    Cell::new(0, 0, 1),
                    Cell::new(0, 1, 1),
                ],
            },
            RoomSpec {
                id: 2,
                role: Role::Bridge,
                deck: 0,
                cells: vec![
                    Cell::new(0, 2, 0),
                    Cell::new(0, 3, 0),
                    Cell::new(0, 2, 1),
                    Cell::new(0, 3, 1),
                ],
            },
            RoomSpec {
                id: 3,
                role: Role::CrewQuarters,
                deck: 1,
                cells: vec![Cell::new(1, 0, 0), Cell::new(1, 1, 0)],
            },
        ],
        portals: vec![PortalIntent {
            from_room: 1,
            to_room: 2,
            from_cell: Cell::new(0, 1, 0),
            to_cell: Cell::new(0, 2, 0),
            state: EdgeKind::Door,
            exterior: false,
        }],
        verticals: vec![VerticalConnection {
            from_room: 1,
            to_room: 3,
            from_cell: Cell::new(0, 0, 0),
            to_cell: Cell::new(1, 0, 0),
        }],
    };
    let plan = compile(&topo, &DefaultModulePicker);
    let mut lines: Vec<String> = Vec::new();
    for e in &plan.errors {
        lines.push(format!("ERROR {e}"));
    }
    for (key, e) in &plan.edges {
        lines.push(format!(
            "EDGE {key} kind={} portal={}",
            e.kind.name(),
            e.portal
        ));
    }
    for f in &plan.floor_placements {
        lines.push(format!(
            "FLOOR {} pos={:.1},{:.1},{:.1} yaw={}",
            f.cell_key, f.position[0], f.position[1], f.position[2], f.yaw_degrees
        ));
    }
    for c in &plan.ceiling_placements {
        lines.push(format!("CEIL {}", c.cell_key));
    }
    lines.sort();
    for l in &lines {
        println!("{l}");
    }
    println!(
        "DIFF_PROBE_DONE edges={} floors={} ceilings={} errors={}",
        plan.edges.len(),
        plan.floor_placements.len(),
        plan.ceiling_placements.len(),
        plan.errors.len()
    );
}
