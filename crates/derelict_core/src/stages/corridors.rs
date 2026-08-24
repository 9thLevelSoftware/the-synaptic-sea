//! Stage 4-5: corridor carving, wall stamping, door/airlock placement.
//!
//! Corridors: minimum spanning tree (Prim, stable tie-breaks) over room
//! centroids plus a seeded fraction of loop-back edges; each edge carved as
//! an L-path when it fits inside the hull, BFS path otherwise. Carved tiles
//! are reassigned to a per-deck Corridor room; rooms split by carving are
//! relabeled. Then walls are stamped on tile edges and every room gets door
//! connectivity (guaranteed by a BFS repair pass over the room adjacency
//! graph). Airlocks get an exterior door on the hull boundary.

use crate::archetype::ShipArchetype;
use crate::model::{RoomType, NO_ROOM};
use crate::rng::{roll_bp, roll_range};
use crate::stages::hull::Mask;
use crate::stages::rooms::{DeckRooms, RoomSlot};
use rand_pcg::Pcg64;

#[derive(Clone, Debug)]
pub struct DoorSpec {
    pub deck: u8,
    /// Door sits on an edge of tile (x, y): its north edge if `north`, else
    /// its west edge.
    pub x: i32,
    pub y: i32,
    pub north: bool,
    pub room_a: u16,
    pub room_b: u16,
    /// Exterior airlock door (room_b == NO_ROOM).
    pub exterior: bool,
}

pub struct CorridorResult {
    /// Corridor room id per deck (NO_ROOM if the deck needed none).
    pub corridor_ids: Vec<u16>,
    pub door_specs: Vec<DoorSpec>,
}

fn manhattan(a: (i32, i32), b: (i32, i32)) -> i64 {
    ((a.0 - b.0).abs() + (a.1 - b.1).abs()) as i64
}

/// L-path between two points: horizontal-then-vertical or vertical-then-
/// horizontal. Returns None if any tile leaves the mask.
fn l_path(mask: &Mask, a: (i32, i32), b: (i32, i32), h_first: bool) -> Option<Vec<(i32, i32)>> {
    let mut path = Vec::new();
    let push = |x: i32, y: i32, path: &mut Vec<(i32, i32)>| -> bool {
        if !mask.get(x, y) {
            return false;
        }
        path.push((x, y));
        true
    };
    let (corner_x, corner_y) = if h_first { (b.0, a.1) } else { (a.0, b.1) };
    let mut x = a.0;
    let mut y = a.1;
    if !push(x, y, &mut path) {
        return None;
    }
    while (x, y) != (corner_x, corner_y) {
        if x != corner_x {
            x += (corner_x - x).signum();
        } else {
            y += (corner_y - y).signum();
        }
        if !push(x, y, &mut path) {
            return None;
        }
    }
    while (x, y) != b {
        if x != b.0 {
            x += (b.0 - x).signum();
        } else {
            y += (b.1 - y).signum();
        }
        if !push(x, y, &mut path) {
            return None;
        }
    }
    Some(path)
}

/// BFS shortest path inside the mask (deterministic neighbor order).
fn bfs_path(mask: &Mask, a: (i32, i32), b: (i32, i32)) -> Option<Vec<(i32, i32)>> {
    let w = mask.width as usize;
    let n = w * mask.height as usize;
    let idx = |p: (i32, i32)| p.1 as usize * w + p.0 as usize;
    let mut prev = vec![usize::MAX; n];
    let mut visited = vec![false; n];
    let mut queue = std::collections::VecDeque::new();
    if !mask.get(a.0, a.1) || !mask.get(b.0, b.1) {
        return None;
    }
    visited[idx(a)] = true;
    queue.push_back(a);
    while let Some(p) = queue.pop_front() {
        if p == b {
            let mut path = vec![b];
            let mut cur = idx(b);
            while prev[cur] != usize::MAX {
                cur = prev[cur];
                path.push(((cur % w) as i32, (cur / w) as i32));
            }
            path.reverse();
            return Some(path);
        }
        for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
            let np = (p.0 + dx, p.1 + dy);
            if mask.get(np.0, np.1) && !visited[idx(np)] {
                visited[idx(np)] = true;
                prev[idx(np)] = idx(p);
                queue.push_back(np);
            }
        }
    }
    None
}

/// Carve corridors on one deck; returns the corridor room id (or NO_ROOM).
/// `next_room_id` is advanced for any fragment rooms created by relabeling.
pub fn carve_deck_corridors(
    rng: &mut Pcg64,
    dr: &mut DeckRooms,
    mask: &Mask,
    arch: &ShipArchetype,
    next_room_id: &mut u16,
) -> u16 {
    if dr.rooms.len() < 2 {
        return NO_ROOM;
    }
    let corridor_id = *next_room_id;
    *next_room_id += 1;

    // MST (Prim) over room centroids.
    let n = dr.rooms.len();
    let cents: Vec<(i32, i32)> = dr.rooms.iter().map(|r| r.centroid).collect();
    let mut in_tree = vec![false; n];
    let mut edges: Vec<(usize, usize)> = Vec::new();
    in_tree[0] = true;
    for _ in 1..n {
        let mut best: Option<(i64, usize, usize)> = None;
        for i in 0..n {
            if !in_tree[i] {
                continue;
            }
            for j in 0..n {
                if in_tree[j] {
                    continue;
                }
                let d = manhattan(cents[i], cents[j]);
                if best.map(|(bd, bi, bj)| (d, i, j) < (bd, bi, bj)).unwrap_or(true) {
                    best = Some((d, i, j));
                }
            }
        }
        let (_, i, j) = best.unwrap();
        in_tree[j] = true;
        edges.push((i, j));
    }

    // Loop-back edges: short non-MST pairs, seeded roll each.
    let avg_len = edges.iter().map(|(a, b)| manhattan(cents[*a], cents[*b])).sum::<i64>()
        / edges.len().max(1) as i64;
    let mut extra: Vec<(i64, usize, usize)> = Vec::new();
    for i in 0..n {
        for j in (i + 1)..n {
            if edges.contains(&(i, j)) || edges.contains(&(j, i)) {
                continue;
            }
            let d = manhattan(cents[i], cents[j]);
            if d <= avg_len * 2 {
                extra.push((d, i, j));
            }
        }
    }
    extra.sort();
    let max_extra = n / 3;
    let mut added = 0;
    for (_, i, j) in extra {
        if added >= max_extra {
            break;
        }
        if roll_bp(rng, arch.corridor_loop_bp as u32) {
            edges.push((i, j));
            added += 1;
        }
    }

    // Carve each edge.
    let wide = arch.min_room_dim >= 4;
    let mut carved: Vec<usize> = Vec::new();
    let w = dr.width as usize;
    for (a, b) in edges {
        let pa = cents[a];
        let pb = cents[b];
        let h_first = roll_range(rng, 0, 1) == 0;
        let path = l_path(mask, pa, pb, h_first)
            .or_else(|| l_path(mask, pa, pb, !h_first))
            .or_else(|| bfs_path(mask, pa, pb));
        let Some(path) = path else { continue };
        for (k, &(x, y)) in path.iter().enumerate() {
            carved.push(y as usize * w + x as usize);
            if wide {
                // Widen perpendicular to travel direction.
                let dir = if k + 1 < path.len() {
                    (path[k + 1].0 - x, path[k + 1].1 - y)
                } else if k > 0 {
                    (x - path[k - 1].0, y - path[k - 1].1)
                } else {
                    (1, 0)
                };
                let (px, py) = if dir.0 != 0 { (x, y + 1) } else { (x + 1, y) };
                if mask.get(px, py) {
                    carved.push(py as usize * w + px as usize);
                }
            }
        }
    }
    if carved.is_empty() {
        *next_room_id -= 1;
        return NO_ROOM;
    }
    carved.sort_unstable();
    carved.dedup();
    for &i in &carved {
        dr.room_grid[i] = corridor_id;
    }

    // Rebuild each room's tile list; relabel disconnected fragments.
    let min_frag = ((arch.min_room_dim as usize).pow(2) / 2).max(2);
    let mut new_rooms: Vec<RoomSlot> = Vec::new();
    let old_rooms = std::mem::take(&mut dr.rooms);
    for room in old_rooms {
        let tiles: Vec<usize> =
            room.tiles.iter().copied().filter(|i| dr.room_grid[*i] == room.id).collect();
        if tiles.is_empty() {
            continue;
        }
        // Connected components of remaining tiles.
        let tile_set: std::collections::BTreeSet<usize> = tiles.iter().copied().collect();
        let mut unvisited = tile_set.clone();
        let mut comps: Vec<Vec<usize>> = Vec::new();
        while let Some(&start) = unvisited.iter().next() {
            unvisited.remove(&start);
            let mut comp = vec![start];
            let mut stack = vec![start];
            while let Some(i) = stack.pop() {
                let x = (i % w) as i32;
                let y = (i / w) as i32;
                for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                    if let Some(j) = mask.idx(x + dx, y + dy) {
                        if unvisited.remove(&j) {
                            comp.push(j);
                            stack.push(j);
                        }
                    }
                }
            }
            comps.push(comp);
        }
        comps.sort_by_key(|c| usize::MAX - c.len());
        for (ci, comp) in comps.into_iter().enumerate() {
            if ci > 0 && comp.len() < min_frag {
                // Absorb sliver into the corridor.
                for &i in &comp {
                    dr.room_grid[i] = corridor_id;
                }
                continue;
            }
            let id = if ci == 0 {
                room.id
            } else {
                let id = *next_room_id;
                *next_room_id += 1;
                id
            };
            let kind = if ci == 0 { room.kind } else { RoomType::Compartment };
            for &i in &comp {
                dr.room_grid[i] = id;
            }
            new_rooms.push(build_slot(id, kind, comp, w, mask));
        }
    }
    // Corridor room record.
    let corridor_tiles: Vec<usize> =
        (0..dr.room_grid.len()).filter(|i| dr.room_grid[*i] == corridor_id).collect();
    new_rooms.push(build_slot(corridor_id, RoomType::Corridor, corridor_tiles, w, mask));
    new_rooms.sort_by_key(|r| r.id);
    dr.rooms = new_rooms;
    corridor_id
}

fn build_slot(id: u16, kind: RoomType, tiles: Vec<usize>, w: usize, mask: &Mask) -> RoomSlot {
    let (mut x0, mut y0, mut x1, mut y1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
    let (mut sx, mut sy) = (0i64, 0i64);
    let mut touches_hull = false;
    for &i in &tiles {
        let x = (i % w) as i32;
        let y = (i / w) as i32;
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
    let n = tiles.len().max(1) as i64;
    RoomSlot {
        id,
        kind,
        tiles,
        min: (x0, y0),
        max: (x1, y1),
        centroid: ((sx / n) as i32, (sy / n) as i32),
        touches_hull,
    }
}

/// A shared wall edge between two rooms (or a room and the void).
#[derive(Clone, Copy, Debug)]
struct SharedEdge {
    x: i32,
    y: i32,
    north: bool,
}

/// All wall edges between room `a` and room `b` (b may be NO_ROOM for hull
/// boundary), in deterministic row-major order.
fn shared_edges(dr: &DeckRooms, a: u16, b: u16) -> Vec<SharedEdge> {
    let w = dr.width as i32;
    let h = dr.height as i32;
    let mut out = Vec::new();
    for y in 0..h {
        for x in 0..w {
            let here = dr.room_grid[y as usize * w as usize + x as usize];
            if here != a {
                continue;
            }
            // North neighbor.
            let up = if y > 0 { dr.room_grid[(y - 1) as usize * w as usize + x as usize] } else { NO_ROOM };
            if up == b {
                out.push(SharedEdge { x, y, north: true });
            }
            // West neighbor.
            let left = if x > 0 { dr.room_grid[y as usize * w as usize + (x - 1) as usize] } else { NO_ROOM };
            if left == b {
                out.push(SharedEdge { x, y, north: false });
            }
            // South neighbor: edge stored as north edge of (x, y+1).
            let down = if y + 1 < h { dr.room_grid[(y + 1) as usize * w as usize + x as usize] } else { NO_ROOM };
            if down == b {
                out.push(SharedEdge { x, y: y + 1, north: true });
            }
            // East neighbor: edge stored as west edge of (x+1, y).
            let right = if x + 1 < w { dr.room_grid[y as usize * w as usize + (x + 1) as usize] } else { NO_ROOM };
            if right == b {
                out.push(SharedEdge { x: x + 1, y, north: false });
            }
        }
    }
    // Deduplicate (each pair edge found from both sides when a != b).
    out.sort_by_key(|e| (e.y, e.x, e.north));
    out.dedup_by_key(|e| (e.y, e.x, e.north));
    out
}

/// Place doors on one deck. Every non-corridor room ends reachable from the
/// corridor (or from any room, on corridor-less decks). Returns door specs;
/// caller stamps `Doorway` edges into the DeckLayer afterwards.
pub fn place_doors(
    rng: &mut Pcg64,
    dr: &DeckRooms,
    deck: u8,
    corridor_id: u16,
) -> Vec<DoorSpec> {
    let mut specs: Vec<DoorSpec> = Vec::new();
    let mut connected: std::collections::BTreeSet<u16> = std::collections::BTreeSet::new();
    if corridor_id != NO_ROOM {
        connected.insert(corridor_id);
    }

    let add_door = |specs: &mut Vec<DoorSpec>, edges: &[SharedEdge], a: u16, b: u16, exterior: bool| {
        if edges.is_empty() {
            return false;
        }
        let e = edges[edges.len() / 2];
        specs.push(DoorSpec { deck, x: e.x, y: e.y, north: e.north, room_a: a, room_b: b, exterior });
        true
    };

    // Pass 1: rooms adjacent to the corridor get 1-2 doors to it.
    if corridor_id != NO_ROOM {
        for room in &dr.rooms {
            if room.id == corridor_id {
                continue;
            }
            let edges = shared_edges(dr, room.id, corridor_id);
            if edges.is_empty() {
                continue;
            }
            add_door(&mut specs, &edges, room.id, corridor_id, false);
            connected.insert(room.id);
            // Big rooms sometimes get a second corridor door far from the first.
            if room.tiles.len() > 60 && edges.len() > 8 && roll_bp(rng, 5000) {
                let far = [edges[0], edges[edges.len() - 1]];
                let e = if roll_range(rng, 0, 1) == 0 { far[0] } else { far[1] };
                specs.push(DoorSpec { deck, x: e.x, y: e.y, north: e.north, room_a: room.id, room_b: corridor_id, exterior: false });
            }
        }
    } else if let Some(first) = dr.rooms.first() {
        connected.insert(first.id);
    }

    // Pass 2: BFS repair — connect unreached rooms through already-reached
    // neighbors until everything is reachable.
    loop {
        let unreached: Vec<&RoomSlot> =
            dr.rooms.iter().filter(|r| !connected.contains(&r.id)).collect();
        if unreached.is_empty() {
            break;
        }
        let mut progressed = false;
        for room in &unreached {
            // Find a reached neighbor with a shared wall (deterministic order).
            let mut done = false;
            for other in &dr.rooms {
                if !connected.contains(&other.id) || other.id == room.id {
                    continue;
                }
                let edges = shared_edges(dr, room.id, other.id);
                if add_door(&mut specs, &edges, room.id, other.id, false) {
                    connected.insert(room.id);
                    progressed = true;
                    done = true;
                    break;
                }
            }
            if done {
                continue;
            }
        }
        if !progressed {
            // Isolated island (should not happen on a connected hull) —
            // give up rather than loop forever; invariant tests will flag it.
            break;
        }
    }

    // Pass 3: exterior airlock doors on the hull boundary.
    for room in &dr.rooms {
        if room.kind != RoomType::Airlock {
            continue;
        }
        let edges = shared_edges(dr, room.id, NO_ROOM);
        add_door(&mut specs, &edges, room.id, NO_ROOM, true);
    }

    specs
}
