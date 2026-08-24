//! Phase 4 verification against The Synaptic Sea's REAL kit data. These
//! tests exercise socket-driven module choice with the actual contract
//! JSON; they skip gracefully when the game repo isn't present (CI).

use derelict_core::structural::compile::{compile, ModulePicker, VertexKind};
use derelict_core::structural::sockets::{KitCatalog, SocketCatalog, SocketModulePicker};
use std::path::Path;

const CONTRACTS: &str =
    r"D:\the-synaptic-sea\data\placement\contracts\structural\ship_structural_v0";
const KIT_V0: &str = r"D:\the-synaptic-sea\data\kits\ship_structural_v0.json";
const KIT_ITHAPPY: &str = r"D:\the-synaptic-sea\data\kits\ithappy_scifi_v0.json";

fn catalog() -> Option<SocketCatalog> {
    let dir = Path::new(CONTRACTS);
    if !dir.exists() {
        eprintln!("SKIP: game repo not present");
        return None;
    }
    Some(SocketCatalog::load_dir(dir).expect("contracts load"))
}

#[test]
fn contracts_load_and_choose_expected_modules() {
    let Some(cat) = catalog() else { return };
    assert!(cat.modules.len() >= 10, "expected the 15-module kit, got {}", cat.modules.len());
    let picker = SocketModulePicker { catalog: cat };
    assert_eq!(picker.floor(false), "floor_1x1");
    assert_eq!(picker.floor(true), "corridor_floor_1x1");
    assert_eq!(picker.wall(), "wall_straight_1x1");
    assert_eq!(picker.ceiling(), "ceiling_cap_1x1");
    assert_eq!(
        picker.portal(derelict_core::structural::plan::EdgeKind::Door),
        "doorway_frame_open_1x1"
    );
    assert_eq!(
        picker.portal(derelict_core::structural::plan::EdgeKind::Locked),
        "doorway_frame_blocked_1x1"
    );
    // Vertex modules exist in the kit.
    assert!(picker.vertex(VertexKind::InnerCorner).is_some());
}

#[test]
fn socket_picker_produces_valid_plan() {
    use derelict_core::role::Role;
    use derelict_core::structural::plan::*;
    use derelict_core::structural::validate::{validate, ValidationPolicy};
    let Some(cat) = catalog() else { return };
    let picker = SocketModulePicker { catalog: cat };
    let topo = Topology {
        rooms: vec![
            RoomSpec {
                id: 1,
                role: Role::Airlock,
                deck: 0,
                cells: vec![Cell::new(0, 0, 0), Cell::new(0, 1, 0)],
            },
            RoomSpec {
                id: 2,
                role: Role::Corridor,
                deck: 0,
                cells: vec![Cell::new(0, 2, 0), Cell::new(0, 3, 0)],
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
        verticals: vec![],
    };
    let plan = compile(&topo, &picker);
    assert!(plan.errors.is_empty(), "{:?}", plan.errors);
    validate(&plan, &topo, &ValidationPolicy::pre_damage(vec![1, 2])).expect("valid");
    // Corridor floor module chosen by socket kinds, not hardcoding.
    assert!(plan
        .floor_placements
        .iter()
        .any(|f| f.module_id == "corridor_floor_1x1"));
}

#[test]
fn kit_catalogs_map_modules_to_scenes() {
    for path in [KIT_V0, KIT_ITHAPPY] {
        let p = Path::new(path);
        if !p.exists() {
            eprintln!("SKIP: {path} not present");
            continue;
        }
        let kit = KitCatalog::load(p).expect("kit load");
        for module in ["floor_1x1", "wall_straight_1x1", "doorway_frame_open_1x1"] {
            let scene = kit.scene_of(module);
            assert!(
                scene.map(|s| s.ends_with(".tscn")).unwrap_or(false),
                "{}: no wrapper scene for {module}",
                kit.kit_id
            );
        }
    }
}
