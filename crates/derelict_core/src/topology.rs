//! Authored semantic topology: template definitions (zones, role pools,
//! connections) and the zone-tree placement engine that turns a template +
//! hull masks into rooms with explicit occupancy and authored portals.
//!
//! Ported from The Synaptic Sea's TopologyTemplate / RoomAssigner /
//! CellLayoutEngine designs, with the fail-open paths made fail-closed:
//! guaranteed roles are enforced structurally (template compatibility is
//! checked at load; unsatisfiable data cannot load), and any placement or
//! connection failure is a typed error feeding the pipeline's bounded
//! retry — never a best-effort layout.

use crate::rng::{roll_range, weighted_choice};
use crate::role::Role;
use crate::stages::hull::Mask;
use crate::structural::plan::{
    Cell, Dir, EdgeKind, PortalIntent, RoomId, RoomSpec, Topology, VerticalConnection, NO_ROOM,
};
use rand_pcg::Pcg64;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

// ---------------------------------------------------------------------------
// Template data model (RON-authored)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum CountSpec {
    Fixed(u8),
    Range(u8, u8),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum PositionHint {
    Bow,
    Stern,
    Lateral,
    Center,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum ZoneLayout {
    Single,
    Clustered,
    Linear,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum Distribution {
    Adjacent,
    Spread,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ZoneDef {
    pub id: String,
    pub role_pool: Vec<Role>,
    pub count: CountSpec,
    pub position_hint: PositionHint,
    pub deck: u8,
    pub layout: ZoneLayout,
    /// Parent zone id; "" = root.
    pub attach_to: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ConnectionDef {
    pub from_zone: String,
    pub to_zone: String,
    pub distribution: Distribution,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct DeckConfig {
    pub max_decks: u8,
    pub vertical_transition_bp: u16,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TemplateDef {
    pub id: String,
    pub description: String,
    pub zones: Vec<ZoneDef>,
    pub connections: Vec<ConnectionDef>,
    pub deck_config: DeckConfig,
}

impl TemplateDef {
    pub fn zone(&self, id: &str) -> Option<&ZoneDef> {
        self.zones.iter().find(|z| z.id == id)
    }

    /// Highest deck index any zone uses (0-based).
    pub fn max_zone_deck(&self) -> u8 {
        self.zones.iter().map(|z| z.deck).max().unwrap_or(0)
    }

    /// Minimum cells this template needs: per zone, min room count times the
    /// smallest footprint of the cheapest role in its pool.
    pub fn min_cell_need(&self) -> u32 {
        self.zones
            .iter()
            .map(|z| {
                let count = match z.count {
                    CountSpec::Fixed(n) => n as u32,
                    CountSpec::Range(a, _) => a as u32,
                };
                let cheapest = z
                    .role_pool
                    .iter()
                    .map(|r| {
                        footprint_options(*r)
                            .iter()
                            .map(|(w, h)| (w * h) as u32)
                            .min()
                            .unwrap_or(4)
                    })
                    .min()
                    .unwrap_or(4);
                count * cheapest
            })
            .sum()
    }

    /// Can this template satisfy every guaranteed role (some zone's pool
    /// contains it)?
    pub fn can_satisfy(&self, guaranteed: &[Role]) -> bool {
        guaranteed
            .iter()
            .all(|g| self.zones.iter().any(|z| z.role_pool.contains(g)))
    }

    /// Structural sanity, checked at load: unique zone ids, resolvable
    /// attach_to/connection refs, non-empty pools, acyclic zone tree.
    pub fn validate(&self) -> Result<(), String> {
        let mut ids = BTreeSet::new();
        for z in &self.zones {
            if !ids.insert(z.id.as_str()) {
                return Err(format!("template {}: duplicate zone '{}'", self.id, z.id));
            }
            if z.role_pool.is_empty() {
                return Err(format!(
                    "template {}: zone '{}' has empty role pool",
                    self.id, z.id
                ));
            }
        }
        for z in &self.zones {
            if !z.attach_to.is_empty() && !ids.contains(z.attach_to.as_str()) {
                return Err(format!(
                    "template {}: zone '{}' attaches to unknown '{}'",
                    self.id, z.id, z.attach_to
                ));
            }
        }
        for c in &self.connections {
            if !ids.contains(c.from_zone.as_str()) || !ids.contains(c.to_zone.as_str()) {
                return Err(format!(
                    "template {}: connection {} -> {} references unknown zone",
                    self.id, c.from_zone, c.to_zone
                ));
            }
        }
        // Zone tree must be acyclic and rooted.
        for z in &self.zones {
            let mut cur = z;
            let mut hops = 0;
            while !cur.attach_to.is_empty() {
                cur = self.zone(&cur.attach_to).unwrap();
                hops += 1;
                if hops > self.zones.len() {
                    return Err(format!(
                        "template {}: attach_to cycle at '{}'",
                        self.id, z.id
                    ));
                }
            }
        }
        Ok(())
    }
}

const DEFAULT_TEMPLATES: &[&str] = &[
    include_str!("../assets/topology_templates/spine.ron"),
    include_str!("../assets/topology_templates/bifurcated.ron"),
    include_str!("../assets/topology_templates/compact.ron"),
    include_str!("../assets/topology_templates/dispersed.ron"),
    include_str!("../assets/topology_templates/double_spine.ron"),
    include_str!("../assets/topology_templates/radial.ron"),
    include_str!("../assets/topology_templates/ring.ron"),
    include_str!("../assets/topology_templates/vault.ron"),
    include_str!("../assets/topology_templates/hangar_wing.ron"),
    include_str!("../assets/topology_templates/derelict_a.ron"),
    include_str!("../assets/topology_templates/derelict_b.ron"),
    include_str!("../assets/topology_templates/stacked.ron"),
    include_str!("../assets/topology_templates/stacked_v2.ron"),
];

#[derive(Clone, Debug)]
pub struct TemplateSet {
    pub templates: BTreeMap<String, TemplateDef>,
}

impl TemplateSet {
    pub fn default_bundle() -> Result<Self, String> {
        let mut templates = BTreeMap::new();
        for src in DEFAULT_TEMPLATES {
            let t: TemplateDef = ron::from_str(src).map_err(|e| format!("template parse: {e}"))?;
            t.validate()?;
            templates.insert(t.id.clone(), t);
        }
        Ok(Self { templates })
    }

    /// Templates that can satisfy the guarantees and fit the deck count.
    pub fn compatible(&self, guaranteed: &[Role], deck_count: u8) -> Vec<&TemplateDef> {
        self.templates
            .values()
            .filter(|t| t.can_satisfy(guaranteed) && t.max_zone_deck() < deck_count)
            .collect()
    }
}

// ---------------------------------------------------------------------------
// Role parameters (from the archetype)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Default)]
pub struct RoleParams {
    pub weights: BTreeMap<Role, u32>,
    pub guaranteed: Vec<Role>,
    /// 0 = unlimited.
    pub max_duplicates: u8,
}

/// Per-role footprint options (w, h) in cells, tried in listed order.
/// Ported in spirit from RoomAssigner.ROOM_FOOTPRINT_OPTIONS at the 4 m
/// module-grid scale.
pub fn footprint_options(role: Role) -> &'static [(i32, i32)] {
    match role {
        Role::Airlock => &[(2, 2), (2, 1), (1, 2)],
        Role::Dock => &[(2, 2), (3, 2), (2, 3)],
        Role::Corridor => &[
            (3, 1),
            (1, 3),
            (4, 1),
            (1, 4),
            (2, 1),
            (1, 2),
            (5, 1),
            (1, 5),
        ],
        Role::MainSpine => &[(5, 1), (1, 5), (6, 1), (1, 6), (4, 1), (1, 4)],
        Role::Hub => &[(2, 2), (3, 3), (3, 2), (2, 3)],
        Role::Ramp => &[(2, 1), (1, 2), (2, 2)],
        Role::Elevator => &[(1, 1), (2, 1), (1, 2)],
        Role::Bridge => &[(3, 2), (2, 3), (2, 2), (3, 3)],
        Role::Engineering => &[(3, 3), (3, 2), (2, 3)],
        Role::Reactor => &[(3, 3), (2, 3), (3, 2)],
        Role::LifeSupport => &[(2, 2), (2, 3), (3, 2)],
        Role::Maintenance => &[(2, 2), (1, 2), (2, 1)],
        Role::Cargo => &[(3, 3), (4, 3), (3, 4), (2, 3), (3, 2)],
        Role::Hangar => &[(4, 3), (3, 4), (4, 4), (3, 3)],
        Role::Storage => &[(2, 2), (3, 2), (2, 3)],
        Role::Armory => &[(2, 2), (3, 2), (2, 3)],
        Role::Security => &[(2, 2), (2, 1)],
        Role::Medical => &[(2, 2), (3, 2), (2, 3)],
        Role::CrewQuarters => &[(3, 2), (2, 3), (2, 2), (3, 3)],
        Role::MessHall => &[(3, 2), (2, 3), (2, 2)],
        Role::Compartment => &[(2, 2), (2, 3), (3, 2)],
    }
}

// ---------------------------------------------------------------------------
// Placement
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub enum TopoError {
    ZonePlacementFailed {
        zone: String,
        detail: String,
    },
    ConnectionFailed {
        from: RoomId,
        to: RoomId,
        detail: String,
    },
    GuaranteeUnsatisfied {
        role: Role,
    },
    HazardAdjacency {
        a: RoomId,
        b: RoomId,
    },
    GoalUnreachable,
}

impl std::fmt::Display for TopoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TopoError::ZonePlacementFailed { zone, detail } => {
                write!(f, "zone '{zone}' placement failed: {detail}")
            }
            TopoError::ConnectionFailed { from, to, detail } => {
                write!(f, "connection {from} -> {to} failed: {detail}")
            }
            TopoError::GuaranteeUnsatisfied { role } => {
                write!(f, "guaranteed role {role:?} unsatisfied")
            }
            TopoError::HazardAdjacency { a, b } => {
                write!(f, "hazardous/comfort adjacency between rooms {a} and {b}")
            }
            TopoError::GoalUnreachable => write!(f, "goal room unreachable from entry"),
        }
    }
}

impl std::error::Error for TopoError {}

#[derive(Clone, Debug)]
pub struct PlacedTopology {
    pub topology: Topology,
    pub zone_of_room: BTreeMap<RoomId, String>,
    pub entry_room: RoomId,
    pub goal_room: RoomId,
    pub critical_path: Vec<RoomId>,
    pub room_links: Vec<(RoomId, RoomId)>,
}

struct PlannedRoom {
    id: RoomId,
    zone_index: usize,
    role: Role,
}

/// Occupancy tracker during placement.
struct Grid<'a> {
    masks: &'a [Mask],
    owner: Vec<BTreeMap<(i32, i32), RoomId>>, // per deck
}

impl<'a> Grid<'a> {
    fn new(masks: &'a [Mask]) -> Self {
        Self {
            masks,
            owner: vec![BTreeMap::new(); masks.len()],
        }
    }
    fn in_hull(&self, deck: u8, x: i32, y: i32) -> bool {
        self.masks
            .get(deck as usize)
            .map(|m| m.get(x, y))
            .unwrap_or(false)
    }
    fn free(&self, deck: u8, x: i32, y: i32) -> bool {
        self.in_hull(deck, x, y) && !self.owner[deck as usize].contains_key(&(x, y))
    }
    fn owner_at(&self, deck: u8, x: i32, y: i32) -> RoomId {
        self.owner
            .get(deck as usize)
            .and_then(|m| m.get(&(x, y)).copied())
            .unwrap_or(NO_ROOM)
    }
    fn claim(&mut self, deck: u8, cells: &[(i32, i32)], id: RoomId) {
        for &(x, y) in cells {
            self.owner[deck as usize].insert((x, y), id);
        }
    }
}

pub fn place_topology(
    rng: &mut Pcg64,
    template: &TemplateDef,
    masks: &[Mask],
    params: &RoleParams,
) -> Result<PlacedTopology, TopoError> {
    // --- 1. Expand zones into a room plan (zone file order = room order) ---
    // Budget-aware: extra rooms (beyond a zone's minimum) are only planned
    // while the remaining hull area still covers the minimum needs of every
    // later zone — so the last zones (often the goal) always fit.
    let hull_budget: i64 = masks.iter().map(|m| m.count() as i64).sum::<i64>() * 9 / 10;
    let min_need_of = |zone: &ZoneDef| -> i64 {
        let count = match zone.count {
            CountSpec::Fixed(n) => n as i64,
            CountSpec::Range(a, _) => a as i64,
        };
        let cheapest = zone
            .role_pool
            .iter()
            .map(|r| {
                footprint_options(*r)
                    .iter()
                    .map(|(w, h)| (w * h) as i64)
                    .min()
                    .unwrap_or(4)
            })
            .min()
            .unwrap_or(4);
        count * cheapest
    };
    let suffix_need: Vec<i64> = {
        let mut v = vec![0i64; template.zones.len() + 1];
        for i in (0..template.zones.len()).rev() {
            v[i] = v[i + 1] + min_need_of(&template.zones[i]);
        }
        v
    };
    let mut allocated: i64 = 0;
    let mut plan: Vec<PlannedRoom> = Vec::new();
    let mut role_counter: BTreeMap<Role, u32> = BTreeMap::new();
    let mut next_id: RoomId = 1;
    for (zi, zone) in template.zones.iter().enumerate() {
        if zone.deck as usize >= masks.len() {
            return Err(TopoError::ZonePlacementFailed {
                zone: zone.id.clone(),
                detail: format!("zone deck {} but hull has {} decks", zone.deck, masks.len()),
            });
        }
        let avg_room = zone
            .role_pool
            .iter()
            .map(|r| {
                footprint_options(*r)
                    .first()
                    .map(|(w, h)| (w * h) as i64)
                    .unwrap_or(6)
            })
            .max()
            .unwrap_or(6);
        let count = match zone.count {
            CountSpec::Fixed(n) => n as i64,
            CountSpec::Range(a, b) => {
                let rolled = roll_range(rng, a as i64, b as i64);
                // Trim extras that would eat later zones' reserved minimums.
                let mut allowed = a as i64;
                while allowed < rolled
                    && allocated + (allowed + 1) * avg_room + suffix_need[zi + 1] <= hull_budget
                {
                    allowed += 1;
                }
                allowed
            }
        };
        allocated += count * avg_room;
        for _ in 0..count {
            let role = pick_role(rng, &zone.role_pool, params, &mut role_counter);
            plan.push(PlannedRoom {
                id: next_id,
                zone_index: zi,
                role,
            });
            next_id += 1;
        }
    }
    if plan.is_empty() {
        return Err(TopoError::ZonePlacementFailed {
            zone: "<template>".into(),
            detail: "no rooms planned".into(),
        });
    }

    // --- 2. Guarantee enforcement (fail-closed) ----------------------------
    for &wanted in &params.guaranteed {
        if plan.iter().any(|r| r.role == wanted) {
            continue;
        }
        // Replace a room whose zone pool allows the wanted role. Zones with
        // a single-role pool are authored intent (entry airlock, bridge) and
        // never repurposed; multi-role pools anywhere — including the goal
        // zone (e.g. spine's engine_room) — are fair game.
        let candidate = (0..plan.len()).find(|&i| {
            let z = &template.zones[plan[i].zone_index];
            z.role_pool.len() > 1
                && z.role_pool.contains(&wanted)
                && !params.guaranteed.contains(&plan[i].role)
        });
        match candidate {
            Some(i) => plan[i].role = wanted,
            None => return Err(TopoError::GuaranteeUnsatisfied { role: wanted }),
        }
    }

    // --- 3. Zone placement order: BFS over the attach_to tree --------------
    let zone_order = zone_bfs_order(template);

    // --- 4. Place rooms -----------------------------------------------------
    let mut grid = Grid::new(masks);
    let mut cells_of: BTreeMap<RoomId, Vec<(i32, i32)>> = BTreeMap::new();
    let mut deck_of: BTreeMap<RoomId, u8> = BTreeMap::new();
    let mut role_of: BTreeMap<RoomId, Role> = BTreeMap::new();
    for r in &plan {
        role_of.insert(r.id, r.role);
    }
    let bbox = hull_bbox(&masks[0]);

    let mut dropped: BTreeSet<RoomId> = BTreeSet::new();
    for &zi in &zone_order {
        let zone = &template.zones[zi];
        let zone_min = match zone.count {
            CountSpec::Fixed(n) => n as usize,
            CountSpec::Range(a, _) => a as usize,
        };
        let rooms: Vec<&PlannedRoom> = plan.iter().filter(|r| r.zone_index == zi).collect();
        let mut placed_in_zone = 0usize;
        let mut prev_in_zone: Option<RoomId> = None;
        for room in rooms {
            // Anchors: parent-zone rooms, rooms of already-placed zones this
            // zone is connected to (cross-deck connections need vertical
            // overlap, which the anchor scoring enforces), and for
            // clustered/linear zones the previous room in this zone.
            let mut anchors: Vec<RoomId> = Vec::new();
            if let Some(parent) = template.zones.iter().position(|z| z.id == zone.attach_to) {
                anchors.extend(plan.iter().filter(|r| r.zone_index == parent).map(|r| r.id));
            }
            for conn in &template.connections {
                let other = if conn.from_zone == zone.id {
                    &conn.to_zone
                } else if conn.to_zone == zone.id {
                    &conn.from_zone
                } else {
                    continue;
                };
                if let Some(oi) = template.zones.iter().position(|z| &z.id == other) {
                    anchors.extend(
                        plan.iter()
                            .filter(|r| r.zone_index == oi && cells_of.contains_key(&r.id))
                            .map(|r| r.id),
                    );
                }
            }
            if matches!(zone.layout, ZoneLayout::Clustered | ZoneLayout::Linear) {
                if let Some(p) = prev_in_zone {
                    anchors.push(p);
                }
            }
            anchors.sort();
            anchors.dedup();
            let placement = place_room(
                rng, &grid, zone, room.role, &anchors, &cells_of, &deck_of, &role_of, bbox,
            );
            let Some(placed) = placement else {
                // Rooms beyond the zone's minimum count are droppable when
                // space runs out — unless they carry a guaranteed role with
                // no other holder.
                let sole_guarantee = params.guaranteed.contains(&room.role)
                    && !plan.iter().any(|r| {
                        r.id != room.id && r.role == room.role && !dropped.contains(&r.id)
                    });
                if placed_in_zone >= zone_min && !sole_guarantee {
                    dropped.insert(room.id);
                    continue;
                }
                return Err(TopoError::ZonePlacementFailed {
                    zone: zone.id.clone(),
                    detail: format!("no viable footprint for {:?} room {}", room.role, room.id),
                });
            };
            grid.claim(zone.deck, &placed, room.id);
            cells_of.insert(room.id, placed);
            deck_of.insert(room.id, zone.deck);
            prev_in_zone = Some(room.id);
            placed_in_zone += 1;
        }
    }
    plan.retain(|r| !dropped.contains(&r.id));

    // --- 5. Realize connections as portals / connectors / verticals --------
    let mut portals: Vec<PortalIntent> = Vec::new();
    let mut verticals: Vec<VerticalConnection> = Vec::new();
    let mut links: Vec<(RoomId, RoomId)> = Vec::new();
    let mut connector_rooms: Vec<RoomSpec> = Vec::new();

    let mut pairs: Vec<(RoomId, RoomId)> = Vec::new();
    // Explicit connections.
    for conn in &template.connections {
        let from_rooms: Vec<RoomId> = rooms_of_zone(template, &plan, &conn.from_zone);
        let to_rooms: Vec<RoomId> = rooms_of_zone(template, &plan, &conn.to_zone);
        if from_rooms.is_empty() || to_rooms.is_empty() {
            continue;
        }
        match conn.distribution {
            Distribution::Adjacent => {
                // Single best pair (closest).
                let pair = closest_pair(&from_rooms, &to_rooms, &cells_of, &deck_of);
                pairs.push(pair);
            }
            Distribution::Spread => {
                // Every `to` room links to its nearest `from` room.
                for &t in &to_rooms {
                    let pair = closest_pair(&from_rooms, &[t], &cells_of, &deck_of);
                    pairs.push(pair);
                }
            }
        }
    }
    // Implicit attach_to links not already covered.
    for zone in &template.zones {
        if zone.attach_to.is_empty() {
            continue;
        }
        let covered = template.connections.iter().any(|c| {
            (c.from_zone == zone.attach_to && c.to_zone == zone.id)
                || (c.to_zone == zone.attach_to && c.from_zone == zone.id)
        });
        if covered {
            continue;
        }
        let parents = rooms_of_zone(template, &plan, &zone.attach_to);
        let children = rooms_of_zone(template, &plan, &zone.id);
        for &c in &children {
            if parents.is_empty() {
                continue;
            }
            pairs.push(closest_pair(&parents, &[c], &cells_of, &deck_of));
        }
    }
    // Intra-zone chains for clustered/linear zones.
    for (zi, zone) in template.zones.iter().enumerate() {
        if matches!(zone.layout, ZoneLayout::Clustered | ZoneLayout::Linear) {
            let ids: Vec<RoomId> = plan
                .iter()
                .filter(|r| r.zone_index == zi)
                .map(|r| r.id)
                .collect();
            for w in ids.windows(2) {
                pairs.push((w[0], w[1]));
            }
        }
    }
    pairs.sort();
    pairs.dedup();

    let mut next_connector_id = next_id;
    // Cross-deck pairs with no vertical overlap are deferred: they are
    // acceptable as long as the two rooms end up connected through the rest
    // of the authored graph (e.g. elevator -> corridor -> ramp -> hub).
    let mut deferred: Vec<(RoomId, RoomId)> = Vec::new();
    for (a, b) in pairs {
        if links.contains(&(a, b)) || links.contains(&(b, a)) {
            continue;
        }
        let (da, db) = (deck_of[&a], deck_of[&b]);
        if da != db {
            // Vertical connection: needs an (x,y) shared by both rooms.
            let sa: BTreeSet<(i32, i32)> = cells_of[&a].iter().copied().collect();
            let shared = cells_of[&b].iter().find(|c| sa.contains(c));
            match shared {
                Some(&(x, y)) => {
                    verticals.push(VerticalConnection {
                        from_room: a,
                        to_room: b,
                        from_cell: Cell::new(da, x, y),
                        to_cell: Cell::new(db, x, y),
                    });
                    links.push((a, b));
                }
                None => deferred.push((a, b)),
            }
            continue;
        }
        // Same deck: shared boundary → portal, else carve a connector.
        if let Some((ca, cb)) = shared_boundary(&cells_of[&a], &cells_of[&b]) {
            portals.push(PortalIntent {
                from_room: a,
                to_room: b,
                from_cell: Cell::new(da, ca.0, ca.1),
                to_cell: Cell::new(da, cb.0, cb.1),
                state: EdgeKind::Door,
                exterior: false,
            });
            links.push((a, b));
        } else {
            // Route through any mix of free cells (which become connector
            // corridors) and existing rooms (which get pass-through doors).
            route_connection(
                &mut grid,
                da,
                a,
                b,
                &mut cells_of,
                &mut deck_of,
                &mut role_of,
                &mut portals,
                &mut links,
                &mut connector_rooms,
                &mut next_connector_id,
            )
            .ok_or_else(|| TopoError::ConnectionFailed {
                from: a,
                to: b,
                detail: "no route through free cells or rooms".into(),
            })?;
        }
    }

    // Deferred cross-deck pairs must be reachable through the built graph.
    links.sort();
    links.dedup();
    for (a, b) in deferred {
        if bfs_room_path(a, b, &links).is_none() {
            return Err(TopoError::ConnectionFailed {
                from: a,
                to: b,
                detail: "no vertical overlap and no indirect route".into(),
            });
        }
    }

    // --- 6. Hazard/comfort adjacency (post-roll defense in depth) ----------
    for (&id_a, cells_a) in &cells_of {
        let ra = role_of[&id_a];
        if !ra.is_hazardous() {
            continue;
        }
        let deck = deck_of[&id_a];
        for &(x, y) in cells_a {
            for dir in Dir::ALL {
                let (dx, dy) = dir.delta();
                let other = grid.owner_at(deck, x + dx, y + dy);
                if other != NO_ROOM && other != id_a {
                    let rb = role_of[&other];
                    if rb.is_crew_comfort() {
                        return Err(TopoError::HazardAdjacency { a: id_a, b: other });
                    }
                }
            }
        }
    }

    // --- 7. Entry exterior door + critical path ----------------------------
    let entry_room = plan.first().unwrap().id;
    let goal_room = plan.last().unwrap().id;
    if let Some((cell, dir)) =
        hull_boundary_edge(&grid, deck_of[&entry_room], &cells_of[&entry_room])
    {
        let n = cell.neighbor(dir);
        portals.push(PortalIntent {
            from_room: entry_room,
            to_room: NO_ROOM,
            from_cell: cell,
            to_cell: n,
            state: EdgeKind::Door,
            exterior: true,
        });
    }

    links.sort();
    links.dedup();
    let critical_path =
        bfs_room_path(entry_room, goal_room, &links).ok_or(TopoError::GoalUnreachable)?;

    // --- 8. Assemble ---------------------------------------------------------
    let mut rooms: Vec<RoomSpec> = plan
        .iter()
        .map(|r| RoomSpec {
            id: r.id,
            role: r.role,
            deck: template.zones[r.zone_index].deck,
            cells: cells_of[&r.id]
                .iter()
                .map(|&(x, y)| Cell::new(template.zones[r.zone_index].deck, x, y))
                .collect(),
        })
        .collect();
    rooms.extend(connector_rooms);
    let zone_of_room: BTreeMap<RoomId, String> = plan
        .iter()
        .map(|r| (r.id, template.zones[r.zone_index].id.clone()))
        .collect();

    Ok(PlacedTopology {
        topology: Topology {
            rooms,
            portals,
            verticals,
        },
        zone_of_room,
        entry_room,
        goal_room,
        critical_path,
        room_links: links,
    })
}

// ---------------------------------------------------------------------------
// Residual fill
// ---------------------------------------------------------------------------

/// Fill unclaimed hull cells with filler rooms (storage/compartments...)
/// after template placement. Components adjacent to existing rooms get a
/// door; upper-deck components with vertical overlap onto a room below get
/// a ladder connection. Unreachable pockets stay void (never sealed rooms).
pub fn residual_fill(
    rng: &mut Pcg64,
    placed: &mut PlacedTopology,
    masks: &[Mask],
    filler_roles: &[(Role, u32)],
) {
    if filler_roles.is_empty() {
        return;
    }
    let mut next_id: RoomId = placed
        .topology
        .rooms
        .iter()
        .map(|r| r.id)
        .max()
        .unwrap_or(0)
        + 1;
    let mut owner: BTreeMap<(u8, i32, i32), RoomId> = BTreeMap::new();
    let mut role_of: BTreeMap<RoomId, Role> = BTreeMap::new();
    for room in &placed.topology.rooms {
        role_of.insert(room.id, room.role);
        for c in &room.cells {
            owner.insert((c.deck, c.x, c.y), room.id);
        }
    }
    let weights: Vec<u32> = filler_roles.iter().map(|(_, w)| *w).collect();

    for (d, mask) in masks.iter().enumerate() {
        let deck = d as u8;
        let mut free: BTreeSet<(i32, i32)> = BTreeSet::new();
        for y in 0..mask.height as i32 {
            for x in 0..mask.width as i32 {
                if mask.get(x, y) && !owner.contains_key(&(deck, x, y)) {
                    free.insert((x, y));
                }
            }
        }
        let mut chunks: Vec<Vec<(i32, i32)>> = Vec::new();
        while let Some(&start) = free.iter().next() {
            free.remove(&start);
            let mut comp = vec![start];
            let mut stack = vec![start];
            while let Some((x, y)) = stack.pop() {
                for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                    let n = (x + dx, y + dy);
                    if free.remove(&n) {
                        comp.push(n);
                        stack.push(n);
                    }
                }
            }
            split_chunks(comp, &mut chunks);
        }
        chunks.sort();

        // Multi-pass: chunks can attach to rooms created by earlier chunks.
        let mut pending = chunks;
        loop {
            let mut progress = false;
            let mut still_pending = Vec::new();
            for chunk in pending {
                let neighbor = chunk.iter().find_map(|&(x, y)| {
                    [(0, -1), (0, 1), (-1, 0), (1, 0)]
                        .iter()
                        .find_map(|(dx, dy)| owner.get(&(deck, x + dx, y + dy)).copied())
                });
                let below = if deck > 0 {
                    chunk.iter().find_map(|&(x, y)| {
                        owner.get(&(deck - 1, x, y)).copied().map(|r| (r, x, y))
                    })
                } else {
                    None
                };
                if neighbor.is_none() && below.is_none() {
                    still_pending.push(chunk);
                    continue;
                }
                progress = true;
                let adjacent_hazard = chunk.iter().any(|&(x, y)| {
                    [(0, -1), (0, 1), (-1, 0), (1, 0)].iter().any(|(dx, dy)| {
                        owner
                            .get(&(deck, x + dx, y + dy))
                            .and_then(|id| role_of.get(id))
                            .map(|r| r.is_hazardous())
                            .unwrap_or(false)
                    })
                });
                let role = loop {
                    let pick = weighted_choice(rng, &weights).unwrap_or(0);
                    let r = filler_roles[pick].0;
                    if !(adjacent_hazard && r.is_crew_comfort()) {
                        break r;
                    }
                    if filler_roles.iter().all(|(fr, _)| fr.is_crew_comfort()) {
                        break Role::Compartment;
                    }
                };
                let id = next_id;
                next_id += 1;
                role_of.insert(id, role);
                for &(x, y) in &chunk {
                    owner.insert((deck, x, y), id);
                }
                placed.topology.rooms.push(RoomSpec {
                    id,
                    role,
                    deck,
                    cells: chunk.iter().map(|&(x, y)| Cell::new(deck, x, y)).collect(),
                });
                if let Some(nid) = neighbor {
                    let n_cells: Vec<(i32, i32)> = placed
                        .topology
                        .rooms
                        .iter()
                        .find(|r| r.id == nid)
                        .map(|r| r.cells.iter().map(|c| (c.x, c.y)).collect())
                        .unwrap_or_default();
                    if let Some((ca, cb)) = shared_boundary(&chunk, &n_cells) {
                        placed.topology.portals.push(PortalIntent {
                            from_room: id,
                            to_room: nid,
                            from_cell: Cell::new(deck, ca.0, ca.1),
                            to_cell: Cell::new(deck, cb.0, cb.1),
                            state: EdgeKind::Door,
                            exterior: false,
                        });
                        placed.room_links.push((id, nid));
                    }
                } else if let Some((rid, x, y)) = below {
                    placed.topology.verticals.push(VerticalConnection {
                        from_room: rid,
                        to_room: id,
                        from_cell: Cell::new(deck - 1, x, y),
                        to_cell: Cell::new(deck, x, y),
                    });
                    placed.room_links.push((rid, id));
                }
            }
            pending = still_pending;
            if !progress || pending.is_empty() {
                break;
            }
        }
    }
    // Refresh the critical path over the richer link graph.
    placed.room_links.sort();
    placed.room_links.dedup();
    if let Some(path) = bfs_room_path(placed.entry_room, placed.goal_room, &placed.room_links) {
        placed.critical_path = path;
    }
}

/// Recursively split an irregular free component into room-sized chunks.
fn split_chunks(comp: Vec<(i32, i32)>, out: &mut Vec<Vec<(i32, i32)>>) {
    if comp.len() <= 9 {
        if !comp.is_empty() {
            out.push(comp);
        }
        return;
    }
    let (mut x0, mut y0, mut x1, mut y1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
    for &(x, y) in &comp {
        x0 = x0.min(x);
        y0 = y0.min(y);
        x1 = x1.max(x);
        y1 = y1.max(y);
    }
    let split_x = x1 - x0 >= y1 - y0;
    let mid = if split_x {
        (x0 + x1) / 2
    } else {
        (y0 + y1) / 2
    };
    let (a, b): (Vec<_>, Vec<_>) =
        comp.into_iter()
            .partition(|&(x, y)| if split_x { x <= mid } else { y <= mid });
    for half in [a, b] {
        let mut set: BTreeSet<(i32, i32)> = half.into_iter().collect();
        while let Some(&start) = set.iter().next() {
            set.remove(&start);
            let mut comp2 = vec![start];
            let mut stack = vec![start];
            while let Some((x, y)) = stack.pop() {
                for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                    let n = (x + dx, y + dy);
                    if set.remove(&n) {
                        comp2.push(n);
                        stack.push(n);
                    }
                }
            }
            split_chunks(comp2, out);
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn pick_role(
    rng: &mut Pcg64,
    pool: &[Role],
    params: &RoleParams,
    counter: &mut BTreeMap<Role, u32>,
) -> Role {
    let chosen = if pool.len() == 1 {
        pool[0]
    } else {
        let eligible: Vec<Role> = pool
            .iter()
            .copied()
            .filter(|r| {
                params.max_duplicates == 0
                    || counter.get(r).copied().unwrap_or(0) < params.max_duplicates as u32
            })
            .collect();
        let candidates = if eligible.is_empty() {
            // Everything capped: least-used pool role (generation never
            // fails here; caps are a soft preference like the original).
            let min = pool
                .iter()
                .map(|r| counter.get(r).copied().unwrap_or(0))
                .min()
                .unwrap();
            pool.iter()
                .copied()
                .filter(|r| counter.get(r).copied().unwrap_or(0) == min)
                .collect()
        } else {
            eligible
        };
        let weights: Vec<u32> = candidates
            .iter()
            .map(|r| params.weights.get(r).copied().unwrap_or(1).max(1))
            .collect();
        candidates[weighted_choice(rng, &weights).unwrap_or(0)]
    };
    *counter.entry(chosen).or_insert(0) += 1;
    chosen
}

fn zone_bfs_order(template: &TemplateDef) -> Vec<usize> {
    let mut order = Vec::new();
    let mut queue: VecDeque<usize> = template
        .zones
        .iter()
        .enumerate()
        .filter(|(_, z)| z.attach_to.is_empty())
        .map(|(i, _)| i)
        .collect();
    let mut seen: BTreeSet<usize> = queue.iter().copied().collect();
    while let Some(i) = queue.pop_front() {
        order.push(i);
        for (j, z) in template.zones.iter().enumerate() {
            if !seen.contains(&j) && z.attach_to == template.zones[i].id {
                seen.insert(j);
                queue.push_back(j);
            }
        }
    }
    // Orphans (shouldn't exist post-validate) appended for safety.
    for i in 0..template.zones.len() {
        if !seen.contains(&i) {
            order.push(i);
        }
    }
    order
}

fn hull_bbox(mask: &Mask) -> (i32, i32, i32, i32) {
    let (mut x0, mut y0, mut x1, mut y1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
    for y in 0..mask.height as i32 {
        for x in 0..mask.width as i32 {
            if mask.get(x, y) {
                x0 = x0.min(x);
                y0 = y0.min(y);
                x1 = x1.max(x);
                y1 = y1.max(y);
            }
        }
    }
    (x0, y0, x1, y1)
}

/// Score-and-scan placement of one room's footprint.
#[allow(clippy::too_many_arguments)]
fn place_room(
    rng: &mut Pcg64,
    grid: &Grid,
    zone: &ZoneDef,
    role: Role,
    anchors: &[RoomId],
    cells_of: &BTreeMap<RoomId, Vec<(i32, i32)>>,
    deck_of: &BTreeMap<RoomId, u8>,
    role_of: &BTreeMap<RoomId, Role>,
    bbox: (i32, i32, i32, i32),
) -> Option<Vec<(i32, i32)>> {
    let deck = zone.deck;
    let mask = &grid.masks[deck as usize];
    let (bx0, by0, bx1, by1) = bbox;
    let span_x = (bx1 - bx0).max(1);
    let span_y = (by1 - by0).max(1);
    // Same-deck anchor cells (adjacency scoring) and cross-deck anchor
    // cells (vertical-overlap scoring).
    let mut same_deck_anchor: Vec<(i32, i32)> = Vec::new();
    let mut cross_deck_anchor: Vec<(i32, i32)> = Vec::new();
    for a in anchors {
        if let (Some(cells), Some(d)) = (cells_of.get(a), deck_of.get(a)) {
            if *d == deck {
                same_deck_anchor.extend(cells.iter().copied());
            } else {
                cross_deck_anchor.extend(cells.iter().copied());
            }
        }
    }
    let same_anchor_set: BTreeSet<(i32, i32)> = same_deck_anchor.iter().copied().collect();
    let cross_anchor_set: BTreeSet<(i32, i32)> = cross_deck_anchor.iter().copied().collect();

    // (score, y, x) key plus the winning rect's cells.
    type Candidate = (i64, i32, i32, Vec<(i32, i32)>);
    let mut best: Option<Candidate> = None;
    let jitter_seed = roll_range(rng, 0, i32::MAX as i64) as u64;
    for &(w, h) in footprint_options(role) {
        for y in 0..mask.height as i32 {
            for x in 0..mask.width as i32 {
                // Rect must fit fully in free hull cells.
                let mut cells = Vec::with_capacity((w * h) as usize);
                let mut ok = true;
                'rect: for dy in 0..h {
                    for dx in 0..w {
                        if !grid.free(deck, x + dx, y + dy) {
                            ok = false;
                            break 'rect;
                        }
                        cells.push((x + dx, y + dy));
                    }
                }
                if !ok {
                    continue;
                }
                // Hazard/comfort hard filter on neighbors.
                let mut incompatible = false;
                let mut adjacency = 0i64;
                let mut contact = 0i64;
                for &(cx, cy) in &cells {
                    for dir in Dir::ALL {
                        let (dx, dy) = dir.delta();
                        let (nx, ny) = (cx + dx, cy + dy);
                        let other = grid.owner_at(deck, nx, ny);
                        if other != NO_ROOM {
                            contact += 1;
                            let or = role_of[&other];
                            if (role.is_hazardous() && or.is_crew_comfort())
                                || (role.is_crew_comfort() && or.is_hazardous())
                            {
                                incompatible = true;
                            }
                            if same_anchor_set.contains(&(nx, ny)) {
                                adjacency += 1;
                            }
                        }
                    }
                }
                if incompatible {
                    continue;
                }
                // Cross-deck overlap (for vertical connections).
                let overlap = cells
                    .iter()
                    .filter(|c| cross_anchor_set.contains(c))
                    .count() as i64;
                if !cross_deck_anchor.is_empty() && overlap == 0 {
                    continue; // must overlap the parent to allow a shaft
                }
                if !same_deck_anchor.is_empty() && adjacency == 0 {
                    // Prefer touching the anchor; allow non-touching only at
                    // a heavy penalty (connector corridor will bridge it).
                }
                let cx = x + w / 2;
                let cy = y + h / 2;
                let hint_score = match zone.position_hint {
                    PositionHint::Bow => -((bx1 - cx).abs() * 100 / span_x) as i64,
                    PositionHint::Stern => -((cx - bx0).abs() * 100 / span_x) as i64,
                    PositionHint::Center => -(((bx0 + bx1) / 2 - cx).abs() * 100 / span_x) as i64,
                    PositionHint::Lateral => {
                        // Prefer off-centerline.
                        ((by0 + by1) / 2 - cy).abs() as i64 * 100 / span_y as i64 - 50
                    }
                };
                // Deterministic per-position jitter for variety.
                let jitter = (crate::rng::key(jitter_seed, "pos", ((x as u64) << 20) ^ (y as u64))
                    % 7) as i64;
                let score = adjacency * 500 + overlap * 500 + contact * 10 + hint_score + jitter;
                let key = (score, y, x);
                if best
                    .as_ref()
                    .map(|(s, by, bx, _)| (key.0, key.1, key.2) > (*s, *by, *bx))
                    .unwrap_or(true)
                {
                    best = Some((score, y, x, cells));
                }
            }
        }
        if best.is_some() {
            break; // first footprint option that fits anywhere wins
        }
    }
    if let Some((_, _, _, cells)) = best {
        return Some(cells);
    }
    // Organic fallback for tight/irregular hulls (mirrors The Synaptic
    // Sea's grow-from-seed): claim a connected blob of free cells the size
    // of the smallest footprint, seeded next to the anchor when possible.
    let min_area = footprint_options(role)
        .iter()
        .map(|(w, h)| (w * h) as usize)
        .min()
        .unwrap_or(4)
        .min(4);
    let mut seeds: Vec<(i32, i32)> = Vec::new();
    let cell_compatible = |x: i32, y: i32| -> bool {
        Dir::ALL.iter().all(|d2| {
            let (ddx, ddy) = d2.delta();
            let other = grid.owner_at(deck, x + ddx, y + ddy);
            other == NO_ROOM || {
                let or = role_of[&other];
                !((role.is_hazardous() && or.is_crew_comfort())
                    || (role.is_crew_comfort() && or.is_hazardous()))
            }
        })
    };
    for &(ax, ay) in &same_deck_anchor {
        for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
            if grid.free(deck, ax + dx, ay + dy) && cell_compatible(ax + dx, ay + dy) {
                seeds.push((ax + dx, ay + dy));
            }
        }
    }
    if seeds.is_empty() {
        for y in 0..mask.height as i32 {
            for x in 0..mask.width as i32 {
                if grid.free(deck, x, y) && cell_compatible(x, y) {
                    seeds.push((x, y));
                }
            }
        }
    }
    seeds.sort();
    seeds.dedup();
    let seed_cell = *seeds.first()?;
    let mut blob: Vec<(i32, i32)> = vec![seed_cell];
    let mut frontier: Vec<(i32, i32)> = vec![seed_cell];
    let mut seen: BTreeSet<(i32, i32)> = BTreeSet::from([seed_cell]);
    while blob.len() < min_area && !frontier.is_empty() {
        // Deterministic frontier expansion; small rng tiebreak via index.
        let idx = (roll_range(rng, 0, frontier.len() as i64 - 1)) as usize;
        let (cx, cy) = frontier.remove(idx);
        for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
            let n = (cx + dx, cy + dy);
            if blob.len() >= min_area || !grid.free(deck, n.0, n.1) {
                continue;
            }
            // Hazard/comfort hard filter applies to organic growth too.
            let incompatible = Dir::ALL.iter().any(|d2| {
                let (ddx, ddy) = d2.delta();
                let other = grid.owner_at(deck, n.0 + ddx, n.1 + ddy);
                other != NO_ROOM && {
                    let or = role_of[&other];
                    (role.is_hazardous() && or.is_crew_comfort())
                        || (role.is_crew_comfort() && or.is_hazardous())
                }
            });
            if !incompatible && seen.insert(n) {
                blob.push(n);
                frontier.push(n);
            }
        }
    }
    if blob.len() >= min_area.min(2) {
        Some(blob)
    } else {
        None
    }
}

fn rooms_of_zone(template: &TemplateDef, plan: &[PlannedRoom], zone_id: &str) -> Vec<RoomId> {
    let Some(zi) = template.zones.iter().position(|z| z.id == zone_id) else {
        return Vec::new();
    };
    plan.iter()
        .filter(|r| r.zone_index == zi)
        .map(|r| r.id)
        .collect()
}

fn centroid(cells: &[(i32, i32)]) -> (i64, i64) {
    let n = cells.len().max(1) as i64;
    (
        cells.iter().map(|c| c.0 as i64).sum::<i64>() / n,
        cells.iter().map(|c| c.1 as i64).sum::<i64>() / n,
    )
}

fn closest_pair(
    from: &[RoomId],
    to: &[RoomId],
    cells_of: &BTreeMap<RoomId, Vec<(i32, i32)>>,
    deck_of: &BTreeMap<RoomId, u8>,
) -> (RoomId, RoomId) {
    let mut best: Option<(i64, RoomId, RoomId)> = None;
    for &a in from {
        for &b in to {
            let ca = centroid(&cells_of[&a]);
            let cb = centroid(&cells_of[&b]);
            let deck_penalty = if deck_of[&a] == deck_of[&b] { 0 } else { 1000 };
            let d = (ca.0 - cb.0).abs() + (ca.1 - cb.1).abs() + deck_penalty;
            if best
                .map(|(bd, ba, bb)| (d, a, b) < (bd, ba, bb))
                .unwrap_or(true)
            {
                best = Some((d, a, b));
            }
        }
    }
    let (_, a, b) = best.unwrap();
    (a, b)
}

/// A pair of cells (one in each room) sharing a cardinal boundary, chosen
/// as the middle of the longest shared run for natural door placement.
fn shared_boundary(a: &[(i32, i32)], b: &[(i32, i32)]) -> Option<((i32, i32), (i32, i32))> {
    let bset: BTreeSet<(i32, i32)> = b.iter().copied().collect();
    let mut pairs: Vec<((i32, i32), (i32, i32))> = Vec::new();
    for &(x, y) in a {
        for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
            if bset.contains(&(x + dx, y + dy)) {
                pairs.push(((x, y), (x + dx, y + dy)));
            }
        }
    }
    if pairs.is_empty() {
        return None;
    }
    pairs.sort();
    Some(pairs[pairs.len() / 2])
}

/// Connect two same-deck rooms by BFS over ALL hull cells: free spans
/// along the path become new connector corridor rooms; crossings between
/// rooms become pass-through doors. Falls back to nothing only when the
/// hull itself is disconnected between them.
#[allow(clippy::too_many_arguments)]
fn route_connection(
    grid: &mut Grid,
    deck: u8,
    a: RoomId,
    b: RoomId,
    cells_of: &mut BTreeMap<RoomId, Vec<(i32, i32)>>,
    deck_of: &mut BTreeMap<RoomId, u8>,
    role_of: &mut BTreeMap<RoomId, Role>,
    portals: &mut Vec<PortalIntent>,
    links: &mut Vec<(RoomId, RoomId)>,
    connector_rooms: &mut Vec<RoomSpec>,
    next_connector_id: &mut RoomId,
) -> Option<()> {
    let a_cells: BTreeSet<(i32, i32)> = cells_of[&a].iter().copied().collect();
    let b_cells: BTreeSet<(i32, i32)> = cells_of[&b].iter().copied().collect();
    // BFS from every cell of `a` through hull cells (any owner) to `b`.
    let mut prev: BTreeMap<(i32, i32), (i32, i32)> = BTreeMap::new();
    let mut seen: BTreeSet<(i32, i32)> = a_cells.clone();
    let mut queue: VecDeque<(i32, i32)> = a_cells.iter().copied().collect();
    let mut hit: Option<(i32, i32)> = None;
    'bfs: while let Some(cur) = queue.pop_front() {
        for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
            let n = (cur.0 + dx, cur.1 + dy);
            if !grid.in_hull(deck, n.0, n.1) || !seen.insert(n) {
                continue;
            }
            prev.insert(n, cur);
            if b_cells.contains(&n) {
                hit = Some(n);
                break 'bfs;
            }
            queue.push_back(n);
        }
    }
    let mut path = vec![hit?];
    while let Some(&p) = prev.get(path.last().unwrap()) {
        path.push(p);
    }
    path.reverse(); // now runs a-cell .. b-cell

    // Collapse into maximal same-owner segments (owner NO_ROOM = free run).
    let mut segments: Vec<(RoomId, Vec<(i32, i32)>)> = Vec::new();
    for &cell in &path {
        let owner = grid.owner_at(deck, cell.0, cell.1);
        match segments.last_mut() {
            Some((o, cells)) if *o == owner => cells.push(cell),
            _ => segments.push((owner, vec![cell])),
        }
    }
    // Materialize free runs as connector corridor rooms.
    for seg in segments.iter_mut() {
        if seg.0 != NO_ROOM {
            continue;
        }
        let id = *next_connector_id;
        *next_connector_id += 1;
        grid.claim(deck, &seg.1, id);
        cells_of.insert(id, seg.1.clone());
        deck_of.insert(id, deck);
        role_of.insert(id, Role::Corridor);
        connector_rooms.push(RoomSpec {
            id,
            role: Role::Corridor,
            deck,
            cells: seg.1.iter().map(|&(x, y)| Cell::new(deck, x, y)).collect(),
        });
        seg.0 = id;
    }
    // Doors at each segment crossing (dedup against existing links).
    for w in segments.windows(2) {
        let ((ra, cells_a), (rb, cells_b)) = (&w[0], &w[1]);
        if ra == rb || links.contains(&(*ra, *rb)) || links.contains(&(*rb, *ra)) {
            continue;
        }
        let ca = *cells_a.last().unwrap();
        let cb = cells_b[0];
        portals.push(PortalIntent {
            from_room: *ra,
            to_room: *rb,
            from_cell: Cell::new(deck, ca.0, ca.1),
            to_cell: Cell::new(deck, cb.0, cb.1),
            state: EdgeKind::Door,
            exterior: false,
        });
        links.push((*ra, *rb));
    }
    Some(())
}

/// A hull-boundary edge of a room (for the exterior entry door).
fn hull_boundary_edge(grid: &Grid, deck: u8, cells: &[(i32, i32)]) -> Option<(Cell, Dir)> {
    let mut candidates: Vec<(Cell, Dir)> = Vec::new();
    for &(x, y) in cells {
        for dir in Dir::ALL {
            let (dx, dy) = dir.delta();
            if !grid.in_hull(deck, x + dx, y + dy) {
                candidates.push((Cell::new(deck, x, y), dir));
            }
        }
    }
    candidates.sort_by_key(|(c, d)| (c.y, c.x, d.yaw_degrees()));
    candidates.get(candidates.len() / 2).copied()
}

/// Public BFS path over room links (used by the pipeline for post-damage
/// critical-path recomputation).
pub fn room_path(start: RoomId, goal: RoomId, links: &[(RoomId, RoomId)]) -> Option<Vec<RoomId>> {
    bfs_room_path(start, goal, links)
}

fn bfs_room_path(start: RoomId, goal: RoomId, links: &[(RoomId, RoomId)]) -> Option<Vec<RoomId>> {
    let mut adj: BTreeMap<RoomId, Vec<RoomId>> = BTreeMap::new();
    for &(a, b) in links {
        adj.entry(a).or_default().push(b);
        adj.entry(b).or_default().push(a);
    }
    let mut prev: BTreeMap<RoomId, RoomId> = BTreeMap::new();
    let mut queue = VecDeque::from([start]);
    let mut seen = BTreeSet::from([start]);
    while let Some(cur) = queue.pop_front() {
        if cur == goal {
            let mut path = vec![goal];
            let mut c = goal;
            while let Some(&p) = prev.get(&c) {
                path.push(p);
                c = p;
            }
            path.reverse();
            return Some(path);
        }
        for &n in adj.get(&cur).map(|v| v.as_slice()).unwrap_or(&[]) {
            if seen.insert(n) {
                prev.insert(n, cur);
                queue.push_back(n);
            }
        }
    }
    None
}
