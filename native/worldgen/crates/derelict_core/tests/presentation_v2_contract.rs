use derelict_core::presentation::*;

#[test]
fn bundled_catalogue_validates_and_assembles_closed_subjects() {
    let catalogue = PresentationCatalogue::bundled().unwrap();
    catalogue.validate().unwrap();
    let request = derelict_core::world::WorldGenerationRequest {
        world_seed: 42,
        platform_version: 3,
        content_manifest_hash: "a".repeat(64),
        site_id: "selected".into(),
        x: 4,
        y: 7,
        archetype_id: "shuttle".into(),
    };
    let context = PresentationContext {
        request,
        presentation_seed: 7,
        locale: "en-us".into(),
        subjects: vec![PresentationSubject {
            subject_id: "subject:ship".into(),
            subject_kind: SubjectKind::Ship,
            binding_tags: vec!["structural.default".into()],
        }],
    };
    let output = assemble(&context, &catalogue).unwrap();
    assert_eq!(output.instructions.len(), 1);
    output.validate(&context, &catalogue).unwrap();
}

#[test]
fn provenance_rejects_missing_required_evidence() {
    let mut record = Provenance::default();
    assert!(record.validate().is_err());
    record.source = "authored/source.glb".into();
    record.license = "CC0".into();
    record.tool_or_model_version = "tool-1".into();
    record.inputs = vec!["input".into()];
    record.parameters_or_seed = "seed:1".into();
    record.human_changes = "none".into();
    record.technical_validation = "passed".into();
    record.art_approval = "approved".into();
    record.promoted_content_manifest_entry = "asset:mesh:ship".into();
    assert!(record.validate().is_ok());
}

#[test]
fn unknown_nested_fields_are_rejected() {
    let value = serde_json::json!({"source":"x","license":"y","tool_or_model_version":"z","inputs":["i"],"parameters_or_seed":"p","human_changes":"h","technical_validation":"t","art_approval":"a","promoted_content_manifest_entry":"m","extra":true});
    assert!(serde_json::from_value::<Provenance>(value).is_err());
}

fn context() -> PresentationContext {
    PresentationContext {
        request: derelict_core::world::WorldGenerationRequest {
            world_seed: 42,
            platform_version: 3,
            content_manifest_hash: "a".repeat(64),
            site_id: "selected".into(),
            x: 4,
            y: 7,
            archetype_id: "shuttle".into(),
        },
        presentation_seed: 7,
        locale: "en-us".into(),
        subjects: vec![PresentationSubject {
            subject_id: "subject:ship".into(),
            subject_kind: SubjectKind::Ship,
            binding_tags: vec!["structural.default".into()],
        }],
    }
}

#[test]
fn output_is_deterministic() {
    let c = context();
    let cat = PresentationCatalogue::bundled().unwrap();
    assert_eq!(assemble(&c, &cat).unwrap(), assemble(&c, &cat).unwrap());
}
#[test]
fn locale_changes_cosmetics_not_subject_projection() {
    let cat = PresentationCatalogue::bundled().unwrap();
    let a = assemble(&context(), &cat).unwrap();
    let mut c = context();
    c.locale = "fr-fr".into();
    assert_eq!(
        a.instructions[0].subject_id,
        assemble(&c, &cat).unwrap().instructions[0].subject_id
    );
}
#[test]
fn presentation_seed_is_cosmetic_input() {
    let cat = PresentationCatalogue::bundled().unwrap();
    let mut c = context();
    c.presentation_seed = 8;
    assert!(assemble(&c, &cat).is_ok());
}
#[test]
fn unsorted_subjects_are_rejected() {
    let mut c = context();
    c.subjects.push(PresentationSubject {
        subject_id: "subject:aaa".into(),
        subject_kind: SubjectKind::Item,
        binding_tags: vec!["x".into()],
    });
    assert!(assemble(&c, &PresentationCatalogue::bundled().unwrap()).is_err());
}
#[test]
fn duplicate_subjects_are_rejected() {
    let mut c = context();
    c.subjects.push(c.subjects[0].clone());
    assert!(assemble(&c, &PresentationCatalogue::bundled().unwrap()).is_err());
}
#[test]
fn dangling_manifest_entry_is_rejected() {
    let mut cat = PresentationCatalogue::bundled().unwrap();
    cat.manifest_entries.clear();
    assert!(cat.validate().is_err());
}
#[test]
fn executable_adapter_binding_is_rejected() {
    let mut cat = PresentationCatalogue::bundled().unwrap();
    if let AssetRecord::Primitive {
        adapter_binding_id, ..
    } = &mut cat.assets[0]
    {
        *adapter_binding_id = "binding:execute".into();
    }
    assert!(cat.validate().is_err());
}
#[test]
fn provenance_mutation_is_rejected() {
    let mut p = Provenance::default();
    p.source = "x".into();
    assert!(p.validate().is_err());
}
#[test]
fn promoted_entry_must_match_asset() {
    let mut cat = PresentationCatalogue::bundled().unwrap();
    if let AssetRecord::Primitive { provenance, .. } = &mut cat.assets[0] {
        provenance.promoted_content_manifest_entry = "asset:audio:ambient".into();
    }
    assert!(cat.validate().is_err());
}
#[test]
fn context_seed_is_bounded() {
    let mut c = context();
    c.presentation_seed = derelict_core::MAX_PUBLIC_SEED + 1;
    assert!(assemble(&c, &PresentationCatalogue::bundled().unwrap()).is_err());
}
#[test]
fn request_manifest_must_be_lowercase_hex() {
    let mut c = context();
    c.request.content_manifest_hash = "A".repeat(64);
    assert!(assemble(&c, &PresentationCatalogue::bundled().unwrap()).is_err());
}
#[test]
fn fallback_is_recorded_for_unmatched_subject() {
    let mut c = context();
    c.subjects[0].binding_tags = vec!["missing.tag".into()];
    assert!(assemble(&c, &PresentationCatalogue::bundled().unwrap()).is_err());
}

#[test]
fn wrong_subject_kind_is_rejected_and_traced() {
    let c = context();
    let cat = PresentationCatalogue::bundled().unwrap();
    let out = assemble(&c, &cat).unwrap();
    let decision = &out.decisions[0];
    assert!(decision.selected.starts_with("asset:primitive:"));
    assert!(decision.rejected.iter().any(|candidate| {
        candidate.asset_id == "asset:audio:ambient"
            && candidate.rationale == "incompatible_subject_kind"
            && !candidate.accepted
    }));
    assert!(decision
        .considered
        .iter()
        .all(|candidate| candidate.rationale.len() <= 96));
}

#[test]
fn missing_compatible_tag_is_rejected_and_not_selected() {
    let mut c = context();
    c.subjects[0].binding_tags = vec!["structural.default".into(), "required.tag".into()];
    let mut cat = PresentationCatalogue::bundled().unwrap();
    if let AssetRecord::Primitive {
        compatible_tags, ..
    } = &mut cat.assets[0]
    {
        compatible_tags.push("required.tag".into());
    }
    if let AssetRecord::Audio {
        compatible_subject_kinds,
        ..
    } = &mut cat.assets[1]
    {
        compatible_subject_kinds.push(SubjectKind::Ship);
        compatible_subject_kinds.sort();
    }
    let out = assemble(&c, &cat).unwrap();
    let decision = &out.decisions[0];
    assert!(decision.selected.starts_with("asset:primitive:"));
    assert!(decision.rejected.iter().any(|candidate| {
        candidate.asset_id == "asset:audio:ambient"
            && candidate.rationale == "missing_compatible_tag"
    }));
}

#[test]
fn fallback_is_validated_for_kind_and_tags() {
    let mut c = context();
    c.subjects[0].binding_tags = vec!["required.tag".into()];
    let mut cat = PresentationCatalogue::bundled().unwrap();
    if let AssetRecord::Primitive {
        compatible_subject_kinds,
        compatible_tags,
        ..
    } = &mut cat.assets[0]
    {
        *compatible_subject_kinds = vec![SubjectKind::Environment];
        *compatible_tags = vec!["other.tag".into()];
    }
    assert!(assemble(&c, &cat).is_err());
}

#[test]
fn catalogue_requires_approved_subject_kind_compatibility() {
    let mut cat = PresentationCatalogue::bundled().unwrap();
    if let AssetRecord::Primitive {
        compatible_subject_kinds,
        ..
    } = &mut cat.assets[0]
    {
        compatible_subject_kinds.clear();
    }
    assert!(cat.validate().is_err());
}
