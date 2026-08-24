//! Background generation machinery. A worker thread runs `generate_ship`
//! (pure Rust, `Send`-safe data only) and posts the result through an mpsc
//! channel; the main thread polls and converts to Godot types.

use derelict_core::model::{GenParams, Ship};
use derelict_core::GenData;
use std::collections::BTreeMap;
use std::sync::mpsc::{channel, Receiver};

pub enum GenResult {
    Ok(Box<Ship>),
    Err(String),
}

pub struct AsyncGen {
    next_request: i64,
    pending: BTreeMap<i64, Receiver<GenResult>>,
}

impl Default for AsyncGen {
    fn default() -> Self {
        Self {
            next_request: 1,
            pending: BTreeMap::new(),
        }
    }
}

impl AsyncGen {
    pub fn start(&mut self, seed: u64, params: GenParams, data: GenData) -> i64 {
        let id = self.next_request;
        self.next_request += 1;
        let (tx, rx) = channel();
        std::thread::spawn(move || {
            let result = match derelict_core::generate_ship(seed, &params, &data) {
                Ok(ship) => GenResult::Ok(Box::new(ship)),
                Err(e) => GenResult::Err(e.to_string()),
            };
            let _ = tx.send(result);
        });
        self.pending.insert(id, rx);
        id
    }

    /// Non-blocking poll; Some(result) exactly once when finished.
    pub fn poll(&mut self, request_id: i64) -> Option<GenResult> {
        let done = match self.pending.get(&request_id) {
            Some(rx) => rx.try_recv().ok(),
            None => return Some(GenResult::Err(format!("unknown request {request_id}"))),
        };
        if done.is_some() {
            self.pending.remove(&request_id);
        }
        done
    }
}
