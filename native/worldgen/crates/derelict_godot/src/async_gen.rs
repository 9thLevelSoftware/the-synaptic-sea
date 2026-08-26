//! Compatibility facade for legacy Godot methods, backed by the bounded service.
use crate::service::{Limits, Service, SystemClock};
use derelict_core::lifecycle::LifecycleStatus;
use derelict_core::model::{GenParams, Ship};
use derelict_core::procgen::{
    Domain, PlayerModel, PresentationRequest, ProcgenRequest, SiteRequest,
};
use derelict_core::GenData;
use std::collections::BTreeMap;
use std::sync::Arc;
pub enum GenResult {
    Ok(Box<Ship>),
    Err(String),
}
#[derive(Default)]
pub struct AsyncGen {
    service: Option<Arc<Service>>,
    pending: BTreeMap<i64, ()>,
}
impl AsyncGen {
    pub fn start(&mut self, seed: u64, params: GenParams, data: GenData) -> i64 {
        let service = self
            .service
            .get_or_insert_with(|| {
                let d = data.clone();
                Service::new(
                    Limits::default(),
                    Arc::new(SystemClock::default()),
                    "0".repeat(64),
                    Arc::new(move |r| derelict_core::procgen::generate_bundle(r, &d)),
                )
            })
            .clone();
        let request = ProcgenRequest {
            schema_version: "procgen-request-1".into(),
            world_seed: seed,
            site: SiteRequest {
                site_id: "legacy".into(),
                x: 0,
                y: 0,
                archetype_id: params.archetype_id,
                kit_id: "legacy".into(),
                intactness_override_bp: params.intactness_override,
                cause_of_loss: params.cause_override,
                loot_richness_bp: params.loot_richness,
            },
            difficulty_id: "legacy".into(),
            player_model: PlayerModel {
                schema_version: "player-model-1".into(),
                signals: Vec::new(),
            },
            requested_domains: vec![
                Domain::World,
                Domain::Site,
                Domain::Gameplay,
                Domain::Presentation,
            ],
            generator_version: derelict_core::GENERATOR_VERSION,
            content_manifest_hash: "0".repeat(64),
            presentation: PresentationRequest {
                seed,
                locale: "en".into(),
            },
        };
        let id = service.submit(request).request_id.unwrap_or(-1);
        self.pending.insert(id, ());
        id
    }
    pub fn poll(&mut self, id: i64) -> Option<GenResult> {
        let service = self.service.as_ref()?;
        let r = service.poll(id);
        match r.status {
            LifecycleStatus::Completed => {
                self.pending.remove(&id);
                Some(GenResult::Ok(Box::new(r.bundle.unwrap().site_ir.ship)))
            }
            LifecycleStatus::Failed => {
                self.pending.remove(&id);
                Some(GenResult::Err(r.failure.unwrap().message))
            }
            _ => None,
        }
    }
}
