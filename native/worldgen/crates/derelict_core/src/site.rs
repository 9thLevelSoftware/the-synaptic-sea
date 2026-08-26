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
pub const SITE_RNG_CHANNELS: [&str; 4] = [
    "site.mission_template",
    "site.gate_order",
    "site.functional_props",
    "site.spatial_annotations",
];
const MAX_SITE_DECISIONS: usize = 64;

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
        let expected = [
            ("key_lock_salvage", Some(GateKind::KeyLock)),
            ("repair_recovery", Some(GateKind::Repair)),
            ("survey", None),
        ];
        let mut actual: Vec<_> = self
            .templates
            .iter()
            .map(|template| (template.id.as_str(), template.gate))
            .collect();
        actual.sort_by_key(|(id, _)| *id);
        if actual != expected
            || self.templates.iter().any(|template| {
                template.id.is_empty()
                    || template.archetypes != ["shuttle", "corvette", "freighter", "frigate"]
                    || template.archetypes.iter().collect::<BTreeSet<_>>().len()
                        != template.archetypes.len()
            })
        {
            return Err(SiteError::Rules("template catalogue".into()));
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
        if self.schema_version != "site-fallback-1"
            || self.mission_id != "authored-safe-return"
            || self.mode != "ungated-critical-path-reverse"
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

fn mission_reaches<'a>(adjacency: &BTreeMap<&'a str, Vec<&'a str>>, from: &str, to: &str) -> bool {
    let mut reached = BTreeSet::from([from]);
    let mut queue = VecDeque::from([from]);
    while let Some(id) = queue.pop_front() {
        for target in adjacency.get(id).into_iter().flatten() {
            if *target == to {
                return true;
            }
            if reached.insert(*target) {
                queue.push_back(*target);
            }
        }
    }
    false
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
    if site.ship.generator_version != crate::model::GENERATOR_VERSION
        || site.ship.seed > crate::world::MAX_PUBLIC_SEED
    {
        return Err(ValidationError("ship identity".into()));
    }
    site.ship
        .topology
        .validate()
        .map_err(|_| ValidationError("topology identity".into()))?;
    if site.ship.critical_path.is_empty()
        || site.ship.critical_path.first() != Some(&site.ship.entry_room)
        || site.ship.critical_path.last() != Some(&site.ship.goal_room)
        || site
            .ship
            .critical_path
            .iter()
            .collect::<BTreeSet<_>>()
            .len()
            != site.ship.critical_path.len()
    {
        return Err(ValidationError("critical path identity".into()));
    }
    let fragment_of = site.ship.fractured.then(|| {
        site.ship
            .fragments
            .iter()
            .flat_map(|fragment| fragment.rooms.iter().map(move |room| (*room, fragment.id)))
            .collect()
    });
    let structural_policy = crate::structural::validate::ValidationPolicy::post_damage(
        site.ship.critical_path.clone(),
        fragment_of,
        false,
    );
    if crate::structural::validate::validate(
        &site.ship.plan,
        &site.ship.topology,
        &structural_policy,
    )
    .is_err()
    {
        return Err(ValidationError("structural plan identity".into()));
    }
    if site.mission_graph.mission_id.is_empty()
        || site.mission_graph.nodes.len() < 3
        || site.mission_graph.nodes.len() > 64
        || site.mission_graph.edges.len() > 128
        || site.mission_graph.gates.len() > 32
        || site.functional_props.len() > 64
    {
        return Err(ValidationError("site bounds".into()));
    }

    let projected = project_navigation(&site.ship)?;
    if site.navigation.nodes != projected.nodes
        || site.navigation.edges.len() != projected.edges.len()
        || site
            .navigation
            .edges
            .windows(2)
            .any(|pair| pair[0].id >= pair[1].id)
    {
        return Err(ValidationError("navigation identity".into()));
    }
    let projected_by_id: BTreeMap<_, _> = projected
        .edges
        .iter()
        .map(|edge| (edge.id.as_str(), edge))
        .collect();
    for actual in &site.navigation.edges {
        let expected = projected_by_id
            .get(actual.id.as_str())
            .ok_or_else(|| ValidationError("navigation edge identity".into()))?;
        if actual.structural_ref != expected.structural_ref
            || actual.from_room != expected.from_room
            || actual.to_room != expected.to_room
            || actual.from_cell != expected.from_cell
            || actual.to_cell != expected.to_cell
            || actual.kind != expected.kind
            || actual.cost != expected.cost
            || actual.clearance != expected.clearance
        {
            return Err(ValidationError("navigation projection".into()));
        }
        match actual.gate_id.as_deref() {
            Some(id) if id.is_empty() || actual.passable => {
                return Err(ValidationError("navigation gate state".into()))
            }
            None if actual.passable != expected.passable => {
                return Err(ValidationError("navigation passability".into()))
            }
            _ => {}
        }
    }
    if site.spatial_annotations != compute_spatial(&site.ship)? {
        return Err(ValidationError("spatial projection".into()));
    }

    let cells = room_cells(&site.ship);
    let graph = &site.mission_graph;
    let mut node_ids = BTreeSet::new();
    let mut key_nodes = BTreeMap::new();
    let mut repair_nodes = BTreeMap::new();
    let mut kind_counts = [0_usize; 5];
    for mission_node in &graph.nodes {
        if mission_node.id.is_empty()
            || !node_ids.insert(mission_node.id.as_str())
            || !cells
                .get(&mission_node.room)
                .is_some_and(|room| room.contains(&mission_node.cell))
        {
            return Err(ValidationError("mission node identity".into()));
        }
        match mission_node.kind {
            NodeKind::AcquireKey => {
                kind_counts[1] += 1;
                let id = mission_node
                    .key_id
                    .as_deref()
                    .filter(|id| !id.is_empty())
                    .ok_or_else(|| ValidationError("key node binding".into()))?;
                if mission_node.repair_id.is_some() || key_nodes.insert(id, mission_node).is_some()
                {
                    return Err(ValidationError("key node binding".into()));
                }
            }
            NodeKind::Repair => {
                kind_counts[2] += 1;
                let id = mission_node
                    .repair_id
                    .as_deref()
                    .filter(|id| !id.is_empty())
                    .ok_or_else(|| ValidationError("repair node binding".into()))?;
                if mission_node.key_id.is_some() || repair_nodes.insert(id, mission_node).is_some()
                {
                    return Err(ValidationError("repair node binding".into()));
                }
            }
            NodeKind::Start | NodeKind::Objective | NodeKind::Extraction => {
                kind_counts[match mission_node.kind {
                    NodeKind::Start => 0,
                    NodeKind::Objective => 3,
                    NodeKind::Extraction => 4,
                    _ => unreachable!(),
                }] += 1;
                if mission_node.key_id.is_some() || mission_node.repair_id.is_some() {
                    return Err(ValidationError("mission node optional fields".into()));
                }
            }
        }
    }
    if kind_counts[0] != 1
        || kind_counts[3] == 0
        || kind_counts[3] > 16
        || kind_counts[4] != 1
        || kind_counts[3] != graph.required_objectives.len()
    {
        return Err(ValidationError("mission node cardinality".into()));
    }
    let start = node(graph, &graph.start_node)
        .filter(|mission_node| mission_node.kind == NodeKind::Start)
        .ok_or_else(|| ValidationError("mission start".into()))?;
    let extraction_node = node(graph, &graph.extraction_node)
        .filter(|mission_node| mission_node.kind == NodeKind::Extraction)
        .ok_or_else(|| ValidationError("mission extraction".into()))?;
    if start.room != site.ship.entry_room
        || extraction_node.room != site.ship.entry_room
        || graph
            .nodes
            .first()
            .map(|mission_node| mission_node.id.as_str())
            != Some(graph.start_node.as_str())
        || graph
            .nodes
            .last()
            .map(|mission_node| mission_node.id.as_str())
            != Some(graph.extraction_node.as_str())
    {
        return Err(ValidationError("mission endpoint identity".into()));
    }
    if graph.required_objectives.is_empty()
        || graph.required_objectives.len() > 16
        || graph
            .required_objectives
            .iter()
            .collect::<BTreeSet<_>>()
            .len()
            != graph.required_objectives.len()
        || graph.required_objectives.iter().any(|id| {
            node(graph, id).is_none_or(|mission_node| mission_node.kind != NodeKind::Objective)
        })
    {
        return Err(ValidationError("required objectives".into()));
    }

    let mut prop_ids = BTreeSet::new();
    let mut prop_cells = BTreeSet::new();
    let mut props_by_node: BTreeMap<&str, Vec<&FunctionalProp>> = BTreeMap::new();
    for prop in &site.functional_props {
        let mission_node = node(graph, &prop.mission_node_id)
            .ok_or_else(|| ValidationError("prop mission node".into()))?;
        if prop.id.is_empty()
            || !prop_ids.insert(prop.id.as_str())
            || mission_node.room != prop.room
            || mission_node.cell != prop.anchor
            || prop.anchor.deck != prop.approach.deck
            || (prop.anchor.x - prop.approach.x).abs() + (prop.anchor.y - prop.approach.y).abs()
                != 1
            || !cells
                .get(&prop.room)
                .is_some_and(|room| room.contains(&prop.anchor) && room.contains(&prop.approach))
            || site
                .ship
                .plan
                .occupancy
                .get(&prop.anchor.key())
                .is_none_or(|record| record.room_id != prop.room)
            || site
                .ship
                .plan
                .occupancy
                .get(&prop.approach.key())
                .is_none_or(|record| record.room_id != prop.room)
            || !prop_cells.insert(prop.anchor)
            || !prop_cells.insert(prop.approach)
        {
            return Err(ValidationError("functional prop socket".into()));
        }
        let optional_ok = match prop.kind {
            PropKind::KeyPickup => {
                mission_node.kind == NodeKind::AcquireKey
                    && prop.key_id.as_deref() == mission_node.key_id.as_deref()
                    && prop.key_id.as_ref().is_some_and(|id| !id.is_empty())
                    && prop.repair_id.is_none()
                    && prop.extraction_portal_ref.is_none()
            }
            PropKind::RepairPanel => {
                mission_node.kind == NodeKind::Repair
                    && prop.repair_id.as_deref() == mission_node.repair_id.as_deref()
                    && prop.repair_id.as_ref().is_some_and(|id| !id.is_empty())
                    && prop.key_id.is_none()
                    && prop.extraction_portal_ref.is_none()
            }
            PropKind::ObjectiveConsole => {
                mission_node.kind == NodeKind::Objective
                    && prop.key_id.is_none()
                    && prop.repair_id.is_none()
                    && prop.extraction_portal_ref.is_none()
            }
            PropKind::ExtractionConsole => {
                mission_node.kind == NodeKind::Extraction
                    && prop.key_id.is_none()
                    && prop.repair_id.is_none()
                    && prop
                        .extraction_portal_ref
                        .as_ref()
                        .is_some_and(|id| !id.is_empty())
            }
        };
        if !optional_ok {
            return Err(ValidationError("functional prop binding".into()));
        }
        props_by_node
            .entry(prop.mission_node_id.as_str())
            .or_default()
            .push(prop);
    }
    for mission_node in &graph.nodes {
        let required = matches!(
            mission_node.kind,
            NodeKind::AcquireKey | NodeKind::Repair | NodeKind::Extraction
        ) || graph.required_objectives.contains(&mission_node.id);
        let count = props_by_node
            .get(mission_node.id.as_str())
            .map_or(0, |props| props.len());
        if (required && count != 1) || (!required && count != 0) {
            return Err(ValidationError("functional prop cardinality".into()));
        }
    }

    let extraction_props = site
        .functional_props
        .iter()
        .filter(|prop| prop.kind == PropKind::ExtractionConsole)
        .collect::<Vec<_>>();
    let entry_portals = site
        .ship
        .topology
        .portals
        .iter()
        .filter(|portal| {
            portal.exterior
                && portal.from_room == site.ship.entry_room
                && portal.to_room == NO_ROOM
                && portal.state == EdgeKind::Door
        })
        .collect::<Vec<_>>();
    if extraction_props.len() != 1 || entry_portals.len() != 1 {
        return Err(ValidationError("extraction cardinality".into()));
    }
    let entry = entry_portals[0];
    let entry_dir = crate::structural::plan::Dir::between(entry.from_cell, entry.to_cell)
        .ok_or_else(|| ValidationError("extraction direction".into()))?;
    let extraction_ref = edge_key(entry.from_cell, entry_dir);
    if extraction_props[0].extraction_portal_ref.as_deref() != Some(extraction_ref.as_str())
        || site.functional_props.iter().any(|prop| {
            prop.kind != PropKind::ExtractionConsole && prop.extraction_portal_ref.is_some()
        })
    {
        return Err(ValidationError("extraction binding".into()));
    }

    let mut gate_ids = BTreeSet::new();
    let mut bound_refs = BTreeSet::new();
    for gate in &graph.gates {
        let prerequisite = node(graph, &gate.prerequisite_node)
            .ok_or_else(|| ValidationError("gate prerequisite".into()))?;
        if gate.id.is_empty()
            || !gate_ids.insert(gate.id.as_str())
            || gate.prerequisite_node == gate.unlock_node
            || node(graph, &gate.unlock_node).is_none()
        {
            return Err(ValidationError("gate identity".into()));
        }
        let binding_ok = match gate.kind {
            GateKind::KeyLock => {
                prerequisite.kind == NodeKind::AcquireKey
                    && gate.key_id.as_deref() == prerequisite.key_id.as_deref()
                    && gate
                        .key_id
                        .as_ref()
                        .is_some_and(|id| key_nodes.contains_key(id.as_str()))
                    && gate.repair_id.is_none()
            }
            GateKind::Repair => {
                prerequisite.kind == NodeKind::Repair
                    && gate.repair_id.as_deref() == prerequisite.repair_id.as_deref()
                    && gate
                        .repair_id
                        .as_ref()
                        .is_some_and(|id| repair_nodes.contains_key(id.as_str()))
                    && gate.key_id.is_none()
            }
        };
        if !binding_ok {
            return Err(ValidationError("gate binding".into()));
        }
        let bound = site
            .navigation
            .edges
            .iter()
            .filter(|edge| edge.gate_id.as_deref() == Some(gate.id.as_str()))
            .collect::<Vec<_>>();
        if bound.len() != 2
            || bound[0].structural_ref != bound[1].structural_ref
            || bound[0].from_room != bound[1].to_room
            || bound[0].to_room != bound[1].from_room
            || bound.iter().any(|edge| edge.passable)
            || !bound.iter().any(|edge| edge.id == gate.navigation_edge)
            || !bound_refs.insert(bound[0].structural_ref.as_str())
        {
            return Err(ValidationError("gate navigation binding".into()));
        }
    }
    if site.navigation.edges.iter().any(|edge| {
        edge.gate_id
            .as_ref()
            .is_some_and(|id| !gate_ids.contains(id.as_str()))
    }) {
        return Err(ValidationError("dangling navigation gate".into()));
    }
    for expected in &projected.edges {
        if !expected.passable {
            let actual = site
                .navigation
                .edges
                .iter()
                .find(|edge| edge.id == expected.id)
                .expect("projected edge count checked");
            let Some(gate_id) = actual.gate_id.as_deref() else {
                return Err(ValidationError("unbound locked portal".into()));
            };
            if graph
                .gates
                .iter()
                .find(|gate| gate.id == gate_id)
                .is_none_or(|gate| gate.kind != GateKind::KeyLock)
            {
                return Err(ValidationError("locked portal gate kind".into()));
            }
        }
    }

    let mut mission_edges = BTreeSet::new();
    let mut indegree: BTreeMap<&str, usize> = graph
        .nodes
        .iter()
        .map(|mission_node| (mission_node.id.as_str(), 0))
        .collect();
    let mut adjacency: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for edge in &graph.edges {
        if edge.from == edge.to
            || !node_ids.contains(edge.from.as_str())
            || !node_ids.contains(edge.to.as_str())
            || !mission_edges.insert((edge.from.as_str(), edge.to.as_str()))
        {
            return Err(ValidationError("mission edge identity".into()));
        }
        *indegree
            .get_mut(edge.to.as_str())
            .expect("node identity checked") += 1;
        adjacency
            .entry(edge.from.as_str())
            .or_default()
            .push(edge.to.as_str());
    }
    let original_indegree = indegree.clone();
    let mut remaining_indegree = indegree;
    let mut queue: VecDeque<&str> = remaining_indegree
        .iter()
        .filter_map(|(id, degree)| (*degree == 0).then_some(*id))
        .collect();
    let mut topological = 0;
    while let Some(id) = queue.pop_front() {
        topological += 1;
        for target in adjacency.get(id).into_iter().flatten() {
            let degree = remaining_indegree
                .get_mut(target)
                .expect("node identity checked");
            *degree -= 1;
            if *degree == 0 {
                queue.push_back(target);
            }
        }
    }
    if topological != graph.nodes.len() {
        return Err(ValidationError("mission cycle".into()));
    }
    let mut logical_reached = BTreeSet::from([graph.start_node.as_str()]);
    let mut queue = VecDeque::from([graph.start_node.as_str()]);
    while let Some(id) = queue.pop_front() {
        for target in adjacency.get(id).into_iter().flatten() {
            if logical_reached.insert(target) {
                queue.push_back(target);
            }
        }
    }
    if logical_reached.len() != graph.nodes.len()
        || !logical_reached.contains(graph.extraction_node.as_str())
    {
        return Err(ValidationError("mission logical reachability".into()));
    }
    let outdegree = |id: &str| adjacency.get(id).map_or(0, Vec::len);
    if original_indegree.get(graph.start_node.as_str()).copied() != Some(0)
        || outdegree(&graph.extraction_node) != 0
        || graph.nodes.iter().any(|mission_node| {
            mission_node.id != graph.start_node
                && original_indegree
                    .get(mission_node.id.as_str())
                    .is_none_or(|degree| *degree == 0)
        })
        || graph.nodes.iter().any(|mission_node| {
            mission_node.id != graph.extraction_node && outdegree(&mission_node.id) == 0
        })
    {
        return Err(ValidationError("mission endpoint order".into()));
    }
    let checkpoints = std::iter::once(&graph.start_node)
        .chain(graph.required_objectives.iter())
        .chain(std::iter::once(&graph.extraction_node))
        .collect::<Vec<_>>();
    if checkpoints
        .windows(2)
        .any(|pair| !mission_reaches(&adjacency, pair[0].as_str(), pair[1].as_str()))
        || graph.mission_id != "survey"
            && graph.mission_id != "key_lock_salvage"
            && graph.mission_id != "repair_recovery"
            && graph.mission_id != "authored-safe-return"
    {
        return Err(ValidationError("mission ordered checkpoints".into()));
    }
    if graph.gates.iter().any(|gate| {
        !mission_reaches(
            &adjacency,
            gate.prerequisite_node.as_str(),
            gate.unlock_node.as_str(),
        )
    }) {
        return Err(ValidationError("gate mission order".into()));
    }
    let initially_reached = reachable_rooms(site, &BTreeSet::from([graph.start_node.clone()]));
    for gate in &graph.gates {
        let is_mission_added = site.navigation.edges.iter().any(|edge| {
            edge.gate_id.as_deref() == Some(gate.id.as_str())
                && projected
                    .edges
                    .iter()
                    .find(|expected| expected.id == edge.id)
                    .is_some_and(|expected| expected.passable)
        });
        if is_mission_added
            && node(graph, &gate.unlock_node)
                .is_some_and(|unlock| initially_reached.contains(&unlock.room))
        {
            return Err(ValidationError("mission gate bypass".into()));
        }
    }
    run_progression_agent(site)
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
    let rooms = room_cells(ship);
    let mut edges = Vec::new();
    let mut structural_refs = BTreeSet::new();
    for p in &ship.topology.portals {
        if matches!(p.state, EdgeKind::Solid | EdgeKind::Open)
            || p.from_room == p.to_room
            || p.exterior != (p.to_room == NO_ROOM)
            || !rooms
                .get(&p.from_room)
                .is_some_and(|cells| cells.contains(&p.from_cell))
            || (!p.exterior
                && !rooms
                    .get(&p.to_room)
                    .is_some_and(|cells| cells.contains(&p.to_cell)))
            || (p.exterior && rooms.values().any(|cells| cells.contains(&p.to_cell)))
        {
            return Err(ValidationError("portal topology identity".into()));
        }
        let dir = crate::structural::plan::Dir::between(p.from_cell, p.to_cell)
            .ok_or_else(|| ValidationError("portal non-cardinal adjacency".into()))?;
        let r = edge_key(p.from_cell, dir);
        if !structural_refs.insert(r.clone()) {
            return Err(ValidationError("duplicate portal structural ref".into()));
        }
        let plan = ship
            .plan
            .edges
            .get(&r)
            .ok_or_else(|| ValidationError("portal structural ref missing".into()))?;
        let expected_rooms = if p.exterior {
            BTreeSet::from([p.from_room, NO_ROOM])
        } else {
            BTreeSet::from([p.from_room, p.to_room])
        };
        if BTreeSet::from([plan.room_ids.0, plan.room_ids.1]) != expected_rooms
            || BTreeSet::from(plan.source_cells) != BTreeSet::from([p.from_cell, p.to_cell])
            || !plan.portal
            || plan.exterior != p.exterior
            || plan.kind != p.state
            || plan.edge_key != r
        {
            return Err(ValidationError("portal structural rooms mismatch".into()));
        }
        if p.exterior {
            continue;
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
        if v.from_room == v.to_room
            || v.from_cell == v.to_cell
            || v.from_cell.deck == v.to_cell.deck
            || !rooms
                .get(&v.from_room)
                .is_some_and(|cells| cells.contains(&v.from_cell))
            || !rooms
                .get(&v.to_room)
                .is_some_and(|cells| cells.contains(&v.to_cell))
            || ship
                .plan
                .occupancy
                .get(&v.from_cell.key())
                .is_none_or(|record| record.room_id != v.from_room)
            || ship
                .plan
                .occupancy
                .get(&v.to_cell.key())
                .is_none_or(|record| record.room_id != v.to_room)
        {
            return Err(ValidationError("vertical topology identity".into()));
        }
        let reference = canonical_vertical_ref(
            (v.from_cell.deck, v.from_cell.x, v.from_cell.y, v.from_room),
            (v.to_cell.deck, v.to_cell.x, v.to_cell.y, v.to_room),
        );
        if !structural_refs.insert(reference.clone()) {
            return Err(ValidationError("duplicate vertical structural ref".into()));
        }
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
    let mut nodes: Vec<_> = ship
        .topology
        .rooms
        .iter()
        .map(|room| NavigationNode { room: room.id })
        .collect();
    nodes.sort_by_key(|node| node.room);
    if nodes.windows(2).any(|pair| pair[0].room == pair[1].room) {
        return Err(ValidationError("duplicate navigation room".into()));
    }
    Ok(Navigation {
        schema_version: NAVIGATION_SCHEMA_VERSION.into(),
        nodes,
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

fn reachable_rooms(site: &SiteIR, completed: &BTreeSet<String>) -> BTreeSet<u16> {
    let mut reached = BTreeSet::from([site.ship.entry_room]);
    let mut queue = VecDeque::from([site.ship.entry_room]);
    while let Some(room) = queue.pop_front() {
        for edge in site
            .navigation
            .edges
            .iter()
            .filter(|edge| edge.from_room == room)
        {
            let open = edge.passable
                || edge.gate_id.as_ref().is_some_and(|gate_id| {
                    site.mission_graph.gates.iter().any(|gate| {
                        gate.id == *gate_id && completed.contains(&gate.prerequisite_node)
                    })
                });
            if open && reached.insert(edge.to_room) {
                queue.push_back(edge.to_room);
            }
        }
    }
    reached
}

fn required_prop<'a>(site: &'a SiteIR, node_id: &str) -> Option<&'a FunctionalProp> {
    site.functional_props
        .iter()
        .find(|prop| prop.mission_node_id == node_id)
}

/// Bounded stateful proof of mission order and physical traversal.
pub fn run_progression_agent(site: &SiteIR) -> Result<(), ValidationError> {
    let graph = &site.mission_graph;
    let mut incoming: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for edge in &graph.edges {
        incoming
            .entry(edge.to.as_str())
            .or_default()
            .push(edge.from.as_str());
    }
    let mut completed = BTreeSet::from([graph.start_node.clone()]);
    let mut next_objective = 0usize;
    let max_steps = graph.nodes.len() + graph.edges.len() + graph.gates.len() + 1;
    for _ in 0..max_steps {
        let reached = reachable_rooms(site, &completed);
        let mut changed = false;
        for mission_node in &graph.nodes {
            if completed.contains(&mission_node.id)
                || !incoming
                    .get(mission_node.id.as_str())
                    .is_some_and(|dependencies| {
                        !dependencies.is_empty()
                            && dependencies.iter().all(|id| completed.contains(*id))
                    })
                || !reached.contains(&mission_node.room)
            {
                continue;
            }
            let prop_reachable = required_prop(site, &mission_node.id)
                .is_none_or(|prop| prop.room == mission_node.room && reached.contains(&prop.room));
            if !prop_reachable {
                continue;
            }
            let permitted = match mission_node.kind {
                NodeKind::Start => false,
                NodeKind::AcquireKey | NodeKind::Repair => true,
                NodeKind::Objective => graph
                    .required_objectives
                    .get(next_objective)
                    .is_some_and(|id| id == &mission_node.id),
                NodeKind::Extraction => {
                    next_objective == graph.required_objectives.len()
                        && mission_node.id == graph.extraction_node
                }
            };
            if permitted {
                completed.insert(mission_node.id.clone());
                if mission_node.kind == NodeKind::Objective {
                    next_objective += 1;
                }
                changed = true;
            }
        }
        if completed.contains(&graph.extraction_node) {
            return Ok(());
        }
        if !changed {
            break;
        }
    }
    let missing = graph
        .required_objectives
        .iter()
        .chain(std::iter::once(&graph.extraction_node))
        .find(|id| !completed.contains(*id))
        .cloned()
        .unwrap_or_else(|| "progression".into());
    Err(ValidationError(format!(
        "progression unreachable:{missing}"
    )))
}

pub fn site_json(site: &SiteIR) -> Result<String, serde_json::Error> {
    serde_json::to_string(site)
}
pub fn site_from_json(data: &str) -> Result<SiteIR, serde_json::Error> {
    serde_json::from_str(data)
}

fn site_key(
    request: &crate::world::WorldGenerationRequest,
    channel: &str,
    sub_index: u32,
) -> Result<crate::world::WorldKey, SiteError> {
    let key = crate::world::WorldKey {
        world_seed: request.world_seed,
        platform_version: request.platform_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        site_id: request.site_id.clone(),
        x: request.x,
        y: request.y,
        domain: "site".into(),
        channel: channel.into(),
        sub_index,
    };
    key.validate()
        .map_err(|field| SiteError::Invalid(field.into()))?;
    Ok(key)
}

fn validate_request_ship(
    ship: &Ship,
    request: &crate::world::WorldGenerationRequest,
) -> Result<(), SiteError> {
    if request.platform_version != crate::world::PROCGEN_GENERATOR_VERSION
        || request.archetype_id != ship.archetype_id
        || request.x == i32::MIN
        || request.x == i32::MAX
        || request.y == i32::MIN
        || request.y == i32::MAX
        || ship.generator_version != crate::model::GENERATOR_VERSION
        || ship.critical_path.first() != Some(&ship.entry_room)
        || ship.critical_path.last() != Some(&ship.goal_room)
    {
        return Err(SiteError::Invalid("request identity".into()));
    }
    let structural_seed = site_key(request, "site.structural", 0)?
        .seed()
        .map_err(|field| SiteError::Invalid(field.into()))?;
    if ship.seed != structural_seed {
        return Err(SiteError::Invalid("ship seed identity".into()));
    }
    project_navigation(ship).map_err(|error| SiteError::Validation(error.0))?;
    Ok(())
}

pub fn validate_site_for_request(
    site: &SiteIR,
    request: &crate::world::WorldGenerationRequest,
) -> Result<(), SiteError> {
    validate_request_ship(&site.ship, request)?;
    validate_site(site).map_err(|error| SiteError::Validation(error.0))
}

fn extraction_portal_ref(ship: &Ship) -> Result<String, SiteError> {
    let portals: Vec<_> = ship
        .topology
        .portals
        .iter()
        .filter(|portal| {
            portal.from_room == ship.entry_room
                && portal.to_room == NO_ROOM
                && portal.exterior
                && portal.state == EdgeKind::Door
        })
        .collect();
    if portals.len() != 1 {
        return Err(SiteError::Invalid("entry extraction portal".into()));
    }
    let portal = portals[0];
    let direction = crate::structural::plan::Dir::between(portal.from_cell, portal.to_cell)
        .ok_or_else(|| SiteError::Invalid("entry extraction direction".into()))?;
    Ok(edge_key(portal.from_cell, direction))
}

fn room_socket_candidates(ship: &Ship, room: u16) -> Result<Vec<(Cell, Cell)>, SiteError> {
    let mut cells = ship
        .topology
        .room(room)
        .ok_or_else(|| SiteError::Invalid("socket room".into()))?
        .cells
        .clone();
    cells.sort();
    cells.dedup();
    let cell_set: BTreeSet<_> = cells.iter().copied().collect();
    let mut pairs = Vec::new();
    for anchor in cells {
        for approach in cell_set.iter().copied() {
            if anchor.deck == approach.deck
                && (anchor.x - approach.x).abs() + (anchor.y - approach.y).abs() == 1
            {
                pairs.push((anchor, approach));
            }
        }
    }
    if pairs.is_empty() {
        return Err(SiteError::Invalid("socket capacity".into()));
    }
    Ok(pairs)
}

fn allocate_socket(
    ship: &Ship,
    room: u16,
    used: &mut BTreeSet<Cell>,
    request: &crate::world::WorldGenerationRequest,
    sub_index: u32,
) -> Result<(Cell, Cell), SiteError> {
    let pairs = room_socket_candidates(ship, room)?;
    let seed = site_key(request, "site.functional_props", sub_index)?
        .seed()
        .map_err(|field| SiteError::Invalid(field.into()))?;
    let offset = (seed as usize) % pairs.len();
    for index in 0..pairs.len() {
        let (anchor, approach) = pairs[(offset + index) % pairs.len()];
        if !used.contains(&anchor) && !used.contains(&approach) {
            used.insert(anchor);
            used.insert(approach);
            return Ok((anchor, approach));
        }
    }
    Err(SiteError::Invalid("socket capacity".into()))
}

fn topology_reaches(
    navigation: &Navigation,
    entry: u16,
    goal: u16,
    blocked_refs: &BTreeSet<&str>,
) -> bool {
    let mut reached = BTreeSet::from([entry]);
    let mut queue = VecDeque::from([entry]);
    while let Some(room) = queue.pop_front() {
        for edge in navigation
            .edges
            .iter()
            .filter(|edge| edge.from_room == room)
        {
            if !blocked_refs.contains(edge.structural_ref.as_str()) && reached.insert(edge.to_room)
            {
                queue.push_back(edge.to_room);
            }
        }
    }
    reached.contains(&goal)
}

fn critical_gate_candidates(ship: &Ship, navigation: &Navigation) -> Vec<String> {
    let mut candidates = BTreeSet::new();
    for rooms in ship.critical_path.windows(2) {
        for reference in navigation
            .edges
            .iter()
            .filter(|edge| edge.from_room == rooms[0] && edge.to_room == rooms[1])
            .map(|edge| edge.structural_ref.as_str())
        {
            if !topology_reaches(
                navigation,
                ship.entry_room,
                ship.goal_room,
                &BTreeSet::from([reference]),
            ) {
                candidates.insert(reference.to_owned());
            }
        }
    }
    candidates.into_iter().collect()
}

fn bind_gate(
    navigation: &mut Navigation,
    reference: &str,
    gate_id: &str,
) -> Result<String, SiteError> {
    let matching: Vec<_> = navigation
        .edges
        .iter_mut()
        .filter(|edge| edge.structural_ref == reference)
        .collect();
    if matching.len() != 2 || matching.iter().any(|edge| edge.gate_id.is_some()) {
        return Err(SiteError::Invalid("gate edge".into()));
    }
    let navigation_edge = matching
        .iter()
        .map(|edge| edge.id.clone())
        .min()
        .ok_or_else(|| SiteError::Invalid("gate edge".into()))?;
    for edge in matching {
        edge.gate_id = Some(gate_id.into());
        edge.passable = false;
    }
    Ok(navigation_edge)
}

fn initially_reachable_rooms(navigation: &Navigation, entry: u16) -> BTreeSet<u16> {
    let mut reached = BTreeSet::from([entry]);
    let mut queue = VecDeque::from([entry]);
    while let Some(room) = queue.pop_front() {
        for edge in navigation
            .edges
            .iter()
            .filter(|edge| edge.from_room == room && edge.passable)
        {
            if reached.insert(edge.to_room) {
                queue.push_back(edge.to_room);
            }
        }
    }
    reached
}

fn build_site_candidate(
    ship: Ship,
    request: &crate::world::WorldGenerationRequest,
    template: &SiteTemplate,
) -> Result<SiteIR, SiteError> {
    let mut navigation =
        project_navigation(&ship).map_err(|error| SiteError::Validation(error.0))?;
    let locked_refs: BTreeSet<String> = navigation
        .edges
        .iter()
        .filter(|edge| !edge.passable)
        .map(|edge| edge.structural_ref.clone())
        .collect();
    if template.gate != Some(GateKind::KeyLock) && !locked_refs.is_empty() {
        return Err(SiteError::Invalid(
            "template cannot bind structural lock".into(),
        ));
    }
    let mut gate_candidates = critical_gate_candidates(&ship, &navigation);
    if template.gate.is_some() && locked_refs.is_empty() && gate_candidates.is_empty() {
        return Err(SiteError::Invalid("no non-bypassable gate edge".into()));
    }
    let gate_seed = site_key(request, "site.gate_order", 0)?
        .seed()
        .map_err(|field| SiteError::Invalid(field.into()))?;
    if !gate_candidates.is_empty() {
        let gate_len = gate_candidates.len();
        gate_candidates.rotate_left((gate_seed as usize) % gate_len);
    }

    let entry = ship.entry_room;
    let goal = ship.goal_room;
    let entry_cell = ship
        .topology
        .room(entry)
        .and_then(|room| room.cells.iter().min().copied())
        .ok_or_else(|| SiteError::Invalid("entry cell".into()))?;
    let mut gates = Vec::new();
    let (node_kind, prop_kind, key_id, repair_id) = match template.gate {
        Some(GateKind::KeyLock) => (
            Some(NodeKind::AcquireKey),
            Some(PropKind::KeyPickup),
            Some("key:site:0".to_owned()),
            None,
        ),
        Some(GateKind::Repair) => (
            Some(NodeKind::Repair),
            Some(PropKind::RepairPanel),
            None,
            Some("repair:site:0".to_owned()),
        ),
        None => (None, None, None, None),
    };
    if let Some(gate_kind) = template.gate {
        let mut refs: Vec<String> = if gate_kind == GateKind::KeyLock && !locked_refs.is_empty() {
            locked_refs.into_iter().collect()
        } else {
            vec![gate_candidates[0].clone()]
        };
        refs.sort();
        let refs_len = refs.len();
        refs.rotate_left((gate_seed as usize) % refs_len);
        for (index, reference) in refs.into_iter().enumerate() {
            let gate_id = format!("gate:{index:02}");
            let navigation_edge = bind_gate(&mut navigation, &reference, &gate_id)?;
            gates.push(MissionGate {
                id: gate_id,
                kind: gate_kind,
                navigation_edge,
                prerequisite_node: "prerequisite:0".into(),
                unlock_node: "objective:0".into(),
                key_id: key_id.clone(),
                repair_id: repair_id.clone(),
            });
        }
    }

    // Reserve endpoint props first. The prerequisite may occupy any room
    // physically reachable before its gates, so small entry rooms remain valid.
    let mut used = BTreeSet::new();
    let (extraction_anchor, extraction_approach) =
        allocate_socket(&ship, entry, &mut used, request, 2)?;
    let (objective_anchor, objective_approach) =
        allocate_socket(&ship, goal, &mut used, request, 1)?;
    let prerequisite_socket = if template.gate.is_some() {
        let reachable = initially_reachable_rooms(&navigation, entry);
        let mut room_order = ship
            .critical_path
            .iter()
            .copied()
            .filter(|room| reachable.contains(room))
            .collect::<Vec<_>>();
        room_order.extend(reachable.iter().copied());
        let mut seen = BTreeSet::new();
        room_order.retain(|room| seen.insert(*room));
        let mut selected = None;
        for room in room_order {
            let mut attempted_used = used.clone();
            if let Ok((anchor, approach)) =
                allocate_socket(&ship, room, &mut attempted_used, request, 0)
            {
                selected = Some((room, anchor, approach));
                break;
            }
        }
        Some(selected.ok_or_else(|| SiteError::Invalid("prerequisite socket".into()))?)
    } else {
        None
    };

    let mut nodes = vec![MissionNode {
        id: "start".into(),
        kind: NodeKind::Start,
        room: entry,
        cell: entry_cell,
        key_id: None,
        repair_id: None,
    }];
    let mut mission_edges = Vec::new();
    let mut functional_props = Vec::new();
    if let Some((room, anchor, approach)) = prerequisite_socket {
        nodes.push(MissionNode {
            id: "prerequisite:0".into(),
            kind: node_kind.expect("gated template has node kind"),
            room,
            cell: anchor,
            key_id: key_id.clone(),
            repair_id: repair_id.clone(),
        });
        functional_props.push(FunctionalProp {
            id: "prop:prerequisite:0".into(),
            kind: prop_kind.expect("gated template has prop kind"),
            room,
            anchor,
            approach,
            mission_node_id: "prerequisite:0".into(),
            key_id: key_id.clone(),
            repair_id: repair_id.clone(),
            extraction_portal_ref: None,
        });
        mission_edges.push(MissionEdge {
            from: "start".into(),
            to: "prerequisite:0".into(),
        });
    }
    nodes.push(MissionNode {
        id: "objective:0".into(),
        kind: NodeKind::Objective,
        room: goal,
        cell: objective_anchor,
        key_id: None,
        repair_id: None,
    });
    functional_props.push(FunctionalProp {
        id: "prop:objective:0".into(),
        kind: PropKind::ObjectiveConsole,
        room: goal,
        anchor: objective_anchor,
        approach: objective_approach,
        mission_node_id: "objective:0".into(),
        key_id: None,
        repair_id: None,
        extraction_portal_ref: None,
    });
    mission_edges.push(MissionEdge {
        from: if template.gate.is_some() {
            "prerequisite:0".into()
        } else {
            "start".into()
        },
        to: "objective:0".into(),
    });
    nodes.push(MissionNode {
        id: "extraction".into(),
        kind: NodeKind::Extraction,
        room: entry,
        cell: extraction_anchor,
        key_id: None,
        repair_id: None,
    });
    functional_props.push(FunctionalProp {
        id: "prop:extraction".into(),
        kind: PropKind::ExtractionConsole,
        room: entry,
        anchor: extraction_anchor,
        approach: extraction_approach,
        mission_node_id: "extraction".into(),
        key_id: None,
        repair_id: None,
        extraction_portal_ref: Some(extraction_portal_ref(&ship)?),
    });
    mission_edges.push(MissionEdge {
        from: "objective:0".into(),
        to: "extraction".into(),
    });

    let _spatial_seed = site_key(request, "site.spatial_annotations", 0)?
        .seed()
        .map_err(|field| SiteError::Invalid(field.into()))?;
    let spatial_annotations =
        compute_spatial(&ship).map_err(|error| SiteError::Validation(error.0))?;
    Ok(SiteIR {
        schema_version: SITE_SCHEMA_VERSION.into(),
        ship,
        mission_graph: MissionGraph {
            schema_version: MISSION_SCHEMA_VERSION.into(),
            mission_id: template.id.clone(),
            start_node: "start".into(),
            required_objectives: vec!["objective:0".into()],
            extraction_node: "extraction".into(),
            nodes,
            edges: mission_edges,
            gates,
        },
        navigation,
        functional_props,
        spatial_annotations,
    })
}

fn prop_socket_valid(site: &SiteIR, index: usize) -> bool {
    let prop = &site.functional_props[index];
    let room = match site.ship.topology.room(prop.room) {
        Some(room) => room,
        None => return false,
    };
    let occupied_elsewhere: BTreeSet<_> = site
        .functional_props
        .iter()
        .enumerate()
        .filter(|(other, _)| *other != index)
        .flat_map(|(_, other)| [other.anchor, other.approach])
        .collect();
    prop.anchor.deck == prop.approach.deck
        && (prop.anchor.x - prop.approach.x).abs() + (prop.anchor.y - prop.approach.y).abs() == 1
        && room.cells.contains(&prop.anchor)
        && room.cells.contains(&prop.approach)
        && !occupied_elsewhere.contains(&prop.anchor)
        && !occupied_elsewhere.contains(&prop.approach)
}

fn repair_one_prop(
    site: &mut SiteIR,
    request: &crate::world::WorldGenerationRequest,
) -> Result<bool, SiteError> {
    let Some(index) =
        (0..site.functional_props.len()).find(|index| !prop_socket_valid(site, *index))
    else {
        return Ok(false);
    };
    let room = site.functional_props[index].room;
    let mut used: BTreeSet<_> = site
        .functional_props
        .iter()
        .enumerate()
        .filter(|(other, _)| *other != index)
        .flat_map(|(_, other)| [other.anchor, other.approach])
        .collect();
    let (anchor, approach) = allocate_socket(&site.ship, room, &mut used, request, index as u32)?;
    let node_id = site.functional_props[index].mission_node_id.clone();
    site.functional_props[index].anchor = anchor;
    site.functional_props[index].approach = approach;
    if let Some(mission_node) = site
        .mission_graph
        .nodes
        .iter_mut()
        .find(|mission_node| mission_node.id == node_id)
    {
        mission_node.cell = anchor;
    }
    Ok(true)
}

fn repair_one_gate(site: &mut SiteIR) -> Result<bool, SiteError> {
    let projected =
        project_navigation(&site.ship).map_err(|error| SiteError::Validation(error.0))?;
    let broken = site.mission_graph.gates.iter().position(|gate| {
        let bound: Vec<_> = site
            .navigation
            .edges
            .iter()
            .filter(|edge| edge.gate_id.as_deref() == Some(gate.id.as_str()))
            .collect();
        bound.len() != 2
            || bound[0].structural_ref != bound[1].structural_ref
            || !bound.iter().any(|edge| edge.id == gate.navigation_edge)
    });
    let Some(index) = broken else {
        return Ok(false);
    };
    let gate_id = site.mission_graph.gates[index].id.clone();
    for edge in &mut site.navigation.edges {
        if edge.gate_id.as_deref() == Some(gate_id.as_str()) {
            if let Some(expected) = projected
                .edges
                .iter()
                .find(|expected| expected.id == edge.id)
            {
                edge.gate_id = None;
                edge.passable = expected.passable;
            }
        }
    }
    let occupied_refs: BTreeSet<_> = site
        .navigation
        .edges
        .iter()
        .filter(|edge| edge.gate_id.is_some())
        .map(|edge| edge.structural_ref.as_str())
        .collect();
    let candidates = critical_gate_candidates(&site.ship, &projected);
    let reference = candidates
        .iter()
        .find(|reference| !occupied_refs.contains(reference.as_str()))
        .ok_or_else(|| SiteError::Validation("gate repair unavailable".into()))?;
    let navigation_edge = bind_gate(&mut site.navigation, reference, &gate_id)?;
    site.mission_graph.gates[index].navigation_edge = navigation_edge;
    Ok(true)
}

pub fn fallback_return_path(site: &SiteIR) -> Vec<u16> {
    site.ship.critical_path.iter().rev().copied().collect()
}

fn build_fallback(
    ship: Ship,
    request: &crate::world::WorldGenerationRequest,
) -> Result<SiteIR, SiteError> {
    let fallback = SiteFallback::bundled()?;
    fallback.validate()?;
    let mut site = build_site_candidate(
        ship,
        request,
        &SiteTemplate {
            id: fallback.mission_id,
            archetypes: vec![request.archetype_id.clone()],
            gate: None,
        },
    )?;
    if fallback_return_path(&site)
        != site
            .ship
            .critical_path
            .iter()
            .rev()
            .copied()
            .collect::<Vec<_>>()
    {
        return Err(SiteError::Validation("fallback return path".into()));
    }
    site.mission_graph.mission_id = "authored-safe-return".into();
    Ok(site)
}

fn resolve_site_candidate_with_trace(
    mut candidate: SiteIR,
    request: &crate::world::WorldGenerationRequest,
    candidate_decisions: Vec<String>,
) -> Result<SiteGenerationOutcome, SiteError> {
    validate_request_ship(&candidate.ship, request)?;
    let original_ship = candidate.ship.clone();
    let mut repairs = Vec::new();
    let mut validation = validate_site(&candidate);
    if validation.is_err() && repair_one_prop(&mut candidate, request)? {
        repairs.push("relocate_required_prop".into());
        validation = validate_site(&candidate);
    }
    if validation.is_err() && repairs.len() < 2 && repair_one_gate(&mut candidate)? {
        repairs.push("replace_gate_binding".into());
        validation = validate_site(&candidate);
    }
    if validation.is_ok() {
        return Ok(SiteGenerationOutcome {
            site: candidate,
            trace: SiteTrace {
                candidate_decisions,
                repairs,
                fallback: None,
            },
        });
    }
    let fallback = build_fallback(original_ship, request)?;
    validate_site_for_request(&fallback, request)?;
    let candidate_decisions = fallback_candidate_decisions(candidate_decisions);
    Ok(SiteGenerationOutcome {
        site: fallback,
        trace: SiteTrace {
            candidate_decisions,
            repairs,
            fallback: Some("authored-safe-return".into()),
        },
    })
}

fn fallback_candidate_decisions(mut decisions: Vec<String>) -> Vec<String> {
    decisions
        .retain(|decision| decision != "rejected_candidate" && decision != "selected_fallback");
    decisions.truncate(MAX_SITE_DECISIONS.saturating_sub(2));
    decisions.push("rejected_candidate".into());
    decisions.push("selected_fallback".into());
    decisions
}

pub fn resolve_site_candidate(
    candidate: SiteIR,
    request: &crate::world::WorldGenerationRequest,
) -> Result<SiteGenerationOutcome, SiteError> {
    resolve_site_candidate_with_trace(candidate, request, Vec::new())
}

/// Compile one deterministic overlay. Structural generation is never rerun.
pub fn generate_site(
    ship: Ship,
    request: &crate::world::WorldGenerationRequest,
) -> Result<SiteGenerationOutcome, SiteError> {
    validate_request_ship(&ship, request)?;
    let rules = SiteRules::bundled()?;
    rules.validate()?;
    let template_seed = site_key(request, "site.mission_template", 0)?
        .seed()
        .map_err(|field| SiteError::Invalid(field.into()))?;
    let mut compatible: Vec<_> = rules
        .templates
        .iter()
        .filter(|template| template.archetypes.contains(&request.archetype_id))
        .cloned()
        .collect();
    if compatible.is_empty() {
        return Err(SiteError::Rules("no compatible template".into()));
    }
    compatible.sort_by(|left, right| left.id.cmp(&right.id));
    let compatible_len = compatible.len();
    compatible.rotate_left((template_seed as usize) % compatible_len);
    let mut decisions = SITE_RNG_CHANNELS
        .iter()
        .enumerate()
        .map(|(index, channel)| {
            let seed = site_key(request, channel, index as u32)
                .and_then(|key| key.seed().map_err(|field| SiteError::Invalid(field.into())))
                .unwrap_or_default();
            format!("channel:{channel}:{seed}")
        })
        .collect::<Vec<_>>();
    for template in compatible {
        match build_site_candidate(ship.clone(), request, &template) {
            Ok(candidate) => {
                decisions.push(format!("template:{}:selected", template.id));
                decisions.truncate(MAX_SITE_DECISIONS);
                return resolve_site_candidate_with_trace(candidate, request, decisions);
            }
            Err(error) => {
                decisions.push(format!("template:{}:rejected:{error}", template.id));
            }
        }
    }
    let decisions = fallback_candidate_decisions(decisions);
    let fallback = build_fallback(ship, request)?;
    validate_site_for_request(&fallback, request)?;
    Ok(SiteGenerationOutcome {
        site: fallback,
        trace: SiteTrace {
            candidate_decisions: decisions,
            repairs: Vec::new(),
            fallback: Some("authored-safe-return".into()),
        },
    })
}
