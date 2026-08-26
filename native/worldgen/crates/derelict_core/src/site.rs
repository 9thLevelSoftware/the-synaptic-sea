//! Validated, deterministic mission overlay for an already-generated ship.
//! This module deliberately owns no structural generation state.
use crate::model::Ship;
use crate::structural::plan::{edge_key, Cell, EdgeKind, NO_ROOM};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub const SITE_SCHEMA_VERSION: &str = "site-ir-2";
pub const MISSION_SCHEMA_VERSION: &str = "site-mission-1";
pub const NAVIGATION_SCHEMA_VERSION: &str = "site-navigation-1";
pub const SPATIAL_SCHEMA_VERSION: &str = "site-spatial-1";
pub const PORTAL_COST: u32 = 1_000;
pub const VERTICAL_COST: u32 = 1_500;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SiteIR {
    pub schema_version: String,
    pub ship: Ship,
    pub mission_graph: MissionGraph,
    pub navigation: Navigation,
    pub functional_props: Vec<FunctionalProp>,
    pub spatial_annotations: SpatialAnnotations,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum NodeKind {
    Start,
    AcquireKey,
    Repair,
    Objective,
    Extraction,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct MissionNode {
    pub id: String,
    pub kind: NodeKind,
    pub room: u16,
    pub cell: Cell,
    pub key_id: Option<String>,
    pub repair_id: Option<String>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum GateKind {
    KeyLock,
    Repair,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct MissionGate {
    pub id: String,
    pub kind: GateKind,
    pub navigation_edge: String,
    pub prerequisite_node: String,
    pub unlock_node: String,
    pub key_id: Option<String>,
    pub repair_id: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct MissionEdge {
    pub from: String,
    pub to: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct MissionGraph {
    pub schema_version: String,
    pub mission_id: String,
    pub start_node: String,
    pub required_objectives: Vec<String>,
    pub extraction_node: String,
    pub nodes: Vec<MissionNode>,
    pub edges: Vec<MissionEdge>,
    pub gates: Vec<MissionGate>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum NavigationKind {
    Portal,
    Vertical,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct NavigationNode {
    pub room: u16,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct NavigationEdge {
    pub id: String,
    pub structural_ref: String,
    pub from_room: u16,
    pub to_room: u16,
    pub from_cell: Cell,
    pub to_cell: Cell,
    pub kind: NavigationKind,
    pub cost: u32,
    pub clearance: u16,
    pub gate_id: Option<String>,
    pub passable: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Navigation {
    pub schema_version: String,
    pub nodes: Vec<NavigationNode>,
    pub edges: Vec<NavigationEdge>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum PropKind {
    KeyPickup,
    RepairPanel,
    ObjectiveConsole,
    ExtractionConsole,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct FunctionalProp {
    pub id: String,
    pub kind: PropKind,
    pub room: u16,
    pub anchor: Cell,
    pub approach: Cell,
    pub mission_node_id: String,
    pub key_id: Option<String>,
    pub repair_id: Option<String>,
    pub extraction_portal_ref: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LosPair {
    pub a: Cell,
    pub b: Cell,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SpatialAnnotation {
    pub room: u16,
    pub minimum_clearance: u16,
    pub cover_cells: Vec<Cell>,
    pub los_pairs: Vec<LosPair>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SpatialAnnotations {
    pub schema_version: String,
    pub rooms: Vec<SpatialAnnotation>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ValidationError(pub String);
impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for ValidationError {}

fn room_cells(ship: &Ship) -> BTreeMap<u16, BTreeSet<Cell>> {
    ship.topology
        .rooms
        .iter()
        .map(|r| (r.id, r.cells.iter().copied().collect()))
        .collect()
}
fn node<'a>(g: &'a MissionGraph, id: &str) -> Option<&'a MissionNode> {
    g.nodes.iter().find(|n| n.id == id)
}

/// Validate identity, sockets, gates, and bounded ordered progression.
pub fn validate_site(site: &SiteIR) -> Result<(), ValidationError> {
    if site.schema_version != SITE_SCHEMA_VERSION
        || site.mission_graph.schema_version != MISSION_SCHEMA_VERSION
        || site.navigation.schema_version != NAVIGATION_SCHEMA_VERSION
        || site.spatial_annotations.schema_version != SPATIAL_SCHEMA_VERSION
    {
        return Err(ValidationError("schema version mismatch".into()));
    }
    if site.ship.generator_version != crate::model::GENERATOR_VERSION {
        return Err(ValidationError(
            "structural generator identity mismatch".into(),
        ));
    }
    let cells = room_cells(&site.ship);
    let g = &site.mission_graph;
    let mut ids = BTreeSet::new();
    let mut keys = BTreeSet::new();
    let mut repairs = BTreeSet::new();
    for n in &g.nodes {
        if n.id.is_empty()
            || !ids.insert(n.id.clone())
            || !cells.get(&n.room).is_some_and(|c| c.contains(&n.cell))
        {
            return Err(ValidationError("invalid mission node identity/cell".into()));
        }
        match n.kind {
            NodeKind::AcquireKey => {
                let k = n
                    .key_id
                    .as_ref()
                    .filter(|x| !x.is_empty())
                    .ok_or_else(|| ValidationError("acquire key missing key_id".into()))?;
                if !keys.insert(k.clone()) {
                    return Err(ValidationError("duplicate key_id".into()));
                }
            }
            NodeKind::Repair => {
                let r = n
                    .repair_id
                    .as_ref()
                    .filter(|x| !x.is_empty())
                    .ok_or_else(|| ValidationError("repair missing repair_id".into()))?;
                if !repairs.insert(r.clone()) {
                    return Err(ValidationError("duplicate repair_id".into()));
                }
            }
            _ => {
                if n.key_id.is_some() || n.repair_id.is_some() {
                    return Err(ValidationError("unexpected node binding".into()));
                }
            }
        }
    }
    if node(g, &g.start_node).is_none() || node(g, &g.extraction_node).is_none() {
        return Err(ValidationError("missing start/extraction".into()));
    }
    let edge_ids: BTreeSet<_> = site
        .navigation
        .edges
        .iter()
        .map(|e| e.id.as_str())
        .collect();
    for e in &site.navigation.edges {
        if e.cost == 0
            || e.clearance == 0
            || !cells.contains_key(&e.from_room)
            || !cells.contains_key(&e.to_room)
        {
            return Err(ValidationError("invalid navigation edge".into()));
        }
    }
    for gate in &g.gates {
        if !edge_ids.contains(gate.navigation_edge.as_str())
            || node(g, &gate.prerequisite_node).is_none()
            || node(g, &gate.unlock_node).is_none()
        {
            return Err(ValidationError("dangling gate".into()));
        }
        match gate.kind {
            GateKind::KeyLock => {
                if gate.key_id.as_ref().is_none_or(|x| !keys.contains(x)) {
                    return Err(ValidationError("invalid key gate".into()));
                }
            }
            GateKind::Repair => {
                if gate.repair_id.as_ref().is_none_or(|x| !repairs.contains(x)) {
                    return Err(ValidationError("invalid repair gate".into()));
                }
            }
        }
    }
    let mut prop_sockets = BTreeSet::new();
    let mut prop_cells = BTreeSet::new();
    let mut extracts = 0;
    for p in &site.functional_props {
        if p.id.is_empty()
            || !cells
                .get(&p.room)
                .is_some_and(|c| c.contains(&p.anchor) && c.contains(&p.approach))
            || (p.anchor.x - p.approach.x).abs() + (p.anchor.y - p.approach.y).abs() != 1
            || !prop_sockets.insert((p.anchor, p.approach))
            || !prop_cells.insert(p.anchor)
            || !prop_cells.insert(p.approach)
        {
            return Err(ValidationError("invalid functional prop socket".into()));
        }
        if node(g, &p.mission_node_id).is_none() {
            return Err(ValidationError("prop missing mission node".into()));
        }
        if matches!(p.kind, PropKind::ExtractionConsole) {
            extracts += 1;
        }
    }
    if extracts != 1 {
        return Err(ValidationError(
            "exactly one extraction console required".into(),
        ));
    }
    // Bounded reachability of mission graph (cycles are rejected by requiring a topological order).
    let mut indeg: BTreeMap<&str, usize> = g.nodes.iter().map(|n| (n.id.as_str(), 0)).collect();
    for e in &g.edges {
        if !indeg.contains_key(e.from.as_str()) || !indeg.contains_key(e.to.as_str()) {
            return Err(ValidationError("dangling mission edge".into()));
        }
        *indeg.get_mut(e.to.as_str()).unwrap() += 1;
    }
    let mut q: VecDeque<&str> = indeg
        .iter()
        .filter(|(_, d)| **d == 0)
        .map(|(k, _)| *k)
        .collect();
    let mut seen = 0;
    while let Some(x) = q.pop_front() {
        seen += 1;
        for e in &g.edges {
            if e.from == x {
                let d = indeg.get_mut(e.to.as_str()).unwrap();
                *d -= 1;
                if *d == 0 {
                    q.push_back(e.to.as_str());
                }
            }
        }
    }
    if seen != g.nodes.len() {
        return Err(ValidationError("cyclic mission progression".into()));
    }
    Ok(())
}

/// Deterministically project structural portals and verticals into navigation.
pub fn project_navigation(ship: &Ship) -> Navigation {
    let mut edges = Vec::new();
    for p in &ship.topology.portals {
        if p.exterior || p.to_room == NO_ROOM {
            continue;
        }
        let r = edge_key(
            p.from_cell,
            crate::structural::plan::Dir::between(p.from_cell, p.to_cell)
                .unwrap_or(crate::structural::plan::Dir::North),
        );
        let blocked = p.state == EdgeKind::Locked;
        for (a, b, ca, cb) in [
            (p.from_room, p.to_room, p.from_cell, p.to_cell),
            (p.to_room, p.from_room, p.to_cell, p.from_cell),
        ] {
            edges.push(NavigationEdge {
                id: format!("portal:{}:{}:{}", r, a, b),
                structural_ref: r.clone(),
                from_room: a,
                to_room: b,
                from_cell: ca,
                to_cell: cb,
                kind: NavigationKind::Portal,
                cost: PORTAL_COST,
                clearance: 1,
                gate_id: None,
                passable: !blocked,
            });
        }
    }
    for v in &ship.topology.verticals {
        let a = format!(
            "{}|{}|{}|{}",
            v.from_cell.deck, v.from_cell.x, v.from_cell.y, v.from_room
        );
        let b = format!(
            "{}|{}|{}|{}",
            v.to_cell.deck, v.to_cell.x, v.to_cell.y, v.to_room
        );
        let reference = if a <= b {
            format!("vertical:{}:{}", a, b)
        } else {
            format!("vertical:{}:{}", b, a)
        };
        for (x, y, cx, cy) in [
            (v.from_room, v.to_room, v.from_cell, v.to_cell),
            (v.to_room, v.from_room, v.to_cell, v.from_cell),
        ] {
            edges.push(NavigationEdge {
                id: format!("{}:{}:{}", reference, x, y),
                structural_ref: reference.clone(),
                from_room: x,
                to_room: y,
                from_cell: cx,
                to_cell: cy,
                kind: NavigationKind::Vertical,
                cost: VERTICAL_COST,
                clearance: 1,
                gate_id: None,
                passable: true,
            });
        }
    }
    edges.sort_by(|a, b| a.id.cmp(&b.id));
    Navigation {
        schema_version: NAVIGATION_SCHEMA_VERSION.into(),
        nodes: ship
            .topology
            .rooms
            .iter()
            .map(|r| NavigationNode { room: r.id })
            .collect(),
        edges,
    }
}

pub fn site_json(site: &SiteIR) -> Result<String, serde_json::Error> {
    serde_json::to_string(site)
}
pub fn site_from_json(data: &str) -> Result<SiteIR, serde_json::Error> {
    serde_json::from_str(data)
}
