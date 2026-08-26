use derelict_core::creature::*;
use derelict_core::world::WorldGenerationRequest;

fn context() -> CreatureGenerationContext { CreatureGenerationContext { request: WorldGenerationRequest { world_seed: 7, platform_version: 3, content_manifest_hash: "a".repeat(64), site_id: "site".into(), x: 2, y: -3, archetype_id: "shuttle".into() }, min_clearance: 1, max_footprint_cells: 8, threat_cap: 1_000, performance_cap: 1_000, instance_cap: 32 } }
fn catalogue() -> CreatureCatalogue { let c = CreatureCatalogue::bundled().unwrap(); c.validate().unwrap(); c }

#[test] fn bundled_catalogue_is_valid() { catalogue(); }
#[test] fn nested_unknown_fields_are_closed() { let c = catalogue(); let mut s=serde_json::to_string(&c).unwrap(); s.insert(s.len()-1, ','); s.push_str("\"extra\":1}"); assert!(serde_json::from_str::<CreatureCatalogue>(&s).is_err()); }
#[test] fn all_authored_families_generate() { let c=catalogue(); let o=c.generate(&context()).unwrap(); assert!(c.fallbacks.iter().any(|x| x.id==o.blueprint.id)); }
#[test] fn deterministic_identity() { let c=catalogue(); assert_eq!(c.generate(&context()).unwrap(), c.generate(&context()).unwrap()); }
#[test] fn coordinate_changes_identity() { let c=catalogue(); let mut x=context(); x.request.x+=1; assert_ne!(c.generate(&context()).unwrap().trace.considered, c.generate(&x).unwrap().trace.considered); }
#[test] fn content_changes_identity() { let c=catalogue(); let mut x=context(); x.request.content_manifest_hash="b".repeat(64); assert_ne!(c.generate(&context()).unwrap().trace.considered, c.generate(&x).unwrap().trace.considered); }
#[test] fn permutation_is_canonical() { let mut c=catalogue(); c.fallbacks.reverse(); assert!(c.validate().is_err()); }
#[test] fn disconnected_footprint_rejected() { let mut c=catalogue(); c.footprints[0].cells.push(Cell{x:9,y:9}); assert!(c.validate().is_err()); }
#[test] fn clearance_is_enforced() { let c=catalogue(); let mut x=context(); x.min_clearance=3; assert!(c.generate(&x).is_err()); }
#[test] fn footprint_cap_is_enforced() { let c=catalogue(); let mut x=context(); x.max_footprint_cells=0; assert!(c.generate(&x).is_err()); }
#[test] fn threat_cap_is_enforced() { let c=catalogue(); let mut x=context(); x.threat_cap=1; assert!(c.generate(&x).is_err()); }
#[test] fn performance_cap_is_enforced() { let c=catalogue(); let mut x=context(); x.performance_cap=1; assert!(c.generate(&x).is_err()); }
#[test] fn entity_cap_is_enforced() { let c=catalogue(); let mut x=context(); x.instance_cap=1; assert!(c.generate(&x).is_err()); }
#[test] fn dangling_ability_rejected() { let mut c=catalogue(); c.fallbacks[0].ability_id="missing".into(); assert!(c.validate().is_err()); }
#[test] fn mismatch_rig_rejected() { let c=catalogue(); let mut b=c.fallbacks[0].clone(); b.rig_id="rig_drone".into(); assert!(c.validate_blueprint(&b,&context()).is_err()); }
#[test] fn mismatch_counterplay_rejected() { let c=catalogue(); let mut b=c.fallbacks[0].clone(); b.counterplay_id="counter_evade".into(); assert!(c.validate_blueprint(&b,&context()).is_err()); }
#[test] fn fallback_trace_is_bounded() { let c=catalogue(); let o=c.generate(&context()).unwrap(); assert!(o.trace.considered.len()<=MAX_CANDIDATES); assert!(o.trace.repairs.len()<=1); }
#[test] fn closed_enum_rejects_unknown() { assert!(serde_json::from_str::<ThreatRole>("\"unknown\"").is_err()); }
