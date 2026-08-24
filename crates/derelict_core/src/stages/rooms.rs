//! Stage 3: interior layout — BSP partition of each deck's hull interior
//! into room slots, then required/optional room-type assignment with
//! positional preference scoring and hard-constraint repair.

use crate::archetype::{ShipArchetype, SizePref};
use crate::model::RoomType;
use crate::rng::{roll_range, weighted_choice};
use crate::stages::hull::Mask;
use rand_pcg::Pcg64;

#[derive(Clone, Debug)]
pub struct RoomSlot {
    pub id: u16,
    pub kind: RoomType,
    /// Tile indices (row-major into the deck canvas).
    pub tiles: Vec<usize>,
    pub min: (i32, i32),
    pub max: (i32, i32),
    pub centroid: (i32, i32),
    pub touches_hull: bool,
}

#[derive(Clone, Debug)]
pub struct DeckRooms {
    pub width: u16,
    pub height: u16,
    /// Room id per tile (NO_ROOM = 0 outside hull).
    pub room_grid: Vec<u16>,
    pub rooms: Vec<RoomSlot>,
}

struct Rect {
    x0: i32,
    y0: i32,
    x1: i32, // inclusive
    y1: i32,
}

/// Recursively split `rect`; leaves are appended to `out`.
fn bsp_split(rng: &mut Pcg64, rect: Rect, min_dim: i32, max_dim: i32, out: &mut Vec<Rect>) {
    let w = rect.x1 - rect.x0 + 1;
    let h = rect.y1 - rect.y0 + 1;
    let must_split = w > max_dim || h > max_dim;
    let can_split_x = w >= min_dim * 2;
    let can_split_y = h >= min_dim * 2;
    if !must_split || (!can_split_x && !can_split_y) {
        out.push(rect);
        return;
    }
    // Prefer splitting the longer axis; randomize a bit when comparable.
    let split_x = if !can_split_y {
        true
    } else if !can_split_x {
        false
    } else if w * 3 > h * 4 {
        true
    } else if h * 3 > w * 4 {
        false
    } else {
        roll_range(rng, 0, 1) == 0
    };
    if split_x {
        let cut = roll_range(rng, (rect.x0 + min_dim) as i64, (rect.x1 - min_dim + 1) as i64) as i32;
        bsp_split(rng, Rect { x0: rect.x0, y0: rect.y0, x1: cut - 1, y1: rect.y1 }, min_dim, max_dim, out);
        bsp_split(rng, Rect { x0: cut, y0: rect.y0, x1: rect.x1, y1: rect.y1 }, min_dim, max_dim, out);
    } else {
        let cut = roll_range(rng, (rect.y0 + min_dim) as i64, (rect.y1 - min_dim + 1) as i64) as i32;
        bsp_split(rng, Rect { x0: rect.x0, y0: rect.y0, x1: rect.x1, y1: cut - 1 }, min_dim, max_dim, out);
        bsp_split(rng, Rect { x0: rect.x0, y0: cut, x1: rect.x1, y1: rect.y1 }, min_dim, max_dim, out);
    }
}

/// Partition one deck's hull mask into room slots (types unassigned:
/// `Compartment`). Room ids start at `first_id` and are contiguous.
pub fn partition_deck(
    rng: &mut Pcg64,
    mask: &Mask,
    arch: &ShipArchetype,
    first_id: u16,
) -> DeckRooms {
    let w = mask.width;
    let h = mask.height;
    // Hull bounding box.
    let (mut bx0, mut by0, mut bx1, mut by1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
    for y in 0..h as i32 {
        for x in 0..w as i32 {
            if mask.get(x, y) {
                bx0 = bx0.min(x);
                by0 = by0.min(y);
                bx1 = bx1.max(x);
                by1 = by1.max(y);
            }
        }
    }
    let min_dim = arch.min_room_dim as i32;
    let max_dim = (min_dim * 3).max(9);
    let mut leaves = Vec::new();
    bsp_split(rng, Rect { x0: bx0, y0: by0, x1: bx1, y1: by1 }, min_dim, max_dim, &mut leaves);

    // Per-tile slot labeling (leaf order = deterministic recursion order).
    let mut slot_of = vec![usize::MAX; w as usize * h as usize];
    for (si, r) in leaves.iter().enumerate() {
        for y in r.y0..=r.y1 {
            for x in r.x0..=r.x1 {
                if mask.get(x, y) {
                    slot_of[y as usize * w as usize + x as usize] = si;
                }
            }
        }
    }

    // Collect slot tiles; merge undersized slots into the neighboring slot
    // with the longest shared boundary (deterministic scan order).
    let n_slots = leaves.len();
    let mut tiles_of: Vec<Vec<usize>> = vec![Vec::new(); n_slots];
    for (i, s) in slot_of.iter().enumerate() {
        if *s != usize::MAX {
            tiles_of[*s].push(i);
        }
    }
    let min_area = (min_dim * min_dim) as usize;
    // Iterate until stable (small slot count, cheap).
    loop {
        let mut merged_any = false;
        for si in 0..n_slots {
            if tiles_of[si].is_empty() || tiles_of[si].len() >= min_area {
                continue;
            }
            // Count shared boundary with each neighbor slot.
            let mut shared: Vec<(usize, u32)> = Vec::new();
            for &i in &tiles_of[si] {
                let x = (i % w as usize) as i32;
                let y = (i / w as usize) as i32;
                for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                    if let Some(j) = mask.idx(x + dx, y + dy) {
                        let os = slot_of[j];
                        if os != usize::MAX && os != si {
                            match shared.iter_mut().find(|(s, _)| *s == os) {
                                Some((_, c)) => *c += 1,
                                None => shared.push((os, 1)),
                            }
                        }
                    }
                }
            }
            shared.sort_by_key(|(s, c)| (u32::MAX - *c, *s));
            if let Some((target, _)) = shared.first().copied() {
                let moved = std::mem::take(&mut tiles_of[si]);
                for &i in &moved {
                    slot_of[i] = target;
                }
                tiles_of[target].extend(moved);
                merged_any = true;
            }
        }
        if !merged_any {
            break;
        }
    }

    // Build RoomSlot records for non-empty slots.
    let mut rooms: Vec<RoomSlot> = Vec::new();
    let mut room_grid = vec![0u16; w as usize * h as usize];
    let mut next_id = first_id;
    for si in 0..n_slots {
        if tiles_of[si].is_empty() {
            continue;
        }
        let tiles = std::mem::take(&mut tiles_of[si]);
        let (mut x0, mut y0, mut x1, mut y1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        let (mut sx, mut sy) = (0i64, 0i64);
        let mut touches_hull = false;
        for &i in &tiles {
            let x = (i % w as usize) as i32;
            let y = (i / w as usize) as i32;
            x0 = x0.min(x);
            y0 = y0.min(y);
            x1 = x1.max(x);
            y1 = y1.max(y);
            sx += x as i64;
            sy += y as i64;
            if !touches_hull {
                for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                    if !mask.get(x + dx, y + dy) {
                        touches_hull = true;
                        break;
                    }
                }
            }
        }
        let n = tiles.len() as i64;
        for &i in &tiles {
            room_grid[i] = next_id;
        }
        rooms.push(RoomSlot {
            id: next_id,
            kind: RoomType::Compartment,
            tiles,
            min: (x0, y0),
            max: (x1, y1),
            centroid: ((sx / n) as i32, (sy / n) as i32),
            touches_hull,
        });
        next_id += 1;
    }

    DeckRooms { width: w, height: h, room_grid, rooms }
}

/// Assign room types to slots across all decks. Required rooms are placed by
/// positional-preference scoring (greedy, listed order); optional rooms fill
/// the rest by weighted roll; leftovers stay `Compartment`.
///
/// `deck_of_slot[i]` gives the deck index of `slots[i]`.
pub fn assign_rooms(
    rng: &mut Pcg64,
    decks: &mut [DeckRooms],
    arch: &ShipArchetype,
    hull_bbox_x: (i32, i32),
) {
    // Flatten mutable slot references deterministically: (deck, slot index).
    let mut all: Vec<(usize, usize)> = Vec::new();
    for (d, dr) in decks.iter().enumerate() {
        for (s, _) in dr.rooms.iter().enumerate() {
            all.push((d, s));
        }
    }
    let areas: Vec<usize> = all.iter().map(|(d, s)| decks[*d].rooms[*s].tiles.len()).collect();
    let mut sorted_areas = areas.clone();
    sorted_areas.sort_unstable();
    let median_area = sorted_areas[sorted_areas.len() / 2] as i64;
    let max_area = *sorted_areas.last().unwrap_or(&1) as i64;
    let span = (hull_bbox_x.1 - hull_bbox_x.0).max(1) as i64;

    let mut taken = vec![false; all.len()];

    // Bridge/engineering etc. prefer the main (bottom) deck; put required
    // rooms on deck 0 unless it runs out of slots.
    for req in &arch.required_rooms {
        let mut best: Option<(i64, usize)> = None;
        for (i, (d, s)) in all.iter().enumerate() {
            if taken[i] {
                continue;
            }
            let slot = &decks[*d].rooms[*s];
            // Airlocks must touch the hull boundary.
            if req.kind == RoomType::Airlock && !slot.touches_hull {
                continue;
            }
            let pos_bp = ((slot.centroid.0 - hull_bbox_x.0) as i64 * 200 / span) - 100; // -100..100
            let area = slot.tiles.len() as i64;
            let pos_score = -(req.bow_bias as i64 - pos_bp).abs() * 6;
            let size_score = match req.size_pref {
                SizePref::Largest => area * 900 / max_area.max(1),
                SizePref::Large => area * 500 / max_area.max(1),
                SizePref::Medium => -(area - median_area).abs() * 400 / median_area.max(1),
                SizePref::Small => -area * 500 / median_area.max(1),
            };
            let deck_score = if *d == 0 { 150 } else { 0 };
            let score = pos_score + size_score + deck_score;
            if best.map(|(b, _)| score > b).unwrap_or(true) {
                best = Some((score, i));
            }
        }
        if let Some((_, i)) = best {
            let (d, s) = all[i];
            decks[d].rooms[s].kind = req.kind;
            taken[i] = true;
        }
        // If no slot qualified (tiny hull), the requirement is dropped — the
        // archetype validator makes this effectively unreachable.
    }

    // Optional rooms: cap how many leftover slots get a named type so a
    // ship doesn't end up with four medbays; the rest stay generic
    // compartments.
    let opt_weights: Vec<u32> = arch.optional_rooms.iter().map(|(_, w)| *w).collect();
    let mut optional_budget = arch.required_rooms.len() / 2 + 2;
    // Specialty rooms appear at most once beyond the required list; bulk
    // rooms (storage/cargo/quarters) may repeat.
    let is_unique = |k: RoomType| {
        matches!(
            k,
            RoomType::Bridge
                | RoomType::Engineering
                | RoomType::Reactor
                | RoomType::Medbay
                | RoomType::Galley
                | RoomType::Armory
                | RoomType::Hydroponics
        )
    };
    let mut placed_unique: Vec<RoomType> = Vec::new();
    for (i, (d, s)) in all.iter().enumerate() {
        if taken[i] || optional_budget == 0 {
            continue;
        }
        if let Some(pick) = weighted_choice(rng, &opt_weights) {
            let kind = arch.optional_rooms[pick].0;
            if is_unique(kind) {
                if placed_unique.contains(&kind) {
                    continue;
                }
                placed_unique.push(kind);
            }
            if kind != RoomType::Compartment {
                optional_budget -= 1;
            }
            decks[*d].rooms[*s].kind = kind;
        }
    }
}
