//! One deliberately-broken plan per validator check family. Each test
//! asserts the SPECIFIC issue code fires — traceability, not just "some
//! error somewhere". A green baseline test proves the fixture itself is
//! valid before any breakage.

use derelict_core::role::Role;
use derelict_core::structural::compile::{compile, DefaultModulePicker};
use derelict_core::structural::plan::*;
use derelict_core::structural::validate::{
    validate, IssueCode, ValidationPolicy,
};

/// Two-deck fixture: airlock (4 cells) + bridge (4 cells) joined by a door,
/// an exterior airlock door, an upper deck room over the airlock joined by
/// a vertical connection.
fn fixture() -> Topology {
    let airlock_cells = vec![
        Cell::new(0, 0, 0),
        Cell::new(0, 1, 0),
        Cell::new(0, 0, 1),
        Cell::new(0, 1, 1),
    ];
    let bridge_cells = vec![
        Cell::new(0, 2, 0),
        Cell::new(0, 3, 0),
        Cell::new(0, 2, 1),
        Cell::new(0, 3, 1),
    ];
    let upper_cells = vec![Cell::new(1, 0, 0), Cell::new(1, 1, 0)];
    Topology {
        rooms: vec![
            RoomSpec { id: 1, role: Role::Airlock, deck: 0, cells: airlock_cells },
            RoomSpec { id: 2, role: Role::Bridge, deck: 0, cells: bridge_cells },
            RoomSpec { id: 3, role: Role::CrewQuarters, deck: 1, cells: upper_cells },
        ],
        portals: vec![
            PortalIntent {
                from_room: 1,
                to_room: 2,
                from_cell: Cell::new(0, 1, 0),
                to_cell: Cell::new(0, 2, 0),
                state: EdgeKind::Door,
                exterior: false,
            },
            PortalIntent {
                from_room: 1,
                to_room: NO_ROOM,
                from_cell: Cell::new(0, 0, 0),
                to_cell: Cell::new(0, -1, 0),
                state: EdgeKind::Door,
                exterior: true,
            },
        ],
        verticals: vec![VerticalConnection {
            from_room: 1,
            to_room: 3,
            from_cell: Cell::new(0, 0, 0),
            to_cell: Cell::new(1, 0, 0),
        }],
    }
}

fn compiled() -> (StructuralPlan, Topology) {
    let topo = fixture();
    let plan = compile(&topo, &DefaultModulePicker);
    (plan, topo)
}

fn policy() -> ValidationPolicy {
    ValidationPolicy::pre_damage(vec![1, 2])
}

fn assert_code(plan: &StructuralPlan, topo: &Topology, code: IssueCode) {
    let issues = validate(plan, topo, &policy()).expect_err("expected validation failure");
    assert!(
        issues.iter().any(|i| i.code == code),
        "expected {code:?}, got: {issues:?}"
    );
}

#[test]
fn baseline_fixture_is_valid() {
    let (plan, topo) = compiled();
    assert!(plan.errors.is_empty(), "compiler errors: {:?}", plan.errors);
    let stats = validate(&plan, &topo, &policy()).expect("fixture must validate");
    assert_eq!(stats.occupied_cells, 10);
    assert_eq!(stats.floor_placements, 10);
    // Two vertical-opening cells have no ceiling.
    assert_eq!(stats.ceiling_placements, 8);
    assert!(stats.edge_placements > 0);
    assert!(stats.socket_bindings > 0);
}

#[test]
fn red_01_compiler_errors_fail_validation() {
    let mut topo = fixture();
    // Overlap: bridge also claims an airlock cell.
    topo.rooms[1].cells.push(Cell::new(0, 0, 0));
    let plan = compile(&topo, &DefaultModulePicker);
    assert!(!plan.errors.is_empty());
    assert_code(&plan, &topo, IssueCode::CompilerError);
}

#[test]
fn red_02_occupancy_key_roundtrip() {
    let (mut plan, topo) = compiled();
    let (key, mut rec) = plan.occupancy.iter().next().map(|(k, v)| (k.clone(), v.clone())).unwrap();
    rec.cell.x += 5; // key no longer reconstructs
    plan.occupancy.insert(key, rec);
    assert_code(&plan, &topo, IssueCode::OccupancyMalformed);
}

#[test]
fn red_03_floor_bijection_missing_floor() {
    let (mut plan, topo) = compiled();
    plan.floor_placements.pop();
    assert_code(&plan, &topo, IssueCode::FloorBijectionBroken);
}

#[test]
fn red_04_floor_duplicate() {
    let (mut plan, topo) = compiled();
    let dup = plan.floor_placements[0].clone();
    plan.floor_placements.push(dup);
    assert_code(&plan, &topo, IssueCode::FloorDuplicate);
}

#[test]
fn red_05_floor_bad_pose() {
    let (mut plan, topo) = compiled();
    plan.floor_placements[0].position[0] += 1.0;
    assert_code(&plan, &topo, IssueCode::FloorBadPose);
}

#[test]
fn red_06_floor_bad_module() {
    let (mut plan, topo) = compiled();
    let key = plan.floor_placements[0].cell_key.clone();
    plan.floor_placements[0].module_id = "wall_straight_1x1".into();
    plan.occupancy.get_mut(&key).unwrap().module_id = "wall_straight_1x1".into();
    assert_code(&plan, &topo, IssueCode::FloorBadModule);
}

#[test]
fn red_07_missing_ceiling() {
    let (mut plan, topo) = compiled();
    plan.ceiling_placements.pop();
    assert_code(&plan, &topo, IssueCode::CeilingInvalid);
}

#[test]
fn red_08_ceiling_on_vertical_opening() {
    let (mut plan, topo) = compiled();
    let opening = Cell::new(0, 0, 0); // vertical connection endpoint
    plan.ceiling_placements.push(FloorPlacement {
        id: format!("ceiling:{}", opening.key()),
        cell: opening,
        cell_key: opening.key(),
        room_id: 1,
        module_id: "ceiling_cap_1x1".into(),
        position: opening.world_pos(),
        yaw_degrees: 0,
        variant: DamageVariant::Intact,
    });
    assert_code(&plan, &topo, IssueCode::CeilingOnVerticalOpening);
}

#[test]
fn red_09_socket_bindings_missing() {
    let (mut plan, topo) = compiled();
    plan.socket_bindings.clear();
    assert_code(&plan, &topo, IssueCode::SocketBindingsMissing);
}

#[test]
fn red_10_floor_only_plan() {
    let (mut plan, topo) = compiled();
    plan.placements.clear();
    for e in plan.edges.values_mut() {
        e.wrapper_required = false; // suppress RequiredEdgeUnplaced noise
    }
    assert_code(&plan, &topo, IssueCode::FloorOnlyPlan);
}

#[test]
fn red_11_open_edge_placed() {
    let (mut plan, topo) = compiled();
    let open = plan
        .edges
        .values()
        .find(|e| e.kind == EdgeKind::Open)
        .expect("fixture has interior open edges")
        .clone();
    plan.placements.push(open);
    assert_code(&plan, &topo, IssueCode::OpenEdgePlaced);
}

#[test]
fn red_12_edge_kind_mismatch() {
    let (mut plan, topo) = compiled();
    plan.placements[0].kind = EdgeKind::Hatch;
    assert_code(&plan, &topo, IssueCode::EdgeKindMismatch);
}

#[test]
fn red_13_edge_bad_pose() {
    let (mut plan, topo) = compiled();
    plan.placements[0].yaw_degrees = plan.placements[0].yaw_degrees.wrapping_add(90);
    assert_code(&plan, &topo, IssueCode::EdgeBadPose);
}

#[test]
fn red_14_required_edge_unplaced() {
    let (mut plan, topo) = compiled();
    plan.placements.pop();
    assert_code(&plan, &topo, IssueCode::RequiredEdgeUnplaced);
}

#[test]
fn red_15_portal_blocked_by_solid() {
    let (mut plan, topo) = compiled();
    // Flip the interior door edge to SOLID in both edge map and placement.
    let door_key = plan
        .edges
        .values()
        .find(|e| e.portal && !e.exterior)
        .unwrap()
        .edge_key
        .clone();
    {
        let e = plan.edges.get_mut(&door_key).unwrap();
        e.kind = EdgeKind::Solid;
        e.module_id = "wall_straight_1x1".into();
    }
    if let Some(p) = plan.placements.iter_mut().find(|p| p.edge_key == door_key) {
        p.kind = EdgeKind::Solid;
        p.module_id = "wall_straight_1x1".into();
    }
    assert_code(&plan, &topo, IssueCode::PortalBlockedBySolid);
}

#[test]
fn red_16_portal_has_no_edge() {
    let (mut plan, topo) = compiled();
    let door_key = plan
        .edges
        .values()
        .find(|e| e.portal && !e.exterior)
        .unwrap()
        .edge_key
        .clone();
    plan.edges.remove(&door_key);
    plan.placements.retain(|p| p.edge_key != door_key);
    assert_code(&plan, &topo, IssueCode::PortalHasNoEdge);
}

#[test]
fn red_17_reachability_broken() {
    let mut topo = fixture();
    // Remove the door between the rooms entirely: compile makes the shared
    // boundary SOLID and the two rooms disconnect on deck 0.
    topo.portals.retain(|p| p.exterior);
    let plan = compile(&topo, &DefaultModulePicker);
    assert!(plan.errors.is_empty());
    let issues = validate(&plan, &topo, &policy()).expect_err("must fail");
    assert!(
        issues
            .iter()
            .any(|i| matches!(i.code, IssueCode::ReachabilityBroken | IssueCode::CriticalPathBroken)),
        "got: {issues:?}"
    );
}

#[test]
fn post_damage_fragments_validate_per_fragment() {
    use std::collections::BTreeMap;
    // Same disconnected topology as red_17, but declared as two fragments
    // post-damage: each side is internally connected, so it must PASS with
    // fragment membership + allows_fragment_split, and FAIL without.
    let mut topo = fixture();
    topo.portals.retain(|p| p.exterior);
    let plan = compile(&topo, &DefaultModulePicker);

    let mut frag: BTreeMap<RoomId, u8> = BTreeMap::new();
    frag.insert(1, 0);
    frag.insert(3, 0); // upper room connects to airlock via the shaft
    frag.insert(2, 1);
    let ok_policy = ValidationPolicy::post_damage(vec![1, 2], Some(frag), true);
    validate(&plan, &topo, &ok_policy).expect("fragment-aware validation must pass");

    let strict = ValidationPolicy::post_damage(vec![1, 2], None, false);
    let issues = validate(&plan, &topo, &strict).expect_err("must fail without fragments");
    assert!(issues.iter().any(|i| matches!(
        i.code,
        IssueCode::ReachabilityBroken | IssueCode::CriticalPathBroken
    )));
}
