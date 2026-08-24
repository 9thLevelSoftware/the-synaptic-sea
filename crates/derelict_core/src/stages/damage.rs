//! Stage 8: damage/wreck pass, gated by intactness (0..=10000 bp).
//!
//! Sub-passes: hull breaches (CA-eroded holes, story-biased placement),
//! scorch decals, crew bodies, sealed doors, and — below the fracture
//! threshold — a structural fracture that tears the ship into two pieces,
//! bakes them apart into an enlarged canvas, and fills the gap with a
//! deterministic debris field.

use crate::archetype::ShipArchetype;
use crate::model::{
    decal, DamageEvent, DamageEventKind, DeckLayer, EntityKind, EntitySpec, FloorTile, GridPos,
    RoomType, ShipFragment, TileCoord, WallEdge, NO_ROOM,
};
use crate::rng::{self, roll_bp, roll_range, weighted_choice};
use crate::stages::story::DamageProfile;
use rand_pcg::Pcg64;
use std::collections::{BTreeMap, BTreeSet};

pub const FRACTURE_THRESHOLD_BP: u16 = 3500;

pub struct DamageOutcome {
    pub events: Vec<DamageEvent>,
    pub depressurized: BTreeSet<u16>,
    pub fractured: bool,
    pub fragments: Vec<ShipFragment>,
}

/// Clear the four wall edges surrounding tile (x, y).
fn clear_edges_around(layer: &mut DeckLayer, x: TileCoord, y: TileCoord) {
    if let Some(i) = layer.idx(x, y) {
        layer.walls[i].north = WallEdge::None;
        layer.walls[i].west = WallEdge::None;
    }
    if let Some(i) = layer.idx(x, y + 1) {
        layer.walls[i].north = WallEdge::None;
    }
    if let Some(i) = layer.idx(x + 1, y) {
        layer.walls[i].west = WallEdge::None;
    }
}

fn remove_tile(layer: &mut DeckLayer, x: TileCoord, y: TileCoord) {
    if let Some(i) = layer.idx(x, y) {
        layer.floor[i] = FloorTile::Void;
        layer.room_id[i] = NO_ROOM;
        layer.decal[i] = decal::NONE;
        clear_edges_around(layer, x, y);
    }
}

#[allow(clippy::too_many_arguments)]
pub fn apply_damage(
    master_seed: u64,
    layers: &mut [DeckLayer],
    entities: &mut Vec<EntitySpec>,
    next_entity_id: &mut u32,
    kind_of: &BTreeMap<u16, RoomType>,
    profile: &DamageProfile,
    intactness: u16,
    arch: &ShipArchetype,
) -> DamageOutcome {
    let mut out = DamageOutcome {
        events: Vec::new(),
        depressurized: BTreeSet::new(),
        fractured: false,
        fragments: Vec::new(),
    };
    let damage_bp = (10_000 - intactness) as i64;

    breach_pass(
        master_seed,
        layers,
        entities,
        kind_of,
        profile,
        damage_bp,
        arch,
        &mut out,
    );
    scorch_pass(master_seed, layers, kind_of, profile);
    seal_doors_pass(master_seed, entities, profile);

    if intactness < FRACTURE_THRESHOLD_BP {
        fracture_pass(master_seed, layers, entities, next_entity_id, &mut out);
    }

    body_pass(
        master_seed,
        layers,
        entities,
        next_entity_id,
        kind_of,
        profile,
        damage_bp,
    );

    if matches!(profile.cause, crate::model::CauseOfLoss::Depressurization) {
        // Ship-wide loss of atmosphere.
        for id in kind_of.keys() {
            out.depressurized.insert(*id);
        }
    }
    out
}

#[allow(clippy::too_many_arguments)]
fn breach_pass(
    master_seed: u64,
    layers: &mut [DeckLayer],
    entities: &mut Vec<EntitySpec>,
    kind_of: &BTreeMap<u16, RoomType>,
    profile: &DamageProfile,
    damage_bp: i64,
    arch: &ShipArchetype,
    out: &mut DamageOutcome,
) {
    let mut rng = rng::stream(master_seed, "breach", 0);
    if damage_bp < 800 {
        return; // pristine ships have no hull breaches
    }
    let base = arch.max_breaches as i64 * damage_bp / 10_000;
    let min = if damage_bp >= 3000 { 1 } else { 0 };
    let n_breaches = (base + roll_range(&mut rng, -1, 1)).clamp(min, arch.max_breaches as i64);

    // Precompute "near a bias room" grids per deck (BFS depth 6 from all
    // bias-room tiles).
    let bias_near: Vec<Vec<bool>> = layers
        .iter()
        .map(|layer| {
            let w = layer.width as usize;
            let mut near = vec![false; layer.floor.len()];
            let mut frontier: Vec<usize> = Vec::new();
            for (i, id) in layer.room_id.iter().enumerate() {
                if let Some(k) = kind_of.get(id) {
                    if profile.breach_bias_rooms.contains(k) {
                        near[i] = true;
                        frontier.push(i);
                    }
                }
            }
            for _ in 0..6 {
                let mut next: Vec<usize> = Vec::new();
                for &i in &frontier {
                    let x = (i % w) as i32;
                    let y = (i / w) as i32;
                    for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                        if let Some(j) = layer.idx(x + dx, y + dy) {
                            if !near[j] {
                                near[j] = true;
                                next.push(j);
                            }
                        }
                    }
                }
                frontier = next;
            }
            near
        })
        .collect();

    let mut placed: Vec<(usize, i32, i32)> = Vec::new(); // (deck, x, y)
    for b in 0..n_breaches {
        let deck = roll_range(&mut rng, 0, layers.len() as i64 - 1) as usize;
        let layer = &layers[deck];
        let w = layer.width as i32;
        // Hull boundary tiles.
        let mut cands: Vec<(i32, i32)> = Vec::new();
        let mut weights: Vec<u32> = Vec::new();
        for y in 0..layer.height as i32 {
            for x in 0..w {
                let i = (y * w + x) as usize;
                if layer.floor[i] == FloorTile::Void {
                    continue;
                }
                let boundary = [(0, -1), (0, 1), (-1, 0), (1, 0)]
                    .iter()
                    .any(|(dx, dy)| layer.floor_at(x + dx, y + dy) == FloorTile::Void);
                if !boundary {
                    continue;
                }
                if placed
                    .iter()
                    .any(|(d, px, py)| *d == deck && (px - x).abs() + (py - y).abs() < 5)
                {
                    continue;
                }
                cands.push((x, y));
                weights.push(if bias_near[deck][i] { 8 } else { 1 });
            }
        }
        let Some(pick) = weighted_choice(&mut rng, &weights) else {
            continue;
        };
        let (ox, oy) = cands[pick];
        placed.push((deck, ox, oy));

        let radius = (roll_range(&mut rng, 2, 4) + damage_bp / 4000) as i32;
        carve_breach(&mut rng, &mut layers[deck], ox, oy, radius, profile, out);
        out.events.push(DamageEvent {
            kind: DamageEventKind::Breach,
            deck: deck as u8,
            origin: (ox, oy),
            radius: radius as u16,
        });
        let _ = b;
    }

    // Entities standing on now-void tiles were destroyed.
    entities.retain(|e| {
        let layer = &layers[e.pos.deck as usize];
        e.kind == EntityKind::Door || layer.floor_at(e.pos.x, e.pos.y) != FloorTile::Void
    });
    // Doors whose edge walls are gone likewise.
    entities.retain(|e| {
        if e.kind != EntityKind::Door {
            return true;
        }
        let layer = &layers[e.pos.deck as usize];
        let edge = if e.rotation == 0 {
            layer.walls_at(e.pos.x, e.pos.y).north
        } else {
            layer.walls_at(e.pos.x, e.pos.y).west
        };
        edge == WallEdge::Doorway
    });
}

fn carve_breach(
    rng: &mut Pcg64,
    layer: &mut DeckLayer,
    ox: i32,
    oy: i32,
    radius: i32,
    profile: &DamageProfile,
    out: &mut DamageOutcome,
) {
    let w = layer.width as i32;
    let h = layer.height as i32;
    // Cellular erosion: removal probability falls off with distance.
    let mut removed: Vec<(i32, i32)> = Vec::new();
    for y in (oy - radius).max(0)..=(oy + radius).min(h - 1) {
        for x in (ox - radius).max(0)..=(ox + radius).min(w - 1) {
            let d = (x - ox).abs() + (y - oy).abs();
            if d > radius {
                continue;
            }
            let i = (y * w + x) as usize;
            if layer.floor[i] == FloorTile::Void {
                continue;
            }
            let p_remove = (radius - d + 1) as u32 * 9000 / (radius + 1) as u32;
            if roll_bp(rng, p_remove) {
                if layer.room_id[i] != NO_ROOM {
                    out.depressurized.insert(layer.room_id[i]);
                }
                removed.push((x, y));
            } else {
                // Scarred ring.
                layer.floor[i] = FloorTile::DamagedDeck;
                if roll_bp(rng, profile.scorch_bp) {
                    layer.decal[i] = decal::SCORCH_LIGHT;
                }
                if layer.room_id[i] != NO_ROOM {
                    out.depressurized.insert(layer.room_id[i]);
                }
            }
        }
    }
    for (x, y) in &removed {
        remove_tile(layer, *x, *y);
    }
    // Jagged wall remnants around the hole.
    for (x, y) in &removed {
        for (dx, dy, north, ex, ey) in [
            (0, -1, true, *x, *y),     // north edge of removed tile
            (0, 1, true, *x, *y + 1),  // south edge
            (-1, 0, false, *x, *y),    // west edge
            (1, 0, false, *x + 1, *y), // east edge
        ] {
            let (nx, ny) = (x + dx, y + dy);
            if layer.floor_at(nx, ny) != FloorTile::Void && roll_bp(rng, 3500) {
                if let Some(i) = layer.idx(ex, ey) {
                    if north {
                        layer.walls[i].north = WallEdge::Breached;
                    } else {
                        layer.walls[i].west = WallEdge::Breached;
                    }
                }
            }
        }
    }
}

fn scorch_pass(
    master_seed: u64,
    layers: &mut [DeckLayer],
    kind_of: &BTreeMap<u16, RoomType>,
    profile: &DamageProfile,
) {
    if profile.scorch_rooms.is_empty() {
        return;
    }
    for (d, layer) in layers.iter_mut().enumerate() {
        let mut rng = rng::stream(master_seed, "scorch", d as u64);
        for i in 0..layer.floor.len() {
            if layer.floor[i] == FloorTile::Void {
                continue;
            }
            let Some(k) = kind_of.get(&layer.room_id[i]) else {
                continue;
            };
            if profile.scorch_rooms.contains(k) && roll_bp(&mut rng, 4500) {
                layer.decal[i] = if roll_bp(&mut rng, 4000) {
                    decal::SCORCH_HEAVY
                } else {
                    decal::SCORCH_LIGHT
                };
            }
        }
    }
}

fn seal_doors_pass(master_seed: u64, entities: &mut [EntitySpec], profile: &DamageProfile) {
    if profile.sealed_door_bp == 0 {
        return;
    }
    for e in entities.iter_mut() {
        if e.kind != EntityKind::Door || e.proto == "airlock_door" {
            continue;
        }
        let mut rng = rng::stream(master_seed, "seal", e.id as u64);
        if roll_bp(&mut rng, profile.sealed_door_bp) {
            e.locked = true;
            e.open = false;
            e.tags.push("sealed".into());
        }
    }
}

fn body_pass(
    master_seed: u64,
    layers: &[DeckLayer],
    entities: &mut Vec<EntitySpec>,
    next_entity_id: &mut u32,
    kind_of: &BTreeMap<u16, RoomType>,
    profile: &DamageProfile,
    damage_bp: i64,
) {
    let mut rng = rng::stream(master_seed, "bodies", 0);
    let extra = damage_bp / 3000; // more carnage on more damaged ships
    let n = roll_range(
        &mut rng,
        profile.bodies.0 as i64,
        profile.bodies.1 as i64 + extra,
    );
    if n <= 0 {
        return;
    }
    let occupied: BTreeSet<(u8, i32, i32)> = entities
        .iter()
        .map(|e| (e.pos.deck, e.pos.x, e.pos.y))
        .collect();
    // Candidates: walkable tiles in preferred rooms first, any room fallback.
    let mut preferred: Vec<GridPos> = Vec::new();
    let mut fallback: Vec<GridPos> = Vec::new();
    for (d, layer) in layers.iter().enumerate() {
        let w = layer.width as i32;
        for y in 0..layer.height as i32 {
            for x in 0..w {
                let i = (y * w + x) as usize;
                if !layer.floor[i].walkable() || layer.room_id[i] == NO_ROOM {
                    continue;
                }
                if occupied.contains(&(d as u8, x, y)) {
                    continue;
                }
                let pos = GridPos::new(x, y, d as u8);
                match kind_of.get(&layer.room_id[i]) {
                    Some(k) if profile.body_rooms.contains(k) => preferred.push(pos),
                    Some(_) => fallback.push(pos),
                    None => {}
                }
            }
        }
    }
    let mut placed: Vec<GridPos> = Vec::new();
    for b in 0..n {
        let pool: &[GridPos] = if !preferred.is_empty() {
            &preferred
        } else {
            &fallback
        };
        if pool.is_empty() {
            break;
        }
        let pick = roll_range(&mut rng, 0, pool.len() as i64 - 1) as usize;
        let pos = pool[pick];
        if placed.contains(&pos) {
            continue;
        }
        placed.push(pos);
        entities.push(EntitySpec {
            id: *next_entity_id,
            kind: EntityKind::Body,
            proto: "crew_body".into(),
            pos,
            rotation: roll_range(&mut rng, 0, 3) as u8,
            locked: false,
            open: false,
            inventory: Vec::new(),
            tags: vec![format!("casualty_{b}")],
        });
        *next_entity_id += 1;
    }
    // Blood under bodies (mutable borrow dance: collect first).
    // (Decals painted by the caller via placed list would complicate; skip —
    // bodies read fine without decals on placeholder art.)
}

fn fracture_pass(
    master_seed: u64,
    layers: &mut [DeckLayer],
    entities: &mut Vec<EntitySpec>,
    next_entity_id: &mut u32,
    out: &mut DamageOutcome,
) {
    let mut rng = rng::stream(master_seed, "fracture", 0);
    let base = &layers[0];
    let w = base.width as i32;
    let h = base.height as i32;
    // Hull x-extent on deck 0.
    let (mut x0, mut x1) = (i32::MAX, i32::MIN);
    for y in 0..h {
        for x in 0..w {
            if base.floor_at(x, y) != FloorTile::Void {
                x0 = x0.min(x);
                x1 = x1.max(x);
            }
        }
    }
    if x1 - x0 < 20 {
        return; // too small to tear in half convincingly
    }

    // Jagged cut column with per-row jitter; retry for a balanced split.
    let gap = roll_range(&mut rng, 4, 7) as i32;
    let jitter: Vec<i32> = (0..h).map(|_| roll_range(&mut rng, -2, 2) as i32).collect();
    let mut cut_x = 0;
    let mut ok = false;
    for _attempt in 0..4 {
        cut_x = roll_range(
            &mut rng,
            (x0 + (x1 - x0) * 3 / 10) as i64,
            (x0 + (x1 - x0) * 7 / 10) as i64,
        ) as i32;
        // Balance check on deck 0 tile counts.
        let (mut left, mut right) = (0i64, 0i64);
        for y in 0..h {
            let cx = cut_x + jitter[y as usize];
            for x in 0..w {
                if layers[0].floor_at(x, y) == FloorTile::Void {
                    continue;
                }
                if x < cx {
                    left += 1;
                } else if x >= cx + gap {
                    right += 1;
                }
            }
        }
        let total = left + right;
        if total > 0 && left * 100 / total >= 25 && left * 100 / total <= 75 {
            ok = true;
            break;
        }
    }
    if !ok {
        return; // no balanced cut found; stay one heavily damaged piece
    }

    // Remove gap tiles on every deck; scar the torn edges.
    for layer in layers.iter_mut() {
        for y in 0..h {
            let cx = cut_x + jitter[y as usize];
            for x in cx..cx + gap {
                remove_tile(layer, x, y);
            }
            for (edge_x, wall_x) in [(cx - 1, cx), (cx + gap, cx + gap)] {
                if layer.floor_at(edge_x, y) != FloorTile::Void {
                    if let Some(i) = layer.idx(edge_x, y) {
                        layer.floor[i] = FloorTile::DamagedDeck;
                        layer.decal[i] = decal::SCORCH_LIGHT;
                    }
                    // Torn wall remnant on the gap-facing edge.
                    if let Some(i) = layer.idx(wall_x, y) {
                        let _ = i;
                    }
                    let _ = wall_x;
                }
            }
        }
    }
    // Entities inside the gap are gone.
    entities.retain(|e| {
        let cx = cut_x + jitter[e.pos.y.clamp(0, h - 1) as usize];
        e.pos.x < cx || e.pos.x >= cx + gap
    });

    // Bake the two pieces apart: right side drifts by (dx, dy).
    let dx = roll_range(&mut rng, 4, 8) as i32;
    let dy = roll_range(&mut rng, 0, 6) as i32;
    let new_w = (w + dx) as u16;
    let new_h = (h + dy) as u16;
    let mut right_rooms: BTreeSet<u16> = BTreeSet::new();
    for layer in layers.iter_mut() {
        let old = &*layer;
        let mut new_layer = DeckLayer::new(new_w, new_h);
        for y in 0..h {
            let cx = cut_x + jitter[y as usize];
            for x in 0..w {
                let Some(oi) = old.idx(x, y) else { continue };
                let is_right = x >= cx + gap;
                let (nx, ny) = if is_right { (x + dx, y + dy) } else { (x, y) };
                let Some(ni) = new_layer.idx(nx, ny) else {
                    continue;
                };
                new_layer.floor[ni] = old.floor[oi];
                new_layer.walls[ni] = old.walls[oi];
                new_layer.room_id[ni] = old.room_id[oi];
                new_layer.decal[ni] = old.decal[oi];
                if is_right && old.room_id[oi] != NO_ROOM {
                    right_rooms.insert(old.room_id[oi]);
                }
            }
        }
        *layer = new_layer;
    }
    for e in entities.iter_mut() {
        let cx = cut_x + jitter[e.pos.y.clamp(0, h - 1) as usize];
        if e.pos.x >= cx + gap {
            e.pos.x += dx;
            e.pos.y += dy;
        }
    }

    out.fractured = true;
    out.fragments = vec![
        ShipFragment {
            id: 0,
            rooms: Vec::new(),
            drift: (0, 0),
        },
        ShipFragment {
            id: 1,
            rooms: right_rooms.iter().copied().collect(),
            drift: (dx, dy),
        },
    ];
    out.events.push(DamageEvent {
        kind: DamageEventKind::StructuralFracture,
        deck: 0,
        origin: (cut_x, h / 2),
        radius: gap as u16,
    });

    // Debris field in and around the gap (grid-jittered scatter, only on
    // void tiles of the enlarged canvas).
    let field_x0 = (cut_x - 2).max(0);
    let field_x1 = (cut_x + gap + dx + 2).min(new_w as i32 - 1);
    let mut debris_rng = rng::stream(master_seed, "debris", 0);
    let cell = 3i32;
    let mut gy = 0;
    while gy < new_h as i32 {
        let mut gx = field_x0;
        while gx <= field_x1 {
            if roll_bp(&mut debris_rng, 3500) {
                let jx = roll_range(&mut debris_rng, 0, (cell - 1) as i64) as i32;
                let jy = roll_range(&mut debris_rng, 0, (cell - 1) as i64) as i32;
                let (px, py) = (
                    (gx + jx).min(new_w as i32 - 1),
                    (gy + jy).min(new_h as i32 - 1),
                );
                let on_void = layers.iter().all(|l| l.floor_at(px, py) == FloorTile::Void);
                if on_void {
                    let protos: [(&str, EntityKind, u32); 4] = [
                        ("hull_plate_debris", EntityKind::Debris, 50),
                        ("debris_small", EntityKind::Debris, 30),
                        ("cargo_crate", EntityKind::Container, 10),
                        ("crew_body", EntityKind::Body, 10),
                    ];
                    let weights: Vec<u32> = protos.iter().map(|p| p.2).collect();
                    if let Some(pi) = weighted_choice(&mut debris_rng, &weights) {
                        entities.push(EntitySpec {
                            id: *next_entity_id,
                            kind: protos[pi].1,
                            proto: protos[pi].0.into(),
                            pos: GridPos::new(px, py, 0),
                            rotation: roll_range(&mut debris_rng, 0, 3) as u8,
                            locked: false,
                            open: false,
                            inventory: Vec::new(),
                            tags: vec!["debris_field".into()],
                        });
                        *next_entity_id += 1;
                    }
                }
            }
            gx += cell;
        }
        gy += cell;
    }
    out.events.push(DamageEvent {
        kind: DamageEventKind::DebrisField,
        deck: 0,
        origin: ((field_x0 + field_x1) / 2, new_h as i32 / 2),
        radius: ((field_x1 - field_x0) / 2) as u16,
    });
}
