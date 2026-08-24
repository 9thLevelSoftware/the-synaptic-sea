//! Stage 5b: vertical shafts (ladders) connecting decks.
//!
//! Shaft positions are tiles that are interior on every deck, preferring
//! tiles that sit in corridors on as many decks as possible, spaced apart.
//! A ladder entity is placed per deck at the shaft tile; the room graph gets
//! `VerticalShaft` edges between the containing rooms of adjacent decks.

use crate::archetype::ShipArchetype;
use crate::model::NO_ROOM;
use crate::rng::roll_range;
use crate::stages::rooms::DeckRooms;
use rand_pcg::Pcg64;

#[derive(Clone, Copy, Debug)]
pub struct ShaftSpec {
    pub x: i32,
    pub y: i32,
}

pub fn choose_shafts(
    rng: &mut Pcg64,
    decks: &[DeckRooms],
    corridor_ids: &[u16],
    arch: &ShipArchetype,
) -> Vec<ShaftSpec> {
    if decks.len() < 2 {
        return Vec::new();
    }
    let want = roll_range(rng, arch.shafts.0.max(1) as i64, arch.shafts.1.max(1) as i64) as usize;
    let w = decks[0].width as i32;
    let h = decks[0].height as i32;

    // Score every tile present in a room on ALL decks.
    let mut candidates: Vec<(i64, i32, i32)> = Vec::new();
    for y in 0..h {
        for x in 0..w {
            let mut ok = true;
            let mut corridor_hits = 0i64;
            for (d, dr) in decks.iter().enumerate() {
                let id = dr.room_grid[y as usize * w as usize + x as usize];
                if id == NO_ROOM {
                    ok = false;
                    break;
                }
                if id == corridor_ids[d] && corridor_ids[d] != NO_ROOM {
                    corridor_hits += 1;
                }
            }
            if ok {
                candidates.push((corridor_hits, x, y));
            }
        }
    }
    // Highest corridor participation first; stable spatial tie-break.
    candidates.sort_by_key(|(c, x, y)| (i64::MAX - c, *y, *x));

    let min_sep = 8i32;
    let mut shafts: Vec<ShaftSpec> = Vec::new();
    for (_, x, y) in candidates {
        if shafts.len() >= want {
            break;
        }
        if shafts.iter().all(|s| (s.x - x).abs() + (s.y - y).abs() >= min_sep) {
            shafts.push(ShaftSpec { x, y });
        }
    }
    shafts
}
