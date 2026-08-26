//! Raster projection: the canonical StructuralPlan → v1-shaped `DeckLayer`
//! tile arrays for the 2D isometric debug renderer. Pure, stateless, and
//! never authoritative — regenerate it whenever the plan changes.

use crate::model::{DeckLayer, FloorTile, WallEdge};
use crate::role::Role;
use crate::structural::plan::{DamageVariant, Dir, EdgeKind, RoomId, StructuralPlan, Topology};
use std::collections::BTreeMap;

pub fn project_to_raster(topology: &Topology, plan: &StructuralPlan) -> Vec<DeckLayer> {
    let role_of: BTreeMap<RoomId, Role> = topology.rooms.iter().map(|r| (r.id, r.role)).collect();
    let mut deck_count: usize = 0;
    let (mut max_x, mut max_y) = (0i32, 0i32);
    for rec in plan.occupancy.values() {
        deck_count = deck_count.max(rec.cell.deck as usize + 1);
        max_x = max_x.max(rec.cell.x);
        max_y = max_y.max(rec.cell.y);
    }
    if deck_count == 0 {
        return Vec::new();
    }
    let w = (max_x + 2) as u16;
    let h = (max_y + 2) as u16;
    let mut layers: Vec<DeckLayer> = (0..deck_count).map(|_| DeckLayer::new(w, h)).collect();

    for rec in plan.occupancy.values() {
        let layer = &mut layers[rec.cell.deck as usize];
        let Some(i) = layer.idx(rec.cell.x, rec.cell.y) else {
            continue;
        };
        let connective = role_of
            .get(&rec.room_id)
            .map(|r| r.is_connective())
            .unwrap_or(false);
        layer.floor[i] = if rec.variant != DamageVariant::Intact {
            FloorTile::DamagedDeck
        } else if connective {
            FloorTile::Grated
        } else {
            FloorTile::Deck
        };
        layer.room_id[i] = rec.room_id;
        layer.decal[i] = rec.decal;
    }

    for edge in plan.edges.values() {
        let wall = match edge.kind {
            EdgeKind::Open => continue,
            EdgeKind::Solid => {
                if edge.exterior {
                    WallEdge::Hull
                } else {
                    WallEdge::Interior
                }
            }
            EdgeKind::Door | EdgeKind::Locked | EdgeKind::Hatch => WallEdge::Doorway,
            EdgeKind::Breach => WallEdge::Breached,
        };
        let layer = &mut layers[edge.cell.deck as usize];
        // Convert canonical (cell, dir) to the north/west storage convention.
        let (x, y, north) = match edge.direction {
            Dir::North => (edge.cell.x, edge.cell.y, true),
            Dir::West => (edge.cell.x, edge.cell.y, false),
            Dir::South => (edge.cell.x, edge.cell.y + 1, true),
            Dir::East => (edge.cell.x + 1, edge.cell.y, false),
        };
        if let Some(i) = layer.idx(x, y) {
            if north {
                layer.walls[i].north = wall;
            } else {
                layer.walls[i].west = wall;
            }
        }
    }
    layers
}
