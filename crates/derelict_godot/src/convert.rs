//! Rust `Ship` -> Godot `VarDictionary` marshalling. GDScript never parses
//! binary: bulk tile layers travel as PackedInt32Array (one per layer), and
//! small structured data (entities, rooms, events) as arrays of dictionaries.

use derelict_core::model::{
    CauseOfLoss, DamageEventKind, EdgeKind, EntityKind, GenParams, RoomType, Ship,
};
use godot::builtin::{PackedInt32Array, PackedStringArray, VarArray, VarDictionary};
use godot::meta::ToGodot;

pub fn ship_to_dictionary(ship: &Ship) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("generator_version", ship.generator_version as i64);
    d.set("seed", ship.seed as i64);
    d.set("archetype_id", ship.archetype_id.as_str());
    d.set("intactness", ship.intactness as i64);
    d.set("cause_of_loss", cause_name(ship.cause_of_loss));
    d.set("fractured", ship.fractured);

    let mut decks = VarArray::new();
    for deck in &ship.decks {
        let l = &deck.layer;
        let mut dd = VarDictionary::new();
        dd.set("width", l.width as i64);
        dd.set("height", l.height as i64);
        dd.set(
            "floor",
            &PackedInt32Array::from_iter(l.floor.iter().map(|f| *f as i32)),
        );
        dd.set(
            "wall_north",
            &PackedInt32Array::from_iter(l.walls.iter().map(|w| w.north as i32)),
        );
        dd.set(
            "wall_west",
            &PackedInt32Array::from_iter(l.walls.iter().map(|w| w.west as i32)),
        );
        dd.set(
            "room_id",
            &PackedInt32Array::from_iter(l.room_id.iter().map(|r| *r as i32)),
        );
        dd.set(
            "decal",
            &PackedInt32Array::from_iter(l.decal.iter().map(|v| *v as i32)),
        );
        decks.push(&dd.to_variant());
    }
    d.set("decks", &decks);

    let mut rooms = VarArray::new();
    for n in &ship.room_graph.nodes {
        let mut rd = VarDictionary::new();
        rd.set("id", n.id as i64);
        rd.set("deck", n.deck as i64);
        rd.set("kind", room_name(n.kind));
        rd.set("min_x", n.min.0 as i64);
        rd.set("min_y", n.min.1 as i64);
        rd.set("max_x", n.max.0 as i64);
        rd.set("max_y", n.max.1 as i64);
        rd.set("tile_count", n.tile_count as i64);
        rd.set("depressurized", n.depressurized);
        rooms.push(&rd.to_variant());
    }
    d.set("rooms", &rooms);

    let mut edges = VarArray::new();
    for e in &ship.room_graph.edges {
        let mut ed = VarDictionary::new();
        ed.set("a", e.a as i64);
        ed.set("b", e.b as i64);
        ed.set(
            "kind",
            match e.kind {
                EdgeKind::Door => "door",
                EdgeKind::OpenCorridor => "open",
                EdgeKind::VerticalShaft => "shaft",
                EdgeKind::Breach => "breach",
            },
        );
        edges.push(&ed.to_variant());
    }
    d.set("edges", &edges);

    let mut entities = VarArray::new();
    for e in &ship.entities {
        let mut ed = VarDictionary::new();
        ed.set("id", e.id as i64);
        ed.set("kind", entity_kind_name(e.kind));
        ed.set("proto", e.proto.as_str());
        ed.set("x", e.pos.x as i64);
        ed.set("y", e.pos.y as i64);
        ed.set("deck", e.pos.deck as i64);
        ed.set("rotation", e.rotation as i64);
        ed.set("locked", e.locked);
        ed.set("open", e.open);
        // Inventory as flat [item_id, qty, item_id, qty, ...].
        let mut inv = PackedInt32Array::new();
        for s in &e.inventory {
            inv.push(s.item_id as i32);
            inv.push(s.qty as i32);
        }
        ed.set("inventory", &inv);
        ed.set(
            "tags",
            &PackedStringArray::from_iter(e.tags.iter().map(|t| t.into())),
        );
        entities.push(&ed.to_variant());
    }
    d.set("entities", &entities);

    let mut events = VarArray::new();
    for ev in &ship.damage_events {
        let mut ed = VarDictionary::new();
        ed.set(
            "kind",
            match ev.kind {
                DamageEventKind::Breach => "breach",
                DamageEventKind::ScorchZone => "scorch",
                DamageEventKind::StructuralFracture => "fracture",
                DamageEventKind::DebrisField => "debris_field",
            },
        );
        ed.set("deck", ev.deck as i64);
        ed.set("x", ev.origin.0 as i64);
        ed.set("y", ev.origin.1 as i64);
        ed.set("radius", ev.radius as i64);
        events.push(&ed.to_variant());
    }
    d.set("damage_events", &events);

    let mut fragments = VarArray::new();
    for f in &ship.fragments {
        let mut fd = VarDictionary::new();
        fd.set("id", f.id as i64);
        fd.set("drift_x", f.drift.0 as i64);
        fd.set("drift_y", f.drift.1 as i64);
        fd.set(
            "rooms",
            &PackedInt32Array::from_iter(f.rooms.iter().map(|r| *r as i32)),
        );
        fragments.push(&fd.to_variant());
    }
    d.set("fragments", &fragments);
    d
}

pub fn gen_params_from_dict(dict: &VarDictionary) -> GenParams {
    let archetype_id = dict
        .get("archetype_id")
        .map(|v| v.to_string())
        .unwrap_or_else(|| "corvette".to_string());
    let mut params = GenParams::new(&archetype_id);
    if let Some(v) = dict.get("intactness_override") {
        let bp = v.try_to::<i64>().unwrap_or(-1);
        if (0..=10_000).contains(&bp) {
            params.intactness_override = Some(bp as u16);
        }
    }
    if let Some(v) = dict.get("cause_override") {
        params.cause_override = cause_from_name(&v.to_string());
    }
    if let Some(v) = dict.get("loot_richness") {
        let bp = v.try_to::<i64>().unwrap_or(10_000).clamp(0, 30_000);
        params.loot_richness = bp as u16;
    }
    params
}

fn cause_name(c: CauseOfLoss) -> &'static str {
    match c {
        CauseOfLoss::ReactorBreach => "reactor_breach",
        CauseOfLoss::Depressurization => "depressurization",
        CauseOfLoss::PirateBoarding => "pirate_boarding",
        CauseOfLoss::Plague => "plague",
        CauseOfLoss::DriveMisjump => "drive_misjump",
        CauseOfLoss::Unknown => "unknown",
    }
}

fn cause_from_name(s: &str) -> Option<CauseOfLoss> {
    Some(match s {
        "reactor_breach" => CauseOfLoss::ReactorBreach,
        "depressurization" => CauseOfLoss::Depressurization,
        "pirate_boarding" => CauseOfLoss::PirateBoarding,
        "plague" => CauseOfLoss::Plague,
        "drive_misjump" => CauseOfLoss::DriveMisjump,
        "unknown" => CauseOfLoss::Unknown,
        _ => return None,
    })
}

fn room_name(k: RoomType) -> &'static str {
    match k {
        RoomType::Bridge => "bridge",
        RoomType::Engineering => "engineering",
        RoomType::Reactor => "reactor",
        RoomType::CrewQuarters => "crew_quarters",
        RoomType::Cargo => "cargo",
        RoomType::Medbay => "medbay",
        RoomType::Galley => "galley",
        RoomType::Armory => "armory",
        RoomType::Storage => "storage",
        RoomType::Hydroponics => "hydroponics",
        RoomType::Airlock => "airlock",
        RoomType::Corridor => "corridor",
        RoomType::VerticalShaft => "vertical_shaft",
        RoomType::Compartment => "compartment",
    }
}

fn entity_kind_name(k: EntityKind) -> &'static str {
    match k {
        EntityKind::Door => "door",
        EntityKind::Container => "container",
        EntityKind::Terminal => "terminal",
        EntityKind::Furniture => "furniture",
        EntityKind::Debris => "debris",
        EntityKind::Body => "body",
        EntityKind::ItemPile => "item_pile",
    }
}
