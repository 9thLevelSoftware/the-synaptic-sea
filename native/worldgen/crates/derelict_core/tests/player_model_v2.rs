use derelict_core::player_model::{
    PlayerModelV2, PlayerSignal, PlayerSignalKind, PLAYER_MODEL_SCHEMA_V2,
};

fn signal(kind: PlayerSignalKind, value_bp: u16) -> PlayerSignal {
    PlayerSignal { kind, value_bp }
}

#[test]
fn empty_snapshot_uses_authored_baseline() {
    let model = PlayerModelV2 {
        schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
        signals: Vec::new(),
    };
    model.validate().unwrap();
    for kind in PlayerSignalKind::ALL {
        assert_eq!(model.signal_bp(kind), 5_000);
    }
}

#[test]
fn complete_snapshot_is_closed_bounded_and_canonical() {
    let model = PlayerModelV2 {
        schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
        signals: vec![
            signal(PlayerSignalKind::CombatMastery, 1_000),
            signal(PlayerSignalKind::DamagePressure, 2_000),
            signal(PlayerSignalKind::ResourcePressure, 3_000),
            signal(PlayerSignalKind::ObjectivePace, 4_000),
        ],
    };
    model.validate().unwrap();
    assert_eq!(model.normalized_values(), [1_000, 2_000, 3_000, 4_000]);

    let json = serde_json::to_string(&model).unwrap();
    assert_eq!(PlayerModelV2::from_json(&json).unwrap(), model);
    let mut value: serde_json::Value = serde_json::from_str(&json).unwrap();
    value["account_id"] = "forbidden".into();
    assert!(PlayerModelV2::from_json(&value.to_string()).is_err());
}

#[test]
fn malformed_schema_order_duplicates_and_bounds_fail_closed() {
    let valid = || PlayerModelV2 {
        schema_version: PLAYER_MODEL_SCHEMA_V2.into(),
        signals: vec![
            signal(PlayerSignalKind::CombatMastery, 1_000),
            signal(PlayerSignalKind::DamagePressure, 2_000),
        ],
    };

    let mut wrong_schema = valid();
    wrong_schema.schema_version = "player-model-1".into();
    assert!(wrong_schema.validate().is_err());

    let mut reversed = valid();
    reversed.signals.reverse();
    assert!(reversed.validate().is_err());

    let mut duplicate = valid();
    duplicate.signals[1].kind = PlayerSignalKind::CombatMastery;
    assert!(duplicate.validate().is_err());

    let mut out_of_bounds = valid();
    out_of_bounds.signals[0].value_bp = 10_001;
    assert!(out_of_bounds.validate().is_err());

    let unknown_kind = r#"{"schema_version":"player-model-2","signals":[{"kind":"account_history","value_bp":1}]}"#;
    assert!(PlayerModelV2::from_json(unknown_kind).is_err());
}
