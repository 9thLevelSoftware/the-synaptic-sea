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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SiteTemplate {
    pub id: String,
    pub archetypes: Vec<String>,
    pub gate: Option<GateKind>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SiteRules {
    pub schema_version: String,
    pub templates: Vec<SiteTemplate>,
    pub portal_cost: u32,
    pub vertical_cost: u32,
    pub clearance: u16,
    pub max_repairs: u8,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SiteFallback {
    pub schema_version: String,
    pub mission_id: String,
    pub mode: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SiteTrace {
    pub candidate_decisions: Vec<String>,
    pub repairs: Vec<String>,
    pub fallback: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SiteGenerationOutcome {
    pub site: SiteIR,
    pub trace: SiteTrace,
}
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum SiteError {
    #[error("invalid site request: {0}")]
    Invalid(String),
    #[error("site validation: {0}")]
    Validation(String),
    #[error("site rules: {0}")]
    Rules(String),
}

impl SiteRules {
    pub fn bundled() -> Result<Self, SiteError> {
        serde_json::from_str(include_str!("../assets/site/rules_v2.json"))
            .map_err(|e| SiteError::Rules(e.to_string()))
    }
    pub fn validate(&self) -> Result<(), SiteError> {
        if self.schema_version != "site-rules-1"
            || self.templates.len() != 3
            || self.portal_cost != PORTAL_COST
            || self.vertical_cost != VERTICAL_COST
            || self.clearance != 1
            || self.max_repairs != 2
        {
            return Err(SiteError::Rules("closed rules mismatch".into()));
        }
        Ok(())
    }
}
impl SiteFallback {
    pub fn bundled() -> Result<Self, SiteError> {
        serde_json::from_str(include_str!("../assets/site/safe_fallback_v2.json"))
            .map_err(|e| SiteError::Rules(e.to_string()))
    }
    pub fn validate(&self) -> Result<(), SiteError> {
        if self.schema_version != "site-fallback-1" || self.mode != "ungated-critical-path-reverse"
        {
            return Err(SiteError::Rules("fallback identity".into()));
        }
        Ok(())
    }
}

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
    // The request identity is checked by generate_site; this guard still rejects
    // malformed hand-authored overlays without attempting to infer identity.
    if site.ship.seed > crate::world::MAX_PUBLIC_SEED {
        return Err(ValidationError("ship seed out of range".into()));
    }
    let projected = project_navigation(&site.ship)?;
    if site.navigation.nodes != projected.nodes {
        return Err(ValidationError("navigation room identity mismatch".into()));
    }
    if site.navigation.edges.len() != projected.edges.len() {
        return Err(ValidationError(
            "navigation directed edge count mismatch".into(),
        ));
    }
    for actual in &site.navigation.edges {
        let expected = projected
            .edges
            .iter()
            .find(|e| e.id == actual.id)
            .ok_or_else(|| ValidationError("navigation edge identity mismatch".into()))?;
        if actual.structural_ref != expected.structural_ref
            || actual.from_room != expected.from_room
            || actual.to_room != expected.to_room
            || actual.from_cell != expected.from_cell
            || actual.to_cell != expected.to_cell
            || actual.cost != expected.cost
            || actual.clearance != expected.clearance
        {
            return Err(ValidationError("navigation projection mismatch".into()));
        }
        if actual.gate_id.is_some() && (actual.passable || actual.clearance != 1) {
            return Err(ValidationError(
                "gated navigation edge must be blocked".into(),
            ));
        }
    }
    let spatial = compute_spatial(&site.ship)?;
    if site.spatial_annotations != spatial {
        return Err(ValidationError("spatial projection mismatch".into()));
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
        let bound: Vec<_> = site
            .navigation
            .edges
            .iter()
            .filter(|e| e.gate_id.as_deref() == Some(&gate.id))
            .collect();
        if bound.len() != 2
            || bound[0].from_room != bound[1].to_room
            || bound[0].to_room != bound[1].from_room
        {
            return Err(ValidationError("gate must bind both directions".into()));
        }
        if bound.iter().any(|e| e.passable) {
            return Err(ValidationError("gate edge is passable".into()));
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
        let n = node(g, &p.mission_node_id).unwrap();
        if n.room != p.room || n.cell != p.anchor {
            return Err(ValidationError("prop/node room mismatch".into()));
        }
        match p.kind {
            PropKind::KeyPickup => {
                if p.key_id.is_none() || p.repair_id.is_some() {
                    return Err(ValidationError("key prop binding".into()));
                }
            }
            PropKind::RepairPanel => {
                if p.repair_id.is_none() || p.key_id.is_some() {
                    return Err(ValidationError("repair prop binding".into()));
                }
            }
            PropKind::ObjectiveConsole => {
                if p.key_id.is_some() || p.repair_id.is_some() {
                    return Err(ValidationError("objective prop binding".into()));
                }
            }
            PropKind::ExtractionConsole => {
                if p.key_id.is_some() || p.repair_id.is_some() {
                    return Err(ValidationError("extraction prop binding".into()));
                }
            }
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
    let extraction = site
        .functional_props
        .iter()
        .find(|p| matches!(p.kind, PropKind::ExtractionConsole))
        .unwrap();
    let entry_portals: Vec<_> = site
        .ship
        .topology
        .portals
        .iter()
        .filter(|p| p.exterior && p.from_room == site.ship.entry_room && p.state == EdgeKind::Door)
        .collect();
    if entry_portals.len() != 1 {
        return Err(ValidationError("entry exterior door cardinality".into()));
    }
    let ep = entry_portals[0];
    let edir = crate::structural::plan::Dir::between(ep.from_cell, ep.to_cell)
        .ok_or_else(|| ValidationError("entry door direction".into()))?;
    let eref = edge_key(ep.from_cell, edir);
    if extraction.extraction_portal_ref.as_deref() != Some(eref.as_str()) {
        return Err(ValidationError("extraction portal binding".into()));
    }
    for p in &site.ship.topology.portals {
        if p.state == EdgeKind::Locked
            && !site.navigation.edges.iter().any(|e| {
                e.structural_ref
                    == edge_key(
                        p.from_cell,
                        crate::structural::plan::Dir::between(p.from_cell, p.to_cell).unwrap(),
                    )
                    && e.gate_id.is_some()
            })
        {
            return Err(ValidationError("unbound locked portal".into()));
        }
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
    run_progression_agent(site)?;
    Ok(())
}

/// Deterministically project structural portals and verticals into navigation.
pub fn canonical_vertical_ref(from: (u8, i32, i32, u16), to: (u8, i32, i32, u16)) -> String {
    let a = format!("{}|{}|{}|{}", from.0, from.1, from.2, from.3);
    let b = format!("{}|{}|{}|{}", to.0, to.1, to.2, to.3);
    if a <= b {
        format!("vertical:{a}:{b}")
    } else {
        format!("vertical:{b}:{a}")
    }
}

pub fn project_navigation(ship: &Ship) -> Result<Navigation, ValidationError> {
    let mut edges = Vec::new();
    for p in &ship.topology.portals {
        if p.exterior || p.to_room == NO_ROOM {
            continue;
        }
        let dir = crate::structural::plan::Dir::between(p.from_cell, p.to_cell)
            .ok_or_else(|| ValidationError("portal non-cardinal adjacency".into()))?;
        let r = edge_key(p.from_cell, dir);
        let plan = ship
            .plan
            .edges
            .get(&r)
            .ok_or_else(|| ValidationError("portal structural ref missing".into()))?;
        if plan.room_ids != (p.from_room, p.to_room) && plan.room_ids != (p.to_room, p.from_room) {
            return Err(ValidationError("portal structural rooms mismatch".into()));
        }
        if plan.source_cells[0] != p.from_cell && plan.source_cells[1] != p.from_cell {
            return Err(ValidationError("portal source cell mismatch".into()));
        }
        if matches!(plan.kind, EdgeKind::Solid | EdgeKind::Open) {
            return Err(ValidationError("invalid portal effective kind".into()));
        }
        let blocked = plan.kind == EdgeKind::Locked;
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
        let reference = canonical_vertical_ref(
            (v.from_cell.deck, v.from_cell.x, v.from_cell.y, v.from_room),
            (v.to_cell.deck, v.to_cell.x, v.to_cell.y, v.to_room),
        );
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
    Ok(Navigation {
        schema_version: NAVIGATION_SCHEMA_VERSION.into(),
        nodes: ship
            .topology
            .rooms
            .iter()
            .map(|r| NavigationNode { room: r.id })
            .collect(),
        edges,
    })
}

pub fn compute_spatial(ship: &Ship) -> Result<SpatialAnnotations, ValidationError> {
    let rooms = room_cells(ship);
    let mut out = Vec::new();
    for room in &ship.topology.rooms {
        let cells = rooms
            .get(&room.id)
            .ok_or_else(|| ValidationError("spatial room missing".into()))?;
        let mut cover = BTreeSet::new();
        for edge in ship
            .plan
            .edges
            .values()
            .filter(|e| e.kind == EdgeKind::Solid)
        {
            for c in edge.source_cells {
                if cells.contains(&c) {
                    cover.insert(c);
                }
            }
        }
        let mut pairs = BTreeSet::new();
        let ordered: Vec<_> = cells.iter().copied().collect();
        for &a in &ordered {
            for &b in &ordered {
                if a >= b || a.deck != b.deck {
                    continue;
                }
                let d = (a.x - b.x).abs() + (a.y - b.y).abs();
                if d == 0 || d > 8 || !(a.x == b.x || a.y == b.y) {
                    continue;
                }
                let (lo, hi) = if a < b { (a, b) } else { (b, a) };
                let mut clear = true;
                if a.x == b.x {
                    for y in (a.y.min(b.y) + 1)..b.y.max(a.y) {
                        if !cells.contains(&Cell::new(a.deck, a.x, y)) {
                            clear = false;
                        }
                    }
                } else {
                    for x in (a.x.min(b.x) + 1)..b.x.max(a.x) {
                        if !cells.contains(&Cell::new(a.deck, x, a.y)) {
                            clear = false;
                        }
                    }
                }
                if clear {
                    pairs.insert((lo, hi));
                }
            }
        }
        out.push(SpatialAnnotation {
            room: room.id,
            minimum_clearance: 1,
            cover_cells: cover.into_iter().take(64).collect(),
            los_pairs: pairs
                .into_iter()
                .take(128)
                .map(|(a, b)| LosPair { a, b })
                .collect(),
        });
    }
    out.sort_by_key(|r| r.room);
    Ok(SpatialAnnotations {
        schema_version: SPATIAL_SCHEMA_VERSION.into(),
        rooms: out,
    })
}

pub fn run_progression_agent(site: &SiteIR) -> Result<(), ValidationError> {
    let mut reached = BTreeSet::from([site.ship.entry_room]);
    let mut completed = BTreeSet::new();
    let mut changed = true;
    while changed {
        changed = false;
        for e in &site.navigation.edges {
            let open = e.passable
                || e.gate_id.as_ref().is_some_and(|gid| {
                    site.mission_graph
                        .gates
                        .iter()
                        .any(|g| &g.id == gid && completed.contains(&g.prerequisite_node))
                });
            if open && reached.contains(&e.from_room) && reached.insert(e.to_room) {
                changed = true;
            }
        }
        for id in site
            .mission_graph
            .required_objectives
            .iter()
            .chain(std::iter::once(&site.mission_graph.extraction_node))
        {
            if let Some(n) = node(&site.mission_graph, id) {
                if reached.contains(&n.room) {
                    completed.insert(id.clone());
                }
            }
        }
        for g in &site.mission_graph.gates {
            if let Some(n) = node(&site.mission_graph, &g.prerequisite_node) {
                if reached.contains(&n.room) {
                    completed.insert(g.prerequisite_node.clone());
                }
            }
        }
    }
    for id in &site.mission_graph.required_objectives {
        let n = node(&site.mission_graph, id)
            .ok_or_else(|| ValidationError("objective missing".into()))?;
        if !reached.contains(&n.room) {
            return Err(ValidationError("objective unreachable".into()));
        }
    }
    let ex = node(&site.mission_graph, &site.mission_graph.extraction_node)
        .ok_or_else(|| ValidationError("extraction missing".into()))?;
    if !reached.contains(&ex.room) {
        return Err(ValidationError("extraction unreachable".into()));
    }
    Ok(())
}

pub fn site_json(site: &SiteIR) -> Result<String, serde_json::Error> {
    serde_json::to_string(site)
}
pub fn site_from_json(data: &str) -> Result<SiteIR, serde_json::Error> {
    serde_json::from_str(data)
}

/// Compile one deterministic overlay. Structural generation is never rerun.
pub fn generate_site(
    ship: Ship,
    request: &crate::world::WorldGenerationRequest,
) -> Result<SiteGenerationOutcome, SiteError> {
    if request.platform_version != crate::world::PROCGEN_GENERATOR_VERSION
        || request.archetype_id != ship.archetype_id
    {
        return Err(SiteError::Invalid("request identity".into()));
    }
    let structural_key = crate::world::WorldKey {
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
    if ship.seed
        != structural_key
            .seed()
            .map_err(|e| SiteError::Invalid(e.into()))?
    {
        return Err(SiteError::Invalid("ship seed identity".into()));
    }
    let rules = SiteRules::bundled()?;
    rules.validate()?;
    let compatible: Vec<_> = rules
        .templates
        .iter()
        .filter(|t| t.archetypes.iter().any(|a| a == &request.archetype_id))
        .cloned()
        .collect();
    if compatible.is_empty() {
        return Err(SiteError::Rules("no compatible template".into()));
    }
    let template_key = crate::world::WorldKey {
        domain: "site".into(),
        channel: "site.template".into(),
        sub_index: 0,
        ..structural_key.clone()
    };
    let pick = (template_key
        .seed()
        .map_err(|e| SiteError::Invalid(e.into()))? as usize)
        % compatible.len();
    let template = compatible[pick].clone();
    let decisions = compatible
        .iter()
        .enumerate()
        .map(|(i, t)| {
            format!(
                "{}:{}",
                t.id,
                if i == pick { "selected" } else { "rejected" }
            )
        })
        .collect();
    let rooms = ship.critical_path.clone();
    if rooms.is_empty() {
        return Err(SiteError::Invalid("empty critical path".into()));
    }
    let cell_for = |id: u16| {
        ship.topology
            .room(id)
            .and_then(|r| r.cells.iter().min().copied())
            .ok_or_else(|| SiteError::Invalid("room cell".into()))
    };
    let mut nodes = Vec::new();
    let mut edges = Vec::new();
    let mut props = Vec::new();
    let start = cell_for(rooms[0])?;
    nodes.push(MissionNode {
        id: "start".into(),
        kind: NodeKind::Start,
        room: rooms[0],
        cell: start,
        key_id: None,
        repair_id: None,
    });
    let goal = cell_for(*rooms.last().unwrap())?;
    let mut navigation = project_navigation(&ship).map_err(|e| SiteError::Validation(e.0))?;
    let gated = template.gate;
    let prereq_room = if rooms.len() > 1 {
        rooms[rooms.len() - 2]
    } else {
        rooms[0]
    };
    if gated.is_some() {
        let pc = cell_for(prereq_room)?;
        let (kind, key_id, repair_id) = match gated {
            Some(GateKind::KeyLock) => (NodeKind::AcquireKey, Some("key-0".into()), None),
            _ => (NodeKind::Repair, None, Some("repair-0".into())),
        };
        nodes.push(MissionNode {
            id: "prerequisite".into(),
            kind,
            room: prereq_room,
            cell: pc,
            key_id: key_id.clone(),
            repair_id: repair_id.clone(),
        });
        edges.push(MissionEdge {
            from: "start".into(),
            to: "prerequisite".into(),
        });
    }
    nodes.push(MissionNode {
        id: "objective-0".into(),
        kind: NodeKind::Objective,
        room: *rooms.last().unwrap(),
        cell: goal,
        key_id: None,
        repair_id: None,
    });
    nodes.push(MissionNode {
        id: "extract".into(),
        kind: NodeKind::Extraction,
        room: ship.entry_room,
        cell: cell_for(ship.entry_room)?,
        key_id: None,
        repair_id: None,
    });
    if gated.is_none() {
        edges.push(MissionEdge {
            from: "start".into(),
            to: "objective-0".into(),
        });
    }
    edges.push(MissionEdge {
        from: "objective-0".into(),
        to: "extract".into(),
    });
    let pair = |room: u16, used: &BTreeSet<Cell>| -> Result<(Cell, Cell), SiteError> {
        let cs = ship
            .topology
            .room(room)
            .ok_or_else(|| SiteError::Invalid("room".into()))?
            .cells
            .clone();
        for a in &cs {
            for b in &cs {
                if (a.x - b.x).abs() + (a.y - b.y).abs() == 1
                    && !used.contains(a)
                    && !used.contains(b)
                {
                    return Ok((*a, *b));
                }
            }
        }
        Err(SiteError::Invalid("socket".into()))
    };
    let mut used = BTreeSet::new();
    let (oa, op) = pair(*rooms.last().unwrap(), &used)?;
    used.insert(oa);
    used.insert(op);
    props.push(FunctionalProp {
        id: "prop-objective".into(),
        kind: PropKind::ObjectiveConsole,
        room: *rooms.last().unwrap(),
        anchor: oa,
        approach: op,
        mission_node_id: "objective-0".into(),
        key_id: None,
        repair_id: None,
        extraction_portal_ref: None,
    });
    if let Some(n) = nodes.iter_mut().find(|n| n.id == "objective-0") {
        n.cell = oa;
    }
    let mut gates = Vec::new();
    if let Some(gk) = gated {
        let (pa, pp) = pair(prereq_room, &used)?;
        used.insert(pa);
        used.insert(pp);
        props.push(FunctionalProp {
            id: "prop-prerequisite".into(),
            kind: if gk == GateKind::KeyLock {
                PropKind::KeyPickup
            } else {
                PropKind::RepairPanel
            },
            room: prereq_room,
            anchor: pa,
            approach: pp,
            mission_node_id: "prerequisite".into(),
            key_id: if gk == GateKind::KeyLock {
                Some("key-0".into())
            } else {
                None
            },
            repair_id: if gk == GateKind::Repair {
                Some("repair-0".into())
            } else {
                None
            },
            extraction_portal_ref: None,
        });
        if let Some(n) = nodes.iter_mut().find(|n| n.id == "prerequisite") {
            n.cell = pa;
        }
        let nav = project_navigation(&ship).map_err(|e| SiteError::Validation(e.0))?;
        let target = nav
            .edges
            .iter()
            .find(|e| {
                e.from_room == prereq_room
                    && e.to_room == *rooms.last().unwrap()
                    && e.kind == NavigationKind::Portal
            })
            .or_else(|| nav.edges.iter().find(|e| e.kind == NavigationKind::Portal))
            .ok_or_else(|| SiteError::Invalid("gate edge".into()))?;
        for e in &mut navigation.edges {
            if e.structural_ref == target.structural_ref {
                e.gate_id = Some("gate-0".into());
                e.passable = false;
            }
        }
        gates.push(MissionGate {
            id: "gate-0".into(),
            kind: gk,
            navigation_edge: target.id.clone(),
            prerequisite_node: "prerequisite".into(),
            unlock_node: "objective-0".into(),
            key_id: if gk == GateKind::KeyLock {
                Some("key-0".into())
            } else {
                None
            },
            repair_id: if gk == GateKind::Repair {
                Some("repair-0".into())
            } else {
                None
            },
        });
        edges.push(MissionEdge {
            from: "prerequisite".into(),
            to: "objective-0".into(),
        });
    }
    let extraction_ref = ship
        .topology
        .portals
        .iter()
        .find(|p| p.from_room == ship.entry_room && p.exterior && p.state == EdgeKind::Door)
        .map(|p| {
            edge_key(
                p.from_cell,
                crate::structural::plan::Dir::between(p.from_cell, p.to_cell)
                    .unwrap_or(crate::structural::plan::Dir::North),
            )
        })
        .ok_or_else(|| SiteError::Invalid("entry extraction portal".into()))?;
    let (ea, ep) = pair(ship.entry_room, &used)?;
    props.push(FunctionalProp {
        id: "prop-extraction".into(),
        kind: PropKind::ExtractionConsole,
        room: ship.entry_room,
        anchor: ea,
        approach: ep,
        mission_node_id: "extract".into(),
        key_id: None,
        repair_id: None,
        extraction_portal_ref: Some(extraction_ref),
    });
    if let Some(n) = nodes.iter_mut().find(|n| n.id == "extract") {
        n.cell = ea;
    }
    let spatial = compute_spatial(&ship).map_err(|e| SiteError::Validation(e.0))?;
    let site = SiteIR {
        schema_version: SITE_SCHEMA_VERSION.into(),
        ship,
        mission_graph: MissionGraph {
            schema_version: MISSION_SCHEMA_VERSION.into(),
            mission_id: template.id,
            start_node: "start".into(),
            required_objectives: vec!["objective-0".into()],
            extraction_node: "extract".into(),
            nodes,
            edges,
            gates,
        },
        navigation,
        functional_props: props,
        spatial_annotations: spatial,
    };
    validate_site(&site).map_err(|e| SiteError::Validation(e.0))?;
    Ok(SiteGenerationOutcome {
        site,
        trace: SiteTrace {
            candidate_decisions: decisions,
            repairs: Vec::new(),
            fallback: None,
        },
    })
}
