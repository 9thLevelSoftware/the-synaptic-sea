use derelict_core::site::{
    site_from_json, site_json, MissionGraph, MissionNode, NodeKind, MISSION_SCHEMA_VERSION,
    PORTAL_COST, VERTICAL_COST,
};
use derelict_core::structural::plan::Cell;

#[test]
fn mission_node_round_trips_as_closed_dto() {
    let node = MissionNode {
        id: "start".into(),
        kind: NodeKind::Start,
        room: 1,
        cell: Cell::new(0, 1, 2),
        key_id: None,
        repair_id: None,
    };
    let json = serde_json::to_string(&node).unwrap();
    assert_eq!(serde_json::from_str::<MissionNode>(&json).unwrap(), node);
    assert!(serde_json::from_str::<MissionNode>(&json.replace("}", ",\"extra\":1}")).is_err());
}

#[test]
fn schema_constants_and_graph_json_are_stable() {
    let graph = MissionGraph {
        schema_version: MISSION_SCHEMA_VERSION.into(),
        mission_id: "survey".into(),
        start_node: "start".into(),
        required_objectives: vec!["goal".into()],
        extraction_node: "extract".into(),
        nodes: vec![],
        edges: vec![],
        gates: vec![],
    };
    let graph_json = serde_json::to_string(&graph).unwrap();
    assert!(graph_json.contains(MISSION_SCHEMA_VERSION));
    assert_eq!(PORTAL_COST, 1000);
    assert_eq!(VERTICAL_COST, 1500);
    let _: fn(&str) -> Result<derelict_core::site::SiteIR, _> = site_from_json;
    let _: fn(&derelict_core::site::SiteIR) -> Result<String, _> = site_json;
}
