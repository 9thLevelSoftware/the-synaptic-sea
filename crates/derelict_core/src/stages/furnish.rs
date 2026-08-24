//! Stage 6: furnishing — doors become entities, rooms get furniture,
//! containers, and terminals per data-driven rules.

use crate::archetype::{FurnishingRules, Placement};
use crate::model::{EntityKind, EntitySpec, GridPos, RoomType, Side, WallEdge};
use crate::rng::{self, roll_bp, roll_range, shuffle};
use crate::stages::corridors::DoorSpec;
use crate::stages::rooms::DeckRooms;
use crate::model::DeckLayer;

pub struct Furnisher<'a> {
    pub master_seed: u64,
    pub rules: &'a FurnishingRules,
    pub next_entity_id: u32,
}

impl<'a> Furnisher<'a> {
    /// Create door entities from door specs. Deterministic order: specs are
    /// created deck-by-deck in stable order already.
    pub fn create_doors(
        &mut self,
        specs: &[DoorSpec],
        room_kind_of: impl Fn(u16) -> Option<RoomType>,
        out: &mut Vec<EntitySpec>,
    ) {
        for spec in specs {
            let mut rng = rng::stream(self.master_seed, "door", self.next_entity_id as u64);
            // Lock chance: strongest of the two rooms' lock policies.
            let lock_bp = [spec.room_a, spec.room_b]
                .iter()
                .filter_map(|id| room_kind_of(*id))
                .filter_map(|k| self.rules.door_lock_bp.get(&k).copied())
                .max()
                .unwrap_or(0);
            let locked = !spec.exterior && roll_bp(&mut rng, lock_bp as u32);
            let open = !locked && roll_bp(&mut rng, 2500);
            out.push(EntitySpec {
                id: self.next_entity_id,
                kind: EntityKind::Door,
                proto: if spec.exterior { "airlock_door".into() } else { "door".into() },
                pos: GridPos::new(spec.x, spec.y, spec.deck),
                rotation: if spec.north { 0 } else { 1 },
                locked,
                open,
                inventory: Vec::new(),
                tags: Vec::new(),
            });
            self.next_entity_id += 1;
        }
    }

    /// Furnish all rooms of one deck. `occupied` is the shared per-deck
    /// entity occupancy grid (row-major bools).
    pub fn furnish_deck(
        &mut self,
        dr: &DeckRooms,
        layer: &DeckLayer,
        deck: u8,
        occupied: &mut [bool],
        out: &mut Vec<EntitySpec>,
    ) {
        let w = dr.width as i32;
        // Tiles adjacent to a doorway must stay clear.
        let mut door_clear = vec![false; dr.room_grid.len()];
        for y in 0..dr.height as i32 {
            for x in 0..w {
                for side in Side::ALL {
                    if layer.edge(x, y, side) == WallEdge::Doorway {
                        door_clear[(y * w + x) as usize] = true;
                    }
                }
            }
        }

        for room in &dr.rooms {
            let Some(rules) = self.rules.rules.get(&room.kind) else { continue };
            let mut rng = rng::stream(self.master_seed, "furnish", room.id as u64);
            for rule in rules {
                let count = roll_range(&mut rng, rule.count.0 as i64, rule.count.1 as i64);
                if count == 0 {
                    continue;
                }
                let mut candidates = candidate_tiles(dr, layer, room.tiles.as_slice(), rule.place);
                match rule.place {
                    Placement::Center => {
                        candidates.sort_by_key(|&i| {
                            let x = (i as i32) % w;
                            let y = (i as i32) / w;
                            let d = (x - room.centroid.0).abs() + (y - room.centroid.1).abs();
                            (d, i)
                        });
                    }
                    _ => shuffle(&mut rng, &mut candidates),
                }
                let mut placed = 0;
                for &i in &candidates {
                    if placed >= count {
                        break;
                    }
                    if occupied[i] || door_clear[i] {
                        continue;
                    }
                    occupied[i] = true;
                    let x = (i as i32) % w;
                    let y = (i as i32) / w;
                    let locked = rule.kind == EntityKind::Container && roll_bp(&mut rng, rule.lock_bp as u32);
                    out.push(EntitySpec {
                        id: self.next_entity_id,
                        kind: rule.kind,
                        proto: rule.proto.clone(),
                        pos: GridPos::new(x, y, deck),
                        rotation: roll_range(&mut rng, 0, 3) as u8,
                        locked,
                        open: false,
                        inventory: Vec::new(),
                        tags: Vec::new(),
                    });
                    self.next_entity_id += 1;
                    placed += 1;
                }
            }
        }
    }
}

fn candidate_tiles(
    dr: &DeckRooms,
    layer: &DeckLayer,
    tiles: &[usize],
    place: Placement,
) -> Vec<usize> {
    let w = dr.width as i32;
    let wall_count = |x: i32, y: i32| -> u8 {
        let mut n = 0;
        for side in Side::ALL {
            if layer.edge(x, y, side).blocks() {
                n += 1;
            }
        }
        n
    };
    tiles
        .iter()
        .copied()
        .filter(|&i| {
            let x = (i as i32) % w;
            let y = (i as i32) / w;
            match place {
                Placement::WallAdjacent => wall_count(x, y) >= 1,
                Placement::Corner => wall_count(x, y) >= 2,
                Placement::Center => wall_count(x, y) == 0,
                Placement::Free => true,
            }
        })
        .collect()
}
