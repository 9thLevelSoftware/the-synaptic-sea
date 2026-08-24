//! Stage 9: loot seeding. Each container rolls from the loot table of its
//! room type using an RNG stream keyed by its entity id — regeneration-
//! stable, and independent of every other container.

use crate::archetype::{GenData, LootEntry};
use crate::model::{DeckLayer, EntityKind, EntitySpec, ItemStack, RoomType, NO_ROOM};
use crate::rng::{self, roll_bp, roll_range, weighted_choice};
use crate::stages::story::DamageProfile;
use std::collections::BTreeMap;

#[allow(clippy::too_many_arguments)]
pub fn seed_loot(
    master_seed: u64,
    entities: &mut [EntitySpec],
    layers: &[DeckLayer],
    kind_of: &BTreeMap<u16, RoomType>,
    data: &GenData,
    profile: &DamageProfile,
    intactness: u16,
    loot_richness: u16,
) {
    // Effective richness: request knob x story multiplier x intactness decay
    // (badly damaged ships have had more destroyed/pilfered).
    let intact_mult = 5000 + intactness as i64 / 2; // 5000..=10000 bp
    let richness = loot_richness as i64 * profile.loot_mult_bp as i64 / 10_000 * intact_mult / 10_000;

    for e in entities.iter_mut() {
        if e.kind != EntityKind::Container {
            continue;
        }
        let mut rng = rng::stream(master_seed, "loot", e.id as u64);
        // Room type of the container's tile (debris-field crates: Cargo).
        let room_kind = layers
            .get(e.pos.deck as usize)
            .map(|l| l.room_at(e.pos.x, e.pos.y))
            .filter(|id| *id != NO_ROOM)
            .and_then(|id| kind_of.get(&id).copied())
            .unwrap_or(RoomType::Cargo);

        // Pirate boarding strips weapon lockers.
        if room_kind == RoomType::Armory && roll_bp(&mut rng, profile.weapon_empty_bp) {
            e.tags.push("ransacked".into());
            continue;
        }

        let Some(table) = data.loot.tables.get(&room_kind) else { continue };
        if table.is_empty() {
            continue;
        }
        let base_rolls = roll_range(&mut rng, data.loot.rolls.0 as i64, data.loot.rolls.1 as i64);
        let rolls = (base_rolls * richness / 10_000).clamp(0, 8);
        // Even at low richness, give a floor chance of one roll so ships
        // aren't universally empty.
        let rolls = if rolls == 0 && roll_bp(&mut rng, 3000) { 1 } else { rolls };
        let mut inv: Vec<ItemStack> = Vec::new();
        let weights: Vec<u32> = table.iter().map(|t: &LootEntry| t.weight).collect();
        for _ in 0..rolls {
            let Some(pick) = weighted_choice(&mut rng, &weights) else { break };
            let entry = &table[pick];
            let qty = roll_range(&mut rng, entry.qty.0 as i64, entry.qty.1 as i64) as u16;
            if qty == 0 {
                continue;
            }
            let item_id = data.items.id_of(&entry.item).expect("validated at load");
            match inv.iter_mut().find(|s| s.item_id == item_id) {
                Some(s) => s.qty = s.qty.saturating_add(qty),
                None => inv.push(ItemStack { item_id, qty }),
            }
        }
        inv.sort();
        e.inventory = inv;
    }
}
