//! Stage 1-2: hull silhouette + deck stacking.
//!
//! Mirrored polyomino growth: cellular accretion from a spine along the
//! ship's long axis, each added cell mirrored across the centerline (with a
//! small asymmetry chance), growth weighted toward the interior of an
//! elliptical envelope. Pure integer math.

use crate::archetype::ShipArchetype;
use crate::model::TileCoord;
use crate::rng::{self, isqrt, roll_bp, roll_range, weighted_choice};
use rand_pcg::Pcg64;

/// Margin of empty tiles around the hull on the canvas (room for hull walls
/// on outer edges and CA damage erosion).
pub const CANVAS_MARGIN: i32 = 2;

#[derive(Clone, Debug)]
pub struct Mask {
    pub width: u16,
    pub height: u16,
    pub cells: Vec<bool>,
}

impl Mask {
    pub fn new(width: u16, height: u16) -> Self {
        Self {
            width,
            height,
            cells: vec![false; width as usize * height as usize],
        }
    }

    #[inline]
    pub fn idx(&self, x: TileCoord, y: TileCoord) -> Option<usize> {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            None
        } else {
            Some(y as usize * self.width as usize + x as usize)
        }
    }

    #[inline]
    pub fn get(&self, x: TileCoord, y: TileCoord) -> bool {
        self.idx(x, y).map(|i| self.cells[i]).unwrap_or(false)
    }

    #[inline]
    pub fn set(&mut self, x: TileCoord, y: TileCoord, v: bool) {
        if let Some(i) = self.idx(x, y) {
            self.cells[i] = v;
        }
    }

    pub fn count(&self) -> usize {
        self.cells.iter().filter(|c| **c).count()
    }

    pub fn neighbors4(&self, x: TileCoord, y: TileCoord) -> u8 {
        let mut n = 0;
        for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
            if self.get(x + dx, y + dy) {
                n += 1;
            }
        }
        n
    }

    /// 4-neighbor morphological erosion (border cells always erode).
    pub fn eroded(&self) -> Mask {
        let mut out = Mask::new(self.width, self.height);
        for y in 0..self.height as i32 {
            for x in 0..self.width as i32 {
                if self.get(x, y) && self.neighbors4(x, y) == 4 {
                    out.set(x, y, true);
                }
            }
        }
        out
    }

    /// Largest 4-connected component; everything else cleared.
    pub fn largest_component(&self) -> Mask {
        let mut label = vec![0u32; self.cells.len()];
        let mut sizes: Vec<u32> = vec![0]; // sizes[0] unused
        let mut next = 1u32;
        for start in 0..self.cells.len() {
            if !self.cells[start] || label[start] != 0 {
                continue;
            }
            let mut stack = vec![start];
            label[start] = next;
            let mut size = 0u32;
            while let Some(i) = stack.pop() {
                size += 1;
                let x = (i % self.width as usize) as i32;
                let y = (i / self.width as usize) as i32;
                for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
                    if let Some(j) = self.idx(x + dx, y + dy) {
                        if self.cells[j] && label[j] == 0 {
                            label[j] = next;
                            stack.push(j);
                        }
                    }
                }
            }
            sizes.push(size);
            next += 1;
        }
        let best = (1..sizes.len()).max_by_key(|i| sizes[*i]).unwrap_or(0) as u32;
        let mut out = Mask::new(self.width, self.height);
        for (cell, l) in out.cells.iter_mut().zip(label.iter()) {
            *cell = *l == best && best != 0;
        }
        out
    }
}

#[derive(Clone, Debug)]
pub struct HullPlan {
    pub width: u16,
    pub height: u16,
    /// Bottom deck first; upper decks are eroded subsets of the deck below.
    pub deck_masks: Vec<Mask>,
    /// Hull length actually rolled (info for later stages).
    pub length: u16,
    pub beam: u16,
}

/// Half-beam of the elliptical envelope at distance `dx` from center.
/// Integer: hb = (B/2) * sqrt(a^2 - dx^2) / a, with a = L/2.
fn half_beam(dx: i64, half_len: i64, half_beam_max: i64) -> i64 {
    if dx.abs() >= half_len {
        return 0;
    }
    isqrt(half_beam_max * half_beam_max * (half_len * half_len - dx * dx)) / half_len
}

pub fn generate_hull(rng_h: &mut Pcg64, arch: &ShipArchetype, deck_count: u8) -> HullPlan {
    let length = roll_range(rng_h, arch.length.0 as i64, arch.length.1 as i64);
    let beam = {
        let b = roll_range(rng_h, arch.beam.0 as i64, arch.beam.1 as i64);
        b.min(length - 2).max(4)
    };
    let width = (length + CANVAS_MARGIN as i64 * 2) as u16;
    let height = (beam + CANVAS_MARGIN as i64 * 2) as u16;
    let cx0 = CANVAS_MARGIN as i64; // hull x extent: [cx0, cx0+length)
    let cy = CANVAS_MARGIN as i64 + beam / 2; // centerline row
    let half_len = length / 2;
    let hb_max = beam / 2;
    let center_x = cx0 + half_len;

    let mut mask = Mask::new(width, height);

    // Seed the spine along the centerline where the envelope is >= 1 wide.
    for x in cx0..cx0 + length {
        let dx = x - center_x;
        if half_beam(dx, half_len, hb_max) >= 1 || dx.abs() < half_len {
            mask.set(x as i32, cy as i32, true);
        }
    }

    // Envelope area (integer sum of widths) and fill target.
    let mut envelope_area: i64 = 0;
    for x in cx0..cx0 + length {
        let hb = half_beam(x - center_x, half_len, hb_max);
        envelope_area += hb * 2 + 1;
    }
    let target = (envelope_area * arch.hull_fill_bp as i64 / 10_000).max(length) as usize;

    // Weight of a candidate cell: envelope depth (0 outside).
    let weight_of = |x: i64, y: i64| -> u32 {
        let hb = half_beam(x - center_x, half_len, hb_max);
        let dy = (y - cy).abs();
        if dy > hb {
            0
        } else {
            (hb - dy + 1) as u32
        }
    };

    // Frontier accretion.
    let mut frontier: Vec<(i64, i64)> = Vec::new();
    let push_neighbors = |mask: &Mask, frontier: &mut Vec<(i64, i64)>, x: i64, y: i64| {
        for (dx, dy) in [(0i64, -1i64), (0, 1), (-1, 0), (1, 0)] {
            let (nx, ny) = (x + dx, y + dy);
            if !mask.get(nx as i32, ny as i32) && weight_of(nx, ny) > 0 {
                frontier.push((nx, ny));
            }
        }
    };
    for x in cx0..cx0 + length {
        if mask.get(x as i32, cy as i32) {
            push_neighbors(&mask, &mut frontier, x, cy);
        }
    }

    let mut count = mask.count();
    let mut weights: Vec<u32> = Vec::new();
    while count < target && !frontier.is_empty() {
        // Drop stale entries (already filled) lazily.
        frontier.retain(|(x, y)| !mask.get(*x as i32, *y as i32));
        if frontier.is_empty() {
            break;
        }
        weights.clear();
        weights.extend(frontier.iter().map(|(x, y)| weight_of(*x, *y)));
        let Some(pick) = weighted_choice(rng_h, &weights) else {
            break;
        };
        let (x, y) = frontier.swap_remove(pick);
        mask.set(x as i32, y as i32, true);
        count += 1;
        push_neighbors(&mask, &mut frontier, x, y);
        // Mirror across the centerline unless this step rolls asymmetric.
        let my = 2 * cy - y;
        if my != y
            && !roll_bp(rng_h, arch.asymmetry_bp as u32)
            && !mask.get(x as i32, my as i32)
            && weight_of(x, my) > 0
        {
            mask.set(x as i32, my as i32, true);
            count += 1;
            push_neighbors(&mask, &mut frontier, x, my);
        }
    }

    // Fill enclosed holes: anything not flood-reachable from the canvas
    // border through empty cells becomes hull.
    let mut outside = Mask::new(width, height);
    let mut stack: Vec<(i32, i32)> = Vec::new();
    for x in 0..width as i32 {
        for y in [0, height as i32 - 1] {
            if !mask.get(x, y) && !outside.get(x, y) {
                outside.set(x, y, true);
                stack.push((x, y));
            }
        }
    }
    for y in 0..height as i32 {
        for x in [0, width as i32 - 1] {
            if !mask.get(x, y) && !outside.get(x, y) {
                outside.set(x, y, true);
                stack.push((x, y));
            }
        }
    }
    while let Some((x, y)) = stack.pop() {
        for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)] {
            let (nx, ny) = (x + dx, y + dy);
            if nx >= 0
                && ny >= 0
                && nx < width as i32
                && ny < height as i32
                && !mask.get(nx, ny)
                && !outside.get(nx, ny)
            {
                outside.set(nx, ny, true);
                stack.push((nx, ny));
            }
        }
    }
    for y in 0..height as i32 {
        for x in 0..width as i32 {
            if !mask.get(x, y) && !outside.get(x, y) {
                mask.set(x, y, true);
            }
        }
    }

    // Prune 1-neighbor nubs (a couple of passes) for cleaner walls.
    for _ in 0..2 {
        let mut prune: Vec<(i32, i32)> = Vec::new();
        for y in 0..height as i32 {
            for x in 0..width as i32 {
                if mask.get(x, y) && mask.neighbors4(x, y) <= 1 {
                    prune.push((x, y));
                }
            }
        }
        if prune.is_empty() {
            break;
        }
        for (x, y) in prune {
            mask.set(x, y, false);
        }
    }
    let mask = mask.largest_component();

    // Upper decks: erode the deck below `deck_erosion` times; drop decks
    // that fall under a viable area.
    let min_deck_area = (arch.min_room_dim as usize).pow(2) * 4;
    let mut deck_masks = vec![mask];
    for _ in 1..deck_count {
        let mut m = deck_masks.last().unwrap().clone();
        for _ in 0..arch.deck_erosion {
            m = m.eroded();
        }
        m = m.largest_component();
        if m.count() < min_deck_area {
            break;
        }
        deck_masks.push(m);
    }

    HullPlan {
        width,
        height,
        deck_masks,
        length: length as u16,
        beam: beam as u16,
    }
}

/// Derive the site seed for a derelict from world seed + world position.
/// Discovery-order independent: any co-op peer computes the same value.
pub fn derive_site_seed(world_seed: u64, world_x: i64, world_y: i64) -> u64 {
    rng::key(
        world_seed,
        "derelict_site",
        (world_x as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ (world_y as u64),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::archetype::GenData;
    use crate::rng::stream;

    #[test]
    fn hull_is_connected_and_sane() {
        let data = GenData::default_bundle().unwrap();
        for (id, arch) in &data.archetypes {
            for seed in 0..20u64 {
                let mut r = stream(seed, "hull", 0);
                let plan = generate_hull(&mut r, arch, arch.decks.1);
                let m = &plan.deck_masks[0];
                assert!(
                    m.count() >= (arch.length.0 as usize * arch.beam.0 as usize) / 3,
                    "{id} seed {seed}: hull too small: {}",
                    m.count()
                );
                // Connectivity: largest component == whole mask.
                assert_eq!(m.count(), m.largest_component().count(), "{id} seed {seed}");
                // Decks nest.
                for d in 1..plan.deck_masks.len() {
                    for i in 0..m.cells.len() {
                        if plan.deck_masks[d].cells[i] {
                            assert!(
                                plan.deck_masks[d - 1].cells[i],
                                "{id} seed {seed}: deck {d} not nested"
                            );
                        }
                    }
                }
            }
        }
    }
}
