//! Compatibility facade for legacy Godot methods, backed by the process service.
use crate::service::Service;
use derelict_core::lifecycle::LifecycleStatus;
use derelict_core::model::Ship;
use std::collections::BTreeMap;
use std::sync::Arc;

pub enum GenResult {
    Ok(Box<Ship>),
    Err(String),
}

#[derive(Default)]
pub struct AsyncGen {
    pending: BTreeMap<i64, ()>,
}

impl AsyncGen {
    pub fn start(
        &mut self,
        request: derelict_core::procgen::ProcgenRequest,
        service: &Arc<Service>,
    ) -> i64 {
        let id = service.submit(request).request_id.unwrap_or(-1);
        if id > 0 {
            self.pending.insert(id, ());
        }
        id
    }
    pub fn poll(&mut self, id: i64, service: &Arc<Service>) -> Option<GenResult> {
        if !self.pending.contains_key(&id) {
            return None;
        }
        let result = service.poll(id);
        match result.status {
            LifecycleStatus::Completed => {
                self.pending.remove(&id);
                Some(GenResult::Ok(Box::new(result.bundle?.site_ir.ship)))
            }
            LifecycleStatus::Failed => {
                self.pending.remove(&id);
                Some(GenResult::Err(result.failure?.message))
            }
            _ => None,
        }
    }
}
