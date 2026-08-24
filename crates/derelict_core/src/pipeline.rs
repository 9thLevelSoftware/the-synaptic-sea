//! Pipeline orchestration: runs the nine generation stages in fixed order
//! and assembles the final immutable `Ship`.

use crate::archetype::GenData;
use crate::model::*;
use crate::rng::{self, roll_range, weighted_choice};
use crate::stages::{corridors, damage, furnish, hull, loot, multideck, rooms, story};
use std::collections::BTreeMap;
use std::time::Instant;

#[derive(Debug)]
pub enum GenError {
    UnknownArchetype(String),
}

impl std::fmt::Display for GenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GenError::UnknownArchetype(id) => write!(f, "unknown archetype '{id}'"),
        }
    }
}

impl std::error::Error for GenError {}

/// Per-stage wall-clock timings (diagnostic only; never feeds generation).
pub struct GenReport {
    pub ship: Ship,
    pub stage_micros: Vec<(&'static str, u128)>,
}

pub fn generate_ship(seed: u64, params: &GenParams, data: &GenData) -> Result<Ship, GenError> {
    generate_ship_timed(seed, params, data).map(|r| r.ship)
}

pub fn generate_ship_timed(
    seed: u64,
    params: &GenParams,
    data: &GenData,
) -> Result<GenReport, GenError> {
    let arch = data
        .archetypes
        .get(&params.archetype_id)
        .ok_or_else(|| GenError::UnknownArchetype(params.archetype_id.clone()))?;
    let mut timings: Vec<(&'static str, u128)> = Vec::new();
    let mut mark = Instant::now();
    let lap = |name: &'static str, timings: &mut Vec<(&'static str, u128)>, mark: &mut Instant| {
        timings.push((name, mark.elapsed().as_micros()));
        *mark = Instant::now();
    };

    // --- Stage 1-2: hull + decks -------------------------------------------
    let mut meta_rng = rng::stream(seed, "meta", 0);
    let deck_count = roll_range(&mut meta_rng, arch.decks.0 as i64, arch.decks.1 as i64) as u8;
    let mut hull_rng = rng::stream(seed, "hull", 0);
    let plan = hull::generate_hull(&mut hull_rng, arch, deck_count);
    lap("hull", &mut timings, &mut mark);

    // --- Stage 3: rooms -----------------------------------------------------
    let mut deck_rooms: Vec<rooms::DeckRooms> = Vec::new();
    let mut next_room_id: u16 = 1;
    for (d, mask) in plan.deck_masks.iter().enumerate() {
        let mut r = rng::stream(seed, "bsp", d as u64);
        let dr = rooms::partition_deck(&mut r, mask, arch, next_room_id);
        next_room_id += dr.rooms.len() as u16;
        deck_rooms.push(dr);
    }
    // Hull bbox on deck 0 for positional scoring.
    let bbox_x = {
        let m = &plan.deck_masks[0];
        let (mut x0, mut x1) = (i32::MAX, i32::MIN);
        for y in 0..m.height as i32 {
            for x in 0..m.width as i32 {
                if m.get(x, y) {
                    x0 = x0.min(x);
                    x1 = x1.max(x);
                }
            }
        }
        (x0, x1)
    };
    let mut assign_rng = rng::stream(seed, "assign", 0);
    rooms::assign_rooms(&mut assign_rng, &mut deck_rooms, arch, bbox_x);
    lap("rooms", &mut timings, &mut mark);

    // --- Stage 4-5: corridors + doors --------------------------------------
    let mut corridor_ids: Vec<u16> = Vec::new();
    for d in 0..deck_rooms.len() {
        let mut r = rng::stream(seed, "corridor", d as u64);
        let cid = corridors::carve_deck_corridors(
            &mut r,
            &mut deck_rooms[d],
            &plan.deck_masks[d],
            arch,
            &mut next_room_id,
        );
        corridor_ids.push(cid);
    }
    ensure_hull_airlock(&mut deck_rooms);
    let mut all_door_specs: Vec<corridors::DoorSpec> = Vec::new();
    for d in 0..deck_rooms.len() {
        let mut dr_rng = rng::stream(seed, "doors", d as u64);
        let specs = corridors::place_doors(&mut dr_rng, &deck_rooms[d], d as u8, corridor_ids[d]);
        all_door_specs.extend(specs);
    }
    lap("corridors", &mut timings, &mut mark);

    // Room kind lookup (ship-wide, ids unique across decks).
    let mut kind_of: BTreeMap<u16, RoomType> = BTreeMap::new();
    let mut deck_of: BTreeMap<u16, u8> = BTreeMap::new();
    for (d, dr) in deck_rooms.iter().enumerate() {
        for room in &dr.rooms {
            kind_of.insert(room.id, room.kind);
            deck_of.insert(room.id, d as u8);
        }
    }

    // --- Build tile layers --------------------------------------------------
    let mut layers: Vec<DeckLayer> = Vec::new();
    for (d, dr) in deck_rooms.iter().enumerate() {
        let mut layer = DeckLayer::new(dr.width, dr.height);
        let w = dr.width as i32;
        for y in 0..dr.height as i32 {
            for x in 0..w {
                let i = (y * w + x) as usize;
                let r = dr.room_grid[i];
                layer.room_id[i] = r;
                if r != NO_ROOM {
                    layer.floor[i] = if r == corridor_ids[d] { FloorTile::Grated } else { FloorTile::Deck };
                }
            }
        }
        // Walls: hull boundary + inter-room partitions (edge-based).
        for y in 0..dr.height as i32 {
            for x in 0..w {
                let here = dr.room_grid[(y * w + x) as usize];
                let up = if y > 0 { dr.room_grid[((y - 1) * w + x) as usize] } else { NO_ROOM };
                let left = if x > 0 { dr.room_grid[(y * w + x - 1) as usize] } else { NO_ROOM };
                let north = wall_between(here, up);
                let west = wall_between(here, left);
                let i = (y * w + x) as usize;
                layer.walls[i].north = north;
                layer.walls[i].west = west;
            }
        }
        layers.push(layer);
    }
    // Doorway edges.
    for spec in &all_door_specs {
        let layer = &mut layers[spec.deck as usize];
        if let Some(i) = layer.idx(spec.x, spec.y) {
            if spec.north {
                layer.walls[i].north = WallEdge::Doorway;
            } else {
                layer.walls[i].west = WallEdge::Doorway;
            }
        }
    }
    lap("layers", &mut timings, &mut mark);

    // --- Stage 5b: vertical shafts -----------------------------------------
    let mut shaft_rng = rng::stream(seed, "shafts", 0);
    let shafts = multideck::choose_shafts(&mut shaft_rng, &deck_rooms, &corridor_ids, arch);
    lap("shafts", &mut timings, &mut mark);

    // --- Stage 6: furnishing ------------------------------------------------
    let mut entities: Vec<EntitySpec> = Vec::new();
    let mut furnisher = furnish::Furnisher {
        master_seed: seed,
        rules: &data.furnishing,
        next_entity_id: 1,
    };
    furnisher.create_doors(&all_door_specs, |id| kind_of.get(&id).copied(), &mut entities);
    // Ladder entities per deck at each shaft.
    for (si, s) in shafts.iter().enumerate() {
        for d in 0..deck_rooms.len() {
            entities.push(EntitySpec {
                id: furnisher.next_entity_id,
                kind: EntityKind::Furniture,
                proto: "ladder".into(),
                pos: GridPos::new(s.x, s.y, d as u8),
                rotation: 0,
                locked: false,
                open: false,
                inventory: Vec::new(),
                tags: vec![format!("shaft_{si}")],
            });
            furnisher.next_entity_id += 1;
        }
    }
    // Shaft tiles must stay clear of furniture.
    for d in 0..deck_rooms.len() {
        let mut occupied = vec![false; layers[d].floor.len()];
        for e in &entities {
            if e.pos.deck as usize == d {
                if let Some(i) = layers[d].idx(e.pos.x, e.pos.y) {
                    occupied[i] = true;
                }
            }
        }
        let (dr, layer) = (&deck_rooms[d], &layers[d]);
        furnisher.furnish_deck(dr, layer, d as u8, &mut occupied, &mut entities);
    }
    let mut next_entity_id = furnisher.next_entity_id;
    lap("furnish", &mut timings, &mut mark);

    // --- Stage 7: story -----------------------------------------------------
    let mut story_rng = rng::stream(seed, "story", 0);
    let cause = story::choose_cause(&mut story_rng, arch, params.cause_override);
    let profile = story::profile_for(cause);
    let intactness = params.intactness_override.unwrap_or_else(|| {
        let mut r = rng::stream(seed, "intact", 0);
        let bucket = weighted_choice(&mut r, &[25, 50, 25]).unwrap_or(1);
        let (lo, hi) = match bucket {
            0 => (7000, 9800),
            1 => (3500, 7000),
            _ => (600, 3500),
        };
        roll_range(&mut r, lo, hi) as u16
    });
    lap("story", &mut timings, &mut mark);

    // --- Stage 8: damage ----------------------------------------------------
    let outcome = damage::apply_damage(
        seed,
        &mut layers,
        &mut entities,
        &mut next_entity_id,
        &kind_of,
        &profile,
        intactness,
        arch,
    );
    lap("damage", &mut timings, &mut mark);

    // --- Stage 9: loot ------------------------------------------------------
    loot::seed_loot(
        seed,
        &mut entities,
        &layers,
        &kind_of,
        data,
        &profile,
        intactness,
        params.loot_richness,
    );
    lap("loot", &mut timings, &mut mark);

    // --- Final room graph from the (possibly fractured) layers --------------
    let mut stats: BTreeMap<u16, (i32, i32, i32, i32, u32)> = BTreeMap::new();
    for layer in &layers {
        let w = layer.width as i32;
        for y in 0..layer.height as i32 {
            for x in 0..w {
                let r = layer.room_id[(y * w + x) as usize];
                if r == NO_ROOM {
                    continue;
                }
                let e = stats.entry(r).or_insert((i32::MAX, i32::MAX, i32::MIN, i32::MIN, 0));
                e.0 = e.0.min(x);
                e.1 = e.1.min(y);
                e.2 = e.2.max(x);
                e.3 = e.3.max(y);
                e.4 += 1;
            }
        }
    }
    let mut nodes: Vec<RoomNode> = Vec::new();
    for (id, (x0, y0, x1, y1, count)) in &stats {
        nodes.push(RoomNode {
            id: *id,
            deck: deck_of.get(id).copied().unwrap_or(0),
            kind: kind_of.get(id).copied().unwrap_or(RoomType::Compartment),
            min: (*x0, *y0),
            max: (*x1, *y1),
            tile_count: *count,
            depressurized: outcome.depressurized.contains(id),
            spans_room_id: None,
        });
    }
    // Edges: doors that survived damage + vertical shafts.
    let mut edges: Vec<RoomEdge> = Vec::new();
    for e in &entities {
        if e.kind != EntityKind::Door {
            continue;
        }
        let layer = &layers[e.pos.deck as usize];
        let (a, b) = if e.rotation == 0 {
            (layer.room_at(e.pos.x, e.pos.y), layer.room_at(e.pos.x, e.pos.y - 1))
        } else {
            (layer.room_at(e.pos.x, e.pos.y), layer.room_at(e.pos.x - 1, e.pos.y))
        };
        if a != NO_ROOM && b != NO_ROOM && a != b {
            let (a, b) = if a < b { (a, b) } else { (b, a) };
            if !edges.iter().any(|e| e.a == a && e.b == b && e.kind == EdgeKind::Door) {
                edges.push(RoomEdge { a, b, kind: EdgeKind::Door });
            }
        }
    }
    for s in &shafts {
        for d in 1..layers.len() {
            // Shaft tiles were not moved by fracture on deck > 0? They were —
            // fracture translates all decks identically, so re-read rooms at
            // the ladder entity's (possibly shifted) position instead.
            let _ = d;
        }
        let _ = s;
    }
    // Vertical edges from ladder entities (positions already post-fracture).
    let ladders: Vec<&EntitySpec> = entities.iter().filter(|e| e.proto == "ladder").collect();
    for l in &ladders {
        let d = l.pos.deck as usize;
        if d + 1 < layers.len() {
            let a = layers[d].room_at(l.pos.x, l.pos.y);
            let b = layers[d + 1].room_at(l.pos.x, l.pos.y);
            if a != NO_ROOM && b != NO_ROOM {
                let (a, b) = if a < b { (a, b) } else { (b, a) };
                if !edges.iter().any(|e| e.a == a && e.b == b && e.kind == EdgeKind::VerticalShaft) {
                    edges.push(RoomEdge { a, b, kind: EdgeKind::VerticalShaft });
                }
            }
        }
    }

    let mut fragments = outcome.fragments;
    if let Some(frag1_rooms) = fragments.get(1).map(|f| f.rooms.clone()) {
        let all_ids: Vec<u16> = stats.keys().copied().collect();
        fragments[0].rooms = all_ids.into_iter().filter(|id| !frag1_rooms.contains(id)).collect();
    }

    let ship = Ship {
        generator_version: GENERATOR_VERSION,
        seed,
        archetype_id: params.archetype_id.clone(),
        intactness,
        cause_of_loss: cause,
        decks: layers.into_iter().map(|layer| Deck { layer }).collect(),
        room_graph: RoomGraph { nodes, edges },
        entities,
        damage_events: outcome.events,
        fractured: outcome.fractured,
        fragments,
    };
    lap("assemble", &mut timings, &mut mark);
    Ok(GenReport { ship, stage_micros: timings })
}

/// Corridor carving can shrink or absorb the assigned airlock until it no
/// longer touches the hull. Guarantee at least one hull-touching Airlock so
/// every ship has an entrance: demote non-boundary airlocks, then promote
/// the smallest hull-touching room (deck 0 preferred) if none remain.
fn ensure_hull_airlock(deck_rooms: &mut [rooms::DeckRooms]) {
    for dr in deck_rooms.iter_mut() {
        for room in dr.rooms.iter_mut() {
            if room.kind == RoomType::Airlock && !room.touches_hull {
                room.kind = RoomType::Compartment;
            }
        }
    }
    let has_airlock = deck_rooms
        .iter()
        .any(|dr| dr.rooms.iter().any(|r| r.kind == RoomType::Airlock && r.touches_hull));
    if has_airlock {
        return;
    }
    // Deterministic promotion: deck order, then smallest room, then id.
    let mut best: Option<(usize, u32, usize, usize)> = None; // (deck, size, idx) key
    for (d, dr) in deck_rooms.iter().enumerate() {
        for (i, room) in dr.rooms.iter().enumerate() {
            if !room.touches_hull || room.kind == RoomType::Corridor {
                continue;
            }
            let key = (d, room.tiles.len() as u32, i, 0usize);
            if best.map(|b| key < (b.0, b.1, b.2, b.3)).unwrap_or(true) {
                best = Some(key);
            }
        }
    }
    if let Some((d, _, i, _)) = best {
        deck_rooms[d].rooms[i].kind = RoomType::Airlock;
    }
}

fn wall_between(a: u16, b: u16) -> WallEdge {
    match (a == NO_ROOM, b == NO_ROOM) {
        (true, true) => WallEdge::None,
        (false, true) | (true, false) => WallEdge::Hull,
        (false, false) => {
            if a == b {
                WallEdge::None
            } else {
                WallEdge::Interior
            }
        }
    }
}
