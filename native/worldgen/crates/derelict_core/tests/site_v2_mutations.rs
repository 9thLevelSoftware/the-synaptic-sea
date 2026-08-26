use derelict_core::site::{generate_site, validate_site_for_request, GateKind};
use derelict_core::structural::plan::Cell;
use derelict_core::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use derelict_core::{generate_ship, GenData, GenParams};

fn request(seed: u64) -> WorldGenerationRequest {
    WorldGenerationRequest {
        world_seed: seed,
        platform_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: "a".repeat(64),
        site_id: "site:test".into(),
        x: 4,
        y: -3,
        archetype_id: "shuttle".into(),
    }
}

fn fixture_for(request: &WorldGenerationRequest) -> derelict_core::site::SiteIR {
    let key = WorldKey {
        world_seed: request.world_seed,
        platform_version: request.platform_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        site_id: request.site_id.clone(),
        x: request.x,
        y: request.y,
        domain: "site".into(),
        channel: "site.structural".into(),
        sub_index: 0,
    };
    let ship = generate_ship(
        key.seed().unwrap(),
        &GenParams::new(&request.archetype_id),
        &GenData::default_bundle().unwrap(),
    )
    .unwrap();
    generate_site(ship, request).unwrap().site
}

fn fixture() -> (WorldGenerationRequest, derelict_core::site::SiteIR) {
    let request = request(17);
    let site = fixture_for(&request);
    validate_site_for_request(&site, &request).unwrap();
    (request, site)
}

fn gated_fixture(kind: GateKind) -> (WorldGenerationRequest, derelict_core::site::SiteIR) {
    for seed in 0..192 {
        let request = request(seed);
        let site = fixture_for(&request);
        if site
            .mission_graph
            .gates
            .iter()
            .any(|gate| gate.kind == kind)
        {
            validate_site_for_request(&site, &request).unwrap();
            return (request, site);
        }
    }
    panic!("no {kind:?} fixture in bounded seed range");
}

fn rejects(request: &WorldGenerationRequest, site: derelict_core::site::SiteIR) {
    assert!(validate_site_for_request(&site, request).is_err());
}

#[test]
fn rejects_schema_substitution() {
    let (request, mut site) = fixture();
    site.schema_version = "site-ir-1".into();
    rejects(&request, site);
}

#[test]
fn rejects_duplicate_node_id() {
    let (request, mut site) = fixture();
    site.mission_graph.nodes[1].id = site.mission_graph.nodes[0].id.clone();
    rejects(&request, site);
}

#[test]
fn rejects_missing_node_id() {
    let (request, mut site) = fixture();
    site.mission_graph.nodes[1].id.clear();
    rejects(&request, site);
}

#[test]
fn rejects_mission_cycle() {
    let (request, mut site) = fixture();
    let start = site.mission_graph.start_node.clone();
    let extraction = site.mission_graph.extraction_node.clone();
    site.mission_graph
        .edges
        .push(derelict_core::site::MissionEdge {
            from: extraction,
            to: start,
        });
    rejects(&request, site);
}

#[test]
fn rejects_mission_checkpoint_order() {
    let (request, mut site) = fixture();
    site.mission_graph.extraction_node = site.mission_graph.required_objectives[0].clone();
    rejects(&request, site);
}

#[test]
fn rejects_broken_gate_prerequisite_id() {
    let (request, mut site) = gated_fixture(GateKind::KeyLock);
    site.mission_graph.gates[0].prerequisite_node = "missing-node".into();
    rejects(&request, site);
}

#[test]
fn rejects_broken_key_id() {
    let (request, mut site) = gated_fixture(GateKind::KeyLock);
    site.mission_graph.gates[0].key_id = Some("missing-key".into());
    rejects(&request, site);
}

#[test]
fn rejects_broken_repair_id() {
    let (request, mut site) = gated_fixture(GateKind::Repair);
    site.mission_graph.gates[0].repair_id = Some("missing-repair".into());
    rejects(&request, site);
}

#[test]
fn rejects_dangling_gate_navigation_ref() {
    let (request, mut site) = fixture();
    site.navigation.edges[0].gate_id = Some("missing-gate".into());
    rejects(&request, site);
}

#[test]
fn rejects_wrong_gate_navigation_edge() {
    let (request, mut site) = gated_fixture(GateKind::KeyLock);
    site.mission_graph.gates[0].navigation_edge = "missing-edge".into();
    rejects(&request, site);
}

#[test]
fn rejects_navigation_passability_mutation() {
    let (request, mut site) = fixture();
    site.navigation.edges[0].passable = !site.navigation.edges[0].passable;
    rejects(&request, site);
}

#[test]
fn rejects_navigation_cost_mutation() {
    let (request, mut site) = fixture();
    site.navigation.edges[0].cost += 1;
    rejects(&request, site);
}

#[test]
fn rejects_navigation_clearance_mutation() {
    let (request, mut site) = fixture();
    site.navigation.edges[0].clearance += 1;
    rejects(&request, site);
}

#[test]
fn rejects_navigation_cell_mutation() {
    let (request, mut site) = fixture();
    site.navigation.edges[0].from_cell = Cell::new(99, 999, 999);
    rejects(&request, site);
}

#[test]
fn rejects_prop_overlap() {
    let (request, mut site) = fixture();
    site.functional_props[1].anchor = site.functional_props[0].anchor;
    rejects(&request, site);
}

#[test]
fn rejects_prop_nonadjacency() {
    let (request, mut site) = fixture();
    site.functional_props[0].approach = site.functional_props[0].anchor;
    rejects(&request, site);
}

#[test]
fn rejects_prop_mission_binding() {
    let (request, mut site) = fixture();
    site.functional_props[0].mission_node_id = "missing-node".into();
    rejects(&request, site);
}

#[test]
fn rejects_extraction_cardinality() {
    let (request, mut site) = fixture();
    let index = site
        .functional_props
        .iter()
        .position(|prop| prop.kind == derelict_core::site::PropKind::ExtractionConsole)
        .unwrap();
    site.functional_props.remove(index);
    rejects(&request, site);
}

#[test]
fn rejects_extraction_portal_ref() {
    let (request, mut site) = fixture();
    let prop = site
        .functional_props
        .iter_mut()
        .find(|prop| prop.kind == derelict_core::site::PropKind::ExtractionConsole)
        .unwrap();
    prop.extraction_portal_ref = Some("wrong-portal".into());
    rejects(&request, site);
}

#[test]
fn rejects_spatial_cover_tampering() {
    let (request, mut site) = fixture();
    site.spatial_annotations.rooms[0]
        .cover_cells
        .push(Cell::new(99, 999, 999));
    rejects(&request, site);
}

#[test]
fn rejects_spatial_los_tampering() {
    let (request, mut site) = fixture();
    site.spatial_annotations.rooms[0]
        .los_pairs
        .push(derelict_core::site::LosPair {
            a: Cell::new(99, 999, 999),
            b: Cell::new(99, 998, 999),
        });
    rejects(&request, site);
}

#[test]
fn rejects_request_seed_mismatch() {
    let (_, site) = fixture();
    let request = request(18);
    rejects(&request, site);
}

#[test]
fn rejects_request_coordinate_mismatch() {
    let (mut request, site) = fixture();
    request.x += 1;
    rejects(&request, site);
}

#[test]
fn rejects_request_manifest_mismatch() {
    let (mut request, site) = fixture();
    request.content_manifest_hash = "b".repeat(64);
    rejects(&request, site);
}
