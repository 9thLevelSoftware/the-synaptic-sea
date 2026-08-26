use derelict_core::item_generation::*;
use derelict_core::world::{WorldGenerationRequest, PROCGEN_GENERATOR_VERSION};

fn context() -> ItemGenerationContext {
    ItemGenerationContext {
        request: WorldGenerationRequest {
            world_seed: 17,
            platform_version: PROCGEN_GENERATOR_VERSION,
            content_manifest_hash: "a".repeat(64),
            site_id: "site:alpha".into(),
            x: 3,
            y: -2,
            archetype_id: "shuttle".into(),
        },
        difficulty_id: "difficulty:normal".into(),
        loot_richness_bp: 0,
        eligible_sources: (0..8)
            .map(|i| SourceBinding {
                source_id: format!("container:{i:02}"),
                source_kind: SourceKind::Container,
            })
            .collect(),
        max_total_value: 10_000,
        max_count: 8,
    }
}

fn catalogue() -> ItemCatalogue {
    let catalogue = ItemCatalogue::bundled().unwrap();
    catalogue.validate().unwrap();
    catalogue
}

fn generated(richness: u32) -> (ItemGenerationContext, ItemCatalogue, ItemGenerationOutcome) {
    let mut context = context();
    context.loot_richness_bp = richness;
    let catalogue = catalogue();
    let outcome = generate_items(&context, &catalogue).unwrap();
    (context, catalogue, outcome)
}

#[test]
fn bundled_catalogue_is_valid_and_closed() {
    let catalogue = catalogue();
    let json = serde_json::to_string(&catalogue).unwrap();
    let round_trip: ItemCatalogue = serde_json::from_str(&json).unwrap();
    assert_eq!(catalogue, round_trip);

    let mut object: serde_json::Value = serde_json::from_str(&json).unwrap();
    object["extra"] = serde_json::json!(true);
    assert!(serde_json::from_value::<ItemCatalogue>(object).is_err());
}

#[test]
fn deterministic_identity_is_stable() {
    let (context, catalogue, first) = generated(5_000);
    let second = generate_items(&context, &catalogue).unwrap();
    assert_eq!(first, second);
    assert_eq!(
        serde_json::to_vec(&first).unwrap(),
        serde_json::to_vec(&second).unwrap()
    );
}

#[test]
fn loot_richness_is_monotonic_and_preserves_prefix() {
    let (_, _, low) = generated(0);
    let (_, _, medium) = generated(15_000);
    let (_, _, high) = generated(30_000);
    assert!(low.items.len() <= medium.items.len());
    assert!(medium.items.len() <= high.items.len());
    assert_eq!(
        &low.items[..low.items.len()],
        &medium.items[..low.items.len()]
    );
    assert_eq!(
        &medium.items[..medium.items.len()],
        &high.items[..medium.items.len()]
    );
    let low_value: u32 = low.items.iter().map(|item| item.economy_value).sum();
    let medium_value: u32 = medium.items.iter().map(|item| item.economy_value).sum();
    let high_value: u32 = high.items.iter().map(|item| item.economy_value).sum();
    assert!(low_value <= medium_value && medium_value <= high_value);
}

#[test]
fn site_level_loot_richness_bounds_are_supported_exactly() {
    let (context, catalogue, outcome) = generated(30_000);
    outcome.validate(&context, &catalogue).unwrap();
    let mut invalid = context;
    invalid.loot_richness_bp = 30_001;
    assert!(generate_items(&invalid, &catalogue).is_err());
}

#[test]
fn generated_output_obeys_budget_economy_and_trace_bounds() {
    let (context, catalogue, outcome) = generated(10_000);
    outcome.validate(&context, &catalogue).unwrap();
    assert!(outcome.items.len() <= MAX_ITEMS);
    assert!(outcome.trace.considered.len() <= 128);
    assert!(outcome.trace.repairs.len() <= 2);
    assert!(outcome.trace.fallback.is_none());
    assert_eq!(outcome.trace.selected.len(), outcome.items.len());
    assert_eq!(outcome.trace.selected[0], outcome.items[0].id);
    assert!(outcome
        .drops
        .iter()
        .all(|drop| drop.frequency_bp <= catalogue.caps.max_drop_frequency_bp));
}

#[test]
fn generated_items_are_typed_compatible_with_authored_catalogue() {
    let (_, catalogue, outcome) = generated(7_500);
    for item in &outcome.items {
        let family = catalogue
            .families
            .iter()
            .find(|family| family.id == item.family_id)
            .unwrap();
        let socket = catalogue
            .sockets
            .iter()
            .find(|socket| socket.id == item.socket_id)
            .unwrap();
        let rarity = catalogue
            .rarities
            .iter()
            .find(|rarity| rarity.id == item.rarity_id)
            .unwrap();
        assert!(socket.family_ids.contains(&family.id));
        assert!(item.affixes.len() <= socket.max_affixes as usize);
        assert!(item.affixes.len() <= rarity.max_affixes as usize);
        assert_eq!(item.visual_tag, family.visual_tag);
        for roll in &item.affixes {
            let definition = catalogue
                .affixes
                .iter()
                .find(|affix| affix.id == roll.affix_id)
                .unwrap();
            assert_eq!(definition.socket_kind, socket.kind);
            assert_eq!(definition.stat, roll.stat);
            assert!((definition.min_value..=definition.max_value).contains(&roll.value));
        }
    }
}

#[test]
fn low_total_value_uses_complete_authored_fallback() {
    let mut context = context();
    context.max_total_value = 30;
    let catalogue = catalogue();
    let outcome = generate_items(&context, &catalogue).unwrap();
    assert_eq!(outcome.trace.fallback.as_deref(), Some("authored_baseline"));
    assert_eq!(outcome.items[0].id, catalogue.fallback.id);
    assert!(outcome
        .trace
        .considered
        .iter()
        .any(|decision| !decision.accepted && decision.rationale == "rejected_economy_cap"));
    outcome.validate(&context, &catalogue).unwrap();
}

#[test]
fn catalogue_rejects_incompatible_family_socket_kind() {
    let mut catalogue = catalogue();
    catalogue.families[0].socket_kinds = vec![SocketKind::Utility];
    assert!(matches!(
        catalogue.validate(),
        Err(ItemError::Invalid("family_socket_kind"))
    ));
}

#[test]
fn catalogue_rejects_socket_without_compatible_affix() {
    let mut catalogue = catalogue();
    catalogue
        .affixes
        .retain(|affix| affix.socket_kind != SocketKind::Defense);
    assert!(matches!(
        catalogue.validate(),
        Err(ItemError::Invalid("socket_affixes"))
    ));
}

#[test]
fn arithmetic_overflow_fails_closed_to_validated_fallback() {
    let mut catalogue = catalogue();
    for affix in &mut catalogue.affixes {
        affix.cost_per_value = u32::MAX;
    }
    let context = context();
    let outcome = generate_items(&context, &catalogue).unwrap();
    outcome.validate(&context, &catalogue).unwrap();
    assert_eq!(outcome.trace.fallback.as_deref(), Some("authored_baseline"));
    assert!(outcome
        .trace
        .considered
        .iter()
        .any(|decision| decision.rationale == "rejected_arithmetic_overflow"));
}

#[test]
fn invalid_or_over_budget_fallback_is_rejected() {
    let mut invalid_fallback = catalogue();
    invalid_fallback.fallback.base_value = invalid_fallback.caps.max_per_item_value + 1;
    assert!(invalid_fallback.validate().is_err());

    let mut over_budget_rarity = catalogue();
    over_budget_rarity.rarities[0].min_budget = 1;
    assert!(over_budget_rarity.validate().is_err());
}

#[test]
fn invalid_context_and_malformed_authored_data_fail_closed() {
    let catalogue = catalogue();
    let mut invalid_context = context();
    invalid_context.request.platform_version = PROCGEN_GENERATOR_VERSION - 1;
    assert!(generate_items(&invalid_context, &catalogue).is_err());

    let mut duplicate_source_context = context();
    duplicate_source_context.eligible_sources[1].source_id = duplicate_source_context
        .eligible_sources[0]
        .source_id
        .clone();
    assert!(generate_items(&duplicate_source_context, &catalogue).is_err());

    let mut malformed = catalogue.clone();
    malformed.families[0].base_value = 0;
    assert!(malformed.validate().is_err());
    let mut unknown: serde_json::Value = serde_json::to_value(catalogue).unwrap();
    unknown["families"][0]["unexpected"] = serde_json::json!(1);
    assert!(serde_json::from_value::<ItemCatalogue>(unknown).is_err());
}

#[test]
fn source_pool_uses_adapter_bound_while_generated_output_stays_capped() {
    let catalogue = catalogue();
    let mut bounded = context();
    bounded.eligible_sources = (0..MAX_SOURCES)
        .map(|index| SourceBinding {
            source_id: format!("container:{index:04}"),
            source_kind: SourceKind::Container,
        })
        .collect();
    bounded.max_count = MAX_ITEMS as u16;
    let outcome = generate_items(&bounded, &catalogue).unwrap();
    assert!(outcome.items.len() <= MAX_ITEMS);

    bounded.eligible_sources.push(SourceBinding {
        source_id: format!("container:{MAX_SOURCES:04}"),
        source_kind: SourceKind::Container,
    });
    assert!(generate_items(&bounded, &catalogue).is_err());
}

#[test]
fn drop_bindings_are_unique_and_match_items() {
    let (_, _, outcome) = generated(10_000);
    let source_ids: std::collections::BTreeSet<_> =
        outcome.drops.iter().map(|drop| &drop.source_id).collect();
    assert_eq!(source_ids.len(), outcome.drops.len());
    for (item, drop) in outcome.items.iter().zip(&outcome.drops) {
        assert_eq!(item.id, drop.item_id);
    }
}

#[test]
fn closed_enums_reject_unknown_values() {
    assert!(serde_json::from_str::<SocketKind>("\"unknown\"").is_err());
    assert!(serde_json::from_str::<StatKind>("\"unknown\"").is_err());
    assert!(serde_json::from_str::<SourceKind>("\"unknown\"").is_err());
}

#[test]
fn no_existing_drop_source_exports_complete_safe_empty_outcome() {
    let mut context = context();
    context.eligible_sources.clear();
    context.max_count = 0;
    let catalogue = catalogue();
    let outcome = generate_items(&context, &catalogue).unwrap();
    assert!(outcome.items.is_empty());
    assert!(outcome.drops.is_empty());
    assert!(outcome.trace.selected.is_empty());
    assert_eq!(
        outcome.trace.fallback.as_deref(),
        Some("authored_safe_empty")
    );
    outcome.validate(&context, &catalogue).unwrap();
}
